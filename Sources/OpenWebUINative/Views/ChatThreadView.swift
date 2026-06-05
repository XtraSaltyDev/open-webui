import SwiftUI

enum ChatTranscriptLayoutPolicy {
    static let horizontalMargin: CGFloat = 28
    static let verticalPadding: CGFloat = 20
    static let rowSpacing: CGFloat = 16
    static let minimumInterBubbleGap: CGFloat = 64
    static let minimumViewportWidth: CGFloat = 720
    static let intrinsicCollapseThreshold: CGFloat = 360
    static let maximumTranscriptWidth: CGFloat = 920
    static let maximumAssistantWidth: CGFloat = 720
    static let maximumUserPillWidth: CGFloat = 560

    static func viewportWidth(for proposedWidth: CGFloat, fallbackWidth: CGFloat?) -> CGFloat {
        let measuredWidth = max(proposedWidth, fallbackWidth ?? 0)
        guard measuredWidth < intrinsicCollapseThreshold else {
            return measuredWidth
        }
        return minimumViewportWidth
    }

    static func transcriptWidth(for viewportWidth: CGFloat) -> CGFloat {
        max(0, min(maximumTranscriptWidth, viewportWidth - (horizontalMargin * 2)))
    }

    static func bubbleWidthLimit(for transcriptWidth: CGFloat, role: ChatRole = .assistant) -> CGFloat {
        let roleLimit = role == .user ? maximumUserPillWidth : maximumAssistantWidth
        return max(0, min(roleLimit, transcriptWidth))
    }

    static func oppositeSideSpacerMinLength(for transcriptWidth: CGFloat) -> CGFloat {
        transcriptWidth > maximumUserPillWidth + minimumInterBubbleGap ? minimumInterBubbleGap : 0
    }
}

struct ChatMessageChromeStyle: Equatable {
    var showsHeader: Bool
    var showsContainer: Bool
    var horizontalPadding: CGFloat
    var verticalPadding: CGFloat
    var cornerRadius: CGFloat
    var contentSpacing: CGFloat

    static func style(for role: ChatRole) -> ChatMessageChromeStyle {
        switch role {
        case .user:
            ChatMessageChromeStyle(
                showsHeader: false,
                showsContainer: true,
                horizontalPadding: 14,
                verticalPadding: 9,
                cornerRadius: 18,
                contentSpacing: 6
            )
        case .assistant, .system:
            ChatMessageChromeStyle(
                showsHeader: true,
                showsContainer: false,
                horizontalPadding: 0,
                verticalPadding: 0,
                cornerRadius: 0,
                contentSpacing: 8
            )
        }
    }
}

struct ChatThreadView: View {
    @ObservedObject var store: AppStore
    var availableWidth: CGFloat?

    private var thread: ChatThread? {
        store.selectedThread
    }

    var body: some View {
        ScrollViewReader { proxy in
            GeometryReader { geometry in
                let viewportWidth = ChatTranscriptLayoutPolicy.viewportWidth(
                    for: geometry.size.width,
                    fallbackWidth: availableWidth
                )
                let transcriptWidth = ChatTranscriptLayoutPolicy.transcriptWidth(for: viewportWidth)

                ScrollView {
                    HStack(alignment: .top, spacing: 0) {
                        Spacer(minLength: ChatTranscriptLayoutPolicy.horizontalMargin)

                        LazyVStack(alignment: .center, spacing: ChatTranscriptLayoutPolicy.rowSpacing) {
                            if let thread, !thread.messages.isEmpty {
                                ForEach(thread.messages) { message in
                                    MessageRow(
                                        message: message,
                                        store: store,
                                        isFocused: message.id == store.focusedChatMessageID,
                                        transcriptWidth: transcriptWidth
                                    )
                                    .id(message.id)
                                }
                            } else {
                                ContentUnavailableView(
                                    "Start a Native Chat",
                                    systemImage: "bubble.left.and.bubble.right",
                                    description: Text("Choose a provider model and send a prompt.")
                                )
                                .frame(width: transcriptWidth)
                                .frame(minHeight: 420)
                            }
                        }
                        .frame(width: transcriptWidth, alignment: .top)

                        Spacer(minLength: ChatTranscriptLayoutPolicy.horizontalMargin)
                    }
                    .padding(.vertical, ChatTranscriptLayoutPolicy.verticalPadding)
                    .frame(minWidth: viewportWidth, minHeight: geometry.size.height, alignment: .top)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
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
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
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

private struct MessageRow: View {
    var message: ChatMessage
    @ObservedObject var store: AppStore
    var isFocused: Bool
    var transcriptWidth: CGFloat

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            if message.role == .user {
                Spacer(minLength: ChatTranscriptLayoutPolicy.oppositeSideSpacerMinLength(for: transcriptWidth))
            }

            MessageBubble(message: message, store: store, isFocused: isFocused)
                .frame(
                    maxWidth: ChatTranscriptLayoutPolicy.bubbleWidthLimit(for: transcriptWidth, role: message.role),
                    alignment: message.role == .user ? .trailing : .leading
                )

            if message.role != .user {
                Spacer(minLength: ChatTranscriptLayoutPolicy.oppositeSideSpacerMinLength(for: transcriptWidth))
            }
        }
        .frame(width: transcriptWidth, alignment: message.role == .user ? .trailing : .leading)
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
        let style = ChatMessageChromeStyle.style(for: message.role)
        VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 5) {
            messageContent(style: style)
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
                Button(message.error == nil ? "Regenerate" : "Retry") {
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
    }

    @ViewBuilder
    private func messageContent(style: ChatMessageChromeStyle) -> some View {
        VStack(alignment: .leading, spacing: style.contentSpacing) {
            if style.showsHeader {
                messageHeader
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
        }
        .padding(.horizontal, style.horizontalPadding)
        .padding(.vertical, style.verticalPadding)
        .background {
            if style.showsContainer {
                RoundedRectangle(cornerRadius: style.cornerRadius, style: .continuous)
                    .fill(messageContainerBackground)
            }
        }
        .overlay {
            if isFocused {
                RoundedRectangle(cornerRadius: max(style.cornerRadius, 8), style: .continuous)
                    .stroke(Color.accentColor, lineWidth: 2)
            }
        }
    }

    private var messageHeader: some View {
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
                Text("Generating...")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let rating = message.rating {
                Text(rating.label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var messageContainerBackground: Color {
        if isFocused {
            return Color.accentColor.opacity(0.24)
        }
        return Color.secondary.opacity(0.16)
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
                    Label(message.error == nil ? "Regenerate" : "Retry", systemImage: "arrow.clockwise")
                }
                .labelStyle(.iconOnly)
                .help(message.error == nil ? "Regenerate response" : "Retry response")
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
