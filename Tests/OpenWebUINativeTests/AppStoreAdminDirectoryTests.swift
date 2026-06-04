import XCTest
@testable import OpenWebUINative

@MainActor
final class AppStoreAdminDirectoryTests: XCTestCase {
    func testCreateUserPersistsAndReloads() async throws {
        let fixture = try AdminDirectoryFixture()
        let store = fixture.makeStore()
        await store.load()

        await store.createAdminUser(name: "Ada Lovelace", email: "ada@example.com", role: .user)

        XCTAssertEqual(store.adminUsers.map(\.email), ["ada@example.com"])
        XCTAssertEqual(store.adminUsers.first?.name, "Ada Lovelace")
        XCTAssertEqual(store.adminUsers.first?.role, .user)

        let reloadedStore = fixture.makeStore()
        await reloadedStore.load()

        XCTAssertEqual(reloadedStore.adminUsers.map(\.email), ["ada@example.com"])
        XCTAssertEqual(reloadedStore.adminUsers.first?.role, .user)
    }

    func testCreateUserCreatesAuditEvent() async throws {
        let fixture = try AdminDirectoryFixture()
        let store = fixture.makeStore()
        await store.load()

        await store.createAdminUser(name: "Ada Lovelace", email: "ADA@EXAMPLE.COM", role: .user)

        let user = try XCTUnwrap(store.adminUsers.first)
        let event = try XCTUnwrap(store.auditEvents.first { $0.action.rawValue == "adminUserCreated" })
        XCTAssertEqual(event.outcome, .succeeded)
        XCTAssertEqual(event.metadata["userID"], user.id)
        XCTAssertEqual(event.metadata["name"], "Ada Lovelace")
        XCTAssertEqual(event.metadata["email"], "ada@example.com")
        XCTAssertEqual(event.metadata["role"], "user")

        let reloadedStore = fixture.makeStore()
        await reloadedStore.load()
        XCTAssertEqual(reloadedStore.auditEvents.first?.action.rawValue, "adminUserCreated")
        XCTAssertEqual(reloadedStore.auditEvents.first?.metadata["userID"], user.id)
    }

    func testUpdateUserRoleTrimsAndPersistsRole() async throws {
        let fixture = try AdminDirectoryFixture()
        let store = fixture.makeStore()
        await store.load()
        await store.createAdminUser(name: "Grace Hopper", email: "grace@example.com", role: .pending)
        let user = try XCTUnwrap(store.adminUsers.first)

        await store.updateAdminUser(user.id, name: "  Admiral Grace  ", email: " grace@example.com ", role: .admin)

        XCTAssertEqual(store.adminUsers.first?.name, "Admiral Grace")
        XCTAssertEqual(store.adminUsers.first?.email, "grace@example.com")
        XCTAssertEqual(store.adminUsers.first?.role, .admin)

        let reloadedStore = fixture.makeStore()
        await reloadedStore.load()

        XCTAssertEqual(reloadedStore.adminUsers.first?.role, .admin)
    }

    func testUpdateUserCreatesAuditEvent() async throws {
        let fixture = try AdminDirectoryFixture()
        let store = fixture.makeStore()
        await store.load()
        await store.createAdminUser(name: "Grace Hopper", email: "grace@example.com", role: .pending)
        let user = try XCTUnwrap(store.adminUsers.first)

        await store.updateAdminUser(user.id, name: "Admiral Grace", email: "grace@navy.example", role: .admin)

        let event = try XCTUnwrap(store.auditEvents.first { $0.action.rawValue == "adminUserUpdated" })
        XCTAssertEqual(event.outcome, .succeeded)
        XCTAssertEqual(event.metadata["userID"], user.id)
        XCTAssertEqual(event.metadata["fromName"], "Grace Hopper")
        XCTAssertEqual(event.metadata["name"], "Admiral Grace")
        XCTAssertEqual(event.metadata["fromEmail"], "grace@example.com")
        XCTAssertEqual(event.metadata["email"], "grace@navy.example")
        XCTAssertEqual(event.metadata["fromRole"], "pending")
        XCTAssertEqual(event.metadata["role"], "admin")
    }

