import Foundation

struct SettingsStore: Sendable {
    private let settingsURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(settingsURL: URL = SettingsStore.defaultSettingsURL()) {
        self.settingsURL = settingsURL
        self.encoder = JSONEncoder()
        self.decoder = JSONDecoder()
    }

    var settingsFileURL: URL {
        settingsURL
    }

    var appDataRootURL: URL {
        settingsURL.deletingLastPathComponent()
    }

    func load() async throws -> AppSettings {
        guard FileManager.default.fileExists(atPath: settingsURL.path) else {
            return try preparedForUse(AppSettings())
        }
        let data = try Data(contentsOf: settingsURL)
        return try preparedForUse(decoder.decode(AppSettings.self, from: data))
    }

    func save(_ settings: AppSettings) async throws {
        let directory = settingsURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try encoder.encode(settings)
        try data.write(to: settingsURL, options: [.atomic])
    }

    private static func defaultSettingsURL() -> URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first ?? FileManager.default.temporaryDirectory
        return appSupport
            .appendingPathComponent("OpenWebUINative", isDirectory: true)
            .appendingPathComponent("settings.json")
    }

    private func preparedForUse(_ settings: AppSettings) throws -> AppSettings {
        var preparedSettings = settings
        preparedSettings.localExecution = settings.localExecution.normalized()
        try preparedSettings.localExecution.ensureSandboxDirectoryExists()
        return preparedSettings
    }
}
