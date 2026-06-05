import Foundation

struct AppDataPaths: Equatable, Sendable {
    var appDataRootURL: URL
    var settingsURL: URL
    var chatStorageURL: URL
    var backupRootURL: URL

    var appDataRootPath: String {
        appDataRootURL.path
    }

    var settingsFilePath: String {
        settingsURL.path
    }

    var chatStoragePath: String {
        chatStorageURL.path
    }

    var backupPath: String {
        backupRootURL.path
    }
}

struct AppDiagnosticsSnapshot: Equatable, Sendable {
    var appVersion: String
    var appBuild: String
    var appDataRootPath: String
    var settingsFilePath: String
    var chatStoragePath: String
    var backupPath: String
    var activeProviderName: String
    var activeProviderKind: String
    var activeProviderBaseURL: String
    var providerHealthStatus: String
    var modelCount: Int
    var selectedModelIDs: [String]
    var selectedEmbeddingModelID: String?
    var chatCount: Int
    var selectedThreadID: UUID?
    var selectedThreadTitle: String?
    var selectedThreadMessageCount: Int
    var activeStreamingBranchCount: Int
    var currentModelSelectionSummary: String
    var lastProviderErrorSummary: String?
    var localExecutionEnabled: Bool
    var localExecutionSandboxRootPath: String
    var latestAutomaticBackupTimestamp: Date?
    var recentErrorSummary: String?

    var searchableText: String {
        [
            appVersion,
            appBuild,
            appDataRootPath,
            settingsFilePath,
            chatStoragePath,
            backupPath,
            activeProviderName,
            activeProviderKind,
            activeProviderBaseURL,
            providerHealthStatus,
            selectedModelIDs.joined(separator: " "),
            selectedEmbeddingModelID ?? "",
            selectedThreadID?.uuidString ?? "",
            selectedThreadTitle ?? "",
            currentModelSelectionSummary,
            lastProviderErrorSummary ?? "",
            localExecutionSandboxRootPath,
            recentErrorSummary ?? ""
        ]
        .joined(separator: " ")
    }

    static func make(
        settings: AppSettings,
        paths: AppDataPaths,
        providerStatus: ProviderStatus,
        models: [ProviderModel],
        threads: [ChatThread] = [],
        selectedThreadID: UUID? = nil,
        activeStreamingBranchCount: Int = 0,
        latestAutomaticBackupTimestamp: Date?,
        recentErrorSummary: String?,
        bundle: Bundle = .main
    ) -> AppDiagnosticsSnapshot {
        let selectedThread = selectedThreadID.flatMap { id in
            threads.first { $0.id == id }
        }
        let selectedModelIDs = settings.selectedModelIDs
        let modelSelectionSummary = selectedModelIDs.isEmpty
            ? "No model selected"
            : selectedModelIDs.joined(separator: ", ")

        return AppDiagnosticsSnapshot(
            appVersion: bundle.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unavailable",
            appBuild: bundle.infoDictionary?["CFBundleVersion"] as? String ?? "Unavailable",
            appDataRootPath: paths.appDataRootPath,
            settingsFilePath: paths.settingsFilePath,
            chatStoragePath: paths.chatStoragePath,
            backupPath: paths.backupPath,
            activeProviderName: settings.activeProvider.name,
            activeProviderKind: providerKindLabel(settings.activeProvider.kind),
            activeProviderBaseURL: settings.activeProvider.baseURL,
            providerHealthStatus: providerStatus.label,
            modelCount: models.count,
            selectedModelIDs: selectedModelIDs,
            selectedEmbeddingModelID: settings.embeddingModelID,
            chatCount: threads.count,
            selectedThreadID: selectedThread?.id,
            selectedThreadTitle: selectedThread?.title,
            selectedThreadMessageCount: selectedThread?.messages.count ?? 0,
            activeStreamingBranchCount: activeStreamingBranchCount,
            currentModelSelectionSummary: modelSelectionSummary,
            lastProviderErrorSummary: recentErrorSummary,
            localExecutionEnabled: settings.localExecution.isEnabled,
            localExecutionSandboxRootPath: settings.localExecution.sandboxRootPath,
            latestAutomaticBackupTimestamp: latestAutomaticBackupTimestamp,
            recentErrorSummary: recentErrorSummary
        )
    }

    private static func providerKindLabel(_ kind: ProviderKind) -> String {
        switch kind {
        case .ollama:
            return "Ollama"
        case .openAICompatible:
            return "OpenAI-compatible"
        case .localFunction:
            return "Local function"
        }
    }
}