    func testDeleteUserCreatesAuditEventAndRemovesMemberships() async throws {
        let fixture = try AdminDirectoryFixture()
        let store = fixture.makeStore()
        await store.load()
        await store.createAdminUser(name: "Linus", email: "linus@example.com", role: .user)
        let user = try XCTUnwrap(store.adminUsers.first)
        await store.createAdminGroup(name: "Knowledge Editors", description: "Can edit.", permissions: ["knowledge.write"])
        let group = try XCTUnwrap(store.adminGroups.first)
        await store.setAdminGroupMembers(group.id, memberIDs: [user.id])

        await store.deleteAdminUser(user.id)

        let event = try XCTUnwrap(store.auditEvents.first { $0.action.rawValue == "adminUserDeleted" })
        XCTAssertEqual(event.outcome, .succeeded)
        XCTAssertEqual(event.metadata["userID"], user.id)
        XCTAssertEqual(event.metadata["name"], "Linus")
        XCTAssertEqual(event.metadata["email"], "linus@example.com")
        XCTAssertEqual(event.metadata["role"], "user")
        XCTAssertEqual(event.metadata["removedFromGroupCount"], "1")
        XCTAssertTrue(store.adminGroups.first?.memberIDs.isEmpty ?? false)
    }

    func testCreateGroupAssignsMembersAndPermissions() async throws {
        let fixture = try AdminDirectoryFixture()
        let store = fixture.makeStore()
        await store.load()
        await store.createAdminUser(name: "Linus", email: "linus@example.com", role: .user)
        let user = try XCTUnwrap(store.adminUsers.first)

        await store.createAdminGroup(
            name: "Knowledge Editors",
            description: "Can manage shared knowledge.",
            permissions: ["knowledge:read", "knowledge:write"]
        )
        let group = try XCTUnwrap(store.adminGroups.first)
        await store.setAdminGroupMembers(group.id, memberIDs: [user.id])

        XCTAssertEqual(store.adminGroups.first?.memberIDs, [user.id])
        XCTAssertTrue(store.userHasPermission(user.id, permission: "knowledge:write"))
        XCTAssertFalse(store.userHasPermission(user.id, permission: "settings:write"))

        let reloadedStore = fixture.makeStore()
        await reloadedStore.load()

        XCTAssertEqual(reloadedStore.adminGroups.first?.memberIDs, [user.id])
        XCTAssertTrue(reloadedStore.userHasPermission(user.id, permission: "knowledge:read"))
    }

    func testCreateGroupCreatesAuditEvent() async throws {
        let fixture = try AdminDirectoryFixture()
        let store = fixture.makeStore()
        await store.load()

        await store.createAdminGroup(
            name: "Knowledge Editors",
            description: "Can manage shared knowledge.",
            permissions: ["knowledge:read", "knowledge:write", "knowledge:read"]
        )

        let group = try XCTUnwrap(store.adminGroups.first)
        let event = try XCTUnwrap(store.auditEvents.first { $0.action.rawValue == "adminGroupCreated" })
        XCTAssertEqual(event.outcome, .succeeded)
        XCTAssertEqual(event.metadata["groupID"], group.id)
        XCTAssertEqual(event.metadata["name"], "Knowledge Editors")
        XCTAssertEqual(event.metadata["description"], "Can manage shared knowledge.")
        XCTAssertEqual(event.metadata["permissions"], "knowledge:read, knowledge:write")
        XCTAssertEqual(event.metadata["memberCount"], "0")
    }

    func testUpdateGroupCreatesAuditEvent() async throws {
        let fixture = try AdminDirectoryFixture()
        let store = fixture.makeStore()
        await store.load()
        await store.createAdminUser(name: "Linus", email: "linus@example.com", role: .user)
        let user = try XCTUnwrap(store.adminUsers.first)
        await store.createAdminGroup(name: "Knowledge Editors", description: "Can edit.", permissions: ["knowledge.read"])
        let group = try XCTUnwrap(store.adminGroups.first)

        await store.updateAdminGroup(
            group.id,
            name: "Workspace Editors",
            description: "Can edit workspace records.",
            permissions: ["workspace.write"],
            memberIDs: [user.id]
        )

        let event = try XCTUnwrap(store.auditEvents.first { $0.action.rawValue == "adminGroupUpdated" })
        XCTAssertEqual(event.outcome, .succeeded)
        XCTAssertEqual(event.metadata["groupID"], group.id)
        XCTAssertEqual(event.metadata["fromName"], "Knowledge Editors")
        XCTAssertEqual(event.metadata["name"], "Workspace Editors")
        XCTAssertEqual(event.metadata["description"], "Can edit workspace records.")
        XCTAssertEqual(event.metadata["permissions"], "workspace.write")
        XCTAssertEqual(event.metadata["memberCount"], "1")
    }

