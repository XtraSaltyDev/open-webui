import Foundation

enum LocalExecutionPolicyDecision: Equatable, Sendable {
    case allowed(workingDirectoryPath: String)
    case blocked(reason: String)
}

struct LocalExecutionSettings: Codable, Equatable, Sendable {
    static let disabledMessage = "Local execution is disabled. Enable it in Settings > Local Execution after reviewing the safety warning."
    static let riskWarningRequiredMessage = "Accept the Local Execution safety warning in Settings > Local Execution before enabling local execution."
    static let outsideSandboxMessage = "Working directory is outside the Local Execution sandbox root."

    var isEnabled: Bool
    var hasAcceptedRiskWarning: Bool
    var sandboxRootPath: String

    enum CodingKeys: String, CodingKey {
        case isEnabled
        case hasAcceptedRiskWarning
        case sandboxRootPath
    }

    init(
        isEnabled: Bool = false,
        hasAcceptedRiskWarning: Bool = false,
        sandboxRootPath: String = LocalExecutionSettings.defaultSandboxRootPath()
    ) {
        self.isEnabled = isEnabled
        self.hasAcceptedRiskWarning = hasAcceptedRiskWarning
        self.sandboxRootPath = Self.normalizedSandboxRootPath(sandboxRootPath)
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            isEnabled: try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? false,
            hasAcceptedRiskWarning: try container.decodeIfPresent(Bool.self, forKey: .hasAcceptedRiskWarning) ?? false,
            sandboxRootPath: try container.decodeIfPresent(String.self, forKey: .sandboxRootPath)
                ?? Self.defaultSandboxRootPath()
        )
    }

    static func defaultSandboxRootPath() -> String {
        normalizedPath("~/OpenWebUINativeSandbox")
    }

    func normalized() -> LocalExecutionSettings {
        LocalExecutionSettings(
            isEnabled: isEnabled,
            hasAcceptedRiskWarning: hasAcceptedRiskWarning,
            sandboxRootPath: sandboxRootPath
        )
    }

    func evaluate(workingDirectoryPath: String?) -> LocalExecutionPolicyDecision {
        guard isEnabled else {
            return .blocked(reason: Self.disabledMessage)
        }

        guard hasAcceptedRiskWarning else {
            return .blocked(reason: Self.riskWarningRequiredMessage)
        }

        let sandboxRoot = Self.normalizedSandboxRootPath(sandboxRootPath)
        let workingDirectory = workingDirectoryPath
            .map(Self.normalizedPath)
            .flatMap { $0.isEmpty ? nil : $0 }
            ?? sandboxRoot

        guard Self.path(workingDirectory, isInsideOrEqualTo: sandboxRoot) else {
            return .blocked(reason: Self.outsideSandboxMessage)
        }

        return .allowed(workingDirectoryPath: workingDirectory)
    }

    func ensureSandboxDirectoryExists(fileManager: FileManager = .default) throws {
        let sandboxURL = URL(fileURLWithPath: Self.normalizedSandboxRootPath(sandboxRootPath), isDirectory: true)
        try fileManager.createDirectory(at: sandboxURL, withIntermediateDirectories: true)
    }

    static func normalizedSandboxRootPath(_ path: String) -> String {
        let normalized = normalizedPath(path)
        return normalized.isEmpty ? defaultSandboxRootPath() : normalized
    }

    static func normalizedPath(_ path: String) -> String {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return ""
        }
        let expanded = (trimmed as NSString).expandingTildeInPath
        return URL(fileURLWithPath: expanded).standardizedFileURL.path
    }

    static func path(_ path: String, isInsideOrEqualTo root: String) -> Bool {
        let normalizedPath = normalizedPath(path)
        let normalizedRoot = normalizedSandboxRootPath(root)
        guard !normalizedPath.isEmpty, !normalizedRoot.isEmpty else {
            return false
        }
        return normalizedPath == normalizedRoot
            || normalizedPath.hasPrefix(normalizedRoot.hasSuffix("/") ? normalizedRoot : "\(normalizedRoot)/")
    }
}
