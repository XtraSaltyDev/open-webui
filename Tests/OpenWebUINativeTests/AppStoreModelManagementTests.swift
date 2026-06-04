import Foundation
import XCTest
@testable import OpenWebUINative

@MainActor
final class AppStoreModelManagementTests: XCTestCase {
    func testPullOllamaModelStreamsStatusRefreshesModelsAndClearsDraftName() async throws {
        let provider = FakeModelManagingProvider()
        let fixture = try ModelManagementFixture(provider: provider)
        let store = fixture.makeStore()
        await store.load()

        store.newOllamaModelName = " gemma3 "
        await store.pullOllamaModel()

        let pulledModels = await provider.pulledModelNames()
        XCTAssertEqual(pulledModels, ["gemma3"])
        XCTAssertEqual(store.modelPullStatus, "success")
        XCTAssertFalse(store.isPullingModel)
        XCTAssertEqual(store.newOllamaModelName, "")
        XCTAssertEqual(store.models.map(\.id), ["llama3.2:latest", "gemma3"])
    }

    func testDeleteSelectedOllamaModelDeletesRefreshesAndClearsSelection() async throws {
        let provider = FakeModelManagingProvider()
        let fixture = try ModelManagementFixture(provider: provider)
        let store = fixture.makeStore()
        await store.load()
        await store.selectModel("gemma3")

        await store.deleteSelectedOllamaModel()

        let deletedModels = await provider.deletedModelNames()
        XCTAssertEqual(deletedModels, ["gemma3"])
        XCTAssertFalse(store.isDeletingModel)
        XCTAssertEqual(store.models.map(\.id), ["llama3.2:latest"])
        XCTAssertEqual(store.selectedModelID, "llama3.2:latest")
    }

    func testModelManagementAvailabilityUsesProviderCapabilities() async throws {
        let provider = UnsupportedModelManagingProvider()
        let fixture = try ModelManagementFixture(provider: provider)
        let store = fixture.makeStore()
        await store.load()

        XCTAssertFalse(store.canManageOllamaModels)
    }

    func testPullOllamaModelBlocksUnsupportedCapabilityBeforeCallingManager() async throws {
        let provider = UnsupportedModelManagingProvider()
        let fixture = try ModelManagementFixture(provider: provider)
        let store = fixture.makeStore()
        await store.load()

        store.newOllamaModelName = " gemma3 "
        await store.pullOllamaModel()

        let pulledModels = await provider.pulledModelNames()
        XCTAssertEqual(pulledModels, [])
        XCTAssertEqual(store.errorMessage, "Ollama does not support native model management.")
        XCTAssertFalse(store.isPullingModel)
        XCTAssertNil(store.modelPullStatus)
        XCTAssertEqual(store.newOllamaModelName, " gemma3 ")
    }

    func testDeleteSelectedOllamaModelBlocksUnsupportedCapabilityBeforeCallingManager() async throws {
        let provider = UnsupportedModelManagingProvider()
        let fixture = try ModelManagementFixture(provider: provider)
        let store = fixture.makeStore()
        await store.load()
        await store.selectModel("fake-model")

        await store.deleteSelectedOllamaModel()

        let deletedModels = await provider.deletedModelNames()
        XCTAssertEqual(deletedModels, [])
        XCTAssertEqual(store.errorMessage, "Ollama does not support native model management.")
        XCTAssertFalse(store.isDeletingModel)
    }
}

private struct ModelManagementFixture {
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

private actor FakeModelManagingProvider: ChatProvider, OllamaModelManaging {
    nonisolated var configuration: ProviderConfiguration {
        ProviderConfiguration.defaultOllama()
    }

    private(set) var pulledModels: [String] = []
    private(set) var deletedModels: [String] = []

    func listModels() async throws -> [ProviderModel] {
        var modelIDs = ["llama3.2:latest"]
        if !pulledModels.isEmpty, deletedModels.isEmpty {
            modelIDs.append(contentsOf: pulledModels)
        }
        return modelIDs.map {
            ProviderModel(id: $0, name: $0, provider: .ollama, providerID: configuration.id)
        }
    }

    func healthCheck() async -> ProviderStatus {
        .available("Fake connected")
    }

    nonisolated func streamChat(model: String, messages: [ProviderChatMessage]) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish()
        }
    }

    func createEmbeddings(model: String, input: [String]) async throws -> [[Double]] {
        []
    }

    nonisolated func pullModel(named name: String) -> AsyncThrowingStream<OllamaModelPullProgress, Error> {
        AsyncThrowingStream { continuation in
            Task {
                await appendPulledModel(name)
                continuation.yield(OllamaModelPullProgress(status: "pulling manifest"))
                continuation.yield(OllamaModelPullProgress(status: "success"))
                continuation.finish()
            }
        }
    }

    func deleteModel(named name: String) async throws {
        deletedModels.append(name)
    }

    func pulledModelNames() -> [String] {
        pulledModels
    }

    func deletedModelNames() -> [String] {
        deletedModels
    }

    private func appendPulledModel(_ name: String) {
        pulledModels.append(name)
    }
}

private actor UnsupportedModelManagingProvider: ChatProvider, OllamaModelManaging {
    nonisolated var configuration: ProviderConfiguration {
        ProviderConfiguration.defaultOllama()
    }

    nonisolated var capabilities: ProviderCapabilities {
        var capabilities = ProviderConfiguration.defaultOllama().capabilities
        capabilities.supportsModelManagement = false
        return capabilities
    }

    private(set) var pulledModels: [String] = []
    private(set) var deletedModels: [String] = []

    func listModels() async throws -> [ProviderModel] {
        [ProviderModel(id: "fake-model", name: "fake-model", provider: .ollama, providerID: configuration.id)]
    }

    func healthCheck() async -> ProviderStatus {
        .available("Fake connected")
    }

    nonisolated func streamChat(model: String, messages: [ProviderChatMessage]) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish()
        }
    }

    func createEmbeddings(model: String, input: [String]) async throws -> [[Double]] {
        []
    }

    nonisolated func pullModel(named name: String) -> AsyncThrowingStream<OllamaModelPullProgress, Error> {
        AsyncThrowingStream { continuation in
            Task {
                await appendPulledModel(name)
                continuation.yield(OllamaModelPullProgress(status: "unsupported pull"))
                continuation.finish()
            }
        }
    }

    func deleteModel(named name: String) async throws {
        deletedModels.append(name)
    }

    func pulledModelNames() -> [String] {
        pulledModels
    }

    func deletedModelNames() -> [String] {
        deletedModels
    }

    private func appendPulledModel(_ name: String) {
        pulledModels.append(name)
    }
}
