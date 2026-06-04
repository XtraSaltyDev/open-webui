import SwiftUI
import UniformTypeIdentifiers

struct FileLibrarySidebarView: View {
    @ObservedObject var store: AppStore

    var body: some View {
        Button {
            store.selectFiles()
        } label: {
            Label("Files", systemImage: "doc.text")
        }
        .buttonStyle(.plain)
    }
}

struct FileLibraryView: View {
    @ObservedObject var store: AppStore
    @State private var isImportingFiles = false
    @State private var isConfirmingDeleteAllFiles = false

    var body: some View {
        let filteredFiles = store.filteredFiles()

        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.horizontal, 20)
                .padding(.vertical, 14)

            Divider()

            if store.files.isEmpty {
                ContentUnavailableView(
                    "No Files",
                    systemImage: "doc.text",
                    description: Text("Attach a text or PDF file from the composer to save it here.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if filteredFiles.isEmpty {
                ContentUnavailableView(
                    "No Matching Files",
                    systemImage: "magnifyingglass",
                    description: Text("Try a different file name, type, or text search.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(filteredFiles) { file in
                        FileLibraryRow(
                            file: file,
                            canAttach: !file.textContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                            onAttach: {
                                store.attachFileToChatContext(file.id)
                            },
                            onCopyText: {
                                store.copyFileText(file.id)
                            },
                            canExportOriginal: file.originalData != nil,
                            onExportOriginal: {
                                store.exportOriginalFileWithSavePanel(file.id)
                            },
                            onExportText: {
                                store.exportFileTextWithSavePanel(file.id)
                            },
                            onShare: {
                                store.shareFile(file.id)
                            },
                            onEditContent: { textContent in
                                await store.updateFileContent(file.id, textContent: textContent)
                            },
                            onRename: { newName in
                                await store.renameFile(file.id, fileName: newName)
                            },
                            onDelete: {
                                Task {
                                    await store.deleteFile(file.id)
                                }
                            }
                        )
                    }
                }
            }
        }
        .searchable(text: $store.fileSearchText, prompt: "Search files")
        .fileImporter(
            isPresented: $isImportingFiles,
            allowedContentTypes: [.item],
            allowsMultipleSelection: true
        ) { result in
            Task {
                do {
                    for url in try result.get() {
                        try await store.importFileToLibrary(from: url)
                    }
                } catch {
                    store.errorMessage = error.localizedDescription
                }
            }
        }
        .confirmationDialog(
            "Delete all saved files?",
            isPresented: $isConfirmingDeleteAllFiles,
            titleVisibility: .visible
        ) {
            Button("Delete All Files", role: .destructive) {
                Task {
                    await store.deleteAllFiles()
                }
            }

            Button("Cancel", role: .cancel) {}
        } message: {
            Text("All saved files will be permanently deleted.")
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Label("Files", systemImage: "doc.text")
                .font(.title2.weight(.semibold))

            Spacer()

            Text("\(store.files.count) saved")
                .font(.caption)
                .foregroundStyle(.secondary)

            Button {
                isImportingFiles = true
            } label: {
                Label("Import", systemImage: "square.and.arrow.down")
            }
            .labelStyle(.iconOnly)
            .help("Import files")

            Button {
                store.importFilesJSONWithOpenPanel()
            } label: {
                Label("Import JSON", systemImage: "doc.badge.plus")
            }
            .labelStyle(.iconOnly)
            .help("Import file library JSON")

            Button {
                isConfirmingDeleteAllFiles = true
            } label: {
                Label("Delete All", systemImage: "trash")
            }
            .labelStyle(.iconOnly)
            .help("Delete all saved files")
            .disabled(store.files.isEmpty)

            Menu {
                Button("Native JSON") {
                    store.exportFilesJSONWithSavePanel()
                }

                Button("Open WebUI JSON") {
                    store.exportFilesOpenWebUIJSONWithSavePanel()
                }
            } label: {
                Label("Export", systemImage: "square.and.arrow.up")
            }
            .labelStyle(.iconOnly)
            .help("Export files")
            .disabled(store.files.isEmpty)
        }
    }
}

