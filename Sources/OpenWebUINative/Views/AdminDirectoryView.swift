import SwiftUI

struct AdminDirectoryView: View {
    @ObservedObject var store: AppStore
    @State private var editorMode: AdminDirectoryEditorMode?

    var body: some View {
        DisclosureGroup {
            if store.adminUsers.isEmpty {
                Text("No users")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(store.adminUsers) { user in
                    AdminUserRow(
                        user: user,
                        canManage: store.currentUserCanManageAdminDirectory,
                        onEdit: {
                            editorMode = .editUser(user)
                        },
                        onDelete: {
                            Task {
                                await store.deleteAdminUser(user.id)
                            }
                        }
                    )
                }
            }
        } label: {
            Label("Users", systemImage: "person.2")
        }

        DisclosureGroup {
            if store.adminGroups.isEmpty {
                Text("No groups")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(store.adminGroups) { group in
                    AdminGroupRow(
                        group: group,
                        users: store.adminUsers,
                        canManage: store.currentUserCanManageAdminDirectory,
                        onEdit: {
                            editorMode = .editGroup(group)
                        },
                        onDelete: {
                            Task {
                                await store.deleteAdminGroup(group.id)
                            }
                        }
                    )
                }
            }
        } label: {
            Label("Groups", systemImage: "person.3")
        }

        HStack {
            Button {
                editorMode = .createUser
            } label: {
                Label("New User", systemImage: "person.badge.plus")
            }
            .help("New user")
            .disabled(!store.currentUserCanManageAdminDirectory)

            Button {
                editorMode = .createGroup
            } label: {
                Label("New Group", systemImage: "person.3.sequence")
            }
            .help("New group")
            .disabled(!store.currentUserCanManageAdminDirectory)

            Button {
                store.importAdminDirectoryJSONWithOpenPanel()
            } label: {
                Label("Import Admin Directory", systemImage: "square.and.arrow.down")
            }
            .help("Import admin directory")
            .disabled(!store.currentUserCanManageAdminDirectory)

            Button {
                store.exportAdminDirectoryJSONWithSavePanel()
            } label: {
                Label("Export Admin Directory", systemImage: "square.and.arrow.up")
            }
            .help("Export admin directory")
            .disabled(!store.currentUserCanManageAdminDirectory || (store.adminUsers.isEmpty && store.adminGroups.isEmpty))
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.borderless)
        .font(.caption)
        .sheet(item: $editorMode) { mode in
            switch mode {
            case .createUser, .editUser:
                AdminUserEditorSheet(
                    mode: mode,
                    onSave: { name, email, role in
                        Task {
                            switch mode {
                            case .createUser:
                                await store.createAdminUser(name: name, email: email, role: role)
                            case .editUser(let user):
                                await store.updateAdminUser(user.id, name: name, email: email, role: role)
                            case .createGroup, .editGroup:
                                break
                            }
                            editorMode = nil
                        }
                    },
                    onCancel: {
                        editorMode = nil
                    }
                )
            case .createGroup, .editGroup:
                AdminGroupEditorSheet(
                    mode: mode,
                    users: store.adminUsers,
                    onSave: { name, description, permissions, memberIDs in
                        Task {
                            switch mode {
                            case .createGroup:
                                await store.createAdminGroup(
                                    name: name,
                                    description: description,
                                    permissions: permissions
                                )
                                if let group = store.adminGroups.first {
                                    await store.setAdminGroupMembers(group.id, memberIDs: memberIDs)
                                }
                            case .editGroup(let group):
                                await store.updateAdminGroup(
                                    group.id,
                                    name: name,
                                    description: description,
                                    permissions: permissions,
                                    memberIDs: memberIDs
                                )
                            case .createUser, .editUser:
                                break
                            }
                            editorMode = nil
                        }
                    },
                    onCancel: {
                        editorMode = nil
                    }
                )
            }
        }
    }
}

private struct AdminUserRow: View {
    var user: AdminUser
    var canManage: Bool
    var onEdit: () -> Void
    var onDelete: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Label(user.name, systemImage: roleIcon)
                .lineLimit(1)

            Spacer()

            Text(user.role.label)
                .font(.caption)
                .foregroundStyle(.secondary)

            Menu {
                Button("Edit...") {
                    onEdit()
                }
                Divider()
                Button("Delete User", role: .destructive) {
                    onDelete()
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .help("User actions")
            .disabled(!canManage)
        }
        .help(user.email)
    }

    private var roleIcon: String {
        switch user.role {
        case .admin:
            return "person.badge.key"
        case .user:
            return "person"
        case .pending:
            return "person.crop.circle.badge.clock"
        }
    }
}

private struct AdminGroupRow: View {
    var group: AdminGroup
    var users: [AdminUser]
    var canManage: Bool
    var onEdit: () -> Void
    var onDelete: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Label(group.name, systemImage: "person.3")
                .lineLimit(1)

