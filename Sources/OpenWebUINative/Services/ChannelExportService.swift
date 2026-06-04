import Foundation

struct ChannelExportService: Sendable {
    func jsonData(for channels: [AppChannel]) throws -> Data {
        let bundle = ChannelExportBundle(
            exportedAt: Date(),
            channels: channels.map(ChannelExportRecord.init(channel:))
        )
        return try JSONEncoder.openWebUIEncoder.encode(bundle)
    }

    func openWebUIJSONData(for channels: [AppChannel], userID: String) throws -> Data {
        try JSONEncoder.openWebUIEncoder.encode(
            channels.map { OpenWebUIChannelExportRecord(channel: $0, userID: userID) }
        )
    }

    func channels(fromJSONData data: Data) throws -> [AppChannel] {
        let decoder = JSONDecoder.openWebUIDecoder
        if let bundle = try? decoder.decode(ChannelExportBundle.self, from: data) {
            return bundle.channels.compactMap(\.appChannel)
        }
        if let records = try? decoder.decode([ChannelExportRecord].self, from: data) {
            return records.compactMap(\.appChannel)
        }
        return try decoder.decode([AppChannel].self, from: data)
    }
}

private struct OpenWebUIChannelExportRecord: Encodable {
    var id: String
    var userID: String
    var type: String
    var name: String
    var description: String?
    var isPrivate: Bool
    var data: OpenWebUIChannelExportData
    var meta: [String: String]
    var accessGrants: [String]
    var createdAt: Int64
    var updatedAt: Int64

    enum CodingKeys: String, CodingKey {
        case id
        case userID = "user_id"
        case type
        case name
        case description
        case isPrivate = "is_private"
        case data
        case meta
        case accessGrants = "access_grants"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    init(channel: AppChannel, userID: String) {
        id = channel.id.uuidString
        self.userID = userID
        type = "channel"
        name = channel.name
        description = channel.description
        isPrivate = false
        data = OpenWebUIChannelExportData(channel: channel)
        meta = [:]
        accessGrants = []
        createdAt = Self.nanoseconds(from: channel.createdAt)
        updatedAt = Self.nanoseconds(from: channel.updatedAt)
    }

    private static func nanoseconds(from date: Date) -> Int64 {
        Int64(date.timeIntervalSince1970 * 1_000_000_000)
    }
}

private struct OpenWebUIChannelExportData: Encodable {
    var unreadCount: Int
    var messages: [OpenWebUIChannelMessageExportRecord]
    var members: [OpenWebUIChannelMemberExportRecord]

    enum CodingKeys: String, CodingKey {
        case unreadCount = "unread_count"
        case messages
        case members
    }

    init(channel: AppChannel) {
        unreadCount = channel.unreadCount
        messages = channel.messages.map(OpenWebUIChannelMessageExportRecord.init(message:))
        members = channel.members.map(OpenWebUIChannelMemberExportRecord.init(member:))
    }
}

private struct OpenWebUIChannelMessageExportRecord: Encodable {
    var id: String
    var authorName: String
    var content: String
    var replies: [OpenWebUIChannelMessageExportRecord]?
    var createdAt: Int64
    var updatedAt: Int64

    enum CodingKeys: String, CodingKey {
        case id
        case authorName = "author_name"
        case content
        case replies
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    init(message: ChannelMessage) {
        id = message.id.uuidString
        authorName = message.authorName
        content = message.content
        replies = message.replies.map(OpenWebUIChannelMessageExportRecord.init(reply:))
        createdAt = Self.nanoseconds(from: message.createdAt)
        updatedAt = Self.nanoseconds(from: message.updatedAt)
    }

    init(reply: ChannelReply) {
        id = reply.id.uuidString
        authorName = reply.authorName
        content = reply.content
        replies = nil
        createdAt = Self.nanoseconds(from: reply.createdAt)
        updatedAt = Self.nanoseconds(from: reply.updatedAt)
    }

    private static func nanoseconds(from date: Date) -> Int64 {
        Int64(date.timeIntervalSince1970 * 1_000_000_000)
    }
}

private struct OpenWebUIChannelMemberExportRecord: Encodable {
    var id: String
    var userID: String
    var displayName: String
    var role: ChannelMemberRole
    var status: ChannelMemberStatus
    var isActive: Bool
    var isMuted: Bool
    var isPinned: Bool
    var lastReadAt: Int64?
    var createdAt: Int64
    var updatedAt: Int64

