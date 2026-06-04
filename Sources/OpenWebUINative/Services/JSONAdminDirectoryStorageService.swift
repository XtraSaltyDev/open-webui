import Foundation

struct JSONAdminDirectoryStorageService: Sendable {
    private let snapshotURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(snapshotURL: URL = JSONAdminDirectoryStorageService.defaultSnapshotURL()) {
        self.snapshotURL = snapshotURL
        self.encoder = JSONEncoder.openWebUIEncoder
        self.decoder = JSONDecoder.openWebUIDecoder
    }

    func loadSnapshot() async throws -> AdminDirectorySnapshot {
        guard FileManager.default.fileExists(atPath: snapshotURL.path) else {
            return AdminDirectorySnapshot()
        }
        let data = try Data(contentsOf: snapshotURL)
        return try decoder.decode(AdminDirectorySnapshot.self, from: data)
    }

    func saveSnapshot(_ snapshot: AdminDirectorySnapshot) async throws {
        try FileManager.default.createDirectory(
            at: snapshotURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let data = try encoder.encode(snapshot)
        try data.write(to: snapshotURL, options: [.atomic])
    }

    private static func defaultSnapshotURL() -> URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first ?? FileManager.default.temporaryDirectory
        return appSupport
            .appendingPathComponent("OpenWebUINative", isDirectory: true)
            .appendingPathComponent("admin-directory.json")
    }
}
