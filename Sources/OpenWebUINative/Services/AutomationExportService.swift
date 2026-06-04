import Foundation

struct AutomationExportService: Sendable {
    func jsonData(for automations: [AppAutomation]) throws -> Data {
        let bundle = AutomationExportBundle(
            exportedAt: Date(),
            automations: automations.map(AutomationExportRecord.init(automation:))
        )
        return try JSONEncoder.openWebUIEncoder.encode(bundle)
    }

    func openWebUIJSONData(for automations: [AppAutomation]) throws -> Data {
        try JSONEncoder.openWebUIEncoder.encode(
            automations.map(OpenWebUIAutomationExportRecord.init(automation:))
        )
    }

    func automations(fromJSONData data: Data) throws -> [AppAutomation] {
        let decoder = JSONDecoder.openWebUIDecoder
        if let bundle = try? decoder.decode(AutomationExportBundle.self, from: data) {
            return bundle.automations.compactMap(\.appAutomation)
        }
        if let records = try? decoder.decode([AutomationExportRecord].self, from: data) {
            return records.compactMap(\.appAutomation)
        }
        return try decoder.decode([AppAutomation].self, from: data)
    }
}

private struct OpenWebUIAutomationExportRecord: Encodable {
    var id: String
    var userID: String
    var name: String
    var data: AutomationExportData
    var meta: JSONValue?
    var isActive: Bool
    var lastRunAt: Int64?
    var nextRunAt: Int64?
    var createdAt: Int64
    var updatedAt: Int64

    enum CodingKeys: String, CodingKey {
        case id
        case userID = "user_id"
        case name
        case data
        case meta
        case isActive = "is_active"
        case lastRunAt = "last_run_at"
        case nextRunAt = "next_run_at"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    init(automation: AppAutomation) {
        id = automation.id
        userID = automation.userID
        name = automation.name
        data = AutomationExportData(
            prompt: automation.prompt,
            modelID: automation.modelID,
            rrule: automation.rrule
        )
        meta = automation.meta
        isActive = automation.isActive
        lastRunAt = automation.lastRunAt.map(Self.nanoseconds(from:))
        nextRunAt = automation.nextRunAt.map(Self.nanoseconds(from:))
        createdAt = Self.nanoseconds(from: automation.createdAt)
        updatedAt = Self.nanoseconds(from: automation.updatedAt)
    }

    private static func nanoseconds(from date: Date) -> Int64 {
        Int64(date.timeIntervalSince1970 * 1_000_000_000)
    }
}

private struct AutomationExportBundle: Codable {
    var format: String = "open-webui-native-automations"
    var version: Int = 1
    var exportedAt: Date
    var automations: [AutomationExportRecord]
}

private struct AutomationExportRecord: Codable {
    var id: String?
    var userID: String?
    var name: String
    var data: AutomationExportData?
    var meta: JSONValue?
    var isActive: Bool?
    var lastRunAt: Date?
    var nextRunAt: Date?
    var createdAt: Date?
    var updatedAt: Date?
    var lastRunAtUnix: Int64?
    var nextRunAtUnix: Int64?
    var createdAtUnix: Int64?
    var updatedAtUnix: Int64?

    enum CodingKeys: String, CodingKey {
        case id
        case userID = "user_id"
        case name
        case data
        case meta
        case isActive = "is_active"
        case lastRunAt
        case nextRunAt
        case createdAt
        case updatedAt
        case lastRunAtUnix = "last_run_at"
        case nextRunAtUnix = "next_run_at"
        case createdAtUnix = "created_at"
        case updatedAtUnix = "updated_at"
    }

    init(automation: AppAutomation) {
        id = automation.id
        userID = automation.userID
        name = automation.name
        data = AutomationExportData(
            prompt: automation.prompt,
            modelID: automation.modelID,
            rrule: automation.rrule
        )
        meta = automation.meta
        isActive = automation.isActive
        lastRunAt = automation.lastRunAt
        nextRunAt = automation.nextRunAt
        createdAt = automation.createdAt
        updatedAt = automation.updatedAt
        lastRunAtUnix = nil
        nextRunAtUnix = nil
        createdAtUnix = nil
        updatedAtUnix = nil
    }

    var appAutomation: AppAutomation? {
        let resolvedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedPrompt = (data?.prompt ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedModelID = (data?.modelID ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedRRule = (data?.rrule ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !resolvedName.isEmpty, !resolvedPrompt.isEmpty, !resolvedModelID.isEmpty, !resolvedRRule.isEmpty else {
            return nil
        }

        return AppAutomation(
            id: id?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? UUID().uuidString,
            userID: userID?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? "local-user",
            name: resolvedName,
            prompt: resolvedPrompt,
            modelID: resolvedModelID,
            rrule: resolvedRRule,
            meta: meta,
            isActive: isActive ?? true,
            lastRunAt: lastRunAt ?? lastRunAtUnix.map(AutomationExportRecord.date(fromEpochValue:)),
            nextRunAt: nextRunAt ?? nextRunAtUnix.map(AutomationExportRecord.date(fromEpochValue:)),
            createdAt: createdAt ?? createdAtUnix.map(AutomationExportRecord.date(fromEpochValue:)) ?? Date(),
            updatedAt: updatedAt ?? updatedAtUnix.map(AutomationExportRecord.date(fromEpochValue:)) ?? Date()
        )
    }

    private static func date(fromEpochValue value: Int64) -> Date {
        if value > 100_000_000_000 {
            return Date(timeIntervalSince1970: TimeInterval(value) / 1_000_000_000)
        }
        return Date(timeIntervalSince1970: TimeInterval(value))
    }
}

private struct AutomationExportData: Codable {
    var prompt: String?
    var modelID: String?
    var rrule: String?

    enum CodingKeys: String, CodingKey {
        case prompt
        case modelID = "model_id"
        case rrule
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
