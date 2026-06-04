import Foundation

struct FunctionExportService: Sendable {
    func jsonData(for functions: [AppFunction]) throws -> Data {
        let bundle = FunctionExportBundle(
            exportedAt: Date(),
            functions: functions.map(FunctionExportRecord.init(function:))
        )
        return try JSONEncoder.openWebUIEncoder.encode(bundle)
    }

    func openWebUIJSONData(for functions: [AppFunction], userID: String) throws -> Data {
        try JSONEncoder.openWebUIEncoder.encode(
            functions.map { OpenWebUIFunctionExportRecord(function: $0, userID: userID) }
        )
    }

    func functions(fromJSONData data: Data) throws -> [AppFunction] {
        let decoder = JSONDecoder.openWebUIDecoder
        if let bundle = try? decoder.decode(FunctionExportBundle.self, from: data) {
            return bundle.functions.compactMap(\.appFunction)
        }
        if let records = try? decoder.decode([FunctionExportRecord].self, from: data) {
            return records.compactMap(\.appFunction)
        }
        return try decoder.decode([AppFunction].self, from: data)
    }
}

private struct OpenWebUIFunctionExportRecord: Encodable {
    var id: String
    var userID: String
    var name: String
    var type: String
    var content: String
    var meta: FunctionExportMeta
    var valves: JSONValue?
    var isActive: Bool
    var isGlobal: Bool
    var createdAt: Int
    var updatedAt: Int

    enum CodingKeys: String, CodingKey {
        case id
        case userID = "user_id"
        case name
        case type
        case content
        case meta
        case valves
        case isActive = "is_active"
        case isGlobal = "is_global"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    init(function: AppFunction, userID: String) {
        id = function.id
        self.userID = userID
        name = function.name
        type = function.kind.rawValue
        content = function.content
        meta = FunctionExportMeta(description: function.description, manifest: function.manifest)
        valves = function.valves
        isActive = function.isActive
        isGlobal = function.isGlobal
        createdAt = Int(function.createdAt.timeIntervalSince1970)
        updatedAt = Int(function.updatedAt.timeIntervalSince1970)
    }
}

private struct FunctionExportBundle: Codable {
    var format: String = "open-webui-native-functions"
    var version: Int = 1
    var exportedAt: Date
    var functions: [FunctionExportRecord]
}

private struct FunctionExportRecord: Codable {
    var id: String?
    var userID: String?
    var name: String
    var type: String
    var content: String
    var meta: FunctionExportMeta?
    var valves: JSONValue?
    var isActive: Bool?
    var isGlobal: Bool?
    var createdAt: Date?
    var updatedAt: Date?
    var createdAtUnix: Int?
    var updatedAtUnix: Int?

    enum CodingKeys: String, CodingKey {
        case id
        case userID = "user_id"
        case name
        case type
        case content
        case meta
        case valves
        case isActive = "is_active"
        case isGlobal = "is_global"
        case createdAt
        case updatedAt
        case createdAtUnix = "created_at"
        case updatedAtUnix = "updated_at"
    }

    init(function: AppFunction) {
        id = function.id
        userID = nil
        name = function.name
        type = function.kind.rawValue
        content = function.content
        meta = FunctionExportMeta(description: function.description, manifest: function.manifest)
        valves = function.valves
        isActive = function.isActive
        isGlobal = function.isGlobal
        createdAt = function.createdAt
        updatedAt = function.updatedAt
        createdAtUnix = nil
        updatedAtUnix = nil
    }

    var appFunction: AppFunction? {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedContent = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty,
              !trimmedContent.isEmpty,
              let kind = AppFunctionKind(rawValue: type.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            return nil
        }

        let trimmedDescription = meta?.description?.trimmingCharacters(in: .whitespacesAndNewlines)
        return AppFunction(
            id: id ?? UUID().uuidString,
            name: trimmedName,
            kind: kind,
            content: trimmedContent,
            description: trimmedDescription?.isEmpty == false ? trimmedDescription : nil,
            manifest: meta?.manifest,
            valves: valves,
            isActive: isActive ?? false,
            isGlobal: isGlobal ?? false,
            createdAt: createdAt ?? createdAtUnix.map { Date(timeIntervalSince1970: TimeInterval($0)) } ?? Date(),
            updatedAt: updatedAt ?? updatedAtUnix.map { Date(timeIntervalSince1970: TimeInterval($0)) } ?? Date()
        )
    }
}

private struct FunctionExportMeta: Codable {
    var description: String?
    var manifest: JSONValue?
}
