import SwiftUI

struct NoteLibraryView: View {
    @ObservedObject var store: AppStore
    @State private var editorMode: NoteEditorMode?

    var body: some View {
        if !store.notes.isEmpty {
            TextField("Search notes", text: $store.noteSearchText)
                .textFieldStyle(.roundedBorder)
        }

        let filteredNotes = store.filteredNotes()
        if store.notes.isEmpty {
            Text("No notes")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else if filteredNotes.isEmpty {
            Text("No matching notes")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else {
            ForEach(filteredNotes) { note in
                NoteRow(
                    note: note,
                    canManageNotes: store.currentUserCanManageNotes,
                    isFocused: store.focusedNoteID == note.id,
                    onTogglePinned: {
                        Task {
                            await store.toggleNotePinned(note.id)
                        }
                    },
                    onAttach: {
                        store.attachNoteToChatContext(note.id)
                    },
                    onCopyLink: {
                        store.copyNoteLink(note.id)
                    },
                    onShare: {
                        store.shareNote(note.id)
                    },
                    onEdit: {
                        editorMode = .edit(note)
                    },
                    onDelete: {
                        Task {
                            await store.deleteNote(note.id)
                        }
                    }
                )
            }
        }

        SidebarActionStrip {
            SidebarActionButton(title: "New Note", systemImage: "note.text.badge.plus", isDisabled: !store.currentUserCanManageNotes) {
                editorMode = .create
            }

            SidebarActionButton(title: "Import Notes", systemImage: "square.and.arrow.down", isDisabled: !store.currentUserCanManageNotes) {
                store.importNotesJSONWithOpenPanel()
            }

            SidebarActionMenu(title: "Export Notes", systemImage: "square.and.arrow.up", isDisabled: store.notes.isEmpty) {
                Button("Native JSON") {
                    store.exportNotesJSONWithSavePanel()
                }

                Button("Open WebUI JSON") {
                    store.exportNotesOpenWebUIJSONWithSavePanel()
                }
            }
        }
        .sheet(item: $editorMode) { mode in
            NoteEditorSheet(
                mode: mode,
                onSave: { title, content in
                    Task {
                        switch mode {
                        case .create:
                            await store.createNote(title: title, content: content)
                        case .edit(let note):
                            await store.updateNote(note.id, title: title, content: content)
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

private struct NoteRow: View {
    var note: AppNote
    var canManageNotes: Bool
    var isFocused: Bool
    var onTogglePinned: () -> Void
    var onAttach: () -> Void
    var onCopyLink: () -> Void
    var onShare: () -> Void
    var onEdit: () -> Void
    var onDelete: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Button {
                onEdit()
            } label: {
                Label(note.title, systemImage: "note.text")
                    .lineLimit(1)
            }
            .buttonStyle(.plain)
            .disabled(!canManageNotes)
            .help("Edit note")

            Spacer()
            if note.isPinned {
                Image(systemName: "pin.fill")
                    .foregroundStyle(.secondary)
                    .help("Pinned")
            }

            Menu {
                if !canManageNotes {
                    Label("You do not have permission to manage notes.", systemImage: "lock")
                }
                Button(note.isPinned ? "Unpin Note" : "Pin Note") {
                    onTogglePinned()
                }
                .disabled(!canManageNotes)
                Divider()
                Button("Attach to Chat") {
                    onAttach()
                }
                Button("Copy Note Link") {
                    onCopyLink()
                }
                Button("Share...") {
                    onShare()
                }
                Divider()
                Button("Edit...") {
                    onEdit()
                }
                .disabled(!canManageNotes)
                Divider()
                Button("Delete Note", role: .destructive) {
                    onDelete()
                }
                .disabled(!canManageNotes)
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .help("Note actions")
        }
        .padding(.vertical, 2)
        .padding(.horizontal, 4)
        .background {
            if isFocused {
                RoundedRectangle(cornerRadius: 5)
                    .fill(Color.accentColor.opacity(0.12))
            }
        }
        .contextMenu {
            Button(note.isPinned ? "Unpin Note" : "Pin Note") {
                onTogglePinned()
            }
            .disabled(!canManageNotes)
            Divider()
            Button("Attach to Chat") {
                onAttach()
            }
            Button("Copy Note Link") {
                onCopyLink()
            }
            Button("Share...") {
                onShare()
            }
            Divider()
            Button("Edit...") {
                onEdit()
            }
            .disabled(!canManageNotes)
            Divider()
            Button("Delete Note", role: .destructive) {
                onDelete()
            }
            .disabled(!canManageNotes)
        }
    }
}

private struct NoteEditorSheet: View {
    var mode: NoteEditorMode
    var onSave: (String, String) -> Void
    var onCancel: () -> Void

    @State private var title: String
    @State private var content: String

    init(mode: NoteEditorMode, onSave: @escaping (String, String) -> Void, onCancel: @escaping () -> Void) {
        self.mode = mode
        self.onSave = onSave
        self.onCancel = onCancel
        switch mode {
        case .create:
            _title = State(initialValue: "")
            _content = State(initialValue: "")
        case .edit(let note):
            _title = State(initialValue: note.title)
            _content = State(initialValue: note.content)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(mode.title)
                .font(.title3)
                .fontWeight(.semibold)

            TextField("Title", text: $title)
                .textFieldStyle(.roundedBorder)

            TextEditor(text: $content)
                .font(.body)
                .frame(minHeight: 220)
                .overlay {
                    RoundedRectangle(cornerRadius: 5)
                        .stroke(.quaternary)
                }

            HStack {
                Spacer()
                Button("Cancel") {
                    onCancel()
                }
                Button("Save") {
                    onSave(title, content)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    || content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .frame(minWidth: 480, minHeight: 380)
    }
}

private enum NoteEditorMode: Identifiable {
    case create
    case edit(AppNote)

    var id: String {
        switch self {
        case .create:
            return "create"
        case .edit(let note):
            return note.id.uuidString
        }
    }

    var title: String {
        switch self {
        case .create:
            return "New Note"
        case .edit:
            return "Edit Note"
        }
    }
}
