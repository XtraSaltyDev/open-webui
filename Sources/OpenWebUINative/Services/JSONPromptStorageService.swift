import Foundation

struct JSONPromptStorageService: Sendable {
    private let rootURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(rootURL: URL = JSONPromptStorageService.defaultRootURL()) {
        self.rootURL = rootURL
        self.encoder = JSONEncoder.openWebUIEncoder
        self.decoder = JSONDecoder.openWebUIDecoder
    }

    func loadPrompts() async throws -> [SavedPrompt] {
        try ensureDirectory()
        let files = try FileManager.default.contentsOfDirectory(
            at: rootURL,
            includingPropertiesForKeys: nil
        )
        .filter { $0.pathExtension == "json" }

        let prompts = try files.map { file in
            let data = try Data(contentsOf: file)
            return try decoder.decode(SavedPrompt.self, from: data)
        }

        return prompts.sorted { $0.updatedAt > $1.updatedAt }
    }

    func save(_ prompt: SavedPrompt) async throws {
        try ensureDirectory()
        let data = try encoder.encode(prompt)
        try data.write(to: fileURL(for: prompt.id), options: [.atomic])
    }

    func deletePrompt(id: UUID) async throws {
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
            .appendingPathComponent("Prompts", isDirectory: true)
    }
}
