import Foundation
import XCTest
@testable import OpenWebUINative

@MainActor
final class AppStoreMultiModelTests: XCTestCase {
    func testToggleSelectedModelPersistsMultipleModelIDs() async throws {
        let fixture = try MultiModelFixture(provider: FakeMultiModelProvider())
        let store = fixture.makeStore()
        await store.load()

        await store.setModel("model-a", selected: true)
        await store.setModel("model-b", selected: true)

        XCTAssertEqual(store.selectedModelIDs, ["model-a", "model-b"])

        let savedSettings = try await fixture.settingsStore.load()
        XCTAssertEqual(savedSettings.selectedModelIDs, ["model-a", "model-b"])
        XCTAssertEqual(savedSettings.selectedModelID, "model-a")
    }

    func testLegacySingleModelSelectionFeedsMultiModelSelectionWithoutRecursion() async throws {
        let fixture = try MultiModelFixture(provider: FakeMultiModelProvider())
        let store = fixture.makeStore()
        store.settings.selectedModelID = "model-a"
        store.settings.selectedModelIDs = []
        store.models = [
            ProviderModel(id: "model-a", name: "model-a", provider: .ollama, providerID: ProviderConfiguration.defaultOllama().id),
            ProviderModel(id: "model-b", name: "model-b", provider: .ollama, providerID: ProviderConfiguration.defaultOllama().id)
        ]

        XCTAssertEqual(store.selectedModelID, "model-a")
        XCTAssertEqual(store.selectedModelIDs, ["model-a"])
    }

    func testSendPromptCreatesAssistantResponseForEachSelectedModel() async throws {
        let provider = FakeMultiModelProvider()
        let fixture = try MultiModelFixture(provider: provider)
        let store = fixture.makeStore()
        await store.load()
        await store.setModel("model-a", selected: true)
        await store.setModel("model-b", selected: true)

        await store.send("Compare answers")

        let messages = try XCTUnwrap(store.selectedThread?.messages)
        XCTAssertEqual(messages.map(\.role), [.user, .assistant, .assistant])
        XCTAssertEqual(messages.filter { $0.role == .assistant }.map(\.modelID), ["model-a", "model-b"])
        XCTAssertEqual(messages.filter { $0.role == .assistant }.map(\.content), ["model-a answer", "model-b answer"])
        XCTAssertEqual(store.selectedThread?.modelIDs, ["model-a", "model-b"])

        let streamedModels = await provider.streamedModelIDs()
        XCTAssertEqual(streamedModels, ["model-a", "model-b"])
    }

    func testSendPromptRecordsGenerationTimingForAssistantBranches() async throws {
        let provider = SlowStreamingMultiModelProvider()
        let fixture = try MultiModelFixture(provider: provider)
        let store = fixture.makeStore()
        await store.load()
        await store.setModel("model-a", selected: true)
        await store.setModel("model-b", selected: true)

        await store.send("Compare answers")

        let messages = try XCTUnwrap(store.selectedThread?.messages)
        XCTAssertNil(messages.first { $0.role == .user }?.generationMetrics)

        let assistantMessages = messages.filter { $0.role == .assistant }
        XCTAssertEqual(assistantMessages.count, 2)
        XCTAssertTrue(assistantMessages.allSatisfy { $0.generationMetrics?.startedAt != nil })
        XCTAssertTrue(assistantMessages.allSatisfy { $0.generationMetrics?.completedAt != nil })
        XCTAssertTrue(assistantMessages.allSatisfy { ($0.generationMetrics?.durationSeconds ?? 0) > 0 })
    }

    func testSendPromptRecordsTokenUsageForAssistantBranches() async throws {
        let provider = TokenUsageMultiModelProvider()
        let fixture = try MultiModelFixture(provider: provider)
        let store = fixture.makeStore()
        await store.load()
        await store.setModel("model-a", selected: true)
        await store.setModel("model-b", selected: true)

        await store.send("Compare answers")

        let assistantMessages = try XCTUnwrap(store.selectedThread?.messages.filter { $0.role == .assistant })
        XCTAssertEqual(assistantMessages.map(\.content), ["model-a answer", "model-b answer"])
        XCTAssertEqual(assistantMessages.map(\.tokenUsage), [
            ChatTokenUsage(promptTokens: 10, completionTokens: 5, totalTokens: 15),
            ChatTokenUsage(promptTokens: 20, completionTokens: 7, totalTokens: 27)
        ])
    }

