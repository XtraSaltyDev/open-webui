import Foundation

struct JSONKnowledgeStorageService: Sendable {
    private let rootURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(rootURL: URL = JSONKnowledgeStorageService.defaultRootURL()) {
        self.rootURL = rootURL
        self.encoder = JSONEncoder.openWebUIEncoder
        self.decoder = JSONDecoder.openWebUIDecoder
    }

    func load() async throws -> KnowledgeSnapshot {
        try ensureDirectory()
        let url = snapshotURL()
        guard FileManager.default.fileExists(atPath: url.path) else {
            return KnowledgeSnapshot()
        }
        let data = try Data(contentsOf: url)
        return try decoder.decode(KnowledgeSnapshot.self, from: data)
    }

    func save(_ snapshot: KnowledgeSnapshot) async throws {
        try ensureDirectory()
        let data = try encoder.encode(snapshot)
        try data.write(to: snapshotURL(), options: [.atomic])
    }

    private func snapshotURL() -> URL {
        rootURL.appendingPathComponent("knowledge.json")
    }

    private func ensureDirectory() throws {
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
    }

    private static func defaultRootURL() -> URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first ?? FileManager.default.temporaryDirectory
        return appSupport
            .appendingPathComponent("OpenWebUINative", isDirectory: true)
            .appendingPathComponent("Knowledge", isDirectory: true)
    }
}
