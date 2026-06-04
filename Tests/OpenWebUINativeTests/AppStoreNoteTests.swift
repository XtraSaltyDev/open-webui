import XCTest
@testable import OpenWebUINative

@MainActor
final class AppStoreNoteTests: XCTestCase {
    func testCreateNotePersistsAndReloads() async throws {
        let fixture = try NoteFixture()
        let store = fixture.makeStore()
        await store.load()

        await store.createNote(title: "Research", content: "Summarize provider parity.")

        XCTAssertEqual(store.notes.map(\.title), ["Research"])
        XCTAssertEqual(store.notes.first?.content, "Summarize provider parity.")

        let reloadedStore = fixture.makeStore()
        await reloadedStore.load()

        XCTAssertEqual(reloadedStore.notes.map(\.title), ["Research"])
        XCTAssertEqual(reloadedStore.notes.first?.content, "Summarize provider parity.")
    }

    func testUpdateNoteTrimsInputAndSortsMostRecentlyUpdatedFirst() async throws {
        let fixture = try NoteFixture()
        let store = fixture.makeStore()
        await store.load()

        await store.createNote(title: "First", content: "First body")
        await store.createNote(title: "Second", content: "Second body")
        let firstNote = try XCTUnwrap(store.notes.first { $0.title == "First" })

        await store.updateNote(firstNote.id, title: "  Updated first  ", content: "  Better body  ")

        XCTAssertEqual(store.notes.map(\.title), ["Updated first", "Second"])
        XCTAssertEqual(store.notes.first?.content, "Better body")
    }

    func testDeleteNoteRemovesItFromStorage() async throws {
        let fixture = try NoteFixture()
        let store = fixture.makeStore()
        await store.load()
        await store.createNote(title: "Temporary", content: "Remove this.")
        let note = try XCTUnwrap(store.notes.first)

        await store.deleteNote(note.id)

        let reloadedStore = fixture.makeStore()
        await reloadedStore.load()
        XCTAssertTrue(reloadedStore.notes.isEmpty)
    }

    func testToggleNotePinnedPersistsAndSortsPinnedNotesFirst() async throws {
        let fixture = try NoteFixture()
        let store = fixture.makeStore()
        await store.load()
        await store.createNote(title: "First", content: "First body")
        await store.createNote(title: "Second", content: "Second body")
        let firstNote = try XCTUnwrap(store.notes.first { $0.title == "First" })

        await store.toggleNotePinned(firstNote.id)

        XCTAssertEqual(store.notes.map(\.title).first, "First")
        XCTAssertTrue(store.notes.first?.isPinned ?? false)

        let reloadedStore = fixture.makeStore()
        await reloadedStore.load()

        XCTAssertEqual(reloadedStore.notes.map(\.title).first, "First")
        XCTAssertTrue(reloadedStore.notes.first?.isPinned ?? false)

        await reloadedStore.toggleNotePinned(firstNote.id)

        XCTAssertFalse(reloadedStore.notes.first { $0.id == firstNote.id }?.isPinned ?? true)
    }

