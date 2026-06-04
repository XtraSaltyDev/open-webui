import SwiftUI

struct TerminalSessionSidebarView: View {
    @ObservedObject var store: AppStore

    var body: some View {
        Button {
            store.selectTerminalSessions()
        } label: {
            Label("Terminal", systemImage: "terminal")
        }
        .buttonStyle(.plain)
    }
}

struct TerminalSessionView: View {
    @ObservedObject var store: AppStore
    @State private var newSessionTitle = "Terminal"
    @State private var newSessionWorkingDirectory = ""
    @State private var editSessionTitle = ""
    @State private var editSessionWorkingDirectory = ""

    private var selectedSession: AppTerminalSession? {
        store.selectedTerminalSession
    }

    private var selectedSessionCommands: [AppTerminalCommand] {
        guard let selectedSession else {
            return []
        }
        return store.terminalCommands
            .filter { $0.sessionID == selectedSession.id }
            .sorted { $0.startedAt > $1.startedAt }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.horizontal, 20)
                .padding(.vertical, 14)

            Divider()

            HSplitView {
                sessionPanel
                    .frame(minWidth: 300, idealWidth: 360, maxWidth: 460)

                commandPanel
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onAppear {
            loadSelectedSessionDraft(selectedSession)
        }
        .onChange(of: store.selectedTerminalSessionID) { _, _ in
            loadSelectedSessionDraft(selectedSession)
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Terminal")
                    .font(.title2.weight(.semibold))
                Text("Run local shell commands with persisted, auditable transcripts")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if let terminalError = store.terminalError {
                Label(terminalError, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(2)
                    .multilineTextAlignment(.trailing)
            }

            Button {
                Task {
                    await store.runTerminalCommand()
                }
            } label: {
                Label(store.isRunningTerminalCommand ? "Running" : "Run", systemImage: "play.fill")
            }
            .disabled(!store.currentUserCanUseTerminal || store.isRunningTerminalCommand || store.terminalCommandInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }

    private var sessionPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 8) {
                Text("New Session")
                    .font(.headline)
                TextField("Title", text: $newSessionTitle)
                    .textFieldStyle(.roundedBorder)
                TextField("Working directory", text: $newSessionWorkingDirectory)
                    .textFieldStyle(.roundedBorder)
                Button {
                    Task {
                        _ = await store.createTerminalSession(
                            title: newSessionTitle,
                            workingDirectoryPath: newSessionWorkingDirectory
                        )
                        newSessionTitle = "Terminal"
                        newSessionWorkingDirectory = ""
                    }
                } label: {
                    Label("Create", systemImage: "plus")
                }
                .disabled(!store.currentUserCanCreateTerminalSessions)
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text("Sessions")
                    .font(.headline)

                if store.terminalSessions.isEmpty {
                    Text("No terminal sessions")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(store.terminalSessions) { session in
                                HStack(spacing: 6) {
                                    Button {
                                        store.selectedTerminalSessionID = session.id
                                        store.terminalError = nil
                                    } label: {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(session.title)
                                                .lineLimit(1)
                                            Text(session.workingDirectoryPath ?? "Default working directory")
                                                .font(.caption2)
                                                .foregroundStyle(.secondary)
                                                .lineLimit(1)
                                        }
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                    .buttonStyle(.plain)

                                    Button {
                                        Task {
                                            await store.deleteTerminalSession(session.id)
                                        }
                                    } label: {
                                        Image(systemName: "trash")
                                    }
                                    .buttonStyle(.borderless)
                                    .help("Delete session")
                                    .disabled(!store.currentUserCanManageTerminalSessions || store.isRunningTerminalCommand)
                                    .foregroundStyle(.secondary)
                                }
                                .padding(.vertical, 4)
                                .padding(.horizontal, 6)
                                .background(
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(session.id == store.selectedTerminalSessionID ? Color.accentColor.opacity(0.12) : Color.clear)
                                )
                            }
                        }
                    }
                }
            }

