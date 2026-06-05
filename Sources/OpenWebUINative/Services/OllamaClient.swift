import Foundation

enum ProviderError: Error, LocalizedError, Equatable {
    case invalidBaseURL(String)
    case invalidResponse
    case httpStatus(Int)
    case missingAPIKey(String)
    case noModelsReturned(String)
    case selectedModelUnavailable(String)
    case noModelSelected
    case emptyPrompt
    case unsupportedAttachment(String)
    case unsupportedChat(String)
    case unsupportedCompletions(String)
    case unsupportedModelManagement(String)
    case unsupportedEmbeddings(String)
    case unsupportedImageGeneration(String)
    case unsupportedImageEditing(String)
    case unsupportedImageVariation(String)
    case unsupportedAudioTranscription(String)
    case unsupportedSpeechSynthesis(String)

    var errorDescription: String? {
        switch self {
        case .invalidBaseURL(let value):
            return "Invalid provider URL: \(value)"
        case .invalidResponse:
            return "The provider returned an invalid response."
        case .httpStatus(let statusCode):
            return "The provider returned HTTP \(statusCode)."
        case .missingAPIKey(let providerName):
            return "Add an API key for \(providerName) before connecting."
        case .noModelsReturned(let providerName):
            return "\(providerName) responded, but returned no models."
        case .selectedModelUnavailable(let modelID):
            return "The selected model \(modelID) is no longer available."
        case .noModelSelected:
            return "Choose a model before sending a message."
        case .emptyPrompt:
            return "Type a message before sending."
        case .unsupportedAttachment(let fileName):
            return "\(fileName) could not be read as a text attachment yet."
        case .unsupportedChat(let providerName):
            return "\(providerName) does not support native chat."
        case .unsupportedCompletions(let providerName):
            return "\(providerName) does not support native completions."
        case .unsupportedModelManagement(let providerName):
            return "\(providerName) does not support native model management."
        case .unsupportedEmbeddings(let providerName):
            return "\(providerName) does not support native embeddings."
        case .unsupportedImageGeneration(let providerName):
            return "\(providerName) does not support native image generation."
        case .unsupportedImageEditing(let providerName):
            return "\(providerName) does not support native image editing."
        case .unsupportedImageVariation(let providerName):
            return "\(providerName) does not support native image variations."
        case .unsupportedAudioTranscription(let providerName):
            return "\(providerName) does not support native audio transcription."
        case .unsupportedSpeechSynthesis(let providerName):
            return "\(providerName) does not support native speech synthesis."
        }
    }
}

struct OllamaClient {
    typealias DataLoader = (URLRequest) async throws -> (Data, URLResponse)
    typealias LineStreamLoader = (URLRequest) async throws -> AsyncThrowingStream<String, Error>

    private let baseURL: URL
    let configuration: ProviderConfiguration
    private let dataLoader: DataLoader
    private let lineStreamLoader: LineStreamLoader

    init(
        baseURL: URL,
        configuration: ProviderConfiguration? = nil,
        dataLoader: @escaping DataLoader = OllamaClient.defaultDataLoader,
        lineStreamLoader: @escaping LineStreamLoader = OllamaClient.defaultLineStreamLoader
    ) {
        self.baseURL = baseURL
        self.configuration = configuration ?? ProviderConfiguration.defaultOllama(baseURL: baseURL.absoluteString)
        self.dataLoader = dataLoader
        self.lineStreamLoader = lineStreamLoader
    }

    func listModels() async throws -> [ProviderModel] {
        var request = URLRequest(url: endpoint("/api/tags"))
        request.httpMethod = "GET"

        let (data, response) = try await dataLoader(request)
        try Self.validate(response)

        let payload = try JSONDecoder().decode(OllamaTagsResponse.self, from: data)
        return payload.models.map { model in
            ProviderModel(
                id: model.name,
                name: model.name,
                provider: .ollama,
                providerID: configuration.id,
                details: model.size.map { ByteCountFormatter.string(fromByteCount: Int64($0), countStyle: .file) }
            )
        }
    }

    func runtimeVersion() async throws -> String {
        var request = URLRequest(url: endpoint("/api/version"))
        request.httpMethod = "GET"

        let (data, response) = try await dataLoader(request)
        try Self.validate(response)

        let payload = try JSONDecoder().decode(OllamaVersionResponse.self, from: data)
        return payload.version
    }

    func runningModelCount() async throws -> Int {
        var request = URLRequest(url: endpoint("/api/ps"))
        request.httpMethod = "GET"

        let (data, response) = try await dataLoader(request)
        try Self.validate(response)

        let payload = try JSONDecoder().decode(OllamaRunningModelsResponse.self, from: data)
        return payload.models.count
    }

