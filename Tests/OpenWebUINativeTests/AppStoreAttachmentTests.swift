import Foundation
import AppKit
import XCTest
@testable import OpenWebUINative

@MainActor
final class AppStoreAttachmentTests: XCTestCase {
    func testImportTextAttachmentAddsPendingAttachmentMetadata() async throws {
        let fixture = try AttachmentStoreFixture()
        let fileURL = fixture.rootURL.appendingPathComponent("notes.txt")
        try "Local context for the model".write(to: fileURL, atomically: true, encoding: .utf8)

        let store = fixture.makeStore()
        await store.load()

        try await store.importAttachment(from: fileURL)

        XCTAssertEqual(store.pendingAttachments.count, 1)
        XCTAssertEqual(store.pendingAttachments.first?.fileName, "notes.txt")
        XCTAssertEqual(store.pendingAttachments.first?.textContent, "Local context for the model")
    }

    func testImportAttachmentPersistsReusableFileAndCanAttachAfterReload() async throws {
        let fixture = try AttachmentStoreFixture()
        let fileURL = fixture.rootURL.appendingPathComponent("launch-plan.md")
        try "# Launch\nUse this reusable source.".write(to: fileURL, atomically: true, encoding: .utf8)
        let store = fixture.makeStore()
        await store.load()

        try await store.importAttachment(from: fileURL)

        let savedFile = try XCTUnwrap(store.files.first)
        XCTAssertEqual(savedFile.fileName, "launch-plan.md")
        XCTAssertEqual(savedFile.textContent, "# Launch\nUse this reusable source.")
        XCTAssertEqual(store.pendingAttachments.first?.fileName, "launch-plan.md")
        let persisted = try await fixture.fileStorage.loadFiles()
        XCTAssertEqual(persisted.map(\.id), [savedFile.id])
        XCTAssertEqual(persisted.first?.fileName, savedFile.fileName)
        XCTAssertEqual(persisted.first?.textContent, savedFile.textContent)

        let reloadedStore = fixture.makeStore()
        await reloadedStore.load()
        XCTAssertEqual(reloadedStore.files.map(\.id), [savedFile.id])
        XCTAssertEqual(reloadedStore.files.first?.fileName, savedFile.fileName)
        XCTAssertEqual(reloadedStore.files.first?.textContent, savedFile.textContent)

        reloadedStore.attachFileToChatContext(savedFile.id)

        XCTAssertEqual(reloadedStore.pendingAttachments.count, 1)
        XCTAssertEqual(reloadedStore.pendingAttachments.first?.fileName, "launch-plan.md")
        XCTAssertEqual(reloadedStore.pendingAttachments.first?.contentType, savedFile.contentType)
        XCTAssertEqual(reloadedStore.pendingAttachments.first?.byteCount, savedFile.byteCount)
        XCTAssertEqual(reloadedStore.pendingAttachments.first?.textContent, "# Launch\nUse this reusable source.")
    }

    func testImportFileToLibraryPersistsWithoutAddingPendingAttachment() async throws {
        let fixture = try AttachmentStoreFixture()
        let fileURL = fixture.rootURL.appendingPathComponent("source-notes.md")
        try "Save this for later.".write(to: fileURL, atomically: true, encoding: .utf8)
        let store = fixture.makeStore()
        await store.load()

        try await store.importFileToLibrary(from: fileURL)

        let savedFile = try XCTUnwrap(store.files.first)
        XCTAssertEqual(savedFile.fileName, "source-notes.md")
        XCTAssertEqual(savedFile.textContent, "Save this for later.")
        XCTAssertTrue(store.pendingAttachments.isEmpty)
        let persistedFiles = try await fixture.fileStorage.loadFiles()
        XCTAssertEqual(persistedFiles.map(\.id), [savedFile.id])
    }