    func testSendPromptBlocksUnsupportedChatProviderBeforeCreatingThread() async throws {
        let provider = UnsupportedChatProvider()
        let fixture = try MultiModelFixture(provider: provider)
        let store = fixture.makeStore()
        await store.load()
        await store.setModel("model-a", selected: true)

        await store.send("Compare answers")

        XCTAssertEqual(store.errorMessage, "Ollama does not support native chat.")
        XCTAssertTrue(store.threads.isEmpty)
        XCTAssertNil(store.selectedThreadID)
        XCTAssertFalse(store.isSending)

        let streamCallCount = await provider.streamCallCount
        XCTAssertEqual(streamCallCount, 0)
    }

    func testSendPromptKeepsOtherModelBranchesWhenOneModelFails() async throws {
        let provider = FakeMultiModelProvider(failingModels: ["model-b"])
        let fixture = try MultiModelFixture(provider: provider)
        let store = fixture.makeStore()
        await store.load()
        await store.setModel("model-a", selected: true)
        await store.setModel("model-b", selected: true)
        await store.setModel("model-c", selected: true)

        await store.send("Compare answers")

        let assistantMessages = try XCTUnwrap(store.selectedThread?.messages.filter { $0.role == .assistant })
        XCTAssertEqual(assistantMessages.map(\.modelID), ["model-a", "model-b", "model-c"])
        XCTAssertEqual(assistantMessages.map(\.content), ["model-a answer", "", "model-c answer"])
        XCTAssertEqual(assistantMessages.map(\.isStreaming), [false, false, false])
        XCTAssertNil(assistantMessages[0].error)
        XCTAssertEqual(assistantMessages[1].error, "model-b failed")
        XCTAssertNil(assistantMessages[2].error)
        XCTAssertNil(store.errorMessage)

        let streamedModels = await provider.streamedModelIDs()
        XCTAssertEqual(Set(streamedModels), ["model-a", "model-b", "model-c"])
        XCTAssertEqual(streamedModels.count, 3)
    }

    func testSendPromptStreamsSelectedModelsConcurrently() async throws {
        let provider = ConcurrentMultiModelProvider()
        let fixture = try MultiModelFixture(provider: provider)
        let store = fixture.makeStore()
        await store.load()
        await store.setModel("model-a", selected: true)
        await store.setModel("model-b", selected: true)

        await store.send("Compare answers")

        let assistantMessages = try XCTUnwrap(store.selectedThread?.messages.filter { $0.role == .assistant })
        XCTAssertEqual(assistantMessages.map(\.content), ["model-a answer", "model-b answer"])
        let maxActiveStreamCount = await provider.maxActiveStreamCount
        XCTAssertGreaterThanOrEqual(maxActiveStreamCount, 2)
    }

    func testCancelCurrentSendStopsActiveModelBranches() async throws {
        let provider = SlowStreamingMultiModelProvider()
        let fixture = try MultiModelFixture(provider: provider)
        let store = fixture.makeStore()
        await store.load()
        await store.setModel("model-a", selected: true)
        await store.setModel("model-b", selected: true)

        let sendTask = Task {
            await store.send("Compare answers")
        }
        try await Task.sleep(nanoseconds: 35_000_000)
        store.cancelCurrentSend()
        _ = await sendTask.value

        let assistantMessages = try XCTUnwrap(store.selectedThread?.messages.filter { $0.role == .assistant })
        XCTAssertEqual(assistantMessages.map(\.isStreaming), [false, false])
        XCTAssertTrue(assistantMessages.allSatisfy { $0.error == nil })
        XCTAssertTrue(assistantMessages.allSatisfy { !$0.content.isEmpty })
        XCTAssertTrue(assistantMessages.allSatisfy { $0.content.count < 20 })
        XCTAssertFalse(store.isSending)
        XCTAssertFalse(store.isCancellingSend)
        XCTAssertNil(store.errorMessage)
    }

