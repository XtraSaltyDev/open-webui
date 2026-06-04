import Foundation
import XCTest
@testable import OpenWebUINative

@MainActor
final class AppStoreChatActionTests: XCTestCase {
    func testEditMessageUpdatesContentAndPersistsThread() async throws {
        let fixture = try StoreFixture()
        let messageID = UUID()
        let thread = ChatThread(
            id: UUID(),
            title: "Editable",
            messages: [ChatMessage(id: messageID, role: .user, content: "Before")]
        )
        try await fixture.storage.save(thread)

        let store = fixture.makeStore()
        await store.load()

        await store.editMessage(id: messageID, content: "After")

        XCTAssertEqual(store.selectedThread?.messages.first?.content, "After")
        let saved = try await fixture.storage.loadThreads()
        XCTAssertEqual(saved.first?.messages.first?.content, "After")
    }

    func testRateMessageUpdatesRatingAndPersistsThread() async throws {
        let fixture = try StoreFixture()
        let messageID = UUID()
        let thread = ChatThread(
            id: UUID(),
            title: "Rateable",
            messages: [ChatMessage(id: messageID, role: .assistant, content: "Answer")]
        )
        try await fixture.storage.save(thread)

        let store = fixture.makeStore()
        await store.load()

        await store.rateMessage(id: messageID, rating: .negative)

        XCTAssertEqual(store.selectedThread?.messages.first?.rating, .negative)
        let saved = try await fixture.storage.loadThreads()
        XCTAssertEqual(saved.first?.messages.first?.rating, .negative)
    }

    func testRenameThreadTrimsTitleAndPersistsThread() async throws {
        let fixture = try StoreFixture()
        let thread = ChatThread(
            id: UUID(),
            title: "Original",
            messages: [ChatMessage(role: .user, content: "Hello")]
        )
        try await fixture.storage.save(thread)

        let store = fixture.makeStore()
        await store.load()

        await store.renameThread(thread.id, title: "  Better title  ")

        XCTAssertEqual(store.threads.first?.title, "Better title")
        let saved = try await fixture.storage.loadThreads()
        XCTAssertEqual(saved.first?.title, "Better title")
    }

    func testToggleThreadPinnedPersistsAndSortsPinnedThreadsFirst() async throws {
        let fixture = try StoreFixture()
        let olderThread = ChatThread(
            id: UUID(),
            title: "Older",
            createdAt: Date(timeIntervalSince1970: 10),
            updatedAt: Date(timeIntervalSince1970: 20)
        )
        let newerThread = ChatThread(
            id: UUID(),
            title: "Newer",
            createdAt: Date(timeIntervalSince1970: 30),
            updatedAt: Date(timeIntervalSince1970: 40)
        )
        try await fixture.storage.save(olderThread)
        try await fixture.storage.save(newerThread)

        let store = fixture.makeStore()
        await store.load()

        await store.toggleThreadPinned(olderThread.id)

        XCTAssertEqual(store.filteredThreads().map(\.id), [olderThread.id, newerThread.id])
        XCTAssertTrue(store.threads.first { $0.id == olderThread.id }?.isPinned ?? false)

        let reloadedStore = fixture.makeStore()
        await reloadedStore.load()

        XCTAssertEqual(reloadedStore.filteredThreads().map(\.id), [olderThread.id, newerThread.id])
        XCTAssertTrue(reloadedStore.threads.first { $0.id == olderThread.id }?.isPinned ?? false)

        await reloadedStore.toggleThreadPinned(olderThread.id)

        XCTAssertFalse(reloadedStore.threads.first { $0.id == olderThread.id }?.isPinned ?? true)
    }

