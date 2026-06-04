import Foundation
import XCTest
@testable import OpenWebUINative

@MainActor
final class AppStoreTagSearchTests: XCTestCase {
    func testAddTagNormalizesDeduplicatesAndPersistsThread() async throws {
        let fixture = try TagSearchFixture()
        let thread = ChatThread(id: UUID(), title: "Tagged")
        try await fixture.chatStorage.save(thread)

        let store = fixture.makeStore()
        await store.load()

        await store.addTag(" Research ", to: thread.id)
        await store.addTag("#research", to: thread.id)

        XCTAssertEqual(store.threads.first?.tags, ["research"])
        let saved = try await fixture.chatStorage.loadThreads()
        XCTAssertEqual(saved.first?.tags, ["research"])
    }

    func testRemoveTagPersistsThread() async throws {
        let fixture = try TagSearchFixture()
        let thread = ChatThread(id: UUID(), title: "Tagged", tags: ["research", "draft"])
        try await fixture.chatStorage.save(thread)

        let store = fixture.makeStore()
        await store.load()

        await store.removeTag("research", from: thread.id)

        XCTAssertEqual(store.threads.first?.tags, ["draft"])
        let saved = try await fixture.chatStorage.loadThreads()
        XCTAssertEqual(saved.first?.tags, ["draft"])
    }

    func testFilteredThreadsSearchesTitleTagsModelsAndMessages() async throws {
        let fixture = try TagSearchFixture()
        let first = ChatThread(
            id: UUID(),
            title: "Local Models",
            modelIDs: ["llama3.2:latest"],
            tags: ["research"],
            messages: [ChatMessage(role: .user, content: "Compare latency")]
        )
        let second = ChatThread(
            id: UUID(),
            title: "Cooking",
            modelIDs: ["gpt-4.1-mini"],
            tags: ["home"],
            messages: [ChatMessage(role: .user, content: "Pasta recipe")]
        )
        try await fixture.chatStorage.save(first)
        try await fixture.chatStorage.save(second)

        let store = fixture.makeStore()
        await store.load()

        store.sidebarSearchText = "research"
        XCTAssertEqual(store.filteredThreads().map(\.id), [first.id])

        store.sidebarSearchText = "gpt-4.1"
        XCTAssertEqual(store.filteredThreads().map(\.id), [second.id])

        store.sidebarSearchText = "latency"
        XCTAssertEqual(store.filteredThreads().map(\.id), [first.id])
    }

    func testFilteredThreadsSupportsPinnedAndArchivedSearchOperators() async throws {
        let fixture = try TagSearchFixture()
        let pinned = ChatThread(
            id: UUID(),
            title: "Pinned plan",
            updatedAt: Date(timeIntervalSince1970: 30),
            isPinned: true
        )
        let unpinned = ChatThread(
            id: UUID(),
            title: "Regular plan",
            updatedAt: Date(timeIntervalSince1970: 20)
        )
        let archivedPinned = ChatThread(
            id: UUID(),
            title: "Archived plan",
            updatedAt: Date(timeIntervalSince1970: 10),
            isPinned: true,
            isArchived: true
        )
        try await fixture.chatStorage.save(pinned)
        try await fixture.chatStorage.save(unpinned)
        try await fixture.chatStorage.save(archivedPinned)

        let store = fixture.makeStore()
        await store.load()

        store.sidebarSearchText = "pinned:true"
        XCTAssertEqual(store.filteredThreads().map(\.id), [pinned.id])
        XCTAssertEqual(store.filteredArchivedThreads().map(\.id), [archivedPinned.id])

        store.sidebarSearchText = "pinned:false"
        XCTAssertEqual(store.filteredThreads().map(\.id), [unpinned.id])
        XCTAssertEqual(store.filteredArchivedThreads().map(\.id), [])

        store.sidebarSearchText = "archived:false plan"
        XCTAssertEqual(store.filteredThreads().map(\.id), [pinned.id, unpinned.id])
        XCTAssertEqual(store.filteredArchivedThreads().map(\.id), [])

        store.sidebarSearchText = "archived:true plan"
        XCTAssertEqual(store.filteredThreads().map(\.id), [])
        XCTAssertEqual(store.filteredArchivedThreads().map(\.id), [archivedPinned.id])
    }

