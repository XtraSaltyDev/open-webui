import Foundation
import XCTest
@testable import OpenWebUINative

@MainActor
final class AppStoreChatImportTests: XCTestCase {
    func testImportChatThreadJSONPersistsAndSelectsImportedThread() async throws {
        let fixture = try ChatImportFixture()
        let exportedThread = ChatThread(
            title: "Imported Chat",
            providerID: ProviderConfiguration.defaultOllamaID,
            modelIDs: ["llama3.2:latest"],
            messages: [
                ChatMessage(role: .user, content: "Remember this.")
            ]
        )
        let importURL = fixture.rootURL.appendingPathComponent("imported-chat.json")
        try ChatExportService().jsonData(for: exportedThread).write(to: importURL)

        let store = fixture.makeStore()
        await store.load()
        await store.importChatThreadJSON(from: importURL)

        XCTAssertEqual(store.threads.first?.title, "Imported Chat")
        XCTAssertEqual(store.selectedThreadID, store.threads.first?.id)

        let reloadedStore = fixture.makeStore()
        await reloadedStore.load()
        XCTAssertEqual(reloadedStore.threads.first?.title, "Imported Chat")
        XCTAssertEqual(reloadedStore.threads.first?.messages.first?.content, "Remember this.")
    }

    func testImportChatThreadsJSONPersistsArrayWithFreshIDsAndSelectsNewestImportedThread() async throws {
        let fixture = try ChatImportFixture()
        let existingID = UUID()
        let messageID = UUID()
        let existingThread = ChatThread(
            id: existingID,
            title: "Existing Chat",
            createdAt: Date(timeIntervalSince1970: 1),
            updatedAt: Date(timeIntervalSince1970: 2),
            messages: [
                ChatMessage(id: messageID, role: .user, content: "Already here.")
            ]
        )
        let archivedImport = ChatThread(
            id: existingID,
            title: "Archived Import",
            createdAt: Date(timeIntervalSince1970: 10),
            updatedAt: Date(timeIntervalSince1970: 20),
            isArchived: true,
            messages: [
                ChatMessage(id: messageID, role: .user, content: "Archived import.")
            ]
        )
        let newestImport = ChatThread(
            title: "Newest Import",
            createdAt: Date(timeIntervalSince1970: 30),
            updatedAt: Date(timeIntervalSince1970: 40),
            isPinned: true,
            messages: [
                ChatMessage(role: .assistant, content: "Newest import.")
            ]
        )
        try await fixture.storage.save(existingThread)
        let importURL = fixture.rootURL.appendingPathComponent("chat-export.json")
        try JSONEncoder.openWebUIEncoder.encode([archivedImport, newestImport]).write(to: importURL)

        let store = fixture.makeStore()
        await store.load()
        await store.importChatThreadsJSON(from: importURL)

        XCTAssertEqual(store.threads.count, 3)
        XCTAssertEqual(store.selectedThread?.title, "Newest Import")
        XCTAssertEqual(store.filteredThreads().map(\.title), ["Newest Import", "Existing Chat"])
        XCTAssertEqual(store.filteredArchivedThreads().map(\.title), ["Archived Import"])

        let importedArchived = try XCTUnwrap(store.threads.first { $0.title == "Archived Import" })
        XCTAssertNotEqual(importedArchived.id, existingID)
        XCTAssertNotEqual(importedArchived.messages.first?.id, messageID)

        let reloadedStore = fixture.makeStore()
        await reloadedStore.load()

        XCTAssertEqual(reloadedStore.threads.count, 3)
        XCTAssertEqual(reloadedStore.filteredThreads().map(\.title), ["Newest Import", "Existing Chat"])
        XCTAssertEqual(reloadedStore.filteredArchivedThreads().map(\.title), ["Archived Import"])
    }
}

private struct ChatImportFixture {
    let rootURL: URL
    let storage: JSONStorageService
    let folderStorage: JSONFolderStorageService
    let promptStorage: JSONPromptStorageService
    let noteStorage: JSONNoteStorageService
    let settingsStore: SettingsStore

    init() throws {
        rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        storage = JSONStorageService(rootURL: rootURL.appendingPathComponent("Chats", isDirectory: true))
        folderStorage = JSONFolderStorageService(rootURL: rootURL.appendingPathComponent("Folders", isDirectory: true))
        promptStorage = JSONPromptStorageService(rootURL: rootURL.appendingPathComponent("Prompts", isDirectory: true))
        noteStorage = JSONNoteStorageService(rootURL: rootURL.appendingPathComponent("Notes", isDirectory: true))
        settingsStore = SettingsStore(settingsURL: rootURL.appendingPathComponent("settings.json"))
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
    }

    @MainActor
    func makeStore() -> AppStore {
        AppStore(
            storage: storage,
            folderStorage: folderStorage,
            settingsStore: settingsStore,
            secretStore: InMemorySecretStore(),
            promptStorage: promptStorage,
            noteStorage: noteStorage
        )
    }
}
