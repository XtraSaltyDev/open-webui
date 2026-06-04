import Foundation

protocol ToolServerToolDiscovering: Sendable {
    func discoverTools(for server: AppToolServer) async -> ToolServerToolDiscoveryResult
}

protocol ToolServerToolCalling: Sendable {
    func callTool(_ request: ToolServerToolCallRequest) async -> AppToolServerRun
}

struct ToolServerMCPDiscoveryService: ToolServerToolDiscovering, ToolServerToolCalling {
    typealias DataLoader = @Sendable (URLRequest) async throws -> (Data, URLResponse)

    private let dataLoader: DataLoader
    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes]
        return encoder
    }()
    private let decoder = JSONDecoder()

    init(dataLoader: @escaping DataLoader = { request in
        try await ToolServerMCPDiscoveryService.defaultDataLoader(request)
    }) {
        self.dataLoader = dataLoader
    }

    func discoverTools(for server: AppToolServer) async -> ToolServerToolDiscoveryResult {
        switch server.kind {
        case .stdio:
            return discoverStdioTools(for: server)
        case .http:
            return await discoverHTTPTools(for: server)
        }
    }

    private func discoverHTTPTools(for server: AppToolServer) async -> ToolServerToolDiscoveryResult {
        guard let baseURL = server.baseURL?.trimmingCharacters(in: .whitespacesAndNewlines),
              let url = URL(string: baseURL),
              let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              url.host != nil else {
            return ToolServerToolDiscoveryResult(status: .unavailable("Invalid URL."), tools: [])
        }

        do {
            let initializeResponse: MCPInitializeResponse = try await sendJSONRPCRequest(
                MCPJSONRPCRequest(
                    id: 1,
                    method: "initialize",
                    params: .object([
                        "protocolVersion": .string("2025-06-18"),
                        "capabilities": .object([:]),
                        "clientInfo": .object([
                            "name": .string("OpenWebUINative"),
                            "version": .string("0.1.0")
                        ])
                    ])
                ),
                to: url,
                sessionID: nil
            )

            try await sendJSONRPCNotification(
                MCPJSONRPCNotification(method: "notifications/initialized"),
                to: url,
                sessionID: initializeResponse.sessionID
            )

            let toolsResponse: MCPToolsListResponse = try await sendJSONRPCRequest(
                MCPJSONRPCRequest(id: 2, method: "tools/list"),
                to: url,
                sessionID: initializeResponse.sessionID
            )

            return ToolServerToolDiscoveryResult(
                status: .available("Discovered \(toolsResponse.tools.count) tools."),
                tools: toolsResponse.tools
            )
        } catch {
            return ToolServerToolDiscoveryResult(status: .unavailable(error.localizedDescription), tools: [])
        }
    }

    private func discoverStdioTools(for server: AppToolServer) -> ToolServerToolDiscoveryResult {
        do {
            let session = try StdioMCPProcessSession(server: server)
            defer {
                session.close()
            }

            _ = try sendStdioJSONRPCRequest(
                MCPJSONRPCRequest(
                    id: 1,
                    method: "initialize",
                    params: .object([
                        "protocolVersion": .string("2025-06-18"),
                        "capabilities": .object([:]),
                        "clientInfo": .object([
                            "name": .string("OpenWebUINative"),
                            "version": .string("0.1.0")
                        ])
                    ])
                ),
                session: session
            ) as MCPInitializeResponse

            try sendStdioJSONRPCNotification(
                MCPJSONRPCNotification(method: "notifications/initialized"),
                session: session
            )

            let toolsResponse: MCPToolsListResponse = try sendStdioJSONRPCRequest(
                MCPJSONRPCRequest(id: 2, method: "tools/list"),
                session: session
            )

            return ToolServerToolDiscoveryResult(
                status: .available("Discovered \(toolsResponse.tools.count) tools."),
                tools: toolsResponse.tools
            )
        } catch {
            return ToolServerToolDiscoveryResult(status: .unavailable(error.localizedDescription), tools: [])
        }
    }

    func callTool(_ request: ToolServerToolCallRequest) async -> AppToolServerRun {
        let startedAt = Date()
        switch request.server.kind {
        case .stdio:
            return callStdioTool(request, startedAt: startedAt)
        case .http:
            return await callHTTPTool(request, startedAt: startedAt)
        }
    }

    private func callHTTPTool(_ request: ToolServerToolCallRequest, startedAt: Date) async -> AppToolServerRun {
        guard let baseURL = request.server.baseURL?.trimmingCharacters(in: .whitespacesAndNewlines),
              let url = URL(string: baseURL),
              let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              url.host != nil else {
            return failedRun(
                request,
                responseBody: "",
                errorMessage: "Invalid URL.",
                startedAt: startedAt
            )
        }

        do {
            let initializeResponse: MCPInitializeResponse = try await sendJSONRPCRequest(
                MCPJSONRPCRequest(
                    id: 1,
                    method: "initialize",
                    params: .object([
                        "protocolVersion": .string("2025-06-18"),
                        "capabilities": .object([:]),
                        "clientInfo": .object([
                            "name": .string("OpenWebUINative"),
                            "version": .string("0.1.0")
                        ])
                    ])
                ),
                to: url,
                sessionID: nil
            )

            try await sendJSONRPCNotification(
                MCPJSONRPCNotification(method: "notifications/initialized"),
                to: url,
                sessionID: initializeResponse.sessionID
            )

            let toolResponse: MCPToolCallResponse = try await sendJSONRPCRequest(
                MCPJSONRPCRequest(
                    id: 2,
                    method: "tools/call",
                    params: .object([
                        "name": .string(request.toolName),
                        "arguments": request.arguments
                    ])
                ),
                to: url,
                sessionID: initializeResponse.sessionID
            )
            let responseBody = String(data: try encoder.encode(toolResponse), encoding: .utf8) ?? ""
            let didToolError = toolResponse.isError ?? false

            return AppToolServerRun(
                serverID: request.server.id,
                serverName: request.server.name,
                serverKind: request.server.kind,
                requestBody: argumentsBody(for: request.arguments),
                responseBody: responseBody,
                statusCode: 200,
                status: didToolError ? .failed : .succeeded,
                errorMessage: didToolError ? "Tool returned an error." : nil,
                startedAt: startedAt,
                completedAt: Date()
            )
        } catch {
            return failedRun(
                request,
                responseBody: "",
                errorMessage: error.localizedDescription,
                startedAt: startedAt
            )
        }
    }

    private func callStdioTool(_ request: ToolServerToolCallRequest, startedAt: Date) -> AppToolServerRun {
        do {
            let session = try StdioMCPProcessSession(server: request.server)
            defer {
                session.close()
            }

            _ = try sendStdioJSONRPCRequest(
                MCPJSONRPCRequest(
                    id: 1,
                    method: "initialize",
                    params: .object([
                        "protocolVersion": .string("2025-06-18"),
                        "capabilities": .object([:]),
                        "clientInfo": .object([
                            "name": .string("OpenWebUINative"),
                            "version": .string("0.1.0")
                        ])
                    ])
                ),
                session: session
            ) as MCPInitializeResponse

            try sendStdioJSONRPCNotification(
                MCPJSONRPCNotification(method: "notifications/initialized"),
                session: session
            )

            let toolResponse: MCPToolCallResponse = try sendStdioJSONRPCRequest(
                MCPJSONRPCRequest(
                    id: 2,
                    method: "tools/call",
                    params: .object([
                        "name": .string(request.toolName),
                        "arguments": request.arguments
                    ])
                ),
                session: session
            )
            let responseBody = String(data: try encoder.encode(toolResponse), encoding: .utf8) ?? ""
            let didToolError = toolResponse.isError ?? false

            return AppToolServerRun(
                serverID: request.server.id,
                serverName: request.server.name,
                serverKind: request.server.kind,
                requestBody: argumentsBody(for: request.arguments),
                responseBody: responseBody,
                statusCode: nil,
                status: didToolError ? .failed : .succeeded,
                errorMessage: didToolError ? "Tool returned an error." : nil,
                startedAt: startedAt,
                completedAt: Date()
            )
        } catch {
            return failedRun(
                request,
                responseBody: "",
                errorMessage: error.localizedDescription,
                startedAt: startedAt
            )
        }
    }

    private func argumentsBody(for arguments: JSONValue) -> String {
        (try? String(data: encoder.encode(arguments), encoding: .utf8)) ?? "{}"
    }

    private func failedRun(
        _ request: ToolServerToolCallRequest,
        responseBody: String,
        errorMessage: String,
        startedAt: Date
    ) -> AppToolServerRun {
        AppToolServerRun(
            serverID: request.server.id,
            serverName: request.server.name,
            serverKind: request.server.kind,
            requestBody: argumentsBody(for: request.arguments),
            responseBody: responseBody,
            statusCode: nil,
            status: .failed,
            errorMessage: errorMessage,
            startedAt: startedAt,
            completedAt: Date()
        )
    }

    private func sendJSONRPCRequest<Result: Decodable>(
        _ message: MCPJSONRPCRequest,
        to url: URL,
        sessionID: String?
    ) async throws -> Result {
        let request = try makeRequest(url: url, body: encoder.encode(message), sessionID: sessionID)
        let (data, response) = try await dataLoader(request)
        let sessionID = (response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Mcp-Session-Id")
        try validateHTTP(response)

        if let error = try? decoder.decode(MCPJSONRPCErrorEnvelope.self, from: data),
           let message = error.error?.message {
            throw ToolServerMCPDiscoveryError.server(message)
        }

        var envelope = try decoder.decode(MCPJSONRPCResultEnvelope<Result>.self, from: data)
        if var initializeResponse = envelope.result as? MCPInitializeResponse {
            initializeResponse.sessionID = sessionID
            envelope.result = initializeResponse as! Result
        }
        return envelope.result
    }

    private func sendJSONRPCNotification(
        _ message: MCPJSONRPCNotification,
        to url: URL,
        sessionID: String?
    ) async throws {
        let request = try makeRequest(url: url, body: encoder.encode(message), sessionID: sessionID)
        let (_, response) = try await dataLoader(request)
        try validateHTTP(response)
    }

    private func sendStdioJSONRPCRequest<Result: Decodable>(
        _ message: MCPJSONRPCRequest,
        session: StdioMCPProcessSession
    ) throws -> Result {
        try session.write(encoder.encode(message))
        let data = try session.readMessage()

        if let error = try? decoder.decode(MCPJSONRPCErrorEnvelope.self, from: data),
           let message = error.error?.message {
            throw ToolServerMCPDiscoveryError.server(message)
        }

        return try decoder.decode(MCPJSONRPCResultEnvelope<Result>.self, from: data).result
    }

    private func sendStdioJSONRPCNotification(
        _ message: MCPJSONRPCNotification,
        session: StdioMCPProcessSession
    ) throws {
        try session.write(encoder.encode(message))
    }

    private func makeRequest(url: URL, body: Data, sessionID: String?) throws -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json, text/event-stream", forHTTPHeaderField: "Accept")
        request.setValue("2025-06-18", forHTTPHeaderField: "Mcp-Protocol-Version")
        if let sessionID {
            request.setValue(sessionID, forHTTPHeaderField: "Mcp-Session-Id")
        }
        request.httpBody = body
        return request
    }

    private func validateHTTP(_ response: URLResponse) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ToolServerMCPDiscoveryError.server("Missing HTTP response.")
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            throw ToolServerMCPDiscoveryError.server("HTTP \(httpResponse.statusCode)")
        }
    }

    private static func defaultDataLoader(_ request: URLRequest) async throws -> (Data, URLResponse) {
        try await URLSession.shared.data(for: request)
    }
}

