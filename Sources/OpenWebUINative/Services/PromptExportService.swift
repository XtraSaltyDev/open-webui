import Foundation

struct PromptExportService: Sendable {
    func jsonData(for prompts: [SavedPrompt]) throws -> Data {
        let bundle = PromptExportBundle(
            exportedAt: Date(),
            prompts: prompts.map(PromptExportRecord.init(prompt:))
        )
        return try JSONEncoder.openWebUIEncoder.encode(bundle)
    }

    func openWebUIJSONData(for prompts: [SavedPrompt]) throws -> Data {
        try JSONEncoder.openWebUIEncoder.encode(prompts.map(OpenWebUIPromptExportRecord.init(prompt:)))
    }

    func prompts(fromJSONData data: Data) throws -> [SavedPrompt] {
        let decoder = JSONDecoder.openWebUIDecoder
        if let bundle = try? decoder.decode(PromptExportBundle.self, from: data) {
            return bundle.prompts.compactMap(\.savedPrompt)
        }
        if let records = try? decoder.decode([PromptExportRecord].self, from: data) {
            return records.compactMap(\.savedPrompt)
        }
        return try decoder.decode([SavedPrompt].self, from: data)
    }
}

private struct PromptExportBundle: Codable {
    var format: String = "open-webui-native-prompts"
    var version: Int = 1
    var exportedAt: Date
    var prompts: [PromptExportRecord]
}

private struct PromptExportRecord: Codable {
    var id: String?
    var command: String?
    var userID: String?
    var name: String?
    var title: String?
    var content: String
    var data: [String: String]?
    var meta: [String: String]?
    var tags: [String?]?
    var allowedUserIDs: [String]?
    var allowedGroupIDs: [String]?
    var accessGrants: [JSONValue]?
    var isActive: Bool?
    var versions: [SavedPromptVersion]?
    var createdAt: Date?
    var updatedAt: Date?
    var createdAtUnix: Int?
    var updatedAtUnix: Int?

    enum CodingKeys: String, CodingKey {
        case id
        case command
        case userID = "user_id"
        case name
        case title
        case content
        case data
        case meta
        case tags
        case allowedUserIDs
        case allowedGroupIDs
        case accessGrants = "access_grants"
        case isActive = "is_active"
        case versions
        case createdAt
        case updatedAt
        case createdAtUnix = "created_at"
        case updatedAtUnix = "updated_at"
    }

    init(prompt: SavedPrompt) {
        id = prompt.id.uuidString
        command = prompt.command ?? PromptExportRecord.command(for: prompt.title)
        userID = nil
        name = prompt.title
        title = prompt.title
        content = prompt.content
        data = [:]
        meta = [:]
        tags = prompt.tags.map(Optional.some)
        allowedUserIDs = prompt.allowedUserIDs
        allowedGroupIDs = prompt.allowedGroupIDs
        accessGrants = prompt.accessGrantJSONValues
        isActive = true
        versions = prompt.versions
        createdAt = prompt.createdAt
        updatedAt = prompt.updatedAt
        createdAtUnix = nil
        updatedAtUnix = nil
    }

    private enum LegacyCodingKeys: String, CodingKey {
        case versionHistory = "version_history"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let legacyContainer = try? decoder.container(keyedBy: LegacyCodingKeys.self)

