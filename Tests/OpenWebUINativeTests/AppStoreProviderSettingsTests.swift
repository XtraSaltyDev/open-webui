import Foundation
import XCTest
@testable import OpenWebUINative

@MainActor
final class AppStoreProviderSettingsTests: XCTestCase {
    func testCheckActiveProviderHealthUpdatesProviderStatusFromProvider() async throws {
        let fixture = try ProviderSettingsFixture()
        let provider = HealthCheckProvider(status: .available("Gateway reachable"))
        let store = fixture.makeStore(secretStore: InMemorySecretStore(), provider: provider)

        await store.checkActiveProviderHealth()

        XCTAssertEqual(store.providerStatus, .available("Gateway reachable"))
        let healthCheckCount = await provider.healthCheckCount
        XCTAssertEqual(healthCheckCount, 1)
    }

    func testLoadPersistsNormalizedSettingsAfterProviderMigration() async throws {
        let fixture = try ProviderSettingsFixture()
        let data = """
        {
          "ollamaBaseURL": "http://localhost:11434",
          "providers": [],
          "activeProviderID": "11111111-1111-1111-1111-111111111111"
        }
        """.data(using: .utf8)!
        try data.write(to: fixture.rootURL.appendingPathComponent("settings.json"))
        let store = fixture.makeStore(secretStore: InMemorySecretStore())

        await store.load()

        XCTAssertEqual(store.settings.providers.map(\.id), [ProviderConfiguration.defaultOllamaID])
        XCTAssertEqual(store.settings.activeProviderID, ProviderConfiguration.defaultOllamaID)

        let savedData = try Data(contentsOf: fixture.rootURL.appendingPathComponent("settings.json"))
        let savedObject = try XCTUnwrap(JSONSerialization.jsonObject(with: savedData) as? [String: Any])
        let savedProviders = try XCTUnwrap(savedObject["providers"] as? [[String: Any]])
        XCTAssertEqual(savedProviders.count, 1)
        XCTAssertEqual(savedProviders.first?["kind"] as? String, "ollama")
        XCTAssertEqual(savedObject["activeProviderID"] as? String, ProviderConfiguration.defaultOllamaID.uuidString)
    }

    func testSelectProviderRejectsUnknownProviderIDBeforePersisting() async throws {
        let fixture = try ProviderSettingsFixture()
        let provider = HealthCheckProvider(status: .available("Gateway reachable"))
        let store = fixture.makeStore(secretStore: InMemorySecretStore(), provider: provider)
        await store.load()

        await store.selectProvider(UUID())

        XCTAssertEqual(store.settings.activeProviderID, ProviderConfiguration.defaultOllamaID)
        XCTAssertEqual(store.errorMessage, "Selected provider is not available.")

        let savedSettings = try await fixture.settingsStore.load()
        XCTAssertEqual(savedSettings.activeProviderID, ProviderConfiguration.defaultOllamaID)
        let healthCheckCount = await provider.healthCheckCount
        XCTAssertEqual(healthCheckCount, 0)
    }

    func testSuccessfulProviderSelectionClearsPreviousSelectionError() async throws {
        let fixture = try ProviderSettingsFixture()
        let providerID = UUID()
        let gateway = ProviderConfiguration(
            id: providerID,
            name: "Gateway",
            kind: .openAICompatible,
            baseURL: "https://gateway.example/v1",
            apiKeySecretID: "secret"
        )
        let settings = AppSettings(
            providers: [
                ProviderConfiguration.defaultOllama(),
                gateway
            ],
            activeProviderID: ProviderConfiguration.defaultOllamaID,
            selectedModelID: "llama3.2",
            selectedModelIDs: ["llama3.2"],
            embeddingModelID: "nomic-embed-text"
        )
        try await fixture.settingsStore.save(settings)
        let provider = HealthCheckProvider(
            status: .available("Gateway reachable"),
            models: [
                ProviderModel(
                    id: "gpt-test",
                    name: "GPT Test",
                    provider: .openAICompatible,
                    providerID: providerID
                )
            ]
        )
        let store = fixture.makeStore(secretStore: InMemorySecretStore(), provider: provider)
        await store.load()

        await store.selectProvider(UUID())
        XCTAssertEqual(store.errorMessage, "Selected provider is not available.")

        await store.selectProvider(providerID)

        XCTAssertNil(store.errorMessage)
        XCTAssertEqual(store.settings.activeProviderID, providerID)
        XCTAssertEqual(store.settings.selectedModelID, "gpt-test")
        XCTAssertEqual(store.settings.selectedModelIDs, ["gpt-test"])
        XCTAssertNil(store.settings.embeddingModelID)
    }

