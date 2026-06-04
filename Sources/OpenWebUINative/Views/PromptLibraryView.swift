import SwiftUI

struct PromptLibraryView: View {
    @ObservedObject var store: AppStore
    @State private var editorMode: PromptEditorMode?
    @State private var variablePrompt: SavedPrompt?

    var body: some View {
        if store.prompts.isEmpty {
            Text("No prompts")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else {
            ForEach(store.prompts) { prompt in
                PromptRow(
                    prompt: prompt,
                    canManagePrompts: store.currentUserCanManagePrompts,
                    onInsert: {
                        if store.promptVariables(for: prompt.id).isEmpty {
                            store.insertPrompt(prompt.id)
                        } else {
                            variablePrompt = prompt
                        }
                    },
                    onEdit: {
                        editorMode = .edit(prompt)
                    },
                    onShare: {
                        store.sharePrompt(prompt.id)
                    },
                    onDelete: {
                        Task {
                            await store.deletePrompt(prompt.id)
                        }
                    }
                )
            }
        }

        SidebarActionStrip {
            SidebarActionButton(title: "New Prompt", systemImage: "text.badge.plus", isDisabled: !store.currentUserCanManagePrompts) {
                editorMode = .create
            }

            SidebarActionButton(title: "Import Prompts", systemImage: "square.and.arrow.down", isDisabled: !store.currentUserCanManagePrompts) {
                store.importPromptsJSONWithOpenPanel()
            }

            SidebarActionMenu(title: "Export Prompts", systemImage: "square.and.arrow.up", isDisabled: store.prompts.isEmpty) {
                Button("Native JSON") {
                    store.exportPromptsJSONWithSavePanel()
                }

                Button("Open WebUI JSON") {
                    store.exportPromptsOpenWebUIJSONWithSavePanel()
                }
            }
        }
        .sheet(item: $editorMode) { mode in
            PromptEditorSheet(
                mode: mode,
                onSave: { title, content, command, tags, allowedUserIDs, allowedGroupIDs in
                    Task {
                        switch mode {
                        case .create:
                            await store.createPrompt(
                                title: title,
                                content: content,
                                command: command,
                                tags: tags,
                                allowedUserIDs: allowedUserIDs,
                                allowedGroupIDs: allowedGroupIDs
                            )
                        case .edit(let prompt):
                            await store.updatePrompt(
                                prompt.id,
                                title: title,
                                content: content,
                                command: command,
                                tags: tags,
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
        .sheet(item: $variablePrompt) { prompt in
            PromptVariableSheet(
                prompt: prompt,
                variables: store.promptVariables(for: prompt.id),
                onInsert: { values in
                    store.insertPrompt(prompt.id, variableValues: values)
                    variablePrompt = nil
                },
                onCancel: {
                    variablePrompt = nil
                }
            )
        }
    }
}

private struct PromptRow: View {
    var prompt: SavedPrompt
    var canManagePrompts: Bool
    var onInsert: () -> Void
    var onEdit: () -> Void
    var onShare: () -> Void
    var onDelete: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Button {
                onInsert()
            } label: {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(prompt.title)
                            .lineLimit(1)
                        if !metadataText.isEmpty {
                            Text(metadataText)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                } icon: {
                    Image(systemName: "text.quote")
                }
            }
            .buttonStyle(.plain)
            .help("Insert prompt")

            Spacer()

            Menu {
                Button("Insert") {
                    onInsert()
                }
                Button("Edit...") {
                    onEdit()
                }
                .disabled(!canManagePrompts)
                Button("Share...") {
                    onShare()
                }
                Divider()
                Button("Delete Prompt", role: .destructive) {
                    onDelete()
                }
                .disabled(!canManagePrompts)
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .help("Prompt actions")
        }
        .contextMenu {
            Button("Insert") {
                onInsert()
            }
            Button("Edit...") {
                onEdit()
            }
            .disabled(!canManagePrompts)
            Button("Share...") {
                onShare()
            }
            Divider()
            Button("Delete Prompt", role: .destructive) {
                onDelete()
            }
            .disabled(!canManagePrompts)
        }
    }

    private var metadataText: String {
        var parts = [prompt.command].compactMap { $0 } + prompt.tags.map { "#\($0)" }
        if !prompt.versions.isEmpty {
            parts.append("\(prompt.versions.count) previous version\(prompt.versions.count == 1 ? "" : "s")")
        }
        return parts.joined(separator: " ")
    }
}

private struct PromptEditorSheet: View {
    var mode: PromptEditorMode
    var onSave: (String, String, String, [String], [String], [String]) -> Void
    var onCancel: () -> Void

    @State private var title: String
    @State private var command: String
    @State private var tagsText: String
    @State private var allowedUserIDsText: String
    @State private var allowedGroupIDsText: String
    @State private var content: String

    init(
        mode: PromptEditorMode,
        onSave: @escaping (String, String, String, [String], [String], [String]) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.mode = mode
        self.onSave = onSave
        self.onCancel = onCancel
        switch mode {
        case .create:
            _title = State(initialValue: "")
            _command = State(initialValue: "")
            _tagsText = State(initialValue: "")
            _allowedUserIDsText = State(initialValue: "")
            _allowedGroupIDsText = State(initialValue: "")
            _content = State(initialValue: "")
        case .edit(let prompt):
            _title = State(initialValue: prompt.title)
            _command = State(initialValue: prompt.command ?? "")
            _tagsText = State(initialValue: prompt.tags.joined(separator: ", "))
            _allowedUserIDsText = State(initialValue: prompt.allowedUserIDs.joined(separator: ", "))
            _allowedGroupIDsText = State(initialValue: prompt.allowedGroupIDs.joined(separator: ", "))
            _content = State(initialValue: prompt.content)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(mode.title)
                .font(.title3)
                .fontWeight(.semibold)

            TextField("Title", text: $title)
                .textFieldStyle(.roundedBorder)

            TextField("Command", text: $command)
                .textFieldStyle(.roundedBorder)

            TextField("Tags", text: $tagsText)
                .textFieldStyle(.roundedBorder)

            TextField("Allowed user IDs", text: $allowedUserIDsText)
                .textFieldStyle(.roundedBorder)

            TextField("Allowed group IDs", text: $allowedGroupIDsText)
                .textFieldStyle(.roundedBorder)

            TextEditor(text: $content)
                .font(.body)
                .frame(minHeight: 180)
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
                    onSave(title, content, command, tags, allowedUserIDs, allowedGroupIDs)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    || content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .frame(minWidth: 420, minHeight: 320)
    }

    private var tags: [String] {
        SavedPrompt.normalizedTags(tagsText.split(separator: ",").map(String.init))
    }

    private var allowedUserIDs: [String] {
        SavedPrompt.normalizedAccessIDs(allowedUserIDsText.split(separator: ",").map(String.init))
    }

    private var allowedGroupIDs: [String] {
        SavedPrompt.normalizedAccessIDs(allowedGroupIDsText.split(separator: ",").map(String.init))
    }
}

private struct PromptVariableSheet: View {
    var prompt: SavedPrompt
    var variables: [PromptVariable]
    var onInsert: ([String: String]) -> Void
    var onCancel: () -> Void

    @State private var values: [String: String]

    init(
        prompt: SavedPrompt,
        variables: [PromptVariable],
        onInsert: @escaping ([String: String]) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.prompt = prompt
        self.variables = variables
        self.onInsert = onInsert
        self.onCancel = onCancel
        _values = State(initialValue: Dictionary(uniqueKeysWithValues: variables.map { ($0.name, "") }))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(prompt.title)
                .font(.title3)
                .fontWeight(.semibold)

            ForEach(variables, id: \.name) { variable in
                VStack(alignment: .leading, spacing: 6) {
                    Text(variable.name)
                        .font(.headline)
                    TextField(variable.name, text: Binding(
                        get: { values[variable.name] ?? "" },
                        set: { values[variable.name] = $0 }
                    ))
                    .textFieldStyle(.roundedBorder)
                }
            }

            HStack {
                Spacer()
                Button("Cancel") {
                    onCancel()
                }
                Button("Insert") {
                    onInsert(values)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(hasMissingValues)
            }
        }
        .padding(20)
        .frame(minWidth: 420)
    }

    private var hasMissingValues: Bool {
        variables.contains { variable in
            values[variable.name]?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false
        }
    }
}

private enum PromptEditorMode: Identifiable {
    case create
    case edit(SavedPrompt)

    var id: String {
        switch self {
        case .create:
            return "create"
        case .edit(let prompt):
            return prompt.id.uuidString
        }
    }

    var title: String {
        switch self {
        case .create:
            return "New Prompt"
        case .edit:
            return "Edit Prompt"
        }
    }
}