    func testSetGroupMembersCreatesAuditEvent() async throws {
        let fixture = try AdminDirectoryFixture()
        let store = fixture.makeStore()
        await store.load()
        await store.createAdminUser(name: "Ada", email: "ada@example.com", role: .user)
        await store.createAdminUser(name: "Grace", email: "grace@example.com", role: .user)
        let memberIDs = store.adminUsers.map(\.id)
        await store.createAdminGroup(name: "Knowledge Editors", description: "Can edit.", permissions: ["knowledge.write"])
        let group = try XCTUnwrap(store.adminGroups.first)

        await store.setAdminGroupMembers(group.id, memberIDs: memberIDs)

        let event = try XCTUnwrap(store.auditEvents.first { $0.action.rawValue == "adminGroupMembersUpdated" })
        XCTAssertEqual(event.outcome, .succeeded)
        XCTAssertEqual(event.metadata["groupID"], group.id)
        XCTAssertEqual(event.metadata["name"], "Knowledge Editors")
        XCTAssertEqual(event.metadata["fromMemberCount"], "0")
        XCTAssertEqual(event.metadata["memberCount"], "2")
    }

    func testDeleteGroupCreatesAuditEvent() async throws {
        let fixture = try AdminDirectoryFixture()
        let store = fixture.makeStore()
        await store.load()
        await store.createAdminGroup(name: "Temporary Group", description: "Remove it.", permissions: ["settings.read"])
        let group = try XCTUnwrap(store.adminGroups.first)

        await store.deleteAdminGroup(group.id)

        let event = try XCTUnwrap(store.auditEvents.first { $0.action.rawValue == "adminGroupDeleted" })
        XCTAssertEqual(event.outcome, .succeeded)
        XCTAssertEqual(event.metadata["groupID"], group.id)
        XCTAssertEqual(event.metadata["name"], "Temporary Group")
        XCTAssertEqual(event.metadata["description"], "Remove it.")
        XCTAssertEqual(event.metadata["permissions"], "settings.read")
    }

    func testAdminUsersHaveAllPermissionsAndPendingUsersHaveNone() async throws {
        let fixture = try AdminDirectoryFixture()
        let store = fixture.makeStore()
        await store.load()
        await store.createAdminUser(name: "Admin", email: "admin@example.com", role: .admin)
        await store.createAdminUser(name: "Pending", email: "pending@example.com", role: .pending)
        let admin = try XCTUnwrap(store.adminUsers.first { $0.email == "admin@example.com" })
        let pending = try XCTUnwrap(store.adminUsers.first { $0.email == "pending@example.com" })

        XCTAssertTrue(store.userHasPermission(admin.id, permission: "anything:anywhere"))
        XCTAssertFalse(store.userHasPermission(pending.id, permission: "chat:write"))
    }

    func testExportAndImportAdminDirectoryJSONRoundTripsUsersGroupsAndPermissions() async throws {
        let fixture = try AdminDirectoryFixture()
        let store = fixture.makeStore()
        await store.load()
        await store.createAdminUser(name: "Ada Lovelace", email: "ada@example.com", role: .user)
        let user = try XCTUnwrap(store.adminUsers.first)
        await store.createAdminGroup(
            name: "Knowledge Editors",
            description: "Can manage shared knowledge.",
            permissions: ["knowledge.read", "knowledge.write", "knowledge.read"]
        )
        let group = try XCTUnwrap(store.adminGroups.first)
        await store.setAdminGroupMembers(group.id, memberIDs: [user.id])

        let data = try store.exportAdminDirectoryJSONData()

        let importFixture = try AdminDirectoryFixture()
        let importStore = importFixture.makeStore()
        await importStore.load()
        try await importStore.importAdminDirectoryJSONData(data)

        let importedUser = try XCTUnwrap(importStore.adminUsers.first)
        XCTAssertEqual(importedUser.email, "ada@example.com")
        XCTAssertEqual(importedUser.role, .user)
        let importedGroup = try XCTUnwrap(importStore.adminGroups.first)
        XCTAssertEqual(importedGroup.name, "Knowledge Editors")
        XCTAssertEqual(importedGroup.permissions, ["knowledge.read", "knowledge.write"])
        XCTAssertEqual(importedGroup.memberIDs, [importedUser.id])
        XCTAssertTrue(importStore.userHasPermission(importedUser.id, permission: "knowledge.write"))
    }