    func testSelectingOllamaChecksRuntimeAndRefreshesModels() async throws {
        let fixture = try ProviderSettingsFixture()
        let providerID = UUID()
        let gateway = ProviderConfiguration(
            id: providerID,
            name: "Gateway",
            kind: .openAICompatible,
            baseURL: "https://gateway.example/v1",
            apiKeySecretID: "secret"
        )
        let settings = AppSettings(
            providers: [
                ProviderConfiguration.defaultOllama(),
                gateway
            ],
            activeProviderID: providerID
        )
        try await fixture.settingsStore.save(settings)
        let runtimeService = FakeOllamaRuntimeService(status: .reachable(version: "0.12.6"))
        let provider = OllamaSettingsProvider(models: [
            ProviderModel(
                id: "llama3.2",
                name: "llama3.2",
                provider: .ollama,
                providerID: ProviderConfiguration.defaultOllamaID
            )
        ])
        let store = fixture.makeStore(
            secretStore: InMemorySecretStore(),
            provider: provider,
            ollamaRuntimeService: runtimeService
        )
        store.settings = try await fixture.settingsStore.load()

        await store.selectProvider(ProviderConfiguration.defaultOllamaID)
        let statusCallCount = await runtimeService.statusCallCount
        let startCallCount = await runtimeService.startCallCount

        XCTAssertEqual(statusCallCount, 1)
        XCTAssertEqual(startCallCount, 0)
        XCTAssertEqual(store.ollamaRuntimeStatus, .reachable(version: "0.12.6"))
        XCTAssertEqual(store.models.map(\.id), ["llama3.2"])
        XCTAssertEqual(store.settings.selectedModelID, "llama3.2")
    }

    func testLoadDoesNotAutoStartOllamaWhenAutoStartDisabled() async throws {
        let fixture = try ProviderSettingsFixture()
        var settings = AppSettings()
        settings.ollamaAutoStartEnabled = false
        try await fixture.settingsStore.save(settings)
        let runtimeService = FakeOllamaRuntimeService(status: .unreachable(reason: "Ollama is not reachable at http://localhost:11434."))
        let store = fixture.makeStore(
            secretStore: InMemorySecretStore(),
            provider: OllamaSettingsProvider(models: []),
            ollamaRuntimeService: runtimeService
        )

        await store.load()
        let statusCallCount = await runtimeService.statusCallCount
        let startCallCount = await runtimeService.startCallCount

        XCTAssertEqual(statusCallCount, 1)
        XCTAssertEqual(startCallCount, 0)
        XCTAssertEqual(store.ollamaRuntimeStatus, .unreachable(reason: "Ollama is not reachable at http://localhost:11434."))
    }

    func testLoadAutoStartsOllamaWhenEnabledAndUnreachable() async throws {
        let fixture = try ProviderSettingsFixture()
        var settings = AppSettings()
        settings.ollamaAutoStartEnabled = true
        try await fixture.settingsStore.save(settings)
        let runtimeService = FakeOllamaRuntimeService(
            status: .unreachable(reason: "Ollama is not reachable at http://localhost:11434."),
            startStatus: .startedByApp(version: "0.12.6")
        )
        let store = fixture.makeStore(
            secretStore: InMemorySecretStore(),
            provider: OllamaSettingsProvider(models: [
                ProviderModel(id: "llama3.2", name: "llama3.2", provider: .ollama, providerID: ProviderConfiguration.defaultOllamaID)
            ]),
            ollamaRuntimeService: runtimeService
        )

        await store.load()
        let startCallCount = await runtimeService.startCallCount

        XCTAssertEqual(startCallCount, 1)
        XCTAssertEqual(store.ollamaRuntimeStatus, .startedByApp(version: "0.12.6"))
        XCTAssertEqual(store.models.map(\.id), ["llama3.2"])
    }

