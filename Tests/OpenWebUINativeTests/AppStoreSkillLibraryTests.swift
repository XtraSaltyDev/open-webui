import XCTest
@testable import OpenWebUINative

@MainActor
final class AppStoreSkillLibraryTests: XCTestCase {
    func testCreateSkillPersistsAndReloads() async throws {
        let fixture = try SkillLibraryFixture()
        let store = fixture.makeStore()
        await store.load()

        await store.createSkill(
            name: "Bug triage",
            content: "You are careful with bug reports.",
            description: "Triage incoming bug reports.",
            tags: ["debug", "support"]
        )

        XCTAssertEqual(store.skills.map(\.name), ["Bug triage"])
        XCTAssertEqual(store.skills.first?.content, "You are careful with bug reports.")
        XCTAssertEqual(store.skills.first?.description, "Triage incoming bug reports.")
        XCTAssertEqual(store.skills.first?.tags, ["debug", "support"])
        XCTAssertEqual(store.skills.first?.isActive, true)

        let reloadedStore = fixture.makeStore()
        await reloadedStore.load()

        XCTAssertEqual(reloadedStore.skills.map(\.name), ["Bug triage"])
        XCTAssertEqual(reloadedStore.skills.first?.tags, ["debug", "support"])
    }

    func testCreateSkillCreatesAuditEvent() async throws {
        let fixture = try SkillLibraryFixture()
        let store = fixture.makeStore()
        await store.load()

        await store.createSkill(
            name: "Bug triage",
            content: "You are careful with bug reports.",
            description: "Triage incoming bug reports.",
            tags: ["debug", "support"]
        )

        let skill = try XCTUnwrap(store.skills.first)
        let event = try XCTUnwrap(store.auditEvents.first { $0.action.rawValue == "skillCreated" })
        XCTAssertEqual(event.outcome, .succeeded)
        XCTAssertEqual(event.metadata["skillID"], skill.id)
        XCTAssertEqual(event.metadata["name"], "Bug triage")
        XCTAssertEqual(event.metadata["description"], "Triage incoming bug reports.")
        XCTAssertEqual(event.metadata["tags"], "debug, support")
        XCTAssertEqual(event.metadata["isActive"], "true")
        XCTAssertNil(event.metadata["content"])

        let reloadedStore = fixture.makeStore()
        await reloadedStore.load()
        XCTAssertEqual(reloadedStore.auditEvents.first?.action.rawValue, "skillCreated")
        XCTAssertEqual(reloadedStore.auditEvents.first?.metadata["skillID"], skill.id)
    }

    func testUpdateSkillTrimsInputSortsAndUpdatesActiveState() async throws {
        let fixture = try SkillLibraryFixture()
        let store = fixture.makeStore()
        await store.load()

        await store.createSkill(name: "First", content: "first", description: "First skill", tags: ["one"])
        await store.createSkill(name: "Second", content: "second", description: "Second skill", tags: ["two"])
        let firstSkill = try XCTUnwrap(store.skills.first { $0.name == "First" })

        await store.updateSkill(
            firstSkill.id,
            name: "  Updated first  ",
            content: "  better  ",
            description: "  Better skill  ",
            tags: [" updated ", "support", "updated"],
            isActive: false
        )

        XCTAssertEqual(store.skills.map(\.name), ["Updated first", "Second"])
        XCTAssertEqual(store.skills.first?.content, "better")
        XCTAssertEqual(store.skills.first?.description, "Better skill")
        XCTAssertEqual(store.skills.first?.tags, ["updated", "support"])
        XCTAssertEqual(store.skills.first?.isActive, false)
    }

