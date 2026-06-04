import Foundation

struct JSONAuditLogStorageService: Sendable {
    private let rootURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(rootURL: URL = JSONAuditLogStorageService.defaultRootURL()) {
        self.rootURL = rootURL
        self.encoder = JSONEncoder.openWebUIEncoder
        self.decoder = JSONDecoder.openWebUIDecoder
    }

    func loadEvents() async throws -> [AppAuditEvent] {
        try ensureDirectory()
        let files = try FileManager.default.contentsOfDirectory(
            at: rootURL,
            includingPropertiesForKeys: nil
        )
        .filter { $0.pathExtension == "json" }

        let storedEvents = try files.map { file in
            let data = try Data(contentsOf: file)
            let event = try decoder.decode(AppAuditEvent.self, from: data)
            let modifiedAt = try file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
            return (event: event, modifiedAt: modifiedAt ?? .distantPast)
        }

        return storedEvents
            .sorted {
                if $0.event.createdAt != $1.event.createdAt {
                    return $0.event.createdAt > $1.event.createdAt
                }
                if $0.modifiedAt != $1.modifiedAt {
                    return $0.modifiedAt > $1.modifiedAt
                }
                return $0.event.id.uuidString > $1.event.id.uuidString
            }
            .map(\.event)
    }

    func save(_ event: AppAuditEvent) async throws {
        try ensureDirectory()
        let data = try encoder.encode(event)
        try data.write(to: fileURL(for: event.id), options: [.atomic])
    }

    func deleteEvent(id: UUID) async throws {
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
            .appendingPathComponent("AuditLog", isDirectory: true)
    }
}