    func testExportAdminDirectoryJSONForUserActionCreatesAuditEventWithoutDirectoryContent() async throws {
        let fixture = try AdminDirectoryFixture()
        let store = fixture.makeStore()
        await store.load()
        await store.createAdminUser(name: "Ada Lovelace", email: "ada@example.com", role: .user)
        let user = try XCTUnwrap(store.adminUsers.first)
        await store.createAdminGroup(
            name: "Knowledge Editors",
            description: "Can manage shared knowledge.",
            permissions: ["knowledge.write"]
        )
        let group = try XCTUnwrap(store.adminGroups.first)
        await store.setAdminGroupMembers(group.id, memberIDs: [user.id])

        let data = try await store.exportAdminDirectoryJSONDataForUserAction()

        let importFixture = try AdminDirectoryFixture()
        let importStore = importFixture.makeStore()
        await importStore.load()
        try await importStore.importAdminDirectoryJSONData(data)
        XCTAssertEqual(importStore.adminUsers.map(\.email), ["ada@example.com"])
        XCTAssertEqual(importStore.adminGroups.map(\.name), ["Knowledge Editors"])

        let event = try XCTUnwrap(store.auditEvents.filter { $0.action == .adminDirectoryExported }.first)
        XCTAssertEqual(event.outcome, .succeeded)
        XCTAssertEqual(event.summary, "Exported admin directory")
        XCTAssertEqual(event.metadata["exportedUserCount"], "1")
        XCTAssertEqual(event.metadata["exportedGroupCount"], "1")
        XCTAssertNil(event.metadata["name"])
        XCTAssertNil(event.metadata["email"])
        XCTAssertNil(event.metadata["permissions"])
    }

    func testAdminDirectoryWriteActionsRequireSettingsWritePermission() async throws {
        let fixture = try AdminDirectoryFixture()
        let store = fixture.makeStore()
        await store.load()
        let user = AdminUser(id: "local-user", name: "Local User", email: "local@example.com", role: .user)
        let existingUser = AdminUser(id: "existing-user", name: "Existing User", email: "existing@example.com", role: .user)
        let group = AdminGroup(
            id: "existing-group",
            name: "Existing Group",
            description: "Existing permissions.",
            permissions: ["knowledge.write"],
            memberIDs: [existingUser.id]
        )
        store.adminUsers = [user, existingUser]
        store.adminGroups = [group]
        let importData = Data(
            """
            {
              "users": [
                { "id": "imported-user", "email": "imported@example.com", "name": "Imported User", "role": "admin" }
              ],
              "groups": []
            }
            """.utf8
        )

        await store.createAdminUser(name: "Blocked", email: "blocked@example.com", role: .admin)
        await store.updateAdminUser(existingUser.id, name: "Updated", email: "updated@example.com", role: .admin)
        await store.deleteAdminUser(existingUser.id)
        await store.createAdminGroup(name: "Blocked Group", description: "Nope.", permissions: ["settings.write"])
        await store.updateAdminGroup(group.id, name: "Updated Group", description: "Nope.", permissions: ["settings.write"], memberIDs: [])
        await store.setAdminGroupMembers(group.id, memberIDs: [])
        await store.deleteAdminGroup(group.id)
        do {
            _ = try await store.exportAdminDirectoryJSONDataForUserAction()
            XCTFail("Missing settings.write should block admin-directory export.")
        } catch {
            XCTAssertEqual(error.localizedDescription, "You do not have permission to manage admin directory.")
        }
        do {
            try await store.importAdminDirectoryJSONData(importData)
            XCTFail("Missing settings.write should block admin-directory import.")
        } catch {
            XCTAssertEqual(error.localizedDescription, "You do not have permission to manage admin directory.")
        }

        XCTAssertEqual(store.adminUsers, [user, existingUser])
        XCTAssertEqual(store.adminGroups, [group])
        XCTAssertEqual(store.errorMessage, "You do not have permission to manage admin directory.")
        XCTAssertFalse(store.auditEvents.contains { event in
            [
                .adminUserCreated,
                .adminUserUpdated,
                .adminUserDeleted,
                .adminGroupCreated,
                .adminGroupUpdated,
                .adminGroupMembersUpdated,
                .adminGroupDeleted,
                .adminDirectoryExported,
                .adminDirectoryImported
            ].contains(event.action)
        })
    }

