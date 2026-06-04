import Foundation

struct JSONFolderStorageService: Sendable {
    private let rootURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(rootURL: URL = JSONFolderStorageService.defaultRootURL()) {
        self.rootURL = rootURL
        self.encoder = JSONEncoder.openWebUIEncoder
        self.decoder = JSONDecoder.openWebUIDecoder
    }

    func loadFolders() async throws -> [ChatFolder] {
        try ensureDirectory()
        let files = try FileManager.default.contentsOfDirectory(
            at: rootURL,
            includingPropertiesForKeys: nil
        )
        .filter { $0.pathExtension == "json" }

        let folders = try files.map { file in
            let data = try Data(contentsOf: file)
            return try decoder.decode(ChatFolder.self, from: data)
        }

        return folders.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    func save(_ folder: ChatFolder) async throws {
        try ensureDirectory()
        let data = try encoder.encode(folder)
        try data.write(to: fileURL(for: folder.id), options: [.atomic])
    }

    func deleteFolder(id: UUID) async throws {
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
            .appendingPathComponent("Folders", isDirectory: true)
    }
}
