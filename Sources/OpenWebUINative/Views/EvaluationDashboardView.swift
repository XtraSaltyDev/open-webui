import SwiftUI

struct EvaluationSidebarView: View {
    @ObservedObject var store: AppStore

    var body: some View {
        Button {
            store.selectEvaluationDashboard()
        } label: {
            Label("Model Feedback", systemImage: "chart.bar.xaxis")
        }
        .buttonStyle(.plain)

        HStack {
            Button {
                store.importFeedbackJSONWithOpenPanel()
            } label: {
                Label("Import Feedback", systemImage: "square.and.arrow.down")
            }
            .help("Import feedback JSON")

            Menu {
                Button("Native JSON") {
                    store.exportFeedbackJSONWithSavePanel()
                }

                Button("Open WebUI JSON") {
                    store.exportFeedbackOpenWebUIJSONWithSavePanel()
                }
            } label: {
                Label("Export Feedback", systemImage: "square.and.arrow.up")
            }
            .help("Export feedback JSON")
            .disabled(store.feedbacks.isEmpty)
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.borderless)
        .font(.caption)
    }
}

struct EvaluationDashboardView: View {
    @ObservedObject var store: AppStore
    @State private var feedbackSearchText = ""

    private var filteredFeedbacks: [AppFeedback] {
        store.filteredFeedbacks(query: feedbackSearchText)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.horizontal, 20)
                .padding(.vertical, 14)

            Divider()

            if store.modelEvaluationSummaries.isEmpty {
                ContentUnavailableView(
                    "No Feedback",
                    systemImage: "chart.bar.xaxis",
                    description: Text("Feedback submitted from assistant messages will appear here.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        LazyVStack(alignment: .leading, spacing: 10) {
                            ForEach(store.modelEvaluationSummaries) { summary in
                                ModelEvaluationSummaryRow(summary: summary)
                            }
                        }
                        feedbackAdminSection
                    }
                    .padding(20)
                }
            }
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Evaluations")
                    .font(.title2.weight(.semibold))
                Text("\(store.feedbacks.count) feedback records")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                store.importFeedbackJSONWithOpenPanel()
            } label: {
                Label("Import", systemImage: "square.and.arrow.down")
            }
            .help("Import feedback JSON")

            Menu {
                Button("Native JSON") {
                    store.exportFeedbackJSONWithSavePanel()
                }

                Button("Open WebUI JSON") {
                    store.exportFeedbackOpenWebUIJSONWithSavePanel()
                }
            } label: {
                Label("Export", systemImage: "square.and.arrow.up")
            }
            .help("Export feedback JSON")
            .disabled(store.feedbacks.isEmpty)
        }
    }

    private var feedbackAdminSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Feedback Records")
                    .font(.headline)
                Text("\(filteredFeedbacks.count) shown")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                TextField("Search feedback", text: $feedbackSearchText)
                    .textFieldStyle(.roundedBorder)
                    .font(.caption)
                if !feedbackSearchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Button {
                        feedbackSearchText = ""
                    } label: {
                        Label("Clear search", systemImage: "xmark.circle.fill")
                    }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    .help("Clear feedback search")
                }
            }

            if filteredFeedbacks.isEmpty {
                Text("No feedback records match this search.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(filteredFeedbacks.prefix(12)) { feedback in
                        FeedbackAdminRow(
                            feedback: feedback,
                            onModerationStatusChange: { status in
                                Task {
                                    await store.updateFeedbackModerationStatus(feedback.id, status: status)
                                }
                            },
                            onDelete: {
                                Task {
                                    await store.deleteFeedback(feedback.id)
                                }
                            }
                        )
                    }
                }
            }
        }
    }
}

private struct ModelEvaluationSummaryRow: View {
    var summary: ModelEvaluationSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(summary.modelID)
                        .font(.headline)
                        .lineLimit(1)
                    Text("\(summary.count) feedback")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 3) {
                    Text("\(summary.rating)")
                        .font(.title3.monospacedDigit().weight(.semibold))
                    Text("Elo")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 16) {
                MetricLabel(title: "Won", value: summary.won)
                MetricLabel(title: "Lost", value: summary.lost)
                MetricLabel(title: "Positive", value: summary.positiveCount)
                MetricLabel(title: "Negative", value: summary.negativeCount)
            }

            if !summary.topTags.isEmpty {
                HStack(spacing: 6) {
                    ForEach(summary.topTags, id: \.tag) { tag in
                        Text("\(tag.tag) \(tag.count)")
                            .font(.caption)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(Color.secondary.opacity(0.12))
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

private struct MetricLabel: View {
    var title: String
    var value: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(value)")
                .font(.callout.monospacedDigit().weight(.semibold))
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(minWidth: 64, alignment: .leading)
    }
}

private struct FeedbackAdminRow: View {
    var feedback: AppFeedback
    var onModerationStatusChange: (AppFeedbackModerationStatus) -> Void
    var onDelete: () -> Void
    @State private var isConfirmingDelete = false

    private var ratingText: String {
        feedback.data.rating?.label ?? "Unrated"
    }

    private var modelText: String {
        feedback.data.modelID ?? "Unknown model"
    }

    private var detailText: String {
        feedback.data.comment
            ?? feedback.data.reason
            ?? feedback.snapshot?.chat?.title
            ?? feedback.id
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(ratingText)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(feedback.data.rating == .negative ? .red : .green)
                Text(modelText)
                    .font(.callout.weight(.semibold))
                    .lineLimit(1)
                Spacer()
                Menu {
                    ForEach(AppFeedbackModerationStatus.allCases, id: \.self) { status in
                        Button {
                            onModerationStatusChange(status)
                        } label: {
                            Label(status.label, systemImage: status.systemImageName)
                        }
                        .disabled(status == feedback.moderationStatus)
                    }
                } label: {
                    Label(feedback.moderationStatus.label, systemImage: feedback.moderationStatus.systemImageName)
                }
                .font(.caption)
                .menuStyle(.borderlessButton)
                .help("Set moderation status")
                Text(feedback.updatedAt, style: .relative)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button(role: .destructive) {
                    isConfirmingDelete = true
                } label: {
                    Label("Delete feedback", systemImage: "trash")
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .help("Delete feedback")
            }

            Text(detailText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)

            if !feedback.meta.tags.isEmpty {
                HStack(spacing: 6) {
                    ForEach(feedback.meta.tags.prefix(4), id: \.self) { tag in
                        Text(tag)
                            .font(.caption)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(Color.secondary.opacity(0.12))
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .confirmationDialog("Delete feedback record?", isPresented: $isConfirmingDelete) {
            Button("Delete Feedback", role: .destructive) {
                onDelete()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes the local feedback record and updates evaluation summaries.")
        }
    }
}