    func testUpdateSkillCreatesAuditEvent() async throws {
        let fixture = try SkillLibraryFixture()
        let store = fixture.makeStore()
        await store.load()
        await store.createSkill(name: "First", content: "first", description: "First skill", tags: ["one"])
        let skill = try XCTUnwrap(store.skills.first)

        await store.updateSkill(
            skill.id,
            name: "Updated first",
            content: "better",
            description: "Better skill",
            tags: ["updated", "support"],
            isActive: false
        )

        let event = try XCTUnwrap(store.auditEvents.first { $0.action.rawValue == "skillUpdated" })
        XCTAssertEqual(event.outcome, .succeeded)
        XCTAssertEqual(event.metadata["skillID"], skill.id)
        XCTAssertEqual(event.metadata["fromName"], "First")
        XCTAssertEqual(event.metadata["name"], "Updated first")
        XCTAssertEqual(event.metadata["description"], "Better skill")
        XCTAssertEqual(event.metadata["tags"], "updated, support")
        XCTAssertEqual(event.metadata["isActive"], "false")
        XCTAssertNil(event.metadata["content"])
    }

    func testDeleteSkillRemovesItFromStorage() async throws {
        let fixture = try SkillLibraryFixture()
        let store = fixture.makeStore()
        await store.load()
        await store.createSkill(name: "Temporary", content: "temp", description: nil, tags: [])
        let skill = try XCTUnwrap(store.skills.first)

        await store.deleteSkill(skill.id)

        let reloadedStore = fixture.makeStore()
        await reloadedStore.load()
        XCTAssertTrue(reloadedStore.skills.isEmpty)
    }

    func testDeleteSkillCreatesAuditEvent() async throws {
        let fixture = try SkillLibraryFixture()
        let store = fixture.makeStore()
        await store.load()
        await store.createSkill(name: "Temporary", content: "temp", description: "Remove after testing.", tags: ["cleanup"])
        let skill = try XCTUnwrap(store.skills.first)

        await store.deleteSkill(skill.id)

        let event = try XCTUnwrap(store.auditEvents.first { $0.action.rawValue == "skillDeleted" })
        XCTAssertEqual(event.outcome, .succeeded)
        XCTAssertEqual(event.metadata["skillID"], skill.id)
        XCTAssertEqual(event.metadata["name"], "Temporary")
        XCTAssertEqual(event.metadata["description"], "Remove after testing.")
        XCTAssertEqual(event.metadata["tags"], "cleanup")
        XCTAssertEqual(event.metadata["isActive"], "true")
        XCTAssertNil(event.metadata["content"])

        let reloadedStore = fixture.makeStore()
        await reloadedStore.load()
        let reloadedEvent = try XCTUnwrap(reloadedStore.auditEvents.first { $0.action.rawValue == "skillDeleted" })
        XCTAssertEqual(reloadedEvent.metadata["skillID"], skill.id)
    }

    func testFilteredSkillsSearchesNameDescriptionTagsAndContent() async throws {
        let fixture = try SkillLibraryFixture()
        let store = fixture.makeStore()
        await store.load()
        await store.createSkill(
            name: "Bug triage",
            content: "Classify incoming issue reports.",
            description: "Triage support tickets.",
            tags: ["debug", "support"]
        )
        await store.createSkill(
            name: "Release coach",
            content: "Prepare launch notes.",
            description: "Ship planning assistant.",
            tags: ["release"]
        )

        store.skillSearchText = "support"
        XCTAssertEqual(store.filteredSkills().map(\.name), ["Bug triage"])

        store.skillSearchText = "launch"
        XCTAssertEqual(store.filteredSkills().map(\.name), ["Release coach"])
    }

    func testFilteredSkillsSupportsTagOperator() async throws {
        let fixture = try SkillLibraryFixture()
        let store = fixture.makeStore()
        await store.load()
        await store.createSkill(name: "Bug triage", content: "triage", description: nil, tags: ["debug", "support"])
        await store.createSkill(name: "Release coach", content: "release", description: nil, tags: ["release"])

        store.skillSearchText = "tag:debug"

        XCTAssertEqual(store.filteredSkills().map(\.name), ["Bug triage"])
    }

    func testFilteredSkillsSupportsActiveOperator() async throws {
        let fixture = try SkillLibraryFixture()
        let store = fixture.makeStore()
        await store.load()
        await store.createSkill(name: "Active skill", content: "active", description: nil, tags: [])
        await store.createSkill(name: "Inactive skill", content: "inactive", description: nil, tags: [])
        let inactiveSkill = try XCTUnwrap(store.skills.first { $0.name == "Inactive skill" })
        await store.updateSkill(
            inactiveSkill.id,
            name: inactiveSkill.name,
            content: inactiveSkill.content,
            description: inactiveSkill.description,
            tags: inactiveSkill.tags,
            isActive: false
        )

        store.skillSearchText = "active:false"

        XCTAssertEqual(store.filteredSkills().map(\.name), ["Inactive skill"])
    }

