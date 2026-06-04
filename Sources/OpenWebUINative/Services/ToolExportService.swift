import Foundation

struct ToolExportService: Sendable {
    func jsonData(for tools: [AppTool]) throws -> Data {
        let bundle = ToolExportBundle(
            exportedAt: Date(),
            tools: tools.map(ToolExportRecord.init(tool:))
        )
        return try JSONEncoder.openWebUIEncoder.encode(bundle)
    }

    func openWebUIJSONData(for tools: [AppTool], userID: String) throws -> Data {
        try JSONEncoder.openWebUIEncoder.encode(
            tools.map { OpenWebUIToolExportRecord(tool: $0, userID: userID) }
        )
    }

    func tools(fromJSONData data: Data) throws -> [AppTool] {
        let decoder = JSONDecoder.openWebUIDecoder
        if let bundle = try? decoder.decode(ToolExportBundle.self, from: data) {
            return bundle.tools.compactMap(\.appTool)
        }
        if let records = try? decoder.decode([ToolExportRecord].self, from: data) {
            return records.compactMap(\.appTool)
        }
        return try decoder.decode([AppTool].self, from: data)
    }
}

private struct OpenWebUIToolExportRecord: Encodable {
    var id: String
    var userID: String
    var name: String
    var content: String
    var specs: [JSONValue]
    var meta: ToolExportMeta
    var valves: JSONValue?
    var accessGrants: [JSONValue]
    var createdAt: Int
    var updatedAt: Int

    enum CodingKeys: String, CodingKey {
        case id
        case userID = "user_id"
        case name
        case content
        case specs
        case meta
        case valves
        case accessGrants = "access_grants"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    init(tool: AppTool, userID: String) {
        id = tool.id
        self.userID = userID
        name = tool.name
        content = tool.content
        specs = tool.specs
        meta = ToolExportMeta(description: tool.description, manifest: tool.manifest)
        valves = tool.valves
        accessGrants = []
        createdAt = Int(tool.createdAt.timeIntervalSince1970)
        updatedAt = Int(tool.updatedAt.timeIntervalSince1970)
    }
}

private struct ToolExportBundle: Codable {
    var format: String = "open-webui-native-tools"
    var version: Int = 1
    var exportedAt: Date
    var tools: [ToolExportRecord]
}

private struct ToolExportRecord: Codable {
    var id: String?
    var userID: String?
    var name: String
    var content: String
    var specs: [JSONValue]?
    var meta: ToolExportMeta?
    var valves: JSONValue?
    var accessGrants: [JSONValue]?
    var createdAt: Date?
    var updatedAt: Date?
    var createdAtUnix: Int?
    var updatedAtUnix: Int?

    enum CodingKeys: String, CodingKey {
        case id
        case userID = "user_id"
        case name
        case content
        case specs
        case meta
        case valves
        case accessGrants = "access_grants"
        case createdAt
        case updatedAt
        case createdAtUnix = "created_at"
        case updatedAtUnix = "updated_at"
    }

    init(tool: AppTool) {
        id = tool.id
        userID = nil
        name = tool.name
        content = tool.content
        specs = tool.specs
        meta = ToolExportMeta(description: tool.description, manifest: tool.manifest)
        valves = tool.valves
        accessGrants = []
        createdAt = tool.createdAt
        updatedAt = tool.updatedAt
        createdAtUnix = nil
        updatedAtUnix = nil
    }

    var appTool: AppTool? {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedContent = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty, !trimmedContent.isEmpty else {
            return nil
        }

        let trimmedDescription = meta?.description?.trimmingCharacters(in: .whitespacesAndNewlines)
        return AppTool(
            id: id ?? UUID().uuidString,
            name: trimmedName,
            content: trimmedContent,
            description: trimmedDescription?.isEmpty == false ? trimmedDescription : nil,
            specs: specs ?? [],
            manifest: meta?.manifest,
            valves: valves,
            createdAt: createdAt ?? createdAtUnix.map { Date(timeIntervalSince1970: TimeInterval($0)) } ?? Date(),
            updatedAt: updatedAt ?? updatedAtUnix.map { Date(timeIntervalSince1970: TimeInterval($0)) } ?? Date()
        )
    }
}

private struct ToolExportMeta: Codable {
    var description: String?
    var manifest: JSONValue?
}