        id = try container.decodeIfPresent(String.self, forKey: .id)
        command = try container.decodeIfPresent(String.self, forKey: .command)
        userID = try container.decodeIfPresent(String.self, forKey: .userID)
        name = try container.decodeIfPresent(String.self, forKey: .name)
        title = try container.decodeIfPresent(String.self, forKey: .title)
        content = try container.decode(String.self, forKey: .content)
        data = try container.decodeIfPresent([String: String].self, forKey: .data)
        meta = try container.decodeIfPresent([String: String].self, forKey: .meta)
        tags = try container.decodeIfPresent([String?].self, forKey: .tags)
        allowedUserIDs = try container.decodeIfPresent([String].self, forKey: .allowedUserIDs)
        allowedGroupIDs = try container.decodeIfPresent([String].self, forKey: .allowedGroupIDs)
        accessGrants = try container.decodeIfPresent([JSONValue].self, forKey: .accessGrants)
        isActive = try container.decodeIfPresent(Bool.self, forKey: .isActive)
        versions = try container.decodeIfPresent([SavedPromptVersion].self, forKey: .versions)
            ?? legacyContainer?.decodeIfPresent([SavedPromptVersion].self, forKey: .versionHistory)
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt)
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt)
        createdAtUnix = try container.decodeIfPresent(Int.self, forKey: .createdAtUnix)
        updatedAtUnix = try container.decodeIfPresent(Int.self, forKey: .updatedAtUnix)
    }

    var savedPrompt: SavedPrompt? {
        let resolvedTitle = (name ?? title ?? command ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let resolvedContent = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !resolvedTitle.isEmpty, !resolvedContent.isEmpty else {
            return nil
        }

        return SavedPrompt(
            id: id.flatMap(UUID.init(uuidString:)) ?? UUID(),
            title: resolvedTitle,
            content: resolvedContent,
            command: SavedPrompt.normalizedCommand(command),
            tags: SavedPrompt.normalizedTags(tags?.compactMap { $0 } ?? []),
            allowedUserIDs: SavedPrompt.normalizedAccessIDs(allowedUserIDs ?? accessGrants?.userIDs ?? []),
            allowedGroupIDs: SavedPrompt.normalizedAccessIDs(allowedGroupIDs ?? accessGrants?.groupIDs ?? []),
            versions: versions ?? [],
            createdAt: createdAt ?? createdAtUnix.map { Date(timeIntervalSince1970: TimeInterval($0)) } ?? Date(),
            updatedAt: updatedAt ?? updatedAtUnix.map { Date(timeIntervalSince1970: TimeInterval($0)) } ?? Date()
        )
    }

    fileprivate static func command(for title: String) -> String {
        let slug = title
            .lowercased()
            .split { !$0.isLetter && !$0.isNumber }
            .joined(separator: "-")
        return slug.isEmpty ? "/prompt" : "/\(slug)"
    }
}

private struct OpenWebUIPromptExportRecord: Encodable {
    var id: String
    var command: String
    var userID: String
    var name: String
    var content: String
    var data: [String: String]
    var meta: [String: String]
    var tags: [String]
    var isActive: Bool
    var createdAt: Int
    var updatedAt: Int
    var accessGrants: [JSONValue]

    enum CodingKeys: String, CodingKey {
        case id
        case command
        case userID = "user_id"
        case name
        case content
        case data
        case meta
        case tags
        case isActive = "is_active"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case accessGrants = "access_grants"
    }

    init(prompt: SavedPrompt) {
        id = prompt.id.uuidString
        command = prompt.command ?? PromptExportRecord.command(for: prompt.title)
        userID = "local-user"
        name = prompt.title
        content = prompt.content
        data = [:]
        meta = [:]
        tags = prompt.tags
        isActive = true
        createdAt = Int(prompt.createdAt.timeIntervalSince1970)
        updatedAt = Int(prompt.updatedAt.timeIntervalSince1970)
        accessGrants = prompt.accessGrantJSONValues
    }
}

private extension SavedPrompt {
    var accessGrantJSONValues: [JSONValue] {
        allowedUserIDs.map { id in
            JSONValue.object([
                "type": .string("user"),
                "id": .string(id)
            ])
        } + allowedGroupIDs.map { id in
            JSONValue.object([
                "type": .string("group"),
                "id": .string(id)
            ])
        }
    }
}

private extension Array where Element == JSONValue {
    var userIDs: [String] {
        compactMap { grantID($0, expectedType: "user", fallbackKeys: ["user_id", "userID"]) }
    }

    var groupIDs: [String] {
        compactMap { grantID($0, expectedType: "group", fallbackKeys: ["group_id", "groupID"]) }
    }

    private func grantID(_ value: JSONValue, expectedType: String, fallbackKeys: [String]) -> String? {
        if case .string(let rawValue) = value {
            let prefix = "\(expectedType):"
            return rawValue.hasPrefix(prefix) ? String(rawValue.dropFirst(prefix.count)) : nil
        }

        guard let object = value.objectValue else {
            return nil
        }

        let type = object["type"]?.stringValue ?? object["kind"]?.stringValue
        guard type == expectedType else {
            return nil
        }

        if let id = object["id"]?.stringValue {
            return id
        }
        for key in fallbackKeys {
            if let id = object[key]?.stringValue {
                return id
            }
        }
        return nil
    }
}

private extension JSONValue {
    var stringValue: String? {
        if case .string(let value) = self {
            return value
        }
        return nil
    }
}
