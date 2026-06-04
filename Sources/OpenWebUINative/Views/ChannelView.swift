import SwiftUI

struct ChannelLibraryView: View {
    @ObservedObject var store: AppStore
    @State private var editorMode: ChannelEditorMode?

    var body: some View {
        let canManageChannels = store.currentUserCanManageChannels

        if !store.channels.isEmpty {
            TextField("Search channels", text: $store.channelSearchText)
                .textFieldStyle(.roundedBorder)
        }

        let filteredChannels = store.filteredChannels()
        if store.channels.isEmpty {
            Text("No channels")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else if filteredChannels.isEmpty {
            Text("No matching channels")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else {
            ForEach(filteredChannels) { channel in
                ChannelRow(
                    channel: channel,
                    isSelected: store.selectedChannelID == channel.id,
                    canManageChannels: canManageChannels,
                    onSelect: {
                        Task {
                            await store.selectChannel(channel.id)
                        }
                    },
                    onEdit: {
                        editorMode = .edit(channel)
                    },
                    onDelete: {
                        Task {
                            await store.deleteChannel(channel.id)
                        }
                    }
                )
            }
        }

        SidebarActionStrip {
            SidebarActionButton(title: "New Channel", systemImage: "number", isDisabled: !canManageChannels) {
                editorMode = .create
            }

            SidebarActionButton(title: "Import Channels", systemImage: "square.and.arrow.down", isDisabled: !canManageChannels) {
                store.importChannelsJSONWithOpenPanel()
            }

            SidebarActionMenu(title: "Export Channels", systemImage: "square.and.arrow.up", isDisabled: store.channels.isEmpty) {
                Button("Native JSON") {
                    store.exportChannelsJSONWithSavePanel()
                }

                Button("Open WebUI JSON") {
                    store.exportChannelsOpenWebUIJSONWithSavePanel()
                }
            }
        }
        .sheet(item: $editorMode) { mode in
            ChannelEditorSheet(
                mode: mode,
                onSave: { name, description in
                    Task {
                        switch mode {
                        case .create:
                            await store.createChannel(name: name, description: description)
                        case .edit(let channel):
                            await store.updateChannel(channel.id, name: name, description: description)
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

struct ChannelDetailView: View {
    @ObservedObject var store: AppStore
    var channel: AppChannel

    @State private var draftMessage = ""

    var body: some View {
        let canManageChannels = store.currentUserCanManageChannels

        VStack(spacing: 0) {
            ChannelHeader(store: store, channel: channel, canManageChannels: canManageChannels)

            Divider()

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    if channel.messages.isEmpty {
                        ContentUnavailableView(
                            "No Messages",
                            systemImage: "number",
                            description: Text("Start the channel conversation below.")
                        )
                        .frame(maxWidth: .infinity, minHeight: 260)
                    } else {
                        ForEach(channel.messages) { message in
                            ChannelMessageBubble(
                                store: store,
                                channelID: channel.id,
                                message: message,
                                canManageChannels: canManageChannels
                            )
                        }
                    }
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Divider()

            HStack(alignment: .bottom, spacing: 10) {
                TextEditor(text: $draftMessage)
                    .font(.body)
                    .frame(minHeight: 54, maxHeight: 120)
                    .overlay {
                        RoundedRectangle(cornerRadius: 5)
                            .stroke(.quaternary)
                    }
                    .disabled(!canManageChannels)

                Button {
                    let message = draftMessage
                    draftMessage = ""
                    Task {
                        await store.postChannelMessage(channel.id, content: message)
                    }
                } label: {
                    Label("Send", systemImage: "paperplane.fill")
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!canManageChannels || draftMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding()
        }
        .navigationTitle(channel.name)
    }
}

private struct ChannelRow: View {
    var channel: AppChannel
    var isSelected: Bool
    var canManageChannels: Bool
    var onSelect: () -> Void
    var onEdit: () -> Void
    var onDelete: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Button {
                onSelect()
            } label: {
                Label(channel.name, systemImage: "number")
                    .lineLimit(1)
            }
            .buttonStyle(.plain)
            .fontWeight(isSelected ? .semibold : .regular)

            Spacer()

            if channel.unreadCount > 0 {
                Text("\(channel.unreadCount)")
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .monospacedDigit()
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.tint.opacity(0.18), in: Capsule())
                    .help("Unread messages")
            }

            Menu {
                Button("Edit...") {
                    onEdit()
                }
                Divider()
                Button("Delete Channel", role: .destructive) {
                    onDelete()
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .disabled(!canManageChannels)
            .help("Channel actions")
        }
        .contextMenu {
            Button("Edit...") {
                onEdit()
            }
            .disabled(!canManageChannels)
            Divider()
            Button("Delete Channel", role: .destructive) {
                onDelete()
            }
            .disabled(!canManageChannels)
        }
    }
}

private struct ChannelHeader: View {
    @ObservedObject var store: AppStore
    var channel: AppChannel
    var canManageChannels: Bool

    @State private var isAddingMember = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(channel.name, systemImage: "number")
                    .font(.title2)
                    .fontWeight(.semibold)
                Spacer()
                Text("\(channel.messages.count) messages")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let description = channel.description, !description.isEmpty {
                Text(description)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        Label("\(channel.members.count) members", systemImage: "person.2")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button {
                            isAddingMember = true
                        } label: {
                            Label("Add Member", systemImage: "person.badge.plus")
                        }
                        .labelStyle(.iconOnly)
                        .buttonStyle(.borderless)
                        .disabled(!canManageChannels)
                        .help("Add channel member")
                    }

                    if channel.members.isEmpty {
                        Text("No members")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    } else {
                        ForEach(channel.members) { member in
                            ChannelMemberRow(
                                member: member,
                                canManageChannels: canManageChannels,
                                onUpdate: { role, status, isMuted, isPinned in
                                    Task {
                                        await store.updateChannelMember(
                                            member.id,
                                            in: channel.id,
                                            role: role,
                                            status: status,
                                            isMuted: isMuted,
                                            isPinned: isPinned
                                        )
                                    }
                                },
                                onRemove: {
                                    Task {
                                        await store.removeChannelMember(member.id, from: channel.id)
                                    }
                                }
                            )
                        }
                    }
                }
                .frame(maxWidth: 360)
            }
        }
        .padding()
        .sheet(isPresented: $isAddingMember) {
            ChannelMemberEditorSheet(
                onSave: { userID, displayName, role in
                    Task {
                        await store.addChannelMember(
                            channel.id,
                            userID: userID,
                            displayName: displayName,
                            role: role
                        )
                        isAddingMember = false
                    }
                },
                onCancel: {
                    isAddingMember = false
                }
            )
        }
    }
}

private struct ChannelMemberRow: View {
    var member: ChannelMember
    var canManageChannels: Bool
    var onUpdate: (ChannelMemberRole, ChannelMemberStatus, Bool, Bool) -> Void
    var onRemove: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(member.displayName)
                    .font(.caption)
                    .fontWeight(.medium)
                    .lineLimit(1)
                Text("\(member.role.label) · \(member.status.label)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            if member.isPinned {
                Image(systemName: "pin.fill")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .help("Pinned")
            }

            if member.isMuted {
                Image(systemName: "bell.slash")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .help("Muted")
            }

            Menu {
                Picker("Role", selection: roleBinding) {
                    ForEach(ChannelMemberRole.allCases, id: \.self) { role in
                        Text(role.label).tag(role)
                    }
                }

                Picker("Status", selection: statusBinding) {
                    ForEach(ChannelMemberStatus.allCases, id: \.self) { status in
                        Text(status.label).tag(status)
                    }
                }

                Divider()

                Toggle("Muted", isOn: mutedBinding)
                Toggle("Pinned", isOn: pinnedBinding)

                Divider()

                Button("Remove Member", role: .destructive) {
                    onRemove()
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .disabled(!canManageChannels)
            .help("Member actions")
        }
    }

    private var roleBinding: Binding<ChannelMemberRole> {
        Binding(
            get: { member.role },
            set: { onUpdate($0, member.status, member.isMuted, member.isPinned) }
        )
    }

    private var statusBinding: Binding<ChannelMemberStatus> {
        Binding(
            get: { member.status },
            set: { onUpdate(member.role, $0, member.isMuted, member.isPinned) }
        )
    }

    private var mutedBinding: Binding<Bool> {
        Binding(
            get: { member.isMuted },
            set: { onUpdate(member.role, member.status, $0, member.isPinned) }
        )
    }

    private var pinnedBinding: Binding<Bool> {
        Binding(
            get: { member.isPinned },
            set: { onUpdate(member.role, member.status, member.isMuted, $0) }
        )
    }
}

private struct ChannelMemberEditorSheet: View {
    var onSave: (String, String, ChannelMemberRole) -> Void
    var onCancel: () -> Void

    @State private var userID = ""
    @State private var displayName = ""
    @State private var role: ChannelMemberRole = .member

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Add Member")
                .font(.title3)
                .fontWeight(.semibold)

            TextField("User ID", text: $userID)
                .textFieldStyle(.roundedBorder)

            TextField("Display name", text: $displayName)
                .textFieldStyle(.roundedBorder)

            Picker("Role", selection: $role) {
                ForEach(ChannelMemberRole.allCases, id: \.self) { role in
                    Text(role.label).tag(role)
                }
            }
            .pickerStyle(.segmented)

            HStack {
                Spacer()
                Button("Cancel") {
                    onCancel()
                }
                Button("Add") {
                    onSave(userID, displayName, role)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(userID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    || displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .frame(minWidth: 420)
    }
}

private struct ChannelMessageBubble: View {
    @ObservedObject var store: AppStore
    var channelID: UUID
    var message: ChannelMessage
    var canManageChannels: Bool

    @State private var isReplying = false
    @State private var replyDraft = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(message.authorName)
                    .font(.caption)
                    .fontWeight(.semibold)
                Text(message.createdAt, style: .time)
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                Spacer()

                Button {
                    isReplying = true
                } label: {
                    Label("Reply", systemImage: "arrowshape.turn.up.left")
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .disabled(!canManageChannels)
                .help("Reply in thread")
            }

            Text(message.content)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)

            if !message.replies.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(message.replies) { reply in
                        ChannelReplyRow(reply: reply)
                    }
                }
                .padding(.leading, 14)
                .overlay(alignment: .leading) {
                    Rectangle()
                        .fill(.quaternary)
                        .frame(width: 2)
                }
            }
        }
        .padding(10)
        .background(.quinary, in: RoundedRectangle(cornerRadius: 6))
        .sheet(isPresented: $isReplying) {
            VStack(alignment: .leading, spacing: 14) {
                Text("Reply")
                    .font(.title3)
                    .fontWeight(.semibold)

                Text(message.content)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)

                TextEditor(text: $replyDraft)
                    .font(.body)
                    .frame(minHeight: 140)
                    .overlay {
                        RoundedRectangle(cornerRadius: 5)
                            .stroke(.quaternary)
                    }
                    .disabled(!canManageChannels)

                HStack {
                    Spacer()
                    Button("Cancel") {
                        replyDraft = ""
                        isReplying = false
                    }
                    Button("Send Reply") {
                        let reply = replyDraft
                        replyDraft = ""
                        isReplying = false
                        Task {
                            await store.postChannelReply(channelID, to: message.id, content: reply)
                        }
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canManageChannels || replyDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .padding(20)
            .frame(minWidth: 460, minHeight: 300)
        }
    }
}

private struct ChannelReplyRow: View {
    var reply: ChannelReply

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 8) {
                Text(reply.authorName)
                    .font(.caption2)
                    .fontWeight(.semibold)
                Text(reply.createdAt, style: .time)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Text(reply.content)
                .font(.callout)
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct ChannelEditorSheet: View {
    var mode: ChannelEditorMode
    var onSave: (String, String?) -> Void
    var onCancel: () -> Void

    @State private var name: String
    @State private var description: String

    init(mode: ChannelEditorMode, onSave: @escaping (String, String?) -> Void, onCancel: @escaping () -> Void) {
        self.mode = mode
        self.onSave = onSave
        self.onCancel = onCancel
        switch mode {
        case .create:
            _name = State(initialValue: "")
            _description = State(initialValue: "")
        case .edit(let channel):
            _name = State(initialValue: channel.name)
            _description = State(initialValue: channel.description ?? "")
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(mode.title)
                .font(.title3)
                .fontWeight(.semibold)

            TextField("Name", text: $name)
                .textFieldStyle(.roundedBorder)

            TextField("Description", text: $description)
                .textFieldStyle(.roundedBorder)

            HStack {
                Spacer()
                Button("Cancel") {
                    onCancel()
                }
                Button("Save") {
                    onSave(name, description)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .frame(minWidth: 420)
    }
}

private enum ChannelEditorMode: Identifiable {
    case create
    case edit(AppChannel)

    var id: String {
        switch self {
        case .create:
            return "create"
        case .edit(let channel):
            return channel.id.uuidString
        }
    }

    var title: String {
        switch self {
        case .create:
            return "New Channel"
        case .edit:
            return "Edit Channel"
        }
    }
}
