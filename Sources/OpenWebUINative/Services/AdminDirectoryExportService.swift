import Foundation

struct AdminDirectoryExportService: Sendable {
    func jsonData(for snapshot: AdminDirectorySnapshot) throws -> Data {
        let bundle = AdminDirectoryExportBundle(
            format: "open-webui-native-admin-directory",
            version: 1,
            exportedAt: Date(),
            users: snapshot.users.map(AdminUserExportRecord.init(user:)),
            groups: snapshot.groups.map(AdminGroupExportRecord.init(group:))
        )
        return try JSONEncoder.openWebUIEncoder.encode(bundle)
    }

    func snapshot(fromJSONData data: Data) throws -> AdminDirectorySnapshot {
        let decoder = JSONDecoder.openWebUIDecoder
        if let bundle = try? decoder.decode(AdminDirectoryExportBundle.self, from: data) {
            return normalizedSnapshot(bundle.snapshot)
        }
        if let snapshot = try? decoder.decode(AdminDirectorySnapshot.self, from: data) {
            return normalizedSnapshot(snapshot)
        }
        if let users = try? decoder.decode([AdminUserExportRecord].self, from: data) {
            return normalizedSnapshot(AdminDirectorySnapshot(users: users.compactMap(\.adminUser), groups: []))
        }
        if let scimList = try? decoder.decode(SCIMListResponse.self, from: data) {
            return normalizedSnapshot(scimList.snapshot)
        }
        return try normalizedSnapshot(decoder.decode(AdminDirectorySnapshot.self, from: data))
    }

    private func normalizedSnapshot(_ snapshot: AdminDirectorySnapshot) -> AdminDirectorySnapshot {
        let users = normalizedUsers(snapshot.users)
        let validUserIDs = Set(users.map(\.id))
        let groups = normalizedGroups(snapshot.groups, validUserIDs: validUserIDs)
        return AdminDirectorySnapshot(users: users, groups: groups)
    }

    private func normalizedUsers(_ users: [AdminUser]) -> [AdminUser] {
        var usersByKey: [String: AdminUser] = [:]
        for user in users {
            let name = user.name.trimmingCharacters(in: .whitespacesAndNewlines)
            let email = user.email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !name.isEmpty, !email.isEmpty else {
                continue
            }

            var normalizedUser = user
            normalizedUser.name = name
            normalizedUser.email = email
            usersByKey[email] = normalizedUser
        }
        return Array(usersByKey.values)
    }

    private func normalizedGroups(_ groups: [AdminGroup], validUserIDs: Set<String>) -> [AdminGroup] {
        var groupsByKey: [String: AdminGroup] = [:]
        for group in groups {
            let name = group.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else {
                continue
            }

            var normalizedGroup = group
            normalizedGroup.name = name
            normalizedGroup.description = group.description.trimmingCharacters(in: .whitespacesAndNewlines)
            normalizedGroup.permissions = AdminGroup.normalizedPermissions(group.permissions)
            normalizedGroup.memberIDs = AdminGroup.normalizedMemberIDs(group.memberIDs, validUserIDs: validUserIDs)
            groupsByKey[normalizedGroup.id] = normalizedGroup
        }
        return Array(groupsByKey.values)
    }
}

private struct SCIMListResponse: Codable {
    var resources: [SCIMResource]

    enum CodingKeys: String, CodingKey {
        case resources = "Resources"
    }

    var snapshot: AdminDirectorySnapshot {
        let users = resources.compactMap(\.adminUser)
        let validUserIDs = Set(users.map(\.id))
        var groupsByID: [String: AdminGroup] = [:]

        for group in resources.compactMap({ $0.adminGroup(validUserIDs: validUserIDs) }) {
            groupsByID[group.id] = group
        }

        for group in resources.flatMap({ $0.adminGroupsFromUserMemberships(validUserIDs: validUserIDs) }) {
            if var existingGroup = groupsByID[group.id] {
                existingGroup.memberIDs = AdminGroup.normalizedMemberIDs(
                    existingGroup.memberIDs + group.memberIDs,
                    validUserIDs: validUserIDs
                )
                groupsByID[group.id] = existingGroup
            } else {
                groupsByID[group.id] = group
            }
        }

        let groups = Array(groupsByID.values)
        return AdminDirectorySnapshot(users: users, groups: groups)
    }
}

