import SwiftUI

struct SkillLibraryView: View {
    @ObservedObject var store: AppStore
    @State private var editorMode: SkillEditorMode?

    var body: some View {
        let filteredSkills = store.filteredSkills()

        if store.skills.isEmpty {
            Text("No skills")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else {
            TextField("Search skills", text: $store.skillSearchText)
                .textFieldStyle(.roundedBorder)
                .font(.caption)

            if filteredSkills.isEmpty {
                Text("No matching skills")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ForEach(filteredSkills) { skill in
                SkillRow(
                    skill: skill,
                    canManageSkills: store.currentUserCanManageSkills,
                    onEdit: {
                        editorMode = .edit(skill)
                    },
                    onShare: {
                        store.shareSkill(skill.id)
                    },
                    onDelete: {
                        Task {
                            await store.deleteSkill(skill.id)
                        }
                    }
                )
            }
        }

        SidebarActionStrip {
            SidebarActionButton(title: "New Skill", systemImage: "sparkles", isDisabled: !store.currentUserCanManageSkills) {
                editorMode = .create
            }

            SidebarActionButton(title: "Import Skills", systemImage: "square.and.arrow.down", isDisabled: !store.currentUserCanManageSkills) {
                store.importSkillsJSONWithOpenPanel()
            }

            SidebarActionMenu(title: "Export Skills", systemImage: "square.and.arrow.up", isDisabled: store.skills.isEmpty) {
                Button("Native JSON") {
                    store.exportSkillsJSONWithSavePanel()
                }

                Button("Open WebUI JSON") {
                    store.exportSkillsOpenWebUIJSONWithSavePanel()
                }
            }
        }
        .sheet(item: $editorMode) { mode in
            SkillEditorSheet(
                mode: mode,
                onSave: { name, description, tags, allowedUserIDs, allowedGroupIDs, content, isActive in
                    Task {
                        switch mode {
                        case .create:
                            await store.createSkill(
                                name: name,
                                content: content,
                                description: description,
                                tags: tags,
                                allowedUserIDs: allowedUserIDs,
                                allowedGroupIDs: allowedGroupIDs
                            )
                        case .edit(let skill):
                            await store.updateSkill(
                                skill.id,
                                name: name,
                                content: content,
                                description: description,
                                tags: tags,
                                isActive: isActive,
                                allowedUserIDs: allowedUserIDs,
                                allowedGroupIDs: allowedGroupIDs
                            )
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

private struct SkillRow: View {
    var skill: AppSkill
    var canManageSkills: Bool
    var onEdit: () -> Void
    var onShare: () -> Void
    var onDelete: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Label(skill.name, systemImage: "sparkles")
                .lineLimit(1)

            Spacer()

            if skill.isActive {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.secondary)
                    .help("Active")
            }

            Menu {
                Button("Edit...") {
                    onEdit()
                }
                .disabled(!canManageSkills)
                Button("Share...") {
                    onShare()
                }
                Divider()
                Button("Delete Skill", role: .destructive) {
                    onDelete()
                }
                .disabled(!canManageSkills)
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .help("Skill actions")
        }
        .help(skill.description ?? skill.name)
        .contextMenu {
            Button("Edit...") {
                onEdit()
            }
            .disabled(!canManageSkills)
            Button("Share...") {
                onShare()
            }
            Divider()
            Button("Delete Skill", role: .destructive) {
                onDelete()
            }
            .disabled(!canManageSkills)
        }
    }
}

private struct SkillEditorSheet: View {
    var mode: SkillEditorMode
    var onSave: (String, String?, [String], [String], [String], String, Bool) -> Void
    var onCancel: () -> Void

    @State private var name: String
    @State private var description: String
    @State private var tagsText: String
    @State private var allowedUserIDsText: String
    @State private var allowedGroupIDsText: String
    @State private var content: String
    @State private var isActive: Bool

    init(
        mode: SkillEditorMode,
        onSave: @escaping (String, String?, [String], [String], [String], String, Bool) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.mode = mode
        self.onSave = onSave
        self.onCancel = onCancel
        switch mode {
        case .create:
            _name = State(initialValue: "")
            _description = State(initialValue: "")
            _tagsText = State(initialValue: "")
            _allowedUserIDsText = State(initialValue: "")
            _allowedGroupIDsText = State(initialValue: "")
            _content = State(initialValue: "")
            _isActive = State(initialValue: true)
        case .edit(let skill):
            _name = State(initialValue: skill.name)
            _description = State(initialValue: skill.description ?? "")
            _tagsText = State(initialValue: skill.tags.joined(separator: ", "))
            _allowedUserIDsText = State(initialValue: skill.allowedUserIDs.joined(separator: ", "))
            _allowedGroupIDsText = State(initialValue: skill.allowedGroupIDs.joined(separator: ", "))
            _content = State(initialValue: skill.content)
            _isActive = State(initialValue: skill.isActive)
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

            TextField("Tags", text: $tagsText)
                .textFieldStyle(.roundedBorder)

            TextField("Allowed user IDs", text: $allowedUserIDsText)
                .textFieldStyle(.roundedBorder)

            TextField("Allowed group IDs", text: $allowedGroupIDsText)
                .textFieldStyle(.roundedBorder)

            Toggle("Active", isOn: $isActive)

            TextEditor(text: $content)
                .font(.body)
                .frame(minHeight: 220)
                .overlay {
                    RoundedRectangle(cornerRadius: 5)
                        .stroke(.quaternary)
                }

            HStack {
                Spacer()
                Button("Cancel") {
                    onCancel()
                }
                Button("Save") {
                    onSave(name, description, parsedTags, parsedAllowedUserIDs, parsedAllowedGroupIDs, content, isActive)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    || content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .frame(minWidth: 520, minHeight: 460)
    }

    private var parsedTags: [String] {
        parsedCommaSeparatedValues(tagsText)
    }

    private var parsedAllowedUserIDs: [String] {
        parsedCommaSeparatedValues(allowedUserIDsText)
    }

    private var parsedAllowedGroupIDs: [String] {
        parsedCommaSeparatedValues(allowedGroupIDsText)
    }

    private func parsedCommaSeparatedValues(_ text: String) -> [String] {
        text.split(separator: ",").map(String.init)
    }
}

private enum SkillEditorMode: Identifiable {
    case create
    case edit(AppSkill)

    var id: String {
        switch self {
        case .create:
            return "create"
        case .edit(let skill):
            return skill.id
        }
    }

    var title: String {
        switch self {
        case .create:
            return "New Skill"
        case .edit:
            return "Edit Skill"
        }
    }
}
