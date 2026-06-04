import Foundation

struct AppChannel: Identifiable, Codable, Equatable, Sendable {
    var id: UUID
    var name: String
    var description: String?
    var createdAt: Date
    var updatedAt: Date
    var unreadCount: Int
    var messages: [ChannelMessage]
    var members: [ChannelMember]

    init(
        id: UUID = UUID(),
        name: String,
        description: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        unreadCount: Int = 0,
        messages: [ChannelMessage] = [],
        members: [ChannelMember] = []
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.unreadCount = unreadCount
        self.messages = messages
        self.members = members
    }

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case description
        case createdAt
        case updatedAt
        case unreadCount
        case messages
        case members
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try container.decode(UUID.self, forKey: .id),
            name: try container.decode(String.self, forKey: .name),
            description: try container.decodeIfPresent(String.self, forKey: .description),
            createdAt: try container.decode(Date.self, forKey: .createdAt),
            updatedAt: try container.decode(Date.self, forKey: .updatedAt),
            unreadCount: try container.decodeIfPresent(Int.self, forKey: .unreadCount) ?? 0,
            messages: try container.decodeIfPresent([ChannelMessage].self, forKey: .messages) ?? [],
            members: try container.decodeIfPresent([ChannelMember].self, forKey: .members) ?? []
        )
    }
}

struct ChannelMessage: Identifiable, Codable, Equatable, Sendable {
    var id: UUID
    var authorName: String
    var content: String
    var createdAt: Date
    var updatedAt: Date
    var replies: [ChannelReply]

    init(
        id: UUID = UUID(),
        authorName: String = "You",
        content: String,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        replies: [ChannelReply] = []
    ) {
        self.id = id
        self.authorName = authorName
        self.content = content
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.replies = replies
    }

    enum CodingKeys: String, CodingKey {
        case id
        case authorName
        case content
        case createdAt
        case updatedAt
        case replies
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try container.decode(UUID.self, forKey: .id),
            authorName: try container.decode(String.self, forKey: .authorName),
            content: try container.decode(String.self, forKey: .content),
            createdAt: try container.decode(Date.self, forKey: .createdAt),
            updatedAt: try container.decode(Date.self, forKey: .updatedAt),
            replies: try container.decodeIfPresent([ChannelReply].self, forKey: .replies) ?? []
        )
    }
}

struct ChannelReply: Identifiable, Codable, Equatable, Sendable {
    var id: UUID
    var authorName: String
    var content: String
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        authorName: String = "You",
        content: String,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.authorName = authorName
        self.content = content
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

enum ChannelMemberRole: String, Codable, CaseIterable, Equatable, Hashable, Sendable {
    case owner
    case admin
    case member

    var label: String {
        switch self {
        case .owner:
            return "Owner"
        case .admin:
            return "Admin"
        case .member:
            return "Member"
        }
    }
}

enum ChannelMemberStatus: String, Codable, CaseIterable, Equatable, Hashable, Sendable {
    case active
    case inactive
    case invited

    var label: String {
        switch self {
        case .active:
            return "Active"
        case .inactive:
            return "Inactive"
        case .invited:
            return "Invited"
        }
    }
}

struct ChannelMember: Identifiable, Codable, Equatable, Sendable {
    var id: String
    var userID: String
    var displayName: String
    var role: ChannelMemberRole
    var status: ChannelMemberStatus
    var isMuted: Bool
    var isPinned: Bool
    var lastReadAt: Date?
    var createdAt: Date
    var updatedAt: Date

    init(
        id: String = UUID().uuidString,
        userID: String,
        displayName: String,
        role: ChannelMemberRole = .member,
        status: ChannelMemberStatus = .active,
        isMuted: Bool = false,
        isPinned: Bool = false,
        lastReadAt: Date? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.userID = userID
        self.displayName = displayName
        self.role = role
        self.status = status
        self.isMuted = isMuted
        self.isPinned = isPinned
        self.lastReadAt = lastReadAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    enum CodingKeys: String, CodingKey {
        case id
        case userID
        case displayName
        case role
        case status
        case isMuted
        case isPinned
        case lastReadAt
        case createdAt
        case updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try container.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString,
            userID: try container.decode(String.self, forKey: .userID),
            displayName: try container.decode(String.self, forKey: .displayName),
            role: try container.decodeIfPresent(ChannelMemberRole.self, forKey: .role) ?? .member,
            status: try container.decodeIfPresent(ChannelMemberStatus.self, forKey: .status) ?? .active,
            isMuted: try container.decodeIfPresent(Bool.self, forKey: .isMuted) ?? false,
            isPinned: try container.decodeIfPresent(Bool.self, forKey: .isPinned) ?? false,
            lastReadAt: try container.decodeIfPresent(Date.self, forKey: .lastReadAt),
            createdAt: try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date(),
            updatedAt: try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? Date()
        )
    }
}