private struct SCIMResource: Codable {
    var schemas: [String]?
    var id: String?
    var userName: String?
    var name: SCIMName?
    var emails: [SCIMEmail]?
    var active: Bool?
    var roles: [SCIMRole]?
    var userType: String?
    var displayName: String?
    var members: [SCIMMember]?
    var groups: [SCIMMember]?
    var entitlements: [SCIMEntitlement]?
    var nativePermissions: JSONValue?

    enum CodingKeys: String, CodingKey {
        case schemas
        case id
        case userName
        case name
        case emails
        case active
        case roles
        case userType
        case displayName
        case members
        case groups
        case entitlements
        case nativePermissions = "urn:open-webui:native:permissions"
    }

    var adminUser: AdminUser? {
        guard isUser else {
            return nil
        }

        let email = primaryEmail ?? userName
        let normalizedEmail = email?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let displayName = userDisplayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let normalizedEmail, !normalizedEmail.isEmpty, !displayName.isEmpty else {
            return nil
        }

        return AdminUser(
            id: id ?? UUID().uuidString,
            name: displayName,
            email: normalizedEmail,
            role: importedRole
        )
    }

    func adminGroup(validUserIDs: Set<String>) -> AdminGroup? {
        guard isGroup else {
            return nil
        }

        let trimmedName = displayName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmedName.isEmpty else {
            return nil
        }

        return AdminGroup(
            id: id ?? UUID().uuidString,
            name: trimmedName,
            description: "",
            permissions: AdminGroup.normalizedPermissions(
                Self.permissions(from: nativePermissions) + Self.permissions(fromEntitlements: entitlements)
            ),
            memberIDs: AdminGroup.normalizedMemberIDs(members?.map(\.value) ?? [], validUserIDs: validUserIDs)
        )
    }

    func adminGroupsFromUserMemberships(validUserIDs: Set<String>) -> [AdminGroup] {
        guard isUser, let userID = id, validUserIDs.contains(userID) else {
            return []
        }

        return groups?.compactMap { group in
            let groupID = group.value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !groupID.isEmpty else {
                return nil
            }

            let displayName = group.display?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return AdminGroup(
                id: groupID,
                name: displayName.isEmpty ? groupID : displayName,
                description: "",
                memberIDs: [userID]
            )
        } ?? []
    }

    private var isUser: Bool {
        hasSchemaSuffix("User") || userName != nil || emails?.isEmpty == false
    }

    private var isGroup: Bool {
        hasSchemaSuffix("Group") || displayName != nil || members?.isEmpty == false
    }

    private var primaryEmail: String? {
        let trimmedEmails = emails?.map { email in
            SCIMEmail(value: email.value.trimmingCharacters(in: .whitespacesAndNewlines), primary: email.primary)
        } ?? []
        return trimmedEmails.first { $0.primary == true && !$0.value.isEmpty }?.value
            ?? trimmedEmails.first { !$0.value.isEmpty }?.value
    }

    private var userDisplayName: String {
        if let formatted = name?.formatted?.trimmingCharacters(in: .whitespacesAndNewlines), !formatted.isEmpty {
            return formatted
        }

        let parts = [name?.givenName, name?.familyName]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        if !parts.isEmpty {
            return parts.joined(separator: " ")
        }

        return userName ?? primaryEmail ?? ""
    }

    private var importedRole: AdminUserRole {
        if active == false {
            return .pending
        }

        for roleName in roleCandidates {
            if let role = adminRole(from: roleName) {
                return role
            }
        }
        return .user
    }

    private var roleCandidates: [String] {
        var candidates: [String] = []
        if let userType {
            candidates.append(userType)
        }
        for role in roles ?? [] {
            candidates.append(role.value)
            if let display = role.display {
                candidates.append(display)
            }
        }
        return candidates
    }

    private func adminRole(from value: String) -> AdminUserRole? {
        let normalizedValue = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "_", with: "-")
            .replacingOccurrences(of: " ", with: "-")

