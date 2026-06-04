import SwiftUI

struct FunctionLibraryView: View {
    @ObservedObject var store: AppStore
    @State private var editorMode: FunctionEditorMode?
    @State private var runDraft: FunctionRunDraft?
    @State private var runMethodName = "inlet"
    @State private var runInputBody = "{}"

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if store.functions.isEmpty {
                Text("No functions")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(store.functions) { function in
                    FunctionRow(
                        function: function,
                        canManageFunctions: store.currentUserCanManageFunctions,
                        canRunFunctions: store.currentUserCanInvokeFunctions,
                        onEdit: {
                            editorMode = .edit(function)
                        },
                        onRun: {
                            presentRun(function)
                        },
                        onShare: {
                            store.shareFunction(function.id)
                        },
                        onDelete: {
                            Task {
                                await store.deleteFunction(function.id)
                            }
                        }
                    )
                }
            }

            HStack {
                Button {
                    editorMode = .create
                } label: {
                    Label("New Function", systemImage: "function")
                }
                .help("New function")
                .disabled(!store.currentUserCanManageFunctions)

                Button {
                    store.importFunctionsJSONWithOpenPanel()
                } label: {
                    Label("Import Functions", systemImage: "square.and.arrow.down")
                }
                .help("Import functions")
                .disabled(!store.currentUserCanManageFunctions)

                Menu {
                    Button("Native JSON") {
                        store.exportFunctionsJSONWithSavePanel()
                    }

                    Button("Open WebUI JSON") {
                        store.exportFunctionsOpenWebUIJSONWithSavePanel()
                    }
                } label: {
                    Label("Export Functions", systemImage: "square.and.arrow.up")
                }
                .help("Export functions")
                .disabled(store.functions.isEmpty)
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)