    enum CodingKeys: String, CodingKey {
        case id
        case userID = "user_id"
        case displayName = "display_name"
        case role
        case status
        case isActive = "is_active"
        case isMuted = "is_channel_muted"
        case isPinned = "is_channel_pinned"
        case lastReadAt = "last_read_at"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    init(member: ChannelMember) {
        id = member.id
        userID = member.userID
        displayName = member.displayName
        role = member.role
        status = member.status
        isActive = member.status == .active
        isMuted = member.isMuted
        isPinned = member.isPinned
        lastReadAt = member.lastReadAt.map(Self.nanoseconds(from:))
        createdAt = Self.nanoseconds(from: member.createdAt)
        updatedAt = Self.nanoseconds(from: member.updatedAt)
    }

    private static func nanoseconds(from date: Date) -> Int64 {
        Int64(date.timeIntervalSince1970 * 1_000_000_000)
    }
}

private struct ChannelExportBundle: Codable {
    var format: String = "open-webui-native-channels"
    var version: Int = 1
    var exportedAt: Date
    var channels: [ChannelExportRecord]
}

private struct ChannelExportRecord: Codable {
    var id: String?
    var userID: String?
    var type: String?
    var name: String
    var description: String?
    var isPrivate: Bool?
    var data: ChannelExportData?
    var meta: [String: String]?
    var createdAt: Date?
    var updatedAt: Date?
    var createdAtUnix: Int64?
    var updatedAtUnix: Int64?
    var unreadCount: Int?

    enum CodingKeys: String, CodingKey {
        case id
        case userID = "user_id"
        case type
        case name
        case description
        case isPrivate = "is_private"
        case data
        case meta
        case createdAt
        case updatedAt
        case createdAtUnix = "created_at"
        case updatedAtUnix = "updated_at"
        case unreadCount
    }

    init(channel: AppChannel) {
        id = channel.id.uuidString
        userID = nil
        type = "channel"
        name = channel.name
        description = channel.description
        isPrivate = nil
        data = ChannelExportData(
            unreadCount: channel.unreadCount,
            messages: channel.messages.map(ChannelMessageExportRecord.init(message:)),
            members: channel.members.map(ChannelMemberExportRecord.init(member:))
        )
        meta = [:]
        createdAt = channel.createdAt
        updatedAt = channel.updatedAt
        createdAtUnix = nil
        updatedAtUnix = nil
        unreadCount = channel.unreadCount
    }

    var appChannel: AppChannel? {
        let resolvedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedDescription = description?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !resolvedName.isEmpty else {
            return nil
        }

        return AppChannel(
            id: id.flatMap(UUID.init(uuidString:)) ?? UUID(),
            name: resolvedName,
            description: resolvedDescription?.isEmpty == false ? resolvedDescription : nil,
            createdAt: createdAt ?? createdAtUnix.map(Self.date(fromEpochValue:)) ?? Date(),
            updatedAt: updatedAt ?? updatedAtUnix.map(Self.date(fromEpochValue:)) ?? Date(),
            unreadCount: data?.unreadCount ?? unreadCount ?? 0,
            messages: data?.messages?.compactMap(\.channelMessage) ?? [],
            members: data?.members?.compactMap(\.channelMember) ?? []
        )
    }

    private static func date(fromEpochValue value: Int64) -> Date {
        if value > 100_000_000_000 {
            return Date(timeIntervalSince1970: TimeInterval(value) / 1_000_000_000)
        }
        return Date(timeIntervalSince1970: TimeInterval(value))
    }
}

private struct ChannelExportData: Codable {
    var unreadCount: Int?
    var messages: [ChannelMessageExportRecord]?
    var members: [ChannelMemberExportRecord]?

    enum CodingKeys: String, CodingKey {
        case unreadCount
        case unreadCountSnake = "unread_count"
        case messages
        case members
    }