    func testCancelAssistantBranchStopsOnlyThatModelBranch() async throws {
        let provider = SlowStreamingMultiModelProvider()
        let fixture = try MultiModelFixture(provider: provider)
        let store = fixture.makeStore()
        await store.load()
        await store.setModel("model-a", selected: true)
        await store.setModel("model-b", selected: true)

        let sendTask = Task {
            await store.send("Compare answers")
        }
        try await Task.sleep(nanoseconds: 35_000_000)

        let streamingMessages = try XCTUnwrap(store.selectedThread?.messages.filter { $0.role == .assistant })
        let cancelledMessageID = try XCTUnwrap(streamingMessages.first?.id)
        store.cancelAssistantBranch(messageID: cancelledMessageID)
        _ = await sendTask.value

        let assistantMessages = try XCTUnwrap(store.selectedThread?.messages.filter { $0.role == .assistant })
        XCTAssertEqual(assistantMessages.map(\.modelID), ["model-a", "model-b"])
        XCTAssertEqual(assistantMessages.map(\.isStreaming), [false, false])
        XCTAssertTrue(assistantMessages[0].content.count < 20)
        XCTAssertEqual(assistantMessages[1].content.count, 20)
        XCTAssertTrue(assistantMessages.allSatisfy { $0.error == nil })
        XCTAssertFalse(store.isSending)
        XCTAssertFalse(store.isCancellingSend)
        XCTAssertNil(store.errorMessage)
    }

    func testChatGenerationProgressTextTracksActiveBranches() async throws {
        let provider = SlowStreamingMultiModelProvider()
        let fixture = try MultiModelFixture(provider: provider)
        let store = fixture.makeStore()
        await store.load()
        await store.setModel("model-a", selected: true)
        await store.setModel("model-b", selected: true)

        let sendTask = Task {
            await store.send("Compare answers")
        }
        try await Task.sleep(nanoseconds: 35_000_000)

        XCTAssertEqual(store.streamingAssistantBranchCount, 2)
        XCTAssertEqual(store.chatGenerationProgressText, "2 responses generating")

        let streamingMessages = try XCTUnwrap(store.selectedThread?.messages.filter { $0.role == .assistant })
        let cancelledMessageID = try XCTUnwrap(streamingMessages.first?.id)
        store.cancelAssistantBranch(messageID: cancelledMessageID)

        XCTAssertEqual(store.streamingAssistantBranchCount, 1)
        XCTAssertEqual(store.chatGenerationProgressText, "1 response generating")

        _ = await sendTask.value

        XCTAssertEqual(store.streamingAssistantBranchCount, 0)
        XCTAssertNil(store.chatGenerationProgressText)
    }

    func testCancelAssistantBranchCancelsUnderlyingProviderStream() async throws {
        let provider = CancellableBranchStreamProvider()
        let fixture = try MultiModelFixture(provider: provider)
        let store = fixture.makeStore()
        await store.load()
        await store.setModel("model-a", selected: true)
        await store.setModel("model-b", selected: true)

        let sendTask = Task {
            await store.send("Compare answers")
        }
        try await Task.sleep(nanoseconds: 35_000_000)

        let streamingMessages = try XCTUnwrap(store.selectedThread?.messages.filter { $0.role == .assistant })
        let cancelledMessageID = try XCTUnwrap(streamingMessages.first { $0.modelID == "model-a" }?.id)
        store.cancelAssistantBranch(messageID: cancelledMessageID)
        try await Task.sleep(nanoseconds: 50_000_000)

        let cancelledModels = await provider.cancelledStreamModels()
        XCTAssertEqual(cancelledModels, ["model-a"])

        _ = await sendTask.value
    }

    func testStreamingBranchFinalizesOriginalThreadAfterSelectingAnotherThread() async throws {
        let provider = SlowStreamingMultiModelProvider()
        let fixture = try MultiModelFixture(provider: provider)
        let store = fixture.makeStore()
        await store.load()
        await store.setModel("model-a", selected: true)

        let sendTask = Task {
            await store.send("Keep generating")
        }
        try await Task.sleep(nanoseconds: 35_000_000)
        let generatingThreadID = try XCTUnwrap(store.selectedThreadID)

        store.createThread()
        XCTAssertNotEqual(store.selectedThreadID, generatingThreadID)

        _ = await sendTask.value

        let originalThread = try XCTUnwrap(store.threads.first { $0.id == generatingThreadID })
        let assistantMessages = originalThread.messages.filter { $0.role == .assistant }
        XCTAssertEqual(assistantMessages.count, 1)
        XCTAssertEqual(assistantMessages.first?.content.count, 20)
        XCTAssertEqual(assistantMessages.first?.isStreaming, false)
        XCTAssertNil(assistantMessages.first?.error)
    }

