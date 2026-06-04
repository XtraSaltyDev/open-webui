import XCTest
@testable import OpenWebUINative

@MainActor
final class AppStorePromptLibraryTests: XCTestCase {
    func testCreatePromptPersistsAndInsertsIntoDraft() async throws {
        let fixture = try PromptLibraryFixture()
        let store = fixture.makeStore()
        await store.load()

        await store.createPrompt(
            title: "Bug triage",
            content: "Summarize this bug report.",
            command: "/triage",
            tags: ["debug", " Debug ", "", "triage"]
        )

        XCTAssertEqual(store.prompts.map(\.title), ["Bug triage"])
        XCTAssertEqual(store.prompts.first?.content, "Summarize this bug report.")
        XCTAssertEqual(store.prompts.first?.command, "/triage")
        XCTAssertEqual(store.prompts.first?.tags, ["debug", "triage"])

        let reloadedStore = fixture.makeStore()
        await reloadedStore.load()

        let prompt = try XCTUnwrap(reloadedStore.prompts.first)
        XCTAssertEqual(prompt.command, "/triage")
        XCTAssertEqual(prompt.tags, ["debug", "triage"])
        reloadedStore.draftPrompt = "Existing context"
        reloadedStore.insertPrompt(prompt.id)

        XCTAssertEqual(reloadedStore.draftPrompt, "Existing context\n\nSummarize this bug report.")
    }

    func testCreatePromptCreatesAuditEvent() async throws {
        let fixture = try PromptLibraryFixture()
        let store = fixture.makeStore()
        await store.load()

        await store.createPrompt(
            title: "Bug triage",
            content: "Summarize this bug report.",
            command: "/triage",
            tags: ["debug", "triage"]
        )

        let prompt = try XCTUnwrap(store.prompts.first)
        let event = try XCTUnwrap(store.auditEvents.first { $0.action.rawValue == "promptCreated" })
        XCTAssertEqual(event.action.rawValue, "promptCreated")
        XCTAssertEqual(event.outcome, .succeeded)
        XCTAssertEqual(event.metadata["promptID"], prompt.id.uuidString)
        XCTAssertEqual(event.metadata["title"], "Bug triage")
        XCTAssertEqual(event.metadata["command"], "/triage")
        XCTAssertEqual(event.metadata["tags"], "debug, triage")

        let reloadedStore = fixture.makeStore()
        await reloadedStore.load()
        XCTAssertEqual(reloadedStore.auditEvents.first?.action.rawValue, "promptCreated")
        XCTAssertEqual(reloadedStore.auditEvents.first?.metadata["promptID"], prompt.id.uuidString)
    }

    func testInsertPromptResolvesVariablesIntoDraft() async throws {
        let fixture = try PromptLibraryFixture()
        let store = fixture.makeStore()
        await store.load()
        await store.createPrompt(title: "Audience brief", content: "Explain {{topic}} for {{ audience }}.")
        let prompt = try XCTUnwrap(store.prompts.first)
        store.draftPrompt = "Existing context"

        store.insertPrompt(
            prompt.id,
            variableValues: [
                "topic": "SwiftUI state",
                "audience": "new engineers"
            ]
        )

        XCTAssertEqual(store.draftPrompt, "Existing context\n\nExplain SwiftUI state for new engineers.")
        XCTAssertNil(store.errorMessage)
    }

    func testInsertPromptWithMissingVariableShowsErrorAndKeepsDraft() async throws {
        let fixture = try PromptLibraryFixture()
        let store = fixture.makeStore()
        await store.load()
        await store.createPrompt(title: "Audience brief", content: "Explain {{topic}} for {{ audience }}.")
        let prompt = try XCTUnwrap(store.prompts.first)
        store.draftPrompt = "Existing context"

        store.insertPrompt(prompt.id, variableValues: ["topic": "SwiftUI state"])

        XCTAssertEqual(store.draftPrompt, "Existing context")
        XCTAssertEqual(store.errorMessage, "Missing prompt variable values: audience")
    }

    func testUpdatePromptTrimsInputAndSortsMostRecentlyUpdatedFirst() async throws {
        let fixture = try PromptLibraryFixture()
        let store = fixture.makeStore()
        await store.load()

        await store.createPrompt(title: "First", content: "First content")
        await store.createPrompt(title: "Second", content: "Second content")
        let firstPrompt = try XCTUnwrap(store.prompts.first { $0.title == "First" })

        await store.updatePrompt(
            firstPrompt.id,
            title: "  Updated first  ",
            content: "  Better content  ",
            command: " first-summary ",
            tags: [" Release Notes ", "release notes", "summary"]
        )

        XCTAssertEqual(store.prompts.map(\.title), ["Updated first", "Second"])
        XCTAssertEqual(store.prompts.first?.content, "Better content")
        XCTAssertEqual(store.prompts.first?.command, "/first-summary")
        XCTAssertEqual(store.prompts.first?.tags, ["Release Notes", "summary"])
    }

