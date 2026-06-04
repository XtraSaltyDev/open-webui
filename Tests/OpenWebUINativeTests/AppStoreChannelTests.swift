import XCTest
@testable import OpenWebUINative

@MainActor
final class AppStoreChannelTests: XCTestCase {
    func testCreateChannelPersistsAndReloads() async throws {
        let fixture = try ChannelFixture()
        let store = fixture.makeStore()
        await store.load()

        await store.createChannel(name: "Team Updates", description: "Daily planning and release notes.")

        XCTAssertEqual(store.channels.map(\.name), ["Team Updates"])
        XCTAssertEqual(store.channels.first?.description, "Daily planning and release notes.")
        XCTAssertEqual(store.selectedChannelID, store.channels.first?.id)

        let reloadedStore = fixture.makeStore()
        await reloadedStore.load()

        XCTAssertEqual(reloadedStore.channels.map(\.name), ["Team Updates"])
        XCTAssertEqual(reloadedStore.channels.first?.description, "Daily planning and release notes.")
    }

    func testPostChannelMessagePersistsUnreadAndMarksReadOnSelect() async throws {
        let fixture = try ChannelFixture()
        let store = fixture.makeStore()
        await store.load()
        await store.createChannel(name: "Research", description: nil)
        let channel = try XCTUnwrap(store.channels.first)

        await store.postChannelMessage(channel.id, content: "Summarize the native port status.")

        XCTAssertEqual(store.channels.first?.messages.map(\.content), ["Summarize the native port status."])
        XCTAssertEqual(store.channels.first?.unreadCount, 1)

        await store.selectChannel(channel.id)

        XCTAssertEqual(store.channels.first?.unreadCount, 0)
        XCTAssertNil(store.selectedThreadID)
        XCTAssertNil(store.selectedKnowledgeDocumentDetail)

        let reloadedStore = fixture.makeStore()
        await reloadedStore.load()

        XCTAssertEqual(reloadedStore.channels.first?.messages.first?.content, "Summarize the native port status.")
        XCTAssertEqual(reloadedStore.channels.first?.unreadCount, 0)
    }

    func testPostChannelReplyPersistsUnderParentMessage() async throws {
        let fixture = try ChannelFixture()
        let store = fixture.makeStore()
        await store.load()
        await store.createChannel(name: "Research", description: nil)
        let channel = try XCTUnwrap(store.channels.first)
        await store.postChannelMessage(channel.id, content: "Can we ship channel replies?")
        let message = try XCTUnwrap(store.channels.first?.messages.first)

        await store.postChannelReply(channel.id, to: message.id, content: "Yes, with local persistence first.")

        XCTAssertEqual(store.channels.first?.messages.first?.replies.map(\.content), ["Yes, with local persistence first."])
        XCTAssertEqual(store.channels.first?.unreadCount, 2)

        let reloadedStore = fixture.makeStore()
        await reloadedStore.load()

        XCTAssertEqual(reloadedStore.channels.first?.messages.first?.replies.first?.content, "Yes, with local persistence first.")
        XCTAssertEqual(reloadedStore.channels.first?.messages.first?.replies.first?.authorName, "You")
    }

    func testUpdateDeleteAndFilterChannels() async throws {
        let fixture = try ChannelFixture()
        let store = fixture.makeStore()
        await store.load()
        await store.createChannel(name: "Release", description: "Ship notes")
        await store.createChannel(name: "Design", description: "Native macOS layout")
        let release = try XCTUnwrap(store.channels.first { $0.name == "Release" })

        await store.updateChannel(release.id, name: "Release Room", description: "Production notes")

        XCTAssertEqual(store.channels.map(\.name).first, "Release Room")
        XCTAssertEqual(store.channels.first?.description, "Production notes")

        store.channelSearchText = "layout"
        XCTAssertEqual(store.filteredChannels().map(\.name), ["Design"])

        store.channelSearchText = "release"
        XCTAssertEqual(store.filteredChannels().map(\.name), ["Release Room"])

        await store.deleteChannel(release.id)

        XCTAssertEqual(store.channels.map(\.name), ["Design"])

        let reloadedStore = fixture.makeStore()
        await reloadedStore.load()
        XCTAssertEqual(reloadedStore.channels.map(\.name), ["Design"])
    }

