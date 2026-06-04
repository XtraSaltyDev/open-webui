import SwiftUI

struct AnalyticsSidebarView: View {
    @ObservedObject var store: AppStore

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                store.selectAnalyticsDashboard()
            } label: {
                Label("Usage Dashboard", systemImage: "chart.bar.doc.horizontal")
            }
            .buttonStyle(.plain)

            Button {
                store.exportAnalyticsJSONWithSavePanel()
            } label: {
                Label("Export Analytics", systemImage: "square.and.arrow.up")
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)
            .font(.caption)
            .help("Export analytics JSON")

            Button {
                store.exportAuditLogJSONWithSavePanel()
            } label: {
                Label("Export Audit Log", systemImage: "doc.badge.clock")
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)
            .font(.caption)
            .help("Export audit log JSON")
        }
    }
}

struct AnalyticsDashboardView: View {
    @ObservedObject var store: AppStore
    @State private var auditSearchText = ""
    @State private var selectedModelID: String?

    private var summary: AnalyticsSummary {
        store.analyticsSummary
    }

    private var filteredAuditEvents: [AppAuditEvent] {
        AuditEventFilter.filteredEvents(store.auditEvents, query: auditSearchText)
    }

    private var webSearchNetworkSummary: WebSearchNetworkHistorySummary {
        WebSearchNetworkHistorySummary(events: store.auditEvents)
    }

    private var auditResultSummary: String {
        AuditEventFilter.resultSummary(
            totalCount: store.auditEvents.count,
            filteredCount: filteredAuditEvents.count,
            query: auditSearchText
        )
    }

    private var isAuditSearchActive: Bool {
        AuditEventFilter.isQueryActive(auditSearchText)
    }

    private var effectiveSelectedModelID: String? {
        if let selectedModelID,
           summary.modelUsage.contains(where: { $0.modelID == selectedModelID }) {
            return selectedModelID
        }
        return summary.modelUsage.first?.modelID
    }

    private var selectedModelChats: [AnalyticsModelChat] {
        guard let effectiveSelectedModelID else {
            return []
        }
        return store.analyticsModelChats(modelID: effectiveSelectedModelID)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.horizontal, 20)
                .padding(.vertical, 14)

            if isAnalyticsFilterVisible {
                filterBar
                    .padding(.horizontal, 20)
                    .padding(.bottom, 12)
            }

            Divider()

            if summary.totalChats == 0 && summary.feedbackRecords == 0 && summary.knowledgeCollections == 0 && store.auditEvents.isEmpty {
                ContentUnavailableView(
                    "No Local Activity",
                    systemImage: "chart.bar.doc.horizontal",
                    description: Text("Chats, feedback, knowledge, audit events, and workspace records will appear here as you use the app.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        metricGrid
                        networkTransparencySection
                        modelUsageSection
                        modelChatDrilldownSection
                        dailyUsageSection
                        auditSection
                        workspaceSection
                    }
                    .padding(20)
                }
            }
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Analytics")
                    .font(.title2.weight(.semibold))
                Text("Local-only summary from persisted app data")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Label("No telemetry", systemImage: "lock.shield")
                .font(.caption)
                .foregroundStyle(.secondary)

            Button {
                store.exportAnalyticsJSONWithSavePanel()
            } label: {
                Label("Export", systemImage: "square.and.arrow.up")
            }
            .help("Export analytics JSON")

