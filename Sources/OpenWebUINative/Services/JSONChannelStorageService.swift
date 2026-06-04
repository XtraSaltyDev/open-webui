import Foundation

struct JSONChannelStorageService: Sendable {
    private let rootURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(rootURL: URL = JSONChannelStorageService.defaultRootURL()) {
        self.rootURL = rootURL
        self.encoder = JSONEncoder.openWebUIEncoder
        self.decoder = JSONDecoder.openWebUIDecoder
    }

    func loadChannels() async throws -> [AppChannel] {
        try ensureDirectory()
        let files = try FileManager.default.contentsOfDirectory(
            at: rootURL,
            includingPropertiesForKeys: nil
        )
        .filter { $0.pathExtension == "json" }

        let channels = try files.map { file in
            let data = try Data(contentsOf: file)
            return try decoder.decode(AppChannel.self, from: data)
        }

        return channels.sorted { $0.updatedAt > $1.updatedAt }
    }

    func save(_ channel: AppChannel) async throws {
        try ensureDirectory()
        let data = try encoder.encode(channel)
        try data.write(to: fileURL(for: channel.id), options: [.atomic])
    }

    func deleteChannel(id: UUID) async throws {
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
            .appendingPathComponent("Channels", isDirectory: true)
    }
}
