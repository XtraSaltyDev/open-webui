import SwiftUI

struct AutomationLibraryView: View {
    @ObservedObject var store: AppStore
    @State private var editorMode: AutomationEditorMode?

    var body: some View {
        let canManageAutomations = store.currentUserCanManageAutomations

        if !store.automations.isEmpty {
            TextField("Search automations", text: $store.automationSearchText)
                .textFieldStyle(.roundedBorder)
        }

        if !store.canChat {
            Label("\(store.activeProvider.name) does not support native chat automation runs.", systemImage: "exclamationmark.triangle")
                .font(.caption)
                .foregroundStyle(.secondary)
        }

        let filteredAutomations = store.filteredAutomations()
        if store.automations.isEmpty {
            Text("No automations")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else if filteredAutomations.isEmpty {
            Text("No matching automations")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else {
            ForEach(filteredAutomations) { automation in
                AutomationRow(
                    automation: automation,
                    recentRuns: store.automationRuns(for: automation.id),
                    canManageAutomations: canManageAutomations,
                    canRun: store.canChat && canManageAutomations,
                    onRun: {
                        Task {
                            await store.runAutomationNow(automation.id)
                        }
                    },
                    onToggle: {
                        Task {
                            await store.toggleAutomation(automation.id)
                        }
                    },
                    onShare: {
                        store.shareAutomation(automation.id)
                    },
                    onEdit: {
                        editorMode = .edit(automation)
                    },
                    onDelete: {
                        Task {
                            await store.deleteAutomation(automation.id)
                        }
                    }
                )
            }
        }

        Label(
            store.isAutomationSchedulerRunning ? "Scheduler active" : "Scheduler stopped",
            systemImage: store.isAutomationSchedulerRunning ? "clock.arrow.circlepath" : "clock.badge.exclamationmark"
        )
        .font(.caption2)
        .foregroundStyle(.secondary)

        SidebarActionStrip {
            SidebarActionButton(title: "New Automation", systemImage: "clock.badge.plus", isDisabled: !canManageAutomations) {
                editorMode = .create(defaultModelID: store.selectedModelID ?? store.models.first?.id ?? "")
            }

            SidebarActionButton(
                title: "Run Due Automations",
                systemImage: "clock.arrow.circlepath",
                isDisabled: !store.canChat || !canManageAutomations || store.automations.isEmpty
            ) {
                Task {
                    await store.runDueAutomations()
                }
            }

            SidebarActionButton(title: "Import Automations", systemImage: "square.and.arrow.down", isDisabled: !canManageAutomations) {
                store.importAutomationsJSONWithOpenPanel()
            }

            SidebarActionMenu(title: "Export Automations", systemImage: "square.and.arrow.up", isDisabled: store.automations.isEmpty) {
                Button("Native JSON") {
                    store.exportAutomationsJSONWithSavePanel()
                }

                Button("Open WebUI JSON") {
                    store.exportAutomationsOpenWebUIJSONWithSavePanel()
                }
            }
        }
        .sheet(item: $editorMode) { mode in
            AutomationEditorSheet(
                mode: mode,
                onSave: { name, prompt, modelID, rrule, isActive in
                    Task {
                        switch mode {
                        case .create:
                            await store.createAutomation(
                                name: name,
                                prompt: prompt,
                                modelID: modelID,
                                rrule: rrule,
                                isActive: isActive
                            )
                        case .edit(let automation):
                            await store.updateAutomation(
                                automation.id,
                                name: name,
                                prompt: prompt,
                                modelID: modelID,
                                rrule: rrule,
                                isActive: isActive
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

private struct AutomationRow: View {
    var automation: AppAutomation
    var recentRuns: [AppAutomationRun]
    var canManageAutomations: Bool
    var canRun: Bool
    var onRun: () -> Void
    var onToggle: () -> Void
    var onShare: () -> Void
    var onEdit: () -> Void
    var onDelete: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Button {
                onEdit()
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Label(automation.name, systemImage: automation.isActive ? "clock.badge.checkmark" : "pause.circle")
                        .lineLimit(1)
                    Text("\(automation.modelID) - \(automation.rrule)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Text(nextRunText(for: automation))
                        .font(.caption2)
                        .foregroundStyle(automation.isActive ? Color.secondary : Color.secondary.opacity(0.75))
                        .lineLimit(1)
                    if let latestRun = recentRuns.first {
                        Label(latestRunStatusText(latestRun), systemImage: latestRun.status.systemImage)
                            .font(.caption2)
                            .foregroundStyle(latestRun.status == .succeeded ? Color.secondary : Color.red)
                            .lineLimit(1)
                    }
                }
            }
            .buttonStyle(.plain)
            .disabled(!canManageAutomations)
            .help("Edit automation")

            Spacer()

            Menu {
                Button("Run Now") {
                    onRun()
                }
                .disabled(!canRun)
                Divider()
                Button(automation.isActive ? "Pause Automation" : "Enable Automation") {
                    onToggle()
                }
                .disabled(!canManageAutomations)
                Divider()
                Button("Share...") {
                    onShare()
                }
                Divider()
                Button("Edit...") {
                    onEdit()
                }
                .disabled(!canManageAutomations)
                Divider()
                Button("Delete Automation", role: .destructive) {
                    onDelete()
                }
                .disabled(!canManageAutomations)
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .help("Automation actions")
        }
        .contextMenu {
            Button("Run Now") {
                onRun()
            }
            .disabled(!canRun)
            Divider()
            Button(automation.isActive ? "Pause Automation" : "Enable Automation") {
                onToggle()
            }
            .disabled(!canManageAutomations)
            Divider()
            Button("Share...") {
                onShare()
            }
            Divider()
            Button("Edit...") {
                onEdit()
            }
            .disabled(!canManageAutomations)
            Divider()
            Button("Delete Automation", role: .destructive) {
                onDelete()
            }
            .disabled(!canManageAutomations)
        }
    }

    private func nextRunText(for automation: AppAutomation) -> String {
        guard automation.isActive else {
            return "Paused"
        }
        guard let nextRunAt = automation.nextRunAt else {
            return "Next run not scheduled"
        }
        return "Next \(nextRunAt.formatted(date: .abbreviated, time: .shortened))"
    }

    private func latestRunStatusText(_ run: AppAutomationRun) -> String {
        switch run.status {
        case .succeeded:
            return "Last run succeeded"
        case .failed:
            return "Last run failed"
        }
    }
}

private extension AppAutomationRunStatus {
    var systemImage: String {
        switch self {
        case .succeeded:
            return "checkmark.circle"
        case .failed:
            return "xmark.octagon"
        }
    }
}

private struct AutomationEditorSheet: View {
    var mode: AutomationEditorMode
    var onSave: (String, String, String, String, Bool) -> Void
    var onCancel: () -> Void

    private let scheduleService = AutomationScheduleService()
    @State private var name: String
    @State private var prompt: String
    @State private var modelID: String
    @State private var rrule: String
    @State private var isActive: Bool
    @State private var previewReferenceDate: Date

    init(
        mode: AutomationEditorMode,
        onSave: @escaping (String, String, String, String, Bool) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.mode = mode
        self.onSave = onSave
        self.onCancel = onCancel
        _previewReferenceDate = State(initialValue: Date())
        switch mode {
        case .create(let defaultModelID):
            _name = State(initialValue: "")
            _prompt = State(initialValue: "")
            _modelID = State(initialValue: defaultModelID)
            _rrule = State(initialValue: "FREQ=DAILY")
            _isActive = State(initialValue: true)
        case .edit(let automation):
            _name = State(initialValue: automation.name)
            _prompt = State(initialValue: automation.prompt)
            _modelID = State(initialValue: automation.modelID)
            _rrule = State(initialValue: automation.rrule)
            _isActive = State(initialValue: automation.isActive)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(mode.title)
                .font(.title3)
                .fontWeight(.semibold)

            TextField("Name", text: $name)
                .textFieldStyle(.roundedBorder)

            TextEditor(text: $prompt)
                .font(.body)
                .frame(minHeight: 180)
                .overlay {
                    RoundedRectangle(cornerRadius: 5)
                        .stroke(.quaternary)
                }

            Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 10) {
                GridRow {
                    Text("Model")
                        .foregroundStyle(.secondary)
                    TextField("model-id", text: $modelID)
                        .textFieldStyle(.roundedBorder)
                }

                GridRow {
                    Text("Schedule")
                        .foregroundStyle(.secondary)
                    TextField("RRULE", text: $rrule)
                        .textFieldStyle(.roundedBorder)
                }

                GridRow {
                    Text("")
                    Label(schedulePreviewText, systemImage: schedulePreviewIcon)
                        .font(.caption)
                        .foregroundStyle(schedulePreview.isValid ? Color.secondary : Color.red)
                }

                GridRow {
                    Text("Status")
                        .foregroundStyle(.secondary)
                    Toggle("Enabled", isOn: $isActive)
                }
            }

            HStack {
                Spacer()
                Button("Cancel") {
                    onCancel()
                }
                Button("Save") {
                    onSave(name, prompt, modelID, rrule, isActive)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(isSaveDisabled)
            }
        }
        .padding(20)
        .frame(minWidth: 520, minHeight: 430)
    }

    private var schedulePreview: AutomationSchedulePreview {
        scheduleService.preview(
            for: rrule,
            createdAt: mode.previewCreatedAt ?? previewReferenceDate,
            lastRunAt: mode.previewLastRunAt,
            after: previewReferenceDate
        )
    }

    private var schedulePreviewText: String {
        guard let nextRunAt = schedulePreview.nextRunAt else {
            return schedulePreview.message
        }
        return "Next run \(nextRunAt.formatted(date: .abbreviated, time: .shortened))"
    }

    private var schedulePreviewIcon: String {
        schedulePreview.isValid ? "calendar.badge.clock" : "exclamationmark.triangle"
    }

    private var isSaveDisabled: Bool {
        name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || modelID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !schedulePreview.isValid
    }
}

private enum AutomationEditorMode: Identifiable {
    case create(defaultModelID: String)
    case edit(AppAutomation)

    var id: String {
        switch self {
        case .create:
            return "create"
        case .edit(let automation):
            return automation.id
        }
    }

    var title: String {
        switch self {
        case .create:
            return "New Automation"
        case .edit:
            return "Edit Automation"
        }
    }

    var previewCreatedAt: Date? {
        switch self {
        case .create:
            return nil
        case .edit(let automation):
            return automation.createdAt
        }
    }

    var previewLastRunAt: Date? {
        switch self {
        case .create:
            return nil
        case .edit(let automation):
            return automation.lastRunAt
        }
    }
}
