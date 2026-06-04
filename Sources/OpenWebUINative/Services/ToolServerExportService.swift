import Foundation

struct ToolServerExportService: Sendable {
    func jsonData(for servers: [AppToolServer]) throws -> Data {
        let bundle = ToolServerExportBundle(
            exportedAt: Date(),
            servers: servers.map(ToolServerExportRecord.init(server:))
        )
        return try JSONEncoder.openWebUIEncoder.encode(bundle)
    }

    func servers(fromJSONData data: Data) throws -> [AppToolServer] {
        let decoder = JSONDecoder.openWebUIDecoder
        if let bundle = try? decoder.decode(ToolServerExportBundle.self, from: data) {
            return bundle.servers.compactMap(\.appToolServer)
        }
        if let records = try? decoder.decode([ToolServerExportRecord].self, from: data) {
            return records.compactMap(\.appToolServer)
        }
        return try decoder.decode([AppToolServer].self, from: data)
    }
}

private struct ToolServerExportBundle: Codable {
    var format: String = "open-webui-native-tool-servers"
    var version: Int = 1
    var exportedAt: Date
    var servers: [ToolServerExportRecord]
}

private struct ToolServerExportRecord: Codable {
    var id: String?
    var name: String
    var type: String
    var command: String?
    var args: [String]?
    var url: String?
    var env: [String: String]?
    var enabled: Bool?
    var createdAt: Date?
    var updatedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case type
        case command
        case args
        case url
        case env
        case enabled
        case createdAt
        case updatedAt
    }

    init(server: AppToolServer) {
        id = server.id
        name = server.name
        type = server.kind.rawValue
        command = server.command
        args = server.arguments
        url = server.baseURL
        env = server.environment
        enabled = server.isEnabled
        createdAt = server.createdAt
        updatedAt = server.updatedAt
    }

    var appToolServer: AppToolServer? {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            return nil
        }

        let kind = AppToolServerKind(rawValue: type.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()) ?? .stdio
        switch kind {
        case .stdio:
            let trimmedCommand = command?.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let trimmedCommand, !trimmedCommand.isEmpty else {
                return nil
            }
            return AppToolServer(
                id: id ?? UUID().uuidString,
                name: trimmedName,
                kind: .stdio,
                command: trimmedCommand,
                arguments: args ?? [],
                environment: env ?? [:],
                isEnabled: enabled ?? true,
                createdAt: createdAt ?? Date(),
                updatedAt: updatedAt ?? createdAt ?? Date()
            )
        case .http:
            let trimmedURL = url?.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let trimmedURL, !trimmedURL.isEmpty else {
                return nil
            }
            return AppToolServer(
                id: id ?? UUID().uuidString,
                name: trimmedName,
                kind: .http,
                baseURL: trimmedURL,
                isEnabled: enabled ?? true,
                createdAt: createdAt ?? Date(),
                updatedAt: updatedAt ?? createdAt ?? Date()
            )
        }
    }
}