    func testChannelLifecycleChangesCreateAuditEvents() async throws {
        let fixture = try ChannelFixture()
        let store = fixture.makeStore()
        await store.load()

        await store.createChannel(name: "Ops", description: "Deploy coordination")
        let channel = try XCTUnwrap(store.channels.first)

        await store.updateChannel(channel.id, name: "Ops Room", description: "Release coordination")
        await store.deleteChannel(channel.id)

        XCTAssertEqual(store.auditEvents.map(\.action.rawValue), [
            "channelDeleted",
            "channelUpdated",
            "channelCreated"
        ])

        let deletionEvent = try XCTUnwrap(store.auditEvents.first)
        XCTAssertEqual(deletionEvent.summary, "Deleted channel Ops Room")
        XCTAssertEqual(deletionEvent.metadata["channelID"], channel.id.uuidString)
        XCTAssertEqual(deletionEvent.metadata["name"], "Ops Room")
        XCTAssertEqual(deletionEvent.metadata["messageCount"], "0")
        XCTAssertEqual(deletionEvent.metadata["memberCount"], "0")

        let updateEvent = try XCTUnwrap(store.auditEvents.dropFirst().first)
        XCTAssertEqual(updateEvent.summary, "Updated channel Ops Room")
        XCTAssertEqual(updateEvent.metadata["previousName"], "Ops")
        XCTAssertEqual(updateEvent.metadata["name"], "Ops Room")

        let creationEvent = try XCTUnwrap(store.auditEvents.last)
        XCTAssertEqual(creationEvent.summary, "Created channel Ops")
        XCTAssertEqual(creationEvent.metadata["hasDescription"], "true")

        let reloadedEvents = try await fixture.auditStorage.loadEvents()
        XCTAssertEqual(reloadedEvents.map(\.action.rawValue), [
            "channelDeleted",
            "channelUpdated",
            "channelCreated"
        ])
    }

    func testExportAndImportChannelsJSONRoundTripsMessages() async throws {
        let fixture = try ChannelFixture()
        let store = fixture.makeStore()
        await store.load()
        await store.createChannel(name: "Team Updates", description: "Daily planning.")
        let channel = try XCTUnwrap(store.channels.first)
        await store.postChannelMessage(channel.id, content: "Ship the native channel import/export slice.")

        let data = try store.exportChannelsJSONData()

        let importFixture = try ChannelFixture()
        let importStore = importFixture.makeStore()
        await importStore.load()
        try await importStore.importChannelsJSONData(data)

        let importedChannel = try XCTUnwrap(importStore.channels.first)
        XCTAssertEqual(importedChannel.name, "Team Updates")
        XCTAssertEqual(importedChannel.description, "Daily planning.")
        XCTAssertEqual(importedChannel.unreadCount, 1)
        XCTAssertEqual(importedChannel.messages.map(\.content), ["Ship the native channel import/export slice."])
    }

    func testExportAndImportChannelsJSONRoundTripsReplies() async throws {
        let fixture = try ChannelFixture()
        let store = fixture.makeStore()
        await store.load()
        await store.createChannel(name: "Team Updates", description: "Daily planning.")
        let channel = try XCTUnwrap(store.channels.first)
        await store.postChannelMessage(channel.id, content: "Status?")
        let message = try XCTUnwrap(store.channels.first?.messages.first)
        await store.postChannelReply(channel.id, to: message.id, content: "Native channel replies are now covered.")

        let data = try store.exportChannelsJSONData()

        let importFixture = try ChannelFixture()
        let importStore = importFixture.makeStore()
        await importStore.load()
        try await importStore.importChannelsJSONData(data)

        let importedReply = try XCTUnwrap(importStore.channels.first?.messages.first?.replies.first)
        XCTAssertEqual(importedReply.content, "Native channel replies are now covered.")
        XCTAssertEqual(importedReply.authorName, "You")
    }

