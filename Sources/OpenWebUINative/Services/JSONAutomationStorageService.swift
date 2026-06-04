import Foundation

struct JSONAutomationStorageService: Sendable {
    private let rootURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(rootURL: URL = JSONAutomationStorageService.defaultRootURL()) {
        self.rootURL = rootURL
        self.encoder = JSONEncoder.openWebUIEncoder
        self.decoder = JSONDecoder.openWebUIDecoder
    }

    func loadAutomations() async throws -> [AppAutomation] {
        try ensureDirectory()
        let files = try FileManager.default.contentsOfDirectory(
            at: rootURL,
            includingPropertiesForKeys: nil
        )
        .filter { $0.pathExtension == "json" }

        let automations = try files.map { file in
            let data = try Data(contentsOf: file)
            return try decoder.decode(AppAutomation.self, from: data)
        }

        return automations.sorted { $0.updatedAt > $1.updatedAt }
    }

    func save(_ automation: AppAutomation) async throws {
        try ensureDirectory()
        let data = try encoder.encode(automation)
        try data.write(to: fileURL(for: automation.id), options: [.atomic])
    }

    func deleteAutomation(id: String) async throws {
        let url = fileURL(for: id)
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }

    private func fileURL(for id: String) -> URL {
        rootURL.appendingPathComponent("\(fileName(for: id)).json")
    }

    private func fileName(for id: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        return id.addingPercentEncoding(withAllowedCharacters: allowed) ?? UUID().uuidString
    }

    private func ensureDirectory() throws {
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
    }

    private static func defaultRootURL() -> URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first ?? FileManager.default.temporaryDirectory
        return appSupport
            .appendingPathComponent("OpenWebUINative", isDirectory: true)
            .appendingPathComponent("Automations", isDirectory: true)
    }
}
