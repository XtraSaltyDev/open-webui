import Foundation
import XCTest
@testable import OpenWebUINative

@MainActor
final class AppStoreModelRefreshTests: XCTestCase {
    func testLiveOllamaTagsReplaceStaleModelList() async throws {
        let provider = RefreshableModelProvider(models: [
            ProviderModel.ollamaTestModel(id: "stale-model"),
            ProviderModel.ollamaTestModel(id: "llama3.2")
        ])
        let fixture = try ModelRefreshFixture(provider: provider)
        let store = fixture.makeStore()
        await store.load()
        store.models = [ProviderModel.ollamaTestModel(id: "stale-model")]
        await provider.setModels([ProviderModel.ollamaTestModel(id: "llama3.2")])

        await store.refreshModels()

        XCTAssertEqual(store.models.map(\.id), ["llama3.2"])
        XCTAssertEqual(store.modelRefreshSourceLabel, "Live Ollama /api/tags")
        XCTAssertEqual(store.modelRefreshStateLabel, "Live")
    }

    func testStaleSelectedModelIsRemovedAfterRefresh() async throws {
        let provider = RefreshableModelProvider(models: [
            ProviderModel.ollamaTestModel(id: "llama3.2")
        ])
        let fixture = try ModelRefreshFixture(provider: provider)
        let store = fixture.makeStore()
        await store.load()
        store.settings.selectedModelID = "missing-model"
        store.settings.selectedModelIDs = ["missing-model"]

        await store.refreshModels()

        XCTAssertEqual(store.models.map(\.id), ["llama3.2"])
        XCTAssertEqual(store.settings.selectedModelID, "llama3.2")
        XCTAssertEqual(store.settings.selectedModelIDs, ["llama3.2"])
    }

    func testNoLiveOllamaModelsDoesNotInjectFakeSelectableModel() async throws {
        let provider = RefreshableModelProvider(models: [])
        let fixture = try ModelRefreshFixture(provider: provider)
        let store = fixture.makeStore()
        await store.load()
        store.models = [ProviderModel.ollamaTestModel(id: "stale-model")]
        store.settings.selectedModelID = "stale-model"
        store.settings.selectedModelIDs = ["stale-model"]
        store.newOllamaModelName = ""

        await store.refreshModels()

        XCTAssertEqual(store.models, [])
        XCTAssertNil(store.settings.selectedModelID)
        XCTAssertEqual(store.settings.selectedModelIDs, [])
        XCTAssertNil(store.selectedModelID)
        XCTAssertEqual(store.newOllamaModelName, "")
        XCTAssertEqual(store.modelRefreshSourceLabel, "Live Ollama /api/tags")
        XCTAssertEqual(store.modelRefreshStateLabel, "Empty")
    }

    func testPullSuccessRefreshesAndSelectsPulledModelOnlyWhenReturnedByTags() async throws {
        let provider = PullingRefreshableModelProvider(models: [
            ProviderModel.ollamaTestModel(id: "llama3.2")
        ])
        let fixture = try ModelRefreshFixture(provider: provider)
        let store = fixture.makeStore()
        await store.load()
        await store.selectModel("llama3.2")
        store.newOllamaModelName = " gemma3 "

        await store.pullOllamaModel()

        let pulledModelNames = await provider.pulledModelNames()
        let listModelCallCount = await provider.listModelCallCount()
        XCTAssertEqual(pulledModelNames, ["gemma3"])
        XCTAssertEqual(listModelCallCount, 2)
        XCTAssertEqual(store.models.map(\.id), ["llama3.2"])
        XCTAssertEqual(store.selectedModelID, "llama3.2")

        await provider.setModels([
            ProviderModel.ollamaTestModel(id: "llama3.2"),
            ProviderModel.ollamaTestModel(id: "gemma3")
        ])
        store.newOllamaModelName = " gemma3 "

        await store.pullOllamaModel()

        XCTAssertEqual(store.models.map(\.id), ["llama3.2", "gemma3"])
        XCTAssertEqual(store.selectedModelID, "gemma3")
    }

    func testModelRefreshFailureDoesNotClearDraftAndReportsRefreshError() async throws {
        let provider = RefreshableModelProvider(models: [
            ProviderModel.ollamaTestModel(id: "llama3.2")
        ])
        let fixture = try ModelRefreshFixture(provider: provider)
        let store = fixture.makeStore()
        await store.load()
        store.draftPrompt = "Do not lose this"
        await provider.setFailure(ProviderError.invalidResponse)

        await store.refreshModels()

        XCTAssertEqual(store.draftPrompt, "Do not lose this")
        XCTAssertEqual(store.models, [])
        XCTAssertEqual(store.modelRefreshStateLabel, "Failed")
        XCTAssertEqual(store.lastModelRefreshError, "Ollama returned a response this app could not read. Refresh models or try again.")
    }

    func testDuplicateModelsAreDedupedByIDAndProvider() async throws {
        let provider = RefreshableModelProvider(models: [
            ProviderModel.ollamaTestModel(id: "llama3.2", details: "first"),
            ProviderModel.ollamaTestModel(id: "llama3.2", details: "duplicate"),
            ProviderModel.ollamaTestModel(id: "gemma3")
        ])
        let fixture = try ModelRefreshFixture(provider: provider)
        let store = fixture.makeStore()
        await store.load()

        XCTAssertEqual(store.models.map(\.id), ["llama3.2", "gemma3"])
        XCTAssertEqual(store.models.first?.details, "first")
    }
}

private struct ModelRefreshFixture {
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

private actor RefreshableModelProvider: ChatProvider {
    nonisolated var configuration: ProviderConfiguration {
        ProviderConfiguration.defaultOllama()
    }

    private var models: [ProviderModel]
    private var failure: Error?
    private var listCalls = 0

    init(models: [ProviderModel]) {
        self.models = models
    }

    func listModels() async throws -> [ProviderModel] {
        listCalls += 1
        if let failure {
            throw failure
        }
        return models
    }

    func setModels(_ models: [ProviderModel]) {
        self.models = models
        failure = nil
    }

    func setFailure(_ failure: Error) {
        self.failure = failure
    }

    func listModelCallCount() -> Int {
        listCalls
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
}

private actor PullingRefreshableModelProvider: ChatProvider, OllamaModelManaging {
    nonisolated var configuration: ProviderConfiguration {
        ProviderConfiguration.defaultOllama()
    }

    private var models: [ProviderModel]
    private var pulledModels: [String] = []
    private var listCalls = 0

    init(models: [ProviderModel]) {
        self.models = models
    }

    func listModels() async throws -> [ProviderModel] {
        listCalls += 1
        return models
    }

    func setModels(_ models: [ProviderModel]) {
        self.models = models
    }

    func listModelCallCount() -> Int {
        listCalls
    }

    func pulledModelNames() -> [String] {
        pulledModels
    }

    nonisolated func pullModel(named name: String) -> AsyncThrowingStream<OllamaModelPullProgress, Error> {
        AsyncThrowingStream { continuation in
            Task {
                await appendPulledModel(name)
                continuation.yield(OllamaModelPullProgress(status: "success"))
                continuation.finish()
            }
        }
    }

    func deleteModel(named name: String) async throws {}

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

    private func appendPulledModel(_ name: String) {
        pulledModels.append(name)
    }
}

private extension ProviderModel {
    static func ollamaTestModel(id: String, details: String? = nil) -> ProviderModel {
        ProviderModel(
            id: id,
            name: id,
            provider: .ollama,
            providerID: ProviderConfiguration.defaultOllamaID,
            details: details
        )
    }
}
