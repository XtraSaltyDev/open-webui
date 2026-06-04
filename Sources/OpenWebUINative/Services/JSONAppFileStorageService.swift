import Foundation

struct JSONAppFileStorageService: Sendable {
    private let rootURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(rootURL: URL = JSONAppFileStorageService.defaultRootURL()) {
        self.rootURL = rootURL
        self.encoder = JSONEncoder.openWebUIEncoder
        self.decoder = JSONDecoder.openWebUIDecoder
    }

    func loadFiles() async throws -> [AppFile] {
        try ensureDirectory()
        let files = try FileManager.default.contentsOfDirectory(
            at: rootURL,
            includingPropertiesForKeys: nil
        )
        .filter { $0.pathExtension == "json" }

        let appFiles = try files.map { file in
            let data = try Data(contentsOf: file)
            return try decoder.decode(AppFile.self, from: data)
        }

        return appFiles.sorted { $0.updatedAt > $1.updatedAt }
    }

    func save(_ file: AppFile) async throws {
        try ensureDirectory()
        let data = try encoder.encode(file)
        try data.write(to: fileURL(for: file.id), options: [.atomic])
    }

    func deleteFile(id: UUID) async throws {
        let url = fileURL(for: id)
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }

    func replaceFiles(_ files: [AppFile]) async throws {
        try ensureDirectory()
        let existingFiles = try FileManager.default.contentsOfDirectory(
            at: rootURL,
            includingPropertiesForKeys: nil
        )
        .filter { $0.pathExtension == "json" }

        for file in existingFiles {
            try FileManager.default.removeItem(at: file)
        }

        for file in files {
            try await save(file)
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
            .appendingPathComponent("Files", isDirectory: true)
    }
}