    func testImportFileToLibraryPreservesOriginalBytesForExport() async throws {
        let fixture = try AttachmentStoreFixture()
        let fileURL = fixture.rootURL.appendingPathComponent("source-notes.md")
        let originalData = Data("# Source\nSave this for later.".utf8)
        try originalData.write(to: fileURL)
        let store = fixture.makeStore()
        await store.load()

        try await store.importFileToLibrary(from: fileURL)

        let savedFile = try XCTUnwrap(store.files.first)
        XCTAssertEqual(savedFile.originalData, originalData)
        let persistedFiles = try await fixture.fileStorage.loadFiles()
        XCTAssertEqual(persistedFiles.first?.originalData, originalData)
        let exportedData = try store.exportOriginalFileData(savedFile.id)
        XCTAssertEqual(exportedData, originalData)
    }

    func testImportBinaryFileToLibraryPreservesOriginalBytesWithoutExtractedText() async throws {
        let fixture = try AttachmentStoreFixture()
        let fileURL = fixture.rootURL.appendingPathComponent("pixel.png")
        let originalData = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        try originalData.write(to: fileURL)
        let store = fixture.makeStore()
        await store.load()

        try await store.importFileToLibrary(from: fileURL)

        let savedFile = try XCTUnwrap(store.files.first)
        XCTAssertEqual(savedFile.fileName, "pixel.png")
        XCTAssertEqual(savedFile.contentType, "image/png")
        XCTAssertEqual(savedFile.textContent, "")
        XCTAssertEqual(savedFile.originalData, originalData)
        XCTAssertTrue(store.pendingAttachments.isEmpty)
        XCTAssertEqual(try store.exportOriginalFileData(savedFile.id), originalData)
    }

    func testImportFileToLibraryIsBlockedWhenFilesFeatureIsDisabled() async throws {
        let fixture = try AttachmentStoreFixture()
        let fileURL = fixture.rootURL.appendingPathComponent("source-notes.md")
        try "Save this for later.".write(to: fileURL, atomically: true, encoding: .utf8)
        let store = fixture.makeStore()
        await store.load()
        await store.setFeatureToggle(.files, isEnabled: false)

        try await store.importFileToLibrary(from: fileURL)

        XCTAssertTrue(store.files.isEmpty)
        XCTAssertEqual(store.errorMessage, "Files is disabled.")
        let persistedFiles = try await fixture.fileStorage.loadFiles()
        XCTAssertTrue(persistedFiles.isEmpty)
    }

    func testAttachFileToChatContextRejectsSavedFilesWithoutExtractedText() async throws {
        let fixture = try AttachmentStoreFixture()
        let store = fixture.makeStore()
        await store.load()
        let file = AppFile(
            fileName: "pixel.png",
            contentType: "image/png",
            byteCount: 8,
            textContent: "",
            originalData: Data([0x89, 0x50, 0x4E, 0x47])
        )
        store.files = [file]

        store.attachFileToChatContext(file.id)

        XCTAssertTrue(store.pendingAttachments.isEmpty)
        XCTAssertEqual(store.errorMessage, "This saved file has no extracted text to attach to chat.")
    }

    func testFilteredFilesSearchesNameContentTypeAndExtractedText() async throws {
        let fixture = try AttachmentStoreFixture()
        let store = fixture.makeStore()
        await store.load()
        store.files = [
            AppFile(fileName: "launch-plan.md", contentType: "text/markdown", byteCount: 22, textContent: "Roadmap for the native app."),
            AppFile(fileName: "budget.csv", contentType: "text/csv", byteCount: 17, textContent: "Costs and vendors.")
        ]

        store.fileSearchText = "launch"
        XCTAssertEqual(store.filteredFiles().map(\.fileName), ["launch-plan.md"])

        store.fileSearchText = "CSV"
        XCTAssertEqual(store.filteredFiles().map(\.fileName), ["budget.csv"])

        store.fileSearchText = "roadmap"
        XCTAssertEqual(store.filteredFiles().map(\.fileName), ["launch-plan.md"])

        store.fileSearchText = "   "
        XCTAssertEqual(store.filteredFiles().map(\.fileName), ["launch-plan.md", "budget.csv"])
    }