    func testImportAdminDirectoryJSONAcceptsOpenWebUIUsersAndGroupExports() async throws {
        let fixture = try AdminDirectoryFixture()
        let store = fixture.makeStore()
        await store.load()
        let data = Data(
            """
            {
              "users": [
                {
                  "id": "user-1",
                  "email": "ADA@EXAMPLE.COM",
                  "name": "Ada Lovelace",
                  "role": "user",
                  "created_at": 1000,
                  "updated_at": 2000,
                  "last_active_at": 3000
                },
                {
                  "id": "user-2",
                  "email": "admin@example.com",
                  "name": "Admin",
                  "role": "admin",
                  "created_at": 1000,
                  "updated_at": 4000
                }
              ],
              "groups": [
                {
                  "id": "group-1",
                  "user_id": "user-2",
                  "name": "Knowledge Editors",
                  "description": "Can manage shared knowledge.",
                  "permissions": {
                    "knowledge": {
                      "read": true,
                      "write": true,
                      "delete": false
                    },
                    "workspace": {
                      "admin": true
                    }
                  },
                  "user_ids": ["user-1", "missing-user", "user-1"],
                  "created_at": 4000,
                  "updated_at": 5000
                }
              ]
            }
            """.utf8
        )

        try await store.importAdminDirectoryJSONData(data)

        XCTAssertEqual(store.adminUsers.map(\.email), ["admin@example.com", "ada@example.com"])
        let importedUser = try XCTUnwrap(store.adminUsers.first { $0.id == "user-1" })
        XCTAssertEqual(importedUser.email, "ada@example.com")
        XCTAssertEqual(importedUser.role, .user)
        XCTAssertEqual(importedUser.lastActiveAt, Date(timeIntervalSince1970: 3000))
        let importedGroup = try XCTUnwrap(store.adminGroups.first)
        XCTAssertEqual(importedGroup.id, "group-1")
        XCTAssertEqual(importedGroup.memberIDs, ["user-1"])
        XCTAssertEqual(importedGroup.permissions, ["knowledge.read", "knowledge.write", "workspace.admin"])
        XCTAssertTrue(store.userHasPermission("user-1", permission: "knowledge.write"))
        XCTAssertFalse(store.userHasPermission("user-1", permission: "knowledge.delete"))
    }

    func testImportAdminDirectoryJSONCreatesAuditEventWithoutDirectoryContent() async throws {
        let fixture = try AdminDirectoryFixture()
        let store = fixture.makeStore()
        await store.load()
        let data = Data(
            """
            {
              "users": [
                {
                  "id": "user-1",
                  "email": "ada@example.com",
                  "name": "Ada Lovelace",
                  "role": "user"
                }
              ],
              "groups": [
                {
                  "id": "group-1",
                  "name": "Knowledge Editors",
                  "description": "Can manage shared knowledge.",
                  "permissions": {
                    "knowledge": {
                      "write": true
                    }
                  },
                  "user_ids": ["user-1"]
                }
              ]
            }
            """.utf8
        )

        try await store.importAdminDirectoryJSONData(data)

        let event = try XCTUnwrap(store.auditEvents.first)
        XCTAssertEqual(event.action, .adminDirectoryImported)
        XCTAssertEqual(event.outcome, .succeeded)
        XCTAssertEqual(event.summary, "Imported admin directory")
        XCTAssertEqual(event.metadata["importedUserCount"], "1")
        XCTAssertEqual(event.metadata["importedGroupCount"], "1")
        XCTAssertEqual(event.metadata["totalUserCount"], "1")
        XCTAssertEqual(event.metadata["totalGroupCount"], "1")
        XCTAssertNil(event.metadata["name"])
        XCTAssertNil(event.metadata["email"])
        XCTAssertNil(event.metadata["permissions"])
    }