    func testRemoveOpenAICompatibleProviderDeletesSecretFallsBackToOllamaAndClearsSelections() async throws {
        let fixture = try ProviderSettingsFixture()
        let secretStore = InMemorySecretStore()
        let providerID = UUID()
        let secretID = "provider-\(providerID.uuidString)-api-key"
        let openAIProvider = ProviderConfiguration(
            id: providerID,
            name: "Local Gateway",
            kind: .openAICompatible,
            baseURL: "https://gateway.example/v1",
            apiKeySecretID: secretID
        )
        let settings = AppSettings(
            providers: [
                ProviderConfiguration.defaultOllama(),
                openAIProvider
            ],
            activeProviderID: providerID,
            selectedModelID: "gpt-test",
            selectedModelIDs: ["gpt-test", "gpt-test-alt"],
            embeddingModelID: "embed-test"
        )
        try await fixture.settingsStore.save(settings)
        try await secretStore.saveSecret("test-key", id: secretID)

        let store = fixture.makeStore(secretStore: secretStore)
        store.settings = try await fixture.settingsStore.load()

        await store.removeOpenAICompatibleProvider()

        XCTAssertNil(store.openAICompatibleProvider)
        XCTAssertEqual(store.settings.providers.map(\.id), [ProviderConfiguration.defaultOllamaID])
        XCTAssertEqual(store.settings.activeProviderID, ProviderConfiguration.defaultOllamaID)
        XCTAssertNil(store.settings.selectedModelID)
        XCTAssertEqual(store.settings.selectedModelIDs, [])
        XCTAssertNil(store.settings.embeddingModelID)
        let deletedSecret = try await secretStore.readSecret(id: secretID)
        XCTAssertNil(deletedSecret)

        let savedSettings = try await fixture.settingsStore.load()
        XCTAssertEqual(savedSettings.providers.map(\.id), [ProviderConfiguration.defaultOllamaID])
        XCTAssertEqual(savedSettings.activeProviderID, ProviderConfiguration.defaultOllamaID)
        XCTAssertNil(savedSettings.selectedModelID)
        XCTAssertEqual(savedSettings.selectedModelIDs, [])
        XCTAssertNil(savedSettings.embeddingModelID)
    }

    func testRemoveOpenAICompatibleProviderCreatesAuditEventWithoutSecretValue() async throws {
        let fixture = try ProviderSettingsFixture()
        let secretStore = InMemorySecretStore()
        let providerID = UUID()
        let secretID = "provider-\(providerID.uuidString)-api-key"
        let openAIProvider = ProviderConfiguration(
            id: providerID,
            name: "Retired Gateway",
            kind: .openAICompatible,
            baseURL: "https://retired.example/v1",
            apiKeySecretID: secretID
        )
        let settings = AppSettings(
            providers: [
                ProviderConfiguration.defaultOllama(),
                openAIProvider
            ],
            activeProviderID: providerID
        )
        try await fixture.settingsStore.save(settings)
        try await secretStore.saveSecret("sk-retired-secret", id: secretID)

        let store = fixture.makeStore(secretStore: secretStore)
        store.settings = try await fixture.settingsStore.load()

        await store.removeOpenAICompatibleProvider()

        let event = try XCTUnwrap(store.auditEvents.first)
        XCTAssertEqual(event.action, .providerSettingsUpdated)
        XCTAssertEqual(event.outcome, .succeeded)
        XCTAssertEqual(event.summary, "Removed OpenAI-compatible provider settings")
        XCTAssertEqual(event.metadata["providerKind"], "openAICompatible")
        XCTAssertEqual(event.metadata["providerName"], "Retired Gateway")
        XCTAssertEqual(event.metadata["baseURL"], "https://retired.example/v1")
        XCTAssertEqual(event.metadata["wasActive"], "true")
        XCTAssertFalse(event.metadata.values.contains("sk-retired-secret"))
    }