    func testFilteredThreadsSupportsTagAndFolderSearchOperators() async throws {
        let fixture = try TagSearchFixture()
        let folder = ChatFolder(id: UUID(), name: "Projects")
        let otherFolder = ChatFolder(id: UUID(), name: "Archive")
        try await fixture.folderStorage.save(folder)
        try await fixture.folderStorage.save(otherFolder)
        let projectThread = ChatThread(
            id: UUID(),
            title: "Latency notes",
            updatedAt: Date(timeIntervalSince1970: 30),
            folderID: folder.id,
            tags: ["research"],
            messages: [ChatMessage(role: .user, content: "Compare local model latency")]
        )
        let otherThread = ChatThread(
            id: UUID(),
            title: "Meal plan",
            updatedAt: Date(timeIntervalSince1970: 20),
            tags: ["home"]
        )
        try await fixture.chatStorage.save(projectThread)
        try await fixture.chatStorage.save(otherThread)

        let store = fixture.makeStore()
        await store.load()

        store.sidebarSearchText = "tag:research latency"
        XCTAssertEqual(store.filteredThreads(folderID: folder.id).map(\.id), [projectThread.id])
        XCTAssertEqual(store.filteredThreads().map(\.id), [])

        store.sidebarSearchText = "tag:home"
        XCTAssertEqual(store.filteredThreads().map(\.id), [otherThread.id])
        XCTAssertEqual(store.filteredThreads(folderID: folder.id).map(\.id), [])

        store.sidebarSearchText = "folder:projects latency"
        XCTAssertEqual(store.filteredThreads(folderID: folder.id).map(\.id), [projectThread.id])
        XCTAssertEqual(store.filteredThreads().map(\.id), [])

        store.sidebarSearchText = "folder:archive"
        XCTAssertEqual(store.filteredThreads(folderID: folder.id).map(\.id), [])
        XCTAssertEqual(store.filteredThreads().map(\.id), [])
    }

    func testChatTranscriptSearchFindsVisibleMessagesAndSelectsThread() async throws {
        let fixture = try TagSearchFixture()
        let matchingThreadID = UUID(uuidString: "00000000-0000-0000-0000-000000005EA1")!
        let hiddenThreadID = UUID(uuidString: "00000000-0000-0000-0000-000000005EA2")!
        let matchingMessageID = UUID(uuidString: "00000000-0000-0000-0000-000000005EB1")!
        let matchingThread = ChatThread(
            id: matchingThreadID,
            title: "Visible Build Notes",
            messages: [
                ChatMessage(
                    id: matchingMessageID,
                    role: .assistant,
                    content: "Native transcript search should find this message."
                )
            ]
        )
        let hiddenThread = ChatThread(
            id: hiddenThreadID,
            title: "Hidden Archive",
            isArchived: true,
            messages: [
                ChatMessage(role: .assistant, content: "Native transcript search should not surface archived matches.")
            ]
        )
        try await fixture.chatStorage.save(matchingThread)
        try await fixture.chatStorage.save(hiddenThread)

        let store = fixture.makeStore()
        await store.load()

        store.chatTranscriptSearchText = "transcript"

        XCTAssertEqual(store.chatTranscriptSearchResults.map(\.threadID), [matchingThreadID])
        let result = try XCTUnwrap(store.chatTranscriptSearchResults.first)

        store.selectChatSearchResult(result)

        XCTAssertEqual(store.selectedThreadID, matchingThreadID)
        XCTAssertEqual(store.focusedChatMessageID, matchingMessageID)
        XCTAssertEqual(store.chatTranscriptSearchText, "")
        XCTAssertTrue(store.chatTranscriptSearchResults.isEmpty)
    }
}

private struct TagSearchFixture {
    let rootURL: URL
    let chatStorage: JSONStorageService
    let folderStorage: JSONFolderStorageService
    let settingsStore: SettingsStore

    init() throws {
        rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        chatStorage = JSONStorageService(rootURL: rootURL.appendingPathComponent("Chats", isDirectory: true))
        folderStorage = JSONFolderStorageService(rootURL: rootURL.appendingPathComponent("Folders", isDirectory: true))
        settingsStore = SettingsStore(settingsURL: rootURL.appendingPathComponent("settings.json"))
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
    }

    @MainActor
    func makeStore() -> AppStore {
        AppStore(
            storage: chatStorage,
            folderStorage: folderStorage,
            settingsStore: settingsStore,
            secretStore: InMemorySecretStore(),
            providerOverride: FakeTagSearchProvider()
        )
    }
}

private struct FakeTagSearchProvider: ChatProvider {
    var configuration = ProviderConfiguration.defaultOllama()

    func listModels() async throws -> [ProviderModel] {
        [ProviderModel(id: "fake-model", name: "fake-model", provider: .ollama, providerID: configuration.id)]
    }

    func healthCheck() async -> ProviderStatus {
        .available("Fake connected")
    }

    func streamChat(model: String, messages: [ProviderChatMessage]) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish()
        }
    }

    func createEmbeddings(model: String, input: [String]) async throws -> [[Double]] {
        []
    }
}
