import Foundation

protocol ToolServerChecking: Sendable {
    func check(_ server: AppToolServer) async -> ToolServerCheckResult
}

struct ToolServerCheckService: ToolServerChecking {
    typealias CommandResolver = @Sendable (String) -> Bool
    typealias HTTPStatusLoader = @Sendable (URL) async throws -> Int

    private let commandResolver: CommandResolver
    private let httpStatusLoader: HTTPStatusLoader

    init(
        commandResolver: @escaping CommandResolver = { command in
            ToolServerCheckService.defaultCommandResolver(command)
        },
        httpStatusLoader: @escaping HTTPStatusLoader = { url in
            try await ToolServerCheckService.defaultHTTPStatusLoader(url)
        }
    ) {
        self.commandResolver = commandResolver
        self.httpStatusLoader = httpStatusLoader
    }

    func check(_ server: AppToolServer) async -> ToolServerCheckResult {
        switch server.kind {
        case .stdio:
            return checkStdio(server)
        case .http:
            return await checkHTTP(server)
        }
    }

    private func checkStdio(_ server: AppToolServer) -> ToolServerCheckResult {
        guard let command = server.command?.trimmingCharacters(in: .whitespacesAndNewlines),
              !command.isEmpty else {
            return ToolServerCheckResult(status: .unavailable("Missing command."))
        }

        if commandResolver(command) {
            return ToolServerCheckResult(status: .available("Command is available: \(command)"))
        }

        return ToolServerCheckResult(status: .unavailable("Command not found: \(command)"))
    }

    private func checkHTTP(_ server: AppToolServer) async -> ToolServerCheckResult {
        guard let baseURL = server.baseURL?.trimmingCharacters(in: .whitespacesAndNewlines),
              let url = URL(string: baseURL),
              let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              url.host != nil else {
            return ToolServerCheckResult(status: .unavailable("Invalid URL."))
        }

        do {
            let statusCode = try await httpStatusLoader(url)
            if (200..<400).contains(statusCode) {
                return ToolServerCheckResult(status: .available("HTTP \(statusCode)"))
            }
            return ToolServerCheckResult(status: .unavailable("HTTP \(statusCode)"))
        } catch {
            return ToolServerCheckResult(status: .unavailable(error.localizedDescription))
        }
    }

    private static func defaultCommandResolver(_ command: String) -> Bool {
        let fileManager = FileManager.default
        if command.hasPrefix("/") {
            return fileManager.isExecutableFile(atPath: command)
        }

        if command.contains("/") {
            return fileManager.isExecutableFile(atPath: command)
        }

        let pathValue = ProcessInfo.processInfo.environment["PATH"] ?? ""
        let searchPaths = pathValue
            .split(separator: ":")
            .map(String.init)
            + ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin"]

        for path in searchPaths {
            let candidate = URL(fileURLWithPath: path)
                .appendingPathComponent(command)
                .path
            if fileManager.isExecutableFile(atPath: candidate) {
                return true
            }
        }

        return false
    }

    private static func defaultHTTPStatusLoader(_ url: URL) async throws -> Int {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 5

        let (_, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            return -1
        }
        return httpResponse.statusCode
    }
}
