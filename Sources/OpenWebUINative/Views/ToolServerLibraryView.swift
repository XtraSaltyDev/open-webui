import SwiftUI

struct ToolServerLibraryView: View {
    @ObservedObject var store: AppStore
    @State private var name = ""
    @State private var kind: AppToolServerKind = .stdio
    @State private var command = ""
    @State private var argumentsText = ""
    @State private var baseURL = ""
    @State private var environmentText = ""
    @State private var isEnabled = true
    @State private var toolCallDraft: ToolCallDraft?
    @State private var toolCallArguments = "{}"
    @State private var toolCallTemplateError: String?
    private let argumentTemplateService = ToolArgumentTemplateService()

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Button {
                    store.exportToolServersJSONWithSavePanel()
                } label: {
                    Label("Export Tool Servers", systemImage: "square.and.arrow.up")
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .help("Export tool server registry JSON")

                Button {
                    store.importToolServersJSONWithOpenPanel()
                } label: {
                    Label("Import Tool Servers", systemImage: "square.and.arrow.down")
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .help("Import tool server registry JSON")
                .disabled(!store.currentUserCanManageTools)
            }

            Picker("Kind", selection: $kind) {
                ForEach(AppToolServerKind.allCases, id: \.self) { kind in
                    Text(kind.label).tag(kind)
                }
            }
            .labelsHidden()

            TextField("Server name", text: $name)
                .textFieldStyle(.roundedBorder)

            if kind == .stdio {
                TextField("Command", text: $command)
                    .textFieldStyle(.roundedBorder)
                TextField("Arguments", text: $argumentsText)
                    .textFieldStyle(.roundedBorder)
                TextField("Environment", text: $environmentText)
                    .textFieldStyle(.roundedBorder)
            } else {
                TextField("Base URL", text: $baseURL)
                    .textFieldStyle(.roundedBorder)
            }

            Toggle("Enabled", isOn: $isEnabled)

            Button {
                Task {
                    await store.createToolServer(
                        name: name,
                        kind: kind,
                        command: command,
                        argumentsText: argumentsText,
                        baseURL: baseURL,
                        environmentText: environmentText,
                        isEnabled: isEnabled
                    )
                    clearForm()
                }
            } label: {
                Label("Add Tool Server", systemImage: "server.rack")
            }
            .disabled(!store.currentUserCanManageTools || !canCreate)

            VStack(alignment: .leading, spacing: 4) {
                Text("Invocation JSON")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                TextEditor(text: $store.toolServerInvocationRequestBody)
                    .font(.system(.caption, design: .monospaced))
                    .frame(minHeight: 72, maxHeight: 120)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.secondary.opacity(0.25))
                    )
                    .disabled(store.isInvokingToolServer)
            }

            if store.toolServers.isEmpty {
                Text("No tool servers")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(store.toolServers) { server in
                    ToolServerRow(
                        server: server,
                        status: store.toolServerStatuses[server.id] ?? .unknown,
                        discoveryStatus: store.toolServerDiscoveryStatuses[server.id] ?? .unknown,
                        discoveredTools: store.toolServerTools[server.id] ?? [],
                        isInvoking: store.isInvokingToolServer,
                        isDiscovering: store.isDiscoveringToolServerTools,
                        canManageToolServers: store.currentUserCanManageTools,
                        canInvokeToolServers: store.currentUserCanInvokeTools,
                        onCheck: {
                            Task {
                                await store.checkToolServer(server.id)
                            }
                        },
                        onDiscover: {
                            Task {
                                await store.discoverToolServerTools(server.id)
                            }
                        },
                        onCallTool: { tool in
                            presentToolCall(server: server, tool: tool)
                        },
                        onInvoke: {
                            Task {
                                await store.invokeToolServer(server.id)
                            }
                        },
                        onToggle: {
                            Task {
                                await store.updateToolServer(
                                    server.id,
                                    name: server.name,
                                    kind: server.kind,
                                    command: server.command ?? "",
                                    argumentsText: server.arguments.joined(separator: ", "),
                                    baseURL: server.baseURL ?? "",
                                    environmentText: server.environment.map { "\($0.key)=\($0.value)" }.sorted().joined(separator: "\n"),
                                    isEnabled: !server.isEnabled
                                )
                            }
                        },
                        onDelete: {
                            Task {
                                await store.deleteToolServer(server.id)
                            }
                        }
                    )
                }
            }

            if !store.toolServerRuns.isEmpty {
                Divider()

                Text("Recent runs")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                ForEach(store.toolServerRuns.prefix(3)) { run in
                    ToolServerRunRow(
                        run: run,
                        canDelete: store.currentUserCanManageTools && !store.isInvokingToolServer,
                        onDelete: {
                            Task {
                                await store.deleteToolServerRun(run.id)
                            }
                        }
                    )
                }
            }
        }
        .sheet(item: $toolCallDraft) { draft in
            ToolCallEditorSheet(
                draft: draft,
                argumentsText: $toolCallArguments,
                templateError: toolCallTemplateError,
                isInvoking: store.isInvokingToolServer,
                canInvokeToolServers: store.currentUserCanInvokeTools,
                onCancel: {
                    toolCallDraft = nil
                },
                onCall: {
                    Task {
                        await store.callToolServerTool(
                            draft.serverID,
                            toolName: draft.tool.name,
                            argumentsBody: toolCallArguments
                        )
                        if store.toolServerInvocationError == nil {
                            toolCallDraft = nil
                        }
                    }
                }
            )
        }
    }

    private var canCreate: Bool {
        let hasName = !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        switch kind {
        case .stdio:
            return hasName && !command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .http:
            return hasName && !baseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    private func clearForm() {
        name = ""
        command = ""
        argumentsText = ""
        baseURL = ""
        environmentText = ""
        isEnabled = true
    }

    private func presentToolCall(server: AppToolServer, tool: AppToolServerTool) {
        toolCallTemplateError = nil
        do {
            toolCallArguments = try argumentTemplateService.argumentsTemplate(for: tool)
        } catch {
            toolCallArguments = "{}"
            toolCallTemplateError = error.localizedDescription
        }
        toolCallDraft = ToolCallDraft(serverID: server.id, serverName: server.name, tool: tool)
    }
}

private struct ToolCallDraft: Identifiable {
    var id: String { "\(serverID):\(tool.name)" }
    var serverID: String
    var serverName: String
    var tool: AppToolServerTool
}

private struct ToolCallEditorSheet: View {
    var draft: ToolCallDraft
    @Binding var argumentsText: String
    var templateError: String?
    var isInvoking: Bool
    var canInvokeToolServers: Bool
    var onCancel: () -> Void
    var onCall: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(draft.tool.displayName)
                        .font(.headline)
                    Text(draft.serverName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }

            if let description = draft.tool.description, !description.isEmpty {
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }

            if let templateError {
                Text(templateError)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            TextEditor(text: $argumentsText)
                .font(.system(.body, design: .monospaced))
                .frame(minWidth: 420, minHeight: 220)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.secondary.opacity(0.25))
                )

            HStack {
                Spacer()

                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)

                Button {
                    onCall()
                } label: {
                    Label("Call Tool", systemImage: "play.fill")
                }
                .disabled(!canInvokeToolServers || isInvoking)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding()
    }
}