    func testSaveOpenAICompatibleProviderRejectsInvalidBaseURLBeforePersistingSettingsOrSecret() async throws {
        let fixture = try ProviderSettingsFixture()
        let secretStore = InMemorySecretStore()
        let store = fixture.makeStore(secretStore: secretStore)

        await store.saveOpenAICompatibleProvider(
            name: "Broken Gateway",
            baseURL: "not a url",
            apiKey: "sk-test",
            makeActive: false
        )

        XCTAssertNil(store.openAICompatibleProvider)
        XCTAssertEqual(store.settings.providers.map(\.id), [ProviderConfiguration.defaultOllamaID])
        XCTAssertEqual(store.errorMessage, ProviderError.invalidBaseURL("not a url").localizedDescription)

        let savedSettings = try await fixture.settingsStore.load()
        XCTAssertEqual(savedSettings.providers.map(\.id), [ProviderConfiguration.defaultOllamaID])
        let savedSecret = try await secretStore.readSecret(id: "provider-\(savedSettings.activeProviderID.uuidString)-api-key")
        XCTAssertNil(savedSecret)
    }

    func testSaveOpenAICompatibleProviderCreatesAuditEventWithoutSecretValue() async throws {
        let fixture = try ProviderSettingsFixture()
        let secretStore = InMemorySecretStore()
        let store = fixture.makeStore(secretStore: secretStore)

        await store.saveOpenAICompatibleProvider(
            name: "Team Gateway",
            baseURL: " https://gateway.example/v1 ",
            apiKey: "sk-sensitive-test",
            makeActive: false
        )

        let event = try XCTUnwrap(store.auditEvents.first)
        XCTAssertEqual(event.action, .providerSettingsUpdated)
        XCTAssertEqual(event.outcome, .succeeded)
        XCTAssertEqual(event.summary, "Saved OpenAI-compatible provider settings")
        XCTAssertEqual(event.metadata["providerKind"], "openAICompatible")
        XCTAssertEqual(event.metadata["providerName"], "Team Gateway")
        XCTAssertEqual(event.metadata["baseURL"], "https://gateway.example/v1")
        XCTAssertEqual(event.metadata["apiKeyUpdated"], "true")
        XCTAssertEqual(event.metadata["madeActive"], "false")
        XCTAssertFalse(event.metadata.values.contains("sk-sensitive-test"))

        let reloadedEvents = try await fixture.auditStorage.loadEvents()
        XCTAssertEqual(reloadedEvents.first?.metadata["providerName"], "Team Gateway")
        let reloadedMetadataValues = reloadedEvents.first.map { Array($0.metadata.values) } ?? []
        XCTAssertFalse(reloadedMetadataValues.contains("sk-sensitive-test"))
    }

    func testUpdateOllamaBaseURLRejectsInvalidURLBeforePersistingSettings() async throws {
        let fixture = try ProviderSettingsFixture()
        let store = fixture.makeStore(secretStore: InMemorySecretStore())

        await store.updateOllamaBaseURL("localhost:11434")

        XCTAssertEqual(store.settings.ollamaBaseURL, "http://localhost:11434")
        XCTAssertEqual(store.activeProvider.baseURL, "http://localhost:11434")
        XCTAssertEqual(store.errorMessage, ProviderError.invalidBaseURL("localhost:11434").localizedDescription)

        let savedSettings = try await fixture.settingsStore.load()
        XCTAssertEqual(savedSettings.ollamaBaseURL, "http://localhost:11434")
        XCTAssertEqual(savedSettings.activeProvider.baseURL, "http://localhost:11434")
    }

    func testUpdateOllamaBaseURLCreatesProviderSettingsAuditEvent() async throws {
        let fixture = try ProviderSettingsFixture()
        let provider = HealthCheckProvider(status: .available("Gateway reachable"))
        let store = fixture.makeStore(secretStore: InMemorySecretStore(), provider: provider)

        await store.updateOllamaBaseURL(" http://127.0.0.1:11434 ")

        let event = try XCTUnwrap(store.auditEvents.first)
        XCTAssertEqual(event.action.rawValue, "providerSettingsUpdated")
        XCTAssertEqual(event.outcome, .succeeded)
        XCTAssertEqual(event.summary, "Updated Ollama provider settings")
        XCTAssertEqual(event.metadata["providerKind"], "ollama")
        XCTAssertEqual(event.metadata["providerName"], "Ollama")
        XCTAssertEqual(event.metadata["baseURL"], "http://127.0.0.1:11434")

        let reloadedEvents = try await fixture.auditStorage.loadEvents()
        XCTAssertEqual(reloadedEvents.first?.metadata["baseURL"], "http://127.0.0.1:11434")
    }