    func testImportAdminDirectoryJSONAcceptsSCIMListResponseUsersAndGroups() async throws {
        let fixture = try AdminDirectoryFixture()
        let store = fixture.makeStore()
        await store.load()
        let data = Data(
            """
            {
              "schemas": ["urn:ietf:params:scim:api:messages:2.0:ListResponse"],
              "Resources": [
                {
                  "schemas": ["urn:ietf:params:scim:schemas:core:2.0:User"],
                  "id": "user-1",
                  "userName": "ada@example.com",
                  "name": {
                    "formatted": "Ada Lovelace"
                  },
                  "emails": [
                    { "value": "ADA@EXAMPLE.COM", "primary": true }
                  ],
                  "active": true
                },
                {
                  "schemas": ["urn:ietf:params:scim:schemas:core:2.0:User"],
                  "id": "user-2",
                  "userName": "pending@example.com",
                  "name": {
                    "givenName": "Pending",
                    "familyName": "User"
                  },
                  "emails": [
                    { "value": "pending@example.com" }
                  ],
                  "active": false
                },
                {
                  "schemas": ["urn:ietf:params:scim:schemas:core:2.0:Group"],
                  "id": "group-1",
                  "displayName": "Workspace Editors",
                  "members": [
                    { "value": "user-1", "display": "Ada Lovelace" },
                    { "value": "missing-user" },
                    { "value": "user-1" }
                  ],
                  "urn:open-webui:native:permissions": ["knowledge.write", "prompts.write"]
                }
              ]
            }
            """.utf8
        )

        try await store.importAdminDirectoryJSONData(data)

        let activeUser = try XCTUnwrap(store.adminUsers.first { $0.id == "user-1" })
        XCTAssertEqual(activeUser.email, "ada@example.com")
        XCTAssertEqual(activeUser.name, "Ada Lovelace")
        XCTAssertEqual(activeUser.role, .user)
        let inactiveUser = try XCTUnwrap(store.adminUsers.first { $0.id == "user-2" })
        XCTAssertEqual(inactiveUser.name, "Pending User")
        XCTAssertEqual(inactiveUser.role, .pending)
        let importedGroup = try XCTUnwrap(store.adminGroups.first)
        XCTAssertEqual(importedGroup.id, "group-1")
        XCTAssertEqual(importedGroup.name, "Workspace Editors")
        XCTAssertEqual(importedGroup.memberIDs, ["user-1"])
        XCTAssertEqual(importedGroup.permissions, ["knowledge.write", "prompts.write"])
        XCTAssertTrue(store.userHasPermission("user-1", permission: "prompts.write"))
    }

    func testImportAdminDirectoryJSONCreatesGroupsFromSCIMUserMemberships() async throws {
        let fixture = try AdminDirectoryFixture()
        let store = fixture.makeStore()
        await store.load()
        let data = Data(
            """
            {
              "schemas": ["urn:ietf:params:scim:api:messages:2.0:ListResponse"],
              "Resources": [
                {
                  "schemas": ["urn:ietf:params:scim:schemas:core:2.0:User"],
                  "id": "user-1",
                  "userName": "ada@example.com",
                  "name": { "formatted": "Ada Lovelace" },
                  "emails": [{ "value": "ada@example.com" }],
                  "groups": [
                    { "value": "group-1", "display": "Research Team" },
                    { "value": "group-1", "display": "Research Team" }
                  ]
                },
                {
                  "schemas": ["urn:ietf:params:scim:schemas:core:2.0:User"],
                  "id": "user-2",
                  "userName": "grace@example.com",
                  "name": { "formatted": "Grace Hopper" },
                  "emails": [{ "value": "grace@example.com" }],
                  "groups": [
                    { "value": "group-1", "display": "Research Team" }
                  ]
                }
              ]
            }
            """.utf8
        )

        try await store.importAdminDirectoryJSONData(data)

        XCTAssertEqual(store.adminUsers.map(\.email).sorted(), ["ada@example.com", "grace@example.com"])
        let importedGroup = try XCTUnwrap(store.adminGroups.first)
        XCTAssertEqual(importedGroup.id, "group-1")
        XCTAssertEqual(importedGroup.name, "Research Team")
        XCTAssertEqual(importedGroup.memberIDs, ["user-1", "user-2"])
        XCTAssertTrue(importedGroup.permissions.isEmpty)
    }

