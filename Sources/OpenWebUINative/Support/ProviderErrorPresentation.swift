import Foundation

struct ProviderErrorPresentation: Equatable, Sendable {
    var message: String
    var technicalDetail: String

    var searchableText: String {
        "\(message) \(technicalDetail)"
    }

    static func presentation(
        for error: Error,
        provider: ProviderConfiguration?
    ) -> ProviderErrorPresentation {
        if error is CancellationError {
            return ProviderErrorPresentation(
                message: "The response stream was interrupted or cancelled. Try again when the provider is steady.",
                technicalDetail: String(describing: error)
            )
        }

        if let urlError = error as? URLError {
            return presentation(for: urlError, provider: provider)
        }

        if let providerError = error as? ProviderError {
            return presentation(for: providerError, provider: provider)
        }

        return ProviderErrorPresentation(
            message: error.localizedDescription,
            technicalDetail: String(describing: error)
        )
    }

    private static func presentation(
        for error: URLError,
        provider: ProviderConfiguration?
    ) -> ProviderErrorPresentation {
        if provider?.kind == .ollama,
           [.cannotConnectToHost, .cannotFindHost, .networkConnectionLost, .timedOut].contains(error.code) {
            return ProviderErrorPresentation(
                message: "Ollama is not reachable. Start Ollama, then check that the base URL is \(provider?.baseURL ?? "http://localhost:11434").",
                technicalDetail: urlErrorTechnicalDetail(error)
            )
        }

        let providerName = provider?.name ?? "The provider"
        return ProviderErrorPresentation(
            message: "\(providerName) could not be reached. Check the base URL and network connection.",
            technicalDetail: urlErrorTechnicalDetail(error)
        )
    }

    private static func presentation(
        for error: ProviderError,
        provider: ProviderConfiguration?
    ) -> ProviderErrorPresentation {
        let providerName = provider?.name ?? "The provider"
        switch error {
        case .invalidBaseURL:
            return ProviderErrorPresentation(
                message: "The provider base URL is not valid. Use a full http or https URL, like http://localhost:11434.",
                technicalDetail: error.localizedDescription
            )
        case .invalidResponse:
            return ProviderErrorPresentation(
                message: "\(providerName) returned a response this app could not read. Refresh models or try again.",
                technicalDetail: error.localizedDescription
            )
        case .httpStatus(let statusCode):
            return ProviderErrorPresentation(
                message: httpStatusMessage(statusCode: statusCode, providerName: providerName, provider: provider),
                technicalDetail: "HTTP \(statusCode)"
            )
        case .missingAPIKey(let name):
            return ProviderErrorPresentation(
                message: "\(name) needs an API key. Add it in Settings; it will be stored in Keychain.",
                technicalDetail: "Missing Keychain API key for provider \(name)."
            )
        case .noModelsReturned(let name):
            return ProviderErrorPresentation(
                message: "\(name) responded, but returned no models. Check the provider account, base URL, or model permissions.",
                technicalDetail: error.localizedDescription
            )
        case .selectedModelUnavailable(let modelID):
            return ProviderErrorPresentation(
                message: "The selected model \(modelID) is no longer available. Refresh models and choose another default.",
                technicalDetail: error.localizedDescription
            )
        case .noModelSelected:
            return ProviderErrorPresentation(
                message: "Choose a model before sending a message.",
                technicalDetail: error.localizedDescription
            )
        case .emptyPrompt:
            return ProviderErrorPresentation(
                message: "Type a message before sending.",
                technicalDetail: error.localizedDescription
            )
        case .unsupportedAttachment(let fileName):
            return ProviderErrorPresentation(
                message: "\(fileName) could not be read as a text attachment yet.",
                technicalDetail: error.localizedDescription
            )
        case .unsupportedChat(let name):
            return unsupportedFeatureMessage(providerName: name, feature: "chat", fallback: nil, error: error)
        case .unsupportedCompletions(let name):
            return unsupportedFeatureMessage(providerName: name, feature: "completions", fallback: nil, error: error)
        case .unsupportedModelManagement(let name):
            return unsupportedFeatureMessage(providerName: name, feature: "model management", fallback: "Use Ollama for native model pull/delete.", error: error)
        case .unsupportedEmbeddings(let name):
            return unsupportedFeatureMessage(providerName: name, feature: "embeddings", fallback: "Choose an OpenAI-compatible provider with embedding models.", error: error)
        case .unsupportedImageGeneration(let name):
            return unsupportedFeatureMessage(providerName: name, feature: "image generation", fallback: "Choose an OpenAI-compatible provider for that feature.", error: error)
        case .unsupportedImageEditing(let name):
            return unsupportedFeatureMessage(providerName: name, feature: "image editing", fallback: "Choose an OpenAI-compatible provider for that feature.", error: error)
        case .unsupportedImageVariation(let name):
            return unsupportedFeatureMessage(providerName: name, feature: "image variations", fallback: "Choose an OpenAI-compatible provider for that feature.", error: error)
        case .unsupportedAudioTranscription(let name):
            return unsupportedFeatureMessage(providerName: name, feature: "audio transcription", fallback: "Choose an OpenAI-compatible provider for that feature.", error: error)
        case .unsupportedSpeechSynthesis(let name):
            return unsupportedFeatureMessage(providerName: name, feature: "speech synthesis", fallback: "Choose an OpenAI-compatible provider for that feature.", error: error)
        }
    }

    private static func httpStatusMessage(
        statusCode: Int,
        providerName: String,
        provider: ProviderConfiguration?
    ) -> String {
        switch statusCode {
        case 401, 403:
            return "\(providerName) returned HTTP \(statusCode). Check the API key, base URL, and model access."
        case 404:
            return "\(providerName) returned HTTP 404. Check the base URL and requested model or endpoint."
        case 429:
            return "\(providerName) returned HTTP 429. Wait a moment or check provider rate limits."
        case 500..<600:
            return "\(providerName) returned HTTP \(statusCode). The provider may be temporarily unavailable."
        default:
            return "\(providerName) returned HTTP \(statusCode). Check the provider settings and try again."
        }
    }

    private static func unsupportedFeatureMessage(
        providerName: String,
        feature: String,
        fallback: String?,
        error: ProviderError
    ) -> ProviderErrorPresentation {
        let message = [("\(providerName) does not support native \(feature) in this app."), fallback]
            .compactMap { $0 }
            .joined(separator: " ")
        return ProviderErrorPresentation(
            message: message,
            technicalDetail: error.localizedDescription
        )
    }

    private static func urlErrorTechnicalDetail(_ error: URLError) -> String {
        let name: String
        switch error.code {
        case .cannotConnectToHost:
            name = "cannotConnectToHost"
        case .cannotFindHost:
            name = "cannotFindHost"
        case .networkConnectionLost:
            name = "networkConnectionLost"
        case .timedOut:
            name = "timedOut"
        default:
            name = "URLError"
        }
        return "\(name) (\(error.errorCode))"
    }
}