    func testProviderCapabilitySummaryRowsDescribeOllamaLimits() {
        let rows = ProviderCapabilitySummary.rows(for: ProviderConfiguration.defaultOllama())

        XCTAssertEqual(rows.map(\.label), [
            "Chat",
            "Completions",
            "Embeddings",
            "Model management",
            "Image generation",
            "Image editing",
            "Image variations",
            "Audio transcription",
            "Speech synthesis"
        ])
        XCTAssertEqual(rows.map(\.statusText), [
            "Supported",
            "Supported",
            "Unsupported",
            "Supported",
            "Unsupported",
            "Unsupported",
            "Unsupported",
            "Unsupported",
            "Unsupported"
        ])
        XCTAssertFalse(try XCTUnwrap(rows.first { $0.label == "Embeddings" }).isSupported)
    }

    func testProviderCapabilitySummaryRowsDescribeOpenAICompatibleProvider() {
        let provider = ProviderConfiguration(
            name: "OpenAI",
            kind: .openAICompatible,
            baseURL: "https://api.openai.com/v1",
            apiKeySecretID: "secret"
        )

        let rows = ProviderCapabilitySummary.rows(for: provider)

        XCTAssertTrue(try XCTUnwrap(rows.first { $0.label == "Chat" }).isSupported)
        XCTAssertTrue(try XCTUnwrap(rows.first { $0.label == "Completions" }).isSupported)
        XCTAssertTrue(try XCTUnwrap(rows.first { $0.label == "Embeddings" }).isSupported)
        XCTAssertFalse(try XCTUnwrap(rows.first { $0.label == "Model management" }).isSupported)
        XCTAssertTrue(try XCTUnwrap(rows.first { $0.label == "Image generation" }).isSupported)
        XCTAssertTrue(try XCTUnwrap(rows.first { $0.label == "Speech synthesis" }).isSupported)
    }

    func testProviderModelCapabilityMetadataClassifiesKnownEmbeddingAndMediaFamilies() {
        let embeddingModel = ProviderModel(id: "text-embedding-3-small", name: "Text Embedding 3 Small", provider: .openAICompatible)
        let transcriptionModel = ProviderModel(id: "whisper-1", name: "Whisper", provider: .openAICompatible)
        let speechModel = ProviderModel(id: "gpt-4o-mini-tts", name: "GPT-4o Mini TTS", provider: .openAICompatible)

        XCTAssertEqual(embeddingModel.capabilityMetadata.embeddings, .supported)
        XCTAssertEqual(transcriptionModel.capabilityMetadata.audioTranscription, .supported)
        XCTAssertEqual(speechModel.capabilityMetadata.speechSynthesis, .supported)
    }

    func testProviderModelCapabilityMetadataLeavesUnknownModelFamiliesUnset() {
        let unknownModel = ProviderModel(id: "gateway-default", name: "Gateway Default", provider: .openAICompatible)

        XCTAssertEqual(unknownModel.capabilityMetadata.embeddings, .unknown)
        XCTAssertEqual(unknownModel.capabilityMetadata.audioTranscription, .unknown)
        XCTAssertEqual(unknownModel.capabilityMetadata.speechSynthesis, .unknown)
    }

    func testEmbeddingModelCandidatesPreferLikelyEmbeddingModels() async throws {
        let models = [
            ProviderModel(id: "gpt-4.1", name: "GPT 4.1", provider: .openAICompatible),
            ProviderModel(id: "text-embedding-3-small", name: "Text Embedding 3 Small", provider: .openAICompatible),
            ProviderModel(id: "whisper-1", name: "Whisper", provider: .openAICompatible),
            ProviderModel(id: "nomic-embed-text:latest", name: "nomic-embed-text", provider: .openAICompatible)
        ]
        let fixture = try ProviderSettingsFixture()
        let provider = HealthCheckProvider(status: .available("Gateway reachable"), models: models)
        let store = fixture.makeStore(secretStore: InMemorySecretStore(), provider: provider)

        await store.refreshModels()

        XCTAssertEqual(store.embeddingModelCandidates.map(\.id), [
            "text-embedding-3-small",
            "nomic-embed-text:latest"
        ])
        XCTAssertEqual(store.selectedEmbeddingModelID, "text-embedding-3-small")
    }

