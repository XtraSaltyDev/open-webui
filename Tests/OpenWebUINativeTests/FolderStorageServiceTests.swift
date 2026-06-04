import Foundation
import XCTest
@testable import OpenWebUINative

final class FolderStorageServiceTests: XCTestCase {
    func testSaveAndLoadFoldersRoundTripsSortedByName() async throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let storage = JSONFolderStorageService(rootURL: rootURL)
        let research = ChatFolder(name: "Research")
        let drafts = ChatFolder(name: "Drafts")

        try await storage.save(research)
        try await storage.save(drafts)
        let loaded = try await storage.loadFolders()

        XCTAssertEqual(loaded.map(\.name), ["Drafts", "Research"])
    }

    func testDeleteFolderRemovesFolderFile() async throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let storage = JSONFolderStorageService(rootURL: rootURL)
        let folder = ChatFolder(name: "Temporary")

        try await storage.save(folder)
        try await storage.deleteFolder(id: folder.id)
        let loaded = try await storage.loadFolders()

        XCTAssertTrue(loaded.isEmpty)
    }
}