private struct ToolServerRow: View {
    var server: AppToolServer
    var status: ToolServerConnectionStatus
    var discoveryStatus: ToolServerConnectionStatus
    var discoveredTools: [AppToolServerTool]
    var isInvoking: Bool
    var isDiscovering: Bool
    var canManageToolServers: Bool
    var canInvokeToolServers: Bool
    var onCheck: () -> Void
    var onDiscover: () -> Void
    var onCallTool: (AppToolServerTool) -> Void
    var onInvoke: () -> Void
    var onToggle: () -> Void
    var onDelete: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: server.kind == .stdio ? "terminal" : "network")
                .foregroundStyle(server.isEnabled ? Color.accentColor : Color.secondary)
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 2) {
                Text(server.name)
                    .font(.callout.weight(.semibold))
                    .lineLimit(1)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                HStack(spacing: 4) {
                    Image(systemName: statusIcon)
                        .imageScale(.small)
                    Text(statusText)
                        .lineLimit(1)
                }
                .font(.caption2)
                .foregroundStyle(statusColor)

                if !discoveredTools.isEmpty {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(discoveredTools.prefix(3)) { tool in
                            HStack(spacing: 4) {
                                Button {
                                    onCallTool(tool)
                                } label: {
                                    Label("Call \(tool.displayName)", systemImage: "play.fill")
                                }
                                .labelStyle(.iconOnly)
                                .buttonStyle(.borderless)
                                .disabled(!canInvokeToolServers || !server.isEnabled || isInvoking)
                                .help("Call \(tool.displayName)")

                                Text(tool.displayName)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                        if discoveredTools.count > 3 {
                            Text("+\(discoveredTools.count - 3) more")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                } else if discoveryStatus != .unknown {
                    HStack(spacing: 4) {
                        Image(systemName: discoveryIcon)
                            .imageScale(.small)
                        Text(discoveryText)
                            .lineLimit(1)
                    }
                    .font(.caption2)
                    .foregroundStyle(discoveryColor)
                }
            }

            Spacer()

            Button(action: onCheck) {
                Label("Check Status", systemImage: "waveform.path.ecg")
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)
            .disabled(status == .checking)
            .help("Check tool server status")

            Button(action: onDiscover) {
                Label("Discover Tools", systemImage: "list.bullet.rectangle")
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)
            .disabled(!server.isEnabled || isDiscovering)
            .help("Discover MCP tools")

            Button(action: onInvoke) {
                Label("Invoke", systemImage: "play.circle")
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)
            .disabled(!canInvokeToolServers || !server.isEnabled || isInvoking)
            .help("Invoke tool server with an empty JSON request")

            Button(action: onToggle) {
                Label(server.isEnabled ? "Disable" : "Enable", systemImage: server.isEnabled ? "checkmark.circle.fill" : "circle")
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)
            .disabled(!canManageToolServers)
            .help(server.isEnabled ? "Disable tool server" : "Enable tool server")

            Button(role: .destructive, action: onDelete) {
                Label("Delete", systemImage: "trash")
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)
            .disabled(!canManageToolServers)
            .help("Delete tool server")
        }
        .contextMenu {
            Button("Discover Tools", action: onDiscover)
                .disabled(!server.isEnabled || isDiscovering)
            ForEach(discoveredTools) { tool in
                Button("Call \(tool.displayName)") {
                    onCallTool(tool)
                }
                .disabled(!canInvokeToolServers || !server.isEnabled || isInvoking)
            }
            Button("Invoke", action: onInvoke)
                .disabled(!canInvokeToolServers || !server.isEnabled || isInvoking)
            Button(server.isEnabled ? "Disable" : "Enable", action: onToggle)
                .disabled(!canManageToolServers)
            Button("Delete", role: .destructive, action: onDelete)
                .disabled(!canManageToolServers)
        }
    }

    private var statusText: String {
        if let detail = status.detail {
            return "\(status.label): \(detail)"
        }
        return status.label
    }

    private var discoveryText: String {
        if let detail = discoveryStatus.detail {
            return "Tools: \(detail)"
        }
        return "Tools: \(discoveryStatus.label)"
    }

    private var statusIcon: String {
        switch status {
        case .unknown:
            return "questionmark.circle"
        case .checking:
            return "arrow.triangle.2.circlepath"
        case .available:
            return "checkmark.circle.fill"
        case .unavailable:
            return "xmark.circle.fill"
        }
    }

    private var discoveryIcon: String {
        switch discoveryStatus {
        case .unknown:
            return "questionmark.circle"
        case .checking:
            return "arrow.triangle.2.circlepath"
        case .available:
            return "checkmark.circle.fill"
        case .unavailable:
            return "xmark.circle.fill"
        }
    }

    private var statusColor: Color {
        switch status {
        case .unknown, .checking:
            return .secondary
        case .available:
            return .green
        case .unavailable:
            return .red
        }
    }

    private var discoveryColor: Color {
        switch discoveryStatus {
        case .unknown, .checking:
            return .secondary
        case .available:
            return .green
        case .unavailable:
            return .red
        }
    }

    private var detail: String {
        switch server.kind {
        case .stdio:
            let args = server.arguments.isEmpty ? "" : " \(server.arguments.joined(separator: " "))"
            return "\(server.command ?? "")\(args)"
        case .http:
            return server.baseURL ?? ""
        }
    }
}

private extension AppToolServerTool {
    var displayName: String {
        title ?? name
    }
}

private struct ToolServerRunRow: View {
    var run: AppToolServerRun
    var canDelete: Bool
    var onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Image(systemName: run.status == .succeeded ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundStyle(run.status == .succeeded ? Color.green : Color.red)
                Text(run.serverName)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                Spacer()
                if let statusCode = run.statusCode {
                    Text(statusLabel(for: statusCode))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Button(action: onDelete) {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .help("Delete run")
                .disabled(!canDelete)
                .foregroundStyle(.secondary)
            }

            Text(run.errorMessage ?? responsePreview)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
    }

    private var responsePreview: String {
        run.responseBody.isEmpty ? "No response body" : run.responseBody
    }

    private func statusLabel(for statusCode: Int) -> String {
        switch run.serverKind {
        case .stdio:
            return "Exit \(statusCode)"
        case .http:
            return "HTTP \(statusCode)"
        }
    }
}