    func testSendPromptIncludesActiveSkillsAsSystemContext() async throws {
        let provider = CapturingSkillChatProvider()
        let fixture = try SkillLibraryFixture(provider: provider)
        let store = fixture.makeStore()
        await store.load()
        await store.selectModel("fake-model")
        await store.createSkill(
            name: "Bug triage",
            content: "Always classify issue severity before proposing fixes.",
            description: "Debug workflow",
            tags: ["debug"]
        )

        await store.send("Help with this crash report.")

        let messages = await provider.messages()
        XCTAssertEqual(messages.first?.role, "system")
        XCTAssertTrue(messages.first?.content.contains("Active Open WebUI skills") ?? false)
        XCTAssertTrue(messages.first?.content.contains("Bug triage") ?? false)
        XCTAssertTrue(messages.first?.content.contains("Always classify issue severity") ?? false)
        XCTAssertEqual(messages.last, ProviderChatMessage(role: "user", content: "Help with this crash report."))
    }

    func testSendPromptOmitsInactiveSkillsFromSystemContext() async throws {
        let provider = CapturingSkillChatProvider()
        let fixture = try SkillLibraryFixture(provider: provider)
        let store = fixture.makeStore()
        await store.load()
        await store.selectModel("fake-model")
        await store.createSkill(name: "Active skill", content: "Keep answers brief.", description: nil, tags: [])
        await store.createSkill(name: "Inactive skill", content: "Never include this instruction.", description: nil, tags: [])
        let inactiveSkill = try XCTUnwrap(store.skills.first { $0.name == "Inactive skill" })
        await store.updateSkill(
            inactiveSkill.id,
            name: inactiveSkill.name,
            content: inactiveSkill.content,
            description: inactiveSkill.description,
            tags: inactiveSkill.tags,
            isActive: false
        )

        await store.send("Answer normally.")

        let systemContent = await provider.messages().first { $0.role == "system" }?.content
        XCTAssertTrue(systemContent?.contains("Active skill") ?? false)
        XCTAssertFalse(systemContent?.contains("Inactive skill") ?? true)
        XCTAssertFalse(systemContent?.contains("Never include this instruction.") ?? true)
    }

    func testSendPromptIncludesSkillGrantedToCurrentUser() async throws {
        let provider = CapturingSkillChatProvider()
        let fixture = try SkillLibraryFixture(provider: provider)
        let store = fixture.makeStore()
        await store.load()
        await store.selectModel("fake-model")
        await store.createAdminUser(name: "Local Admin", email: "admin@example.com", role: .admin)
        await store.createAdminUser(name: "Workspace User", email: "user@example.com", role: .user)
        let admin = try XCTUnwrap(store.adminUsers.first { $0.role == .admin })
        let user = try XCTUnwrap(store.adminUsers.first { $0.role == .user })
        store.currentUserID = admin.id
        await store.createSkill(
            name: "Ops guard",
            content: "Ask for rollout risk before release changes.",
            description: nil,
            tags: ["release"],
            allowedUserIDs: [user.id],
            allowedGroupIDs: []
        )

        store.currentUserID = user.id
        await store.send("Ship this change.")

        let systemContent = await provider.messages().first { $0.role == "system" }?.content
        XCTAssertTrue(systemContent?.contains("Ops guard") ?? false)
        XCTAssertTrue(systemContent?.contains("Ask for rollout risk") ?? false)
    }