    func testNoteChangesCreateAuditEventsWithoutNoteContent() async throws {
        let fixture = try NoteFixture()
        let store = fixture.makeStore()
        await store.load()

        await store.createNote(title: "Private strategy", content: "Sensitive roadmap detail.")
        let note = try XCTUnwrap(store.notes.first)
        await store.updateNote(note.id, title: "Private strategy v2", content: "Sensitive roadmap detail.")
        await store.toggleNotePinned(note.id)
        await store.deleteNote(note.id)

        let noteAuditEvents = store.auditEvents.filter {
            ["noteCreated", "noteUpdated", "notePinUpdated", "noteDeleted"].contains($0.action.rawValue)
        }
        XCTAssertEqual(Set(noteAuditEvents.map(\.action.rawValue)), [
            "noteCreated",
            "noteUpdated",
            "notePinUpdated",
            "noteDeleted"
        ])

        let createdEvent = try XCTUnwrap(noteAuditEvents.first { $0.action.rawValue == "noteCreated" })
        XCTAssertEqual(createdEvent.summary, "Created note")
        XCTAssertEqual(createdEvent.metadata["noteID"], note.id.uuidString)
        XCTAssertEqual(createdEvent.metadata["isPinned"], "false")

        let updatedEvent = try XCTUnwrap(noteAuditEvents.first { $0.action.rawValue == "noteUpdated" })
        XCTAssertEqual(updatedEvent.summary, "Updated note")
        XCTAssertEqual(updatedEvent.metadata["noteID"], note.id.uuidString)

        let pinnedEvent = try XCTUnwrap(noteAuditEvents.first { $0.action.rawValue == "notePinUpdated" })
        XCTAssertEqual(pinnedEvent.summary, "Updated note pin state")
        XCTAssertEqual(pinnedEvent.metadata["isPinned"], "true")
        XCTAssertEqual(pinnedEvent.metadata["previousIsPinned"], "false")

        let deletedEvent = try XCTUnwrap(noteAuditEvents.first { $0.action.rawValue == "noteDeleted" })
        XCTAssertEqual(deletedEvent.summary, "Deleted note")
        XCTAssertEqual(deletedEvent.metadata["noteID"], note.id.uuidString)

        for auditEvent in noteAuditEvents {
            XCTAssertFalse(auditEvent.summary.contains("Private strategy"))
            XCTAssertFalse(auditEvent.metadata.values.contains("Private strategy"))
            XCTAssertFalse(auditEvent.metadata.values.contains("Private strategy v2"))
            XCTAssertFalse(auditEvent.metadata.values.contains("Sensitive roadmap detail."))
        }

        let reloadedEvents = try await fixture.auditStorage.loadEvents()
        XCTAssertTrue(reloadedEvents.contains { $0.action.rawValue == "noteCreated" && $0.metadata["noteID"] == note.id.uuidString })
        XCTAssertTrue(reloadedEvents.contains { $0.action.rawValue == "noteUpdated" && $0.metadata["noteID"] == note.id.uuidString })
        XCTAssertTrue(reloadedEvents.contains { $0.action.rawValue == "notePinUpdated" && $0.metadata["noteID"] == note.id.uuidString })
        XCTAssertTrue(reloadedEvents.contains { $0.action.rawValue == "noteDeleted" && $0.metadata["noteID"] == note.id.uuidString })
    }

    func testLoadNotesDefaultsMissingPinnedStateToFalse() async throws {
        let fixture = try NoteFixture()
        let noteID = UUID()
        let legacyNoteData = Data(
            """
            {
              "id": "\(noteID.uuidString)",
              "title": "Legacy note",
              "content": "Saved before pinning existed.",
              "createdAt": "2026-01-01T00:00:00Z",
              "updatedAt": "2026-01-02T00:00:00Z"
            }
            """.utf8
        )
        let notesURL = fixture.rootURL.appendingPathComponent("Notes", isDirectory: true)
        try FileManager.default.createDirectory(at: notesURL, withIntermediateDirectories: true)
        try legacyNoteData.write(to: notesURL.appendingPathComponent("\(noteID.uuidString).json"))

        let store = fixture.makeStore()
        await store.load()

        let note = try XCTUnwrap(store.notes.first)
        XCTAssertEqual(note.title, "Legacy note")
        XCTAssertFalse(note.isPinned)
    }

    func testExportAndImportNotesJSONRoundTripsNotes() async throws {
        let fixture = try NoteFixture()
        let store = fixture.makeStore()
        await store.load()
        await store.createNote(title: "Research", content: "Summarize provider parity.")
        await store.createNote(title: "Release", content: "Draft release notes.")

        let data = try store.exportNotesJSONData()

        let importFixture = try NoteFixture()
        let importStore = importFixture.makeStore()
        await importStore.load()
        try await importStore.importNotesJSONData(data)

        XCTAssertEqual(Set(importStore.notes.map(\.title)), ["Research", "Release"])
        XCTAssertEqual(importStore.notes.first { $0.title == "Research" }?.content, "Summarize provider parity.")
    }

    func testExportNotesOpenWebUIJSONDataBuildsRawNoteRecords() async throws {
        let fixture = try NoteFixture()
        let store = fixture.makeStore()
        await store.load()
        await store.createNote(title: "Research", content: "Summarize provider parity.")

        let data = try store.exportNotesOpenWebUIJSONData()
        let records = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [[String: Any]])
        let record = try XCTUnwrap(records.first)
        let dataBody = try XCTUnwrap(record["data"] as? [String: Any])
        let content = try XCTUnwrap(dataBody["content"] as? [String: Any])