            Spacer()

            Text("\(group.memberIDs.count)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .help("Members")

            Menu {
                Button("Edit...") {
                    onEdit()
                }
                Divider()
                Button("Delete Group", role: .destructive) {
                    onDelete()
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .help("Group actions")
            .disabled(!canManage)
        }
        .help(helpText)
    }

    private var helpText: String {
        let permissions = group.permissions.isEmpty ? "No permissions" : group.permissions.joined(separator: ", ")
        return "\(group.description)\n\(permissions)"
    }
}

private struct AdminUserEditorSheet: View {
    var mode: AdminDirectoryEditorMode
    var onSave: (String, String, AdminUserRole) -> Void
    var onCancel: () -> Void

    @State private var name: String
    @State private var email: String
    @State private var role: AdminUserRole

    init(
        mode: AdminDirectoryEditorMode,
        onSave: @escaping (String, String, AdminUserRole) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.mode = mode
        self.onSave = onSave
        self.onCancel = onCancel
        if case .editUser(let user) = mode {
            _name = State(initialValue: user.name)
            _email = State(initialValue: user.email)
            _role = State(initialValue: user.role)
        } else {
            _name = State(initialValue: "")
            _email = State(initialValue: "")
            _role = State(initialValue: .pending)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(mode.title)
                .font(.title3.weight(.semibold))

            TextField("Name", text: $name)
                .textFieldStyle(.roundedBorder)

            TextField("Email", text: $email)
                .textFieldStyle(.roundedBorder)

            Picker("Role", selection: $role) {
                ForEach(AdminUserRole.allCases, id: \.self) { role in
                    Text(role.label).tag(role)
                }
            }
            .pickerStyle(.segmented)

            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                Button("Save") {
                    onSave(name, email, role)
                }
                .buttonStyle(.borderedProminent)
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    || email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(18)
        .frame(width: 420)
    }
}

private struct AdminGroupEditorSheet: View {
    var mode: AdminDirectoryEditorMode
    var users: [AdminUser]
    var onSave: (String, String, [String], [String]) -> Void
    var onCancel: () -> Void

    @State private var name: String
    @State private var description: String
    @State private var permissionsText: String
    @State private var memberIDs: Set<String>

    init(
        mode: AdminDirectoryEditorMode,
        users: [AdminUser],
        onSave: @escaping (String, String, [String], [String]) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.mode = mode
        self.users = users
        self.onSave = onSave
        self.onCancel = onCancel
        if case .editGroup(let group) = mode {
            _name = State(initialValue: group.name)
            _description = State(initialValue: group.description)
            _permissionsText = State(initialValue: group.permissions.joined(separator: ", "))
            _memberIDs = State(initialValue: Set(group.memberIDs))
        } else {
            _name = State(initialValue: "")
            _description = State(initialValue: "")
            _permissionsText = State(initialValue: "")
            _memberIDs = State(initialValue: [])
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(mode.title)
                .font(.title3.weight(.semibold))

            TextField("Name", text: $name)
                .textFieldStyle(.roundedBorder)

            TextField("Description", text: $description)
                .textFieldStyle(.roundedBorder)

            TextField("Permissions", text: $permissionsText)
                .textFieldStyle(.roundedBorder)

            VStack(alignment: .leading, spacing: 8) {
                Text("Members")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                if users.isEmpty {
                    Text("No users")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(users) { user in
                        Toggle(isOn: memberBinding(for: user.id)) {
                            Text(user.name)
                                .lineLimit(1)
                        }
                    }
                }
            }

            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                Button("Save") {
                    onSave(name, description, parsedPermissions, Array(memberIDs))
                }
                .buttonStyle(.borderedProminent)
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(18)
        .frame(width: 460)
    }

    private var parsedPermissions: [String] {
        permissionsText
            .split(separator: ",")
            .map { String($0) }
    }

    private func memberBinding(for userID: String) -> Binding<Bool> {
        Binding {
            memberIDs.contains(userID)
        } set: { isMember in
            if isMember {
                memberIDs.insert(userID)
            } else {
                memberIDs.remove(userID)
            }
        }
    }
}

private enum AdminDirectoryEditorMode: Identifiable {
    case createUser
    case editUser(AdminUser)
    case createGroup
    case editGroup(AdminGroup)

    var id: String {
        switch self {
        case .createUser:
            return "create-user"
        case .editUser(let user):
            return "edit-user-\(user.id)"
        case .createGroup:
            return "create-group"
        case .editGroup(let group):
            return "edit-group-\(group.id)"
        }
    }

    var title: String {
        switch self {
        case .createUser:
            return "New User"
        case .editUser:
            return "Edit User"
        case .createGroup:
            return "New Group"
        case .editGroup:
            return "Edit Group"
        }
    }
}
