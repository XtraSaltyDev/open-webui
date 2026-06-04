import Foundation

enum AdminUserRole: String, Codable, CaseIterable, Equatable, Sendable {
    case admin
    case user
    case pending

    var label: String {
        rawValue.capitalized
    }
}

struct AdminUser: Identifiable, Codable, Equatable, Sendable {
    var id: String
    var name: String
    var email: String
    var role: AdminUserRole
    var createdAt: Date
    var updatedAt: Date
    var lastActiveAt: Date?

    init(
        id: String = UUID().uuidString,
        name: String,
        email: String,
        role: AdminUserRole = .pending,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        lastActiveAt: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.email = email
        self.role = role
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.lastActiveAt = lastActiveAt
    }
}

struct AdminGroup: Identifiable, Codable, Equatable, Sendable {
    var id: String
    var name: String
    var description: String
    var permissions: [String]
    var memberIDs: [String]
    var createdAt: Date
    var updatedAt: Date

    init(
        id: String = UUID().uuidString,
        name: String,
        description: String,
        permissions: [String] = [],
        memberIDs: [String] = [],
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.permissions = permissions
        self.memberIDs = memberIDs
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

struct AdminDirectorySnapshot: Codable, Equatable, Sendable {
    var users: [AdminUser]
    var groups: [AdminGroup]

    init(users: [AdminUser] = [], groups: [AdminGroup] = []) {
        self.users = users
        self.groups = groups
    }
}

extension AdminGroup {
    static func normalizedPermissions(_ permissions: [String]) -> [String] {
        var seen: Set<String> = []
        var normalized: [String] = []
        for permission in permissions {
            let value = permission.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty, !seen.contains(value) else {
                continue
            }
            seen.insert(value)
            normalized.append(value)
        }
        return normalized
    }

    static func normalizedMemberIDs(_ memberIDs: [String], validUserIDs: Set<String>) -> [String] {
        var seen: Set<String> = []
        var normalized: [String] = []
        for memberID in memberIDs where validUserIDs.contains(memberID) && !seen.contains(memberID) {
            seen.insert(memberID)
            normalized.append(memberID)
        }
        return normalized
    }
}