    func testLoadThreadsDefaultsMissingPinnedStateToFalse() async throws {
        let fixture = try StoreFixture()
        let threadID = UUID()
        let legacyThreadData = Data(
            """
            {
              "id": "\(threadID.uuidString)",
              "title": "Legacy chat",
              "createdAt": "2026-01-01T00:00:00Z",
              "updatedAt": "2026-01-02T00:00:00Z",
              "folderID": null,
              "providerID": null,
              "modelIDs": [],
              "tags": [],
              "messages": []
            }
            """.utf8
        )
        let chatsURL = fixture.rootURL.appendingPathComponent("Chats", isDirectory: true)
        try FileManager.default.createDirectory(at: chatsURL, withIntermediateDirectories: true)
        try legacyThreadData.write(to: chatsURL.appendingPathComponent("\(threadID.uuidString).json"))

        let store = fixture.makeStore()
        await store.load()

        XCTAssertEqual(store.threads.first?.id, threadID)
        XCTAssertFalse(store.threads.first?.isPinned ?? true)
    }

    func testToggleThreadArchivedPersistsAndHidesFromDefaultThreadList() async throws {
        let fixture = try StoreFixture()
        let folder = ChatFolder(id: UUID(), name: "Projects")
        try await fixture.folderStorage.save(folder)
        let archivedThread = ChatThread(
            id: UUID(),
            title: "Archive me",
            createdAt: Date(timeIntervalSince1970: 10),
            updatedAt: Date(timeIntervalSince1970: 20),
            folderID: folder.id
        )
        let visibleThread = ChatThread(
            id: UUID(),
            title: "Keep visible",
            createdAt: Date(timeIntervalSince1970: 30),
            updatedAt: Date(timeIntervalSince1970: 40)
        )
        try await fixture.storage.save(archivedThread)
        try await fixture.storage.save(visibleThread)

        let store = fixture.makeStore()
        await store.load()

        await store.toggleThreadArchived(archivedThread.id)

        XCTAssertEqual(store.filteredThreads(folderID: folder.id).map(\.id), [])
        XCTAssertEqual(store.filteredThreads().map(\.id), [visibleThread.id])
        XCTAssertEqual(store.filteredArchivedThreads().map(\.id), [archivedThread.id])
        XCTAssertTrue(store.threads.first { $0.id == archivedThread.id }?.isArchived ?? false)

        let reloadedStore = fixture.makeStore()
        await reloadedStore.load()

        XCTAssertEqual(reloadedStore.filteredThreads(folderID: folder.id).map(\.id), [])
        XCTAssertEqual(reloadedStore.filteredArchivedThreads().map(\.id), [archivedThread.id])
        XCTAssertTrue(reloadedStore.threads.first { $0.id == archivedThread.id }?.isArchived ?? false)

        await reloadedStore.toggleThreadArchived(archivedThread.id)

        XCTAssertEqual(reloadedStore.filteredThreads(folderID: folder.id).map(\.id), [archivedThread.id])
        XCTAssertEqual(reloadedStore.filteredArchivedThreads().map(\.id), [])
        XCTAssertFalse(reloadedStore.threads.first { $0.id == archivedThread.id }?.isArchived ?? true)
    }

    func testArchivingSelectedThreadSelectsNextVisibleThread() async throws {
        let fixture = try StoreFixture()
        let selectedThread = ChatThread(
            id: UUID(),
            title: "Selected",
            createdAt: Date(timeIntervalSince1970: 10),
            updatedAt: Date(timeIntervalSince1970: 20)
        )
        let nextThread = ChatThread(
            id: UUID(),
            title: "Next",
            createdAt: Date(timeIntervalSince1970: 30),
            updatedAt: Date(timeIntervalSince1970: 40)
        )
        try await fixture.storage.save(selectedThread)
        try await fixture.storage.save(nextThread)

        let store = fixture.makeStore()
        await store.load()
        store.selectedThreadID = selectedThread.id

        await store.toggleThreadArchived(selectedThread.id)

        XCTAssertEqual(store.selectedThreadID, nextThread.id)
    }