    func testEmbeddingModelCandidatesStayEmptyForUnlabeledModelsAndFallBackToChatModel() async throws {
        let models = [
            ProviderModel(id: "custom-vector-model", name: "Custom Vector Model", provider: .openAICompatible),
            ProviderModel(id: "gateway-default", name: "Gateway Default", provider: .openAICompatible)
        ]
        let fixture = try ProviderSettingsFixture()
        let provider = HealthCheckProvider(status: .available("Gateway reachable"), models: models)
        let store = fixture.makeStore(secretStore: InMemorySecretStore(), provider: provider)

        await store.refreshModels()

        XCTAssertTrue(store.embeddingModelCandidates.isEmpty)
        XCTAssertEqual(store.selectedModelID, "custom-vector-model")
        XCTAssertEqual(store.selectedEmbeddingModelID, "custom-vector-model")
    }

    func testCompleteFirstRunSetupPersistsCompletedFlag() async throws {
        let fixture = try ProviderSettingsFixture()
        let store = fixture.makeStore(secretStore: InMemorySecretStore())
        await store.load()
        store.providerStatus = .available("Ollama connected")
        store.models = [
            ProviderModel(id: "llama3.2", name: "llama3.2", provider: .ollama, providerID: ProviderConfiguration.defaultOllamaID)
        ]
        store.settings.selectedModelID = "llama3.2"
        store.settings.selectedModelIDs = ["llama3.2"]

        await store.completeFirstRunSetup()

        XCTAssertTrue(store.settings.hasCompletedFirstRunSetup)
        let savedSettings = try await fixture.settingsStore.load()
        XCTAssertTrue(savedSettings.hasCompletedFirstRunSetup)
    }

    func testCompleteFirstRunSetupRequiresReachableProviderAndSelectedModel() async throws {
        let fixture = try ProviderSettingsFixture()
        let store = fixture.makeStore(secretStore: InMemorySecretStore())
        store.providerStatus = .unavailable("Ollama is not reachable at http://localhost:11434.")
        store.models = []
        store.settings.selectedModelID = nil
        store.settings.selectedModelIDs = []

        await store.completeFirstRunSetup()

        XCTAssertFalse(store.settings.hasCompletedFirstRunSetup)
        XCTAssertEqual(store.errorMessage, "Finish setup needs a reachable provider and selected model. Use Skip Setup to keep safe defaults for later.")
    }

    func testSkipFirstRunSetupLeavesSafeDefaultsAndPersistsCompletedFlag() async throws {
        let fixture = try ProviderSettingsFixture()
        let store = fixture.makeStore(secretStore: InMemorySecretStore())
        store.settings.localExecution = LocalExecutionSettings(
            isEnabled: true,
            hasAcceptedRiskWarning: true,
            sandboxRootPath: "/tmp/custom-sandbox"
        )

        await store.skipFirstRunSetup()

        XCTAssertTrue(store.settings.hasCompletedFirstRunSetup)
        XCTAssertEqual(store.settings.activeProviderID, ProviderConfiguration.defaultOllamaID)
        XCTAssertEqual(store.settings.activeProvider.kind, .ollama)
        XCTAssertFalse(store.settings.localExecution.isEnabled)
        XCTAssertFalse(store.settings.localExecution.hasAcceptedRiskWarning)

        let savedSettings = try await fixture.settingsStore.load()
        XCTAssertTrue(savedSettings.hasCompletedFirstRunSetup)
        XCTAssertFalse(savedSettings.localExecution.isEnabled)
    }

    func testRefreshModelsShowsEmptyStateWhenProviderReturnsNoModels() async throws {
        let fixture = try ProviderSettingsFixture()
        let provider = HealthCheckProvider(status: .available("Gateway reachable"), models: [])
        let store = fixture.makeStore(secretStore: InMemorySecretStore(), provider: provider)

        await store.refreshModels()

        XCTAssertEqual(store.models, [])
        XCTAssertNil(store.settings.selectedModelID)
        XCTAssertEqual(store.modelRefreshSourceLabel, "OpenAI-compatible /models")
        XCTAssertEqual(store.modelRefreshStateLabel, "Empty")
        XCTAssertEqual(store.providerStatus, .available("Gateway connected (0 live models)"))
    }

