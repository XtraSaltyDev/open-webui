import Foundation
import XCTest
@testable import OpenWebUINative

@MainActor
final class AppStoreFeedbackTests: XCTestCase {
    func testCreateFeedbackFromMessagePersistsAndReloads() async throws {
        let fixture = try FeedbackFixture()
        let threadID = UUID()
        let messageID = UUID()
        let thread = ChatThread(
            id: threadID,
            title: "Feedback chat",
            modelIDs: ["llama3.2:latest"],
            tags: ["swift", "testing"],
            messages: [
                ChatMessage(role: .user, content: "How do actors work?"),
                ChatMessage(
                    id: messageID,
                    role: .assistant,
                    content: "Actors isolate mutable state.",
                    modelID: "llama3.2:latest"
                )
            ]
        )
        try await fixture.chatStorage.save(thread)

        let store = fixture.makeStore()
        await store.load()

        await store.createFeedback(
            messageID: messageID,
            rating: .positive,
            reason: "helpful",
            comment: "Clear explanation."
        )

        XCTAssertEqual(store.feedbacks.count, 1)
        let feedback = try XCTUnwrap(store.feedbacks.first)
        XCTAssertEqual(feedback.type, "rating")
        XCTAssertEqual(feedback.data.rating, .positive)
        XCTAssertEqual(feedback.data.modelID, "llama3.2:latest")
        XCTAssertEqual(feedback.data.reason, "helpful")
        XCTAssertEqual(feedback.data.comment, "Clear explanation.")
        XCTAssertEqual(feedback.meta.chatID, threadID.uuidString)
        XCTAssertEqual(feedback.meta.messageID, messageID.uuidString)
        XCTAssertEqual(feedback.meta.tags, ["swift", "testing"])
        XCTAssertEqual(feedback.moderationStatus, .pending)
        XCTAssertEqual(feedback.snapshot?.chat?.title, "Feedback chat")
        XCTAssertEqual(store.selectedThread?.messages.last?.rating, .positive)

        let reloadedStore = fixture.makeStore()
        await reloadedStore.load()

        XCTAssertEqual(reloadedStore.feedbacks.count, 1)
        XCTAssertEqual(reloadedStore.feedbacks.first?.data.comment, "Clear explanation.")
        XCTAssertEqual(reloadedStore.selectedThread?.messages.last?.rating, .positive)
    }

    func testCreateFeedbackTrimsOptionalFieldsAndIgnoresEmptyComments() async throws {
        let fixture = try FeedbackFixture()
        let messageID = UUID()
        let thread = ChatThread(
            id: UUID(),
            title: "Trim chat",
            messages: [
                ChatMessage(id: messageID, role: .assistant, content: "Answer", modelID: "mistral:latest")
            ]
        )
        try await fixture.chatStorage.save(thread)

        let store = fixture.makeStore()
        await store.load()

        await store.createFeedback(
            messageID: messageID,
            rating: .negative,
            reason: "  incomplete  ",
            comment: "   "
        )

        let feedback = try XCTUnwrap(store.feedbacks.first)
        XCTAssertEqual(feedback.data.rating, .negative)
        XCTAssertEqual(feedback.data.reason, "incomplete")
        XCTAssertNil(feedback.data.comment)
    }

    func testExportAndImportFeedbackJSONRoundTripsFeedbackRecords() async throws {
        let fixture = try FeedbackFixture()
        let messageID = UUID()
        let thread = ChatThread(
            id: UUID(),
            title: "Export chat",
            messages: [
                ChatMessage(id: messageID, role: .assistant, content: "Answer", modelID: "llama3.2:latest")
            ]
        )
        try await fixture.chatStorage.save(thread)
        let store = fixture.makeStore()
        await store.load()
        await store.createFeedback(messageID: messageID, rating: .positive, reason: nil, comment: "Works well")

        let data = try store.exportFeedbackJSONData()

        let importFixture = try FeedbackFixture()
        let importStore = importFixture.makeStore()
        await importStore.load()
        try await importStore.importFeedbackJSONData(data)

        XCTAssertEqual(importStore.feedbacks.count, 1)
        XCTAssertEqual(importStore.feedbacks.first?.data.modelID, "llama3.2:latest")
        XCTAssertEqual(importStore.feedbacks.first?.data.comment, "Works well")
        XCTAssertEqual(importStore.feedbacks.first?.moderationStatus, .pending)
    }