    func testUpdatePromptCreatesAuditEvent() async throws {
        let fixture = try PromptLibraryFixture()
        let store = fixture.makeStore()
        await store.load()
        await store.createPrompt(title: "First", content: "First content", command: "/first")
        let prompt = try XCTUnwrap(store.prompts.first)

        await store.updatePrompt(
            prompt.id,
            title: "Updated first",
            content: "Better content",
            command: "/updated",
            tags: ["summary"]
        )

        let event = try XCTUnwrap(store.auditEvents.first { $0.action.rawValue == "promptUpdated" })
        XCTAssertEqual(event.action.rawValue, "promptUpdated")
        XCTAssertEqual(event.outcome, .succeeded)
        XCTAssertEqual(event.metadata["promptID"], prompt.id.uuidString)
        XCTAssertEqual(event.metadata["fromTitle"], "First")
        XCTAssertEqual(event.metadata["title"], "Updated first")
        XCTAssertEqual(event.metadata["command"], "/updated")
        XCTAssertEqual(event.metadata["tags"], "summary")
    }

    func testUpdatePromptAppendsPreviousVersionSnapshot() async throws {
        let fixture = try PromptLibraryFixture()
        let store = fixture.makeStore()
        await store.load()

        await store.createPrompt(
            title: "Bug triage",
            content: "Summarize this bug report.",
            command: "/triage",
            tags: ["debug"],
            allowedUserIDs: ["user-id"],
            allowedGroupIDs: ["qa-team"]
        )
        let originalPrompt = try XCTUnwrap(store.prompts.first)

        await store.updatePrompt(
            originalPrompt.id,
            title: "Updated triage",
            content: "Summarize this bug and the next steps.",
            command: "/triage-updated",
            tags: ["debug", "release"],
            allowedUserIDs: ["user-id", "reviewer-id"],
            allowedGroupIDs: ["qa-team", "ops-team"]
        )

        let updatedPrompt = try XCTUnwrap(store.prompts.first)
        XCTAssertEqual(updatedPrompt.versions.count, 1)
        let version = try XCTUnwrap(updatedPrompt.versions.first)
        XCTAssertEqual(version.title, originalPrompt.title)
        XCTAssertEqual(version.content, originalPrompt.content)
        XCTAssertEqual(version.command, originalPrompt.command)
        XCTAssertEqual(version.tags, originalPrompt.tags)
        XCTAssertEqual(version.allowedUserIDs, originalPrompt.allowedUserIDs)
        XCTAssertEqual(version.allowedGroupIDs, originalPrompt.allowedGroupIDs)
        XCTAssertEqual(version.createdAt, originalPrompt.createdAt)
        XCTAssertEqual(version.updatedAt, originalPrompt.updatedAt)
    }

    func testDeletePromptRemovesItFromStorage() async throws {
        let fixture = try PromptLibraryFixture()
        let store = fixture.makeStore()
        await store.load()
        await store.createPrompt(title: "Temporary", content: "Use once.")
        let prompt = try XCTUnwrap(store.prompts.first)

        await store.deletePrompt(prompt.id)

        let reloadedStore = fixture.makeStore()
        await reloadedStore.load()
        XCTAssertTrue(reloadedStore.prompts.isEmpty)
    }

    func testDeletePromptCreatesAuditEvent() async throws {
        let fixture = try PromptLibraryFixture()
        let store = fixture.makeStore()
        await store.load()
        await store.createPrompt(title: "Temporary", content: "Use once.", command: "/temp", tags: ["cleanup"])
        let prompt = try XCTUnwrap(store.prompts.first)

        await store.deletePrompt(prompt.id)

        let event = try XCTUnwrap(store.auditEvents.first { $0.action.rawValue == "promptDeleted" })
        XCTAssertEqual(event.action.rawValue, "promptDeleted")
        XCTAssertEqual(event.outcome, .succeeded)
        XCTAssertEqual(event.metadata["promptID"], prompt.id.uuidString)
        XCTAssertEqual(event.metadata["title"], "Temporary")
        XCTAssertEqual(event.metadata["command"], "/temp")
        XCTAssertEqual(event.metadata["tags"], "cleanup")

        let reloadedStore = fixture.makeStore()
        await reloadedStore.load()
        let reloadedEvent = try XCTUnwrap(reloadedStore.auditEvents.first { $0.action.rawValue == "promptDeleted" })
        XCTAssertEqual(reloadedEvent.metadata["promptID"], prompt.id.uuidString)
    }