        switch normalizedValue {
        case "admin", "administrator", "owner", "workspace-admin", "super-admin":
            return .admin
        case "user", "member", "standard-user":
            return .user
        case "pending", "inactive", "suspended", "disabled":
            return .pending
        default:
            return nil
        }
    }

    private func hasSchemaSuffix(_ suffix: String) -> Bool {
        schemas?.contains { schema in
            schema.split(separator: ":").last?.caseInsensitiveCompare(suffix) == .orderedSame
        } ?? false
    }

    private static func permissions(from value: JSONValue?) -> [String] {
        guard let value else {
            return []
        }
        switch value {
        case .string(let permission):
            return [permission]
        case .array(let values):
            return values.flatMap { permissions(from: $0) }
        case .object(let object):
            return flattenedPermissions(from: object)
        case .bool(let isEnabled):
            return isEnabled ? ["enabled"] : []
        case .number, .null:
            return []
        }
    }

    private static func permissions(fromEntitlements entitlements: [SCIMEntitlement]?) -> [String] {
        entitlements?.map(\.value)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty } ?? []
    }

    private static func flattenedPermissions(from object: [String: JSONValue], prefix: String? = nil) -> [String] {
        var flattened: [String] = []
        for key in object.keys.sorted() {
            let path = [prefix, key].compactMap { $0 }.joined(separator: ".")
            switch object[key] {
            case .bool(let isEnabled):
                if isEnabled {
                    flattened.append(path)
                }
            case .object(let child):
                flattened.append(contentsOf: flattenedPermissions(from: child, prefix: path))
            case .array(let values):
                flattened.append(contentsOf: values.flatMap { permissions(from: $0) })
            case .string(let permission):
                flattened.append(permission)
            case .number, .null, .none:
                break
            }
        }
        return flattened
    }
}

private struct SCIMName: Codable {
    var formatted: String?
    var givenName: String?
    var familyName: String?
}

private struct SCIMEmail: Codable {
    var value: String
    var primary: Bool?
}

private struct SCIMRole: Codable {
    var value: String
    var display: String?
    var primary: Bool?
}

private struct SCIMEntitlement: Codable {
    var value: String
    var display: String?
}

private struct SCIMMember: Codable {
    var value: String
    var display: String?
}

private struct AdminDirectoryExportBundle: Codable {
    var format: String?
    var version: Int?
    var exportedAt: Date?
    var users: [AdminUserExportRecord]
    var groups: [AdminGroupExportRecord]

    enum CodingKeys: String, CodingKey {
        case format
        case version
        case exportedAt
        case users
        case groups
    }

    var snapshot: AdminDirectorySnapshot {
        let users = self.users.compactMap(\.adminUser)
        let validUserIDs = Set(users.map(\.id))
        let groups = self.groups.compactMap { $0.adminGroup(validUserIDs: validUserIDs) }
        return AdminDirectorySnapshot(users: users, groups: groups)
    }
}

private struct AdminUserExportRecord: Codable {
    var id: String?
    var email: String
    var username: String?
    var role: String?
    var name: String
    var createdAt: Date?
    var updatedAt: Date?
    var lastActiveAt: Date?
    var createdAtUnix: Int?
    var updatedAtUnix: Int?
    var lastActiveAtUnix: Int?

    enum CodingKeys: String, CodingKey {
        case id
        case email
        case username
        case role
        case name
        case createdAt
        case updatedAt
        case lastActiveAt
        case createdAtUnix = "created_at"
        case updatedAtUnix = "updated_at"
        case lastActiveAtUnix = "last_active_at"
    }

    init(user: AdminUser) {
        id = user.id
        email = user.email
        username = nil
        role = user.role.rawValue
        name = user.name
        createdAt = user.createdAt
        updatedAt = user.updatedAt
        lastActiveAt = user.lastActiveAt
        createdAtUnix = nil
        updatedAtUnix = nil
        lastActiveAtUnix = nil
    }

    var adminUser: AdminUser? {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmedName.isEmpty, !normalizedEmail.isEmpty else {
            return nil
        }

        return AdminUser(
            id: id ?? UUID().uuidString,
            name: trimmedName,
            email: normalizedEmail,
            role: role.flatMap(AdminUserRole.init(rawValue:)) ?? .pending,
            createdAt: createdAt ?? createdAtUnix.map { Date(timeIntervalSince1970: TimeInterval($0)) } ?? Date(),
            updatedAt: updatedAt ?? updatedAtUnix.map { Date(timeIntervalSince1970: TimeInterval($0)) } ?? Date(),
            lastActiveAt: lastActiveAt ?? lastActiveAtUnix.map { Date(timeIntervalSince1970: TimeInterval($0)) }
        )
    }
}