    func testUnarchiveAllArchivedThreadsPersistsAndRestoresVisibleThreads() async throws {
        let fixture = try StoreFixture()
        let archivedOne = ChatThread(
            id: UUID(),
            title: "Archived One",
            createdAt: Date(timeIntervalSince1970: 10),
            updatedAt: Date(timeIntervalSince1970: 20),
            isArchived: true
        )
        let archivedTwo = ChatThread(
            id: UUID(),
            title: "Archived Two",
            createdAt: Date(timeIntervalSince1970: 30),
            updatedAt: Date(timeIntervalSince1970: 40),
            isArchived: true
        )
        try await fixture.storage.save(archivedOne)
        try await fixture.storage.save(archivedTwo)

        let store = fixture.makeStore()
        await store.load()

        await store.unarchiveAllArchivedThreads()

        XCTAssertEqual(store.filteredArchivedThreads(), [])
        XCTAssertEqual(store.filteredThreads().map(\.id), [archivedTwo.id, archivedOne.id])

        let reloadedStore = fixture.makeStore()
        await reloadedStore.load()

        XCTAssertEqual(reloadedStore.filteredArchivedThreads(), [])
        XCTAssertEqual(reloadedStore.filteredThreads().map(\.id), [archivedTwo.id, archivedOne.id])
    }

    func testArchiveAllThreadsPersistsHidesVisibleThreadsAndClearsSelection() async throws {
        let fixture = try StoreFixture()
        let visibleOne = ChatThread(
            id: UUID(),
            title: "Visible One",
            createdAt: Date(timeIntervalSince1970: 10),
            updatedAt: Date(timeIntervalSince1970: 20)
        )
        let visibleTwo = ChatThread(
            id: UUID(),
            title: "Visible Two",
            createdAt: Date(timeIntervalSince1970: 30),
            updatedAt: Date(timeIntervalSince1970: 40),
            isPinned: true
        )
        let alreadyArchived = ChatThread(
            id: UUID(),
            title: "Already Archived",
            createdAt: Date(timeIntervalSince1970: 50),
            updatedAt: Date(timeIntervalSince1970: 60),
            isArchived: true
        )
        try await fixture.storage.save(visibleOne)
        try await fixture.storage.save(visibleTwo)
        try await fixture.storage.save(alreadyArchived)

        let store = fixture.makeStore()
        await store.load()
        store.selectedThreadID = visibleOne.id

        await store.archiveAllThreads()

        XCTAssertNil(store.selectedThreadID)
        XCTAssertEqual(store.filteredThreads(), [])
        XCTAssertEqual(store.filteredArchivedThreads().map(\.id), [alreadyArchived.id, visibleTwo.id, visibleOne.id])
        XCTAssertTrue(store.threads.allSatisfy(\.isArchived))

        let reloadedStore = fixture.makeStore()
        await reloadedStore.load()

        XCTAssertNil(reloadedStore.selectedThreadID)
        XCTAssertEqual(reloadedStore.filteredThreads(), [])
        XCTAssertEqual(reloadedStore.filteredArchivedThreads().map(\.id), [alreadyArchived.id, visibleTwo.id, visibleOne.id])
        XCTAssertTrue(reloadedStore.threads.allSatisfy(\.isArchived))
    }