    func testFilteredFilesSupportsOpenWebUIWildcardFilenamePatterns() async throws {
        let fixture = try AttachmentStoreFixture()
        let store = fixture.makeStore()
        await store.load()
        store.files = [
            AppFile(fileName: "brief.md", contentType: "text/markdown", byteCount: 10, textContent: "Launch notes"),
            AppFile(fileName: "file1.txt", contentType: "text/plain", byteCount: 5, textContent: "Alpha"),
            AppFile(fileName: "file12.txt", contentType: "text/plain", byteCount: 4, textContent: "Beta"),
            AppFile(fileName: "image.png", contentType: "image/png", byteCount: 3, textContent: "")
        ]

        store.fileSearchText = "*.md"
        XCTAssertEqual(store.filteredFiles().map(\.fileName), ["brief.md"])

        store.fileSearchText = "file?.txt"
        XCTAssertEqual(store.filteredFiles().map(\.fileName), ["file1.txt"])

        store.fileSearchText = "*.PDF"
        XCTAssertTrue(store.filteredFiles().isEmpty)
    }

    func testSelectFilesShowsFileLibraryAndClearsOtherSelections() async throws {
        let fixture = try AttachmentStoreFixture()
        let store = fixture.makeStore()
        await store.load()
        store.createThread()
        store.selectAudio()
        XCTAssertTrue(store.isShowingAudio)

        store.selectFiles()

        XCTAssertTrue(store.isShowingFiles)
        XCTAssertFalse(store.isShowingAudio)
        XCTAssertNil(store.selectedThreadID)

        store.createThread()

        XCTAssertFalse(store.isShowingFiles)
        XCTAssertNotNil(store.selectedThreadID)

        store.selectFiles()
        store.selectCalendarDashboard()

        XCTAssertFalse(store.isShowingFiles)
        XCTAssertTrue(store.isShowingCalendar)
    }

    func testDeleteFileRemovesPersistedFileAndPendingAttachments() async throws {
        let fixture = try AttachmentStoreFixture()
        let fileURL = fixture.rootURL.appendingPathComponent("brief.md")
        try "Reusable brief".write(to: fileURL, atomically: true, encoding: .utf8)
        let store = fixture.makeStore()
        await store.load()
        try await store.importAttachment(from: fileURL)
        let savedFile = try XCTUnwrap(store.files.first)
        store.attachFileToChatContext(savedFile.id)
        XCTAssertEqual(store.pendingAttachments.count, 2)

        await store.deleteFile(savedFile.id)

        XCTAssertTrue(store.files.isEmpty)
        XCTAssertTrue(store.pendingAttachments.isEmpty)
        let persistedFiles = try await fixture.fileStorage.loadFiles()
        XCTAssertTrue(persistedFiles.isEmpty)
    }

    func testDeleteAllFilesRemovesPersistedFilesAndPendingAttachments() async throws {
        let fixture = try AttachmentStoreFixture()
        let store = fixture.makeStore()
        await store.load()
        let firstFile = AppFile(
            fileName: "first.md",
            contentType: "text/markdown",
            byteCount: 10,
            textContent: "First file"
        )
        let secondFile = AppFile(
            fileName: "second.md",
            contentType: "text/markdown",
            byteCount: 11,
            textContent: "Second file"
        )
        try await fixture.fileStorage.save(firstFile)
        try await fixture.fileStorage.save(secondFile)
        store.files = [firstFile, secondFile]
        store.attachFileToChatContext(firstFile.id)
        store.attachFileToChatContext(secondFile.id)

        await store.deleteAllFiles()

        XCTAssertTrue(store.files.isEmpty)
        XCTAssertTrue(store.pendingAttachments.isEmpty)
        let persistedFiles = try await fixture.fileStorage.loadFiles()
        XCTAssertTrue(persistedFiles.isEmpty)
    }

