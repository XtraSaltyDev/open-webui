import Foundation

struct OpenAICompatibleClient: ChatProvider {
    typealias DataLoader = (URLRequest) async throws -> (Data, URLResponse)
    typealias LineStreamLoader = (URLRequest) async throws -> AsyncThrowingStream<String, Error>

    let configuration: ProviderConfiguration
    private let secretStore: SecretStoring
    private let dataLoader: DataLoader
    private let lineStreamLoader: LineStreamLoader
    private let decoder = JSONDecoder()

    init(
        configuration: ProviderConfiguration,
        secretStore: SecretStoring,
        dataLoader: @escaping DataLoader = OpenAICompatibleClient.defaultDataLoader,
        lineStreamLoader: @escaping LineStreamLoader = OpenAICompatibleClient.defaultLineStreamLoader
    ) {
        self.configuration = configuration
        self.secretStore = secretStore
        self.dataLoader = dataLoader
        self.lineStreamLoader = lineStreamLoader
    }

    func listModels() async throws -> [ProviderModel] {
        var request = try await authorizedRequest(path: "/models")
        request.httpMethod = "GET"

        let (data, response) = try await dataLoader(request)
        try Self.validate(response)

        let payload = try decoder.decode(OpenAIModelsResponse.self, from: data)
        return payload.data.map { model in
            ProviderModel(
                id: model.id,
                name: model.id,
                provider: .openAICompatible,
                providerID: configuration.id,
                details: model.ownedBy
            )
        }
    }

    func healthCheck() async -> ProviderStatus {
        do {
            let models = try await listModels()
            return .available("\(configuration.name) connected (\(models.count) models)")
        } catch {
            return .unavailable(error.localizedDescription)
        }
    }

    func streamChat(model: String, messages: [ProviderChatMessage]) -> AsyncThrowingStream<String, Error> {
        streamChat(model: model, messages: messages, options: nil)
    }