    func testSendPromptOmitsSkillWithoutCurrentUserOrGroupGrant() async throws {
        let provider = CapturingSkillChatProvider()
        let fixture = try SkillLibraryFixture(provider: provider)
        let store = fixture.makeStore()
        await store.load()
        await store.selectModel("fake-model")
        await store.createAdminUser(name: "Local Admin", email: "admin@example.com", role: .admin)
        await store.createAdminUser(name: "Workspace User", email: "user@example.com", role: .user)
        let admin = try XCTUnwrap(store.adminUsers.first { $0.role == .admin })
        let user = try XCTUnwrap(store.adminUsers.first { $0.role == .user })
        store.currentUserID = admin.id
        await store.createSkill(
            name: "Private skill",
            content: "Never leak this instruction.",
            description: nil,
            tags: [],
            allowedUserIDs: ["someone-else"],
            allowedGroupIDs: []
        )

        store.currentUserID = user.id
        await store.send("Answer normally.")

        let systemContent = await provider.messages().first { $0.role == "system" }?.content
        XCTAssertFalse(systemContent?.contains("Private skill") ?? false)
        XCTAssertFalse(systemContent?.contains("Never leak this instruction.") ?? false)
    }

    func testSendPromptIncludesSkillGrantedToCurrentUsersGroup() async throws {
        let provider = CapturingSkillChatProvider()
        let fixture = try SkillLibraryFixture(provider: provider)
        let store = fixture.makeStore()
        await store.load()
        await store.selectModel("fake-model")
        await store.createAdminUser(name: "Local Admin", email: "admin@example.com", role: .admin)
        await store.createAdminUser(name: "Workspace User", email: "user@example.com", role: .user)
        let admin = try XCTUnwrap(store.adminUsers.first { $0.role == .admin })
        let user = try XCTUnwrap(store.adminUsers.first { $0.role == .user })
        store.currentUserID = admin.id
        await store.createAdminGroup(name: "Release Team", description: "Ships builds.", permissions: [])
        let group = try XCTUnwrap(store.adminGroups.first)
        await store.setAdminGroupMembers(group.id, memberIDs: [user.id])
        await store.createSkill(
            name: "Release coach",
            content: "Check release notes before final answer.",
            description: nil,
            tags: ["release"],
            allowedUserIDs: [],
            allowedGroupIDs: [group.id]
        )

        store.currentUserID = user.id
        await store.send("Prepare the launch.")

        let systemContent = await provider.messages().first { $0.role == "system" }?.content
        XCTAssertTrue(systemContent?.contains("Release coach") ?? false)
        XCTAssertTrue(systemContent?.contains("Check release notes") ?? false)
    }

    func testSkillWritePermissionAllowsCreateUpdateAndDeleteForCurrentUser() async throws {
        let fixture = try SkillLibraryFixture()
        let store = fixture.makeStore()
        await store.load()
        await store.createAdminUser(name: "Workspace User", email: "user@example.com", role: .user)
        let user = try XCTUnwrap(store.adminUsers.first)
        await store.createAdminGroup(name: "Skill Editors", description: "Can manage skills.", permissions: ["skills.write"])
        let group = try XCTUnwrap(store.adminGroups.first)
        await store.setAdminGroupMembers(group.id, memberIDs: [user.id])
        store.currentUserID = user.id

        await store.createSkill(name: "Bug triage", content: "Classify bugs.", description: nil, tags: [])
        let skill = try XCTUnwrap(store.skills.first)
        await store.updateSkill(
            skill.id,
            name: "Updated triage",
            content: "Classify bugs and suggest next steps.",
            description: nil,
            tags: ["debug"],
            isActive: true
        )
        let updatedSkill = try XCTUnwrap(store.skills.first)
        await store.deleteSkill(updatedSkill.id)

        XCTAssertTrue(store.skills.isEmpty)
        XCTAssertNil(store.errorMessage)
        XCTAssertTrue(store.auditEvents.contains { $0.action.rawValue == "skillCreated" })
        XCTAssertTrue(store.auditEvents.contains { $0.action.rawValue == "skillUpdated" })
        XCTAssertTrue(store.auditEvents.contains { $0.action.rawValue == "skillDeleted" })
    }