private enum ToolServerMCPDiscoveryError: LocalizedError {
    case server(String)

    var errorDescription: String? {
        switch self {
        case .server(let message):
            return message
        }
    }
}

private final class StdioMCPProcessSession {
    private let process: Process
    private let input: Pipe
    private let outputReader: StdioLineReader

    init(server: AppToolServer) throws {
        guard let command = server.command?.trimmingCharacters(in: .whitespacesAndNewlines),
              !command.isEmpty else {
            throw ToolServerMCPDiscoveryError.server("Missing command.")
        }

        process = Process()
        input = Pipe()
        let output = Pipe()
        let error = Pipe()

        if command.contains("/") {
            process.executableURL = URL(fileURLWithPath: command)
            process.arguments = server.arguments
        } else {
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = [command] + server.arguments
        }
        process.standardInput = input
        process.standardOutput = output
        process.standardError = error
        process.environment = ProcessInfo.processInfo.environment.merging(server.environment) { _, new in
            new
        }

        outputReader = StdioLineReader(handle: output.fileHandleForReading)
        do {
            try process.run()
        } catch {
            outputReader.close()
            throw ToolServerMCPDiscoveryError.server(error.localizedDescription)
        }
    }

    func write(_ data: Data) throws {
        var message = data
        message.append(0x0A)
        input.fileHandleForWriting.write(message)
    }

