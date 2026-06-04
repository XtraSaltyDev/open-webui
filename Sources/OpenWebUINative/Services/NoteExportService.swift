import Foundation

struct NoteExportService: Sendable {
    func jsonData(for notes: [AppNote]) throws -> Data {
        let bundle = NoteExportBundle(
            exportedAt: Date(),
            notes: notes.map(NoteExportRecord.init(note:))
        )
        return try JSONEncoder.openWebUIEncoder.encode(bundle)
    }

    func openWebUIJSONData(for notes: [AppNote]) throws -> Data {
        try JSONEncoder.openWebUIEncoder.encode(notes.map(OpenWebUINoteExportRecord.init(note:)))
    }

    func notes(fromJSONData data: Data) throws -> [AppNote] {
        let decoder = JSONDecoder.openWebUIDecoder
        if let bundle = try? decoder.decode(NoteExportBundle.self, from: data) {
            return bundle.notes.compactMap(\.appNote)
        }
        if let records = try? decoder.decode([NoteExportRecord].self, from: data) {
            return records.compactMap(\.appNote)
        }
        return try decoder.decode([AppNote].self, from: data)
    }
}

private struct NoteExportBundle: Codable {
    var format: String = "open-webui-native-notes"
    var version: Int = 1
    var exportedAt: Date
    var notes: [NoteExportRecord]
}

private struct NoteExportRecord: Codable {
    var id: String?
    var userID: String?
    var title: String
    var content: String?
    var data: NoteExportData?
    var meta: [String: String]?
    var createdAt: Date?
    var updatedAt: Date?
    var createdAtUnix: Int64?
    var updatedAtUnix: Int64?

    enum CodingKeys: String, CodingKey {
        case id
        case userID = "user_id"
        case title
        case content
        case data
        case meta
        case createdAt
        case updatedAt
        case createdAtUnix = "created_at"
        case updatedAtUnix = "updated_at"
    }

    init(note: AppNote) {
        id = note.id.uuidString
        userID = nil
        title = note.title
        content = note.content
        data = NoteExportData(content: NoteExportContent(md: note.content, html: nil))
        meta = [:]
        createdAt = note.createdAt
        updatedAt = note.updatedAt
        createdAtUnix = nil
        updatedAtUnix = nil
    }

    var appNote: AppNote? {
        let resolvedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedContent = (data?.content?.md ?? content ?? data?.content?.html ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !resolvedTitle.isEmpty, !resolvedContent.isEmpty else {
            return nil
        }

        return AppNote(
            id: id.flatMap(UUID.init(uuidString:)) ?? UUID(),
            title: resolvedTitle,
            content: resolvedContent,
            createdAt: createdAt ?? createdAtUnix.map(NoteExportRecord.date(fromEpochValue:)) ?? Date(),
            updatedAt: updatedAt ?? updatedAtUnix.map(NoteExportRecord.date(fromEpochValue:)) ?? Date()
        )
    }

    private static func date(fromEpochValue value: Int64) -> Date {
        if value > 100_000_000_000 {
            return Date(timeIntervalSince1970: TimeInterval(value) / 1_000_000_000)
        }
        return Date(timeIntervalSince1970: TimeInterval(value))
    }
}

private struct NoteExportData: Codable {
    var content: NoteExportContent?
}

private struct NoteExportContent: Codable {
    var md: String?
    var html: String?
}

private struct OpenWebUINoteExportRecord: Encodable {
    var id: String
    var userID: String
    var title: String
    var data: NoteExportData
    var meta: [String: String]
    var isPinned: Bool
    var accessGrants: [String]
    var createdAt: Int64
    var updatedAt: Int64

    enum CodingKeys: String, CodingKey {
        case id
        case userID = "user_id"
        case title
        case data
        case meta
        case isPinned = "is_pinned"
        case accessGrants = "access_grants"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    init(note: AppNote) {
        id = note.id.uuidString
        userID = "local-user"
        title = note.title
        data = NoteExportData(content: NoteExportContent(md: note.content, html: nil))
        meta = [:]
        isPinned = note.isPinned
        accessGrants = []
        createdAt = Int64(note.createdAt.timeIntervalSince1970 * 1_000_000_000)
        updatedAt = Int64(note.updatedAt.timeIntervalSince1970 * 1_000_000_000)
    }
}