    func testCancelCurrentSendDoesNotDuplicateAssistantMessages() async throws {
        let provider = SlowStreamingMultiModelProvider()
        let fixture = try MultiModelFixture(provider: provider)
        let store = fixture.makeStore()
        await store.load()
        await store.setModel("model-a", selected: true)
        await store.setModel("model-b", selected: true)

        let sendTask = Task {
            await store.send("Compare answers")
        }
        try await Task.sleep(nanoseconds: 35_000_000)
        store.cancelCurrentSend()
        _ = await sendTask.value

        let assistantMessages = try XCTUnwrap(store.selectedThread?.messages.filter { $0.role == .assistant })
        XCTAssertEqual(assistantMessages.count, 2)
        XCTAssertEqual(assistantMessages.map(\.modelID), ["model-a", "model-b"])
    }
}

private struct MultiModelFixture {
    let rootURL: URL
    let storage: JSONStorageService
    let settingsStore: SettingsStore
    let provider: (any ChatProvider)?

    init(provider: (any ChatProvider)? = nil) throws {
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

private actor FakeMultiModelProvider: ChatProvider {
    nonisolated var configuration: ProviderConfiguration {
        ProviderConfiguration.defaultOllama()
    }

    private var streamedModels: [String] = []
    private let failingModels: Set<String>

    init(failingModels: Set<String> = []) {
        self.failingModels = failingModels
    }

    func listModels() async throws -> [ProviderModel] {
        [
            ProviderModel(id: "model-a", name: "model-a", provider: .ollama, providerID: configuration.id),
            ProviderModel(id: "model-b", name: "model-b", provider: .ollama, providerID: configuration.id),
            ProviderModel(id: "model-c", name: "model-c", provider: .ollama, providerID: configuration.id)
        ]
    }

    func healthCheck() async -> ProviderStatus {
        .available("Fake connected")
    }

    nonisolated func streamChat(model: String, messages: [ProviderChatMessage]) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task {
                await appendStreamedModel(model)
                if await shouldFail(model) {
                    continuation.finish(throwing: NSError(domain: "FakeMultiModelProvider", code: 1, userInfo: [
                        NSLocalizedDescriptionKey: "\(model) failed"
                    ]))
                    return
                }
                continuation.yield("\(model) answer")
                continuation.finish()
            }
        }
    }

    func createEmbeddings(model: String, input: [String]) async throws -> [[Double]] {
        []
    }

    func streamedModelIDs() -> [String] {
        streamedModels
    }

    private func appendStreamedModel(_ model: String) {
        streamedModels.append(model)
    }

    private func shouldFail(_ model: String) -> Bool {
        failingModels.contains(model)
    }
}

private actor UnsupportedChatProvider: ChatProvider {
    nonisolated var configuration: ProviderConfiguration {
        ProviderConfiguration.defaultOllama()
    }

    nonisolated var capabilities: ProviderCapabilities {
        var capabilities = ProviderConfiguration.defaultOllama().capabilities
        capabilities.supportsChat = false
        return capabilities
    }

    private(set) var streamCallCount = 0

    func listModels() async throws -> [ProviderModel] {
        [
            ProviderModel(id: "model-a", name: "model-a", provider: .ollama, providerID: configuration.id)
        ]
    }

    func healthCheck() async -> ProviderStatus {
        .available("Fake connected")
    }

    nonisolated func streamChat(model: String, messages: [ProviderChatMessage]) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task {
                await recordStreamCall()
                continuation.yield("Unsupported answer")
                continuation.finish()
            }
        }
    }

    func createEmbeddings(model: String, input: [String]) async throws -> [[Double]] {
        []
    }

    private func recordStreamCall() {
        streamCallCount += 1
    }
}

private actor ConcurrentMultiModelProvider: ChatProvider {
    nonisolated var configuration: ProviderConfiguration {
        ProviderConfiguration.defaultOllama()
    }

    private var activeStreamCount = 0
    private(set) var maxActiveStreamCount = 0

    func listModels() async throws -> [ProviderModel] {
        [
            ProviderModel(id: "model-a", name: "model-a", provider: .ollama, providerID: configuration.id),
            ProviderModel(id: "model-b", name: "model-b", provider: .ollama, providerID: configuration.id)
        ]
    }

    func healthCheck() async -> ProviderStatus {
        .available("Fake connected")
    }

    nonisolated func streamChat(model: String, messages: [ProviderChatMessage]) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task {
                await beginStream()
                try? await Task.sleep(nanoseconds: 30_000_000)
                continuation.yield("\(model) answer")
                await endStream()
                continuation.finish()
            }
        }
    }

    func createEmbeddings(model: String, input: [String]) async throws -> [[Double]] {
        []
    }

    private func beginStream() {
        activeStreamCount += 1
        maxActiveStreamCount = max(maxActiveStreamCount, activeStreamCount)
    }

    private func endStream() {
        activeStreamCount -= 1
    }
}