    func readMessage() throws -> Data {
        try outputReader.readLine(timeoutSeconds: 5)
    }

    func close() {
        outputReader.close()
        try? input.fileHandleForWriting.close()
        if process.isRunning {
            process.terminate()
            process.waitUntilExit()
        }
    }
}

private final class StdioLineReader {
    private let handle: FileHandle
    private let lock = NSLock()
    private let semaphore = DispatchSemaphore(value: 0)
    private var buffer = Data()
    private var isClosed = false

    init(handle: FileHandle) {
        self.handle = handle
        handle.readabilityHandler = { [weak self] readableHandle in
            let data = readableHandle.availableData
            guard let self else {
                return
            }
            self.lock.lock()
            if data.isEmpty {
                self.isClosed = true
            } else {
                self.buffer.append(data)
            }
            self.lock.unlock()
            self.semaphore.signal()
        }
    }

    func readLine(timeoutSeconds: TimeInterval) throws -> Data {
        while true {
            lock.lock()
            if let newlineIndex = buffer.firstIndex(of: 0x0A) {
                let line = buffer[..<newlineIndex]
                buffer.removeSubrange(...newlineIndex)
                lock.unlock()
                return Data(line).trimmingTrailingCarriageReturn()
            }
            let closed = isClosed
            lock.unlock()

            if closed {
                throw ToolServerMCPDiscoveryError.server("Stdio server closed stdout.")
            }

            let deadline = DispatchTime.now() + timeoutSeconds
            if semaphore.wait(timeout: deadline) == .timedOut {
                throw ToolServerMCPDiscoveryError.server("Timed out waiting for stdio response.")
            }
        }
    }

    func close() {
        handle.readabilityHandler = nil
        try? handle.close()
    }
}

private extension Data {
    func trimmingTrailingCarriageReturn() -> Data {
        guard last == 0x0D else {
            return self
        }
        return dropLast()
    }
}

private struct MCPJSONRPCRequest: Encodable {
    var jsonrpc = "2.0"
    var id: Int
    var method: String
    var params: JSONValue?
}

private struct MCPJSONRPCNotification: Encodable {
    var jsonrpc = "2.0"
    var method: String
    var params: JSONValue?
}

private struct MCPJSONRPCResultEnvelope<Result: Decodable>: Decodable {
    var result: Result
}

private struct MCPJSONRPCErrorEnvelope: Decodable {
    var error: MCPJSONRPCError?
}

private struct MCPJSONRPCError: Decodable {
    var message: String
}

private struct MCPInitializeResponse: Decodable {
    var sessionID: String?

    enum CodingKeys: CodingKey {}

    init(from decoder: Decoder) throws {
        sessionID = nil
    }
}

private struct MCPToolsListResponse: Decodable {
    var tools: [AppToolServerTool]
}

private struct MCPToolCallResponse: Codable {
    var content: [JSONValue]
    var structuredContent: JSONValue?
    var isError: Bool?
}
