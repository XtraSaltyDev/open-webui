import SwiftUI
import UniformTypeIdentifiers

struct ComposerView: View {
    @ObservedObject var store: AppStore
    @FocusState private var focused: Bool
    @State private var isImportingAttachment = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !store.pendingAttachments.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(store.pendingAttachments) { attachment in
                            PendingAttachmentPill(
                                attachment: attachment,
                                onRemove: {
                                    store.removePendingAttachment(id: attachment.id)
                                }
                            )
                        }
                    }
                }
            }

            if !store.canChat {
                Label("\(store.activeProvider.name) does not support native chat.", systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let composerInlineMessage = store.composerInlineMessage {
                Label(composerInlineMessage, systemImage: "exclamationmark.circle")
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            if !store.recentWebSearchResults.isEmpty {
                WebSearchPreviewStrip(
                    results: store.recentWebSearchResults,
                    telemetry: store.recentWebSearchTelemetry
                )
            }

            HStack(alignment: .bottom, spacing: 10) {
                Button {
                    isImportingAttachment = true
                } label: {
                    Label("Attach File", systemImage: "paperclip")
                }
                .labelStyle(.iconOnly)
                .help("Attach text or PDF file")
                .disabled(store.isSending)

                if store.isFeatureEnabled(.files), !store.files.isEmpty {
                    Menu {
                        ForEach(store.files) { file in
                            Button {
                                store.attachFileToChatContext(file.id)
                            } label: {
                                Label(file.fileName, systemImage: "doc.text")
                            }
                        }
                    } label: {
                        Label("Attach Saved File", systemImage: "tray.and.arrow.down")
                    }
                    .labelStyle(.iconOnly)
                    .help("Attach from saved files")
                    .disabled(store.isSending)
                }

                if store.isFeatureEnabled(.webSearch) {
                    Button {
                        store.isWebSearchEnabledForNextPrompt.toggle()
                    } label: {
                        Label("Web Search", systemImage: store.isWebSearchEnabledForNextPrompt ? "checkmark.circle" : "globe")
                    }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.bordered)
                    .tint(store.isWebSearchEnabledForNextPrompt ? .accentColor : nil)
                    .help(store.currentUserCanUseWebSearch ? "Search the web before sending" : "You do not have permission to use web search")
                    .disabled(store.isSending || !store.currentUserCanUseWebSearch)
                }

                TextField("Message \(store.activeProvider.name)...", text: $store.draftPrompt, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(1...6)
                    .focused($focused)

                if store.isSending {
                    if let progressText = store.chatGenerationProgressText {
                        Label(progressText, systemImage: "sparkles")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize()
                    }

                    Button {
                        store.cancelCurrentSend()
                    } label: {
                        Label("Stop", systemImage: "stop.fill")
                    }
                    .disabled(store.isCancellingSend)
                    .help("Stop generating")
                } else {
                    Button {
                        send()
                    } label: {
                        Label("Send", systemImage: "paperplane.fill")
                    }
                    .disabled(!store.canChat || store.isSending)
                    .keyboardShortcut(.return, modifiers: [.command])
                }
            }
        }
        .fileImporter(
            isPresented: $isImportingAttachment,
            allowedContentTypes: [.plainText, .text, .sourceCode, .pdf, UTType(filenameExtension: "md") ?? .plainText],
            allowsMultipleSelection: true
        ) { result in
            Task {
                do {
                    for url in try result.get() {
                        try await store.importAttachment(from: url)
                    }
                } catch {
                    store.errorMessage = error.localizedDescription
                }
            }
        }
        .onAppear {
            focused = true
        }
        .onExitCommand {
            focused = false
            store.clearComposerTransientState()
        }
    }

    private func send() {
        Task {
            if await store.sendDraftPrompt() {
                focused = true
            }
        }
    }
}

private struct WebSearchPreviewStrip: View {
    var results: [WebSearchResult]
    var telemetry: WebSearchTelemetry?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "globe")
                    .foregroundStyle(.secondary)
                Text(statusText)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            if let networkText = networkText {
                Text(networkText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Array(results.enumerated()), id: \.offset) { _, result in
                        WebSearchPreviewCard(result: result)
                    }
                }
            }
        }
    }

    private var statusText: String {
        guard let telemetry else {
            return "\(results.count) web result\(results.count == 1 ? "" : "s")"
        }

        let timestamp = telemetry.completedAt.formatted(date: .omitted, time: .shortened)
        return "\(telemetry.statusSummary) at \(timestamp)"
    }

    private var networkText: String? {
        telemetry?.networkSummary
    }
}

private struct WebSearchPreviewCard: View {
    var result: WebSearchResult

    private var host: String {
        result.url.host ?? result.url.absoluteString
    }

    private var previewText: String {
        let loadedText = result.pageContent?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return loadedText.isEmpty ? result.snippet : loadedText
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(result.title)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)

                Link(destination: result.url) {
                    Label("Open", systemImage: "arrow.up.forward.square")
                }
                .labelStyle(.iconOnly)
                .font(.caption)
                .help(result.url.absoluteString)
            }

            Text(host)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            if !previewText.isEmpty {
                Text(previewText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .frame(width: 240, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color.secondary.opacity(0.10))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

private struct PendingAttachmentPill: View {
    var attachment: ChatAttachment
    var onRemove: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "doc.text")
                .foregroundStyle(.secondary)
            Text(attachment.fileName)
                .lineLimit(1)
            Text(ByteCountFormatter.string(fromByteCount: Int64(attachment.byteCount), countStyle: .file))
                .foregroundStyle(.secondary)
            Button {
                onRemove()
            } label: {
                Label("Remove", systemImage: "xmark.circle.fill")
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.plain)
            .help("Remove attachment")
        }
        .font(.caption)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(Color.secondary.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}