    func testSavedFileMutationsAreBlockedWhenFilesFeatureIsDisabled() async throws {
        let fixture = try AttachmentStoreFixture()
        let store = fixture.makeStore()
        await store.load()
        let originalFile = AppFile(
            fileName: "source.md",
            contentType: "text/markdown",
            byteCount: 11,
            textContent: "Old context",
            updatedAt: Date(timeIntervalSince1970: 10)
        )
        try await fixture.fileStorage.save(originalFile)
        store.files = [originalFile]
        await store.setFeatureToggle(.files, isEnabled: false)

        await store.renameFile(originalFile.id, fileName: "renamed.md")
        await store.updateFileContent(originalFile.id, textContent: "Updated context")
        await store.deleteFile(originalFile.id)
        await store.deleteAllFiles()

        XCTAssertEqual(store.files.map(\.fileName), ["source.md"])
        XCTAssertEqual(store.files.first?.textContent, "Old context")
        XCTAssertEqual(store.errorMessage, "Files is disabled.")
        let persistedFiles = try await fixture.fileStorage.loadFiles()
        XCTAssertEqual(persistedFiles.map(\.fileName), ["source.md"])
        XCTAssertEqual(persistedFiles.first?.textContent, "Old context")
    }

    func testRenameFileTrimsPersistsAndUpdatesPendingAttachments() async throws {
        let fixture = try AttachmentStoreFixture()
        let store = fixture.makeStore()
        await store.load()
        let originalFile = AppFile(
            fileName: "draft-notes.txt",
            contentType: "text/plain",
            byteCount: 11,
            textContent: "Draft notes",
            updatedAt: Date(timeIntervalSince1970: 10)
        )
        try await fixture.fileStorage.save(originalFile)
        store.files = [originalFile]
        store.attachFileToChatContext(originalFile.id)

        await store.renameFile(originalFile.id, fileName: "  final-notes.md  ")

        XCTAssertEqual(store.files.first?.fileName, "final-notes.md")
        XCTAssertEqual(store.pendingAttachments.first?.fileName, "final-notes.md")
        XCTAssertEqual(store.files.first?.id, originalFile.id)
        XCTAssertGreaterThan(store.files.first?.updatedAt ?? .distantPast, originalFile.updatedAt)
        let persistedFiles = try await fixture.fileStorage.loadFiles()
        XCTAssertEqual(persistedFiles.first?.fileName, "final-notes.md")
        XCTAssertEqual(persistedFiles.first?.id, originalFile.id)
    }

    func testUpdateFileContentPersistsByteCountAndPendingAttachments() async throws {
        let fixture = try AttachmentStoreFixture()
        let store = fixture.makeStore()
        await store.load()
        let originalFile = AppFile(
            fileName: "source.md",
            contentType: "text/markdown",
            byteCount: 11,
            textContent: "Old context",
            updatedAt: Date(timeIntervalSince1970: 10)
        )
        try await fixture.fileStorage.save(originalFile)
        store.files = [originalFile]
        store.attachFileToChatContext(originalFile.id)
        let updatedText = "Updated context\nwith details"

        await store.updateFileContent(originalFile.id, textContent: updatedText)

        XCTAssertEqual(store.files.first?.textContent, updatedText)
        XCTAssertEqual(store.pendingAttachments.first?.textContent, updatedText)
        XCTAssertEqual(store.files.first?.byteCount, Data(updatedText.utf8).count)
        XCTAssertEqual(store.pendingAttachments.first?.byteCount, Data(updatedText.utf8).count)
        XCTAssertGreaterThan(store.files.first?.updatedAt ?? .distantPast, originalFile.updatedAt)
        let persistedFiles = try await fixture.fileStorage.loadFiles()
        XCTAssertEqual(persistedFiles.first?.textContent, updatedText)
        XCTAssertEqual(persistedFiles.first?.byteCount, Data(updatedText.utf8).count)
    }

    func testShareFileSharesSavedTextWithFileNameTitle() async throws {
        let shareService = FakeAttachmentShareService()
        let fixture = try AttachmentStoreFixture(shareService: shareService)
        let store = fixture.makeStore()
        await store.load()
        let file = AppFile(
            fileName: "research.md",
            contentType: "text/markdown",
            byteCount: 18,
            textContent: "# Research\nUse me."
        )
        store.files = [file]

        store.shareFile(file.id)

        XCTAssertEqual(shareService.sharedTitle, "research.md")
        XCTAssertEqual(shareService.sharedText, "# Research\nUse me.")
    }