        XCTAssertEqual(records.count, 1)
        XCTAssertNil(record["format"])
        XCTAssertEqual(record["title"] as? String, "Research")
        XCTAssertEqual((content["md"] as? String), "Summarize provider parity.")
        XCTAssertEqual(record["user_id"] as? String, "local-user")
        XCTAssertEqual(record["is_pinned"] as? Bool, false)
        XCTAssertEqual(record["access_grants"] as? [String], [])
        XCTAssertNotNil(record["created_at"] as? Int64)
        XCTAssertNotNil(record["updated_at"] as? Int64)
        XCTAssertNil(record["createdAt"])
        XCTAssertNil(record["updatedAt"])
    }

    func testImportNotesJSONAcceptsOpenWebUINoteRecords() async throws {
        let fixture = try NoteFixture()
        let store = fixture.makeStore()
        await store.load()
        let data = Data(
            """
            [
              {
                "id": "00000000-0000-0000-0000-000000000123",
                "user_id": "user-id",
                "title": "Migration note",
                "data": {
                  "content": {
                    "md": "Markdown from Open WebUI."
                  }
                },
                "meta": {},
                "created_at": 1000,
                "updated_at": 2000
              }
            ]
            """.utf8
        )

        try await store.importNotesJSONData(data)

        XCTAssertEqual(store.notes.first?.id.uuidString, "00000000-0000-0000-0000-000000000123")
        XCTAssertEqual(store.notes.first?.title, "Migration note")
        XCTAssertEqual(store.notes.first?.content, "Markdown from Open WebUI.")
        XCTAssertEqual(store.notes.first?.createdAt, Date(timeIntervalSince1970: 1000))
        XCTAssertEqual(store.notes.first?.updatedAt, Date(timeIntervalSince1970: 2000))
    }

    func testFilteredNotesSearchesTitleAndContent() async throws {
        let fixture = try NoteFixture()
        let store = fixture.makeStore()
        await store.load()
        await store.createNote(title: "Launch Plan", content: "Ship native notes search.")
        await store.createNote(title: "Recipe", content: "Make tomato pasta.")

        XCTAssertEqual(Set(store.filteredNotes().map(\.title)), ["Launch Plan", "Recipe"])

        store.noteSearchText = "launch"
        XCTAssertEqual(store.filteredNotes().map(\.title), ["Launch Plan"])

        store.noteSearchText = "tomato"
        XCTAssertEqual(store.filteredNotes().map(\.title), ["Recipe"])

        store.noteSearchText = "missing"
        XCTAssertTrue(store.filteredNotes().isEmpty)
    }

    func testNoteDeepLinkUsesStableAppURL() {
        let note = AppNote(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000123")!,
            title: "Research",
            content: "Draft link behavior."
        )

        XCTAssertEqual(note.deepLinkURL.absoluteString, "openwebui-native://notes/00000000-0000-0000-0000-000000000123")
        XCTAssertEqual(AppNote.noteID(fromDeepLink: note.deepLinkURL), note.id)
        XCTAssertNil(AppNote.noteID(fromDeepLink: URL(string: "https://example.com/notes/\(note.id.uuidString)")!))
    }

    func testShareNoteSharesMarkdownWithTitle() async throws {
        let shareService = FakeNoteShareService()
        let fixture = try NoteFixture(shareService: shareService)
        let store = fixture.makeStore()
        await store.load()
        await store.createNote(title: "Research", content: "Summarize provider parity.")
        let note = try XCTUnwrap(store.notes.first)

        store.shareNote(note.id)

        XCTAssertEqual(shareService.sharedTitle, "Research")
        XCTAssertEqual(shareService.sharedText, "# Research\n\nSummarize provider parity.")
    }

    func testNoteActionsBlockDisabledFeatureBeforeSharingAttachmentsOrPersistenceChanges() async throws {
        let shareService = FakeNoteShareService()
        let fixture = try NoteFixture(shareService: shareService)
        let store = fixture.makeStore()
        await store.load()
        await store.createNote(title: "Existing note", content: "Existing content.")
        let note = try XCTUnwrap(store.notes.first)
        let importData = try NoteExportService().jsonData(for: [
            AppNote(title: "Blocked import", content: "Imported body.")
        ])

        await store.setFeatureToggle(.notes, isEnabled: false)
        await store.createNote(title: "Blocked create", content: "Created body.")
        await store.updateNote(note.id, title: "Blocked update", content: "Blocked content.")
        await store.toggleNotePinned(note.id)
        store.attachNoteToChatContext(note.id)
        store.shareNote(note.id)
        store.errorMessage = nil
        await store.importNoteToKnowledge(note.id, toCollectionID: UUID())
        XCTAssertEqual(store.errorMessage, "Notes is disabled.")
        try await store.importNotesJSONData(importData)
        await store.deleteNote(note.id)

        let unchangedNote = try XCTUnwrap(store.notes.first)
        XCTAssertEqual(store.notes.count, 1)
        XCTAssertEqual(unchangedNote.title, "Existing note")
        XCTAssertEqual(unchangedNote.content, "Existing content.")
        XCTAssertFalse(unchangedNote.isPinned)
        XCTAssertTrue(store.pendingAttachments.isEmpty)
        XCTAssertNil(shareService.sharedTitle)
        XCTAssertNil(shareService.sharedText)
        XCTAssertEqual(store.errorMessage, "Notes is disabled.")

        let persistedNotes = try await fixture.noteStorage.loadNotes()
        XCTAssertEqual(persistedNotes.map(\.title), ["Existing note"])
        XCTAssertEqual(persistedNotes.first?.content, "Existing content.")
        XCTAssertFalse(persistedNotes.first?.isPinned ?? true)
    }

    func testResolveNoteLinkFocusesExistingNoteAndFiltersList() async throws {
        let fixture = try NoteFixture()
        let store = fixture.makeStore()
        await store.load()
        let noteID = UUID(uuidString: "00000000-0000-0000-0000-000000000456")!
        try await store.importNotesJSONData(
            NoteExportService().jsonData(for: [
                AppNote(id: noteID, title: "Link Target", content: "Open this note.")
            ])
        )

        let resolvedNote = store.resolveNoteLink(URL(string: "openwebui-native://notes/\(noteID.uuidString)")!)

        XCTAssertEqual(resolvedNote?.id, noteID)
        XCTAssertEqual(store.focusedNoteID, noteID)
        XCTAssertEqual(store.noteSearchText, "Link Target")
        XCTAssertEqual(store.filteredNotes().map(\.id), [noteID])
    }

    func testNoteWritePermissionAllowsCreateUpdatePinDeleteAndImportForCurrentUser() async throws {
        let fixture = try NoteFixture()
        let store = fixture.makeStore()
        await store.load()
        await store.createAdminUser(name: "Workspace User", email: "user@example.com", role: .user)
        let user = try XCTUnwrap(store.adminUsers.first)
        await store.createAdminGroup(name: "Note Editors", description: "Can manage notes.", permissions: ["notes.write"])
        let group = try XCTUnwrap(store.adminGroups.first)
        await store.setAdminGroupMembers(group.id, memberIDs: [user.id])
        store.currentUserID = user.id

        await store.createNote(title: "Research", content: "Draft note.")
        let note = try XCTUnwrap(store.notes.first)
        await store.updateNote(note.id, title: "Updated Research", content: "Updated note.")
        await store.toggleNotePinned(note.id)
        XCTAssertTrue(store.notes.first?.isPinned ?? false)
        await store.deleteNote(note.id)

        let data = try NoteExportService().jsonData(for: [
            AppNote(title: "Imported", content: "Imported body.")
        ])
        try await store.importNotesJSONData(data)

        XCTAssertEqual(store.notes.map(\.title), ["Imported"])
        XCTAssertNil(store.errorMessage)
    }

    func testNoteWritePermissionBlocksCreateUpdatePinDeleteAndImportForCurrentUser() async throws {
        let fixture = try NoteFixture()
        let store = fixture.makeStore()
        await store.load()
        await store.createAdminUser(name: "Workspace User", email: "user@example.com", role: .user)
        let user = try XCTUnwrap(store.adminUsers.first)
        store.currentUserID = user.id

        await store.createNote(title: "Blocked note", content: "Should not persist.")

        XCTAssertTrue(store.notes.isEmpty)
        XCTAssertEqual(store.errorMessage, "You do not have permission to manage notes.")

        store.errorMessage = nil
        store.currentUserID = "local-admin"
        await store.createAdminUser(name: "Local Admin", email: "admin@example.com", role: .admin)
        let admin = try XCTUnwrap(store.adminUsers.first { $0.role == .admin })
        store.currentUserID = admin.id
        await store.createNote(title: "Existing note", content: "Existing content.")
        let note = try XCTUnwrap(store.notes.first)

        store.currentUserID = user.id
        await store.updateNote(note.id, title: "Blocked update", content: "Blocked content.")
        await store.toggleNotePinned(note.id)
        await store.deleteNote(note.id)
        let data = try NoteExportService().jsonData(for: [
            AppNote(title: "Blocked import", content: "Imported body.")
        ])
        try await store.importNotesJSONData(data)

        XCTAssertEqual(store.notes.map(\.title), ["Existing note"])
        XCTAssertEqual(store.notes.first?.content, "Existing content.")
        XCTAssertFalse(store.notes.first?.isPinned ?? true)
        XCTAssertEqual(store.errorMessage, "You do not have permission to manage notes.")

        let reloadedStore = fixture.makeStore()
        await reloadedStore.load()
        XCTAssertEqual(reloadedStore.notes.map(\.title), ["Existing note"])
        XCTAssertEqual(reloadedStore.notes.first?.content, "Existing content.")
        XCTAssertFalse(reloadedStore.notes.first?.isPinned ?? true)
    }

    func testUnmanagedLocalUserCanManageNotesWhenAdminDirectoryExists() async throws {
        let fixture = try NoteFixture()
        let store = fixture.makeStore()
        await store.load()
        await store.createAdminUser(name: "Workspace User", email: "user@example.com", role: .user)

        await store.createNote(title: "Local note", content: "Local body.")

        XCTAssertEqual(store.notes.map(\.title), ["Local note"])
        XCTAssertNil(store.errorMessage)
    }
}