    func healthCheck() async -> ProviderStatus {
        do {
            let version = try await runtimeVersion()
            let models = try await listModels()
            let runningModelCount = try await runningModelCount()
            guard !models.isEmpty else {
                throw ProviderError.noModelsReturned(configuration.name)
            }
            return .available(
                "Ollama \(version) connected (\(models.count) models, \(runningModelCount) running)"
            )
        } catch {
            return .unavailable(ProviderErrorPresentation.presentation(for: error, provider: configuration).message)
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
                    var request = URLRequest(url: endpoint("/api/chat"))
                    request.httpMethod = "POST"
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    request.httpBody = try JSONEncoder().encode(
                        OllamaChatRequest(model: model, messages: messages, stream: true, options: options)
                    )

                    let lines = try await lineStreamLoader(request)
                    for try await line in lines {
                        guard !line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                            continue
                        }
                        let data = Data(line.utf8)
                        let event = try JSONDecoder().decode(OllamaChatStreamEvent.self, from: data)
                        if let content = event.message?.content, !content.isEmpty {
                            continuation.yield(.content(content))
                        }
                        if let tokenUsage = event.tokenUsage {
                            continuation.yield(.tokenUsage(tokenUsage))
                        }
                        if event.done {
                            break
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
                    var request = URLRequest(url: endpoint("/api/generate"))
                    request.httpMethod = "POST"
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    request.httpBody = try JSONEncoder().encode(
                        OllamaCompletionRequest(model: model, prompt: prompt, stream: true, options: options)
                    )

                    let lines = try await lineStreamLoader(request)
                    for try await line in lines {
                        guard !line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                            continue
                        }
                        let event = try JSONDecoder().decode(OllamaCompletionStreamEvent.self, from: Data(line.utf8))
                        if let response = event.response, !response.isEmpty {
                            continuation.yield(response)
                        }
                        if event.done {
                            break
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

    func pullModel(named name: String) -> AsyncThrowingStream<OllamaModelPullProgress, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    var request = URLRequest(url: endpoint("/api/pull"))
                    request.httpMethod = "POST"
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    request.httpBody = try JSONEncoder().encode(OllamaModelNameRequest(model: name, stream: true))

                    let lines = try await lineStreamLoader(request)
                    for try await line in lines {
                        guard !line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                            continue
                        }
                        let progress = try JSONDecoder().decode(OllamaModelPullProgress.self, from: Data(line.utf8))
                        continuation.yield(progress)
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

    func deleteModel(named name: String) async throws {
        var request = URLRequest(url: endpoint("/api/delete"))
        request.httpMethod = "DELETE"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(OllamaModelNameRequest(model: name, stream: nil))

        let (_, response) = try await dataLoader(request)
        try Self.validate(response)
    }

    private func endpoint(_ path: String) -> URL {
        baseURL.appending(path: path)
    }

    private static let defaultDataLoader: DataLoader = { request in
        try await URLSession.shared.data(for: request)
    }

    private static let defaultLineStreamLoader: LineStreamLoader = { request in
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

extension OllamaClient: ChatProvider {
    func createEmbeddings(model: String, input: [String]) async throws -> [[Double]] {
        throw ProviderError.invalidResponse
    }
}

extension OllamaClient: OllamaModelManaging {}

private struct OllamaTagsResponse: Decodable {
    var models: [OllamaModel]
}

private struct OllamaModel: Decodable {
    var name: String
    var size: Int?
}

private struct OllamaVersionResponse: Decodable {
    var version: String
}

private struct OllamaRunningModelsResponse: Decodable {
    var models: [OllamaRunningModel]
}

private struct OllamaRunningModel: Decodable {
    var name: String?
}

private struct OllamaChatRequest: Encodable {
    var model: String
    var messages: [ProviderChatMessage]
    var stream: Bool
    var options: ProviderChatOptions?

    enum CodingKeys: String, CodingKey {
        case model
        case messages
        case stream
        case options
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(model, forKey: .model)
        try container.encode(messages, forKey: .messages)
        try container.encode(stream, forKey: .stream)
        try container.encodeIfPresent(options?.ollamaOptions, forKey: .options)
    }
}

private struct OllamaCompletionRequest: Encodable {
    var model: String
    var prompt: String
    var stream: Bool
    var options: ProviderChatOptions?

    enum CodingKeys: String, CodingKey {
        case model
        case prompt
        case stream
        case options
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(model, forKey: .model)
        try container.encode(prompt, forKey: .prompt)
        try container.encode(stream, forKey: .stream)
        try container.encodeIfPresent(options?.ollamaOptions, forKey: .options)
    }
}

private struct OllamaChatOptions: Encodable {
    var temperature: Double?
    var topP: Double?
    var numPredict: Int?

    enum CodingKeys: String, CodingKey {
        case temperature
        case topP = "top_p"
        case numPredict = "num_predict"
    }
}

private extension ProviderChatOptions {
    var ollamaOptions: OllamaChatOptions? {
        let mapped = OllamaChatOptions(temperature: temperature, topP: topP, numPredict: maxTokens)
        guard mapped.temperature != nil || mapped.topP != nil || mapped.numPredict != nil else {
            return nil
        }
        return mapped
    }
}

private struct OllamaChatStreamEvent: Decodable {
    var message: OllamaStreamMessage?
    var done: Bool
    var promptEvalCount: Int?
    var evalCount: Int?

    enum CodingKeys: String, CodingKey {
        case message
        case done
        case promptEvalCount = "prompt_eval_count"
        case evalCount = "eval_count"
    }

    var tokenUsage: ChatTokenUsage? {
        guard promptEvalCount != nil || evalCount != nil else {
            return nil
        }
        return ChatTokenUsage(promptTokens: promptEvalCount, completionTokens: evalCount)
    }
}

private struct OllamaCompletionStreamEvent: Decodable {
    var response: String?
    var done: Bool
}

private struct OllamaStreamMessage: Decodable {
    var role: String?
    var content: String
}

private struct OllamaModelNameRequest: Encodable {
    var model: String
    var stream: Bool?

    enum CodingKeys: String, CodingKey {
        case model
        case stream
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(model, forKey: .model)
        try container.encodeIfPresent(stream, forKey: .stream)
    }
}