    func testDeleteAllThreadsPersistsClearsVisibleArchivedAndSelection() async throws {
        let fixture = try StoreFixture()
        let visible = ChatThread(
            id: UUID(),
            title: "Visible",
            createdAt: Date(timeIntervalSince1970: 10),
            updatedAt: Date(timeIntervalSince1970: 20)
        )
        let pinned = ChatThread(
            id: UUID(),
            title: "Pinned",
            createdAt: Date(timeIntervalSince1970: 30),
            updatedAt: Date(timeIntervalSince1970: 40),
            isPinned: true
        )
        let archived = ChatThread(
            id: UUID(),
            title: "Archived",
            createdAt: Date(timeIntervalSince1970: 50),
            updatedAt: Date(timeIntervalSince1970: 60),
            isArchived: true
        )
        try await fixture.storage.save(visible)
        try await fixture.storage.save(pinned)
        try await fixture.storage.save(archived)

        let store = fixture.makeStore()
        await store.load()
        store.selectedThreadID = visible.id

        await store.deleteAllThreads()

        XCTAssertEqual(store.threads, [])
        XCTAssertEqual(store.filteredThreads(), [])
        XCTAssertEqual(store.filteredArchivedThreads(), [])
        XCTAssertNil(store.selectedThreadID)

        let reloadedStore = fixture.makeStore()
        await reloadedStore.load()

        XCTAssertEqual(reloadedStore.threads, [])
        XCTAssertEqual(reloadedStore.filteredThreads(), [])
        XCTAssertEqual(reloadedStore.filteredArchivedThreads(), [])
        XCTAssertNil(reloadedStore.selectedThreadID)
    }

    func testExportArchivedThreadsJSONDataExportsOnlyArchivedThreads() async throws {
        let fixture = try StoreFixture()
        let archivedNewer = ChatThread(
            id: UUID(),
            title: "Archived Newer",
            createdAt: Date(timeIntervalSince1970: 30),
            updatedAt: Date(timeIntervalSince1970: 40),
            isArchived: true
        )
        let archivedOlder = ChatThread(
            id: UUID(),
            title: "Archived Older",
            createdAt: Date(timeIntervalSince1970: 10),
            updatedAt: Date(timeIntervalSince1970: 20),
            isArchived: true
        )
        let visible = ChatThread(
            id: UUID(),
            title: "Visible",
            createdAt: Date(timeIntervalSince1970: 50),
            updatedAt: Date(timeIntervalSince1970: 60)
        )
        try await fixture.storage.save(archivedNewer)
        try await fixture.storage.save(archivedOlder)
        try await fixture.storage.save(visible)

        let store = fixture.makeStore()
        await store.load()

        let data = try store.exportArchivedThreadsJSONData()
        let decoded = try JSONDecoder.openWebUIDecoder.decode([ChatThread].self, from: data)

        XCTAssertEqual(decoded.map(\.id), [archivedNewer.id, archivedOlder.id])
        XCTAssertTrue(decoded.allSatisfy(\.isArchived))
    }

    func testExportAllThreadsJSONDataExportsVisibleAndArchivedThreadsNewestFirst() async throws {
        let fixture = try StoreFixture()
        let olderVisible = ChatThread(
            id: UUID(),
            title: "Older Visible",
            createdAt: Date(timeIntervalSince1970: 10),
            updatedAt: Date(timeIntervalSince1970: 20)
        )
        let archivedNewer = ChatThread(
            id: UUID(),
            title: "Archived Newer",
            createdAt: Date(timeIntervalSince1970: 30),
            updatedAt: Date(timeIntervalSince1970: 60),
            isArchived: true
        )
        let visibleMiddle = ChatThread(
            id: UUID(),
            title: "Visible Middle",
            createdAt: Date(timeIntervalSince1970: 40),
            updatedAt: Date(timeIntervalSince1970: 50),
            isPinned: true
        )
        try await fixture.storage.save(olderVisible)
        try await fixture.storage.save(archivedNewer)
        try await fixture.storage.save(visibleMiddle)

        let store = fixture.makeStore()
        await store.load()

        let data = try store.exportAllThreadsJSONData()
        let decoded = try JSONDecoder.openWebUIDecoder.decode([ChatThread].self, from: data)

        XCTAssertEqual(decoded.map(\.id), [archivedNewer.id, visibleMiddle.id, olderVisible.id])
        XCTAssertTrue(decoded.first?.isArchived ?? false)
        XCTAssertEqual(decoded[1].title, "Visible Middle")
        XCTAssertTrue(decoded[1].isPinned)
    }

