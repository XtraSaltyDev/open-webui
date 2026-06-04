import Foundation
import XCTest
@testable import OpenWebUINative

final class SettingsViewProviderPickerTests: XCTestCase {
    func testProviderPickerOptionsIncludeOnlyEnabledProvidersAndMarkActiveProvider() {
        let gatewayID = UUID()
        let disabledID = UUID()
        let settings = AppSettings(
            providers: [
                ProviderConfiguration.defaultOllama(),
                ProviderConfiguration(
                    id: disabledID,
                    name: "Legacy Gateway",
                    kind: .openAICompatible,
                    baseURL: "https://legacy.example/v1",
                    apiKeySecretID: "legacy-secret",
                    isEnabled: false
                ),
                ProviderConfiguration(
                    id: gatewayID,
                    name: "Gateway",
                    kind: .openAICompatible,
                    baseURL: "https://gateway.example/v1",
                    apiKeySecretID: "gateway-secret"
                )
            ],
            activeProviderID: gatewayID
        )

        let options = SettingsProviderPickerOption.options(for: settings)

        XCTAssertEqual(options.map(\.id), [ProviderConfiguration.defaultOllamaID, gatewayID])
        XCTAssertEqual(options.map(\.name), ["Ollama", "Gateway"])
        XCTAssertEqual(options.map(\.detailText), ["Ollama - http://localhost:11434", "OpenAI-compatible - https://gateway.example/v1"])
        XCTAssertEqual(options.map(\.isActive), [false, true])
    }

    func testOpenAIProviderFormPresentationUsesDefaultsWhenProviderIsMissing() {
        let presentation = SettingsOpenAIProviderFormPresentation.presentation(for: nil)

        XCTAssertEqual(presentation.name, "OpenAI")
        XCTAssertEqual(presentation.baseURL, "https://api.openai.com/v1")
        XCTAssertEqual(presentation.apiKey, "")
        XCTAssertEqual(presentation.apiKeyHelpText, "Enter an API key to store it in Keychain.")
    }

    func testOpenAIProviderFormPresentationUsesProviderMetadataWithoutSecretValue() {
        let provider = ProviderConfiguration(
            name: "Workspace Gateway",
            kind: .openAICompatible,
            baseURL: "https://gateway.example/v1",
            apiKeySecretID: "stored-secret"
        )

        let presentation = SettingsOpenAIProviderFormPresentation.presentation(for: provider)

        XCTAssertEqual(presentation.name, "Workspace Gateway")
        XCTAssertEqual(presentation.baseURL, "https://gateway.example/v1")
        XCTAssertEqual(presentation.apiKey, "")
        XCTAssertEqual(presentation.apiKeyHelpText, "Leave blank to keep the existing Keychain API key.")
    }

    func testOpenAIProviderFormSaveIsDisabledForMalformedBaseURL() {
        XCTAssertFalse(SettingsOpenAIProviderFormPresentation.isSaveEnabled(baseURL: "not a url"))
        XCTAssertFalse(SettingsOpenAIProviderFormPresentation.isSaveEnabled(baseURL: ""))
    }

    func testOpenAIProviderFormSaveIsEnabledForHTTPOrHTTPSBaseURL() {
        XCTAssertTrue(SettingsOpenAIProviderFormPresentation.isSaveEnabled(baseURL: " https://gateway.example/v1 "))
        XCTAssertTrue(SettingsOpenAIProviderFormPresentation.isSaveEnabled(baseURL: "http://localhost:8080/v1"))
    }

    func testOpenAIProviderFormBaseURLMessageExplainsMalformedURL() {
        XCTAssertEqual(
            SettingsOpenAIProviderFormPresentation.baseURLValidationMessage(for: "not a url"),
            "Enter a valid http or https provider base URL."
        )
        XCTAssertEqual(
            SettingsOpenAIProviderFormPresentation.baseURLValidationMessage(for: ""),
            "Enter a provider base URL."
        )
    }

    func testOpenAIProviderFormBaseURLMessageIsNilForValidURL() {
        XCTAssertNil(SettingsOpenAIProviderFormPresentation.baseURLValidationMessage(for: "https://gateway.example/v1"))
        XCTAssertNil(SettingsOpenAIProviderFormPresentation.baseURLValidationMessage(for: " http://localhost:8080/v1 "))
    }

    func testOllamaProviderFormBaseURLMessageExplainsMalformedURL() {
        XCTAssertEqual(
            SettingsOllamaProviderFormPresentation.baseURLValidationMessage(for: "localhost:11434"),
            "Enter a valid http or https provider base URL."
        )
        XCTAssertEqual(
            SettingsOllamaProviderFormPresentation.baseURLValidationMessage(for: ""),
            "Enter a provider base URL."
        )
    }

    func testOllamaProviderFormSaveIsEnabledOnlyForValidBaseURL() {
        XCTAssertFalse(SettingsOllamaProviderFormPresentation.isSaveEnabled(baseURL: "localhost:11434"))
        XCTAssertFalse(SettingsOllamaProviderFormPresentation.isSaveEnabled(baseURL: ""))
        XCTAssertTrue(SettingsOllamaProviderFormPresentation.isSaveEnabled(baseURL: " http://localhost:11434 "))
        XCTAssertTrue(SettingsOllamaProviderFormPresentation.isSaveEnabled(baseURL: "https://ollama.example"))
    }

    func testProviderHealthPresentationExplainsUnknownAndUnavailableStates() {
        XCTAssertEqual(
            SettingsProviderHealthPresentation.presentation(for: .unknown),
            SettingsProviderHealthPresentation(
                label: "Health unknown",
                systemImage: "questionmark.circle",
                tone: .neutral,
                helpText: "Run a health check to verify the active provider before using it.",
                isActionInProgress: false
            )
        )

        XCTAssertEqual(
            SettingsProviderHealthPresentation.presentation(for: .unavailable("Connection refused")),
            SettingsProviderHealthPresentation(
                label: "Connection refused",
                systemImage: "xmark.octagon.fill",
                tone: .failure,
                helpText: "The active provider could not be reached. Check the base URL, API key, or local runtime.",
                isActionInProgress: false
            )
        )
    }

    func testProviderHealthPresentationExplainsCheckingAndAvailableStates() {
        XCTAssertEqual(
            SettingsProviderHealthPresentation.presentation(for: .checking),
            SettingsProviderHealthPresentation(
                label: "Checking provider...",
                systemImage: "arrow.triangle.2.circlepath",
                tone: .progress,
                helpText: "Contacting the active provider.",
                isActionInProgress: true
            )
        )

        XCTAssertEqual(
            SettingsProviderHealthPresentation.presentation(for: .available("Gateway connected")),
            SettingsProviderHealthPresentation(
                label: "Gateway connected",
                systemImage: "checkmark.circle.fill",
                tone: .success,
                helpText: "The active provider responded successfully.",
                isActionInProgress: false
            )
        )
    }
}