    func testExportChannelsOpenWebUIJSONDataBuildsRawChannelRecords() async throws {
        let fixture = try ChannelFixture()
        let store = fixture.makeStore()
        await store.load()
        await store.createChannel(name: "Team Updates", description: "Daily planning.")
        let channel = try XCTUnwrap(store.channels.first)
        await store.postChannelMessage(channel.id, content: "Ship the Open WebUI channel export.")
        let message = try XCTUnwrap(store.channels.first?.messages.first)
        await store.postChannelReply(channel.id, to: message.id, content: "Raw channel records are covered.")
        await store.addChannelMember(channel.id, userID: "user-2", displayName: "Morgan", role: .admin)

        let data = try store.exportChannelsOpenWebUIJSONData()
        let records = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [[String: Any]])
        let record = try XCTUnwrap(records.first)
        let recordData = try XCTUnwrap(record["data"] as? [String: Any])
        let messages = try XCTUnwrap(recordData["messages"] as? [[String: Any]])
        let replies = try XCTUnwrap(messages.first?["replies"] as? [[String: Any]])
        let members = try XCTUnwrap(recordData["members"] as? [[String: Any]])

        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(record["id"] as? String, channel.id.uuidString)
        XCTAssertEqual(record["user_id"] as? String, store.currentUserID)
        XCTAssertEqual(record["type"] as? String, "channel")
        XCTAssertEqual(record["name"] as? String, "Team Updates")
        XCTAssertEqual(record["description"] as? String, "Daily planning.")
        XCTAssertEqual(record["is_private"] as? Bool, false)
        XCTAssertEqual(recordData["unread_count"] as? Int, 2)
        XCTAssertEqual(messages.first?["author_name"] as? String, "You")
        XCTAssertEqual(messages.first?["content"] as? String, "Ship the Open WebUI channel export.")
        XCTAssertEqual(replies.first?["content"] as? String, "Raw channel records are covered.")
        XCTAssertEqual(members.first?["user_id"] as? String, "user-2")
        XCTAssertEqual(members.first?["display_name"] as? String, "Morgan")
        XCTAssertEqual(members.first?["role"] as? String, "admin")
        XCTAssertNotNil(record["created_at"])
        XCTAssertNotNil(record["updated_at"])
    }

    func testImportChannelsJSONAcceptsOpenWebUIChannelRecords() async throws {
        let fixture = try ChannelFixture()
        let store = fixture.makeStore()
        await store.load()
        let data = Data(
            """
            [
              {
                "id": "00000000-0000-0000-0000-000000000321",
                "user_id": "user-id",
                "type": "channel",
                "name": "Ops",
                "description": "Deploy coordination",
                "is_private": false,
                "data": {
                  "unread_count": 2,
                  "messages": [
                    {
                      "id": "00000000-0000-0000-0000-000000000654",
                      "author_name": "Alex",
                      "content": "Deploy window is open.",
                      "replies": [
                        {
                          "id": "00000000-0000-0000-0000-000000000655",
                          "author_name": "Sam",
                          "content": "Rollback plan is ready.",
                          "created_at": 3000000000000,
                          "updated_at": 4000000000000
                        }
                      ],
                      "created_at": 1000000000000,
                      "updated_at": 2000000000000
                    }
                  ]
                },
                "meta": {},
                "created_at": 1000000000000,
                "updated_at": 2000000000000
              }
            ]
            """.utf8
        )

        try await store.importChannelsJSONData(data)

        let importedChannel = try XCTUnwrap(store.channels.first)
        XCTAssertEqual(importedChannel.id.uuidString, "00000000-0000-0000-0000-000000000321")
        XCTAssertEqual(importedChannel.name, "Ops")
        XCTAssertEqual(importedChannel.description, "Deploy coordination")
        XCTAssertEqual(importedChannel.unreadCount, 2)
        XCTAssertEqual(importedChannel.createdAt, Date(timeIntervalSince1970: 1000))
        XCTAssertEqual(importedChannel.updatedAt, Date(timeIntervalSince1970: 2000))
        XCTAssertEqual(importedChannel.messages.first?.id.uuidString, "00000000-0000-0000-0000-000000000654")
        XCTAssertEqual(importedChannel.messages.first?.authorName, "Alex")
        XCTAssertEqual(importedChannel.messages.first?.content, "Deploy window is open.")
        XCTAssertEqual(importedChannel.messages.first?.replies.first?.id.uuidString, "00000000-0000-0000-0000-000000000655")
        XCTAssertEqual(importedChannel.messages.first?.replies.first?.authorName, "Sam")
        XCTAssertEqual(importedChannel.messages.first?.replies.first?.content, "Rollback plan is ready.")
    }

    func testAddUpdateAndRemoveChannelMembersPersists() async throws {
        let fixture = try ChannelFixture()
        let store = fixture.makeStore()
        await store.load()
        await store.createChannel(name: "Ops", description: "Deploy coordination")
        let channel = try XCTUnwrap(store.channels.first)

        await store.addChannelMember(
            channel.id,
            userID: " user-1 ",
            displayName: " Alex Rivera ",
            role: .admin
        )

        let member = try XCTUnwrap(store.channels.first?.members.first)
        XCTAssertEqual(member.userID, "user-1")
        XCTAssertEqual(member.displayName, "Alex Rivera")
        XCTAssertEqual(member.role, .admin)
        XCTAssertEqual(member.status, .active)

        await store.updateChannelMember(
            member.id,
            in: channel.id,
            role: .member,
            status: .inactive,
            isMuted: true,
            isPinned: true
        )

        let updatedMember = try XCTUnwrap(store.channels.first?.members.first)
        XCTAssertEqual(updatedMember.role, .member)
        XCTAssertEqual(updatedMember.status, .inactive)
        XCTAssertTrue(updatedMember.isMuted)
        XCTAssertTrue(updatedMember.isPinned)

        let reloadedStore = fixture.makeStore()
        await reloadedStore.load()
        XCTAssertEqual(reloadedStore.channels.first?.members.first?.displayName, "Alex Rivera")
        XCTAssertEqual(reloadedStore.channels.first?.members.first?.status, .inactive)

        await reloadedStore.removeChannelMember(member.id, from: channel.id)
        XCTAssertTrue(reloadedStore.channels.first?.members.isEmpty ?? false)
    }

    func testChannelMemberChangesCreateAuditEventsWithoutMessageContent() async throws {
        let fixture = try ChannelFixture()
        let store = fixture.makeStore()
        await store.load()
        await store.createChannel(name: "Ops", description: "Deploy coordination")
        let channel = try XCTUnwrap(store.channels.first)
        await store.postChannelMessage(channel.id, content: "Sensitive deployment detail.")

        await store.addChannelMember(channel.id, userID: "user-2", displayName: "Morgan Lee", role: .admin)
        let member = try XCTUnwrap(store.channels.first?.members.first)
        await store.updateChannelMember(member.id, in: channel.id, role: .member, status: .inactive, isMuted: true, isPinned: true)
        await store.removeChannelMember(member.id, from: channel.id)

        XCTAssertEqual(Array(store.auditEvents.prefix(3).map(\.action.rawValue)), [
            "channelMemberRemoved",
            "channelMemberUpdated",
            "channelMemberAdded"
        ])

        let removalEvent = try XCTUnwrap(store.auditEvents.first)
        XCTAssertEqual(removalEvent.summary, "Removed channel member from Ops")
        XCTAssertEqual(removalEvent.metadata["channelID"], channel.id.uuidString)
        XCTAssertEqual(removalEvent.metadata["channelName"], "Ops")
        XCTAssertEqual(removalEvent.metadata["memberID"], member.id)
        XCTAssertEqual(removalEvent.metadata["userID"], "user-2")
        XCTAssertFalse(removalEvent.metadata.values.contains("Sensitive deployment detail."))
        XCTAssertFalse(removalEvent.metadata.values.contains("Morgan Lee"))

        let updateEvent = try XCTUnwrap(store.auditEvents.dropFirst().first)
        XCTAssertEqual(updateEvent.summary, "Updated channel member in Ops")
        XCTAssertEqual(updateEvent.metadata["role"], ChannelMemberRole.member.rawValue)
        XCTAssertEqual(updateEvent.metadata["previousRole"], ChannelMemberRole.admin.rawValue)
        XCTAssertEqual(updateEvent.metadata["status"], ChannelMemberStatus.inactive.rawValue)
        XCTAssertEqual(updateEvent.metadata["isMuted"], "true")
        XCTAssertEqual(updateEvent.metadata["isPinned"], "true")

        let addEvent = try XCTUnwrap(store.auditEvents.dropFirst(2).first)
        XCTAssertEqual(addEvent.summary, "Added channel member to Ops")
        XCTAssertEqual(addEvent.metadata["role"], ChannelMemberRole.admin.rawValue)

        let reloadedEvents = try await fixture.auditStorage.loadEvents()
        XCTAssertEqual(Array(reloadedEvents.prefix(3).map(\.action.rawValue)), [
            "channelMemberRemoved",
            "channelMemberUpdated",
            "channelMemberAdded"
        ])
    }

    func testChannelExportAndImportRoundTripsMembers() async throws {
        let fixture = try ChannelFixture()
        let store = fixture.makeStore()
        await store.load()
        await store.createChannel(name: "Research", description: nil)
        let channel = try XCTUnwrap(store.channels.first)
        await store.addChannelMember(
            channel.id,
            userID: "user-2",
            displayName: "Morgan",
            role: .member
        )
        let member = try XCTUnwrap(store.channels.first?.members.first)
        await store.updateChannelMember(member.id, in: channel.id, role: .member, status: .active, isMuted: true, isPinned: false)

        let data = try store.exportChannelsJSONData()

        let importFixture = try ChannelFixture()
        let importStore = importFixture.makeStore()
        await importStore.load()
        try await importStore.importChannelsJSONData(data)

        let importedMember = try XCTUnwrap(importStore.channels.first?.members.first)
        XCTAssertEqual(importedMember.userID, "user-2")
        XCTAssertEqual(importedMember.displayName, "Morgan")
        XCTAssertEqual(importedMember.role, .member)
        XCTAssertTrue(importedMember.isMuted)
    }

    func testImportChannelsJSONAcceptsOpenWebUIChannelMembersInData() async throws {
        let fixture = try ChannelFixture()
        let store = fixture.makeStore()
        await store.load()
        let data = Data(
            """
            [
              {
                "id": "00000000-0000-0000-0000-000000000777",
                "user_id": "owner-id",
                "name": "Private Ops",
                "description": "Sensitive deploy coordination",
                "data": {
                  "members": [
                    {
                      "id": "member-1",
                      "user_id": "user-3",
                      "display_name": "Sam",
                      "role": "admin",
                      "status": "active",
                      "is_channel_muted": true,
                      "is_channel_pinned": true,
                      "last_read_at": 1000000000000
                    }
                  ]
                },
                "created_at": 1000000000000,
                "updated_at": 2000000000000
              }
            ]
            """.utf8
        )

        try await store.importChannelsJSONData(data)

        let importedMember = try XCTUnwrap(store.channels.first?.members.first)
        XCTAssertEqual(importedMember.id, "member-1")
        XCTAssertEqual(importedMember.userID, "user-3")
        XCTAssertEqual(importedMember.displayName, "Sam")
        XCTAssertEqual(importedMember.role, .admin)
        XCTAssertEqual(importedMember.status, .active)
        XCTAssertTrue(importedMember.isMuted)
        XCTAssertTrue(importedMember.isPinned)
        XCTAssertEqual(importedMember.lastReadAt, Date(timeIntervalSince1970: 1000))
    }

    func testChannelWritePermissionAllowsCreateUpdatePostReplyMemberDeleteAndImportForCurrentUser() async throws {
        let fixture = try ChannelFixture()
        let store = fixture.makeStore()
        await store.load()
        await store.createAdminUser(name: "Workspace User", email: "user@example.com", role: .user)
        let user = try XCTUnwrap(store.adminUsers.first)
        await store.createAdminGroup(name: "Channel Editors", description: "Can manage channels.", permissions: ["channels.write"])
        let group = try XCTUnwrap(store.adminGroups.first)
        await store.setAdminGroupMembers(group.id, memberIDs: [user.id])
        store.currentUserID = user.id

        await store.createChannel(name: "Ops", description: "Deploy coordination")
        let channel = try XCTUnwrap(store.channels.first)
        await store.updateChannel(channel.id, name: "Ops Room", description: "Release coordination")
        await store.postChannelMessage(channel.id, content: "Deploy window is open.")
        let message = try XCTUnwrap(store.channels.first?.messages.first)
        await store.postChannelReply(channel.id, to: message.id, content: "Rollback plan is ready.")
        await store.addChannelMember(channel.id, userID: "user-2", displayName: "Morgan", role: .admin)
        let member = try XCTUnwrap(store.channels.first?.members.first)
        await store.updateChannelMember(member.id, in: channel.id, role: .member, status: .inactive, isMuted: true, isPinned: true)
        await store.removeChannelMember(member.id, from: channel.id)
        await store.deleteChannel(channel.id)

        let data = try ChannelExportService().jsonData(for: [
            AppChannel(name: "Imported", description: "Imported channel.")
        ])
        try await store.importChannelsJSONData(data)

        XCTAssertEqual(store.channels.map(\.name), ["Imported"])
        XCTAssertNil(store.errorMessage)
    }

    func testChannelWritePermissionBlocksCreateUpdatePostReplyMemberDeleteAndImportForCurrentUser() async throws {
        let fixture = try ChannelFixture()
        let store = fixture.makeStore()
        await store.load()
        await store.createAdminUser(name: "Workspace User", email: "user@example.com", role: .user)
        let user = try XCTUnwrap(store.adminUsers.first)
        store.currentUserID = user.id

        await store.createChannel(name: "Blocked", description: "Should not persist.")

        XCTAssertTrue(store.channels.isEmpty)
        XCTAssertEqual(store.errorMessage, "You do not have permission to manage channels.")

        store.errorMessage = nil
        store.currentUserID = "local-admin"
        await store.createAdminUser(name: "Local Admin", email: "admin@example.com", role: .admin)
        let admin = try XCTUnwrap(store.adminUsers.first { $0.role == .admin })
        store.currentUserID = admin.id
        await store.createChannel(name: "Existing", description: "Existing channel.")
        let channel = try XCTUnwrap(store.channels.first)
        await store.postChannelMessage(channel.id, content: "Existing message.")
        let message = try XCTUnwrap(store.channels.first?.messages.first)
        await store.addChannelMember(channel.id, userID: "user-2", displayName: "Morgan", role: .admin)
        let member = try XCTUnwrap(store.channels.first?.members.first)
        let importData = try ChannelExportService().jsonData(for: [
            AppChannel(name: "Blocked Import", description: "Should not import.")
        ])

        store.currentUserID = user.id
        await store.updateChannel(channel.id, name: "Blocked update", description: "Blocked description.")
        await store.postChannelMessage(channel.id, content: "Blocked message.")
        await store.postChannelReply(channel.id, to: message.id, content: "Blocked reply.")
        await store.addChannelMember(channel.id, userID: "user-3", displayName: "Taylor", role: .member)
        await store.updateChannelMember(member.id, in: channel.id, role: .member, status: .inactive, isMuted: true, isPinned: true)
        await store.removeChannelMember(member.id, from: channel.id)
        try await store.importChannelsJSONData(importData)
        await store.deleteChannel(channel.id)

        let unchangedChannel = try XCTUnwrap(store.channels.first)
        XCTAssertEqual(store.channels.count, 1)
        XCTAssertEqual(unchangedChannel.name, "Existing")
        XCTAssertEqual(unchangedChannel.description, "Existing channel.")
        XCTAssertEqual(unchangedChannel.messages.map(\.content), ["Existing message."])
        XCTAssertTrue(unchangedChannel.messages.first?.replies.isEmpty ?? false)
        XCTAssertEqual(unchangedChannel.members.map(\.displayName), ["Morgan"])
        XCTAssertEqual(unchangedChannel.members.first?.role, .admin)
        XCTAssertEqual(unchangedChannel.members.first?.status, .active)
        XCTAssertFalse(unchangedChannel.members.first?.isMuted ?? true)
        XCTAssertFalse(unchangedChannel.members.first?.isPinned ?? true)
        XCTAssertEqual(store.errorMessage, "You do not have permission to manage channels.")

        let reloadedStore = fixture.makeStore()
        await reloadedStore.load()
        let reloadedChannel = try XCTUnwrap(reloadedStore.channels.first)
        XCTAssertEqual(reloadedStore.channels.count, 1)
        XCTAssertEqual(reloadedChannel.name, "Existing")
        XCTAssertEqual(reloadedChannel.messages.map(\.content), ["Existing message."])
        XCTAssertEqual(reloadedChannel.members.map(\.displayName), ["Morgan"])
    }

    func testCreateChannelIsBlockedWhenChannelsFeatureIsDisabled() async throws {
        let fixture = try ChannelFixture()
        let store = fixture.makeStore()
        await store.load()
        await store.setFeatureToggle(.channels, isEnabled: false)

        await store.createChannel(name: "Hidden", description: "Should not persist.")

        XCTAssertTrue(store.channels.isEmpty)
        XCTAssertNil(store.selectedChannelID)
        XCTAssertEqual(store.errorMessage, "Channels is disabled.")
        let saved = try await fixture.channelStorage.loadChannels()
        XCTAssertTrue(saved.isEmpty)
    }

    func testDisablingChannelsFeatureClearsSelectedChannelAndBlocksSelection() async throws {
        let fixture = try ChannelFixture()
        let store = fixture.makeStore()
        await store.load()
        await store.createChannel(name: "Ops", description: "Deploy coordination")
        let channel = try XCTUnwrap(store.channels.first)
        await store.postChannelMessage(channel.id, content: "Deploy window is open.")
        XCTAssertEqual(store.channels.first?.unreadCount, 1)
        XCTAssertEqual(store.selectedChannelID, channel.id)

        await store.setFeatureToggle(.channels, isEnabled: false)
        await store.selectChannel(channel.id)

        XCTAssertNil(store.selectedChannelID)
        XCTAssertEqual(store.channels.first?.unreadCount, 1)
        XCTAssertEqual(store.errorMessage, "Channels is disabled.")
        let saved = try await fixture.channelStorage.loadChannels()
        XCTAssertEqual(saved.first?.unreadCount, 1)
    }

    func testChannelMutationsAreBlockedWhenChannelsFeatureIsDisabled() async throws {
        let fixture = try ChannelFixture()
        let store = fixture.makeStore()
        await store.load()
        await store.createChannel(name: "Existing", description: "Existing channel.")
        let channel = try XCTUnwrap(store.channels.first)
        await store.postChannelMessage(channel.id, content: "Existing message.")
        let message = try XCTUnwrap(store.channels.first?.messages.first)
        await store.addChannelMember(channel.id, userID: "user-2", displayName: "Morgan", role: .admin)
        let member = try XCTUnwrap(store.channels.first?.members.first)
        await store.setFeatureToggle(.channels, isEnabled: false)

        await store.updateChannel(channel.id, name: "Blocked update", description: "Blocked description.")
        await store.postChannelMessage(channel.id, content: "Blocked message.")
        await store.postChannelReply(channel.id, to: message.id, content: "Blocked reply.")
        await store.addChannelMember(channel.id, userID: "user-3", displayName: "Taylor", role: .member)
        await store.updateChannelMember(member.id, in: channel.id, role: .member, status: .inactive, isMuted: true, isPinned: true)
        await store.removeChannelMember(member.id, from: channel.id)
        await store.deleteChannel(channel.id)

        let unchangedChannel = try XCTUnwrap(store.channels.first)
        XCTAssertEqual(store.channels.count, 1)
        XCTAssertEqual(unchangedChannel.name, "Existing")
        XCTAssertEqual(unchangedChannel.description, "Existing channel.")
        XCTAssertEqual(unchangedChannel.messages.map(\.content), ["Existing message."])
        XCTAssertTrue(unchangedChannel.messages.first?.replies.isEmpty ?? false)
        XCTAssertEqual(unchangedChannel.members.map(\.displayName), ["Morgan"])
        XCTAssertEqual(unchangedChannel.members.first?.role, .admin)
        XCTAssertEqual(unchangedChannel.members.first?.status, .active)
        XCTAssertFalse(unchangedChannel.members.first?.isMuted ?? true)
        XCTAssertFalse(unchangedChannel.members.first?.isPinned ?? true)
        XCTAssertEqual(store.errorMessage, "Channels is disabled.")

        let saved = try await fixture.channelStorage.loadChannels()
        let savedChannel = try XCTUnwrap(saved.first)
        XCTAssertEqual(saved.count, 1)
        XCTAssertEqual(savedChannel.name, "Existing")
        XCTAssertEqual(savedChannel.messages.map(\.content), ["Existing message."])
        XCTAssertEqual(savedChannel.members.map(\.displayName), ["Morgan"])
    }

    func testImportChannelsJSONIsBlockedWhenChannelsFeatureIsDisabled() async throws {
        let sourceFixture = try ChannelFixture()
        let sourceStore = sourceFixture.makeStore()
        await sourceStore.load()
        await sourceStore.createChannel(name: "Imported", description: "Imported channel.")
        let data = try sourceStore.exportChannelsJSONData()

        let fixture = try ChannelFixture()
        let store = fixture.makeStore()
        await store.load()
        await store.setFeatureToggle(.channels, isEnabled: false)

        try await store.importChannelsJSONData(data)

        XCTAssertTrue(store.channels.isEmpty)
        XCTAssertEqual(store.errorMessage, "Channels is disabled.")
        let saved = try await fixture.channelStorage.loadChannels()
        XCTAssertTrue(saved.isEmpty)
    }

    func testUnmanagedLocalUserCanManageChannelsWhenAdminDirectoryExists() async throws {
        let fixture = try ChannelFixture()
        let store = fixture.makeStore()
        await store.load()
        await store.createAdminUser(name: "Workspace User", email: "user@example.com", role: .user)

        await store.createChannel(name: "Local", description: "Local channel.")

        XCTAssertEqual(store.channels.map(\.name), ["Local"])
        XCTAssertNil(store.errorMessage)
    }
}