    func testExportSelectedThreadOpenWebUIJSONDataExportsImportEnvelope() async throws {
        let fixture = try StoreFixture()
        let thread = ChatThread(
            title: "Selected Export",
            createdAt: Date(timeIntervalSince1970: 100),
            updatedAt: Date(timeIntervalSince1970: 200),
            modelIDs: ["llama3.2:latest"],
            messages: [
                ChatMessage(role: .user, content: "Export me.")
            ]
        )
        try await fixture.storage.save(thread)

        let store = fixture.makeStore()
        await store.load()
        store.selectedThreadID = thread.id

        let data = try XCTUnwrap(store.exportSelectedThreadOpenWebUIJSONData())
        let envelope = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let chats = try XCTUnwrap(envelope["chats"] as? [[String: Any]])
        let chat = try XCTUnwrap(chats.first?["chat"] as? [String: Any])

        XCTAssertEqual(chats.count, 1)
        XCTAssertEqual(chat["title"] as? String, "Selected Export")
        XCTAssertEqual(chat["models"] as? [String], ["llama3.2:latest"])
    }

    func testExportAllThreadsOpenWebUIJSONDataExportsImportEnvelopeNewestFirst() async throws {
        let fixture = try StoreFixture()
        let olderThread = ChatThread(
            id: UUID(),
            title: "Older Export",
            createdAt: Date(timeIntervalSince1970: 10),
            updatedAt: Date(timeIntervalSince1970: 20),
            modelIDs: ["llama3.2:latest"],
            messages: [
                ChatMessage(role: .user, content: "First saved chat.")
            ]
        )
        let newerThread = ChatThread(
            id: UUID(),
            title: "Newer Export",
            createdAt: Date(timeIntervalSince1970: 30),
            updatedAt: Date(timeIntervalSince1970: 40),
            modelIDs: ["gpt-4.1-mini"],
            isArchived: true,
            messages: [
                ChatMessage(role: .user, content: "Second saved chat.")
            ]
        )
        try await fixture.storage.save(olderThread)
        try await fixture.storage.save(newerThread)

        let store = fixture.makeStore()
        await store.load()

        let data = try store.exportAllThreadsOpenWebUIJSONData()
        let envelope = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let chats = try XCTUnwrap(envelope["chats"] as? [[String: Any]])
        let firstChat = try XCTUnwrap(chats.first?["chat"] as? [String: Any])
        let secondChat = try XCTUnwrap(chats.last?["chat"] as? [String: Any])

        XCTAssertEqual(chats.count, 2)
        XCTAssertEqual(firstChat["title"] as? String, "Newer Export")
        XCTAssertEqual(firstChat["models"] as? [String], ["gpt-4.1-mini"])
        XCTAssertEqual(secondChat["title"] as? String, "Older Export")
    }

    func testCloneThreadCopiesThreadWithNewIDsPersistsAndSelectsClone() async throws {
        let fixture = try StoreFixture()
        let folder = ChatFolder(id: UUID(), name: "Research")
        try await fixture.folderStorage.save(folder)
        let messageID = UUID()
        let sourceThread = ChatThread(
            id: UUID(),
            title: "Source chat",
            createdAt: Date(timeIntervalSince1970: 10),
            updatedAt: Date(timeIntervalSince1970: 20),
            folderID: folder.id,
            providerID: ProviderConfiguration.defaultOllamaID,
            modelIDs: ["llama3.2"],
            tags: ["draft"],
            isPinned: true,
            isArchived: true,
            messages: [
                ChatMessage(id: messageID, role: .user, content: "Original prompt")
            ]
        )
        try await fixture.storage.save(sourceThread)

        let store = fixture.makeStore()
        await store.load()

        await store.cloneThread(sourceThread.id)

        let clonedThread = try XCTUnwrap(store.selectedThread)
        XCTAssertNotEqual(clonedThread.id, sourceThread.id)
        XCTAssertEqual(clonedThread.title, "Clone of Source chat")
        XCTAssertEqual(clonedThread.folderID, folder.id)
        XCTAssertEqual(clonedThread.providerID, ProviderConfiguration.defaultOllamaID)
        XCTAssertEqual(clonedThread.modelIDs, ["llama3.2"])
        XCTAssertEqual(clonedThread.tags, ["draft"])
        XCTAssertTrue(clonedThread.isPinned)
        XCTAssertFalse(clonedThread.isArchived)
        XCTAssertEqual(clonedThread.messages.map(\.content), ["Original prompt"])
        XCTAssertNotEqual(clonedThread.messages.first?.id, messageID)
        XCTAssertEqual(store.filteredThreads(folderID: folder.id).map(\.id), [clonedThread.id])

        let saved = try await fixture.storage.loadThreads()
        let savedClone = try XCTUnwrap(saved.first { $0.id == clonedThread.id })
        XCTAssertEqual(savedClone.title, "Clone of Source chat")
        XCTAssertEqual(savedClone.messages.first?.content, "Original prompt")
    }

