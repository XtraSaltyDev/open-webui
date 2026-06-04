import SwiftUI

struct ToolLibraryView: View {
    @ObservedObject var store: AppStore
    @State private var editorMode: ToolEditorMode?
    @State private var runDraft: ToolRunDraft?
    @State private var runFunctionName = "run"
    @State private var runArgumentsBody = "{}"

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if store.tools.isEmpty {
                Text("No tools")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(store.tools) { tool in
                    ToolRow(
                        tool: tool,
                        canManageTools: store.currentUserCanManageTools,
                        canRunTools: store.currentUserCanInvokeTools,
                        onEdit: {
                            editorMode = .edit(tool)
                        },
                        onRun: {
                            presentRun(tool)
                        },
                        onShare: {
                            store.shareTool(tool.id)
                        },
                        onDelete: {
                            Task {
                                await store.deleteTool(tool.id)
                            }
                        }
                    )
                }
            }

            SidebarActionStrip {
                SidebarActionButton(title: "New Tool", systemImage: "hammer", isDisabled: !store.currentUserCanManageTools) {
                    editorMode = .create
                }

                SidebarActionButton(title: "Import Tools", systemImage: "square.and.arrow.down", isDisabled: !store.currentUserCanManageTools) {
                    store.importToolsJSONWithOpenPanel()
                }

                SidebarActionMenu(title: "Export Tools", systemImage: "square.and.arrow.up", isDisabled: store.tools.isEmpty) {
                    Button("Native JSON") {
                        store.exportToolsJSONWithSavePanel()
                    }

                    Button("Open WebUI JSON") {
                        store.exportToolsOpenWebUIJSONWithSavePanel()
                    }
                }
            }

            if !store.toolRuns.isEmpty {
                Divider()

                Text("Recent tool runs")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                ForEach(store.toolRuns.prefix(3)) { run in
                    ToolRunRow(run: run)
                }
            }
        }
        .sheet(item: $editorMode) { mode in
            ToolEditorSheet(
                mode: mode,
                onGenerateValvesSchema: { name, content in
                    await store.toolValvesSchemaDraft(name: name, content: content)
                },
                onSave: { name, description, content, valvesJSON in
                    Task {
                        switch mode {
                        case .create:
                            await store.createTool(
                                name: name,
                                content: content,
                                description: description,
                                valvesJSON: valvesJSON
                            )
                        case .edit(let tool):
                            await store.updateTool(
                                tool.id,
                                name: name,
                                content: content,
                                description: description,
                                valvesJSON: valvesJSON
                            )
                        }
                        if store.errorMessage == nil {
                            editorMode = nil
                        }
                    }
                },
                onCancel: {
                    editorMode = nil
                }
            )
        }
        .sheet(item: $runDraft) { draft in
            ToolRunSheet(
                draft: draft,
                functionName: $runFunctionName,
                argumentsBody: $runArgumentsBody,
                isRunning: store.isRunningTool,
                canRunTools: store.currentUserCanInvokeTools,
                onCancel: {
                    runDraft = nil
                },
                onRun: {
                    Task {
                        await store.runTool(
                            draft.toolID,
                            functionName: runFunctionName,
                            argumentsBody: runArgumentsBody
                        )
                        if store.toolExecutionError == nil {
                            runDraft = nil
                        }
                    }
                }
            )
        }
    }

    private func presentRun(_ tool: AppTool) {
        runFunctionName = tool.defaultFunctionName
        runArgumentsBody = "{}"
        runDraft = ToolRunDraft(toolID: tool.id, toolName: tool.name)
    }
}

private struct ToolRunDraft: Identifiable {
    var id: String { toolID }
    var toolID: String
    var toolName: String
}

private struct ToolRunSheet: View {
    var draft: ToolRunDraft
    @Binding var functionName: String
    @Binding var argumentsBody: String
    var isRunning: Bool
    var canRunTools: Bool
    var onCancel: () -> Void
    var onRun: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Run \(draft.toolName)")
                    .font(.headline)
                Text("Local Python tool")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            TextField("Function", text: $functionName)
                .textFieldStyle(.roundedBorder)

            TextEditor(text: $argumentsBody)
                .font(.system(.body, design: .monospaced))
                .frame(minWidth: 420, minHeight: 220)
                .overlay {
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.secondary.opacity(0.25))
                }

            HStack {
                Spacer()

                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)

                Button {
                    onRun()
                } label: {
                    Label("Run Tool", systemImage: "play.fill")
                }
                .disabled(!canRunTools || isRunning || functionName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding()
    }
}