    func testExportAndImportPromptsJSONRoundTripsPromptLibrary() async throws {
        let fixture = try PromptLibraryFixture()
        let store = fixture.makeStore()
        await store.load()
        await store.createPrompt(title: "Bug triage", content: "Summarize this bug.", tags: ["debug", "triage"])
        await store.createPrompt(title: "Release notes", content: "Draft release notes.")

        let data = try store.exportPromptsJSONData()

        let importFixture = try PromptLibraryFixture()
        let importStore = importFixture.makeStore()
        await importStore.load()
        try await importStore.importPromptsJSONData(data)

        XCTAssertEqual(Set(importStore.prompts.map(\.title)), ["Bug triage", "Release notes"])
        XCTAssertEqual(importStore.prompts.first { $0.title == "Bug triage" }?.content, "Summarize this bug.")
        XCTAssertEqual(importStore.prompts.first { $0.title == "Bug triage" }?.tags, ["debug", "triage"])
    }

    func testExportPromptsOpenWebUIJSONDataBuildsRawPromptRecords() async throws {
        let fixture = try PromptLibraryFixture()
        let store = fixture.makeStore()
        await store.load()
        await store.createPrompt(
            title: "Bug triage",
            content: "Summarize this bug.",
            command: "/triage",
            tags: ["debug", "triage"]
        )

        let data = try store.exportPromptsOpenWebUIJSONData()
        let records = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [[String: Any]])
        let record = try XCTUnwrap(records.first)