    func testShareBinaryOnlyFileSharesOriginalFileURL() async throws {
        let shareService = FakeAttachmentShareService()
        let fixture = try AttachmentStoreFixture(shareService: shareService)
        let store = fixture.makeStore()
        await store.load()
        let originalData = Data([0x89, 0x50, 0x4E, 0x47])
        let file = AppFile(
            fileName: "pixel.png",
            contentType: "image/png",
            byteCount: originalData.count,
            textContent: "",
            originalData: originalData
        )
        store.files = [file]

        store.shareFile(file.id)

        XCTAssertEqual(shareService.sharedTitle, "pixel.png")
        let sharedFileURL = try XCTUnwrap(shareService.sharedFileURL)
        XCTAssertEqual(try Data(contentsOf: sharedFileURL), originalData)
        XCTAssertNil(shareService.sharedText)
    }

    func testCopyFileTextCopiesSavedTextToPasteboard() async throws {
        let fixture = try AttachmentStoreFixture()
        let store = fixture.makeStore()
        await store.load()
        let file = AppFile(
            fileName: "source.md",
            contentType: "text/markdown",
            byteCount: 18,
            textContent: "# Source\nUse me."
        )
        store.files = [file]
        let pasteboard = NSPasteboard.general
        let previousString = pasteboard.string(forType: .string)
        defer {
            pasteboard.clearContents()
            if let previousString {
                pasteboard.setString(previousString, forType: .string)
            }
        }

        store.copyFileText(file.id)

        XCTAssertEqual(pasteboard.string(forType: .string), "# Source\nUse me.")
    }

    func testExportFileTextDataReturnsSavedTextBytes() async throws {
        let fixture = try AttachmentStoreFixture()
        let store = fixture.makeStore()
        await store.load()
        let file = AppFile(
            fileName: "source.md",
            contentType: "text/markdown",
            byteCount: 18,
            textContent: "# Source\nUse me."
        )
        store.files = [file]

        let data = try store.exportFileTextData(file.id)

        XCTAssertEqual(String(data: data, encoding: .utf8), "# Source\nUse me.")
    }

    func testImportFilesJSONDataPersistsOpenWebUIFileRecords() async throws {
        let fixture = try AttachmentStoreFixture()
        let store = fixture.makeStore()
        await store.load()
        let json = """
        [
          {
            "id": "33333333-3333-3333-3333-333333333333",
            "user_id": "user-1",
            "filename": "source.md",
            "data": {
              "content": "Imported file context",
              "status": "completed"
            },
            "meta": {
              "name": "source.md",
              "content_type": "text/markdown",
              "size": 21
            },
            "created_at": 1700002000,
            "updated_at": 1700002300
          }
        ]
        """

        try await store.importFilesJSONData(Data(json.utf8))

        XCTAssertEqual(store.files.map(\.fileName), ["source.md"])
        XCTAssertEqual(store.files.first?.textContent, "Imported file context")
        let persistedFiles = try await fixture.fileStorage.loadFiles()
        XCTAssertEqual(persistedFiles.map(\.id.uuidString), ["33333333-3333-3333-3333-333333333333"])
        XCTAssertEqual(persistedFiles.first?.contentType, "text/markdown")
    }

    func testImportFilesJSONDataIsBlockedWhenFilesFeatureIsDisabled() async throws {
        let fixture = try AttachmentStoreFixture()
        let store = fixture.makeStore()
        await store.load()
        await store.setFeatureToggle(.files, isEnabled: false)
        let json = """
        [
          {
            "id": "33333333-3333-3333-3333-333333333333",
            "filename": "source.md",
            "data": { "content": "Imported file context" },
            "meta": { "content_type": "text/markdown", "size": 21 }
          }
        ]
        """

        try await store.importFilesJSONData(Data(json.utf8))
        await store.importFilesJSON(from: fixture.rootURL.appendingPathComponent("missing-files.json"))

        XCTAssertTrue(store.files.isEmpty)
        XCTAssertEqual(store.errorMessage, "Files is disabled.")
        let persistedFiles = try await fixture.fileStorage.loadFiles()
        XCTAssertTrue(persistedFiles.isEmpty)
    }