    func testSkillWritePermissionBlocksCreateUpdateAndDeleteForCurrentUser() async throws {
        let fixture = try SkillLibraryFixture()
        let store = fixture.makeStore()
        await store.load()
        await store.createAdminUser(name: "Workspace User", email: "user@example.com", role: .user)
        let user = try XCTUnwrap(store.adminUsers.first)
        store.currentUserID = user.id

        await store.createSkill(name: "Blocked skill", content: "Should not persist.", description: nil, tags: [])

        XCTAssertTrue(store.skills.isEmpty)
        XCTAssertEqual(store.errorMessage, "You do not have permission to manage skills.")

        store.errorMessage = nil
        store.currentUserID = "local-admin"
        await store.createAdminUser(name: "Local Admin", email: "admin@example.com", role: .admin)
        let admin = try XCTUnwrap(store.adminUsers.first { $0.role == .admin })
        store.currentUserID = admin.id
        await store.createSkill(name: "Existing skill", content: "Existing content.", description: nil, tags: [])
        let skill = try XCTUnwrap(store.skills.first)

        store.currentUserID = user.id
        await store.updateSkill(
            skill.id,
            name: "Blocked update",
            content: "Should not update.",
            description: nil,
            tags: [],
            isActive: false
        )
        await store.deleteSkill(skill.id)

        XCTAssertEqual(store.skills.first?.name, "Existing skill")
        XCTAssertEqual(store.skills.first?.content, "Existing content.")
        XCTAssertEqual(store.errorMessage, "You do not have permission to manage skills.")
        XCTAssertFalse(store.auditEvents.contains { $0.action.rawValue == "skillUpdated" })
        XCTAssertFalse(store.auditEvents.contains { $0.action.rawValue == "skillDeleted" })
    }

    func testCreateSkillIsBlockedWhenSkillsFeatureIsDisabled() async throws {
        let fixture = try SkillLibraryFixture()
        let store = fixture.makeStore()
        await store.load()
        await store.setFeatureToggle(.skills, isEnabled: false)

        await store.createSkill(name: "Hidden skill", content: "Should not persist.", description: nil, tags: [])

        XCTAssertTrue(store.skills.isEmpty)
        XCTAssertEqual(store.errorMessage, "Skills is disabled.")
        let saved = try await fixture.skillStorage.loadSkills()
        XCTAssertTrue(saved.isEmpty)
    }

    func testUpdateAndDeleteSkillAreBlockedWhenSkillsFeatureIsDisabled() async throws {
        let fixture = try SkillLibraryFixture()
        let store = fixture.makeStore()
        await store.load()
        await store.createSkill(name: "Existing skill", content: "Existing content.", description: nil, tags: ["local"])
        let skill = try XCTUnwrap(store.skills.first)
        await store.setFeatureToggle(.skills, isEnabled: false)

        await store.updateSkill(
            skill.id,
            name: "Blocked update",
            content: "Blocked content.",
            description: "Should not save.",
            tags: ["blocked"],
            isActive: false
        )
        await store.deleteSkill(skill.id)

        XCTAssertEqual(store.skills.map(\.name), ["Existing skill"])
        XCTAssertEqual(store.skills.first?.content, "Existing content.")
        XCTAssertEqual(store.skills.first?.tags, ["local"])
        XCTAssertEqual(store.errorMessage, "Skills is disabled.")
        let saved = try await fixture.skillStorage.loadSkills()
        XCTAssertEqual(saved.map(\.name), ["Existing skill"])
        XCTAssertEqual(saved.first?.content, "Existing content.")
    }

    func testImportSkillsJSONIsBlockedWhenSkillsFeatureIsDisabled() async throws {
        let sourceFixture = try SkillLibraryFixture()
        let sourceStore = sourceFixture.makeStore()
        await sourceStore.load()
        await sourceStore.createSkill(name: "Imported skill", content: "Reusable behavior.", description: nil, tags: ["imported"])
        let data = try sourceStore.exportSkillsJSONData()

        let fixture = try SkillLibraryFixture()
        let store = fixture.makeStore()
        await store.load()
        await store.setFeatureToggle(.skills, isEnabled: false)

        try await store.importSkillsJSONData(data)
        await store.importSkillsJSON(from: fixture.rootURL.appendingPathComponent("missing-skills.json"))

        XCTAssertTrue(store.skills.isEmpty)
        XCTAssertEqual(store.errorMessage, "Skills is disabled.")
        let saved = try await fixture.skillStorage.loadSkills()
        XCTAssertTrue(saved.isEmpty)
    }