    func testLoadThreadsDefaultsMissingArchivedStateToFalse() async throws {
        let fixture = try StoreFixture()
        let threadID = UUID()
        let legacyThreadData = Data(
            """
            {
              "id": "\(threadID.uuidString)",
              "title": "Legacy unarchived chat",
              "createdAt": "2026-01-01T00:00:00Z",
              "updatedAt": "2026-01-02T00:00:00Z",
              "folderID": null,
              "providerID": null,
              "modelIDs": [],
              "tags": [],
              "messages": []
            }
            """.utf8
        )
        let chatsURL = fixture.rootURL.appendingPathComponent("Chats", isDirectory: true)
        try FileManager.default.createDirectory(at: chatsURL, withIntermediateDirectories: true)
        try legacyThreadData.write(to: chatsURL.appendingPathComponent("\(threadID.uuidString).json"))

        let store = fixture.makeStore()
        await store.load()

        XCTAssertEqual(store.filteredThreads().map(\.id), [threadID])
        XCTAssertFalse(store.threads.first?.isArchived ?? true)
    }

    func testShareSelectedThreadAsMarkdownUsesChatTitleAndExportedMarkdown() async throws {
        let shareService = FakeChatShareService()
        let fixture = try StoreFixture(shareService: shareService)
        let thread = ChatThread(
            id: UUID(),
            title: "Share Me",
            messages: [
                ChatMessage(role: .user, content: "Please share this.")
            ]
        )
        try await fixture.storage.save(thread)

        let store = fixture.makeStore()
        await store.load()
        store.shareSelectedThreadAsMarkdown()

        XCTAssertEqual(shareService.sharedTitle, "Share Me")
        XCTAssertTrue(shareService.sharedText?.contains("# Share Me") ?? false)
        XCTAssertTrue(shareService.sharedText?.contains("Please share this.") ?? false)
    }

    func testChatDeepLinkUsesStableAppURL() {
        let messageID = UUID(uuidString: "00000000-0000-0000-0000-000000000654")!
        let thread = ChatThread(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000456")!,
            title: "Research"
        )
        let messageURL = thread.deepLinkURL(forMessageID: messageID)

        XCTAssertEqual(thread.deepLinkURL.absoluteString, "openwebui-native://chats/00000000-0000-0000-0000-000000000456")
        XCTAssertEqual(ChatThread.threadID(fromDeepLink: thread.deepLinkURL), thread.id)
        XCTAssertEqual(messageURL.absoluteString, "openwebui-native://chats/00000000-0000-0000-0000-000000000456/messages/00000000-0000-0000-0000-000000000654")
        XCTAssertEqual(ChatThread.threadID(fromDeepLink: messageURL), thread.id)
        XCTAssertEqual(ChatThread.deepLinkTarget(fromDeepLink: messageURL), ChatDeepLinkTarget(threadID: thread.id, messageID: messageID))
        XCTAssertEqual(ChatThread.deepLinkTarget(fromDeepLink: thread.deepLinkURL), ChatDeepLinkTarget(threadID: thread.id, messageID: nil))
        XCTAssertNil(ChatThread.threadID(fromDeepLink: URL(string: "openwebui-native://notes/\(thread.id.uuidString)")!))
        XCTAssertNil(ChatThread.threadID(fromDeepLink: URL(string: "https://example.com/chats/\(thread.id.uuidString)")!))
        XCTAssertNil(ChatThread.deepLinkTarget(fromDeepLink: URL(string: "openwebui-native://chats/\(thread.id.uuidString)/messages/not-a-uuid")!))
    }

