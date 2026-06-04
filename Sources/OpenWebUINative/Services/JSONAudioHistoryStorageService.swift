import Foundation

struct JSONAudioHistoryStorageService: Sendable {
    private let rootURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(rootURL: URL = JSONAudioHistoryStorageService.defaultRootURL()) {
        self.rootURL = rootURL
        self.encoder = JSONEncoder.openWebUIEncoder
        self.decoder = JSONDecoder.openWebUIDecoder
    }

    func loadHistory() async throws -> [AppAudioHistoryItem] {
        try ensureDirectory()
        let files = try FileManager.default.contentsOfDirectory(
            at: rootURL,
            includingPropertiesForKeys: nil
        )
        .filter { $0.pathExtension == "json" }

        let items = try files.map { file in
            let data = try Data(contentsOf: file)
            return try decoder.decode(AppAudioHistoryItem.self, from: data)
        }

        return items.sorted { $0.createdAt > $1.createdAt }
    }

    func save(_ item: AppAudioHistoryItem) async throws {
        try ensureDirectory()
        let data = try encoder.encode(item)
        try data.write(to: fileURL(for: item.id), options: [.atomic])
    }

    func replaceHistory(_ items: [AppAudioHistoryItem]) async throws {
        try ensureDirectory()
        let files = try FileManager.default.contentsOfDirectory(
            at: rootURL,
            includingPropertiesForKeys: nil
        )
        .filter { $0.pathExtension == "json" }

        for file in files {
            try FileManager.default.removeItem(at: file)
        }

        for item in items {
            try await save(item)
        }
    }

    func deleteHistoryItem(id: UUID) async throws {
        let url = fileURL(for: id)
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }

    private func fileURL(for id: UUID) -> URL {
        rootURL.appendingPathComponent("\(id.uuidString).json")
    }

    private func ensureDirectory() throws {
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
    }

    private static func defaultRootURL() -> URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first ?? FileManager.default.temporaryDirectory
        return appSupport
            .appendingPathComponent("OpenWebUINative", isDirectory: true)
            .appendingPathComponent("AudioHistory", isDirectory: true)
    }
}