private actor SlowStreamingMultiModelProvider: ChatProvider {
    nonisolated var configuration: ProviderConfiguration {
        ProviderConfiguration.defaultOllama()
    }

    func listModels() async throws -> [ProviderModel] {
        [
            ProviderModel(id: "model-a", name: "model-a", provider: .ollama, providerID: configuration.id),
            ProviderModel(id: "model-b", name: "model-b", provider: .ollama, providerID: configuration.id)
        ]
    }

    func healthCheck() async -> ProviderStatus {
        .available("Fake connected")
    }

    nonisolated func streamChat(model: String, messages: [ProviderChatMessage]) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task {
                for _ in 0..<20 {
                    try? await Task.sleep(nanoseconds: 10_000_000)
                    continuation.yield("x")
                }
                continuation.finish()
            }
        }
    }

    func createEmbeddings(model: String, input: [String]) async throws -> [[Double]] {
        []
    }
}

private actor TokenUsageMultiModelProvider: ChatProvider {
    nonisolated var configuration: ProviderConfiguration {
        ProviderConfiguration.defaultOllama()
    }

    func listModels() async throws -> [ProviderModel] {
        [
            ProviderModel(id: "model-a", name: "model-a", provider: .ollama, providerID: configuration.id),
            ProviderModel(id: "model-b", name: "model-b", provider: .ollama, providerID: configuration.id)
        ]
    }

    func healthCheck() async -> ProviderStatus {
        .available("Fake connected")
    }

    nonisolated func streamChat(model: String, messages: [ProviderChatMessage]) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            continuation.yield("\(model) answer")
            continuation.finish()
        }
    }

    nonisolated func streamChatEvents(
        model: String,
        messages: [ProviderChatMessage],
        options: ProviderChatOptions?
    ) -> AsyncThrowingStream<ChatStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            continuation.yield(.content("\(model) answer"))
            if model == "model-a" {
                continuation.yield(.tokenUsage(ChatTokenUsage(promptTokens: 10, completionTokens: 5, totalTokens: 15)))
            } else {
                continuation.yield(.tokenUsage(ChatTokenUsage(promptTokens: 20, completionTokens: 7, totalTokens: 27)))
            }
            continuation.finish()
        }
    }

    func createEmbeddings(model: String, input: [String]) async throws -> [[Double]] {
        []
    }
}

private actor CancellableBranchStreamProvider: ChatProvider {
    nonisolated var configuration: ProviderConfiguration {
        ProviderConfiguration.defaultOllama()
    }

    private var cancelledModels: [String] = []

    func listModels() async throws -> [ProviderModel] {
        [
            ProviderModel(id: "model-a", name: "model-a", provider: .ollama, providerID: configuration.id),
            ProviderModel(id: "model-b", name: "model-b", provider: .ollama, providerID: configuration.id)
        ]
    }

    func healthCheck() async -> ProviderStatus {
        .available("Fake connected")
    }

    nonisolated func streamChat(model: String, messages: [ProviderChatMessage]) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                continuation.yield("x")
                if model == "model-a" {
                    try? await Task.sleep(nanoseconds: 300_000_000)
                    continuation.yield("late")
                } else {
                    try? await Task.sleep(nanoseconds: 40_000_000)
                    continuation.yield("done")
                }
                continuation.finish()
            }
            continuation.onTermination = { termination in
                if case .cancelled = termination {
                    task.cancel()
                    Task {
                        await self.recordCancelledModel(model)
                    }
                }
            }
        }
    }

    func createEmbeddings(model: String, input: [String]) async throws -> [[Double]] {
        []
    }

    func cancelledStreamModels() -> [String] {
        cancelledModels
    }

    private func recordCancelledModel(_ model: String) {
        cancelledModels.append(model)
    }
}
