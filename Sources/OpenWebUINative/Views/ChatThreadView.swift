import SwiftUI

struct ChatThreadView: View {
    @ObservedObject var store: AppStore

    private var thread: ChatThread? {
        store.selectedThread
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    if let thread, !thread.messages.isEmpty {
                        ForEach(thread.messages) { message in
                            MessageBubble(
                                message: message,
                                store: store,
                                isFocused: message.id == store.focusedChatMessageID
                            )
                                .id(message.id)
                        }
                    } else {
                        ContentUnavailableView(
                            "Start a Native Chat",
                            systemImage: "bubble.left.and.bubble.right",
                            description: Text("Choose a provider model and send a prompt.")
                        )
                        .frame(maxWidth: .infinity, minHeight: 420)
                    }
                }
                .padding()
            }
            .onChange(of: thread?.messages.last?.content) {
                if let lastID = thread?.messages.last?.id {
                    withAnimation {
                        proxy.scrollTo(lastID, anchor: .bottom)
                    }
                }
            }
            .onChange(of: store.focusedChatMessageID) {
                scrollToFocusedMessage(with: proxy)
            }
            .onAppear {
                scrollToFocusedMessage(with: proxy)
            }
        }
    }

    private func scrollToFocusedMessage(with proxy: ScrollViewProxy) {
        guard let focusedChatMessageID = store.focusedChatMessageID else {
            return
        }
        withAnimation {
            proxy.scrollTo(focusedChatMessageID, anchor: .center)
        }
    }
}

private struct MessageBubble: View {
    var message: ChatMessage
    @ObservedObject var store: AppStore
    var isFocused: Bool
    @State private var isEditing = false
    @State private var editedContent = ""
    @State private var isShowingFeedback = false
    @State private var feedbackRating: MessageRating = .positive
    @State private var feedbackReason = ""
    @State private var feedbackComment = ""

    var body: some View {
        HStack(alignment: .top) {
            if message.role == .user {
                Spacer(minLength: 80)
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Text(message.role == .user ? "You" : "Assistant")
                        .font(.caption.weight(.semibold))
                    if let modelID = message.modelID {
                        Text(modelID)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if let durationLabel = message.generationMetrics?.durationLabel {
                        Text(durationLabel)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if message.isStreaming {
                        ProgressView()
                            .controlSize(.small)
                    }
                    if let rating = message.rating {
                        Text(rating.label)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if isEditing {
                    TextField("Message", text: $editedContent, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .lineLimit(2...8)
                    HStack {
                        Button("Save") {
                            Task {
                                await store.editMessage(id: message.id, content: editedContent)
                                isEditing = false
                            }
                        }
                        Button("Cancel") {
                            isEditing = false
                        }
                    }
                    .font(.caption)
                } else {
                    MarkdownMessageView(content: message.content)
                }

                if !message.attachments.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(message.attachments) { attachment in
                            MessageAttachmentRow(attachment: attachment)
                        }
                    }
                }

                if !message.citations.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(message.citations) { citation in
                            MessageCitationRow(
                                citation: citation,
                                onOpenSource: {
                                    Task {
                                        await store.openCitationSource(citation)
                                    }
                                }
                            )
                        }
                    }
                }

                if let error = message.error {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                MessageActions(
                    message: message,
                    canRegenerate: store.canChat,
                    actionFunctions: store.activeActionFunctions,
                    canRunFunctions: store.currentUserCanInvokeFunctions,
                    onCopy: {
                        store.copyMessageToPasteboard(id: message.id)
                    },
                    onCopyLink: {
                        store.copyMessageLink(message.id)
                    },
                    onEdit: {
                        editedContent = message.content
                        isEditing = true
                    },
                    onRegenerate: {
                        Task {
                            await store.regenerateResponse(messageID: message.id)
                        }
                    },
                    onRate: { rating in
                        Task {
                            await store.rateMessage(id: message.id, rating: rating)
                        }
                    },
                    onFeedback: {
                        feedbackRating = message.rating ?? .positive
                        feedbackReason = ""
                        feedbackComment = ""
                        isShowingFeedback = true
                    },
                    onRunActionFunction: { function in
                        Task {
                            await store.runActionFunction(function.id, messageID: message.id)
                        }
                    },
                    onCancelBranch: {
                        store.cancelAssistantBranch(messageID: message.id)
                    }
                )
            }
            .padding(12)
            .background(bubbleBackground)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay {
                if isFocused {
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.accentColor, lineWidth: 2)
                }
            }
            .frame(maxWidth: 720, alignment: .leading)
            .contextMenu {
                Button("Copy") {
                    store.copyMessageToPasteboard(id: message.id)
                }
                Button("Copy Message Link") {
                    store.copyMessageLink(message.id)
                }
                Button("Edit") {
                    editedContent = message.content
                    isEditing = true
                }
                if message.role == .assistant {
                    if message.isStreaming {
                        Button("Stop This Response") {
                            store.cancelAssistantBranch(messageID: message.id)
                        }
                    }
                    Button("Regenerate") {
                        Task {
                            await store.regenerateResponse(messageID: message.id)
                        }
                    }
                    .disabled(!store.canChat || message.isStreaming)
                    Button("Rate Positive") {
                        Task {
                            await store.rateMessage(id: message.id, rating: .positive)
                        }
                    }
                    Button("Rate Negative") {
                        Task {
                            await store.rateMessage(id: message.id, rating: .negative)
                        }
                    }
                    Button("Give Feedback") {
                        feedbackRating = message.rating ?? .positive
                        feedbackReason = ""
                        feedbackComment = ""
                        isShowingFeedback = true
                    }
                    if !store.activeActionFunctions.isEmpty {
                        Divider()
                        ForEach(store.activeActionFunctions) { function in
                            Button(function.name) {
                                Task {
                                    await store.runActionFunction(function.id, messageID: message.id)
                                }
                            }
                            .disabled(!store.currentUserCanInvokeFunctions || message.isStreaming)
                        }
                    }
                }
            }
        .sheet(isPresented: $isShowingFeedback) {
                FeedbackSheet(
                    message: message,
                    rating: $feedbackRating,
                    reason: $feedbackReason,
                    comment: $feedbackComment,
                    onCancel: {
                        isShowingFeedback = false
                    },
                    onSubmit: {
                        let rating = feedbackRating
                        let reason = feedbackReason
                        let comment = feedbackComment
                        isShowingFeedback = false
                        Task {
                            await store.createFeedback(
                                messageID: message.id,
                                rating: rating,
                                reason: reason,
                                comment: comment
                            )
                        }
                    }
                )
            }

            if message.role != .user {
                Spacer(minLength: 80)
            }
        }
    }