    func testSavedFileUsageActionsAreBlockedWhenFilesFeatureIsDisabled() async throws {
        let shareService = FakeAttachmentShareService()
        let fixture = try AttachmentStoreFixture(shareService: shareService)
        let store = fixture.makeStore()
        await store.load()
        let file = AppFile(
            fileName: "source.md",
            contentType: "text/markdown",
            byteCount: 18,
            textContent: "# Source\nUse me."
        )
        store.files = [file]
        let pasteboard = NSPasteboard.general
        let previousString = pasteboard.string(forType: .string)
        defer {
            pasteboard.clearContents()
            if let previousString {
                pasteboard.setString(previousString, forType: .string)
            }
        }
        pasteboard.clearContents()
        pasteboard.setString("unchanged", forType: .string)
        await store.setFeatureToggle(.files, isEnabled: false)

        store.attachFileToChatContext(file.id)
        store.shareFile(file.id)
        store.copyFileText(file.id)

        XCTAssertTrue(store.pendingAttachments.isEmpty)
        XCTAssertNil(shareService.sharedTitle)
        XCTAssertNil(shareService.sharedText)
        XCTAssertEqual(pasteboard.string(forType: .string), "unchanged")
        XCTAssertEqual(store.errorMessage, "Files is disabled.")
    }

    func testImportPDFAttachmentExtractsSelectableText() async throws {
        let fixture = try AttachmentStoreFixture()
        let fileURL = fixture.rootURL.appendingPathComponent("brief.pdf")
        try makePDFData(text: "PDF context for the model").write(to: fileURL)

        let store = fixture.makeStore()
        await store.load()

        try await store.importAttachment(from: fileURL)

        XCTAssertEqual(store.pendingAttachments.first?.fileName, "brief.pdf")
        XCTAssertEqual(store.pendingAttachments.first?.contentType, "application/pdf")
        XCTAssertTrue(store.pendingAttachments.first?.textContent?.contains("PDF context for the model") ?? false)
    }

    func testAttachNoteAddsPendingAttachmentMetadata() async throws {
        let fixture = try AttachmentStoreFixture()
        let store = fixture.makeStore()
        await store.load()
        let note = AppNote(title: "Research", content: "Use this note in the answer.")
        store.notes = [note]

        store.attachNoteToChatContext(note.id)

        XCTAssertEqual(store.pendingAttachments.count, 1)
        XCTAssertEqual(store.pendingAttachments.first?.fileName, "Research.md")
        XCTAssertEqual(store.pendingAttachments.first?.contentType, "text/markdown")
        XCTAssertEqual(store.pendingAttachments.first?.byteCount, Data(note.content.utf8).count)
        XCTAssertEqual(store.pendingAttachments.first?.textContent, "Use this note in the answer.")
    }

    func testSendPromptWithAttachedNoteSendsNoteContextToProvider() async throws {
        let provider = CapturingAttachmentProvider(chunks: ["ok"])
        let fixture = try AttachmentStoreFixture(provider: provider)
        let store = fixture.makeStore()
        await store.load()
        await store.selectModel("fake-model")
        let note = AppNote(title: "Launch plan", content: "Mention the native notes workflow.")
        store.notes = [note]

        store.attachNoteToChatContext(note.id)
        await store.send("Use the attached note")

        let userMessage = store.selectedThread?.messages.first { $0.role == .user }
        XCTAssertEqual(userMessage?.attachments.first?.fileName, "Launch plan.md")
        XCTAssertTrue(store.pendingAttachments.isEmpty)

        let providerContent = await provider.capturedMessages.first?.content
        XCTAssertTrue(providerContent?.contains("Use the attached note") ?? false)
        XCTAssertTrue(providerContent?.contains("Attachment: Launch plan.md") ?? false)
        XCTAssertTrue(providerContent?.contains("Mention the native notes workflow.") ?? false)
    }

