import Foundation

struct FileExportService: Sendable {
    func jsonData(for files: [AppFile]) throws -> Data {
        let bundle = FileExportBundle(
            exportedAt: Date(),
            files: files.map(FileExportRecord.init(file:))
        )
        return try JSONEncoder.openWebUIEncoder.encode(bundle)
    }

    func openWebUIJSONData(for files: [AppFile], userID: String) throws -> Data {
        try JSONEncoder.openWebUIEncoder.encode(
            files.map { OpenWebUIFileExportRecord(file: $0, userID: userID) }
        )
    }

    func files(fromJSONData data: Data) throws -> [AppFile] {
        let decoder = JSONDecoder.openWebUIDecoder
        if let bundle = try? decoder.decode(FileExportBundle.self, from: data) {
            return bundle.files.compactMap(\.appFile)
        }
        if let response = try? decoder.decode(OpenWebUIFileListResponse.self, from: data) {
            return response.items.compactMap(\.appFile)
        }
        if let records = try? decoder.decode([FileExportRecord].self, from: data) {
            return records.compactMap(\.appFile)
        }
        return try decoder.decode([AppFile].self, from: data)
    }
}

private struct FileExportBundle: Codable {
    var format: String = "open-webui-native-files"
    var version: Int = 1
    var exportedAt: Date
    var files: [FileExportRecord]
}

private struct OpenWebUIFileListResponse: Decodable {
    var items: [FileExportRecord]
}

private struct FileExportRecord: Codable {
    var id: String?
    var userID: String?
    var hash: String?
    var fileName: String?
    var filename: String?
    var contentType: String?
    var byteCount: Int?
    var textContent: String?
    var originalData: Data?
    var data: [String: JSONValue]?
    var meta: [String: JSONValue]?
    var createdAt: Date?
    var updatedAt: Date?
    var createdAtUnix: Int64?
    var updatedAtUnix: Int64?

    enum CodingKeys: String, CodingKey {
        case id
        case userID = "user_id"
        case hash
        case fileName
        case filename
        case contentType
        case byteCount
        case textContent
        case originalData
        case data
        case meta
        case createdAt
        case updatedAt
        case createdAtUnix = "created_at"
        case updatedAtUnix = "updated_at"
    }

    init(file: AppFile) {
        id = file.id.uuidString
        userID = nil
        hash = nil
        fileName = file.fileName
        filename = file.fileName
        contentType = file.contentType
        byteCount = file.byteCount
        textContent = file.textContent
        originalData = file.originalData
        data = ["content": .string(file.textContent), "status": .string("completed")]
        meta = [
            "name": .string(file.fileName),
            "content_type": .string(file.contentType),
            "size": .number(Double(file.byteCount))
        ]
        createdAt = file.createdAt
        updatedAt = file.updatedAt
        createdAtUnix = nil
        updatedAtUnix = nil
    }

    var appFile: AppFile? {
        let resolvedName = (
            stringValue(for: "name", in: meta) ??
            fileName ??
            filename ??
            ""
        )
        .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !resolvedName.isEmpty else {
            return nil
        }

        let resolvedText = textContent ?? stringValue(for: "content", in: data) ?? ""
        let resolvedContentType = contentType ?? stringValue(for: "content_type", in: meta) ?? "text/plain"
        let resolvedByteCount = byteCount ?? intValue(for: "size", in: meta) ?? Data(resolvedText.utf8).count

        return AppFile(
            id: id.flatMap(UUID.init(uuidString:)) ?? UUID(),
            fileName: resolvedName,
            contentType: resolvedContentType,
            byteCount: resolvedByteCount,
            textContent: resolvedText,
            originalData: originalData,
            createdAt: createdAt ?? createdAtUnix.map(FileExportRecord.date(fromEpochValue:)) ?? Date(),
            updatedAt: updatedAt ?? updatedAtUnix.map(FileExportRecord.date(fromEpochValue:)) ?? Date()
        )
    }

    private func stringValue(for key: String, in object: [String: JSONValue]?) -> String? {
        guard let value = object?[key] else {
            return nil
        }
        switch value {
        case .string(let string):
            return string
        case .array(let values):
            return values.compactMap { value in
                if case .string(let string) = value {
                    return string
                }
                return nil
            }.first
        default:
            return nil
        }
    }

    private func intValue(for key: String, in object: [String: JSONValue]?) -> Int? {
        guard let value = object?[key] else {
            return nil
        }
        switch value {
        case .number(let number):
            return Int(number)
        case .string(let string):
            return Int(string)
        default:
            return nil
        }
    }

    private static func date(fromEpochValue value: Int64) -> Date {
        if value > 100_000_000_000 {
            return Date(timeIntervalSince1970: TimeInterval(value) / 1_000_000_000)
        }
        return Date(timeIntervalSince1970: TimeInterval(value))
    }
}

private struct OpenWebUIFileExportRecord: Encodable {
    var id: String
    var userID: String
    var hash: String?
    var filename: String
    var data: [String: JSONValue]
    var meta: [String: JSONValue]
    var createdAt: Int64
    var updatedAt: Int64

    enum CodingKeys: String, CodingKey {
        case id
        case userID = "user_id"
        case hash
        case filename
        case data
        case meta
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    init(file: AppFile, userID: String) {
        id = file.id.uuidString
        self.userID = userID
        hash = nil
        filename = file.fileName
        data = [
            "content": .string(file.textContent),
            "status": .string("completed")
        ]
        meta = [
            "name": .string(file.fileName),
            "content_type": .string(file.contentType),
            "size": .number(Double(file.byteCount))
        ]
        createdAt = Int64(file.createdAt.timeIntervalSince1970)
        updatedAt = Int64(file.updatedAt.timeIntervalSince1970)
    }
}
