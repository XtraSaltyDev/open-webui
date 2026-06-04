import Foundation

struct AuditLogExportBundle: Codable, Equatable, Sendable {
    var format: String
    var version: Int
    var exportedAt: Date
    var events: [AppAuditEvent]

    init(
        format: String = "open-webui-native-audit-log",
        version: Int = 1,
        exportedAt: Date = Date(),
        events: [AppAuditEvent]
    ) {
        self.format = format
        self.version = version
        self.exportedAt = exportedAt
        self.events = events
    }
}

struct AuditLogExportService: Sendable {
    func jsonData(for events: [AppAuditEvent], exportedAt: Date = Date()) throws -> Data {
        try JSONEncoder.openWebUIEncoder.encode(
            AuditLogExportBundle(exportedAt: exportedAt, events: events)
        )
    }

    func importBundle(from data: Data) throws -> AuditLogExportBundle {
        try JSONDecoder.openWebUIDecoder.decode(AuditLogExportBundle.self, from: data)
    }
}
