import Foundation

struct JSONGeneratedImageStorageService: Sendable {
    private let rootURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(rootURL: URL = JSONGeneratedImageStorageService.defaultRootURL()) {
        self.rootURL = rootURL
        self.encoder = JSONEncoder.openWebUIEncoder
        self.decoder = JSONDecoder.openWebUIDecoder
    }

    func loadImages() async throws -> [AppGeneratedImage] {
        try ensureDirectory()
        let files = try FileManager.default.contentsOfDirectory(
            at: rootURL,
            includingPropertiesForKeys: nil
        )
        .filter { $0.pathExtension == "json" }

        let images = try files.map { file in
            let data = try Data(contentsOf: file)
            return try decoder.decode(AppGeneratedImage.self, from: data)
        }

        return images.sorted { $0.createdAt > $1.createdAt }
    }

    func save(_ image: AppGeneratedImage) async throws {
        try ensureDirectory()
        let data = try encoder.encode(image)
        try data.write(to: fileURL(for: image.id), options: [.atomic])
    }

    func replaceImages(_ images: [AppGeneratedImage]) async throws {
        try await deleteAllImages()
        for image in images {
            try await save(image)
        }
    }

    func deleteImage(id: UUID) async throws {
        let url = fileURL(for: id)
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }

    func deleteAllImages() async throws {
        try ensureDirectory()
        for image in try await loadImages() {
            try await deleteImage(id: image.id)
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
            .appendingPathComponent("GeneratedImages", isDirectory: true)
    }
}
