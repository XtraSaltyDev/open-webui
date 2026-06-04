import SwiftUI
import UniformTypeIdentifiers

struct SidebarView: View {
    @ObservedObject var store: AppStore
    @State private var newFolderName = ""
    @State private var newKnowledgeName = ""
    @State private var editingKnowledgeCollectionID: UUID?
    @State private var editingKnowledgeCollectionName = ""
    @State private var editingKnowledgeCollectionAllowedUserIDs = ""
    @State private var editingKnowledgeCollectionAllowedGroupIDs = ""
    @State private var editingKnowledgeDocumentID: UUID?
    @State private var editingKnowledgeDocumentName = ""
    @State private var pendingKnowledgeFileAction: KnowledgeFileAction?
    @State private var isShowingArchiveAllConfirmation = false
    @State private var isShowingDeleteAllConfirmation = false

    private var isTranscriptSearchActive: Bool {
        !store.chatTranscriptSearchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        List(selection: Binding(
            get: { store.selectedThreadID },
            set: { threadID in
                store.selectedThreadID = threadID
                store.focusedChatMessageID = nil
                if threadID != nil {
                    store.selectedChannelID = nil
                    store.isShowingEvaluationDashboard = false
                    store.isShowingAnalyticsDashboard = false
                    store.isShowingPlayground = false
                    store.isShowingFiles = false
                    store.isShowingCalendar = false
                    store.isShowingImageGeneration = false
                    store.isShowingAudio = false
                    store.isShowingCodeInterpreter = false
                    store.clearSelectedKnowledgeDocument()
                }
            }
        )) {
            Section {
                TextField("Search chats", text: $store.sidebarSearchText)
                    .textFieldStyle(.roundedBorder)
                TextField("Search messages", text: $store.chatTranscriptSearchText)
                    .textFieldStyle(.roundedBorder)
                if isTranscriptSearchActive {
                    transcriptSearchResults
                }
            }

            if store.isFeatureEnabled(.folders), !store.folders.isEmpty {
                Section("Folders") {
                    ForEach(store.folders) { folder in
                        DisclosureGroup {
                            let folderThreads = store.filteredThreads(folderID: folder.id)
                            if folderThreads.isEmpty {
                                Text("No chats")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            } else {
                                ForEach(folderThreads) { thread in
                                    ChatRow(thread: thread, store: store)
                                        .tag(thread.id)
                                }
                            }
                        } label: {
                            Label(folder.name, systemImage: "folder")
                        }
                        .contextMenu {
                            Button("Delete Folder") {
                                Task {
                                    await store.deleteFolder(folder.id)
                                }
                            }
                        }
                    }
                }
            }

            Section("Recent Chats") {
                if store.threads.contains(where: { !$0.isArchived }) {
                    HStack {
                        Button {
                            isShowingArchiveAllConfirmation = true
                        } label: {
                            Label("Archive All Chats", systemImage: "archivebox")
                        }
                        .buttonStyle(.borderless)
                        .help("Archive all chats")

                        Button {
                            store.exportAllThreadsJSONWithSavePanel()
                        } label: {
                            Label("Export All Chats", systemImage: "square.and.arrow.up")
                        }
                        .buttonStyle(.borderless)
                        .help("Export all chats JSON")

                        Button {
                            isShowingDeleteAllConfirmation = true
                        } label: {
                            Label("Delete All Chats", systemImage: "trash")
                        }
                        .buttonStyle(.borderless)
                        .help("Delete all chats")
                    }
                    .font(.caption)
                } else if !store.threads.isEmpty {
                    HStack {
                        Button {
                            store.exportAllThreadsJSONWithSavePanel()
                        } label: {
                            Label("Export All Chats", systemImage: "square.and.arrow.up")
                        }
                        .buttonStyle(.borderless)
                        .help("Export all chats JSON")

                        Button {
                            isShowingDeleteAllConfirmation = true
                        } label: {
                            Label("Delete All Chats", systemImage: "trash")
                        }
                        .buttonStyle(.borderless)
                        .help("Delete all chats")
                    }
                    .font(.caption)
                }

                ForEach(store.filteredThreads()) { thread in
                    ChatRow(thread: thread, store: store)
                        .tag(thread.id)
                }
            }

            let archivedThreads = store.filteredArchivedThreads()
            if !archivedThreads.isEmpty {
                Section("Archive") {
                    DisclosureGroup {
                        HStack {
                            Button {
                                Task {
                                    await store.unarchiveAllArchivedThreads()
                                }
                            } label: {
                                Label("Unarchive All", systemImage: "tray.and.arrow.up")
                            }
                            .labelStyle(.iconOnly)
                            .buttonStyle(.borderless)
                            .help("Unarchive all chats")

                            Button {
                                store.exportArchivedThreadsJSONWithSavePanel()
                            } label: {
                                Label("Export Archived Chats", systemImage: "square.and.arrow.up")
                            }
                            .labelStyle(.iconOnly)
                            .buttonStyle(.borderless)
                            .help("Export archived chats JSON")
                        }
                        .font(.caption)

                        ForEach(archivedThreads) { thread in
                            ChatRow(thread: thread, store: store)
                                .tag(thread.id)
                        }
                    } label: {
                        Label("Archived Chats", systemImage: "archivebox")
                    }
                }
            }

            if store.isFeatureEnabled(.prompts) {
                Section("Prompts") {
                    PromptLibraryView(store: store)
                }
            }

            if store.isFeatureEnabled(.files) {
                Section("Files") {
                    FileLibrarySidebarView(store: store)
                }
            }

            if store.isFeatureEnabled(.notes) {
                Section("Notes") {
                    NoteLibraryView(store: store)
                }
            }

            if store.isFeatureEnabled(.channels) {
                Section("Channels") {
                    ChannelLibraryView(store: store)
                }
            }

            if store.isFeatureEnabled(.automations) {
                Section("Automations") {
                    AutomationLibraryView(store: store)
                }
            }

            if store.isFeatureEnabled(.calendar) {
                Section("Calendar") {
                    CalendarSidebarView(store: store)
                }
            }

            if store.isFeatureEnabled(.tools) {
                Section("Tools") {
                    ToolLibraryView(store: store)
                }
            }

            if store.isFeatureEnabled(.directToolServers) {
                Section("Tool Servers") {
                    ToolServerLibraryView(store: store)
                }
            }

            if store.isFeatureEnabled(.skills) {
                Section("Skills") {
                    SkillLibraryView(store: store)
                }
            }

            if store.isFeatureEnabled(.functions) {
                Section("Functions") {
                    FunctionLibraryView(store: store)
                }
            }

            if store.isFeatureEnabled(.evaluations) {
                Section("Evaluations") {
                    EvaluationSidebarView(store: store)
                }
            }

            if store.isFeatureEnabled(.analytics) {
                Section("Analytics") {
                    AnalyticsSidebarView(store: store)
                }
            }

            if store.isFeatureEnabled(.playground) {
                Section("Playground") {
                    PlaygroundSidebarView(store: store)
                }
            }

            if store.isFeatureEnabled(.imageGeneration) {
                Section("Images") {
                    ImageGenerationSidebarView(store: store)
                }
            }

            if store.isFeatureEnabled(.audio) {
                Section("Audio") {
                    AudioSidebarView(store: store)
                }
            }

            if store.isFeatureEnabled(.codeInterpreter) {
                Section("Code") {
                    CodeInterpreterSidebarView(store: store)
                }
            }

            if store.isFeatureEnabled(.terminalSessions) {
                Section("Terminal") {
                    TerminalSessionSidebarView(store: store)
                }
            }

            if store.isFeatureEnabled(.adminDirectory) {
                Section("Admin") {
                    AdminDirectoryView(store: store)
                }
            }

            if store.isFeatureEnabled(.knowledge) {
                Section("Knowledge") {
                    if !store.canCreateEmbeddings {
                        Label("Active provider cannot create embeddings.", systemImage: "exclamationmark.triangle")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if store.knowledgeCollections.isEmpty {
                        Text("No collections")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(store.knowledgeCollections) { collection in
                            KnowledgeCollectionRow(
                                collection: collection,
                                documents: store.knowledgeDocuments[collection.id] ?? [],
                                notes: store.notes,
                                canImportDocuments: store.canCreateEmbeddings,
                                canManageKnowledge: store.currentUserCanManageKnowledge,
                                onImport: {
                                    pendingKnowledgeFileAction = KnowledgeFileAction(collectionID: collection.id, mode: .import)
                                },
                                onImportNote: { note in
                                    Task {
                                        await store.importNoteToKnowledge(note.id, toCollectionID: collection.id)
                                    }
                                },
                                onReindex: {
                                    pendingKnowledgeFileAction = KnowledgeFileAction(collectionID: collection.id, mode: .reindex)
                                },
                                onShare: {
                                    Task {
                                        await store.shareKnowledgeCollection(collection.id)
                                    }
                                },
                                onRename: {
                                    editingKnowledgeCollectionID = collection.id
                                    editingKnowledgeCollectionName = collection.name
                                    editingKnowledgeCollectionAllowedUserIDs = collection.allowedUserIDs.joined(separator: ", ")
                                    editingKnowledgeCollectionAllowedGroupIDs = collection.allowedGroupIDs.joined(separator: ", ")
                                    editingKnowledgeDocumentID = nil
                                    editingKnowledgeDocumentName = ""
                                },
                                onDelete: {
                                    Task {
                                        await store.deleteKnowledgeCollection(collection.id)
                                    }
                                },
                                onRenameDocument: { document in
                                    editingKnowledgeDocumentID = document.id
                                    editingKnowledgeDocumentName = document.fileName
                                    editingKnowledgeCollectionID = nil
                                    editingKnowledgeCollectionName = ""
                                    editingKnowledgeCollectionAllowedUserIDs = ""
                                    editingKnowledgeCollectionAllowedGroupIDs = ""
                                },
                                onDeleteDocument: { document in
                                    Task {
                                        await store.deleteKnowledgeDocument(document.id)
                                    }
                                },
                                onSelectDocument: { document in
                                    Task {
                                        await store.selectKnowledgeDocument(document.id)
                                    }
                                }
                            )
                        }
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 8) {
                if store.isFeatureEnabled(.folders) {
                    HStack {
                        TextField("New folder", text: $newFolderName)
                            .textFieldStyle(.roundedBorder)
                        Button {
                            Task {
                                await store.createFolder(named: newFolderName)
                                newFolderName = ""
                            }
                        } label: {
                            Label("Add Folder", systemImage: "folder.badge.plus")
                        }
                        .labelStyle(.iconOnly)
                        .disabled(newFolderName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }

                if store.isFeatureEnabled(.knowledge) {
                    if let editingKnowledgeCollectionID {
                        VStack(spacing: 6) {
                            TextField("Collection name", text: $editingKnowledgeCollectionName)
                                .textFieldStyle(.roundedBorder)

                            HStack {
                                TextField("Allowed user IDs", text: $editingKnowledgeCollectionAllowedUserIDs)
                                    .textFieldStyle(.roundedBorder)
                                TextField("Allowed group IDs", text: $editingKnowledgeCollectionAllowedGroupIDs)
                                    .textFieldStyle(.roundedBorder)
                            }

                            HStack {
                                Button {
                                    Task {
                                        await store.updateKnowledgeCollection(
                                            editingKnowledgeCollectionID,
                                            name: editingKnowledgeCollectionName,
                                            allowedUserIDs: parsedCommaSeparatedValues(editingKnowledgeCollectionAllowedUserIDs),
                                            allowedGroupIDs: parsedCommaSeparatedValues(editingKnowledgeCollectionAllowedGroupIDs)
                                        )
                                        self.editingKnowledgeCollectionID = nil
                                        editingKnowledgeCollectionName = ""
                                        editingKnowledgeCollectionAllowedUserIDs = ""
                                        editingKnowledgeCollectionAllowedGroupIDs = ""
                                    }
                                } label: {
                                    Label("Save Collection", systemImage: "checkmark")
                                }
                                .labelStyle(.iconOnly)
                                .disabled(editingKnowledgeCollectionName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                                Button {
                                    self.editingKnowledgeCollectionID = nil
                                    editingKnowledgeCollectionName = ""
                                    editingKnowledgeCollectionAllowedUserIDs = ""
                                    editingKnowledgeCollectionAllowedGroupIDs = ""
                                } label: {
                                    Label("Cancel", systemImage: "xmark")
                                }
                                .labelStyle(.iconOnly)
                            }
                        }
                    }

                    if let editingKnowledgeDocumentID {
                        HStack {
                            TextField("Document name", text: $editingKnowledgeDocumentName)
                                .textFieldStyle(.roundedBorder)
                            Button {
                                Task {
                                    await store.updateKnowledgeDocument(
                                        editingKnowledgeDocumentID,
                                        fileName: editingKnowledgeDocumentName
                                    )
                                    self.editingKnowledgeDocumentID = nil
                                    editingKnowledgeDocumentName = ""
                                }
                            } label: {
                                Label("Save Document", systemImage: "checkmark")
                            }
                            .labelStyle(.iconOnly)
                            .disabled(editingKnowledgeDocumentName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            Button {
                                self.editingKnowledgeDocumentID = nil
                                editingKnowledgeDocumentName = ""
                            } label: {
                                Label("Cancel", systemImage: "xmark")
                            }
                            .labelStyle(.iconOnly)
                        }
                    }

                    HStack {
                        TextField("New knowledge", text: $newKnowledgeName)
                            .textFieldStyle(.roundedBorder)
                        Button {
                            store.importKnowledgeJSONWithOpenPanel()
                        } label: {
                            Label("Import Knowledge", systemImage: "square.and.arrow.down")
                        }
                        .labelStyle(.iconOnly)
                        .disabled(!store.currentUserCanManageKnowledge)
                        .help("Import knowledge JSON")
                        Button {
                            store.exportKnowledgeJSONWithSavePanel()
                        } label: {
                            Label("Export Knowledge", systemImage: "square.and.arrow.up")
                        }
                        .labelStyle(.iconOnly)
                        .disabled(store.knowledgeCollections.isEmpty)
                        .help("Export knowledge JSON")
                        Button {
                            Task {
                                await store.createKnowledgeCollection(named: newKnowledgeName)
                                newKnowledgeName = ""
                            }
                        } label: {
                            Label("Add Knowledge", systemImage: "books.vertical")
                        }
                        .labelStyle(.iconOnly)
                        .disabled(
                            !store.currentUserCanManageKnowledge ||
                            newKnowledgeName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        )
                    }
                }

                HStack {
                    Button {
                        store.createThread()
                    } label: {
                        Label("New Chat", systemImage: "plus")
                    }
                    .buttonStyle(.borderless)

                    Spacer()
                }
            }
            .padding(10)
        }
        .fileImporter(
            isPresented: Binding(
                get: { pendingKnowledgeFileAction != nil },
                set: { if !$0 { pendingKnowledgeFileAction = nil } }
            ),
            allowedContentTypes: [.plainText, .text, .sourceCode, .pdf, UTType(filenameExtension: "md") ?? .plainText],
            allowsMultipleSelection: true
        ) { result in
            guard let action = pendingKnowledgeFileAction else {
                return
            }
            pendingKnowledgeFileAction = nil
            Task {
                do {
                    for url in try result.get() {
                        switch action.mode {
                        case .import:
                            await store.importKnowledgeDocument(from: url, toCollectionID: action.collectionID)
                        case .reindex:
                            await store.reindexKnowledgeDocument(from: url, toCollectionID: action.collectionID)
                        }
                    }
                } catch {
                    store.errorMessage = error.localizedDescription
                }
            }
        }
        .navigationTitle("Open WebUI")
        .alert("Archive All Chats?", isPresented: $isShowingArchiveAllConfirmation) {
            Button("Archive All", role: .destructive) {
                Task {
                    await store.archiveAllThreads()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("All chats will move to Archived Chats.")
        }
        .alert("Delete All Chats?", isPresented: $isShowingDeleteAllConfirmation) {
            Button("Delete All", role: .destructive) {
                Task {
                    await store.deleteAllThreads()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("All chats will be permanently deleted.")
        }
    }

    @ViewBuilder
    private var transcriptSearchResults: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Message Matches")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            if store.chatTranscriptSearchResults.isEmpty {
                Text("No messages match.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(Array(store.chatTranscriptSearchResults.prefix(6))) { result in
                    Button {
                        store.selectChatSearchResult(result)
                    } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 6) {
                                Image(systemName: result.role == .user ? "person.fill" : "sparkles")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                Text(result.threadTitle)
                                    .font(.caption.weight(.semibold))
                                    .lineLimit(1)
                                Spacer(minLength: 4)
                                Text(result.role.rawValue.capitalized)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            Text(result.snippet)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                    .help("Open matching chat message")
                }

                if store.chatTranscriptSearchResults.count > 6 {
                    Text("\(store.chatTranscriptSearchResults.count - 6) more matches")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.top, 2)
    }
}

private struct KnowledgeCollectionRow: View {
    var collection: KnowledgeCollection
    var documents: [KnowledgeDocument]
    var notes: [AppNote]
    var canImportDocuments: Bool
    var canManageKnowledge: Bool
    var onImport: () -> Void
    var onImportNote: (AppNote) -> Void
    var onReindex: () -> Void
    var onShare: () -> Void
    var onRename: () -> Void
    var onDelete: () -> Void
    var onRenameDocument: (KnowledgeDocument) -> Void
    var onDeleteDocument: (KnowledgeDocument) -> Void
    var onSelectDocument: (KnowledgeDocument) -> Void

    var body: some View {
        DisclosureGroup {
            if documents.isEmpty {
                Text("No documents")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(documents) { document in
                    KnowledgeDocumentRow(
                        document: document,
                        canDelete: canManageKnowledge,
                        onSelect: {
                            onSelectDocument(document)
                        },
                        onRename: {
                            onRenameDocument(document)
                        },
                        onDelete: {
                            onDeleteDocument(document)
                        }
                    )
                }
            }
        } label: {
            HStack {
                Label(collection.name, systemImage: "books.vertical")
                Spacer()
                Text("#\(collection.slug)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Menu {
                    knowledgeActions
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton)
                .help("Knowledge actions")
            }
        }
        .contextMenu {
            knowledgeActions
        }
    }

    @ViewBuilder
    private var knowledgeActions: some View {
        if !canManageKnowledge {
            Label("You do not have permission to manage knowledge.", systemImage: "lock")
        }
        if !canImportDocuments {
            Label("Active provider cannot create embeddings.", systemImage: "exclamationmark.triangle")
        }
        Button("Import File...") {
            onImport()
        }
        .disabled(!canManageKnowledge || !canImportDocuments)
        Menu("Import Note") {
            if notes.isEmpty {
                Text("No notes")
            } else {
                ForEach(notes) { note in
                    Button(note.title) {
                        onImportNote(note)
                    }
                }
            }
        }
        .disabled(!canManageKnowledge || !canImportDocuments || notes.isEmpty)
        Button("Reindex File...") {
            onReindex()
        }
        .disabled(!canManageKnowledge || !canImportDocuments)
        Button("Share Collection...") {
            onShare()
        }
        Button("Rename Collection") {
            onRename()
        }
        .disabled(!canManageKnowledge)
        Divider()
        Button("Delete Collection", role: .destructive) {
            onDelete()
        }
        .disabled(!canManageKnowledge)
    }
}

private struct KnowledgeDocumentRow: View {
    var document: KnowledgeDocument
    var canDelete: Bool
    var onSelect: () -> Void
    var onRename: () -> Void
    var onDelete: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Button {
                onSelect()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: document.contentType == "application/pdf" ? "doc.richtext" : "doc.text")
                        .foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(document.fileName)
                            .lineLimit(1)
                        Text(ByteCountFormatter.string(fromByteCount: Int64(document.byteCount), countStyle: .file))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .buttonStyle(.plain)
            Spacer()
            Button {
                onDelete()
            } label: {
                Label("Delete Document", systemImage: "trash")
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)
            .disabled(!canDelete)
            .help("Delete document")
        }
        .font(.caption)
        .contextMenu {
            Button("Rename Document") {
                onRename()
            }
            .disabled(!canDelete)
            Button("Delete Document", role: .destructive) {
                onDelete()
            }
            .disabled(!canDelete)
        }
    }
}

private struct KnowledgeFileAction {
    var collectionID: UUID
    var mode: KnowledgeFileActionMode
}

private enum KnowledgeFileActionMode {
    case `import`
    case reindex
}

private struct ChatRow: View {
    var thread: ChatThread
    @ObservedObject var store: AppStore
    @State private var isShowingTagSheet = false
    @State private var isShowingRenameSheet = false

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 5) {
                Text(thread.title)
                    .lineLimit(1)
                if thread.isPinned {
                    Image(systemName: "pin.fill")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("Pinned chat")
                }
                if thread.isArchived {
                    Image(systemName: "archivebox.fill")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("Archived chat")
                }
            }
            Text(thread.updatedAt, style: .relative)
                .font(.caption)
                .foregroundStyle(.secondary)
            if !thread.tags.isEmpty {
                Text(thread.tags.map { "#\($0)" }.joined(separator: " "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .contextMenu {
            if !store.folders.isEmpty {
                Menu("Move to Folder") {
                    ForEach(store.folders) { folder in
                        Button(folder.name) {
                            Task {
                                await store.assignThread(thread.id, toFolder: folder.id)
                            }
                        }
                    }
                    if thread.folderID != nil {
                        Divider()
                        Button("Remove from Folder") {
                            Task {
                                await store.assignThread(thread.id, toFolder: nil)
                            }
                        }
                    }
                }
            }

            Button("Rename...") {
                isShowingRenameSheet = true
            }

            Button("Clone Chat") {
                Task {
                    await store.cloneThread(thread.id)
                }
            }

            Button("Copy Chat Link") {
                store.copyChatLink(thread.id)
            }

            Button(thread.isPinned ? "Unpin Chat" : "Pin Chat") {
                Task {
                    await store.toggleThreadPinned(thread.id)
                }
            }

            Button(thread.isArchived ? "Unarchive Chat" : "Archive Chat") {
                Task {
                    await store.toggleThreadArchived(thread.id)
                }
            }

            Button("Add Tag...") {
                isShowingTagSheet = true
            }

            if !thread.tags.isEmpty {
                Menu("Remove Tag") {
                    ForEach(thread.tags, id: \.self) { tag in
                        Button("#\(tag)") {
                            Task {
                                await store.removeTag(tag, from: thread.id)
                            }
                        }
                    }
                }
            }

            Button("Delete") {
                Task {
                    store.selectedThreadID = thread.id
                    await store.deleteSelectedThread()
                }
            }
        }
        .sheet(isPresented: $isShowingTagSheet) {
            AddTagSheet(thread: thread, store: store)
        }
        .sheet(isPresented: $isShowingRenameSheet) {
            RenameThreadSheet(thread: thread, store: store)
        }
    }
}

private struct RenameThreadSheet: View {
    var thread: ChatThread
    @ObservedObject var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var title: String

    init(thread: ChatThread, store: AppStore) {
        self.thread = thread
        self.store = store
        _title = State(initialValue: thread.title)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Rename Chat")
                .font(.headline)
            TextField("Title", text: $title)
                .textFieldStyle(.roundedBorder)
            HStack {
                Spacer()
                Button("Cancel") {
                    dismiss()
                }
                Button("Rename") {
                    Task {
                        await store.renameThread(thread.id, title: title)
                        dismiss()
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding()
        .frame(width: 360)
    }
}

private struct AddTagSheet: View {
    var thread: ChatThread
    @ObservedObject var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var tagName = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Add Tag")
                .font(.headline)
            Text(thread.title)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            TextField("Tag", text: $tagName)
                .textFieldStyle(.roundedBorder)
            HStack {
                Spacer()
                Button("Cancel") {
                    dismiss()
                }
                Button("Add") {
                    Task {
                        await store.addTag(tagName, to: thread.id)
                        dismiss()
                    }
                }
                .disabled(tagName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding()
        .frame(width: 320)
    }
}

private func parsedCommaSeparatedValues(_ text: String) -> [String] {
    text.split(separator: ",").map(String.init)
}