private struct FileLibraryRow: View {
    var file: AppFile
    var canAttach: Bool
    var onAttach: () -> Void
    var onCopyText: () -> Void
    var canExportOriginal: Bool
    var onExportOriginal: () -> Void
    var onExportText: () -> Void
    var onShare: () -> Void
    var onEditContent: (String) async -> Void
    var onRename: (String) async -> Void
    var onDelete: () -> Void
    @State private var isShowingEditSheet = false
    @State private var isShowingRenameSheet = false

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "doc.text")
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 4) {
                Text(file.fileName)
                    .font(.headline)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Text("\(file.contentType) · \(file.byteCount) bytes")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text(file.textContent)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer()

            Button {
                onAttach()
            } label: {
                Label("Attach", systemImage: "paperclip")
            }
            .labelStyle(.iconOnly)
            .help("Attach to current draft")
            .disabled(!canAttach)

            Button {
                onCopyText()
            } label: {
                Label("Copy Text", systemImage: "doc.on.doc")
            }
            .labelStyle(.iconOnly)
            .help("Copy extracted text")
            .disabled(!canAttach)

            Button {
                onExportOriginal()
            } label: {
                Label("Export File", systemImage: "doc")
            }
            .labelStyle(.iconOnly)
            .help("Export original file")
            .disabled(!canExportOriginal)

            Button {
                onExportText()
            } label: {
                Label("Export Text", systemImage: "square.and.arrow.down")
            }
            .labelStyle(.iconOnly)
            .help("Export extracted text")
            .disabled(!canAttach)

            Button {
                onShare()
            } label: {
                Label("Share", systemImage: "square.and.arrow.up")
            }
            .labelStyle(.iconOnly)
            .help("Share saved file")

            Button {
                isShowingEditSheet = true
            } label: {
                Label("Edit Text", systemImage: "square.and.pencil")
            }
            .labelStyle(.iconOnly)
            .help("Edit extracted text")

            Button {
                isShowingRenameSheet = true
            } label: {
                Label("Rename", systemImage: "pencil")
            }
            .labelStyle(.iconOnly)
            .help("Rename saved file")

            Button(role: .destructive) {
                onDelete()
            } label: {
                Label("Delete", systemImage: "trash")
            }
            .labelStyle(.iconOnly)
            .help("Delete saved file")
        }
        .padding(.vertical, 4)
        .sheet(isPresented: $isShowingEditSheet) {
            EditFileTextSheet(
                fileName: file.fileName,
                textContent: file.textContent,
                onCancel: {
                    isShowingEditSheet = false
                },
                onSave: { textContent in
                    Task {
                        await onEditContent(textContent)
                        isShowingEditSheet = false
                    }
                }
            )
        }
        .sheet(isPresented: $isShowingRenameSheet) {
            RenameFileSheet(
                fileName: file.fileName,
                onCancel: {
                    isShowingRenameSheet = false
                },
                onRename: { newName in
                    Task {
                        await onRename(newName)
                        isShowingRenameSheet = false
                    }
                }
            )
        }
    }
}

private struct EditFileTextSheet: View {
    var fileName: String
    @State private var textContent: String
    var onCancel: () -> Void
    var onSave: (String) -> Void

    init(fileName: String, textContent: String, onCancel: @escaping () -> Void, onSave: @escaping (String) -> Void) {
        self.fileName = fileName
        _textContent = State(initialValue: textContent)
        self.onCancel = onCancel
        self.onSave = onSave
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Edit File Text")
                .font(.headline)

            Text(fileName)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)

            TextEditor(text: $textContent)
                .font(.system(.body, design: .monospaced))
                .frame(minHeight: 220)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(.quaternary)
                )

            HStack {
                Spacer()
                Button("Cancel") {
                    onCancel()
                }
                Button("Save") {
                    onSave(textContent)
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding()
        .frame(width: 520)
    }
}

private struct RenameFileSheet: View {
    @State private var fileName: String
    var onCancel: () -> Void
    var onRename: (String) -> Void

    init(fileName: String, onCancel: @escaping () -> Void, onRename: @escaping (String) -> Void) {
        _fileName = State(initialValue: fileName)
        self.onCancel = onCancel
        self.onRename = onRename
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Rename File")
                .font(.headline)

            TextField("File name", text: $fileName)
                .textFieldStyle(.roundedBorder)

            HStack {
                Spacer()
                Button("Cancel") {
                    onCancel()
                }
                Button("Rename") {
                    onRename(fileName)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(fileName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding()
        .frame(width: 320)
    }
}