    func testShareSkillIsBlockedWhenSkillsFeatureIsDisabled() async throws {
        let shareService = FakeSkillShareService()
        let fixture = try SkillLibraryFixture(shareService: shareService)
        let store = fixture.makeStore()
        await store.load()
        await store.createSkill(name: "Existing skill", content: "Existing content.", description: nil, tags: [])
        let skill = try XCTUnwrap(store.skills.first)
        await store.setFeatureToggle(.skills, isEnabled: false)

        store.shareSkill(skill.id)

        XCTAssertNil(shareService.sharedTitle)
        XCTAssertNil(shareService.sharedText)
        XCTAssertEqual(store.errorMessage, "Skills is disabled.")
    }

    func testSendPromptOmitsActiveSkillsWhenSkillsFeatureIsDisabled() async throws {
        let provider = CapturingSkillChatProvider()
        let fixture = try SkillLibraryFixture(provider: provider)
        let store = fixture.makeStore()
        await store.load()
        await store.selectModel("fake-model")
        await store.createSkill(
            name: "Bug triage",
            content: "Always classify issue severity.",
            description: nil,
            tags: ["debug"]
        )
        await store.setFeatureToggle(.skills, isEnabled: false)

        await store.send("Help with this crash report.")

        let messages = await provider.messages()
        XCTAssertEqual(messages.first, ProviderChatMessage(role: "user", content: "Help with this crash report."))
        XCTAssertFalse(messages.contains { $0.role == "system" && $0.content.contains("Active Open WebUI skills") })
        XCTAssertNil(store.errorMessage)
    }

    func testUnmanagedLocalUserCanManageSkillsWhenAdminDirectoryExists() async throws {
        let fixture = try SkillLibraryFixture()
        let store = fixture.makeStore()
        await store.load()
        await store.createAdminUser(name: "Workspace User", email: "user@example.com", role: .user)

        await store.createSkill(name: "Local skill", content: "Keep local owner working.", description: nil, tags: [])

        XCTAssertEqual(store.skills.map(\.name), ["Local skill"])
        XCTAssertNil(store.errorMessage)
    }

    func testExportAndImportSkillsJSONRoundTripsSkillLibrary() async throws {
        let fixture = try SkillLibraryFixture()
        let store = fixture.makeStore()
        await store.load()
        await store.createSkill(name: "Bug triage", content: "triage", description: "Debug", tags: ["debug"])
        await store.createSkill(name: "Release coach", content: "release", description: "Ship", tags: ["release"])

        let data = try store.exportSkillsJSONData()

        let importFixture = try SkillLibraryFixture()
        let importStore = importFixture.makeStore()
        await importStore.load()
        try await importStore.importSkillsJSONData(data)

        XCTAssertEqual(Set(importStore.skills.map(\.name)), ["Bug triage", "Release coach"])
        XCTAssertEqual(importStore.skills.first { $0.name == "Release coach" }?.tags, ["release"])
    }

    func testExportSkillJSONDataExportsOnlySelectedSkill() async throws {
        let fixture = try SkillLibraryFixture()
        let store = fixture.makeStore()
        await store.load()
        await store.createSkill(name: "Bug triage", content: "triage", description: "Debug", tags: ["debug"])
        await store.createSkill(name: "Release coach", content: "release", description: "Ship", tags: ["release"])
        let skill = try XCTUnwrap(store.skills.first { $0.name == "Bug triage" })

        let data = try XCTUnwrap(store.exportSkillJSONData(skill.id))

        let importFixture = try SkillLibraryFixture()
        let importStore = importFixture.makeStore()
        await importStore.load()
        try await importStore.importSkillsJSONData(data)

        XCTAssertEqual(importStore.skills.map(\.name), ["Bug triage"])
        XCTAssertEqual(importStore.skills.first?.description, "Debug")
        XCTAssertEqual(importStore.skills.first?.tags, ["debug"])
    }

