import Foundation
import XCTest
@testable import OpenWebUINative

@MainActor
final class AppStoreSidebarStabilityTests: XCTestCase {
    func testTypingDraftDoesNotChangeThreadOrderSelectionOrUpdatedAt() async throws {
        let fixture = try SidebarStabilityFixture(provider: CountingSidebarProvider())
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
        store.selectedThreadID = olderThread.id

        let initialOrder = store.filteredThreads().map(\.id)
        let initialUpdatedAt = try XCTUnwrap(store.threads.first { $0.id == olderThread.id }?.updatedAt)

        store.draftPrompt = "h"
        store.draftPrompt = "hello"
        store.draftPrompt = "hello from a longer draft"

        XCTAssertEqual(store.filteredThreads().map(\.id), initialOrder)
        XCTAssertEqual(store.selectedThreadID, olderThread.id)
        XCTAssertEqual(store.threads.first { $0.id == olderThread.id }?.updatedAt, initialUpdatedAt)
    }

    func testDraftTypingDoesNotRefreshModels() async throws {
        let provider = CountingSidebarProvider()
        let fixture = try SidebarStabilityFixture(provider: provider)
        let store = fixture.makeStore()
        await store.load()
        let initialRefreshCount = await provider.listModelCallCount()

        store.draftPrompt = "one"
        store.draftPrompt = "one two"
        store.draftPrompt = "one two three"

        let finalRefreshCount = await provider.listModelCallCount()
        XCTAssertEqual(finalRefreshCount, initialRefreshCount)
    }

    func testStreamingChunksDoNotUpdateSidebarThreadTimestampBeforeSendFinalizes() async throws {
        let provider = ControllableStreamingSidebarProvider()
        let fixture = try SidebarStabilityFixture(provider: provider)
        let selectedThread = ChatThread(
            id: UUID(),
            title: "Selected older chat",
            createdAt: Date(timeIntervalSince1970: 10),
            updatedAt: Date(timeIntervalSince1970: 20)
        )
        let otherThread = ChatThread(
            id: UUID(),
            title: "Other newer chat",
            createdAt: Date(timeIntervalSince1970: 30),
            updatedAt: Date(timeIntervalSince1970: 40)
        )
        try await fixture.storage.save(selectedThread)
        try await fixture.storage.save(otherThread)

        let store = fixture.makeStore()
        await store.load()
        store.selectedThreadID = selectedThread.id

        let sendTask = Task {
            await store.send("Keep the sidebar stable")
        }
        try await waitUntil {
            store.selectedThread?.messages.count == 2
        }
        let acceptedSendUpdatedAt = try XCTUnwrap(store.selectedThread?.updatedAt)

        await provider.yieldContent("A")
        try await waitUntil {
            store.selectedThread?.messages.last?.content == "A"
        }

        XCTAssertEqual(store.selectedThread?.updatedAt, acceptedSendUpdatedAt)

        await provider.finish()
        _ = await sendTask.value
    }

    func testAcceptedSendUpdatesThreadOrderIntentionally() async throws {
        let provider = CountingSidebarProvider(chunks: ["Answer"])
        let fixture = try SidebarStabilityFixture(provider: provider)
        let selectedThread = ChatThread(
            id: UUID(),
            title: "Selected older chat",
            createdAt: Date(timeIntervalSince1970: 10),
            updatedAt: Date(timeIntervalSince1970: 20)
        )
        let otherThread = ChatThread(
            id: UUID(),
            title: "Other newer chat",
            createdAt: Date(timeIntervalSince1970: 30),
            updatedAt: Date(timeIntervalSince1970: 40)
        )
        try await fixture.storage.save(selectedThread)
        try await fixture.storage.save(otherThread)

        let store = fixture.makeStore()
        await store.load()
        store.selectedThreadID = selectedThread.id

        await store.send("Move this chat after a real send")

        XCTAssertEqual(store.filteredThreads().map(\.id).first, selectedThread.id)
        XCTAssertEqual(store.selectedThreadID, selectedThread.id)
        XCTAssertGreaterThan(
            try XCTUnwrap(store.threads.first { $0.id == selectedThread.id }?.updatedAt),
            selectedThread.updatedAt
        )
    }
}

private struct SidebarStabilityFixture {
    let rootURL: URL
    let storage: JSONStorageService
    let settingsStore: SettingsStore
    let provider: any ChatProvider

    init(provider: any ChatProvider) throws {
        rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        storage = JSONStorageService(rootURL: rootURL.appendingPathComponent("Chats", isDirectory: true))
        settingsStore = SettingsStore(settingsURL: rootURL.appendingPathComponent("settings.json"))
        self.provider = provider
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
    }

    @MainActor
    func makeStore() -> AppStore {
        AppStore(
            storage: storage,
            settingsStore: settingsStore,
            secretStore: InMemorySecretStore(),
            providerOverride: provider
        )
    }
}

private actor CountingSidebarProvider: ChatProvider {
    nonisolated var configuration: ProviderConfiguration {
        ProviderConfiguration.defaultOllama()
    }

    private var listCalls = 0
    private let chunks: [String]

    init(chunks: [String] = []) {
        self.chunks = chunks
    }

    func listModels() async throws -> [ProviderModel] {
        listCalls += 1
        return [
            ProviderModel(
                id: "llama3.2",
                name: "llama3.2",
                provider: .ollama,
                providerID: ProviderConfiguration.defaultOllamaID
            )
        ]
    }

    func listModelCallCount() -> Int {
        listCalls
    }

    func healthCheck() async -> ProviderStatus {
        .available("Fake connected")
    }

    nonisolated func streamChat(model: String, messages: [ProviderChatMessage]) -> AsyncThrowingStream<String, Error> {
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

private actor ControllableStreamingSidebarProvider: ChatProvider {
    nonisolated var configuration: ProviderConfiguration {
        ProviderConfiguration.defaultOllama()
    }

    private var continuation: AsyncThrowingStream<ChatStreamEvent, Error>.Continuation?

    func listModels() async throws -> [ProviderModel] {
        [
            ProviderModel(
                id: "llama3.2",
                name: "llama3.2",
                provider: .ollama,
                providerID: ProviderConfiguration.defaultOllamaID
            )
        ]
    }

    func healthCheck() async -> ProviderStatus {
        .available("Fake connected")
    }

    nonisolated func streamChat(model: String, messages: [ProviderChatMessage]) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish()
        }
    }

    nonisolated func streamChatEvents(
        model: String,
        messages: [ProviderChatMessage],
        options: ProviderChatOptions?
    ) -> AsyncThrowingStream<ChatStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            Task {
                await setContinuation(continuation)
            }
        }
    }

    func createEmbeddings(model: String, input: [String]) async throws -> [[Double]] {
        []
    }

    func yieldContent(_ content: String) {
        continuation?.yield(.content(content))
    }

    func finish() {
        continuation?.finish()
        continuation = nil
    }

    private func setContinuation(_ continuation: AsyncThrowingStream<ChatStreamEvent, Error>.Continuation) {
        self.continuation = continuation
    }
}

@MainActor
private func waitUntil(
    timeoutNanoseconds: UInt64 = 1_000_000_000,
    predicate: @escaping @MainActor () -> Bool
) async throws {
    let step: UInt64 = 10_000_000
    var elapsed: UInt64 = 0
    while elapsed < timeoutNanoseconds {
        if predicate() {
            return
        }
        try await Task.sleep(nanoseconds: step)
        elapsed += step
    }
    XCTFail("Timed out waiting for condition.")
}