private struct AdminGroupExportRecord: Codable {
    var id: String?
    var userID: String?
    var name: String
    var description: String?
    var data: JSONValue?
    var meta: JSONValue?
    var permissions: JSONValue?
    var userIDs: [String]?
    var memberIDs: [String]?
    var createdAt: Date?
    var updatedAt: Date?
    var createdAtUnix: Int?
    var updatedAtUnix: Int?

    enum CodingKeys: String, CodingKey {
        case id
        case userID = "user_id"
        case name
        case description
        case data
        case meta
        case permissions
        case userIDs = "user_ids"
        case memberIDs = "member_ids"
        case createdAt
        case updatedAt
        case createdAtUnix = "created_at"
        case updatedAtUnix = "updated_at"
    }

    init(group: AdminGroup) {
        id = group.id
        userID = nil
        name = group.name
        description = group.description
        data = nil
        meta = nil
        permissions = Self.permissionsObject(from: group.permissions)
        userIDs = group.memberIDs
        memberIDs = group.memberIDs
        createdAt = group.createdAt
        updatedAt = group.updatedAt
        createdAtUnix = nil
        updatedAtUnix = nil
    }

    func adminGroup(validUserIDs: Set<String>) -> AdminGroup? {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            return nil
        }

        return AdminGroup(
            id: id ?? UUID().uuidString,
            name: trimmedName,
            description: description?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
            permissions: AdminGroup.normalizedPermissions(Self.permissions(from: permissions)),
            memberIDs: AdminGroup.normalizedMemberIDs(userIDs ?? memberIDs ?? [], validUserIDs: validUserIDs),
            createdAt: createdAt ?? createdAtUnix.map { Date(timeIntervalSince1970: TimeInterval($0)) } ?? Date(),
            updatedAt: updatedAt ?? updatedAtUnix.map { Date(timeIntervalSince1970: TimeInterval($0)) } ?? Date()
        )
    }

    private static func permissions(from value: JSONValue?) -> [String] {
        guard let value else {
            return []
        }
        switch value {
        case .string(let permission):
            return [permission]
        case .array(let values):
            return values.flatMap { permissions(from: $0) }
        case .object(let object):
            return flattenedPermissions(from: object)
        case .bool(let isEnabled):
            return isEnabled ? ["enabled"] : []
        case .number, .null:
            return []
        }
    }

    private static func flattenedPermissions(from object: [String: JSONValue], prefix: String? = nil) -> [String] {
        var flattened: [String] = []
        for key in object.keys.sorted() {
            let path = [prefix, key].compactMap { $0 }.joined(separator: ".")
            switch object[key] {
            case .bool(let isEnabled):
                if isEnabled {
                    flattened.append(path)
                }
            case .object(let child):
                flattened.append(contentsOf: flattenedPermissions(from: child, prefix: path))
            case .array(let values):
                flattened.append(contentsOf: values.flatMap { permissions(from: $0) })
            case .string(let permission):
                flattened.append(permission)
            case .number, .null, .none:
                break
            }
        }
        return flattened
    }

    private static func permissionsObject(from permissions: [String]) -> JSONValue {
        var object: [String: JSONValue] = [:]
        for permission in AdminGroup.normalizedPermissions(permissions) {
            insert(permission: permission, into: &object)
        }
        return .object(object)
    }

    private static func insert(permission: String, into object: inout [String: JSONValue]) {
        let parts = permission.split(separator: ".").map(String.init)
        guard !parts.isEmpty else {
            return
        }
        insert(parts: parts, into: &object)
    }

    private static func insert(parts: [String], into object: inout [String: JSONValue]) {
        guard let first = parts.first else {
            return
        }
        if parts.count == 1 {
            object[first] = .bool(true)
            return
        }

        var child = object[first]?.objectValue ?? [:]
        insert(parts: Array(parts.dropFirst()), into: &child)
        object[first] = .object(child)
    }
}