    func testExportSkillsOpenWebUIJSONDataBuildsRawSkillRecords() async throws {
        let fixture = try SkillLibraryFixture()
        try await fixture.skillStorage.save(
            AppSkill(
                id: "bug-triage",
                name: "Bug Triage",
                content: "You are careful with bug reports.",
                description: "Triage incoming bug reports.",
                tags: ["debug", "support"],
                allowedUserIDs: ["user-id"],
                allowedGroupIDs: ["qa-team"],
                isActive: false,
                createdAt: Date(timeIntervalSince1970: 1_000),
                updatedAt: Date(timeIntervalSince1970: 2_000)
            )
        )
        let store = fixture.makeStore()
        await store.load()

        let data = try store.exportSkillsOpenWebUIJSONData()
        let records = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [[String: Any]])
        let record = try XCTUnwrap(records.first)
        let meta = try XCTUnwrap(record["meta"] as? [String: Any])
        let accessGrants = try XCTUnwrap(record["access_grants"] as? [[String: Any]])

        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(record["id"] as? String, "bug-triage")
        XCTAssertEqual(record["user_id"] as? String, store.currentUserID)
        XCTAssertEqual(record["name"] as? String, "Bug Triage")
        XCTAssertEqual(record["description"] as? String, "Triage incoming bug reports.")
        XCTAssertEqual(record["content"] as? String, "You are careful with bug reports.")
        XCTAssertEqual(meta["tags"] as? [String], ["debug", "support"])
        XCTAssertEqual(record["is_active"] as? Bool, false)
        XCTAssertEqual(accessGrants.first?["type"] as? String, "user")
        XCTAssertEqual(accessGrants.first?["id"] as? String, "user-id")
        XCTAssertEqual(accessGrants.last?["type"] as? String, "group")
        XCTAssertEqual(accessGrants.last?["id"] as? String, "qa-team")
        XCTAssertEqual(record["created_at"] as? Int, 1_000)
        XCTAssertEqual(record["updated_at"] as? Int, 2_000)
    }

    func testShareSkillSharesSelectedSkillJSON() async throws {
        let shareService = FakeSkillShareService()
        let fixture = try SkillLibraryFixture(shareService: shareService)
        let store = fixture.makeStore()
        await store.load()
        await store.createSkill(name: "Bug triage", content: "triage", description: "Debug", tags: ["debug"])
        await store.createSkill(name: "Release coach", content: "release", description: "Ship", tags: ["release"])
        let skill = try XCTUnwrap(store.skills.first { $0.name == "Bug triage" })

        store.shareSkill(skill.id)

        XCTAssertEqual(shareService.sharedTitle, "Bug triage")
        let sharedText = try XCTUnwrap(shareService.sharedText)
        let sharedSkills = try SkillExportService().skills(fromJSONData: Data(sharedText.utf8))
        XCTAssertEqual(sharedSkills.map(\.name), ["Bug triage"])
        XCTAssertEqual(sharedSkills.first?.tags, ["debug"])
    }

    func testImportSkillsJSONAcceptsOpenWebUISkillRecords() async throws {
        let fixture = try SkillLibraryFixture()
        let store = fixture.makeStore()
        await store.load()
        let data = Data(
            """
            [
              {
                "id": "bug-triage",
                "user_id": "user-id",
                "name": "Bug Triage",
                "description": "Triage incoming bug reports.",
                "content": "You are careful with bug reports.",
                "meta": {
                  "tags": ["debug", "support"]
                },
                "is_active": false,
                "access_grants": [
                  {"type": "user", "id": "user-id"},
                  {"type": "group", "id": "qa-team"}
                ],
                "created_at": 1000,
                "updated_at": 2000
              }
            ]
            """.utf8
        )

        try await store.importSkillsJSONData(data)

        let skill = try XCTUnwrap(store.skills.first)
        XCTAssertEqual(skill.id, "bug-triage")
        XCTAssertEqual(skill.name, "Bug Triage")
        XCTAssertEqual(skill.description, "Triage incoming bug reports.")
        XCTAssertEqual(skill.content, "You are careful with bug reports.")
        XCTAssertEqual(skill.tags, ["debug", "support"])
        XCTAssertEqual(skill.isActive, false)
        XCTAssertEqual(skill.allowedUserIDs, ["user-id"])
        XCTAssertEqual(skill.allowedGroupIDs, ["qa-team"])
    }
}

