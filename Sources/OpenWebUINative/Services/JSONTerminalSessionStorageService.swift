import Foundation

struct JSONTerminalSessionStorageService: Sendable {
    private let rootURL: URL
    private let sessionsURL: URL
    private let commandsURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(rootURL: URL = JSONTerminalSessionStorageService.defaultRootURL()) {
        self.rootURL = rootURL
        self.sessionsURL = rootURL.appendingPathComponent("Sessions", isDirectory: true)
        self.commandsURL = rootURL.appendingPathComponent("Commands", isDirectory: true)
        self.encoder = JSONEncoder.openWebUIEncoder
        self.decoder = JSONDecoder.openWebUIDecoder
    }

    func loadSessions() async throws -> [AppTerminalSession] {
        try ensureDirectory(sessionsURL)
        let sessions = try jsonFiles(in: sessionsURL).map { file in
            let data = try Data(contentsOf: file)
            return try decoder.decode(AppTerminalSession.self, from: data)
        }
        return sessions.sorted { $0.updatedAt > $1.updatedAt }
    }

    func loadCommands() async throws -> [AppTerminalCommand] {
        try ensureDirectory(commandsURL)
        let commands = try jsonFiles(in: commandsURL).map { file in
            let data = try Data(contentsOf: file)
            return try decoder.decode(AppTerminalCommand.self, from: data)
        }
        return commands.sorted { $0.startedAt > $1.startedAt }
    }

    func saveSession(_ session: AppTerminalSession) async throws {
        try ensureDirectory(sessionsURL)
        let data = try encoder.encode(session)
        try data.write(to: sessionsURL.appendingPathComponent("\(session.id.uuidString).json"), options: [.atomic])
    }

    func saveCommand(_ command: AppTerminalCommand) async throws {
        try ensureDirectory(commandsURL)
        let data = try encoder.encode(command)
        try data.write(to: commandsURL.appendingPathComponent("\(command.id.uuidString).json"), options: [.atomic])
    }

    func deleteSession(id: UUID) async throws {
        let url = sessionsURL.appendingPathComponent("\(id.uuidString).json")
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
        for command in try await loadCommands() where command.sessionID == id {
            try await deleteCommand(id: command.id)
        }
    }

    func deleteCommand(id: UUID) async throws {
        let url = commandsURL.appendingPathComponent("\(id.uuidString).json")
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }

    private func jsonFiles(in url: URL) throws -> [URL] {
        try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }
    }

    private func ensureDirectory(_ url: URL) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    private static func defaultRootURL() -> URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first ?? FileManager.default.temporaryDirectory
        return appSupport
            .appendingPathComponent("OpenWebUINative", isDirectory: true)
            .appendingPathComponent("Terminal", isDirectory: true)
    }
}