    func testHandleAppURLSelectsChatThreadAndClearsOtherDetailSelections() async throws {
        let fixture = try StoreFixture()
        let threadID = UUID(uuidString: "00000000-0000-0000-0000-000000000789")!
        let messageID = UUID(uuidString: "00000000-0000-0000-0000-000000000987")!
        let thread = ChatThread(
            id: threadID,
            title: "Linked Chat",
            messages: [
                ChatMessage(id: messageID, role: .assistant, content: "Linked answer")
            ]
        )
        try await fixture.storage.save(thread)

        let store = fixture.makeStore()
        await store.load()
        store.isShowingAnalyticsDashboard = true
        store.isShowingPlayground = true
        store.focusedChatMessageID = UUID()

        let handled = store.handleAppURL(URL(string: "openwebui-native://chats/\(threadID.uuidString)")!)

        XCTAssertTrue(handled)
        XCTAssertEqual(store.selectedThreadID, threadID)
        XCTAssertNil(store.focusedChatMessageID)
        XCTAssertFalse(store.isShowingAnalyticsDashboard)
        XCTAssertFalse(store.isShowingPlayground)

        store.isShowingAnalyticsDashboard = true
        store.focusedChatMessageID = nil

        let handledMessage = store.handleAppURL(URL(string: "openwebui-native://chats/\(threadID.uuidString)/messages/\(messageID.uuidString)")!)

        XCTAssertTrue(handledMessage)
        XCTAssertEqual(store.selectedThreadID, threadID)
        XCTAssertEqual(store.focusedChatMessageID, messageID)
        XCTAssertFalse(store.isShowingAnalyticsDashboard)
    }

    func testMessageLinkFindsOwningThread() async throws {
        let fixture = try StoreFixture()
        let messageID = UUID(uuidString: "00000000-0000-0000-0000-000000000321")!
        let thread = ChatThread(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000123")!,
            title: "Owning Chat",
            messages: [
                ChatMessage(id: messageID, role: .user, content: "Where am I?")
            ]
        )
        try await fixture.storage.save(thread)

        let store = fixture.makeStore()
        await store.load()

        XCTAssertEqual(
            store.messageLink(for: messageID)?.absoluteString,
            "openwebui-native://chats/00000000-0000-0000-0000-000000000123/messages/00000000-0000-0000-0000-000000000321"
        )
        XCTAssertNil(store.messageLink(for: UUID()))
    }

    func testRegenerateAssistantMessageReplacesContentFromParentUserPrompt() async throws {
        let fixture = try StoreFixture(provider: FakeChatProvider(chunks: ["New", " answer"]))
        let userID = UUID()
        let assistantID = UUID()
        let thread = ChatThread(
            id: UUID(),
            title: "Regenerate",
            providerID: ProviderConfiguration.defaultOllamaID,
            modelIDs: ["fake-model"],
            messages: [
                ChatMessage(id: userID, role: .user, content: "Try again"),
                ChatMessage(id: assistantID, role: .assistant, content: "Old answer", modelID: "fake-model")
            ]
        )
        try await fixture.storage.save(thread)

        let store = fixture.makeStore()
        await store.load()
        await store.selectModel("fake-model")

        await store.regenerateResponse(messageID: assistantID)

        XCTAssertEqual(store.selectedThread?.messages.first { $0.id == assistantID }?.content, "New answer")
    }