    func testExportFeedbackJSONForUserActionCreatesAuditEventWithoutFeedbackContent() async throws {
        let fixture = try FeedbackFixture()
        let store = fixture.makeStore()
        await store.load()
        store.feedbacks = [
            AppFeedback(
                id: "feedback-one",
                data: AppFeedbackData(
                    rating: .positive,
                    modelID: "gpt-4.1",
                    reason: "accurate",
                    comment: "Sensitive feedback comment"
                ),
                meta: AppFeedbackMeta(tags: ["private-tag"]),
                snapshot: AppFeedbackSnapshot(chat: AppFeedbackChatSnapshot(title: "Sensitive chat title")),
                moderationStatus: .reviewed
            )
        ]

        let data = try await store.exportFeedbackJSONDataForUserAction()

        let importFixture = try FeedbackFixture()
        let importStore = importFixture.makeStore()
        await importStore.load()
        try await importStore.importFeedbackJSONData(data)
        XCTAssertEqual(importStore.feedbacks.count, 1)
        XCTAssertEqual(importStore.feedbacks.first?.data.comment, "Sensitive feedback comment")
        let event = try XCTUnwrap(store.auditEvents.first(where: { $0.action == .feedbackExported }))
        XCTAssertEqual(event.outcome, .succeeded)
        XCTAssertEqual(event.summary, "Exported feedback records")
        XCTAssertEqual(event.metadata["exportedFeedbackCount"], "1")
        XCTAssertEqual(event.metadata["exportedReviewedCount"], "1")
        XCTAssertNil(event.metadata["comment"])
        XCTAssertNil(event.metadata["reason"])
        XCTAssertNil(event.metadata["chatTitle"])
        XCTAssertFalse(event.metadata.values.contains("Sensitive feedback comment"))
        XCTAssertFalse(event.metadata.values.contains("Sensitive chat title"))
        XCTAssertFalse(event.metadata.values.contains("private-tag"))
    }