    init(
        unreadCount: Int?,
        messages: [ChannelMessageExportRecord]?,
        members: [ChannelMemberExportRecord]? = nil
    ) {
        self.unreadCount = unreadCount
        self.messages = messages
        self.members = members
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        unreadCount = try container.decodeIfPresent(Int.self, forKey: .unreadCount)
            ?? container.decodeIfPresent(Int.self, forKey: .unreadCountSnake)
        messages = try container.decodeIfPresent([ChannelMessageExportRecord].self, forKey: .messages)
        members = try container.decodeIfPresent([ChannelMemberExportRecord].self, forKey: .members)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(unreadCount, forKey: .unreadCountSnake)
        try container.encodeIfPresent(messages, forKey: .messages)
        try container.encodeIfPresent(members, forKey: .members)
    }
}

private struct ChannelMessageExportRecord: Codable {
    var id: String?
    var authorName: String?
    var content: String
    var replies: [ChannelMessageExportRecord]?
    var createdAt: Date?
    var updatedAt: Date?
    var createdAtUnix: Int64?
    var updatedAtUnix: Int64?

    enum CodingKeys: String, CodingKey {
        case id
        case authorName
        case authorNameSnake = "author_name"
        case content
        case replies
        case createdAt
        case updatedAt
        case createdAtUnix = "created_at"
        case updatedAtUnix = "updated_at"
    }

    init(message: ChannelMessage) {
        id = message.id.uuidString
        authorName = message.authorName
        content = message.content
        replies = message.replies.map(ChannelMessageExportRecord.init(reply:))
        createdAt = message.createdAt
        updatedAt = message.updatedAt
        createdAtUnix = nil
        updatedAtUnix = nil
    }

    init(reply: ChannelReply) {
        id = reply.id.uuidString
        authorName = reply.authorName
        content = reply.content
        replies = nil
        createdAt = reply.createdAt
        updatedAt = reply.updatedAt
        createdAtUnix = nil
        updatedAtUnix = nil
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id)
        authorName = try container.decodeIfPresent(String.self, forKey: .authorName)
            ?? container.decodeIfPresent(String.self, forKey: .authorNameSnake)
        content = try container.decode(String.self, forKey: .content)
        replies = try container.decodeIfPresent([ChannelMessageExportRecord].self, forKey: .replies)
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt)
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt)
        createdAtUnix = try container.decodeIfPresent(Int64.self, forKey: .createdAtUnix)
        updatedAtUnix = try container.decodeIfPresent(Int64.self, forKey: .updatedAtUnix)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(id, forKey: .id)
        try container.encodeIfPresent(authorName, forKey: .authorNameSnake)
        try container.encode(content, forKey: .content)
        try container.encodeIfPresent(replies, forKey: .replies)
        try container.encodeIfPresent(createdAt, forKey: .createdAt)
        try container.encodeIfPresent(updatedAt, forKey: .updatedAt)
    }

    var channelMessage: ChannelMessage? {
        let resolvedContent = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !resolvedContent.isEmpty else {
            return nil
        }

        return ChannelMessage(
            id: id.flatMap(UUID.init(uuidString:)) ?? UUID(),
            authorName: authorName?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
                ? authorName!.trimmingCharacters(in: .whitespacesAndNewlines)
                : "Unknown",
            content: resolvedContent,
            createdAt: createdAt ?? createdAtUnix.map(Self.date(fromEpochValue:)) ?? Date(),
            updatedAt: updatedAt ?? updatedAtUnix.map(Self.date(fromEpochValue:)) ?? Date(),
            replies: replies?.compactMap(\.channelReply) ?? []
        )
    }

    var channelReply: ChannelReply? {
        let resolvedContent = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !resolvedContent.isEmpty else {
            return nil
        }

        return ChannelReply(
            id: id.flatMap(UUID.init(uuidString:)) ?? UUID(),
            authorName: authorName?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
                ? authorName!.trimmingCharacters(in: .whitespacesAndNewlines)
                : "Unknown",
            content: resolvedContent,
            createdAt: createdAt ?? createdAtUnix.map(Self.date(fromEpochValue:)) ?? Date(),
            updatedAt: updatedAt ?? updatedAtUnix.map(Self.date(fromEpochValue:)) ?? Date()
        )
    }

    private static func date(fromEpochValue value: Int64) -> Date {
        if value > 100_000_000_000 {
            return Date(timeIntervalSince1970: TimeInterval(value) / 1_000_000_000)
        }
        return Date(timeIntervalSince1970: TimeInterval(value))
    }
}

private struct ChannelMemberExportRecord: Codable {
    var id: String?
    var userID: String?
    var displayName: String?
    var role: ChannelMemberRole?
    var status: ChannelMemberStatus?
    var isMuted: Bool?
    var isPinned: Bool?
    var lastReadAt: Date?
    var lastReadAtUnix: Int64?
    var createdAt: Date?
    var updatedAt: Date?
    var createdAtUnix: Int64?
    var updatedAtUnix: Int64?