    func streamChat(
        model: String,
        messages: [ProviderChatMessage],
        options: ProviderChatOptions?
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    for try await event in streamChatEvents(model: model, messages: messages, options: options) {
                        if case .content(let content) = event {
                            continuation.yield(content)
                        }
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

    func streamChatEvents(
        model: String,
        messages: [ProviderChatMessage],
        options: ProviderChatOptions?
    ) -> AsyncThrowingStream<ChatStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    var request = try await authorizedRequest(path: "/chat/completions")
                    request.httpMethod = "POST"
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    request.httpBody = try JSONEncoder().encode(
                        OpenAIChatCompletionsRequest(model: model, messages: messages, stream: true, options: options)
                    )

                    let lines = try await lineStreamLoader(request)
                    for try await line in lines {
                        let payload = line.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard payload.hasPrefix("data:") else {
                            continue
                        }

                        let dataString = payload.dropFirst("data:".count).trimmingCharacters(in: .whitespacesAndNewlines)
                        if dataString == "[DONE]" {
                            break
                        }

                        let event = try decoder.decode(
                            OpenAIChatCompletionChunk.self,
                            from: Data(dataString.utf8)
                        )
                        for choice in event.choices {
                            if let content = choice.delta?.content, !content.isEmpty {
                                continuation.yield(.content(content))
                            }
                        }
                        if let usage = event.usage?.tokenUsage {
                            continuation.yield(.tokenUsage(usage))
                        }
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
            let task = Task {
                do {
                    var request = try await authorizedRequest(path: "/completions")
                    request.httpMethod = "POST"
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    request.httpBody = try JSONEncoder().encode(
                        OpenAICompletionsRequest(model: model, prompt: prompt, stream: true, options: options)
                    )

                    let lines = try await lineStreamLoader(request)
                    for try await line in lines {
                        let payload = line.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard payload.hasPrefix("data:") else {
                            continue
                        }

                        let dataString = payload.dropFirst("data:".count).trimmingCharacters(in: .whitespacesAndNewlines)
                        if dataString == "[DONE]" {
                            break
                        }

                        let event = try decoder.decode(
                            OpenAICompletionChunk.self,
                            from: Data(dataString.utf8)
                        )
                        for choice in event.choices {
                            if let text = choice.text, !text.isEmpty {
                                continuation.yield(text)
                            }
                        }
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

    func createEmbeddings(model: String, input: [String]) async throws -> [[Double]] {
        var request = try await authorizedRequest(path: "/embeddings")
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(OpenAIEmbeddingsRequest(model: model, input: input))

        let (data, response) = try await dataLoader(request)
        try Self.validate(response)

        let payload = try decoder.decode(OpenAIEmbeddingsResponse.self, from: data)
        return payload.data.sorted { $0.index < $1.index }.map(\.embedding)
    }

    func generateImages(request imageRequest: ImageGenerationRequest) async throws -> ImageGenerationResult {
        var request = try await authorizedRequest(path: "/images/generations")
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(OpenAIImageGenerationRequest(request: imageRequest))

        let (data, response) = try await dataLoader(request)
        try Self.validate(response)

        let payload = try decoder.decode(OpenAIImageGenerationResponse.self, from: data)
        return ImageGenerationResult(
            images: payload.data.compactMap(\.generatedImage),
            outputFormat: payload.outputFormat,
            size: payload.size,
            quality: payload.quality
        )
    }

    func editImage(request imageRequest: ImageEditRequest) async throws -> ImageGenerationResult {
        var request = try await authorizedRequest(path: "/images/edits")
        request.httpMethod = "POST"
        let boundary = "Boundary-\(UUID().uuidString)"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        var form = MultipartFormDataBuilder(boundary: boundary)
            .addingField(name: "model", value: imageRequest.model)
            .addingField(name: "prompt", value: imageRequest.prompt)
            .addingField(name: "size", value: imageRequest.size)
            .addingOptionalField(name: "quality", value: imageRequest.quality)
            .addingField(name: "n", value: "\(imageRequest.count)")
            .addingFile(
                name: "image",
                fileName: imageRequest.imageFileName,
                contentType: imageRequest.imageContentType,
                data: imageRequest.imageData
            )

        if let maskData = imageRequest.maskData {
            form = form.addingFile(
                name: "mask",
                fileName: imageRequest.maskFileName?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? "mask.png",
                contentType: imageRequest.maskContentType?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? "image/png",
                data: maskData
            )
        }

        request.httpBody = form
            .build()

        let (data, response) = try await dataLoader(request)
        try Self.validate(response)

        let payload = try decoder.decode(OpenAIImageGenerationResponse.self, from: data)
        return ImageGenerationResult(
            images: payload.data.compactMap(\.generatedImage),
            outputFormat: payload.outputFormat,
            size: payload.size,
            quality: payload.quality
        )
    }

    func varyImage(request imageRequest: ImageVariationRequest) async throws -> ImageGenerationResult {
        var request = try await authorizedRequest(path: "/images/variations")
        request.httpMethod = "POST"
        let boundary = "Boundary-\(UUID().uuidString)"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = MultipartFormDataBuilder(boundary: boundary)
            .addingField(name: "model", value: imageRequest.model)
            .addingField(name: "size", value: imageRequest.size)
            .addingField(name: "n", value: "\(imageRequest.count)")
            .addingField(name: "response_format", value: "b64_json")
            .addingFile(
                name: "image",
                fileName: imageRequest.imageFileName,
                contentType: imageRequest.imageContentType,
                data: imageRequest.imageData
            )
            .build()

        let (data, response) = try await dataLoader(request)
        try Self.validate(response)

        let payload = try decoder.decode(OpenAIImageGenerationResponse.self, from: data)
        return ImageGenerationResult(
            images: payload.data.compactMap(\.generatedImage),
            outputFormat: payload.outputFormat,
            size: payload.size,
            quality: payload.quality
        )
    }

    func transcribeAudio(request audioRequest: AudioTranscriptionRequest) async throws -> AudioTranscriptionResult {
        var request = try await authorizedRequest(path: "/audio/transcriptions")
        request.httpMethod = "POST"
        let boundary = "Boundary-\(UUID().uuidString)"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = MultipartFormDataBuilder(boundary: boundary)
            .addingField(name: "model", value: audioRequest.model)
            .addingField(name: "response_format", value: audioRequest.responseFormat)
            .addingOptionalField(name: "prompt", value: audioRequest.prompt)
            .addingOptionalField(name: "language", value: audioRequest.language)
            .addingFile(
                name: "file",
                fileName: audioRequest.fileName,
                contentType: audioRequest.contentType,
                data: audioRequest.audioData
            )
            .build()

        let (data, response) = try await dataLoader(request)
        try Self.validate(response)

        return AudioTranscriptionResult(
            text: String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        )
    }

    func synthesizeSpeech(request speechRequest: SpeechSynthesisRequest) async throws -> SpeechSynthesisResult {
        var request = try await authorizedRequest(path: "/audio/speech")
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(speechRequest)

        let (data, response) = try await dataLoader(request)
        try Self.validate(response)

        return SpeechSynthesisResult(audioData: data, outputFormat: speechRequest.responseFormat)
    }

    private func authorizedRequest(path: String) async throws -> URLRequest {
        guard let baseURL = URL(string: configuration.baseURL), baseURL.scheme != nil else {
            throw ProviderError.invalidBaseURL(configuration.baseURL)
        }
        guard let secretID = configuration.apiKeySecretID,
              let apiKey = try await secretStore.readSecret(id: secretID),
              !apiKey.isEmpty else {
            throw ProviderError.missingAPIKey(configuration.name)
        }

        var request = URLRequest(url: baseURL.appending(path: path))
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        return request
    }

    static let defaultDataLoader: DataLoader = { request in
        try await URLSession.shared.data(for: request)
    }

    static let defaultLineStreamLoader: LineStreamLoader = { request in
        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        try validate(response)

        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    for try await line in bytes.lines {
                        continuation.yield(line)
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

    private static func validate(_ response: URLResponse) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ProviderError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw ProviderError.httpStatus(httpResponse.statusCode)
        }
    }
}

private struct OpenAIModelsResponse: Decodable {
    var data: [OpenAIModel]
}

private struct OpenAIModel: Decodable {
    var id: String
    var ownedBy: String?

    enum CodingKeys: String, CodingKey {
        case id
        case ownedBy = "owned_by"
    }
}

private struct OpenAIChatCompletionsRequest: Encodable {
    var model: String
    var messages: [ProviderChatMessage]
    var stream: Bool
    var options: ProviderChatOptions?

    enum CodingKeys: String, CodingKey {
        case model
        case messages
        case stream
        case temperature
        case topP = "top_p"
        case maxTokens = "max_tokens"
        case streamOptions = "stream_options"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(model, forKey: .model)
        try container.encode(messages, forKey: .messages)
        try container.encode(stream, forKey: .stream)
        try container.encodeIfPresent(options?.temperature, forKey: .temperature)
        try container.encodeIfPresent(options?.topP, forKey: .topP)
        try container.encodeIfPresent(options?.maxTokens, forKey: .maxTokens)
        if stream {
            try container.encode(OpenAIStreamOptions(includeUsage: true), forKey: .streamOptions)
        }
    }
}

private struct OpenAICompletionsRequest: Encodable {
    var model: String
    var prompt: String
    var stream: Bool
    var options: ProviderChatOptions?

    enum CodingKeys: String, CodingKey {
        case model
        case prompt
        case stream
        case temperature
        case topP = "top_p"
        case maxTokens = "max_tokens"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(model, forKey: .model)
        try container.encode(prompt, forKey: .prompt)
        try container.encode(stream, forKey: .stream)
        try container.encodeIfPresent(options?.temperature, forKey: .temperature)
        try container.encodeIfPresent(options?.topP, forKey: .topP)
        try container.encodeIfPresent(options?.maxTokens, forKey: .maxTokens)
    }
}

private struct OpenAIStreamOptions: Encodable {
    var includeUsage: Bool

    enum CodingKeys: String, CodingKey {
        case includeUsage = "include_usage"
    }
}

private struct OpenAIChatCompletionChunk: Decodable {
    var choices: [OpenAIChatChoice]
    var usage: OpenAIChatUsage?
}

private struct OpenAICompletionChunk: Decodable {
    var choices: [OpenAICompletionChoice]
}

private struct OpenAICompletionChoice: Decodable {
    var text: String?
}

private struct OpenAIChatChoice: Decodable {
    var delta: OpenAIChatDelta?
}

private struct OpenAIChatDelta: Decodable {
    var content: String?
}

private struct OpenAIChatUsage: Decodable {
    var promptTokens: Int?
    var completionTokens: Int?
    var totalTokens: Int?

    enum CodingKeys: String, CodingKey {
        case promptTokens = "prompt_tokens"
        case completionTokens = "completion_tokens"
        case totalTokens = "total_tokens"
    }

    var tokenUsage: ChatTokenUsage {
        ChatTokenUsage(promptTokens: promptTokens, completionTokens: completionTokens, totalTokens: totalTokens)
    }
}

private struct OpenAIEmbeddingsRequest: Encodable {
    var model: String
    var input: [String]
    var encodingFormat: String = "float"

    enum CodingKeys: String, CodingKey {
        case model
        case input
        case encodingFormat = "encoding_format"
    }
}

private struct OpenAIEmbeddingsResponse: Decodable {
    var data: [OpenAIEmbeddingData]
}

private struct OpenAIEmbeddingData: Decodable {
    var index: Int
    var embedding: [Double]
}

private struct OpenAIImageGenerationRequest: Encodable {
    var model: String
    var prompt: String
    var size: String
    var quality: String?
    var count: Int

    enum CodingKeys: String, CodingKey {
        case model
        case prompt
        case size
        case quality
        case count = "n"
    }

    init(request: ImageGenerationRequest) {
        model = request.model
        prompt = request.prompt
        size = request.size
        quality = request.quality
        count = request.count
    }
}

private struct OpenAIImageGenerationResponse: Decodable {
    var data: [OpenAIImageData]
    var outputFormat: String?
    var size: String?
    var quality: String?

    enum CodingKeys: String, CodingKey {
        case data
        case outputFormat = "output_format"
        case size
        case quality
    }
}

private struct OpenAIImageData: Decodable {
    var b64JSON: String?
    var revisedPrompt: String?

    enum CodingKeys: String, CodingKey {
        case b64JSON = "b64_json"
        case revisedPrompt = "revised_prompt"
    }

    var generatedImage: GeneratedImage? {
        guard let b64JSON, let data = Data(base64Encoded: b64JSON) else {
            return nil
        }
        return GeneratedImage(data: data, revisedPrompt: revisedPrompt)
    }
}

private struct MultipartFormDataBuilder {
    private let boundary: String
    private var data = Data()

    init(boundary: String) {
        self.boundary = boundary
    }

    func addingField(name: String, value: String) -> MultipartFormDataBuilder {
        var builder = self
        builder.appendBoundary()
        builder.append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n")
        builder.append("\(value)\r\n")
        return builder
    }

    func addingOptionalField(name: String, value: String?) -> MultipartFormDataBuilder {
        guard let value, !value.isEmpty else {
            return self
        }
        return addingField(name: name, value: value)
    }

    func addingFile(name: String, fileName: String, contentType: String, data fileData: Data) -> MultipartFormDataBuilder {
        var builder = self
        builder.appendBoundary()
        builder.append("Content-Disposition: form-data; name=\"\(name)\"; filename=\"\(fileName)\"\r\n")
        builder.append("Content-Type: \(contentType)\r\n\r\n")
        builder.data.append(fileData)
        builder.append("\r\n")
        return builder
    }

    func build() -> Data {
        var builder = self
        builder.append("--\(boundary)--\r\n")
        return builder.data
    }

    private mutating func appendBoundary() {
        append("--\(boundary)\r\n")
    }

    private mutating func append(_ string: String) {
        data.append(Data(string.utf8))
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