            Button {
                store.exportAuditLogJSONWithSavePanel()
            } label: {
                Label("Audit", systemImage: "doc.badge.clock")
            }
            .help("Export audit log JSON")
        }
    }

    private var isAnalyticsFilterVisible: Bool {
        !store.adminUsers.isEmpty || !store.adminGroups.isEmpty || store.analyticsFilter.isActive
    }

    private var selectedAnalyticsUserID: Binding<String> {
        Binding(
            get: { store.analyticsFilter.userIDs.sorted().first ?? "" },
            set: { store.setAnalyticsUserFilter($0.isEmpty ? nil : $0) }
        )
    }

    private var selectedAnalyticsGroupID: Binding<String> {
        Binding(
            get: { store.analyticsFilter.groupIDs.sorted().first ?? "" },
            set: { store.setAnalyticsGroupFilter($0.isEmpty ? nil : $0) }
        )
    }

    private var filterBar: some View {
        HStack(spacing: 10) {
            if !store.adminUsers.isEmpty || !store.analyticsFilter.userIDs.isEmpty {
                Picker("User", selection: selectedAnalyticsUserID) {
                    Text("All Users").tag("")
                    ForEach(store.adminUsers) { user in
                        Text(user.name).tag(user.id)
                    }
                }
                .pickerStyle(.menu)
                .frame(maxWidth: 220)
            }

            if !store.adminGroups.isEmpty || !store.analyticsFilter.groupIDs.isEmpty {
                Picker("Group", selection: selectedAnalyticsGroupID) {
                    Text("All Groups").tag("")
                    ForEach(store.adminGroups) { group in
                        Text(group.name).tag(group.id)
                    }
                }
                .pickerStyle(.menu)
                .frame(maxWidth: 220)
            }

            if store.analyticsFilter.isActive {
                Button {
                    store.clearAnalyticsFilter()
                } label: {
                    Label("Clear", systemImage: "xmark.circle")
                }
                .help("Clear analytics filters")
            }

            Spacer()
        }
    }

    private var metricGrid: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 10)], spacing: 10) {
            AnalyticsMetricTile(title: "Chats", value: summary.totalChats, detail: "\(summary.activeChats) active")
            AnalyticsMetricTile(title: "Messages", value: summary.totalMessages, detail: "\(summary.assistantMessages) assistant")
            AnalyticsMetricTile(title: "Models", value: summary.totalModels, detail: "\(summary.modelUsage.count) used")
            AnalyticsMetricTile(title: "Tokens", value: summary.totalTokens, detail: "\(summary.totalCompletionTokens) output")
            AnalyticsMetricTile(title: "Feedback", value: summary.feedbackRecords, detail: "\(summary.positiveFeedback) positive")
            AnalyticsMetricTile(title: "Knowledge", value: summary.knowledgeDocuments, detail: "\(summary.knowledgeCollections) collections")
            AnalyticsMetricTile(title: "Automations", value: summary.automations, detail: "\(summary.activeAutomations) active")
            AnalyticsMetricTile(title: "Audit Events", value: store.auditEvents.count, detail: "local log")
        }
    }

    private var modelUsageSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Model Usage")
                .font(.headline)

            if summary.modelUsage.isEmpty {
                Text("No assistant messages have model IDs yet.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(summary.modelUsage) { usage in
                        ModelUsageRow(
                            usage: usage,
                            maxMessageCount: summary.modelUsage.first?.messageCount ?? 1,
                            isSelected: effectiveSelectedModelID == usage.modelID
                        ) {
                            selectedModelID = usage.modelID
                        }
                    }
                }
            }
        }
    }

    private var modelChatDrilldownSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Model Chats")
                    .font(.headline)
                if let effectiveSelectedModelID {
                    Text(effectiveSelectedModelID)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            if selectedModelChats.isEmpty {
                Text("No matching model chats.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(selectedModelChats.prefix(8)) { chat in
                        ModelChatDrilldownRow(chat: chat) {
                            store.openAnalyticsModelChat(threadID: chat.threadID)
                        }
                    }
                }
            }
        }
    }

    private var workspaceSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Workspace")
                .font(.headline)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 10)], spacing: 10) {
                AnalyticsMetricTile(title: "Pinned Chats", value: summary.pinnedChats, detail: "\(summary.archivedChats) archived")
                AnalyticsMetricTile(title: "Channels", value: summary.channels, detail: "\(summary.channelMessages) messages")
                AnalyticsMetricTile(title: "Replies", value: summary.channelReplies, detail: "channel threads")
                AnalyticsMetricTile(title: "Notes", value: summary.notes, detail: "local notes")
                AnalyticsMetricTile(title: "Calendars", value: summary.calendars, detail: "\(summary.calendarEvents) events")
                AnalyticsMetricTile(title: "System Prompts", value: summary.systemMessages, detail: "chat messages")
            }
        }
    }

    private var dailyUsageSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Daily Model Activity")
                .font(.headline)

            if summary.dailyModelUsage.isEmpty {
                Text("No dated model activity yet.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(summary.dailyModelUsage.suffix(14)) { day in
                        DailyModelUsageRow(day: day)
                    }
                }
            }
        }
    }

    private var auditSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Audit Log")
                    .font(.headline)

                Spacer()

                Button {
                    store.exportAuditLogJSONWithSavePanel()
                } label: {
                    Label("Export", systemImage: "square.and.arrow.up")
                }
                .font(.caption)
                .help("Export audit log JSON")
            }

            if store.auditEvents.isEmpty {
                Text("Security-relevant local actions will appear here.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    TextField("Search audit log", text: $auditSearchText)
                        .textFieldStyle(.roundedBorder)
                        .font(.caption)
                    Text(auditResultSummary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                    if isAuditSearchActive {
                        Button {
                            auditSearchText = AuditEventFilter.clearedQuery(from: auditSearchText)
                        } label: {
                            Label("Clear search", systemImage: "xmark.circle.fill")
                        }
                        .labelStyle(.iconOnly)
                        .buttonStyle(.borderless)
                        .help(AuditEventFilter.clearSearchHelpText)
                    }
                }
                .onExitCommand {
                    auditSearchText = AuditEventFilter.clearedQuery(from: auditSearchText)
                }

                if filteredAuditEvents.isEmpty {
                    Text(AuditEventFilter.emptyResultText)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(filteredAuditEvents.prefix(12)) { event in
                        AuditEventRow(event: event) {
                            Task {
                                await store.deleteAuditEvent(event.id)
                            }
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var networkTransparencySection: some View {
        if webSearchNetworkSummary.hasHistory {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Network Transparency")
                        .font(.headline)
                    Spacer()
                    if let mostRecentRunAt = webSearchNetworkSummary.mostRecentRunAt {
                        Text("Updated \(mostRecentRunAt, style: .relative)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 10)], spacing: 10) {
                    AnalyticsMetricTile(
                        title: "Web Searches",
                        value: webSearchNetworkSummary.totalRuns,
                        detail: "\(webSearchNetworkSummary.succeededRuns) completed"
                    )
                    AnalyticsMetricTile(
                        title: "Hosts",
                        value: webSearchNetworkSummary.uniqueHostCount,
                        detail: "unique contacted"
                    )
                    AnalyticsMetricTile(
                        title: "API-key Runs",
                        value: webSearchNetworkSummary.apiKeyRuns,
                        detail: "Keychain-backed"
                    )
                    AnalyticsMetricTile(
                        title: "Blocked/Failed",
                        value: webSearchNetworkSummary.blockedRuns + webSearchNetworkSummary.failedRuns,
                        detail: "\(webSearchNetworkSummary.blockedRuns) blocked"
                    )
                }

                if !webSearchNetworkSummary.topHosts.isEmpty {
                    LazyVStack(alignment: .leading, spacing: 6) {
                        ForEach(webSearchNetworkSummary.topHosts.prefix(6)) { host in
                            NetworkHostSummaryRow(host: host)
                        }
                    }
                }
            }
        }
    }
}

private struct AnalyticsMetricTile: View {
    var title: String
    var value: Int
    var detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("\(value)")
                .font(.title3.monospacedDigit().weight(.semibold))
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.secondary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

private struct NetworkHostSummaryRow: View {
    var host: WebSearchNetworkHostSummary

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "network")
                .foregroundStyle(.secondary)
                .frame(width: 18)

            Text(host.host)
                .font(.caption.monospaced())
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer()

            Text("\(host.runCount)")
                .font(.caption.monospacedDigit().weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.secondary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

private struct ModelUsageRow: View {
    var usage: AnalyticsModelUsage
    var maxMessageCount: Int
    var isSelected: Bool
    var onSelect: () -> Void

    private var fraction: Double {
        guard maxMessageCount > 0 else {
            return 0
        }
        return Double(usage.messageCount) / Double(maxMessageCount)
    }

    private var tokenDetail: String {
        guard usage.totalTokens > 0 else {
            return "\(usage.chatCount) chats"
        }
        return "\(usage.chatCount) chats · \(usage.totalTokens) tokens"
    }

    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(usage.modelID)
                            .font(.callout.weight(.semibold))
                            .lineLimit(1)
                        Text(tokenDetail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Text("\(usage.messageCount)")
                        .font(.callout.monospacedDigit().weight(.semibold))
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }

                GeometryReader { proxy in
                    Capsule()
                        .fill(Color.secondary.opacity(0.14))
                        .overlay(alignment: .leading) {
                            Capsule()
                                .fill(Color.accentColor.opacity(0.7))
                                .frame(width: max(6, proxy.size.width * fraction))
                        }
                }
                .frame(height: 6)
            }
        }
        .buttonStyle(.plain)
        .padding(12)
        .background(isSelected ? Color.accentColor.opacity(0.12) : Color.secondary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

private struct ModelChatDrilldownRow: View {
    var chat: AnalyticsModelChat
    var onOpen: () -> Void

    private var tokenDetail: String {
        guard chat.totalTokens > 0 else {
            return "\(chat.messageCount) messages"
        }
        return "\(chat.messageCount) messages · \(chat.totalTokens) tokens"
    }

    var body: some View {
        Button(action: onOpen) {
            HStack(alignment: .center, spacing: 10) {
                Image(systemName: "bubble.left.and.bubble.right")
                    .foregroundStyle(.secondary)
                    .frame(width: 18)

                VStack(alignment: .leading, spacing: 3) {
                    Text(chat.title)
                        .font(.callout.weight(.semibold))
                        .lineLimit(1)
                    Text(tokenDetail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Text(chat.lastMessageAt, style: .relative)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(12)
            .background(Color.secondary.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }
}

private struct DailyModelUsageRow: View {
    var day: AnalyticsDailyModelUsage

    private var total: Int {
        day.models.values.reduce(0, +)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(day.date)
                    .font(.callout.weight(.semibold))

                Spacer()

                Text("\(total)")
                    .font(.callout.monospacedDigit().weight(.semibold))
            }

            ForEach(sortedModels, id: \.modelID) { entry in
                HStack {
                    Text(entry.modelID)
                        .font(.caption)
                        .lineLimit(1)
                    Spacer()
                    Text("\(entry.count)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(12)
        .background(Color.secondary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var sortedModels: [(modelID: String, count: Int)] {
        day.models.map { (modelID: $0.key, count: $0.value) }
            .sorted { lhs, rhs in
                if lhs.count != rhs.count {
                    return lhs.count > rhs.count
                }
                return lhs.modelID.localizedStandardCompare(rhs.modelID) == .orderedAscending
            }
    }
}

private struct AuditEventRow: View {
    var event: AppAuditEvent
    var onDelete: () -> Void

    @State private var isShowingAllMetadata = false

    private var metadataPresentation: AuditEventMetadataPresentation {
        AuditEventMetadataFormatter.presentation(for: event)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: iconName)
                .foregroundStyle(iconColor)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(event.action.label)
                        .font(.callout.weight(.semibold))
                    Text(event.outcome.label)
                        .font(.caption)
                        .foregroundStyle(iconColor)
                    Spacer()
                    Text(event.createdAt, style: .relative)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Text(event.summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)

                if !metadataPresentation.previewRows.isEmpty {
                    VStack(alignment: .leading, spacing: 3) {
                        ForEach(metadataPresentation.previewRows) { row in
                            AuditMetadataLine(row: row)
                        }

                        if !metadataPresentation.overflowRows.isEmpty {
                            DisclosureGroup(
                                isExpanded: $isShowingAllMetadata,
                                content: {
                                    VStack(alignment: .leading, spacing: 3) {
                                        ForEach(metadataPresentation.overflowRows) { row in
                                            AuditMetadataLine(row: row, allowsWrapping: true)
                                        }
                                    }
                                    .padding(.top, 2)
                                },
                                label: {
                                    Text("\(metadataPresentation.overflowCount) more details")
                                        .font(.caption2.weight(.medium))
                                        .foregroundStyle(.secondary)
                                }
                            )
                            .disclosureGroupStyle(.automatic)
                        }
                    }
                }
            }

            Button(role: .destructive, action: onDelete) {
                Label("Delete", systemImage: "trash")
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)
            .help("Delete audit event")
        }
        .padding(12)
        .background(Color.secondary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var iconName: String {
        switch event.outcome {
        case .succeeded:
            return "checkmark.seal"
        case .failed:
            return "xmark.octagon"
        case .blocked:
            return "hand.raised"
        }
    }

    private var iconColor: Color {
        switch event.outcome {
        case .succeeded:
            return .green
        case .failed:
            return .red
        case .blocked:
            return .orange
        }
    }
}

private struct AuditMetadataLine: View {
    var row: AuditEventMetadataRow
    var allowsWrapping = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(row.label)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 68, alignment: .leading)
            Text(row.value)
                .font(.caption2.monospaced())
                .foregroundStyle(.secondary)
                .lineLimit(allowsWrapping ? 3 : 1)
                .truncationMode(.middle)
        }
    }
}