    func testRefreshModelsSurfacesRecoveryNoticeWhenSelectedModelDisappears() async throws {
        let fixture = try ProviderSettingsFixture()
        let settings = AppSettings(
            selectedModelID: "stale-model",
            selectedModelIDs: ["stale-model"],
            embeddingModelID: "stale-embed"
        )
        try await fixture.settingsStore.save(settings)
        let provider = HealthCheckProvider(
            status: .available("Gateway reachable"),
            models: [
                ProviderModel(
                    id: "fresh-model",
                    name: "Fresh Model",
                    provider: .ollama,
                    providerID: ProviderConfiguration.defaultOllamaID
                )
            ]
        )
        let store = fixture.makeStore(secretStore: InMemorySecretStore(), provider: provider)
        store.settings = try await fixture.settingsStore.load()

        await store.refreshModels()

        XCTAssertEqual(store.settings.selectedModelID, "fresh-model")
        XCTAssertEqual(store.settings.selectedModelIDs, ["fresh-model"])
        XCTAssertNil(store.settings.embeddingModelID)
        XCTAssertEqual(
            store.recoveryNotice,
            "Recovered provider defaults: stale-model is no longer available, so fresh-model is selected."
        )
    }

    func testMissingOpenAICompatibleKeychainSecretIsHandledAsProviderStatus() async throws {
        let fixture = try ProviderSettingsFixture()
        let providerID = UUID()
        let provider = ProviderConfiguration(
            id: providerID,
            name: "Gateway",
            kind: .openAICompatible,
            baseURL: "https://gateway.example/v1",
            apiKeySecretID: "missing-secret"
        )
        try await fixture.settingsStore.save(
            AppSettings(providers: [provider], activeProviderID: providerID)
        )
        let store = fixture.makeStore(secretStore: InMemorySecretStore())
        store.settings = try await fixture.settingsStore.load()

        await store.checkActiveProviderHealth()

        XCTAssertEqual(
            store.providerStatus,
            .unavailable("Gateway needs an API key. Add it in Settings; it will be stored in Keychain.")
        )
    }

    func testTestOllamaChatDoesNotCreateOrPersistChatThread() async throws {
        let fixture = try ProviderSettingsFixture()
        let provider = OllamaSettingsProvider(
            models: [
                ProviderModel(id: "llama3.2", name: "llama3.2", provider: .ollama, providerID: ProviderConfiguration.defaultOllamaID)
            ],
            diagnosticReply: "OK"
        )
        let store = fixture.makeStore(secretStore: InMemorySecretStore(), provider: provider)
        store.models = try await provider.listModels()
        store.settings.selectedModelID = "llama3.2"
        store.settings.selectedModelIDs = ["llama3.2"]

        await store.testOllamaChat()
        let persistedThreads = try await fixture.storage.loadThreads()

        XCTAssertEqual(store.ollamaChatTestResult, "Ollama chat test succeeded: OK")
        XCTAssertTrue(store.threads.isEmpty)
        XCTAssertTrue(persistedThreads.isEmpty)
    }

    func testFailedOllamaPreflightPreservesDraftAndDoesNotCreateThread() async throws {
        let fixture = try ProviderSettingsFixture()
        let store = fixture.makeStore(secretStore: InMemorySecretStore(), provider: OllamaSettingsProvider(models: []))
        store.models = [
            ProviderModel(id: "llama3.2", name: "llama3.2", provider: .ollama, providerID: ProviderConfiguration.defaultOllamaID)
        ]
        store.settings.selectedModelID = "missing-model"
        store.settings.selectedModelIDs = ["missing-model"]
        store.draftPrompt = "hello from draft"

        let didSend = await store.sendDraftPrompt()

        XCTAssertFalse(didSend)
        XCTAssertEqual(store.draftPrompt, "hello from draft")
        XCTAssertTrue(store.threads.isEmpty)
        XCTAssertEqual(
            store.composerInlineMessage,
            "Selected Ollama model 'missing-model' is not installed. Pull it or choose another model."
        )
    }
}

private struct ProviderSettingsFixture {
    let rootURL: URL
    let storage: JSONStorageService
    let folderStorage: JSONFolderStorageService
    let promptStorage: JSONPromptStorageService
    let noteStorage: JSONNoteStorageService
    let auditStorage: JSONAuditLogStorageService
    let settingsStore: SettingsStore