    private var bubbleBackground: Color {
        if isFocused {
            return Color.accentColor.opacity(0.22)
        }
        return message.role == .user ? Color.accentColor.opacity(0.14) : Color.secondary.opacity(0.10)
    }
}

private struct MarkdownMessageView: View {
    var content: String
    private let parser = MarkdownMessageParser()
    private let renderer = MarkdownMessageRenderer()

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(parser.segments(from: content.isEmpty ? " " : content).enumerated()), id: \.offset) { _, segment in
                switch segment {
                case .markdown(let markdown):
                    Text(renderer.attributedString(from: markdown))
                        .textSelection(.enabled)
                case .math(let display, let content):
                    LatexMathView(display: display, content: content)
                case .code(let language, let code):
                    CodeBlockView(language: language, code: code)
                }
            }
        }
    }
}

private struct LatexMathView: View {
    var display: Bool
    var content: String

    var body: some View {
        Text(displayText)
            .font(display ? .system(.title3, design: .serif) : .system(.body, design: .serif))
            .textSelection(.enabled)
            .padding(.horizontal, display ? 10 : 4)
            .padding(.vertical, display ? 8 : 2)
            .frame(maxWidth: display ? .infinity : nil, alignment: .leading)
            .background(display ? Color.secondary.opacity(0.10) : Color.secondary.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: display ? 8 : 4))
            .accessibilityLabel("Math: \(content)")
    }

    private var displayText: String {
        content
            .replacingOccurrences(of: "\\,", with: " ")
            .replacingOccurrences(of: "\\pi", with: "π")
            .replacingOccurrences(of: "\\int", with: "∫")
            .replacingOccurrences(of: "\\sum", with: "∑")
            .replacingOccurrences(of: "\\sqrt", with: "√")
            .replacingOccurrences(of: "\\times", with: "×")
            .replacingOccurrences(of: "\\cdot", with: "·")
            .replacingOccurrences(of: "\\leq", with: "≤")
            .replacingOccurrences(of: "\\geq", with: "≥")
            .replacingOccurrences(of: "\\neq", with: "≠")
            .replacingOccurrences(of: "\\frac", with: "frac")
    }
}

private struct CodeBlockView: View {
    var language: String?
    var code: String
    private let highlighter = CodeSyntaxHighlighter()

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(language?.uppercased() ?? "CODE")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)

                Spacer()

                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(code, forType: .string)
                } label: {
                    Label("Copy Code", systemImage: "doc.on.doc")
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.plain)
                .help("Copy code")
            }

            ScrollView(.horizontal, showsIndicators: true) {
                Text(highlighter.attributedString(for: code, language: language))
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.bottom, 2)
            }
        }
        .padding(10)
        .background(Color.secondary.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

private struct MessageCitationRow: View {
    var citation: ChatCitation
    var onOpenSource: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Image(systemName: "quote.bubble")
                    .foregroundStyle(.secondary)
                Text("#\(citation.collectionSlug)")
                    .fontWeight(.semibold)
                Text(citation.sourceName)
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    onOpenSource()
                } label: {
                    Label("Open Source", systemImage: "arrow.up.forward.square")
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.plain)
                .help("Open source document")
                .disabled(citation.documentID == nil)
            }
            Text(citation.text)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .font(.caption)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(Color.secondary.opacity(0.10))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

