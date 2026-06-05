import Foundation

protocol ChatProvider {
    var configuration: ProviderConfiguration { get }
    var capabilities: ProviderCapabilities { get }

    func listModels() async throws -> [ProviderModel]
    func healthCheck() async -> ProviderStatus
    func streamChat(model: String, messages: [ProviderChatMessage]) -> AsyncThrowingStream<String, Error>
    func streamChat(
        model: String,
        messages: [ProviderChatMessage],
        options: ProviderChatOptions?
    ) -> AsyncThrowingStream<String, Error>
    func streamChatEvents(model: String, messages: [ProviderChatMessage]) -> AsyncThrowingStream<ChatStreamEvent, Error>
    func streamChatEvents(
        model: String,
        messages: [ProviderChatMessage],
        options: ProviderChatOptions?
    ) -> AsyncThrowingStream<ChatStreamEvent, Error>
    func streamCompletion(
        model: String,
        prompt: String,
        options: ProviderChatOptions?
    ) -> AsyncThrowingStream<String, Error>
    func createEmbeddings(model: String, input: [String]) async throws -> [[Double]]
    func generateImages(request: ImageGenerationRequest) async throws -> ImageGenerationResult
    func editImage(request: ImageEditRequest) async throws -> ImageGenerationResult
    func varyImage(request: ImageVariationRequest) async throws -> ImageGenerationResult
    func transcribeAudio(request: AudioTranscriptionRequest) async throws -> AudioTranscriptionResult
    func synthesizeSpeech(request: SpeechSynthesisRequest) async throws -> SpeechSynthesisResult
}

protocol OllamaChatDiagnosing {
    var configuration: ProviderConfiguration { get }

    func runtimeVersion() async throws -> String
    func listModels() async throws -> [ProviderModel]
    func runDiagnosticChat(model: String) async throws -> String
}

extension ChatProvider {
    var capabilities: ProviderCapabilities {
        configuration.capabilities
    }

    func streamChat(
        model: String,
        messages: [ProviderChatMessage],
        options: ProviderChatOptions?
    ) -> AsyncThrowingStream<String, Error> {
        streamChat(model: model, messages: messages)
    }

    func streamChatEvents(model: String, messages: [ProviderChatMessage]) -> AsyncThrowingStream<ChatStreamEvent, Error> {
        streamChatEvents(model: model, messages: messages, options: nil)
    }

    func streamChatEvents(
        model: String,
        messages: [ProviderChatMessage],
        options: ProviderChatOptions?
    ) -> AsyncThrowingStream<ChatStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    for try await chunk in streamChat(model: model, messages: messages, options: options) {
                        continuation.yield(.content(chunk))
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    func streamCompletion(
        model: String,
        prompt: String,
        options: ProviderChatOptions?
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish(throwing: ProviderError.unsupportedCompletions(configuration.name))
        }
    }

    func generateImages(request: ImageGenerationRequest) async throws -> ImageGenerationResult {
        throw ProviderError.unsupportedImageGeneration(configuration.name)
    }

    func editImage(request: ImageEditRequest) async throws -> ImageGenerationResult {
        throw ProviderError.unsupportedImageEditing(configuration.name)
    }

    func varyImage(request: ImageVariationRequest) async throws -> ImageGenerationResult {
        throw ProviderError.unsupportedImageVariation(configuration.name)
    }

    func transcribeAudio(request: AudioTranscriptionRequest) async throws -> AudioTranscriptionResult {
        throw ProviderError.unsupportedAudioTranscription(configuration.name)
    }

    func synthesizeSpeech(request: SpeechSynthesisRequest) async throws -> SpeechSynthesisResult {
        throw ProviderError.unsupportedSpeechSynthesis(configuration.name)
    }
}

struct ProviderChatOptions: Codable, Equatable, Sendable {
    var temperature: Double?
    var topP: Double?
    var maxTokens: Int?
}

enum ChatStreamEvent: Equatable, Sendable {
    case content(String)
    case tokenUsage(ChatTokenUsage)
}

struct ImageGenerationRequest: Codable, Equatable, Sendable {
    var model: String
    var prompt: String
    var size: String
    var quality: String?
    var count: Int

    init(
        model: String,
        prompt: String,
        size: String = "1024x1024",
        quality: String? = nil,
        count: Int = 1
    ) {
        self.model = model
        self.prompt = prompt
        self.size = size
        self.quality = quality
        self.count = count
    }
}

struct GeneratedImage: Equatable, Sendable {
    var data: Data
    var revisedPrompt: String?
}

struct ImageGenerationResult: Equatable, Sendable {
    var images: [GeneratedImage]
    var outputFormat: String?
    var size: String?
    var quality: String?
}

