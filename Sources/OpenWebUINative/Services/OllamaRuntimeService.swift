import AppKit
import Foundation

enum OllamaStartMethod: String, CaseIterable, Codable, Equatable, Sendable {
    case automatic
    case app
    case cli

    var label: String {
        switch self {
        case .automatic:
            return "Automatic"
        case .app:
            return "Ollama app"
        case .cli:
            return "CLI"
        }
    }
}

enum OllamaRuntimeStatus: Equatable, Sendable {
    case notConfigured
    case reachable(version: String)
    case unreachable(reason: String)
    case starting
    case startedByApp(version: String)
    case failedToStart(reason: String)

    var label: String {
        switch self {
        case .notConfigured:
            return "Ollama is not configured."
        case .reachable(let version):
            return "Ollama \(version) is reachable."
        case .unreachable(let reason):
            return reason
        case .starting:
            return "Starting Ollama..."
        case .startedByApp(let version):
            return "OpenWebUINative started Ollama \(version)."
        case .failedToStart(let reason):
            return reason
        }
    }

    var version: String? {
        switch self {
        case .reachable(let version), .startedByApp(let version):
            return version
        case .notConfigured, .unreachable, .starting, .failedToStart:
            return nil
        }
    }

    var isReachable: Bool {
        switch self {
        case .reachable, .startedByApp:
            return true
        case .notConfigured, .unreachable, .starting, .failedToStart:
            return false
        }
    }
}

protocol OllamaRuntimeManaging {
    var ownsRunningCLIProcess: Bool { get async }

    func status(baseURL: String) async -> OllamaRuntimeStatus
    func start(baseURL: String, preferredMethod: OllamaStartMethod) async -> OllamaRuntimeStatus
    func stopOwnedCLIProcess() async
}

protocol OllamaRuntimeProcessHandling: AnyObject {
    var isRunning: Bool { get }

    func terminate()
}