    func testSendPromptPersistsAttachmentsAndSendsContextToProvider() async throws {
        let provider = CapturingAttachmentProvider(chunks: ["ok"])
        let fixture = try AttachmentStoreFixture(provider: provider)
        let fileURL = fixture.rootURL.appendingPathComponent("brief.md")
        try "# Brief\nUse this source.".write(to: fileURL, atomically: true, encoding: .utf8)

        let store = fixture.makeStore()
        await store.load()
        await store.selectModel("fake-model")
        try await store.importAttachment(from: fileURL)

        await store.send("Answer using the attached brief")

        let userMessage = store.selectedThread?.messages.first { $0.role == .user }
        XCTAssertEqual(userMessage?.attachments.first?.fileName, "brief.md")
        XCTAssertTrue(store.pendingAttachments.isEmpty)

        let saved = try await fixture.storage.loadThreads()
        XCTAssertEqual(saved.first?.messages.first { $0.role == .user }?.attachments.first?.fileName, "brief.md")

        let providerContent = await provider.capturedMessages.first?.content
        XCTAssertTrue(providerContent?.contains("Answer using the attached brief") ?? false)
        XCTAssertTrue(providerContent?.contains("Attachment: brief.md") ?? false)
        XCTAssertTrue(providerContent?.contains("# Brief") ?? false)
    }
}

private func makePDFData(text: String) throws -> Data {
    let data = NSMutableData()
    var mediaBox = CGRect(x: 0, y: 0, width: 612, height: 792)
    guard
        let consumer = CGDataConsumer(data: data as CFMutableData),
        let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil)
    else {
        throw NSError(domain: "PDFTestFixture", code: 1)
    }

    context.beginPDFPage(nil)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
    let attributedString = NSAttributedString(
        string: text,
        attributes: [.font: NSFont.systemFont(ofSize: 14)]
    )
    attributedString.draw(in: CGRect(x: 72, y: 700, width: 468, height: 48))
    NSGraphicsContext.restoreGraphicsState()
    context.endPDFPage()
    context.closePDF()

    return data as Data
}

private struct AttachmentStoreFixture {
    let rootURL: URL
    let storage: JSONStorageService
    let settingsStore: SettingsStore
    let fileStorage: JSONAppFileStorageService
    let provider: (any ChatProvider)?
    let shareService: FakeAttachmentShareService?

    init(provider: (any ChatProvider)? = nil, shareService: FakeAttachmentShareService? = nil) throws {
        rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        storage = JSONStorageService(rootURL: rootURL.appendingPathComponent("Chats", isDirectory: true))
        settingsStore = SettingsStore(settingsURL: rootURL.appendingPathComponent("settings.json"))
        fileStorage = JSONAppFileStorageService(rootURL: rootURL.appendingPathComponent("Files", isDirectory: true))
        self.provider = provider
        self.shareService = shareService
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
    }

    @MainActor
    func makeStore() -> AppStore {
        AppStore(
            storage: storage,
            fileStorage: fileStorage,
            settingsStore: settingsStore,
            secretStore: InMemorySecretStore(),
            providerOverride: provider,
            shareService: shareService ?? FakeAttachmentShareService()
        )
    }
}

private final class FakeAttachmentShareService: ChatSharing {
    private(set) var sharedText: String?
    private(set) var sharedTitle: String?
    private(set) var sharedFileURL: URL?

    func share(text: String, title: String) {
        sharedText = text
        sharedTitle = title
    }

    func share(fileURL: URL, title: String) {
        sharedFileURL = fileURL
        sharedTitle = title
    }
}

private actor CapturingAttachmentProvider: ChatProvider {
    nonisolated var configuration: ProviderConfiguration {
        ProviderConfiguration.defaultOllama()
    }

    private(set) var capturedMessages: [ProviderChatMessage] = []
    var chunks: [String]

    init(chunks: [String]) {
        self.chunks = chunks
    }

    func listModels() async throws -> [ProviderModel] {
        [ProviderModel(id: "fake-model", name: "fake-model", provider: .ollama, providerID: configuration.id)]
    }

    func healthCheck() async -> ProviderStatus {
        .available("Fake connected")
    }

    nonisolated func streamChat(model: String, messages: [ProviderChatMessage]) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task {
                await setCapturedMessages(messages)
                let chunks = await chunks
                for chunk in chunks {
                    continuation.yield(chunk)
                }
                continuation.finish()
            }
        }
    }

    func createEmbeddings(model: String, input: [String]) async throws -> [[Double]] {
        []
    }

    private func setCapturedMessages(_ messages: [ProviderChatMessage]) {
        capturedMessages = messages
    }
}
