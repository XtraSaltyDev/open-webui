import Foundation
import XCTest
@testable import OpenWebUINative

final class JSONGeneratedImageStorageServiceTests: XCTestCase {
    func testSaveAndLoadImagesRoundTripsNewestFirst() async throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let storage = JSONGeneratedImageStorageService(rootURL: rootURL)
        let older = AppGeneratedImage(
            prompt: "Older image",
            modelID: "gpt-image-1",
            providerID: UUID(),
            imageData: Data("older".utf8),
            revisedPrompt: "Older revised",
            outputFormat: "png",
            size: "1024x1024",
            quality: "medium",
            createdAt: Date(timeIntervalSince1970: 100)
        )
        let newer = AppGeneratedImage(
            prompt: "Newer image",
            modelID: "gpt-image-1",
            imageData: Data("newer".utf8),
            outputFormat: "png",
            size: "1536x1024",
            quality: "high",
            createdAt: Date(timeIntervalSince1970: 200)
        )

        try await storage.save(older)
        try await storage.save(newer)

        let loaded = try await storage.loadImages()

        XCTAssertEqual(loaded, [newer, older])
    }

    func testDeleteImageRemovesPersistedRecord() async throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let storage = JSONGeneratedImageStorageService(rootURL: rootURL)
        let image = AppGeneratedImage(
            prompt: "Delete me",
            modelID: "gpt-image-1",
            imageData: Data("bytes".utf8)
        )

        try await storage.save(image)
        try await storage.deleteImage(id: image.id)

        let loaded = try await storage.loadImages()

        XCTAssertTrue(loaded.isEmpty)
    }
}
