import Foundation
import XCTest
@testable import OpenWebUINative

@MainActor
final class AppStoreFolderTests: XCTestCase {
    func testCreateFolderPersistsAndSortsFolders() async throws {
        let fixture = try FolderStoreFixture()
        let store = fixture.makeStore()
        await store.load()

        await store.createFolder(named: "Research")
        await store.createFolder(named: "Drafts")

        XCTAssertEqual(store.folders.map(\.name), ["Drafts", "Research"])
        let saved = try await fixture.folderStorage.loadFolders()
        XCTAssertEqual(saved.map(\.name), ["Drafts", "Research"])
    }

    func testAssignThreadToFolderPersistsThreadFolderID() async throws {
        let fixture = try FolderStoreFixture()
        let thread = ChatThread(id: UUID(), title: "Organize me")
        try await fixture.chatStorage.save(thread)

        let store = fixture.makeStore()
        await store.load()
        await store.createFolder(named: "Work")
        let folder = try XCTUnwrap(store.folders.first)

        await store.assignThread(thread.id, toFolder: folder.id)

        XCTAssertEqual(store.threads.first?.folderID, folder.id)
        let saved = try await fixture.chatStorage.loadThreads()
        XCTAssertEqual(saved.first?.folderID, folder.id)
    }

    func testDeleteFolderClearsAssignedThreadsWithoutDeletingChats() async throws {
        let fixture = try FolderStoreFixture()
        let folder = ChatFolder(name: "Work")
        let thread = ChatThread(id: UUID(), title: "Keep me", folderID: folder.id)
        try await fixture.folderStorage.save(folder)
        try await fixture.chatStorage.save(thread)

        let store = fixture.makeStore()
        await store.load()

        await store.deleteFolder(folder.id)

        XCTAssertTrue(store.folders.isEmpty)
        XCTAssertEqual(store.threads.count, 1)
        XCTAssertNil(store.threads.first?.folderID)
        let savedThreads = try await fixture.chatStorage.loadThreads()
        XCTAssertNil(savedThreads.first?.folderID)
    }

    func testCreateFolderIsBlockedWhenFoldersFeatureIsDisabled() async throws {
        let fixture = try FolderStoreFixture()
        let store = fixture.makeStore()
        await store.load()
        await store.setFeatureToggle(.folders, isEnabled: false)

        await store.createFolder(named: "Hidden")

        XCTAssertTrue(store.folders.isEmpty)
        XCTAssertEqual(store.errorMessage, "Folders is disabled.")
        let saved = try await fixture.folderStorage.loadFolders()
        XCTAssertTrue(saved.isEmpty)
    }

    func testAssignThreadToFolderIsBlockedWhenFoldersFeatureIsDisabled() async throws {
        let fixture = try FolderStoreFixture()
        let folder = ChatFolder(name: "Work")
        let thread = ChatThread(id: UUID(), title: "Organize me")
        try await fixture.folderStorage.save(folder)
        try await fixture.chatStorage.save(thread)
        let store = fixture.makeStore()
        await store.load()
        await store.setFeatureToggle(.folders, isEnabled: false)

        await store.assignThread(thread.id, toFolder: folder.id)

        XCTAssertNil(store.threads.first?.folderID)
        XCTAssertEqual(store.errorMessage, "Folders is disabled.")
        let saved = try await fixture.chatStorage.loadThreads()
        XCTAssertNil(saved.first?.folderID)
    }

    func testDeleteFolderIsBlockedWhenFoldersFeatureIsDisabled() async throws {
        let fixture = try FolderStoreFixture()
        let folder = ChatFolder(name: "Work")
        let thread = ChatThread(id: UUID(), title: "Keep me", folderID: folder.id)
        try await fixture.folderStorage.save(folder)
        try await fixture.chatStorage.save(thread)
        let store = fixture.makeStore()
        await store.load()
        await store.setFeatureToggle(.folders, isEnabled: false)

        await store.deleteFolder(folder.id)

        XCTAssertEqual(store.folders.map(\.id), [folder.id])
        XCTAssertEqual(store.threads.first?.folderID, folder.id)
        XCTAssertEqual(store.errorMessage, "Folders is disabled.")
        let savedFolders = try await fixture.folderStorage.loadFolders()
        XCTAssertEqual(savedFolders.map(\.id), [folder.id])
    }
}

private struct FolderStoreFixture {
    let rootURL: URL
    let chatStorage: JSONStorageService
    let folderStorage: JSONFolderStorageService
    let settingsStore: SettingsStore

    init() throws {
        rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        chatStorage = JSONStorageService(rootURL: rootURL.appendingPathComponent("Chats", isDirectory: true))
        folderStorage = JSONFolderStorageService(rootURL: rootURL.appendingPathComponent("Folders", isDirectory: true))
        settingsStore = SettingsStore(settingsURL: rootURL.appendingPathComponent("settings.json"))
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
    }

    @MainActor
    func makeStore() -> AppStore {
        AppStore(
            storage: chatStorage,
            folderStorage: folderStorage,
            settingsStore: settingsStore,
            secretStore: InMemorySecretStore(),
            providerOverride: FakeFolderProvider()
        )
    }
}

private struct FakeFolderProvider: ChatProvider {
    var configuration = ProviderConfiguration.defaultOllama()

    func listModels() async throws -> [ProviderModel] {
        [ProviderModel(id: "fake-model", name: "fake-model", provider: .ollama, providerID: configuration.id)]
    }

    func healthCheck() async -> ProviderStatus {
        .available("Fake connected")
    }

    func streamChat(model: String, messages: [ProviderChatMessage]) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish()
        }
    }

    func createEmbeddings(model: String, input: [String]) async throws -> [[Double]] {
        []
    }
}
