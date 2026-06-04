import Foundation

enum CodeExecutionLanguage: String, CaseIterable, Codable, Identifiable, Equatable, Hashable, Sendable {
    case shell
    case python

    var id: String { rawValue }

    var label: String {
        switch self {
        case .shell:
            return "Shell"
        case .python:
            return "Python"
        }
    }

    var defaultCode: String {
        switch self {
        case .shell:
            return "pwd\nls"
        case .python:
            return "print('Hello from Open WebUI Native')"
        }
    }
}

enum CodeExecutionStatus: String, Codable, Equatable, Sendable {
    case succeeded
    case failed
    case timedOut
}

struct CodeExecutionRequest: Codable, Equatable, Sendable {
    var language: CodeExecutionLanguage
    var code: String
    var workingDirectoryPath: String?
    var timeoutSeconds: Double
    var maxCapturedOutputBytes: Int?

    init(
        language: CodeExecutionLanguage,
        code: String,
        workingDirectoryPath: String? = nil,
        timeoutSeconds: Double = 10,
        maxCapturedOutputBytes: Int? = nil
    ) {
        self.language = language
        self.code = code
        self.workingDirectoryPath = workingDirectoryPath
        self.timeoutSeconds = timeoutSeconds
        self.maxCapturedOutputBytes = maxCapturedOutputBytes
    }
}

struct CodeExecutionSettings: Codable, Equatable, Sendable {
    var allowedLanguages: [CodeExecutionLanguage]
    var allowedWorkingDirectoryRoots: [String]
    var allowedExecutableNames: [String]
    var deniedExecutableNames: [String]
    var maxTimeoutSeconds: Double
    var maxCapturedOutputBytes: Int

    enum CodingKeys: String, CodingKey {
        case allowedLanguages
        case allowedWorkingDirectoryRoots
        case allowedExecutableNames
        case deniedExecutableNames
        case maxTimeoutSeconds
        case maxCapturedOutputBytes
    }

    init(
        allowedLanguages: [CodeExecutionLanguage] = CodeExecutionLanguage.allCases,
        allowedWorkingDirectoryRoots: [String] = CodeExecutionSettings.defaultAllowedWorkingDirectoryRoots(),
        allowedExecutableNames: [String] = [],
        deniedExecutableNames: [String] = [],
        maxTimeoutSeconds: Double = 30,
        maxCapturedOutputBytes: Int = 1_048_576
    ) {
        self.allowedLanguages = allowedLanguages
        self.allowedWorkingDirectoryRoots = allowedWorkingDirectoryRoots
        self.allowedExecutableNames = allowedExecutableNames
        self.deniedExecutableNames = deniedExecutableNames
        self.maxTimeoutSeconds = maxTimeoutSeconds
        self.maxCapturedOutputBytes = maxCapturedOutputBytes
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        allowedLanguages = try container.decodeIfPresent([CodeExecutionLanguage].self, forKey: .allowedLanguages)
            ?? CodeExecutionLanguage.allCases
        allowedWorkingDirectoryRoots = try container.decodeIfPresent([String].self, forKey: .allowedWorkingDirectoryRoots)
            ?? CodeExecutionSettings.defaultAllowedWorkingDirectoryRoots()
        allowedExecutableNames = try container.decodeIfPresent([String].self, forKey: .allowedExecutableNames) ?? []
        deniedExecutableNames = try container.decodeIfPresent([String].self, forKey: .deniedExecutableNames) ?? []
        maxTimeoutSeconds = try container.decodeIfPresent(Double.self, forKey: .maxTimeoutSeconds) ?? 30
        maxCapturedOutputBytes = try container.decodeIfPresent(Int.self, forKey: .maxCapturedOutputBytes) ?? 1_048_576
    }

    static func defaultAllowedWorkingDirectoryRoots() -> [String] {
        [
            FileManager.default.homeDirectoryForCurrentUser.path,
            "/tmp",
            NSTemporaryDirectory()
        ].map(normalizedPath)
    }
}

enum CodeExecutionPolicyDecision: Equatable, Sendable {
    case allowed(timeoutSeconds: Double, workingDirectoryPath: String?, maxCapturedOutputBytes: Int)
    case blocked(reason: String)
}

struct CodeExecutionPolicy: Sendable {
    var settings: CodeExecutionSettings

    func evaluate(_ request: CodeExecutionRequest) -> CodeExecutionPolicyDecision {
        guard settings.allowedLanguages.contains(request.language) else {
            return .blocked(reason: "\(request.language.label) execution is disabled by policy.")
        }

        let workingDirectory = request.workingDirectoryPath
            .map(Self.normalizedPath)
            .flatMap { $0.isEmpty ? nil : $0 }

        if let workingDirectory,
           !isAllowedWorkingDirectory(workingDirectory) {
            return .blocked(reason: "Working directory is outside the allowed code execution roots.")
        }

        if let blockedExecutableReason = blockedExecutableReason(for: request) {
            return .blocked(reason: blockedExecutableReason)
        }

        let timeout = min(max(request.timeoutSeconds, 0.1), max(settings.maxTimeoutSeconds, 0.1))
        let maxCapturedOutputBytes = max(settings.maxCapturedOutputBytes, 1)
        return .allowed(
            timeoutSeconds: timeout,
            workingDirectoryPath: workingDirectory,
            maxCapturedOutputBytes: maxCapturedOutputBytes
        )
    }

    private func isAllowedWorkingDirectory(_ workingDirectory: String) -> Bool {
        let allowedRoots = settings.allowedWorkingDirectoryRoots
            .map(Self.normalizedPath)
            .filter { !$0.isEmpty }
        guard !allowedRoots.isEmpty else {
            return false
        }

        return allowedRoots.contains { root in
            workingDirectory == root || workingDirectory.hasPrefix(root.hasSuffix("/") ? root : "\(root)/")
        }
    }

