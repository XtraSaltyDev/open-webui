import Foundation

enum ProviderError: Error, LocalizedError, Equatable {
    case invalidBaseURL(String)
    case invalidResponse
    case httpStatus(Int, message: String? = nil, bodySnippet: String? = nil, endpoint: String? = nil)
    case malformedStreamLine(endpoint: String, lineSnippet: String)
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
        case .httpStatus(let statusCode, let message, _, let endpoint):
            let endpointText = endpoint.map { " from \($0)" } ?? ""
            let messageText = message.map { ": \($0)" } ?? "."
            return "The provider returned HTTP \(statusCode)\(endpointText)\(messageText)"
        case .malformedStreamLine(let endpoint, let lineSnippet):
            return "The provider returned malformed streaming JSON from \(endpoint): \(lineSnippet)"
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
        try Self.validate(response, data: data, endpoint: request.url?.path)

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
        try Self.validate(response, data: data, endpoint: request.url?.path)

        let payload = try JSONDecoder().decode(OllamaVersionResponse.self, from: data)
        return payload.version
    }

    func runningModelCount() async throws -> Int {
        var request = URLRequest(url: endpoint("/api/ps"))
        request.httpMethod = "GET"

        let (data, response) = try await dataLoader(request)
        try Self.validate(response, data: data, endpoint: request.url?.path)

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

    func runDiagnosticChat(model: String) async throws -> String {
        var request = URLRequest(url: endpoint("/api/chat"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(
            OllamaChatRequest(
                model: model,
                messages: [OllamaChatMessage(role: "user", content: "Reply with OK.")],
                stream: false,
                options: nil
            )
        )

        let (data, response) = try await dataLoader(request)
        try Self.validate(response, data: data, endpoint: request.url?.path)

        let payload = try JSONDecoder().decode(OllamaChatResponse.self, from: data)
        guard let content = payload.message?.content.trimmingCharacters(in: .whitespacesAndNewlines),
              !content.isEmpty else {
            throw ProviderError.invalidResponse
        }
        return content
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
                        OllamaChatRequest(model: model, messages: messages.ollamaSanitized(), stream: true, options: options)
                    )

                    let lines = try await lineStreamLoader(request)
                    for try await line in lines {
                        guard !line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                            continue
                        }
                        let data = Data(line.utf8)
                        let event: OllamaChatStreamEvent
                        do {
                            event = try JSONDecoder().decode(OllamaChatStreamEvent.self, from: data)
                        } catch {
                            throw ProviderError.malformedStreamLine(
                                endpoint: request.url?.path ?? "/api/chat",
                                lineSnippet: Self.cappedSnippet(line)
                            )
                        }
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

        let (data, response) = try await dataLoader(request)
        try Self.validate(response, data: data, endpoint: request.url?.path)
    }

    private func endpoint(_ path: String) -> URL {
        baseURL.appending(path: path)
    }

    private static let defaultDataLoader: DataLoader = { request in
        try await URLSession.shared.data(for: request)
    }

    private static let defaultLineStreamLoader: LineStreamLoader = { request in
        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        if let httpResponse = response as? HTTPURLResponse,
           !(200..<300).contains(httpResponse.statusCode) {
            let bodySnippet = try await cappedSnippet(from: bytes.lines)
            throw httpStatusError(
                statusCode: httpResponse.statusCode,
                bodySnippet: bodySnippet,
                endpoint: request.url?.path
            )
        }
        try validate(response, data: Data(), endpoint: request.url?.path)

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

    private static func validate(_ response: URLResponse, data: Data, endpoint: String?) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ProviderError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw httpStatusError(
                statusCode: httpResponse.statusCode,
                bodySnippet: String(data: data, encoding: .utf8).map { cappedSnippet($0) },
                endpoint: endpoint
            )
        }
    }

    private static func httpStatusError(
        statusCode: Int,
        bodySnippet: String?,
        endpoint: String?
    ) -> ProviderError {
        ProviderError.httpStatus(
            statusCode,
            message: extractedErrorMessage(from: bodySnippet),
            bodySnippet: bodySnippet,
            endpoint: endpoint
        )
    }

    private static func extractedErrorMessage(from bodySnippet: String?) -> String? {
        guard let bodySnippet, !bodySnippet.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        if let data = bodySnippet.data(using: .utf8),
           let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            for key in ["error", "message", "detail"] {
                if let value = object[key] as? String,
                   !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    return cappedSnippet(value)
                }
            }
        }
        return cappedSnippet(bodySnippet)
    }

    fileprivate static func cappedSnippet(_ text: String, maxCharacters: Int = 1_000) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > maxCharacters else {
            return trimmed
        }
        return String(trimmed.prefix(maxCharacters))
    }

    private static func cappedSnippet(
        from lines: AsyncLineSequence<URLSession.AsyncBytes>,
        maxCharacters: Int = 1_000
    ) async throws -> String {
        var captured = ""
        for try await line in lines {
            if !captured.isEmpty {
                captured += "\n"
            }
            captured += line
            if captured.count >= maxCharacters {
                break
            }
        }
        return cappedSnippet(captured, maxCharacters: maxCharacters)
    }
}

extension OllamaClient: ChatProvider {
    func createEmbeddings(model: String, input: [String]) async throws -> [[Double]] {
        throw ProviderError.invalidResponse
    }
}

extension OllamaClient: OllamaChatDiagnosing {}

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
    var messages: [OllamaChatMessage]
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

private struct OllamaChatMessage: Encodable {
    var role: String
    var content: String
}

private struct OllamaChatResponse: Decodable {
    var message: OllamaStreamMessage?
    var done: Bool?
}

private extension Array where Element == ProviderChatMessage {
    func ollamaSanitized() throws -> [OllamaChatMessage] {
        let messages = compactMap { message -> OllamaChatMessage? in
            let content = message.content.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !content.isEmpty else {
                return nil
            }

            let normalizedRole: String
            switch message.role.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
            case ChatRole.system.rawValue:
                normalizedRole = ChatRole.system.rawValue
            case ChatRole.assistant.rawValue:
                normalizedRole = ChatRole.assistant.rawValue
            case ChatRole.user.rawValue:
                normalizedRole = ChatRole.user.rawValue
            default:
                normalizedRole = ChatRole.user.rawValue
            }

            return OllamaChatMessage(role: normalizedRole, content: content)
        }

        guard !messages.isEmpty else {
            throw ProviderError.emptyPrompt
        }
        return messages
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