private struct SkillLibraryFixture {
    let rootURL: URL
    let storage: JSONStorageService
    let folderStorage: JSONFolderStorageService
    let promptStorage: JSONPromptStorageService
    let noteStorage: JSONNoteStorageService
    let toolStorage: JSONToolStorageService
    let functionStorage: JSONFunctionStorageService
    let skillStorage: JSONSkillStorageService
    let auditStorage: JSONAuditLogStorageService
    let adminStorage: JSONAdminDirectoryStorageService
    let settingsStore: SettingsStore
    let provider: (any ChatProvider)?
    let shareService: FakeSkillShareService?

    init(provider: (any ChatProvider)? = nil, shareService: FakeSkillShareService? = nil) throws {
        rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        storage = JSONStorageService(rootURL: rootURL.appendingPathComponent("Chats", isDirectory: true))
        folderStorage = JSONFolderStorageService(rootURL: rootURL.appendingPathComponent("Folders", isDirectory: true))
        promptStorage = JSONPromptStorageService(rootURL: rootURL.appendingPathComponent("Prompts", isDirectory: true))
        noteStorage = JSONNoteStorageService(rootURL: rootURL.appendingPathComponent("Notes", isDirectory: true))
        toolStorage = JSONToolStorageService(rootURL: rootURL.appendingPathComponent("Tools", isDirectory: true))
        functionStorage = JSONFunctionStorageService(
            rootURL: rootURL.appendingPathComponent("Functions", isDirectory: true)
        )
        skillStorage = JSONSkillStorageService(rootURL: rootURL.appendingPathComponent("Skills", isDirectory: true))
        auditStorage = JSONAuditLogStorageService(rootURL: rootURL.appendingPathComponent("AuditLog", isDirectory: true))
        adminStorage = JSONAdminDirectoryStorageService(
            snapshotURL: rootURL.appendingPathComponent("admin-directory.json")
        )
        settingsStore = SettingsStore(settingsURL: rootURL.appendingPathComponent("settings.json"))
        self.provider = provider
        self.shareService = shareService
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
    }

    @MainActor
    func makeStore() -> AppStore {
        AppStore(
            storage: storage,
            folderStorage: folderStorage,
            settingsStore: settingsStore,
            secretStore: InMemorySecretStore(),
            providerOverride: provider,
            shareService: shareService ?? FakeSkillShareService(),
            auditLogStorage: auditStorage,
            promptStorage: promptStorage,
            noteStorage: noteStorage,
            toolStorage: toolStorage,
            functionStorage: functionStorage,
            skillStorage: skillStorage,
            adminDirectoryStorage: adminStorage
        )
    }
}

@MainActor
private final class FakeSkillShareService: ChatSharing {
    private(set) var sharedText: String?
    private(set) var sharedTitle: String?

    func share(text: String, title: String) {
        sharedText = text
        sharedTitle = title
    }
}

private actor CapturingSkillChatProvider: ChatProvider {
    nonisolated let configuration = ProviderConfiguration.defaultOllama()
    private var capturedMessages: [ProviderChatMessage] = []

    func listModels() async throws -> [ProviderModel] {
        [ProviderModel(id: "fake-model", name: "fake-model", provider: .ollama, providerID: configuration.id)]
    }

    func healthCheck() async -> ProviderStatus {
        .available("Fake connected")
    }

    nonisolated func streamChat(model: String, messages: [ProviderChatMessage]) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task {
                await capture(messages)
                continuation.yield("answer")
                continuation.finish()
            }
        }
    }

    func createEmbeddings(model: String, input: [String]) async throws -> [[Double]] {
        []
    }

    func messages() -> [ProviderChatMessage] {
        capturedMessages
    }

    private func capture(_ messages: [ProviderChatMessage]) {
        capturedMessages = messages
    }
}