private struct ToolRunRow: View {
    var run: AppToolRun

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Image(systemName: run.status == .succeeded ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundStyle(run.status == .succeeded ? Color.green : Color.red)
                Text(run.toolName)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                Spacer()
                Text(run.functionName)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Text(run.errorMessage ?? outputPreview)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
    }

    private var outputPreview: String {
        run.output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "No output" : run.output
    }
}

private extension AppTool {
    var defaultFunctionName: String {
        for spec in specs {
            guard let nameValue = spec.objectValue?["name"] else {
                continue
            }
            if case .string(let name) = nameValue {
                let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmedName.isEmpty {
                    return trimmedName
                }
            }
        }
        return "run"
    }
}

private struct ToolRow: View {
    var tool: AppTool
    var canManageTools: Bool
    var canRunTools: Bool
    var onEdit: () -> Void
    var onRun: () -> Void
    var onShare: () -> Void
    var onDelete: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Label(tool.name, systemImage: "hammer")
                .lineLimit(1)

            Spacer()

            Menu {
                Button("Run...") {
                    onRun()
                }
                .disabled(!canRunTools)
                Divider()
                Button("Share...") {
                    onShare()
                }
                Divider()
                Button("Edit...") {
                    onEdit()
                }
                .disabled(!canManageTools)
                Divider()
                Button("Delete Tool", role: .destructive) {
                    onDelete()
                }
                .disabled(!canManageTools)
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .help("Tool actions")
        }
        .help(tool.description ?? tool.name)
        .contextMenu {
            Button("Run...") {
                onRun()
            }
            .disabled(!canRunTools)
            Divider()
            Button("Share...") {
                onShare()
            }
            Divider()
            Button("Edit...") {
                onEdit()
            }
            .disabled(!canManageTools)
            Divider()
            Button("Delete Tool", role: .destructive) {
                onDelete()
            }
            .disabled(!canManageTools)
        }
    }
}

private struct ToolEditorSheet: View {
    var mode: ToolEditorMode
    var onGenerateValvesSchema: (String, String) async -> ValvesSchemaDraft?
    var onSave: (String, String?, String, String) -> Void
    var onCancel: () -> Void

    @State private var name: String
    @State private var description: String
    @State private var content: String
    @State private var valvesJSON: String
    @State private var valvesSchemaFields: [JSONSchemaFormField] = []
    @State private var isGeneratingValvesJSON = false

    init(
        mode: ToolEditorMode,
        onGenerateValvesSchema: @escaping (String, String) async -> ValvesSchemaDraft?,
        onSave: @escaping (String, String?, String, String) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.mode = mode
        self.onGenerateValvesSchema = onGenerateValvesSchema
        self.onSave = onSave
        self.onCancel = onCancel
        switch mode {
        case .create:
            _name = State(initialValue: "")
            _description = State(initialValue: "")
            _content = State(initialValue: "")
            _valvesJSON = State(initialValue: "")
        case .edit(let tool):
            _name = State(initialValue: tool.name)
            _description = State(initialValue: tool.description ?? "")
            _content = State(initialValue: tool.content)
            _valvesJSON = State(initialValue: tool.valves?.jsonString ?? "")
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

            TextEditor(text: $content)
                .font(.system(.body, design: .monospaced))
                .frame(minHeight: 220)
                .overlay {
                    RoundedRectangle(cornerRadius: 5)
                        .stroke(.quaternary)
                }

            HStack {
                Text("Valves JSON")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                Spacer()

                Button {
                    Task {
                        isGeneratingValvesJSON = true
                        if let draft = await onGenerateValvesSchema(name, content) {
                            valvesJSON = draft.templateJSON
                            valvesSchemaFields = draft.fields
                        }
                        isGeneratingValvesJSON = false
                    }
                } label: {
                    Label("Use Schema Defaults", systemImage: "slider.horizontal.3")
                }
                .buttonStyle(.borderless)
                .disabled(isGeneratingValvesJSON || content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .help("Use Valves schema defaults")
            }

            if !valvesSchemaFields.isEmpty {
                ValvesSchemaFieldEditor(fields: valvesSchemaFields, jsonBody: $valvesJSON)
            }

            TextEditor(text: $valvesJSON)
                .font(.system(.body, design: .monospaced))
                .frame(minHeight: 90)
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
                    onSave(name, description, content, valvesJSON)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    || content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .frame(minWidth: 520, minHeight: 520)
    }
}

private enum ToolEditorMode: Identifiable {
    case create
    case edit(AppTool)

    var id: String {
        switch self {
        case .create:
            return "create"
        case .edit(let tool):
            return tool.id
        }
    }

    var title: String {
        switch self {
        case .create:
            return "New Tool"
        case .edit:
            return "Edit Tool"
        }
    }
}
