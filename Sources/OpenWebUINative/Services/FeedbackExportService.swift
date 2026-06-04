import Foundation

struct FeedbackExportService: Sendable {
    func jsonData(for feedbacks: [AppFeedback]) throws -> Data {
        let bundle = FeedbackExportBundle(
            exportedAt: Date(),
            feedbacks: feedbacks.map(FeedbackExportRecord.init(feedback:))
        )
        return try JSONEncoder.openWebUIEncoder.encode(bundle)
    }

    func openWebUIJSONData(for feedbacks: [AppFeedback]) throws -> Data {
        try JSONEncoder.openWebUIEncoder.encode(
            feedbacks.map(OpenWebUIFeedbackExportRecord.init(feedback:))
        )
    }

    func feedbacks(fromJSONData data: Data) throws -> [AppFeedback] {
        let decoder = JSONDecoder.openWebUIDecoder
        if let bundle = try? decoder.decode(FeedbackExportBundle.self, from: data) {
            return bundle.feedbacks.map(\.appFeedback)
        }
        if let records = try? decoder.decode([FeedbackExportRecord].self, from: data) {
            return records.map(\.appFeedback)
        }
        return try decoder.decode([AppFeedback].self, from: data)
    }
}

private struct OpenWebUIFeedbackExportRecord: Encodable {
    var id: String
    var userID: String
    var version: Int
    var type: String
    var data: AppFeedbackData
    var meta: AppFeedbackMeta
    var snapshot: AppFeedbackSnapshot?
    var createdAt: Int
    var updatedAt: Int

    enum CodingKeys: String, CodingKey {
        case id
        case userID = "user_id"
        case version
        case type
        case data
        case meta
        case snapshot
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    init(feedback: AppFeedback) {
        id = feedback.id
        userID = feedback.userID
        version = feedback.version
        type = feedback.type
        data = feedback.data
        meta = feedback.meta
        snapshot = feedback.snapshot
        createdAt = Int(feedback.createdAt.timeIntervalSince1970)
        updatedAt = Int(feedback.updatedAt.timeIntervalSince1970)
    }
}

private struct FeedbackExportBundle: Codable {
    var format: String = "open-webui-native-feedback"
    var version: Int = 1
    var exportedAt: Date
    var feedbacks: [FeedbackExportRecord]
}

private struct FeedbackExportRecord: Codable {
    var id: String?
    var userID: String?
    var version: Int?
    var type: String
    var data: AppFeedbackData?
    var meta: AppFeedbackMeta?
    var snapshot: AppFeedbackSnapshot?
    var moderationStatus: AppFeedbackModerationStatus?
    var createdAt: Date?
    var updatedAt: Date?
    var createdAtUnix: Int?
    var updatedAtUnix: Int?

    enum CodingKeys: String, CodingKey {
        case id
        case userID = "user_id"
        case version
        case type
        case data
        case meta
        case snapshot
        case moderationStatus
        case createdAt
        case updatedAt
        case createdAtUnix = "created_at"
        case updatedAtUnix = "updated_at"
    }

    init(feedback: AppFeedback) {
        id = feedback.id
        userID = feedback.userID
        version = feedback.version
        type = feedback.type
        data = feedback.data
        meta = feedback.meta
        snapshot = feedback.snapshot
        moderationStatus = feedback.moderationStatus
        createdAt = feedback.createdAt
        updatedAt = feedback.updatedAt
        createdAtUnix = nil
        updatedAtUnix = nil
    }

    var appFeedback: AppFeedback {
        AppFeedback(
            id: id ?? UUID().uuidString,
            userID: userID ?? "local-user",
            version: version ?? 0,
            type: type.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "rating" : type,
            data: data ?? AppFeedbackData(),
            meta: meta ?? AppFeedbackMeta(),
            snapshot: snapshot,
            moderationStatus: moderationStatus ?? .pending,
            createdAt: createdAt ?? createdAtUnix.map { Date(timeIntervalSince1970: TimeInterval($0)) } ?? Date(),
            updatedAt: updatedAt ?? updatedAtUnix.map { Date(timeIntervalSince1970: TimeInterval($0)) } ?? Date()
        )
    }
}