    private static func normalizedPath(_ path: String) -> String {
        CodeExecutionSettings.normalizedPath(path)
    }

    private func blockedExecutableReason(for request: CodeExecutionRequest) -> String? {
        let executableNames = Self.executableNames(for: request)
        guard !executableNames.isEmpty else {
            return nil
        }

        let deniedExecutables = Set(settings.deniedExecutableNames.compactMap(Self.normalizedExecutableName))
        for executableName in executableNames {
            if deniedExecutables.contains(executableName) {
                return "Executable '\(executableName)' is blocked by code execution policy."
            }
        }

        let allowedExecutables = Set(settings.allowedExecutableNames.compactMap(Self.normalizedExecutableName))
        guard !allowedExecutables.isEmpty else {
            return nil
        }

        for executableName in executableNames where !allowedExecutables.contains(executableName) {
            return "Executable '\(executableName)' is not in the allowed code execution executables."
        }

        return nil
    }

    private static func executableNames(for request: CodeExecutionRequest) -> [String] {
        switch request.language {
        case .shell:
            return shellExecutableNames(in: request.code)
        case .python:
            return ["python3"]
        }
    }

    private static func shellExecutableNames(in code: String) -> [String] {
        shellCommandSegments(in: code).compactMap { segment in
            firstExecutableName(inShellSegment: segment)
        }
    }

    private static func shellCommandSegments(in code: String) -> [String] {
        var segments: [String] = []
        var current = ""
        var quote: Character?
        var isEscaped = false

        for character in code {
            if isEscaped {
                current.append(character)
                isEscaped = false
                continue
            }

            if character == "\\" {
                current.append(character)
                isEscaped = true
                continue
            }

            if let activeQuote = quote {
                current.append(character)
                if character == activeQuote {
                    quote = nil
                }
                continue
            }

            if character == "'" || character == "\"" {
                quote = character
                current.append(character)
                continue
            }

            if character == "\n" || character == ";" || character == "|" || character == "&" {
                let segment = current.trimmingCharacters(in: .whitespacesAndNewlines)
                if !segment.isEmpty {
                    segments.append(segment)
                }
                current = ""
                continue
            }

            current.append(character)
        }

        let segment = current.trimmingCharacters(in: .whitespacesAndNewlines)
        if !segment.isEmpty {
            segments.append(segment)
        }
        return segments
    }

    private static func firstExecutableName(inShellSegment segment: String) -> String? {
        let tokens = shellTokens(in: segment)
        var index = 0
        while index < tokens.count {
            let token = tokens[index]
            if token.hasPrefix("#") {
                return nil
            }
            if token.contains("="), !token.hasPrefix("="), !token.hasSuffix("="), token.first != "-" {
                index += 1
                continue
            }
            if token == "command" || token == "exec" || token == "env" {
                index += 1
                continue
            }
            return normalizedExecutableName(token)
        }
        return nil
    }

    private static func shellTokens(in segment: String) -> [String] {
        var tokens: [String] = []
        var current = ""
        var quote: Character?
        var isEscaped = false

        for character in segment {
            if isEscaped {
                current.append(character)
                isEscaped = false
                continue
            }

            if character == "\\" {
                isEscaped = true
                continue
            }

            if let activeQuote = quote {
                if character == activeQuote {
                    quote = nil
                } else {
                    current.append(character)
                }
                continue
            }

            if character == "'" || character == "\"" {
                quote = character
                continue
            }

            if character.isWhitespace {
                if !current.isEmpty {
                    tokens.append(current)
                    current = ""
                }
                continue
            }

            current.append(character)
        }

        if !current.isEmpty {
            tokens.append(current)
        }
        return tokens
    }

    private static func normalizedExecutableName(_ name: String) -> String? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }
        return URL(fileURLWithPath: trimmed).lastPathComponent
    }
}

struct AppCodeExecutionRun: Identifiable, Codable, Equatable, Sendable {
    var id: UUID
    var language: CodeExecutionLanguage
    var code: String
    var workingDirectoryPath: String?
    var stdout: String
    var stderr: String
    var status: CodeExecutionStatus
    var exitCode: Int32?
    var startedAt: Date
    var completedAt: Date?

    init(
        id: UUID = UUID(),
        language: CodeExecutionLanguage,
        code: String,
        workingDirectoryPath: String? = nil,
        stdout: String,
        stderr: String = "",
        status: CodeExecutionStatus,
        exitCode: Int32?,
        startedAt: Date = Date(),
        completedAt: Date? = nil
    ) {
        self.id = id
        self.language = language
        self.code = code
        self.workingDirectoryPath = workingDirectoryPath
        self.stdout = stdout
        self.stderr = stderr
        self.status = status
        self.exitCode = exitCode
        self.startedAt = startedAt
        self.completedAt = completedAt
    }

    var title: String {
        let firstLine = code
            .split(whereSeparator: \.isNewline)
            .first
            .map(String.init)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let title = firstLine?.isEmpty == false ? firstLine! : "\(language.label) Run"
        return title.count > 60 ? String(title.prefix(60)) : title
    }
}

private extension CodeExecutionSettings {
    static func normalizedPath(_ path: String) -> String {
        let expanded = (path.trimmingCharacters(in: .whitespacesAndNewlines) as NSString).expandingTildeInPath
        guard !expanded.isEmpty else {
            return ""
        }
        return URL(fileURLWithPath: expanded).standardizedFileURL.path
    }
}