    func testImportAdminDirectoryJSONMapsSCIMGroupEntitlementsToPermissions() async throws {
        let fixture = try AdminDirectoryFixture()
        let store = fixture.makeStore()
        await store.load()
        let data = Data(
            """
            {
              "schemas": ["urn:ietf:params:scim:api:messages:2.0:ListResponse"],
              "Resources": [
                {
                  "schemas": ["urn:ietf:params:scim:schemas:core:2.0:User"],
                  "id": "user-1",
                  "userName": "ada@example.com",
                  "name": { "formatted": "Ada Lovelace" },
                  "emails": [{ "value": "ada@example.com" }]
                },
                {
                  "schemas": ["urn:ietf:params:scim:schemas:core:2.0:Group"],
                  "id": "group-1",
                  "displayName": "Knowledge Editors",
                  "members": [{ "value": "user-1", "display": "Ada Lovelace" }],
                  "entitlements": [
                    { "value": "knowledge.write" },
                    { "value": "prompts.write", "display": "Prompt publishing" }
                  ]
                }
              ]
            }
            """.utf8
        )

        try await store.importAdminDirectoryJSONData(data)

        let importedGroup = try XCTUnwrap(store.adminGroups.first)
        XCTAssertEqual(importedGroup.permissions, ["knowledge.write", "prompts.write"])
        XCTAssertTrue(store.userHasPermission("user-1", permission: "knowledge.write"))
        XCTAssertTrue(store.userHasPermission("user-1", permission: "prompts.write"))
    }

    func testImportAdminDirectoryJSONMapsSCIMUserRoles() async throws {
        let fixture = try AdminDirectoryFixture()
        let store = fixture.makeStore()
        await store.load()
        let data = Data(
            """
            {
              "schemas": ["urn:ietf:params:scim:api:messages:2.0:ListResponse"],
              "Resources": [
                {
                  "schemas": ["urn:ietf:params:scim:schemas:core:2.0:User"],
                  "id": "admin-user",
                  "userName": "admin@example.com",
                  "name": { "formatted": "Admin User" },
                  "emails": [{ "value": "admin@example.com" }],
                  "roles": [{ "value": "admin", "primary": true }]
                },
                {
                  "schemas": ["urn:ietf:params:scim:schemas:core:2.0:User"],
                  "id": "pending-user",
                  "userName": "pending@example.com",
                  "name": { "formatted": "Pending User" },
                  "emails": [{ "value": "pending@example.com" }],
                  "userType": "pending"
                }
              ]
            }
            """.utf8
        )

        try await store.importAdminDirectoryJSONData(data)

        let admin = try XCTUnwrap(store.adminUsers.first { $0.id == "admin-user" })
        XCTAssertEqual(admin.role, .admin)
        XCTAssertTrue(store.userHasPermission(admin.id, permission: "settings.write"))
        let pending = try XCTUnwrap(store.adminUsers.first { $0.id == "pending-user" })
        XCTAssertEqual(pending.role, .pending)
        XCTAssertFalse(store.userHasPermission(pending.id, permission: "settings.write"))
    }
}

private struct AdminDirectoryFixture {
    let rootURL: URL
    let chatStorage: JSONStorageService
    let folderStorage: JSONFolderStorageService
    let settingsStore: SettingsStore
    let adminStorage: JSONAdminDirectoryStorageService
    let auditStorage: JSONAuditLogStorageService

    init() throws {
        rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        chatStorage = JSONStorageService(rootURL: rootURL.appendingPathComponent("Chats", isDirectory: true))
        folderStorage = JSONFolderStorageService(rootURL: rootURL.appendingPathComponent("Folders", isDirectory: true))
        settingsStore = SettingsStore(settingsURL: rootURL.appendingPathComponent("settings.json"))
        adminStorage = JSONAdminDirectoryStorageService(
            snapshotURL: rootURL.appendingPathComponent("admin-directory.json")
        )
        auditStorage = JSONAuditLogStorageService(rootURL: rootURL.appendingPathComponent("AuditLog", isDirectory: true))
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
    }

    @MainActor
    func makeStore() -> AppStore {
        AppStore(
            storage: chatStorage,
            folderStorage: folderStorage,
            settingsStore: settingsStore,
            secretStore: InMemorySecretStore(),
            auditLogStorage: auditStorage,
            adminDirectoryStorage: adminStorage
        )
    }
}