        XCTAssertEqual(records.count, 1)
        XCTAssertNil(record["format"])
        XCTAssertEqual(record["command"] as? String, "/triage")
        XCTAssertEqual(record["name"] as? String, "Bug triage")
        XCTAssertEqual(record["content"] as? String, "Summarize this bug.")
        XCTAssertEqual(record["tags"] as? [String], ["debug", "triage"])
        XCTAssertEqual(record["is_active"] as? Bool, true)
        XCTAssertEqual(record["user_id"] as? String, "local-user")
        XCTAssertNotNil(record["created_at"] as? Int)
        XCTAssertNotNil(record["updated_at"] as? Int)
        XCTAssertNil(record["createdAt"])
        XCTAssertNil(record["updatedAt"])
    }

    func testNativePromptJSONRoundTripsAccessGrants() async throws {
        let fixture = try PromptLibraryFixture()
        let store = fixture.makeStore()
        await store.load()
        let data = Data(
            """
            {
              "format": "open-webui-native-prompts",
              "version": 1,
              "exportedAt": "2026-06-03T00:00:00Z",
              "prompts": [
                {
                  "id": "11111111-1111-1111-1111-111111111111",
                  "title": "Bug triage",
                  "content": "Summarize this bug.",
                  "command": "/triage",
                  "tags": ["debug"],
                  "allowedUserIDs": ["user-id"],
                  "allowedGroupIDs": ["qa-team"],
                  "createdAt": "2026-06-03T00:00:00Z",
                  "updatedAt": "2026-06-03T00:00:00Z"
                }
              ]
            }
            """.utf8
        )

        try await store.importPromptsJSONData(data)

        let exportedData = try store.exportPromptsJSONData()
        let exportedBundle = try XCTUnwrap(JSONSerialization.jsonObject(with: exportedData) as? [String: Any])
        let exportedPrompts = try XCTUnwrap(exportedBundle["prompts"] as? [[String: Any]])
        let exportedPrompt = try XCTUnwrap(exportedPrompts.first)
        XCTAssertEqual(exportedPrompt["allowedUserIDs"] as? [String], ["user-id"])
        XCTAssertEqual(exportedPrompt["allowedGroupIDs"] as? [String], ["qa-team"])
    }

    func testNativePromptJSONRoundTripsVersionHistory() async throws {
        let fixture = try PromptLibraryFixture()
        let store = fixture.makeStore()
        await store.load()

        await store.createPrompt(
            title: "Bug triage",
            content: "Summarize this bug report.",
            command: "/triage",
            tags: ["debug"],
            allowedUserIDs: ["user-id"],
            allowedGroupIDs: ["qa-team"]
        )
        let originalPrompt = try XCTUnwrap(store.prompts.first)
        await store.updatePrompt(
            originalPrompt.id,
            title: "Updated triage",
            content: "Summarize this bug and the next steps.",
            command: "/triage-updated",
            tags: ["debug", "release"],
            allowedUserIDs: ["user-id", "reviewer-id"],
            allowedGroupIDs: ["qa-team", "ops-team"]
        )

        let data = try store.exportPromptsJSONData()

        let importFixture = try PromptLibraryFixture()
        let importStore = importFixture.makeStore()
        await importStore.load()
        try await importStore.importPromptsJSONData(data)

        let importedPrompt = try XCTUnwrap(importStore.prompts.first)
        XCTAssertEqual(importedPrompt.title, "Updated triage")
        XCTAssertEqual(importedPrompt.versions.count, 1)
        let version = try XCTUnwrap(importedPrompt.versions.first)
        XCTAssertEqual(version.title, "Bug triage")
        XCTAssertEqual(version.content, "Summarize this bug report.")
        XCTAssertEqual(version.command, "/triage")
        XCTAssertEqual(version.tags, ["debug"])
        XCTAssertEqual(version.allowedUserIDs, ["user-id"])
        XCTAssertEqual(version.allowedGroupIDs, ["qa-team"])
    }

    func testImportPromptsJSONAcceptsVersionHistoryShape() async throws {
        let fixture = try PromptLibraryFixture()
        let store = fixture.makeStore()
        await store.load()
        let data = Data(
            """
            [
              {
                "id": "11111111-1111-1111-1111-111111111111",
                "command": "/triage",
                "name": "Bug triage",
                "content": "Summarize this bug report.",
                "tags": ["debug"],
                "is_active": true,
                "version_history": [
                  {
                    "title": "Bug triage",
                    "content": "Old content.",
                    "command": "/triage",
                    "tags": ["debug"],
                    "allowedUserIDs": ["user-id"],
                    "allowedGroupIDs": ["qa-team"],
                    "createdAt": "2026-06-03T00:00:00Z",
                    "updatedAt": "2026-06-03T00:01:00Z"
                  }
                ],
                "created_at": 1000,
                "updated_at": 2000
              }
            ]
            """.utf8
        )

        try await store.importPromptsJSONData(data)

        let prompt = try XCTUnwrap(store.prompts.first)
        XCTAssertEqual(prompt.title, "Bug triage")
        XCTAssertEqual(prompt.versions.count, 1)
        XCTAssertEqual(prompt.versions.first?.title, "Bug triage")
        XCTAssertEqual(prompt.versions.first?.content, "Old content.")
        XCTAssertEqual(prompt.versions.first?.allowedUserIDs, ["user-id"])
        XCTAssertEqual(prompt.versions.first?.allowedGroupIDs, ["qa-team"])
    }

    func testImportPromptsJSONAcceptsOpenWebUIPromptAccessGrants() async throws {
        let fixture = try PromptLibraryFixture()
        let store = fixture.makeStore()
        await store.load()
        let data = Data(
            """
            [
              {
                "id": "11111111-1111-1111-1111-111111111111",
                "user_id": "user-id",
                "command": "/triage",
                "name": "Bug triage",
                "content": "Summarize this bug.",
                "tags": ["debug"],
                "is_active": true,
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

        try await store.importPromptsJSONData(data)

        let exportedData = try store.exportPromptsOpenWebUIJSONData()
        let records = try XCTUnwrap(JSONSerialization.jsonObject(with: exportedData) as? [[String: Any]])
        let record = try XCTUnwrap(records.first)
        let accessGrants = try XCTUnwrap(record["access_grants"] as? [[String: Any]])
        XCTAssertEqual(accessGrants.first?["type"] as? String, "user")
        XCTAssertEqual(accessGrants.first?["id"] as? String, "user-id")
        XCTAssertEqual(accessGrants.last?["type"] as? String, "group")
        XCTAssertEqual(accessGrants.last?["id"] as? String, "qa-team")
    }

    func testExportPromptsJSONForUserActionCreatesAuditEventWithoutPromptContent() async throws {
        let fixture = try PromptLibraryFixture()
        let store = fixture.makeStore()
        await store.load()
        await store.createPrompt(
            title: "Sensitive prompt title",
            content: "Sensitive reusable instruction",
            command: "/sensitive",
            tags: ["private-tag"]
        )

        let data = try await store.exportPromptsJSONDataForUserAction()

        let importFixture = try PromptLibraryFixture()
        let importStore = importFixture.makeStore()
        await importStore.load()
        try await importStore.importPromptsJSONData(data)
        XCTAssertEqual(importStore.prompts.count, 1)
        XCTAssertEqual(importStore.prompts.first?.content, "Sensitive reusable instruction")
        let event = try XCTUnwrap(store.auditEvents.first(where: { $0.action == .promptsExported }))
        XCTAssertEqual(event.outcome, .succeeded)
        XCTAssertEqual(event.summary, "Exported prompt library")
        XCTAssertEqual(event.metadata["exportedPromptCount"], "1")
        XCTAssertEqual(event.metadata["exportedCommandPromptCount"], "1")
        XCTAssertEqual(event.metadata["exportedTaggedPromptCount"], "1")
        XCTAssertNil(event.metadata["title"])
        XCTAssertNil(event.metadata["content"])
        XCTAssertNil(event.metadata["command"])
        XCTAssertNil(event.metadata["tags"])
        XCTAssertFalse(event.metadata.values.contains("Sensitive prompt title"))
        XCTAssertFalse(event.metadata.values.contains("Sensitive reusable instruction"))
        XCTAssertFalse(event.metadata.values.contains("/sensitive"))
        XCTAssertFalse(event.metadata.values.contains("private-tag"))
    }

    func testExportPromptsOpenWebUIJSONForUserActionCreatesAuditEventWithoutPromptContent() async throws {
        let fixture = try PromptLibraryFixture()
        let store = fixture.makeStore()
        await store.load()
        await store.createPrompt(
            title: "Sensitive prompt title",
            content: "Sensitive reusable instruction",
            command: "/sensitive",
            tags: ["private-tag"]
        )

        let data = try await store.exportPromptsOpenWebUIJSONDataForUserAction()
        let records = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [[String: Any]])

        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records.first?["content"] as? String, "Sensitive reusable instruction")
        let event = try XCTUnwrap(store.auditEvents.first(where: { $0.action == .promptsExported }))
        XCTAssertEqual(event.outcome, .succeeded)
        XCTAssertEqual(event.summary, "Exported Open WebUI prompt records")
        XCTAssertEqual(event.metadata["exportedPromptCount"], "1")
        XCTAssertEqual(event.metadata["exportedCommandPromptCount"], "1")
        XCTAssertEqual(event.metadata["exportedTaggedPromptCount"], "1")
        XCTAssertEqual(event.metadata["format"], "open-webui")
        XCTAssertNil(event.metadata["title"])
        XCTAssertNil(event.metadata["content"])
        XCTAssertNil(event.metadata["command"])
        XCTAssertNil(event.metadata["tags"])
        XCTAssertFalse(event.metadata.values.contains("Sensitive prompt title"))
        XCTAssertFalse(event.metadata.values.contains("Sensitive reusable instruction"))
        XCTAssertFalse(event.metadata.values.contains("/sensitive"))
        XCTAssertFalse(event.metadata.values.contains("private-tag"))
    }

    func testImportPromptsJSONForUserActionCreatesAuditEventWithoutPromptContent() async throws {
        let fixture = try PromptLibraryFixture()
        let sourceStore = fixture.makeStore()
        await sourceStore.load()
        await sourceStore.createPrompt(
            title: "Imported prompt title",
            content: "Imported reusable instruction",
            command: "/imported",
            tags: ["import-tag"]
        )
        let data = try sourceStore.exportPromptsJSONData()

        let importFixture = try PromptLibraryFixture()
        let importStore = importFixture.makeStore()
        await importStore.load()
        try await importStore.importPromptsJSONDataForUserAction(data)

        XCTAssertEqual(importStore.prompts.count, 1)
        XCTAssertEqual(importStore.prompts.first?.content, "Imported reusable instruction")
        let event = try XCTUnwrap(importStore.auditEvents.first(where: { $0.action == .promptsImported }))
        XCTAssertEqual(event.outcome, .succeeded)
        XCTAssertEqual(event.summary, "Imported prompt library")
        XCTAssertEqual(event.metadata["importedPromptCount"], "1")
        XCTAssertEqual(event.metadata["importedCommandPromptCount"], "1")
        XCTAssertEqual(event.metadata["importedTaggedPromptCount"], "1")
        XCTAssertEqual(event.metadata["totalPromptCount"], "1")
        XCTAssertNil(event.metadata["title"])
        XCTAssertNil(event.metadata["content"])
        XCTAssertNil(event.metadata["command"])
        XCTAssertNil(event.metadata["tags"])
        XCTAssertFalse(event.metadata.values.contains("Imported prompt title"))
        XCTAssertFalse(event.metadata.values.contains("Imported reusable instruction"))
        XCTAssertFalse(event.metadata.values.contains("/imported"))
        XCTAssertFalse(event.metadata.values.contains("import-tag"))
    }

    func testAuditMetadataFormatterPromotesPromptTransferRows() {
        let event = AppAuditEvent(
            action: .promptsImported,
            outcome: .succeeded,
            summary: "Imported prompt library",
            metadata: [
                "importedPromptCount": "5",
                "importedCommandPromptCount": "3",
                "importedTaggedPromptCount": "4",
                "totalPromptCount": "8"
            ]
        )

        let rows = AuditEventMetadataFormatter.rows(for: event)

        XCTAssertEqual(
            rows.map(\.label),
            ["Prompts", "Slash Commands", "Tagged Prompts", "Total Prompts"]
        )
        XCTAssertEqual(rows.map(\.value), ["5", "3", "4", "8"])
    }

    func testExportPromptJSONDataExportsOnlySelectedPrompt() async throws {
        let fixture = try PromptLibraryFixture()
        let store = fixture.makeStore()
        await store.load()
        await store.createPrompt(title: "Bug triage", content: "Summarize this bug.", tags: ["debug"])
        await store.createPrompt(title: "Release notes", content: "Draft release notes.")
        let prompt = try XCTUnwrap(store.prompts.first { $0.title == "Bug triage" })

        let data = try XCTUnwrap(store.exportPromptJSONData(prompt.id))

        let importFixture = try PromptLibraryFixture()
        let importStore = importFixture.makeStore()
        await importStore.load()
        try await importStore.importPromptsJSONData(data)

        XCTAssertEqual(importStore.prompts.map(\.title), ["Bug triage"])
        XCTAssertEqual(importStore.prompts.first?.content, "Summarize this bug.")
        XCTAssertEqual(importStore.prompts.first?.tags, ["debug"])
    }

    func testSharePromptSharesSelectedPromptJSON() async throws {
        let shareService = FakePromptShareService()
        let fixture = try PromptLibraryFixture(shareService: shareService)
        let store = fixture.makeStore()
        await store.load()
        await store.createPrompt(title: "Bug triage", content: "Summarize this bug.", command: "/triage")
        await store.createPrompt(title: "Release notes", content: "Draft release notes.")
        let prompt = try XCTUnwrap(store.prompts.first { $0.title == "Bug triage" })

        store.sharePrompt(prompt.id)

        XCTAssertEqual(shareService.sharedTitle, "Bug triage")
        let sharedText = try XCTUnwrap(shareService.sharedText)
        let sharedPrompts = try PromptExportService().prompts(fromJSONData: Data(sharedText.utf8))
        XCTAssertEqual(sharedPrompts.map(\.title), ["Bug triage"])
        XCTAssertEqual(sharedPrompts.first?.command, "/triage")
    }

    func testImportPromptsJSONAcceptsOpenWebUIPromptRecords() async throws {
        let fixture = try PromptLibraryFixture()
        let store = fixture.makeStore()
        await store.load()
        let data = Data(
            """
            [
              {
                "id": "open-webui-prompt-id",
                "command": "/triage",
                "user_id": "user-id",
                "name": "Bug triage",
                "content": "Summarize this bug report.",
                "data": {},
                "meta": {},
                "tags": ["debug", null, " debug ", "", "triage"],
                "is_active": true,
                "created_at": 1000,
                "updated_at": 2000
              }
            ]
            """.utf8
        )

        try await store.importPromptsJSONData(data)

        XCTAssertEqual(store.prompts.first?.title, "Bug triage")
        XCTAssertEqual(store.prompts.first?.content, "Summarize this bug report.")
        XCTAssertEqual(store.prompts.first?.command, "/triage")
        XCTAssertEqual(store.prompts.first?.tags, ["debug", "triage"])
    }

    func testCreatePromptIsBlockedWhenPromptsFeatureIsDisabled() async throws {
        let fixture = try PromptLibraryFixture()
        let store = fixture.makeStore()
        await store.load()
        await store.setFeatureToggle(.prompts, isEnabled: false)

        await store.createPrompt(title: "Hidden prompt", content: "Should not persist.", command: "/hidden")

        XCTAssertTrue(store.prompts.isEmpty)
        XCTAssertEqual(store.errorMessage, "Prompts is disabled.")
        let saved = try await fixture.promptStorage.loadPrompts()
        XCTAssertTrue(saved.isEmpty)
    }

    func testUpdateAndDeletePromptAreBlockedWhenPromptsFeatureIsDisabled() async throws {
        let fixture = try PromptLibraryFixture()
        let store = fixture.makeStore()
        await store.load()
        await store.createPrompt(title: "Existing prompt", content: "Existing content.", command: "/existing")
        let prompt = try XCTUnwrap(store.prompts.first)
        await store.setFeatureToggle(.prompts, isEnabled: false)

        await store.updatePrompt(prompt.id, title: "Blocked update", content: "Blocked content.")
        await store.deletePrompt(prompt.id)

        XCTAssertEqual(store.prompts.map(\.title), ["Existing prompt"])
        XCTAssertEqual(store.prompts.first?.content, "Existing content.")
        XCTAssertEqual(store.errorMessage, "Prompts is disabled.")
        let saved = try await fixture.promptStorage.loadPrompts()
        XCTAssertEqual(saved.map(\.title), ["Existing prompt"])
    }

    func testImportPromptsJSONIsBlockedWhenPromptsFeatureIsDisabled() async throws {
        let sourceFixture = try PromptLibraryFixture()
        let sourceStore = sourceFixture.makeStore()
        await sourceStore.load()
        await sourceStore.createPrompt(title: "Imported prompt", content: "Reusable instruction.", command: "/imported")
        let data = try sourceStore.exportPromptsJSONData()

        let fixture = try PromptLibraryFixture()
        let store = fixture.makeStore()
        await store.load()
        await store.setFeatureToggle(.prompts, isEnabled: false)

        try await store.importPromptsJSONData(data)
        await store.importPromptsJSON(from: fixture.rootURL.appendingPathComponent("missing-prompts.json"))

        XCTAssertTrue(store.prompts.isEmpty)
        XCTAssertEqual(store.errorMessage, "Prompts is disabled.")
        let saved = try await fixture.promptStorage.loadPrompts()
        XCTAssertTrue(saved.isEmpty)
    }

    func testPromptInsertionAndSlashCommandLookupAreBlockedWhenPromptsFeatureIsDisabled() async throws {
        let fixture = try PromptLibraryFixture()
        let store = fixture.makeStore()
        await store.load()
        await store.createPrompt(title: "Bug triage", content: "Summarize this bug.", command: "/triage")
        let prompt = try XCTUnwrap(store.prompts.first)
        await store.setFeatureToggle(.prompts, isEnabled: false)
        store.draftPrompt = "Existing draft"

        XCTAssertNil(store.prompt(matchingCommand: "/triage"))
        store.insertPrompt(prompt.id)

        XCTAssertEqual(store.draftPrompt, "Existing draft")
        XCTAssertEqual(store.errorMessage, "Prompts is disabled.")
    }

    func testSharePromptIsBlockedWhenPromptsFeatureIsDisabled() async throws {
        let shareService = FakePromptShareService()
        let fixture = try PromptLibraryFixture(shareService: shareService)
        let store = fixture.makeStore()
        await store.load()
        await store.createPrompt(title: "Existing prompt", content: "Existing content.", command: "/existing")
        let prompt = try XCTUnwrap(store.prompts.first)
        await store.setFeatureToggle(.prompts, isEnabled: false)

        store.sharePrompt(prompt.id)

        XCTAssertNil(shareService.sharedTitle)
        XCTAssertNil(shareService.sharedText)
        XCTAssertEqual(store.errorMessage, "Prompts is disabled.")
    }

    func testSendDraftPromptExpandsMatchingSlashCommandWithoutSending() async throws {
        let fixture = try PromptLibraryFixture()
        let store = fixture.makeStore()
        await store.load()
        await store.createPrompt(title: "Bug triage", content: "Summarize this bug report.", command: "/triage")
        store.draftPrompt = "/triage"

        await store.sendDraftPrompt()

        XCTAssertEqual(store.draftPrompt, "Summarize this bug report.")
        XCTAssertTrue(store.threads.isEmpty)
    }

    func testSendDraftPromptCommandWithVariablesShowsErrorAndKeepsDraft() async throws {
        let fixture = try PromptLibraryFixture()
        let store = fixture.makeStore()
        await store.load()
        await store.createPrompt(title: "Explain topic", content: "Explain {{topic}}.", command: "/explain")
        store.draftPrompt = "/explain"

        await store.sendDraftPrompt()

        XCTAssertEqual(store.draftPrompt, "/explain")
        XCTAssertEqual(
            store.errorMessage,
            "Prompt command /explain requires variable values. Insert it from the prompt library."
        )
        XCTAssertTrue(store.threads.isEmpty)
    }

    func testPromptWritePermissionAllowsCreateUpdateAndDeleteForCurrentUser() async throws {
        let fixture = try PromptLibraryFixture()
        let store = fixture.makeStore()
        await store.load()
        await store.createAdminUser(name: "Workspace User", email: "user@example.com", role: .user)
        let user = try XCTUnwrap(store.adminUsers.first)
        await store.createAdminGroup(name: "Prompt Editors", description: "Can manage prompts.", permissions: ["prompts.write"])
        let group = try XCTUnwrap(store.adminGroups.first)
        await store.setAdminGroupMembers(group.id, memberIDs: [user.id])
        store.currentUserID = user.id

        await store.createPrompt(title: "Bug triage", content: "Summarize this bug.", command: "/triage")
        let prompt = try XCTUnwrap(store.prompts.first)
        await store.updatePrompt(
            prompt.id,
            title: "Updated triage",
            content: "Summarize this bug and name next steps.",
            command: "/triage",
            tags: ["debug"]
        )
        let updatedPrompt = try XCTUnwrap(store.prompts.first)
        await store.deletePrompt(updatedPrompt.id)

        XCTAssertTrue(store.prompts.isEmpty)
        XCTAssertNil(store.errorMessage)
        XCTAssertTrue(store.auditEvents.contains { $0.action.rawValue == "promptCreated" })
        XCTAssertTrue(store.auditEvents.contains { $0.action.rawValue == "promptUpdated" })
        XCTAssertTrue(store.auditEvents.contains { $0.action.rawValue == "promptDeleted" })
    }

    func testPromptWritePermissionBlocksCreateUpdateAndDeleteForCurrentUser() async throws {
        let fixture = try PromptLibraryFixture()
        let store = fixture.makeStore()
        await store.load()
        await store.createAdminUser(name: "Workspace User", email: "user@example.com", role: .user)
        let user = try XCTUnwrap(store.adminUsers.first)
        store.currentUserID = user.id

        await store.createPrompt(title: "Blocked prompt", content: "Should not persist.")

        XCTAssertTrue(store.prompts.isEmpty)
        XCTAssertEqual(store.errorMessage, "You do not have permission to manage prompts.")

        store.errorMessage = nil
        store.currentUserID = "local-admin"
        await store.createAdminUser(name: "Local Admin", email: "admin@example.com", role: .admin)
        let admin = try XCTUnwrap(store.adminUsers.first { $0.role == .admin })
        store.currentUserID = admin.id
        await store.createPrompt(title: "Existing prompt", content: "Existing content.")
        let prompt = try XCTUnwrap(store.prompts.first)

        store.currentUserID = user.id
        await store.updatePrompt(prompt.id, title: "Blocked update", content: "Should not update.")
        await store.deletePrompt(prompt.id)

        XCTAssertEqual(store.prompts.first?.title, "Existing prompt")
        XCTAssertEqual(store.prompts.first?.content, "Existing content.")
        XCTAssertEqual(store.errorMessage, "You do not have permission to manage prompts.")
        XCTAssertFalse(store.auditEvents.contains { $0.action.rawValue == "promptUpdated" })
        XCTAssertFalse(store.auditEvents.contains { $0.action.rawValue == "promptDeleted" })
    }

    func testUnmanagedLocalUserCanManagePromptsWhenAdminDirectoryExists() async throws {
        let fixture = try PromptLibraryFixture()
        let store = fixture.makeStore()
        await store.load()
        await store.createAdminUser(name: "Workspace User", email: "user@example.com", role: .user)

        await store.createPrompt(title: "Local prompt", content: "Keep local owner working.")

        XCTAssertEqual(store.prompts.map(\.title), ["Local prompt"])
        XCTAssertNil(store.errorMessage)
    }
}

private struct PromptLibraryFixture {
    let rootURL: URL
    let storage: JSONStorageService
    let folderStorage: JSONFolderStorageService
    let promptStorage: JSONPromptStorageService
    let auditStorage: JSONAuditLogStorageService
    let adminStorage: JSONAdminDirectoryStorageService
    let settingsStore: SettingsStore
    let shareService: FakePromptShareService?

    init(shareService: FakePromptShareService? = nil) throws {
        rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        storage = JSONStorageService(rootURL: rootURL.appendingPathComponent("Chats", isDirectory: true))
        folderStorage = JSONFolderStorageService(rootURL: rootURL.appendingPathComponent("Folders", isDirectory: true))
        promptStorage = JSONPromptStorageService(rootURL: rootURL.appendingPathComponent("Prompts", isDirectory: true))
        auditStorage = JSONAuditLogStorageService(rootURL: rootURL.appendingPathComponent("AuditLog", isDirectory: true))
        adminStorage = JSONAdminDirectoryStorageService(
            snapshotURL: rootURL.appendingPathComponent("admin-directory.json")
        )
        settingsStore = SettingsStore(settingsURL: rootURL.appendingPathComponent("settings.json"))
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
            shareService: shareService ?? FakePromptShareService(),
            auditLogStorage: auditStorage,
            promptStorage: promptStorage,
            adminDirectoryStorage: adminStorage
        )
    }
}

@MainActor
private final class FakePromptShareService: ChatSharing {
    private(set) var sharedText: String?
    private(set) var sharedTitle: String?

    func share(text: String, title: String) {
        sharedText = text
        sharedTitle = title
    }
}