private struct NoteFixture {
    let rootURL: URL
    let storage: JSONStorageService
    let folderStorage: JSONFolderStorageService
    let promptStorage: JSONPromptStorageService
    let noteStorage: JSONNoteStorageService
    let auditStorage: JSONAuditLogStorageService
    let adminStorage: JSONAdminDirectoryStorageService
    let settingsStore: SettingsStore
    let shareService: FakeNoteShareService?

    init(shareService: FakeNoteShareService? = nil) throws {
        rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        storage = JSONStorageService(rootURL: rootURL.appendingPathComponent("Chats", isDirectory: true))
        folderStorage = JSONFolderStorageService(rootURL: rootURL.appendingPathComponent("Folders", isDirectory: true))
        promptStorage = JSONPromptStorageService(rootURL: rootURL.appendingPathComponent("Prompts", isDirectory: true))
        noteStorage = JSONNoteStorageService(rootURL: rootURL.appendingPathComponent("Notes", isDirectory: true))
        auditStorage = JSONAuditLogStorageService(
            rootURL: rootURL.appendingPathComponent("AuditLog", isDirectory: true)
        )
        adminStorage = JSONAdminDirectoryStorageService(
            snapshotURL: rootURL.appendingPathComponent("admin-directory.json")
        )
        settingsStore = SettingsStore(settingsURL: rootURL.appendingPathComponent("settings.json"))
        self.shareService = shareService
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
    }

    @MainActor
    func makeStore() -> AppStore {
        AppStore(
            storage: storage,
            folderStorage: folderStorage,
            settingsStore: settingsStore,
            secretStore: InMemorySecretStore(),
            shareService: shareService ?? FakeNoteShareService(),
            auditLogStorage: auditStorage,
            promptStorage: promptStorage,
            noteStorage: noteStorage,
            adminDirectoryStorage: adminStorage
        )
    }
}

@MainActor
private final class FakeNoteShareService: ChatSharing {
    private(set) var sharedText: String?
    private(set) var sharedTitle: String?

    func share(text: String, title: String) {
        sharedText = text
        sharedTitle = title
    }
}