struct ImageEditRequest: Equatable, Sendable {
    var model: String
    var prompt: String
    var imageData: Data
    var imageFileName: String
    var imageContentType: String
    var maskData: Data?
    var maskFileName: String?
    var maskContentType: String?
    var size: String
    var quality: String?
    var count: Int

    init(
        model: String,
        prompt: String,
        imageData: Data,
        imageFileName: String = "image.png",
        imageContentType: String = "image/png",
        maskData: Data? = nil,
        maskFileName: String? = nil,
        maskContentType: String? = nil,
        size: String = "1024x1024",
        quality: String? = nil,
        count: Int = 1
    ) {
        self.model = model
        self.prompt = prompt
        self.imageData = imageData
        self.imageFileName = imageFileName
        self.imageContentType = imageContentType
        self.maskData = maskData
        self.maskFileName = maskFileName
        self.maskContentType = maskContentType
        self.size = size
        self.quality = quality
        self.count = count
    }
}

struct ImageVariationRequest: Equatable, Sendable {
    var model: String
    var imageData: Data
    var imageFileName: String
    var imageContentType: String
    var size: String
    var count: Int

    init(
        model: String,
        imageData: Data,
        imageFileName: String = "image.png",
        imageContentType: String = "image/png",
        size: String = "1024x1024",
        count: Int = 1
    ) {
        self.model = model
        self.imageData = imageData
        self.imageFileName = imageFileName
        self.imageContentType = imageContentType
        self.size = size
        self.count = count
    }
}

struct AudioTranscriptionRequest: Equatable, Sendable {
    var model: String
    var audioData: Data
    var fileName: String
    var contentType: String
    var responseFormat: String
    var prompt: String?
    var language: String?

    init(
        model: String,
        audioData: Data,
        fileName: String,
        contentType: String,
        responseFormat: String = "text",
        prompt: String? = nil,
        language: String? = nil
    ) {
        self.model = model
        self.audioData = audioData
        self.fileName = fileName
        self.contentType = contentType
        self.responseFormat = responseFormat
        self.prompt = prompt
        self.language = language
    }
}

struct AudioTranscriptionResult: Equatable, Sendable {
    var text: String
}

struct SpeechSynthesisRequest: Codable, Equatable, Sendable {
    var model: String
    var input: String
    var voice: String
    var instructions: String?
    var responseFormat: String

    enum CodingKeys: String, CodingKey {
        case model
        case input
        case voice
        case instructions
        case responseFormat = "response_format"
    }

    init(
        model: String,
        input: String,
        voice: String = "coral",
        instructions: String? = nil,
        responseFormat: String = "mp3"
    ) {
        self.model = model
        self.input = input
        self.voice = voice
        self.instructions = instructions
        self.responseFormat = responseFormat
    }
}

struct SpeechSynthesisResult: Equatable, Sendable {
    var audioData: Data
    var outputFormat: String
}

protocol OllamaModelManaging {
    func pullModel(named name: String) -> AsyncThrowingStream<OllamaModelPullProgress, Error>
    func deleteModel(named name: String) async throws
}

struct OllamaModelPullProgress: Decodable, Equatable, Sendable {
    var status: String
    var digest: String?
    var total: Int?
    var completed: Int?

    var progressFraction: Double? {
        guard let total, let completed, total > 0 else {
            return nil
        }
        return min(max(Double(completed) / Double(total), 0), 1)
    }
}

struct ProviderFactory {
    var secretStore: SecretStoring

    func makeProvider(
        for configuration: ProviderConfiguration,
        dataLoader: @escaping OpenAICompatibleClient.DataLoader = OpenAICompatibleClient.defaultDataLoader,
        lineStreamLoader: @escaping OpenAICompatibleClient.LineStreamLoader = OpenAICompatibleClient.defaultLineStreamLoader
    ) throws -> any ChatProvider {
        if configuration.kind == .localFunction {
            throw ProviderError.unsupportedChat("Local Function")
        }
        guard let baseURL = URL(string: configuration.baseURL), baseURL.scheme != nil else {
            throw ProviderError.invalidBaseURL(configuration.baseURL)
        }

        switch configuration.kind {
        case .ollama:
            return OllamaClient(baseURL: baseURL, configuration: configuration)
        case .openAICompatible:
            return OpenAICompatibleClient(
                configuration: configuration,
                secretStore: secretStore,
                dataLoader: dataLoader,
                lineStreamLoader: lineStreamLoader
            )
        case .localFunction:
            throw ProviderError.unsupportedChat("Local Function")
        }
    }
}
