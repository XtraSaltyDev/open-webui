import SwiftUI

struct CodeInterpreterSidebarView: View {
    @ObservedObject var store: AppStore

    var body: some View {
        Button {
            store.selectCodeInterpreter()
        } label: {
            Label("Code Interpreter", systemImage: "terminal")
        }
        .buttonStyle(.plain)
    }
}

struct CodeInterpreterView: View {
    @ObservedObject var store: AppStore

    private var selectedRun: AppCodeExecutionRun? {
        guard let selectedCodeExecutionRunID = store.selectedCodeExecutionRunID else {
            return store.codeExecutionRuns.first
        }
        return store.codeExecutionRuns.first { $0.id == selectedCodeExecutionRunID }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.horizontal, 20)
                .padding(.vertical, 14)

            Divider()

            HSplitView {
                controls
                    .frame(minWidth: 340, idealWidth: 420, maxWidth: 520)

                outputPanel
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Code Interpreter")
                    .font(.title2.weight(.semibold))
                Text("Run local shell or Python snippets and keep an auditable history")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if let codeExecutionError = store.codeExecutionError {
                Label(codeExecutionError, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(2)
                    .multilineTextAlignment(.trailing)
            }

            Button {
                Task {
                    await store.runCodeExecution()
                }
            } label: {
                Label(store.isRunningCodeExecution ? "Running" : "Run", systemImage: "play.fill")
            }
            .disabled(!store.currentUserCanRunCode || store.isRunningCodeExecution || store.codeExecutionInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Language")
                        .font(.headline)
                    Picker("Language", selection: $store.codeExecutionLanguage) {
                        ForEach(CodeExecutionLanguage.allCases) { language in
                            Text(language.label).tag(language)
                        }
                    }
                    .labelsHidden()
                    .onChange(of: store.codeExecutionLanguage) {
                        if store.codeExecutionInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            store.codeExecutionInput = store.codeExecutionLanguage.defaultCode
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Timeout")
                        .font(.headline)
                    Stepper(value: $store.codeExecutionTimeoutSeconds, in: 1...120, step: 1) {
                        Text("\(Int(store.codeExecutionTimeoutSeconds))s")
                            .monospacedDigit()
                            .frame(width: 44, alignment: .trailing)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Working Directory")
                    .font(.headline)
                TextField("Optional path", text: $store.codeExecutionWorkingDirectory)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Code")
                    .font(.headline)
                TextEditor(text: $store.codeExecutionInput)
                    .font(.body.monospaced())
                    .frame(minHeight: 240)
                    .overlay {
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.secondary.opacity(0.2))
                    }
            }

            HStack {
                Button {
                    Task {
                        await store.runCodeExecution()
                    }
                } label: {
                    Label("Run", systemImage: "play.fill")
                }
                .disabled(!store.currentUserCanRunCode || store.isRunningCodeExecution || store.codeExecutionInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                Button {
                    store.codeExecutionInput = store.codeExecutionLanguage.defaultCode
                    store.codeExecutionError = nil
                } label: {
                    Label("Reset", systemImage: "arrow.counterclockwise")
                }

                Spacer()
            }

            historyList

            Spacer()
        }
        .padding(16)
    }

    private var historyList: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("History")
                .font(.headline)

            if store.codeExecutionRuns.isEmpty {
                Text("No runs yet")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(store.codeExecutionRuns) { run in
                            HStack(spacing: 6) {
                                Button {
                                    store.loadCodeExecutionRun(run.id)
                                } label: {
                                    VStack(alignment: .leading, spacing: 2) {
                                        HStack(spacing: 6) {
                                            Text(run.title)
                                                .lineLimit(1)
                                            statusText(for: run.status)
                                        }
                                        Text("\(run.language.label) - \(run.startedAt.formatted(date: .abbreviated, time: .shortened))")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .buttonStyle(.plain)

                                Button {
                                    Task {
                                        await store.deleteCodeExecutionRun(run.id)
                                    }
                                } label: {
                                    Image(systemName: "trash")
                                }
                                .buttonStyle(.borderless)
                                .help("Delete run")
                            }
                            .padding(.vertical, 4)
                            .padding(.horizontal, 6)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(run.id == store.selectedCodeExecutionRunID ? Color.accentColor.opacity(0.12) : Color.clear)
                            )
                        }
                    }
                }
                .frame(maxHeight: 210)
            }
        }
    }

    private var outputPanel: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if let selectedRun {
                    HStack(spacing: 8) {
                        Label(selectedRun.language.label, systemImage: "terminal")
                            .font(.title3.weight(.semibold))
                        statusText(for: selectedRun.status)
                        if let exitCode = selectedRun.exitCode {
                            Text("exit \(exitCode)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(selectedRun.startedAt.formatted(date: .abbreviated, time: .shortened))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    outputBlock(title: "Stdout", text: selectedRun.stdout)
                    outputBlock(title: "Stderr", text: selectedRun.stderr)
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("No run selected", systemImage: "terminal")
                            .font(.title3.weight(.semibold))
                        Text("Run a shell or Python snippet to see captured output here.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func outputBlock(title: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.headline)
            Text(text.isEmpty ? "No output" : text)
                .font(.body.monospaced())
                .foregroundStyle(text.isEmpty ? .secondary : .primary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
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
}