actor OllamaRuntimeService: OllamaRuntimeManaging {
    typealias DataLoader = (URLRequest) async throws -> (Data, URLResponse)
    typealias FileExists = (String) -> Bool
    typealias ApplicationOpener = (URL) -> Bool
    typealias ProcessLauncher = (String, [String]) throws -> any OllamaRuntimeProcessHandling
    typealias Sleeper = (UInt64) async throws -> Void

    static let likelyLocalBaseURLs = [
        "http://localhost:11434",
        "http://127.0.0.1:11434"
    ]

    private let dataLoader: DataLoader
    private let fileExists: FileExists
    private let openApplication: ApplicationOpener
    private let launchProcess: ProcessLauncher
    private let sleep: Sleeper
    private var ownedProcess: (any OllamaRuntimeProcessHandling)?

    init(
        dataLoader: @escaping DataLoader = OllamaRuntimeService.defaultDataLoader,
        fileExists: @escaping FileExists = { FileManager.default.fileExists(atPath: $0) },
        openApplication: @escaping ApplicationOpener = { NSWorkspace.shared.open($0) },
        launchProcess: @escaping ProcessLauncher = OllamaRuntimeService.defaultProcessLauncher,
        sleep: @escaping Sleeper = { try await Task.sleep(nanoseconds: $0) }
    ) {
        self.dataLoader = dataLoader
        self.fileExists = fileExists
        self.openApplication = openApplication
        self.launchProcess = launchProcess
        self.sleep = sleep
    }

    var ownsRunningCLIProcess: Bool {
        ownedProcess?.isRunning == true
    }

    func status(baseURL: String) async -> OllamaRuntimeStatus {
        let trimmedBaseURL = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmedBaseURL), url.scheme != nil else {
            return .notConfigured
        }

        do {
            var request = URLRequest(url: url.appending(path: "/api/version"))
            request.httpMethod = "GET"
            let (data, response) = try await dataLoader(request)
            guard let httpResponse = response as? HTTPURLResponse else {
                return .unreachable(reason: "Ollama returned an invalid health response at \(trimmedBaseURL).")
            }
            guard (200..<300).contains(httpResponse.statusCode) else {
                return .unreachable(reason: "Ollama returned HTTP \(httpResponse.statusCode) from /api/version.")
            }
            let payload = try JSONDecoder().decode(OllamaRuntimeVersionResponse.self, from: data)
            return .reachable(version: payload.version)
        } catch let urlError as URLError where [.cannotConnectToHost, .cannotFindHost, .networkConnectionLost, .timedOut].contains(urlError.code) {
            return .unreachable(reason: "Ollama is not reachable at \(trimmedBaseURL).")
        } catch {
            return .unreachable(reason: "Ollama health check failed at \(trimmedBaseURL): \(error.localizedDescription)")
        }
    }

    func start(baseURL: String, preferredMethod: OllamaStartMethod) async -> OllamaRuntimeStatus {
        let currentStatus = await status(baseURL: baseURL)
        if case .reachable = currentStatus {
            return currentStatus
        }

        let methods: [OllamaStartMethod]
        switch preferredMethod {
        case .automatic:
            methods = [.app, .cli]
        case .app:
            methods = [.app]
        case .cli:
            methods = [.cli]
        }

        for method in methods {
            switch method {
            case .app:
                guard let appURL = installedAppURL() else {
                    continue
                }
                guard openApplication(appURL) else {
                    continue
                }
                return await waitForReachability(baseURL: baseURL)
            case .cli:
                guard let cliPath = trustedCLIPath() else {
                    continue
                }
                do {
                    ownedProcess = try launchProcess(cliPath, ["serve"])
                    let status = await waitForReachability(baseURL: baseURL)
                    if status.isReachable {
                        return status
                    }
                    ownedProcess?.terminate()
                    ownedProcess = nil
                    return status
                } catch {
                    return .failedToStart(reason: "Could not start Ollama CLI: \(error.localizedDescription)")
                }
            case .automatic:
                continue
            }
        }

        return .failedToStart(reason: "Ollama app or trusted CLI was not found. Install Ollama, then retry.")
    }

    func stopOwnedCLIProcess() async {
        guard let ownedProcess, ownedProcess.isRunning else {
            self.ownedProcess = nil
            return
        }
        ownedProcess.terminate()
        self.ownedProcess = nil
    }

    private func waitForReachability(baseURL: String) async -> OllamaRuntimeStatus {
        for attempt in 0..<8 {
            let status = await status(baseURL: baseURL)
            if case .reachable(let version) = status {
                return .startedByApp(version: version)
            }
            if attempt < 7 {
                try? await sleep(250_000_000)
            }
        }
        return .failedToStart(reason: "Ollama did not become reachable at \(baseURL) after starting.")
    }

    private func installedAppURL() -> URL? {
        for path in Self.appSearchPaths {
            if fileExists(path) {
                return URL(fileURLWithPath: path, isDirectory: true)
            }
        }
        return nil
    }

    private func trustedCLIPath() -> String? {
        Self.trustedCLIPaths.first { fileExists($0) }
    }

    private static let appSearchPaths = [
        "/Applications/Ollama.app",
        NSString(string: "~/Applications/Ollama.app").expandingTildeInPath
    ]

    private static let trustedCLIPaths = [
        "/opt/homebrew/bin/ollama",
        "/usr/local/bin/ollama",
        "/usr/bin/ollama"
    ]

    private static let defaultDataLoader: DataLoader = { request in
        try await URLSession.shared.data(for: request)
    }

    private static let defaultProcessLauncher: ProcessLauncher = { executablePath, arguments in
        let process = Process()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        stdoutPipe.fileHandleForReading.readabilityHandler = { _ in }
        stderrPipe.fileHandleForReading.readabilityHandler = { _ in }
        try process.run()
        return OllamaRuntimeProcess(process: process, stdoutPipe: stdoutPipe, stderrPipe: stderrPipe)
    }
}

private struct OllamaRuntimeVersionResponse: Decodable {
    var version: String
}

private final class OllamaRuntimeProcess: OllamaRuntimeProcessHandling {
    private let process: Process
    private let stdoutPipe: Pipe
    private let stderrPipe: Pipe

    init(process: Process, stdoutPipe: Pipe, stderrPipe: Pipe) {
        self.process = process
        self.stdoutPipe = stdoutPipe
        self.stderrPipe = stderrPipe
    }

    var isRunning: Bool {
        process.isRunning
    }

    func terminate() {
        stdoutPipe.fileHandleForReading.readabilityHandler = nil
        stderrPipe.fileHandleForReading.readabilityHandler = nil
        guard process.isRunning else {
            return
        }
        process.terminate()
    }
}