private struct ChannelFixture {
    let rootURL: URL
    let storage: JSONStorageService
    let folderStorage: JSONFolderStorageService
    let promptStorage: JSONPromptStorageService
    let noteStorage: JSONNoteStorageService
    let channelStorage: JSONChannelStorageService
    let adminStorage: JSONAdminDirectoryStorageService
    let settingsStore: SettingsStore
    let auditStorage: JSONAuditLogStorageService

    init() throws {
        rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        storage = JSONStorageService(rootURL: rootURL.appendingPathComponent("Chats", isDirectory: true))
        folderStorage = JSONFolderStorageService(rootURL: rootURL.appendingPathComponent("Folders", isDirectory: true))
        promptStorage = JSONPromptStorageService(rootURL: rootURL.appendingPathComponent("Prompts", isDirectory: true))
        noteStorage = JSONNoteStorageService(rootURL: rootURL.appendingPathComponent("Notes", isDirectory: true))
        channelStorage = JSONChannelStorageService(rootURL: rootURL.appendingPathComponent("Channels", isDirectory: true))
        adminStorage = JSONAdminDirectoryStorageService(
            snapshotURL: rootURL.appendingPathComponent("admin-directory.json")
        )
        settingsStore = SettingsStore(settingsURL: rootURL.appendingPathComponent("settings.json"))
        auditStorage = JSONAuditLogStorageService(rootURL: rootURL.appendingPathComponent("AuditLog", isDirectory: true))
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
    }

    @MainActor
    func makeStore() -> AppStore {
        AppStore(
            storage: storage,
            folderStorage: folderStorage,
            settingsStore: settingsStore,
            secretStore: InMemorySecretStore(),
            auditLogStorage: auditStorage,
            promptStorage: promptStorage,
            noteStorage: noteStorage,
            adminDirectoryStorage: adminStorage,
            channelStorage: channelStorage
        )
    }
}
