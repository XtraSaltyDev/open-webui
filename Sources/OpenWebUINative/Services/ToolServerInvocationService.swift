import Foundation

protocol ToolServerInvoking: Sendable {
    func invoke(_ request: ToolServerInvocationRequest) async -> AppToolServerRun
}

struct ToolServerInvocationService: ToolServerInvoking {
    typealias DataLoader = @Sendable (URLRequest) async throws -> (Data, URLResponse)

    private let dataLoader: DataLoader
    private let stdioTimeoutSeconds: TimeInterval

    init(
        dataLoader: @escaping DataLoader = { request in
        try await ToolServerInvocationService.defaultDataLoader(request)
        },
        stdioTimeoutSeconds: TimeInterval = 30
    ) {
        self.dataLoader = dataLoader
        self.stdioTimeoutSeconds = stdioTimeoutSeconds
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
        let worker = Task(priority: .userInitiated) {
            Self.runStdioProcess(
                request,
                startedAt: startedAt,
                stdioTimeoutSeconds: stdioTimeoutSeconds
            )
        }
        return await withTaskCancellationHandler(operation: {
            await worker.value
        }, onCancel: {
            worker.cancel()
        })
    }

    private static func runStdioProcess(
        _ request: ToolServerInvocationRequest,
        startedAt: Date,
        stdioTimeoutSeconds: TimeInterval
    ) -> AppToolServerRun {
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

        let executablePath: String
        let arguments: [String]
        if command.contains("/") {
            executablePath = command
            arguments = request.server.arguments
        } else {
            executablePath = "/usr/bin/env"
            arguments = [command] + request.server.arguments
        }

        let timeoutSeconds = max(stdioTimeoutSeconds, 0.1)
        let result = BoundedProcessRunner().run(
            executablePath: executablePath,
            arguments: arguments,
            workingDirectoryPath: request.workingDirectoryPath,
            environment: request.server.environment,
            stdinData: request.requestBody.data(using: .utf8),
            timeoutSeconds: timeoutSeconds,
            maxCapturedOutputBytes: request.maxCapturedOutputBytes ?? CodeExecutionSettings().maxCapturedOutputBytes,
            shouldCancel: { Task.isCancelled }
        )

        if result.timedOut || result.wasCancelled {
            return failedRun(
                request,
                statusCode: nil,
                responseBody: result.stdout,
                errorMessage: result.timedOut
                    ? timeoutMessage(seconds: timeoutSeconds)
                    : "Invocation cancelled.",
                startedAt: startedAt
            )
        }

        let exitCode = result.exitCode.map(Int.init)
        let didSucceed = result.status == .succeeded
        return AppToolServerRun(
            serverID: request.server.id,
            serverName: request.server.name,
            serverKind: request.server.kind,
            requestBody: request.requestBody,
            responseBody: result.stdout,
            statusCode: exitCode,
            status: didSucceed ? .succeeded : .failed,
            errorMessage: didSucceed ? nil : Self.failureMessage(for: result.stderr, exitCode: exitCode ?? -1),
            startedAt: startedAt,
            completedAt: result.completedAt
        )
    }

    private static func timeoutMessage(seconds: TimeInterval) -> String {
        let rounded = seconds.rounded()
        if abs(seconds - rounded) < 0.000_001 {
            return "Timed out after \(Int(rounded)) seconds."
        }
        return String(format: "Timed out after %.1f seconds.", seconds)
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