            Spacer()
        }
        .padding(16)
    }

    private var commandPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let selectedSession {
                HStack(spacing: 8) {
                    Label(selectedSession.title, systemImage: "terminal")
                        .font(.title3.weight(.semibold))
                    if let workingDirectoryPath = selectedSession.workingDirectoryPath {
                        Text(workingDirectoryPath)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer()
                    Button {
                        Task {
                            await store.deleteTerminalSession(selectedSession.id)
                        }
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.borderless)
                    .help("Delete session")
                    .disabled(!store.currentUserCanManageTerminalSessions || store.isRunningTerminalCommand)
                    .foregroundStyle(.secondary)
                    Stepper(value: $store.terminalTimeoutSeconds, in: 1...120, step: 1) {
                        Text("\(Int(store.terminalTimeoutSeconds))s")
                            .monospacedDigit()
                            .frame(width: 44, alignment: .trailing)
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Session")
                        .font(.headline)
                    HStack(spacing: 8) {
                        TextField("Title", text: $editSessionTitle)
                            .textFieldStyle(.roundedBorder)
                        TextField("Working directory", text: $editSessionWorkingDirectory)
                            .textFieldStyle(.roundedBorder)
                        Button {
                            Task {
                                await store.updateTerminalSession(
                                    selectedSession.id,
                                    title: editSessionTitle,
                                    workingDirectoryPath: editSessionWorkingDirectory
                                )
                                loadSelectedSessionDraft(store.selectedTerminalSession)
                            }
                        } label: {
                            Label("Save", systemImage: "checkmark")
                        }
                        .disabled(!store.currentUserCanManageTerminalSessions || store.isRunningTerminalCommand)
                    }
                }

                TextEditor(text: $store.terminalCommandInput)
                    .font(.body.monospaced())
                    .frame(minHeight: 96, maxHeight: 140)
                    .overlay {
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.secondary.opacity(0.2))
                    }

                HStack {
                    Button {
                        Task {
                            await store.runTerminalCommand()
                        }
                    } label: {
                        Label("Run", systemImage: "play.fill")
                    }
                    .disabled(!store.currentUserCanUseTerminal || store.isRunningTerminalCommand || store.terminalCommandInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                    Button {
                        store.terminalCommandInput = ""
                        store.terminalError = nil
                    } label: {
                        Label("Clear", systemImage: "xmark")
                    }

                    Spacer()
                }

                transcript
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Label("No terminal session selected", systemImage: "terminal")
                        .font(.title3.weight(.semibold))
                    Text("Create a session to run shell commands and capture transcripts.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(16)
            }

            Spacer(minLength: 0)
        }
        .padding(16)
    }

    private var transcript: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if selectedSessionCommands.isEmpty {
                    Text("No commands yet")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(selectedSessionCommands) { command in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 8) {
                                Text(command.title)
                                    .font(.headline)
                                    .lineLimit(1)
                                statusText(for: command.status)
                                if let exitCode = command.exitCode {
                                    Text("exit \(exitCode)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text(command.startedAt.formatted(date: .abbreviated, time: .shortened))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Button {
                                    store.prepareTerminalCommandForRerun(command.id)
                                } label: {
                                    Image(systemName: "arrow.clockwise")
                                }
                                .buttonStyle(.borderless)
                                .help("Prepare command to rerun")
                                .disabled(!store.currentUserCanUseTerminal || store.isRunningTerminalCommand)
                                .foregroundStyle(.secondary)
                                Button {
                                    Task {
                                        await store.deleteTerminalCommand(command.id)
                                    }
                                } label: {
                                    Image(systemName: "trash")
                                }
                                .buttonStyle(.borderless)
                                .help("Delete transcript")
                                .disabled(!store.currentUserCanManageTerminalSessions || store.isRunningTerminalCommand)
                                .foregroundStyle(.secondary)
                            }
                            outputBlock(title: "Stdout", text: command.stdout)
                            outputBlock(title: "Stderr", text: command.stderr)
                        }
                        .padding(10)
                        .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func outputBlock(title: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(text.isEmpty ? "No output" : text)
                .font(.body.monospaced())
                .foregroundStyle(text.isEmpty ? .secondary : .primary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func statusText(for status: CodeExecutionStatus) -> some View {
        let color: Color = switch status {
        case .succeeded:
            .green
        case .failed:
            .orange
        case .timedOut:
            .red
        }
        return Text(status.rawValue)
            .font(.caption.weight(.semibold))
            .foregroundStyle(color)
    }

    private func loadSelectedSessionDraft(_ session: AppTerminalSession?) {
        editSessionTitle = session?.title ?? ""
        editSessionWorkingDirectory = session?.workingDirectoryPath ?? ""
    }
}
