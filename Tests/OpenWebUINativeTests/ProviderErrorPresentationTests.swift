import Foundation
import XCTest
@testable import OpenWebUINative

final class ProviderErrorPresentationTests: XCTestCase {
    func testOllamaConnectionRefusedMessageExplainsAction() {
        let presentation = ProviderErrorPresentation.presentation(
            for: URLError(.cannotConnectToHost),
            provider: ProviderConfiguration.defaultOllama()
        )

        XCTAssertEqual(
            presentation.message,
            "Ollama is not reachable. Start Ollama, then check that the base URL is http://localhost:11434."
        )
        XCTAssertTrue(presentation.technicalDetail.contains("cannotConnectToHost"))
    }

    func testMalformedBaseURLMessageIsActionable() {
        let presentation = ProviderErrorPresentation.presentation(
            for: ProviderError.invalidBaseURL("localhost:11434"),
            provider: ProviderConfiguration.defaultOllama()
        )

        XCTAssertEqual(
            presentation.message,
            "The provider base URL is not valid. Use a full http or https URL, like http://localhost:11434."
        )
    }

    func testMissingAPIKeyMessageDoesNotExposeSecretIDs() {
        let provider = ProviderConfiguration(
            name: "Gateway",
            kind: .openAICompatible,
            baseURL: "https://gateway.example/v1",
            apiKeySecretID: "secret-provider-key"
        )

        let presentation = ProviderErrorPresentation.presentation(
            for: ProviderError.missingAPIKey("Gateway"),
            provider: provider
        )

        XCTAssertEqual(
            presentation.message,
            "Gateway needs an API key. Add it in Settings; it will be stored in Keychain."
        )
        XCTAssertFalse(presentation.searchableText.contains("secret-provider-key"))
    }

    func testNoModelsReturnedAndSelectedModelUnavailableMessagesAreClear() {
        XCTAssertEqual(
            ProviderErrorPresentation.presentation(
                for: ProviderError.noModelsReturned("Gateway"),
                provider: nil
            ).message,
            "Gateway responded, but returned no models. Check the provider account, base URL, or model permissions."
        )

        XCTAssertEqual(
            ProviderErrorPresentation.presentation(
                for: ProviderError.selectedModelUnavailable("old-model"),
                provider: nil
            ).message,
            "The selected model old-model is no longer available. Refresh models and choose another default."
        )
    }

    func testUnsupportedFeatureAndHTTPStatusMessagesPreserveUsefulDetail() {
        XCTAssertEqual(
            ProviderErrorPresentation.presentation(
                for: ProviderError.unsupportedImageGeneration("Ollama"),
                provider: ProviderConfiguration.defaultOllama()
            ).message,
            "Ollama does not support native image generation in this app. Choose an OpenAI-compatible provider for that feature."
        )

        let httpPresentation = ProviderErrorPresentation.presentation(
            for: ProviderError.httpStatus(401),
            provider: ProviderConfiguration(
                name: "Gateway",
                kind: .openAICompatible,
                baseURL: "https://gateway.example/v1",
                apiKeySecretID: "secret"
            )
        )

        XCTAssertEqual(
            httpPresentation.message,
            "Gateway returned HTTP 401. Check the API key, base URL, and model access."
        )
        XCTAssertTrue(httpPresentation.technicalDetail.contains("HTTP 401"))
    }

    func testOllamaHTTPErrorMessageIncludesEndpointAndSafeBodyMessage() {
        let presentation = ProviderErrorPresentation.presentation(
            for: ProviderError.httpStatus(
                500,
                message: "model requires more system memory",
                bodySnippet: #"{"error":"model requires more system memory"}"#,
                endpoint: "/api/chat"
            ),
            provider: ProviderConfiguration.defaultOllama()
        )

        XCTAssertEqual(
            presentation.message,
            "Ollama returned HTTP 500 from /api/chat: model requires more system memory"
        )
        XCTAssertTrue(presentation.technicalDetail.contains("HTTP 500"))
        XCTAssertTrue(presentation.technicalDetail.contains("/api/chat"))
    }

    func testOllamaSelectedModelUnavailableMessageIsInstallFocused() {
        let presentation = ProviderErrorPresentation.presentation(
            for: ProviderError.selectedModelUnavailable("missing-model"),
            provider: ProviderConfiguration.defaultOllama()
        )

        XCTAssertEqual(
            presentation.message,
            "Selected Ollama model 'missing-model' is not installed. Pull it or choose another model."
        )
    }

    func testCancelledStreamMessageIsNonScary() {
        let presentation = ProviderErrorPresentation.presentation(
            for: CancellationError(),
            provider: ProviderConfiguration.defaultOllama()
        )

        XCTAssertEqual(
            presentation.message,
            "The response stream was interrupted or cancelled. Try again when the provider is steady."
        )
    }
}