    func testRegenerateAssistantMessageBlocksUnsupportedChatProviderBeforeClearingContent() async throws {
        let provider = UnsupportedRegenerateChatProvider()
        let fixture = try StoreFixture(provider: provider)
        let userID = UUID()
        let assistantID = UUID()
        let thread = ChatThread(
            id: UUID(),
            title: "Regenerate",
            providerID: ProviderConfiguration.defaultOllamaID,
            modelIDs: ["fake-model"],
            messages: [
                ChatMessage(id: userID, role: .user, content: "Try again"),
                ChatMessage(id: assistantID, role: .assistant, content: "Old answer", modelID: "fake-model")
            ]
        )
        try await fixture.storage.save(thread)

        let store = fixture.makeStore()
        await store.load()
        await store.selectModel("fake-model")

        await store.regenerateResponse(messageID: assistantID)

        let message = try XCTUnwrap(store.selectedThread?.messages.first { $0.id == assistantID })
        XCTAssertEqual(message.content, "Old answer")
        XCTAssertFalse(message.isStreaming)
        XCTAssertNil(message.error)
        XCTAssertEqual(store.errorMessage, "Ollama does not support native chat.")
        XCTAssertEqual(provider.streamCallCount, 0)
    }
}

private struct StoreFixture {
    let rootURL: URL
    let storage: JSONStorageService
    let folderStorage: JSONFolderStorageService
    let settingsURL: URL
    let settingsStore: SettingsStore
    let provider: (any ChatProvider)?
    let shareService: FakeChatShareService?

    init(provider: (any ChatProvider)? = nil, shareService: FakeChatShareService? = nil) throws {
        rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        storage = JSONStorageService(rootURL: rootURL.appendingPathComponent("Chats", isDirectory: true))
        folderStorage = JSONFolderStorageService(rootURL: rootURL.appendingPathComponent("Folders", isDirectory: true))
        settingsURL = rootURL.appendingPathComponent("settings.json")
        settingsStore = SettingsStore(settingsURL: settingsURL)
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
            shareService: shareService ?? FakeChatShareService()
        )
    }
}

@MainActor
private final class FakeChatShareService: ChatSharing {
    var sharedText: String?
    var sharedTitle: String?

    func share(text: String, title: String) {
        sharedText = text
        sharedTitle = title
    }
}

private struct FakeChatProvider: ChatProvider {
    var configuration = ProviderConfiguration.defaultOllama()
    var chunks: [String]

    func listModels() async throws -> [ProviderModel] {
        [ProviderModel(id: "fake-model", name: "fake-model", provider: .ollama, providerID: configuration.id)]
    }

    func healthCheck() async -> ProviderStatus {
        .available("Fake connected")
    }

    func streamChat(model: String, messages: [ProviderChatMessage]) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            for chunk in chunks {
                continuation.yield(chunk)
            }
            continuation.finish()
        }
    }

    func createEmbeddings(model: String, input: [String]) async throws -> [[Double]] {
        []
    }
}

private final class UnsupportedRegenerateChatProvider: ChatProvider {
    var configuration = ProviderConfiguration.defaultOllama()
    private(set) var streamCallCount = 0

    var capabilities: ProviderCapabilities {
        var capabilities = configuration.capabilities
        capabilities.supportsChat = false
        return capabilities
    }

    func listModels() async throws -> [ProviderModel] {
        [ProviderModel(id: "fake-model", name: "fake-model", provider: .ollama, providerID: configuration.id)]
    }

    func healthCheck() async -> ProviderStatus {
        .available("Fake connected")
    }

    func streamChat(model: String, messages: [ProviderChatMessage]) -> AsyncThrowingStream<String, Error> {
        streamCallCount += 1
        return AsyncThrowingStream { continuation in
            continuation.yield("Unsupported answer")
            continuation.finish()
        }
    }

    func createEmbeddings(model: String, input: [String]) async throws -> [[Double]] {
        []
    }
}