            if !store.functionRuns.isEmpty {
                Divider()

                Text("Recent function runs")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                ForEach(store.functionRuns.prefix(3)) { run in
                    FunctionRunRow(run: run)
                }
            }
        }
        .sheet(item: $editorMode) { mode in
            FunctionEditorSheet(
                mode: mode,
                onGenerateValvesSchema: { name, kind, content in
                    await store.functionValvesSchemaDraft(name: name, kind: kind, content: content)
                },
                onSave: { name, kind, description, content, valvesJSON, isActive, isGlobal in
                    Task {
                        switch mode {
                        case .create:
                            await store.createFunction(
                                name: name,
                                kind: kind,
                                content: content,
                                description: description,
                                valvesJSON: valvesJSON
                            )
                        case .edit(let function):
                            await store.updateFunction(
                                function.id,
                                name: name,
                                kind: kind,
                                content: content,
                                description: description,
                                isActive: isActive,
                                isGlobal: isGlobal,
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
            FunctionRunSheet(
                draft: draft,
                methodName: $runMethodName,
                inputBody: $runInputBody,
                isRunning: store.isRunningFunction,
                canRunFunctions: store.currentUserCanInvokeFunctions,
                onCancel: {
                    runDraft = nil
                },
                onRun: {
                    Task {
                        await store.runFunction(
                            draft.functionID,
                            methodName: runMethodName,
                            inputBody: runInputBody
                        )
                        if store.functionExecutionError == nil {
                            runDraft = nil
                        }
                    }
                }
            )
        }
    }

    private func presentRun(_ function: AppFunction) {
        runMethodName = function.defaultMethodName
        runInputBody = "{}"
        runDraft = FunctionRunDraft(functionID: function.id, functionName: function.name)
    }
}

private struct FunctionRunDraft: Identifiable {
    var id: String { functionID }
    var functionID: String
    var functionName: String
}

private struct FunctionRunSheet: View {
    var draft: FunctionRunDraft
    @Binding var methodName: String
    @Binding var inputBody: String
    var isRunning: Bool
    var canRunFunctions: Bool
    var onCancel: () -> Void
    var onRun: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Run \(draft.functionName)")
                    .font(.headline)
                Text("Local Python function")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            TextField("Method", text: $methodName)
                .textFieldStyle(.roundedBorder)

            TextEditor(text: $inputBody)
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
                    Label("Run Function", systemImage: "play.fill")
                }
                .disabled(!canRunFunctions || isRunning || methodName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding()
    }
}

private struct FunctionRunRow: View {
    var run: AppFunctionRun

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Image(systemName: run.status == .succeeded ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundStyle(run.status == .succeeded ? Color.green : Color.red)
                Text(run.functionName)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                Spacer()
                Text(run.methodName)
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

private struct FunctionRow: View {
    var function: AppFunction
    var canManageFunctions: Bool
    var canRunFunctions: Bool
    var onEdit: () -> Void
    var onRun: () -> Void
    var onShare: () -> Void
    var onDelete: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Label(function.name, systemImage: iconName)
                .lineLimit(1)

            Spacer()

            if function.isActive {
                Image(systemName: function.isGlobal ? "globe" : "checkmark.circle.fill")
                    .foregroundStyle(.secondary)
                    .help(function.isGlobal ? "Active globally" : "Active")
            }

            Menu {
                Button("Run...") {
                    onRun()
                }
                .disabled(!canRunFunctions)
                Divider()
                Button("Share...") {
                    onShare()
                }
                Divider()
                Button("Edit...") {
                    onEdit()
                }
                .disabled(!canManageFunctions)
                Divider()
                Button("Delete Function", role: .destructive) {
                    onDelete()
                }
                .disabled(!canManageFunctions)
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .help("Function actions")
        }
        .help(function.description ?? function.name)
        .contextMenu {
            Button("Run...") {
                onRun()
            }
            .disabled(!canRunFunctions)
            Divider()
            Button("Share...") {
                onShare()
            }
            Divider()
            Button("Edit...") {
                onEdit()
            }
            .disabled(!canManageFunctions)
            Divider()
            Button("Delete Function", role: .destructive) {
                onDelete()
            }
            .disabled(!canManageFunctions)
        }
    }

    private var iconName: String {
        switch function.kind {
        case .filter:
            return "line.3.horizontal.decrease.circle"
        case .action:
            return "bolt.circle"
        case .pipe:
            return "point.3.connected.trianglepath.dotted"
        }
    }
}

private extension AppFunction {
    var defaultMethodName: String {
        switch kind {
        case .filter:
            return "inlet"
        case .action:
            return "action"
        case .pipe:
            return "pipe"
        }
    }
}

private struct FunctionEditorSheet: View {
    var mode: FunctionEditorMode
    var onGenerateValvesSchema: (String, AppFunctionKind, String) async -> ValvesSchemaDraft?
    var onSave: (String, AppFunctionKind, String?, String, String, Bool, Bool) -> Void
    var onCancel: () -> Void

    @State private var name: String
    @State private var kind: AppFunctionKind
    @State private var description: String
    @State private var content: String
    @State private var valvesJSON: String
    @State private var valvesSchemaFields: [JSONSchemaFormField] = []
    @State private var isActive: Bool
    @State private var isGlobal: Bool
    @State private var isGeneratingValvesJSON = false

    init(
        mode: FunctionEditorMode,
        onGenerateValvesSchema: @escaping (String, AppFunctionKind, String) async -> ValvesSchemaDraft?,
        onSave: @escaping (String, AppFunctionKind, String?, String, String, Bool, Bool) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.mode = mode
        self.onGenerateValvesSchema = onGenerateValvesSchema
        self.onSave = onSave
        self.onCancel = onCancel
        switch mode {
        case .create:
            _name = State(initialValue: "")
            _kind = State(initialValue: .filter)
            _description = State(initialValue: "")
            _content = State(initialValue: "")
            _valvesJSON = State(initialValue: "")
            _isActive = State(initialValue: false)
            _isGlobal = State(initialValue: false)
        case .edit(let function):
            _name = State(initialValue: function.name)
            _kind = State(initialValue: function.kind)
            _description = State(initialValue: function.description ?? "")
            _content = State(initialValue: function.content)
            _valvesJSON = State(initialValue: function.valves?.jsonString ?? "")
            _isActive = State(initialValue: function.isActive)
            _isGlobal = State(initialValue: function.isGlobal)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(mode.title)
                .font(.title3)
                .fontWeight(.semibold)

            TextField("Name", text: $name)
                .textFieldStyle(.roundedBorder)

            Picker("Type", selection: $kind) {
                ForEach(AppFunctionKind.allCases, id: \.self) { kind in
                    Text(kind.rawValue.capitalized).tag(kind)
                }
            }
            .pickerStyle(.segmented)

            TextField("Description", text: $description)
                .textFieldStyle(.roundedBorder)

            HStack {
                Toggle("Active", isOn: $isActive)
                Toggle("Global", isOn: $isGlobal)
                    .disabled(!isActive)
            }

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
                        if let draft = await onGenerateValvesSchema(name, kind, content) {
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
                    onSave(name, kind, description, content, valvesJSON, isActive, isActive && isGlobal)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    || content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .frame(minWidth: 540, minHeight: 580)
        .onChange(of: isActive) {
            if !isActive {
                isGlobal = false
            }
        }
    }
}

private enum FunctionEditorMode: Identifiable {
    case create
    case edit(AppFunction)

    var id: String {
        switch self {
        case .create:
            return "create"
        case .edit(let function):
            return function.id
        }
    }

    var title: String {
        switch self {
        case .create:
            return "New Function"
        case .edit:
            return "Edit Function"
        }
    }
}
