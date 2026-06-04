import Foundation

struct JSONFunctionStorageService: Sendable {
    private let rootURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(rootURL: URL = JSONFunctionStorageService.defaultRootURL()) {
        self.rootURL = rootURL
        self.encoder = JSONEncoder.openWebUIEncoder
        self.decoder = JSONDecoder.openWebUIDecoder
    }

    func loadFunctions() async throws -> [AppFunction] {
        try ensureDirectory()
        let files = try FileManager.default.contentsOfDirectory(
            at: rootURL,
            includingPropertiesForKeys: nil
        )
        .filter { $0.pathExtension == "json" }

        let functions = try files.map { file in
            let data = try Data(contentsOf: file)
            return try decoder.decode(AppFunction.self, from: data)
        }

        return functions.sorted { $0.updatedAt > $1.updatedAt }
    }

    func save(_ function: AppFunction) async throws {
        try ensureDirectory()
        let data = try encoder.encode(function)
        try data.write(to: fileURL(for: function.id), options: [.atomic])
    }

    func deleteFunction(id: String) async throws {
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
            .appendingPathComponent("Functions", isDirectory: true)
    }
}