    func testExportFeedbackOpenWebUIJSONDataBuildsRawFeedbackRecords() async throws {
        let fixture = try FeedbackFixture()
        let store = fixture.makeStore()
        await store.load()
        let chatID = UUID().uuidString
        let messageID = UUID().uuidString
        store.feedbacks = [
            AppFeedback(
                id: "feedback-id",
                userID: "user-id",
                version: 0,
                type: "rating",
                data: AppFeedbackData(
                    rating: .negative,
                    modelID: "gpt-4.1",
                    siblingModelIDs: ["llama3.2:latest"],
                    reason: "incorrect",
                    comment: "Missed the citation.",
                    additional: ["source": .string("thumbs-down")]
                ),
                meta: AppFeedbackMeta(
                    arena: true,
                    chatID: chatID,
                    messageID: messageID,
                    tags: ["research"],
                    additional: ["workspace": .string("native")]
                ),
                snapshot: AppFeedbackSnapshot(
                    chat: AppFeedbackChatSnapshot(title: "Research chat", messageCount: 3)
                ),
                moderationStatus: .dismissed,
                createdAt: Date(timeIntervalSince1970: 1_000),
                updatedAt: Date(timeIntervalSince1970: 2_000)
            )
        ]

        let data = try store.exportFeedbackOpenWebUIJSONData()
        let records = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [[String: Any]])
        let record = try XCTUnwrap(records.first)
        let recordData = try XCTUnwrap(record["data"] as? [String: Any])
        let meta = try XCTUnwrap(record["meta"] as? [String: Any])
        let snapshot = try XCTUnwrap(record["snapshot"] as? [String: Any])
        let chat = try XCTUnwrap(snapshot["chat"] as? [String: Any])

        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(record["id"] as? String, "feedback-id")
        XCTAssertEqual(record["user_id"] as? String, "user-id")
        XCTAssertEqual(record["version"] as? Int, 0)
        XCTAssertEqual(record["type"] as? String, "rating")
        XCTAssertEqual(recordData["rating"] as? String, "negative")
        XCTAssertEqual(recordData["model_id"] as? String, "gpt-4.1")
        XCTAssertEqual(recordData["sibling_model_ids"] as? [String], ["llama3.2:latest"])
        XCTAssertEqual(recordData["reason"] as? String, "incorrect")
        XCTAssertEqual(recordData["comment"] as? String, "Missed the citation.")
        XCTAssertEqual(recordData["source"] as? String, "thumbs-down")
        XCTAssertEqual(meta["arena"] as? Bool, true)
        XCTAssertEqual(meta["chat_id"] as? String, chatID)
        XCTAssertEqual(meta["message_id"] as? String, messageID)
        XCTAssertEqual(meta["tags"] as? [String], ["research"])
        XCTAssertEqual(meta["workspace"] as? String, "native")
        XCTAssertEqual(chat["title"] as? String, "Research chat")
        XCTAssertEqual(chat["message_count"] as? Int, 3)
        XCTAssertEqual(record["created_at"] as? Int, 1_000)
        XCTAssertEqual(record["updated_at"] as? Int, 2_000)
        XCTAssertNil(record["moderationStatus"])
    }

    func testImportFeedbackJSONForUserActionCreatesAuditEventWithoutFeedbackContent() async throws {
        let fixture = try FeedbackFixture()
        let sourceStore = fixture.makeStore()
        await sourceStore.load()
        sourceStore.feedbacks = [
            AppFeedback(
                id: "feedback-imported",
                data: AppFeedbackData(
                    rating: .negative,
                    modelID: "llama3.2:latest",
                    reason: "incorrect",
                    comment: "Imported private comment"
                ),
                meta: AppFeedbackMeta(tags: ["import-tag"]),
                snapshot: AppFeedbackSnapshot(chat: AppFeedbackChatSnapshot(title: "Imported private chat")),
                moderationStatus: .dismissed
            )
        ]
        let data = try sourceStore.exportFeedbackJSONData()

        let importFixture = try FeedbackFixture()
        let importStore = importFixture.makeStore()
        await importStore.load()
        try await importStore.importFeedbackJSONDataForUserAction(data)

        XCTAssertEqual(importStore.feedbacks.count, 1)
        XCTAssertEqual(importStore.feedbacks.first?.data.comment, "Imported private comment")
        let event = try XCTUnwrap(importStore.auditEvents.first(where: { $0.action == .feedbackImported }))
        XCTAssertEqual(event.outcome, .succeeded)
        XCTAssertEqual(event.summary, "Imported feedback records")
        XCTAssertEqual(event.metadata["importedFeedbackCount"], "1")
        XCTAssertEqual(event.metadata["importedDismissedCount"], "1")
        XCTAssertEqual(event.metadata["totalFeedbackCount"], "1")
        XCTAssertNil(event.metadata["comment"])
        XCTAssertNil(event.metadata["reason"])
        XCTAssertNil(event.metadata["chatTitle"])
        XCTAssertFalse(event.metadata.values.contains("Imported private comment"))
        XCTAssertFalse(event.metadata.values.contains("Imported private chat"))
        XCTAssertFalse(event.metadata.values.contains("import-tag"))
    }

    func testAuditMetadataFormatterPromotesFeedbackTransferRows() {
        let event = AppAuditEvent(
            action: .feedbackExported,
            outcome: .succeeded,
            summary: "Exported feedback records",
            metadata: [
                "exportedFeedbackCount": "6",
                "exportedPositiveCount": "4",
                "exportedNegativeCount": "2",
                "exportedReviewedCount": "3"
            ]
        )

        let rows = AuditEventMetadataFormatter.rows(for: event)

        XCTAssertEqual(
            rows.map(\.label),
            ["Feedback", "Positive", "Negative", "Reviewed"]
        )
        XCTAssertEqual(rows.map(\.value), ["6", "4", "2", "3"])
    }

    func testUpdateFeedbackModerationStatusPersistsAndReloads() async throws {
        let fixture = try FeedbackFixture()
        let store = fixture.makeStore()
        await store.load()
        let feedback = AppFeedback(
            id: "feedback-id",
            data: AppFeedbackData(rating: .negative, modelID: "llama3.2:latest"),
            meta: AppFeedbackMeta()
        )
        try await fixture.feedbackStorage.save(feedback)
        store.feedbacks = [feedback]

        await store.updateFeedbackModerationStatus("feedback-id", status: .reviewed)

        XCTAssertEqual(store.feedbacks.first?.moderationStatus, .reviewed)
        let reloaded = try await fixture.feedbackStorage.loadFeedbacks()
        XCTAssertEqual(reloaded.first?.moderationStatus, .reviewed)
    }

    func testUpdateFeedbackModerationStatusCreatesAuditEvent() async throws {
        let fixture = try FeedbackFixture()
        let store = fixture.makeStore()
        await store.load()
        let feedback = AppFeedback(
            id: "feedback-id",
            data: AppFeedbackData(rating: .negative, modelID: "llama3.2:latest"),
            meta: AppFeedbackMeta()
        )
        try await fixture.feedbackStorage.save(feedback)
        store.feedbacks = [feedback]

        await store.updateFeedbackModerationStatus("feedback-id", status: .reviewed)

        let event = try XCTUnwrap(store.auditEvents.first)
        XCTAssertEqual(event.action.rawValue, "feedbackModerationUpdated")
        XCTAssertEqual(event.outcome, .succeeded)
        XCTAssertEqual(event.metadata["feedbackID"], "feedback-id")
        XCTAssertEqual(event.metadata["modelID"], "llama3.2:latest")
        XCTAssertEqual(event.metadata["fromStatus"], "pending")
        XCTAssertEqual(event.metadata["toStatus"], "reviewed")

        let reloadedStore = fixture.makeStore()
        await reloadedStore.load()
        XCTAssertEqual(reloadedStore.auditEvents.first?.action.rawValue, "feedbackModerationUpdated")
        XCTAssertEqual(reloadedStore.auditEvents.first?.metadata["feedbackID"], "feedback-id")
    }

    func testDeleteFeedbackRemovesPersistedRecord() async throws {
        let fixture = try FeedbackFixture()
        let store = fixture.makeStore()
        await store.load()
        let kept = AppFeedback(
            id: "kept-feedback",
            data: AppFeedbackData(rating: .positive, modelID: "gpt-4.1"),
            meta: AppFeedbackMeta()
        )
        let deleted = AppFeedback(
            id: "deleted-feedback",
            data: AppFeedbackData(rating: .negative, modelID: "llama3.2:latest"),
            meta: AppFeedbackMeta()
        )
        try await fixture.feedbackStorage.save(kept)
        try await fixture.feedbackStorage.save(deleted)
        store.feedbacks = [kept, deleted]

        await store.deleteFeedback("deleted-feedback")

        XCTAssertEqual(store.feedbacks.map(\.id), ["kept-feedback"])
        let reloaded = try await fixture.feedbackStorage.loadFeedbacks()
        XCTAssertEqual(reloaded.map(\.id), ["kept-feedback"])
    }

    func testDeleteFeedbackCreatesAuditEvent() async throws {
        let fixture = try FeedbackFixture()
        let store = fixture.makeStore()
        await store.load()
        let feedback = AppFeedback(
            id: "feedback-id",
            data: AppFeedbackData(rating: .negative, modelID: "llama3.2:latest"),
            meta: AppFeedbackMeta(),
            moderationStatus: .dismissed
        )
        try await fixture.feedbackStorage.save(feedback)
        store.feedbacks = [feedback]

        await store.deleteFeedback("feedback-id")

        let event = try XCTUnwrap(store.auditEvents.first)
        XCTAssertEqual(event.action.rawValue, "feedbackDeleted")
        XCTAssertEqual(event.outcome, .succeeded)
        XCTAssertEqual(event.metadata["feedbackID"], "feedback-id")
        XCTAssertEqual(event.metadata["modelID"], "llama3.2:latest")
        XCTAssertEqual(event.metadata["rating"], "negative")
        XCTAssertEqual(event.metadata["moderationStatus"], "dismissed")

        let reloadedStore = fixture.makeStore()
        await reloadedStore.load()
        XCTAssertEqual(reloadedStore.auditEvents.first?.action.rawValue, "feedbackDeleted")
        XCTAssertEqual(reloadedStore.auditEvents.first?.metadata["feedbackID"], "feedback-id")
    }

    func testExportAndImportFeedbackJSONPreservesModerationStatus() async throws {
        let fixture = try FeedbackFixture()
        let store = fixture.makeStore()
        await store.load()
        store.feedbacks = [
            AppFeedback(
                id: "feedback-id",
                data: AppFeedbackData(rating: .positive, modelID: "gpt-4.1"),
                meta: AppFeedbackMeta(),
                moderationStatus: .dismissed
            )
        ]

        let data = try store.exportFeedbackJSONData()
        let importFixture = try FeedbackFixture()
        let importStore = importFixture.makeStore()
        await importStore.load()
        try await importStore.importFeedbackJSONData(data)

        XCTAssertEqual(importStore.feedbacks.first?.moderationStatus, .dismissed)
    }

    func testImportFeedbackJSONAcceptsOpenWebUIFeedbackRecords() async throws {
        let fixture = try FeedbackFixture()
        let store = fixture.makeStore()
        await store.load()
        let data = Data(
            """
            [
              {
                "id": "feedback-id",
                "user_id": "user-id",
                "version": 0,
                "type": "rating",
                "data": {
                  "rating": "positive",
                  "model_id": "gpt-4.1",
                  "sibling_model_ids": ["llama3.2:latest"],
                  "reason": "accurate",
                  "comment": "Good citations.",
                  "tags": ["research"]
                },
                "meta": {
                  "arena": false,
                  "chat_id": "\(UUID().uuidString)",
                  "message_id": "\(UUID().uuidString)",
                  "tags": ["research", "citations"]
                },
                "snapshot": {
                  "chat": {
                    "title": "Research chat"
                  }
                },
                "created_at": 1000,
                "updated_at": 2000
              }
            ]
            """.utf8
        )

        try await store.importFeedbackJSONData(data)

        let feedback = try XCTUnwrap(store.feedbacks.first)
        XCTAssertEqual(feedback.id, "feedback-id")
        XCTAssertEqual(feedback.userID, "user-id")
        XCTAssertEqual(feedback.data.rating, .positive)
        XCTAssertEqual(feedback.data.modelID, "gpt-4.1")
        XCTAssertEqual(feedback.data.siblingModelIDs, ["llama3.2:latest"])
        XCTAssertEqual(feedback.data.reason, "accurate")
        XCTAssertEqual(feedback.data.comment, "Good citations.")
        XCTAssertEqual(feedback.meta.tags, ["research", "citations"])
        XCTAssertEqual(feedback.snapshot?.chat?.title, "Research chat")
        XCTAssertEqual(feedback.createdAt, Date(timeIntervalSince1970: 1000))
        XCTAssertEqual(feedback.updatedAt, Date(timeIntervalSince1970: 2000))
    }

    func testModelEvaluationSummariesReflectImportedFeedback() async throws {
        let fixture = try FeedbackFixture()
        let store = fixture.makeStore()
        await store.load()
        let data = Data(
            """
            [
              {
                "id": "one",
                "user_id": "user-id",
                "version": 0,
                "type": "rating",
                "data": {
                  "rating": "positive",
                  "model_id": "llama3.2:latest",
                  "sibling_model_ids": ["mistral:latest"]
                },
                "meta": {
                  "arena": true,
                  "tags": ["swift"]
                },
                "created_at": 1000,
                "updated_at": 1000
              }
            ]
            """.utf8
        )

        try await store.importFeedbackJSONData(data)

        XCTAssertEqual(store.modelEvaluationSummaries.map(\.modelID), ["llama3.2:latest", "mistral:latest"])
        XCTAssertEqual(store.modelEvaluationSummaries.first?.won, 1)
        XCTAssertEqual(store.modelEvaluationSummaries.first?.topTags.first?.tag, "swift")
    }

    func testSelectEvaluationDashboardClearsSelectedThread() async throws {
        let fixture = try FeedbackFixture()
        let thread = ChatThread(id: UUID(), title: "Selected")
        try await fixture.chatStorage.save(thread)
        let store = fixture.makeStore()
        await store.load()

        store.selectEvaluationDashboard()

        XCTAssertTrue(store.isShowingEvaluationDashboard)
        XCTAssertNil(store.selectedThreadID)
    }
}

private struct FeedbackFixture {
    let rootURL: URL
    let chatStorage: JSONStorageService
    let folderStorage: JSONFolderStorageService
    let feedbackStorage: JSONFeedbackStorageService
    let settingsStore: SettingsStore
    let auditStorage: JSONAuditLogStorageService

    init() throws {
        rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        chatStorage = JSONStorageService(rootURL: rootURL.appendingPathComponent("Chats", isDirectory: true))
        folderStorage = JSONFolderStorageService(rootURL: rootURL.appendingPathComponent("Folders", isDirectory: true))
        feedbackStorage = JSONFeedbackStorageService(rootURL: rootURL.appendingPathComponent("Feedback", isDirectory: true))
        settingsStore = SettingsStore(settingsURL: rootURL.appendingPathComponent("settings.json"))
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
            feedbackStorage: feedbackStorage
        )
    }
}
