import Foundation
import XCTest
@testable import OpenWebUINative

final class StorageServiceTests: XCTestCase {
    func testSaveAndLoadThreadsRoundTripsChatHistory() async throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let storage = JSONStorageService(rootURL: rootURL)
        let thread = ChatThread(
            id: UUID(),
            title: "Local Ollama chat",
            createdAt: Date(timeIntervalSince1970: 10),
            updatedAt: Date(timeIntervalSince1970: 20),
            modelIDs: ["llama3.2:latest"],
            messages: [
                ChatMessage(role: .user, content: "Hello", createdAt: Date(timeIntervalSince1970: 11)),
                ChatMessage(role: .assistant, content: "Hi there", modelID: "llama3.2:latest", createdAt: Date(timeIntervalSince1970: 12))
            ]
        )

        try await storage.save(thread)
        let loaded = try await storage.loadThreads()

        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded.first?.id, thread.id)
        XCTAssertEqual(loaded.first?.title, "Local Ollama chat")
        XCTAssertEqual(loaded.first?.messages.map(\.content), ["Hello", "Hi there"])
    }
}