private struct MessageAttachmentRow: View {
    var attachment: ChatAttachment

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "doc.text")
                .foregroundStyle(.secondary)
            Text(attachment.fileName)
                .lineLimit(1)
            Text(ByteCountFormatter.string(fromByteCount: Int64(attachment.byteCount), countStyle: .file))
                .foregroundStyle(.secondary)
        }
        .font(.caption)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(Color.secondary.opacity(0.10))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

private struct MessageActions: View {
    var message: ChatMessage
    var canRegenerate: Bool
    var actionFunctions: [AppFunction]
    var canRunFunctions: Bool
    var onCopy: () -> Void
    var onCopyLink: () -> Void
    var onEdit: () -> Void
    var onRegenerate: () -> Void
    var onRate: (MessageRating?) -> Void
    var onFeedback: () -> Void
    var onRunActionFunction: (AppFunction) -> Void
    var onCancelBranch: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Button {
                onCopy()
            } label: {
                Label("Copy", systemImage: "doc.on.doc")
            }
            .labelStyle(.iconOnly)
            .help("Copy message")

            Button {
                onCopyLink()
            } label: {
                Label("Copy Message Link", systemImage: "link")
            }
            .labelStyle(.iconOnly)
            .help("Copy message link")

            Button {
                onEdit()
            } label: {
                Label("Edit", systemImage: "pencil")
            }
            .labelStyle(.iconOnly)
            .help("Edit message")
            .disabled(message.isStreaming)

            if message.role == .assistant {
                if message.isStreaming {
                    Button {
                        onCancelBranch()
                    } label: {
                        Label("Stop This Response", systemImage: "stop.circle")
                    }
                    .labelStyle(.iconOnly)
                    .help("Stop this response")
                }

                Button {
                    onRegenerate()
                } label: {
                    Label("Regenerate", systemImage: "arrow.clockwise")
                }
                .labelStyle(.iconOnly)
                .help("Regenerate response")
                .disabled(!canRegenerate || message.isStreaming)

                Button {
                    onRate(message.rating == .positive ? nil : .positive)
                } label: {
                    Label("Rate Positive", systemImage: message.rating == .positive ? "hand.thumbsup.fill" : "hand.thumbsup")
                }
                .labelStyle(.iconOnly)
                .help("Rate positive")
                .disabled(message.isStreaming)

                Button {
                    onRate(message.rating == .negative ? nil : .negative)
                } label: {
                    Label("Rate Negative", systemImage: message.rating == .negative ? "hand.thumbsdown.fill" : "hand.thumbsdown")
                }
                .labelStyle(.iconOnly)
                .help("Rate negative")
                .disabled(message.isStreaming)

                Button {
                    onFeedback()
                } label: {
                    Label("Feedback", systemImage: "text.bubble")
                }
                .labelStyle(.iconOnly)
                .help("Add feedback")
                .disabled(message.isStreaming)

                if !actionFunctions.isEmpty {
                    Menu {
                        ForEach(actionFunctions) { function in
                            Button(function.name) {
                                onRunActionFunction(function)
                            }
                        }
                    } label: {
                        Label("Function Actions", systemImage: "function")
                    }
                    .labelStyle(.iconOnly)
                    .help("Run function action")
                    .disabled(!canRunFunctions || message.isStreaming)
                }
            }
        }
        .buttonStyle(.borderless)
        .font(.caption)
        .foregroundStyle(.secondary)
    }
}

private struct FeedbackSheet: View {
    var message: ChatMessage
    @Binding var rating: MessageRating
    @Binding var reason: String
    @Binding var comment: String
    var onCancel: () -> Void
    var onSubmit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Feedback")
                .font(.headline)

            Picker("Rating", selection: $rating) {
                Text("Positive").tag(MessageRating.positive)
                Text("Negative").tag(MessageRating.negative)
            }
            .pickerStyle(.segmented)

            TextField("Reason", text: $reason)
                .textFieldStyle(.roundedBorder)

            Text("Comment")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            TextEditor(text: $comment)
                .frame(minHeight: 120)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.secondary.opacity(0.22))
                )

            Text(message.content)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(3)
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.secondary.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 8))

            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                Button("Save", action: onSubmit)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(18)
        .frame(width: 420)
    }
}