    init() throws {
        rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        storage = JSONStorageService(rootURL: rootURL.appendingPathComponent("Chats", isDirectory: true))
        folderStorage = JSONFolderStorageService(rootURL: rootURL.appendingPathComponent("Folders", isDirectory: true))
        promptStorage = JSONPromptStorageService(rootURL: rootURL.appendingPathComponent("Prompts", isDirectory: true))
        noteStorage = JSONNoteStorageService(rootURL: rootURL.appendingPathComponent("Notes", isDirectory: true))
        auditStorage = JSONAuditLogStorageService(rootURL: rootURL.appendingPathComponent("Audit", isDirectory: true))
        settingsStore = SettingsStore(settingsURL: rootURL.appendingPathComponent("settings.json"))
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
    }

    @MainActor
    func makeStore(
        secretStore: SecretStoring,
        provider: (any ChatProvider)? = nil,
        ollamaRuntimeService: (any OllamaRuntimeManaging)? = nil
    ) -> AppStore {
        AppStore(
            storage: storage,
            folderStorage: folderStorage,
            settingsStore: settingsStore,
            secretStore: secretStore,
            providerOverride: provider,
            ollamaRuntimeService: ollamaRuntimeService,
            auditLogStorage: auditStorage,
            promptStorage: promptStorage,
            noteStorage: noteStorage
        )
    }
}

private actor HealthCheckProvider: ChatProvider {
    nonisolated var configuration: ProviderConfiguration {
        ProviderConfiguration(
            name: "Gateway",
            kind: .openAICompatible,
            baseURL: "https://gateway.example/v1",
            apiKeySecretID: "secret"
        )
    }

    private let status: ProviderStatus
    private let models: [ProviderModel]
    private(set) var healthCheckCount = 0

    init(status: ProviderStatus, models: [ProviderModel] = []) {
        self.status = status
        self.models = models
    }

    func listModels() async throws -> [ProviderModel] {
        models
    }

    func healthCheck() async -> ProviderStatus {
        healthCheckCount += 1
        return status
    }

    nonisolated func streamChat(model: String, messages: [ProviderChatMessage]) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish()
        }
    }

    func createEmbeddings(model: String, input: [String]) async throws -> [[Double]] {
        input.map { _ in [1.0] }
    }
}

private actor FakeOllamaRuntimeService: OllamaRuntimeManaging {
    private let status: OllamaRuntimeStatus
    private let startStatus: OllamaRuntimeStatus
    private(set) var statusCallCount = 0
    private(set) var startCallCount = 0
    private(set) var stopCallCount = 0
    var ownsRunningCLIProcess = false

    init(
        status: OllamaRuntimeStatus,
        startStatus: OllamaRuntimeStatus = .failedToStart(reason: "Start not configured.")
    ) {
        self.status = status
        self.startStatus = startStatus
    }

    func status(baseURL: String) async -> OllamaRuntimeStatus {
        statusCallCount += 1
        return status
    }

    func start(baseURL: String, preferredMethod: OllamaStartMethod) async -> OllamaRuntimeStatus {
        startCallCount += 1
        return startStatus
    }

    func stopOwnedCLIProcess() async {
        stopCallCount += 1
        ownsRunningCLIProcess = false
    }
}

private actor OllamaSettingsProvider: ChatProvider, OllamaChatDiagnosing {
    nonisolated let configuration = ProviderConfiguration.defaultOllama()
    private let models: [ProviderModel]
    private let diagnosticReply: String

    init(models: [ProviderModel], diagnosticReply: String = "OK") {
        self.models = models
        self.diagnosticReply = diagnosticReply
    }

    func listModels() async throws -> [ProviderModel] {
        models
    }

    func healthCheck() async -> ProviderStatus {
        .available("Ollama connected")
    }

    func runtimeVersion() async throws -> String {
        "0.12.6"
    }

    func runDiagnosticChat(model: String) async throws -> String {
        diagnosticReply
    }

    nonisolated func streamChat(model: String, messages: [ProviderChatMessage]) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            continuation.yield("Hello")
            continuation.finish()
        }
    }

    func createEmbeddings(model: String, input: [String]) async throws -> [[Double]] {
        []
    }
}
