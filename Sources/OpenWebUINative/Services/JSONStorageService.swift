import Foundation

struct JSONStorageService: Sendable {
    private let rootURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(rootURL: URL = JSONStorageService.defaultRootURL()) {
        self.rootURL = rootURL
        self.encoder = JSONEncoder.openWebUIEncoder
        self.decoder = JSONDecoder.openWebUIDecoder
    }

    var rootDirectoryURL: URL {
        rootURL
    }

    func loadThreads() async throws -> [ChatThread] {
        try await loadThreadsWithRecovery().records
    }

    func loadThreadsWithRecovery() async throws -> JSONRecordLoadResult<ChatThread> {
        try ensureDirectory()
        let files = try FileManager.default.contentsOfDirectory(
            at: rootURL,
            includingPropertiesForKeys: nil
        )
        .filter { $0.pathExtension == "json" }

        var skippedCorruptRecordCount = 0
        let threads = files.compactMap { file -> ChatThread? in
            do {
                let data = try Data(contentsOf: file)
                return try decoder.decode(ChatThread.self, from: data)
            } catch {
                skippedCorruptRecordCount += 1
                quarantineCorruptRecord(at: file)
                return nil
            }
        }

        return JSONRecordLoadResult(
            records: threads.sorted { $0.updatedAt > $1.updatedAt },
            skippedCorruptRecordCount: skippedCorruptRecordCount
        )
    }

    func save(_ thread: ChatThread) async throws {
        try ensureDirectory()
        let data = try encoder.encode(thread)
        try data.write(to: fileURL(for: thread.id), options: [.atomic])
    }

    func deleteThread(id: UUID) async throws {
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

    private func quarantineCorruptRecord(at url: URL) {
        let quarantineURL = uniqueQuarantineURL(for: url)
        try? FileManager.default.moveItem(at: url, to: quarantineURL)
    }

    private func uniqueQuarantineURL(for url: URL) -> URL {
        let baseURL = url.appendingPathExtension("corrupt")
        guard FileManager.default.fileExists(atPath: baseURL.path) else {
            return baseURL
        }
        return url
            .deletingLastPathComponent()
            .appendingPathComponent("\(url.lastPathComponent).\(UUID().uuidString).corrupt")
    }

    private static func defaultRootURL() -> URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first ?? FileManager.default.temporaryDirectory
        return appSupport
            .appendingPathComponent("OpenWebUINative", isDirectory: true)
            .appendingPathComponent("Chats", isDirectory: true)
    }
}

struct JSONRecordLoadResult<Record: Sendable>: Sendable {
    var records: [Record]
    var skippedCorruptRecordCount: Int
}
