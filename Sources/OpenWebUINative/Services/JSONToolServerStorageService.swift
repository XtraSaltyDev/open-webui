import Foundation

struct JSONToolServerStorageService: Sendable {
    private let rootURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(rootURL: URL = JSONToolServerStorageService.defaultRootURL()) {
        self.rootURL = rootURL
        self.encoder = JSONEncoder.openWebUIEncoder
        self.decoder = JSONDecoder.openWebUIDecoder
    }

    func loadServers() async throws -> [AppToolServer] {
        try ensureDirectory()
        let files = try FileManager.default.contentsOfDirectory(
            at: rootURL,
            includingPropertiesForKeys: nil
        )
        .filter { $0.pathExtension == "json" }

        let servers = try files.map { file in
            let data = try Data(contentsOf: file)
            return try decoder.decode(AppToolServer.self, from: data)
        }

        return servers.sorted { $0.updatedAt > $1.updatedAt }
    }

    func save(_ server: AppToolServer) async throws {
        try ensureDirectory()
        let data = try encoder.encode(server)
        try data.write(to: fileURL(for: server.id), options: [.atomic])
    }

    func deleteServer(id: String) async throws {
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
            .appendingPathComponent("ToolServers", isDirectory: true)
    }
}
