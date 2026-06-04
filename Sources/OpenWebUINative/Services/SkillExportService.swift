import Foundation

struct SkillExportService: Sendable {
    func jsonData(for skills: [AppSkill]) throws -> Data {
        let bundle = SkillExportBundle(
            exportedAt: Date(),
            skills: skills.map(SkillExportRecord.init(skill:))
        )
        return try JSONEncoder.openWebUIEncoder.encode(bundle)
    }

    func openWebUIJSONData(for skills: [AppSkill], userID: String) throws -> Data {
        try JSONEncoder.openWebUIEncoder.encode(
            skills.map { OpenWebUISkillExportRecord(skill: $0, userID: userID) }
        )
    }

    func skills(fromJSONData data: Data) throws -> [AppSkill] {
        let decoder = JSONDecoder.openWebUIDecoder
        if let bundle = try? decoder.decode(SkillExportBundle.self, from: data) {
            return bundle.skills.compactMap(\.appSkill)
        }
        if let records = try? decoder.decode([SkillExportRecord].self, from: data) {
            return records.compactMap(\.appSkill)
        }
        return try decoder.decode([AppSkill].self, from: data)
    }
}

private struct OpenWebUISkillExportRecord: Encodable {
    var id: String
    var userID: String
    var name: String
    var description: String?
    var content: String
    var meta: SkillExportMeta
    var isActive: Bool
    var accessGrants: [JSONValue]
    var createdAt: Int
    var updatedAt: Int

    enum CodingKeys: String, CodingKey {
        case id
        case userID = "user_id"
        case name
        case description
        case content
        case meta
        case isActive = "is_active"
        case accessGrants = "access_grants"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    init(skill: AppSkill, userID: String) {
        id = skill.id
        self.userID = userID
        name = skill.name
        description = skill.description
        content = skill.content
        meta = SkillExportMeta(tags: skill.tags)
        isActive = skill.isActive
        accessGrants = skill.accessGrantJSONValues
        createdAt = Int(skill.createdAt.timeIntervalSince1970)
        updatedAt = Int(skill.updatedAt.timeIntervalSince1970)
    }
}

private struct SkillExportBundle: Codable {
    var format: String = "open-webui-native-skills"
    var version: Int = 1
    var exportedAt: Date
    var skills: [SkillExportRecord]
}

private struct SkillExportRecord: Codable {
    var id: String?
    var userID: String?
    var name: String
    var description: String?
    var content: String
    var meta: SkillExportMeta?
    var isActive: Bool?
    var accessGrants: [JSONValue]?
    var createdAt: Date?
    var updatedAt: Date?
    var createdAtUnix: Int?
    var updatedAtUnix: Int?

    enum CodingKeys: String, CodingKey {
        case id
        case userID = "user_id"
        case name
        case description
        case content
        case meta
        case isActive = "is_active"
        case accessGrants = "access_grants"
        case createdAt
        case updatedAt
        case createdAtUnix = "created_at"
        case updatedAtUnix = "updated_at"
    }

    init(skill: AppSkill) {
        id = skill.id
        userID = nil
        name = skill.name
        description = skill.description
        content = skill.content
        meta = SkillExportMeta(tags: skill.tags)
        isActive = skill.isActive
        accessGrants = skill.accessGrantJSONValues
        createdAt = skill.createdAt
        updatedAt = skill.updatedAt
        createdAtUnix = nil
        updatedAtUnix = nil
    }

    var appSkill: AppSkill? {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedContent = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty, !trimmedContent.isEmpty else {
            return nil
        }

        let trimmedDescription = description?.trimmingCharacters(in: .whitespacesAndNewlines)
        return AppSkill(
            id: id ?? UUID().uuidString,
            name: trimmedName,
            content: trimmedContent,
            description: trimmedDescription?.isEmpty == false ? trimmedDescription : nil,
            tags: AppSkill.normalizedTags(meta?.tags ?? []),
            allowedUserIDs: AppSkill.normalizedAccessIDs(accessGrants?.userIDs ?? []),
            allowedGroupIDs: AppSkill.normalizedAccessIDs(accessGrants?.groupIDs ?? []),
            isActive: isActive ?? true,
            createdAt: createdAt ?? createdAtUnix.map { Date(timeIntervalSince1970: TimeInterval($0)) } ?? Date(),
            updatedAt: updatedAt ?? updatedAtUnix.map { Date(timeIntervalSince1970: TimeInterval($0)) } ?? Date()
        )
    }
}

private struct SkillExportMeta: Codable {
    var tags: [String]?
}

extension AppSkill {
    static func normalizedTags(_ tags: [String]) -> [String] {
        var seen: Set<String> = []
        var normalized: [String] = []
        for tag in tags {
            let value = tag.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty, !seen.contains(value) else {
                continue
            }
            seen.insert(value)
            normalized.append(value)
        }
        return normalized
    }

    static func normalizedAccessIDs(_ ids: [String]) -> [String] {
        var seen: Set<String> = []
        var normalized: [String] = []
        for id in ids {
            let value = id.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty, !seen.contains(value) else {
                continue
            }
            seen.insert(value)
            normalized.append(value)
        }
        return normalized
    }

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
