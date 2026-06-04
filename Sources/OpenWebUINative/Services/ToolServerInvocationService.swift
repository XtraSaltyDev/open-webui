import Foundation

protocol ToolServerInvoking: Sendable {
    func invoke(_ request: ToolServerInvocationRequest) async -> AppToolServerRun
}

struct ToolServerInvocationService: ToolServerInvoking {
    typealias DataLoader = @Sendable (URLRequest) async throws -> (Data, URLResponse)

    private let dataLoader: DataLoader

    init(dataLoader: @escaping DataLoader = { request in
        try await ToolServerInvocationService.defaultDataLoader(request)
    }) {
        self.dataLoader = dataLoader
    }

    func invoke(_ request: ToolServerInvocationRequest) async -> AppToolServerRun {
        let startedAt = Date()
        switch request.server.kind {
        case .stdio:
            return await invokeStdio(request, startedAt: startedAt)
        case .http:
            return await invokeHTTP(request, startedAt: startedAt)
        }
    }

    private func invokeStdio(_ request: ToolServerInvocationRequest, startedAt: Date) async -> AppToolServerRun {
        await Task.detached(priority: .userInitiated) {
            Self.runStdioProcess(request, startedAt: startedAt)
        }.value
    }

    private static func runStdioProcess(_ request: ToolServerInvocationRequest, startedAt: Date) -> AppToolServerRun {
        guard let command = request.server.command?.trimmingCharacters(in: .whitespacesAndNewlines),
              !command.isEmpty else {
            return failedRun(
                request,
                statusCode: nil,
                responseBody: "",
                errorMessage: "Missing command.",
                startedAt: startedAt
            )
        }

        let process = Process()
        let input = Pipe()
        let output = Pipe()
        let error = Pipe()
        let outputCollector = PipeDataCollector(pipe: output)
        let errorCollector = PipeDataCollector(pipe: error)
        let termination = DispatchSemaphore(value: 0)

        if command.contains("/") {
            process.executableURL = URL(fileURLWithPath: command)
            process.arguments = request.server.arguments
        } else {
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = [command] + request.server.arguments
        }
        process.standardInput = input
        process.standardOutput = output
        process.standardError = error
        process.environment = ProcessInfo.processInfo.environment.merging(request.server.environment) { _, new in
            new
        }
        process.terminationHandler = { _ in
            termination.signal()
        }

        do {
            try process.run()
            if let body = request.requestBody.data(using: .utf8) {
                input.fileHandleForWriting.write(body)
            }
            try? input.fileHandleForWriting.close()

            if termination.wait(timeout: .now() + 30) == .timedOut {
                if process.isRunning {
                    process.terminate()
                    process.waitUntilExit()
                }
                let responseBody = outputCollector.collectedString()
                _ = errorCollector.collectedString()
                return failedRun(
                    request,
                    statusCode: nil,
                    responseBody: responseBody,
                    errorMessage: "Timed out after 30 seconds.",
                    startedAt: startedAt
                )
            }

            let responseBody = outputCollector.collectedString()
            let errorBody = errorCollector.collectedString()
            let exitCode = Int(process.terminationStatus)
            let didSucceed = process.terminationReason == .exit && exitCode == 0
            return AppToolServerRun(
                serverID: request.server.id,
                serverName: request.server.name,
                serverKind: request.server.kind,
                requestBody: request.requestBody,
                responseBody: responseBody,
                statusCode: exitCode,
                status: didSucceed ? .succeeded : .failed,
                errorMessage: didSucceed ? nil : Self.failureMessage(for: errorBody, exitCode: exitCode),
                startedAt: startedAt,
                completedAt: Date()
            )
        } catch {
            outputCollector.close()
            errorCollector.close()
            try? input.fileHandleForWriting.close()
            return failedRun(
                request,
                statusCode: nil,
                responseBody: "",
                errorMessage: error.localizedDescription,
                startedAt: startedAt
            )
        }
    }

    private static func failureMessage(for stderr: String, exitCode: Int) -> String {
        let trimmedError = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedError.isEmpty {
            return trimmedError
        }
        return "Process exited with code \(exitCode)."
    }

    private func invokeHTTP(_ request: ToolServerInvocationRequest, startedAt: Date) async -> AppToolServerRun {
        guard let baseURL = request.server.baseURL?.trimmingCharacters(in: .whitespacesAndNewlines),
              let url = URL(string: baseURL),
              let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              url.host != nil else {
            return Self.failedRun(
                request,
                statusCode: nil,
                responseBody: "",
                errorMessage: "Invalid URL.",
                startedAt: startedAt
            )
        }

        do {
            var urlRequest = URLRequest(url: url)
            urlRequest.httpMethod = "POST"
            urlRequest.timeoutInterval = 30
            urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
            urlRequest.httpBody = Data(request.requestBody.utf8)

            let (data, response) = try await dataLoader(urlRequest)
            let responseBody = String(data: data, encoding: .utf8) ?? ""
            let statusCode = (response as? HTTPURLResponse)?.statusCode
            let didSucceed = statusCode.map { (200..<300).contains($0) } ?? false

            return AppToolServerRun(
                serverID: request.server.id,
                serverName: request.server.name,
                serverKind: request.server.kind,
                requestBody: request.requestBody,
                responseBody: responseBody,
                statusCode: statusCode,
                status: didSucceed ? .succeeded : .failed,
                errorMessage: didSucceed ? nil : statusCode.map { "HTTP \($0)" } ?? "Missing HTTP response.",
                startedAt: startedAt,
                completedAt: Date()
            )
        } catch {
            return Self.failedRun(
                request,
                statusCode: nil,
                responseBody: "",
                errorMessage: error.localizedDescription,
                startedAt: startedAt
            )
        }
    }

    private static func failedRun(
        _ request: ToolServerInvocationRequest,
        statusCode: Int?,
        responseBody: String,
        errorMessage: String,
        startedAt: Date
    ) -> AppToolServerRun {
        AppToolServerRun(
            serverID: request.server.id,
            serverName: request.server.name,
            serverKind: request.server.kind,
            requestBody: request.requestBody,
            responseBody: responseBody,
            statusCode: statusCode,
            status: .failed,
            errorMessage: errorMessage,
            startedAt: startedAt,
            completedAt: Date()
        )
    }

    private static func defaultDataLoader(_ request: URLRequest) async throws -> (Data, URLResponse) {
        try await URLSession.shared.data(for: request)
    }
}

private final class PipeDataCollector {
    private let handle: FileHandle
    private let lock = NSLock()
    private var data = Data()

    init(pipe: Pipe) {
        handle = pipe.fileHandleForReading
        handle.readabilityHandler = { [weak self] readableHandle in
            let chunk = readableHandle.availableData
            guard let self, !chunk.isEmpty else {
                return
            }
            self.lock.lock()
            self.data.append(chunk)
            self.lock.unlock()
        }
    }

    func collectedString() -> String {
        close()
        lock.lock()
        let collected = data
        lock.unlock()
        return String(data: collected, encoding: .utf8) ?? ""
    }

    func close() {
        handle.readabilityHandler = nil
        try? handle.close()
    }
}