    enum CodingKeys: String, CodingKey {
        case id
        case userID = "user_id"
        case userIDCamel = "userID"
        case displayName = "display_name"
        case displayNameCamel = "displayName"
        case role
        case status
        case isMuted = "is_channel_muted"
        case isMutedCamel = "isMuted"
        case isPinned = "is_channel_pinned"
        case isPinnedCamel = "isPinned"
        case lastReadAt
        case lastReadAtUnix = "last_read_at"
        case createdAt
        case updatedAt
        case createdAtUnix = "created_at"
        case updatedAtUnix = "updated_at"
    }

    init(member: ChannelMember) {
        id = member.id
        userID = member.userID
        displayName = member.displayName
        role = member.role
        status = member.status
        isMuted = member.isMuted
        isPinned = member.isPinned
        lastReadAt = member.lastReadAt
        lastReadAtUnix = nil
        createdAt = member.createdAt
        updatedAt = member.updatedAt
        createdAtUnix = nil
        updatedAtUnix = nil
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id)
        userID = try container.decodeIfPresent(String.self, forKey: .userID)
            ?? container.decodeIfPresent(String.self, forKey: .userIDCamel)
        displayName = try container.decodeIfPresent(String.self, forKey: .displayName)
            ?? container.decodeIfPresent(String.self, forKey: .displayNameCamel)
        role = try container.decodeIfPresent(ChannelMemberRole.self, forKey: .role)
        status = try container.decodeIfPresent(ChannelMemberStatus.self, forKey: .status)
        isMuted = try container.decodeIfPresent(Bool.self, forKey: .isMuted)
            ?? container.decodeIfPresent(Bool.self, forKey: .isMutedCamel)
        isPinned = try container.decodeIfPresent(Bool.self, forKey: .isPinned)
            ?? container.decodeIfPresent(Bool.self, forKey: .isPinnedCamel)
        lastReadAt = try container.decodeIfPresent(Date.self, forKey: .lastReadAt)
        lastReadAtUnix = try container.decodeIfPresent(Int64.self, forKey: .lastReadAtUnix)
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt)
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt)
        createdAtUnix = try container.decodeIfPresent(Int64.self, forKey: .createdAtUnix)
        updatedAtUnix = try container.decodeIfPresent(Int64.self, forKey: .updatedAtUnix)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(id, forKey: .id)
        try container.encodeIfPresent(userID, forKey: .userID)
        try container.encodeIfPresent(displayName, forKey: .displayName)
        try container.encodeIfPresent(role, forKey: .role)
        try container.encodeIfPresent(status, forKey: .status)
        try container.encodeIfPresent(isMuted, forKey: .isMuted)
        try container.encodeIfPresent(isPinned, forKey: .isPinned)
        try container.encodeIfPresent(lastReadAt, forKey: .lastReadAt)
        try container.encodeIfPresent(createdAt, forKey: .createdAt)
        try container.encodeIfPresent(updatedAt, forKey: .updatedAt)
    }

    var channelMember: ChannelMember? {
        let resolvedUserID = userID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let resolvedDisplayName = displayName?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !resolvedUserID.isEmpty else {
            return nil
        }

        return ChannelMember(
            id: id?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
                ? id!.trimmingCharacters(in: .whitespacesAndNewlines)
                : UUID().uuidString,
            userID: resolvedUserID,
            displayName: resolvedDisplayName?.isEmpty == false ? resolvedDisplayName! : resolvedUserID,
            role: role ?? .member,
            status: status ?? .active,
            isMuted: isMuted ?? false,
            isPinned: isPinned ?? false,
            lastReadAt: lastReadAt ?? lastReadAtUnix.map(Self.date(fromEpochValue:)),
            createdAt: createdAt ?? createdAtUnix.map(Self.date(fromEpochValue:)) ?? Date(),
            updatedAt: updatedAt ?? updatedAtUnix.map(Self.date(fromEpochValue:)) ?? Date()
        )
    }

    private static func date(fromEpochValue value: Int64) -> Date {
        if value > 100_000_000_000 {
            return Date(timeIntervalSince1970: TimeInterval(value) / 1_000_000_000)
        }
        return Date(timeIntervalSince1970: TimeInterval(value))
    }
}
