import Foundation
import XCTest
@testable import OpenWebUINative

final class KnowledgeServiceTests: XCTestCase {
    func testChunkerSplitsTextWithSourceMetadata() {
        let collectionID = UUID()
        let documentID = UUID()
        let chunks = KnowledgeTextChunker(maxCharacters: 24).chunks(
            for: "Alpha beta gamma delta epsilon zeta eta theta.",
            collectionID: collectionID,
            documentID: documentID,
            sourceName: "notes.txt"
        )

        XCTAssertGreaterThan(chunks.count, 1)
        XCTAssertEqual(chunks.first?.collectionID, collectionID)
        XCTAssertEqual(chunks.first?.documentID, documentID)
        XCTAssertEqual(chunks.first?.sourceName, "notes.txt")
        XCTAssertEqual(chunks.map(\.index), Array(chunks.indices))
    }

    func testImportDocumentEmbedsChunksPersistsAndRetrievesBestMatch() async throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let storage = JSONKnowledgeStorageService(rootURL: rootURL)
        let service = KnowledgeService(
            storage: storage,
            chunker: KnowledgeTextChunker(maxCharacters: 80),
            now: { Date(timeIntervalSince1970: 100) }
        )
        let provider = KeywordEmbeddingProvider()

        let collection = try await service.createCollection(named: "Research")
        try await service.importTextDocument(
            collectionID: collection.id,
            fileName: "notes.txt",
            contentType: "text/plain",
            text: "Apples are red and sweet.\n\nEngines produce torque.",
            embeddingModel: "embedding-model",
            provider: provider
        )

        let loaded = try await storage.load()
        XCTAssertEqual(loaded.collections.first?.name, "Research")
        XCTAssertEqual(loaded.documents.first?.fileName, "notes.txt")
        XCTAssertFalse(loaded.chunks.isEmpty)
        XCTAssertTrue(loaded.chunks.allSatisfy { !$0.embedding.isEmpty })

        let results = try await service.retrieve(
            collectionID: collection.id,
            query: "Which fruit is sweet?",
            embeddingModel: "embedding-model",
            provider: provider,
            limit: 1
        )

        XCTAssertEqual(results.count, 1)
        XCTAssertTrue(results.first?.text.contains("Apples") ?? false)
    }

    func testImportDocumentPopulatesKnowledgeMetadata() async throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let storage = JSONKnowledgeStorageService(rootURL: rootURL)
        let service = KnowledgeService(
            storage: storage,
            chunker: KnowledgeTextChunker(maxCharacters: 80),
            now: { Date(timeIntervalSince1970: 300) }
        )
        let provider = KeywordEmbeddingProvider()
        let collection = try await service.createCollection(named: "Research")

        try await service.importTextDocument(
            collectionID: collection.id,
            fileName: "research.pdf",
            contentType: "application/pdf",
            text: "PDF knowledge about native macOS apps.",
            embeddingModel: "embedding-model",
            provider: provider,
            sourceKind: .pdf
        )

        let loaded = try await storage.load()
        let document = try XCTUnwrap(loaded.documents.first)
        XCTAssertEqual(document.metadata.importedFileName, "research.pdf")
        XCTAssertEqual(document.metadata.mimeTypeHint, "application/pdf")
        XCTAssertEqual(document.metadata.byteCount, Data("PDF knowledge about native macOS apps.".utf8).count)
        XCTAssertEqual(document.metadata.sourceKind, .pdf)
        XCTAssertEqual(document.metadata.lastIndexedAt, Date(timeIntervalSince1970: 300))
    }

    func testReindexTextDocumentPreservesDocumentIDAndReplacesChunks() async throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let storage = JSONKnowledgeStorageService(rootURL: rootURL)
        let service = KnowledgeService(
            storage: storage,
            chunker: KnowledgeTextChunker(maxCharacters: 80),
            now: { Date(timeIntervalSince1970: 200) }
        )
        let provider = KeywordEmbeddingProvider()
        let collection = try await service.createCollection(named: "Research")
        try await service.importTextDocument(
            collectionID: collection.id,
            fileName: "notes.txt",
            contentType: "text/plain",
            text: "Old apple notes.",
            embeddingModel: "embedding-model",
            provider: provider
        )
        let originalSnapshot = try await storage.load()
        let originalDocumentID = try XCTUnwrap(originalSnapshot.documents.first?.id)

        try await service.reindexTextDocument(
            collectionID: collection.id,
            fileName: "notes.txt",
            contentType: "text/plain",
            text: "Fresh engine notes.",
            embeddingModel: "embedding-model",
            provider: provider
        )

        let reindexedSnapshot = try await storage.load()
        XCTAssertEqual(reindexedSnapshot.documents.count, 1)
        XCTAssertEqual(reindexedSnapshot.documents.first?.id, originalDocumentID)
        XCTAssertEqual(reindexedSnapshot.documents.first?.byteCount, Data("Fresh engine notes.".utf8).count)
        XCTAssertFalse(reindexedSnapshot.chunks.contains { $0.text.contains("Old apple") })
        XCTAssertTrue(reindexedSnapshot.chunks.contains { $0.text.contains("Fresh engine") })
        XCTAssertTrue(reindexedSnapshot.chunks.allSatisfy { $0.documentID == originalDocumentID })
    }

    func testDeleteCollectionRemovesCollectionDocumentsAndChunks() async throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let storage = JSONKnowledgeStorageService(rootURL: rootURL)
        let service = KnowledgeService(storage: storage)
        let keptCollection = try await service.createCollection(named: "Keep")
        let deletedCollection = try await service.createCollection(named: "Delete")
        let provider = KeywordEmbeddingProvider()
        try await service.importTextDocument(
            collectionID: keptCollection.id,
            fileName: "keep.txt",
            contentType: "text/plain",
            text: "Keep apples.",
            embeddingModel: "embedding-model",
            provider: provider
        )
        try await service.importTextDocument(
            collectionID: deletedCollection.id,
            fileName: "delete.txt",
            contentType: "text/plain",
            text: "Delete engines.",
            embeddingModel: "embedding-model",
            provider: provider
        )

        try await service.deleteCollection(id: deletedCollection.id)

        let snapshot = try await storage.load()
        XCTAssertEqual(snapshot.collections.map(\.id), [keptCollection.id])
        XCTAssertEqual(snapshot.documents.map(\.collectionID), [keptCollection.id])
        XCTAssertEqual(snapshot.chunks.map(\.collectionID), [keptCollection.id])
    }

    func testDeleteDocumentRemovesOnlyThatDocumentsChunks() async throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let storage = JSONKnowledgeStorageService(rootURL: rootURL)
        let service = KnowledgeService(storage: storage)
        let collection = try await service.createCollection(named: "Research")
        let provider = KeywordEmbeddingProvider()
        try await service.importTextDocument(
            collectionID: collection.id,
            fileName: "fruit.txt",
            contentType: "text/plain",
            text: "Apples are sweet.",
            embeddingModel: "embedding-model",
            provider: provider
        )
        try await service.importTextDocument(
            collectionID: collection.id,
            fileName: "engine.txt",
            contentType: "text/plain",
            text: "Engines make torque.",
            embeddingModel: "embedding-model",
            provider: provider
        )
        let documents = try await service.loadDocuments(collectionID: collection.id)
        let deletedDocument = try XCTUnwrap(documents.first { $0.fileName == "fruit.txt" })

        try await service.deleteDocument(id: deletedDocument.id)

        let snapshot = try await storage.load()
        XCTAssertEqual(snapshot.documents.map(\.fileName), ["engine.txt"])
        XCTAssertFalse(snapshot.chunks.contains { $0.documentID == deletedDocument.id })
        XCTAssertTrue(snapshot.chunks.contains { $0.sourceName == "engine.txt" })
        XCTAssertEqual(snapshot.collections.first?.id, collection.id)
    }

    func testLoadDocumentDetailReturnsCollectionDocumentAndOrderedChunks() async throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let storage = JSONKnowledgeStorageService(rootURL: rootURL)
        let service = KnowledgeService(
            storage: storage,
            chunker: KnowledgeTextChunker(maxCharacters: 24)
        )
        let provider = KeywordEmbeddingProvider()
        let collection = try await service.createCollection(named: "Research")
        try await service.importTextDocument(
            collectionID: collection.id,
            fileName: "notes.txt",
            contentType: "text/plain",
            text: "Apples are sweet.\n\nEngines make torque.",
            embeddingModel: "embedding-model",
            provider: provider
        )
        let documents = try await service.loadDocuments(collectionID: collection.id)
        let document = try XCTUnwrap(documents.first)

        let detail = try await service.loadDocumentDetail(id: document.id)

        XCTAssertEqual(detail.collection.id, collection.id)
        XCTAssertEqual(detail.document.fileName, "notes.txt")
        XCTAssertEqual(detail.chunks.map(\.index), Array(detail.chunks.indices))
        XCTAssertTrue(detail.previewText.contains("Apples are sweet."))
        XCTAssertTrue(detail.previewText.contains("Engines make torque."))
    }

    func testExportAndImportKnowledgeJSONRoundTripsIndexedSnapshot() async throws {
        let exportRootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let exportStorage = JSONKnowledgeStorageService(rootURL: exportRootURL)
        let exportService = KnowledgeService(
            storage: exportStorage,
            chunker: KnowledgeTextChunker(maxCharacters: 80)
        )
        let provider = KeywordEmbeddingProvider()
        let collection = try await exportService.createCollection(named: "Research")
        try await exportService.importTextDocument(
            collectionID: collection.id,
            fileName: "fruit.txt",
            contentType: "text/plain",
            text: "Apples are sweet.",
            embeddingModel: "embedding-model",
            provider: provider
        )
        try await exportService.importTextDocument(
            collectionID: collection.id,
            fileName: "engine.txt",
            contentType: "text/plain",
            text: "Engines make torque.",
            embeddingModel: "embedding-model",
            provider: provider
        )

        let data = try await exportService.exportKnowledgeJSONData()

        let importRootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let importStorage = JSONKnowledgeStorageService(rootURL: importRootURL)
        let importService = KnowledgeService(storage: importStorage)
        try await importService.importKnowledgeJSONData(data)

        let importedSnapshot = try await importStorage.load()
        XCTAssertEqual(importedSnapshot.collections.map(\.id), [collection.id])
        XCTAssertEqual(Set(importedSnapshot.documents.map(\.fileName)), ["fruit.txt", "engine.txt"])
        XCTAssertEqual(importedSnapshot.chunks.count, 2)
        XCTAssertTrue(importedSnapshot.chunks.allSatisfy { !$0.embedding.isEmpty })

        let results = try await importService.retrieve(
            collectionID: collection.id,
            query: "Which machine creates torque?",
            embeddingModel: "embedding-model",
            provider: provider,
            limit: 1
        )
        XCTAssertEqual(results.first?.document?.fileName, "engine.txt")
    }

    func testStorageRoundTripsKnowledgeSnapshot() async throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let storage = JSONKnowledgeStorageService(rootURL: rootURL)
        let collectionID = UUID()
        let documentID = UUID()
        let date = Date(timeIntervalSince1970: 50)
        let snapshot = KnowledgeSnapshot(
            collections: [
                KnowledgeCollection(id: collectionID, name: "Docs", createdAt: date, updatedAt: date)
            ],
            documents: [
                KnowledgeDocument(
                    id: documentID,
                    collectionID: collectionID,
                    fileName: "doc.txt",
                    contentType: "text/plain",
                    byteCount: 12,
                    createdAt: date,
                    updatedAt: date
                )
            ],
            chunks: [
                KnowledgeChunk(
                    collectionID: collectionID,
                    documentID: documentID,
                    sourceName: "doc.txt",
                    index: 0,
                    text: "Local notes",
                    embedding: [1, 0],
                    createdAt: date
                )
            ]
        )

        try await storage.save(snapshot)
        let loaded = try await storage.load()

        XCTAssertEqual(loaded.collections, snapshot.collections)
        XCTAssertEqual(loaded.documents, snapshot.documents)
        XCTAssertEqual(loaded.chunks, snapshot.chunks)
    }

    func testStorageLoadsLegacyKnowledgeSnapshotWithoutDocumentMetadata() async throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let storage = JSONKnowledgeStorageService(rootURL: rootURL)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)

        let collectionID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
        let documentID = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
        let timestamp = "1970-01-01T00:00:50Z"
        let legacyJSON = """
        {
          "collections": [
            {
              "id": "\(collectionID.uuidString)",
              "name": "Docs",
              "slug": "docs",
              "allowedUserIDs": [],
              "allowedGroupIDs": [],
              "createdAt": "\(timestamp)",
              "updatedAt": "\(timestamp)"
            }
          ],
          "documents": [
            {
              "id": "\(documentID.uuidString)",
              "collectionID": "\(collectionID.uuidString)",
              "fileName": "doc.txt",
              "contentType": "text/plain",
              "byteCount": 12,
              "createdAt": "\(timestamp)",
              "updatedAt": "\(timestamp)"
            }
          ],
          "chunks": []
        }
        """
        let legacyURL = rootURL.appendingPathComponent("knowledge.json")
        let legacyData = try XCTUnwrap(legacyJSON.data(using: .utf8))
        try legacyData.write(to: legacyURL)

        let loaded = try await storage.load()
        let document = try XCTUnwrap(loaded.documents.first)

        XCTAssertEqual(document.fileName, "doc.txt")
        XCTAssertEqual(document.metadata.importedFileName, "doc.txt")
        XCTAssertEqual(document.metadata.mimeTypeHint, "text/plain")
        XCTAssertEqual(document.metadata.sourceKind, .plainText)
        XCTAssertEqual(document.metadata.byteCount, 12)
        XCTAssertEqual(document.metadata.lastIndexedAt, Date(timeIntervalSince1970: 50))
    }
}

private actor KeywordEmbeddingProvider: ChatProvider {
    nonisolated var configuration: ProviderConfiguration {
        ProviderConfiguration.defaultOllama()
    }

    func listModels() async throws -> [ProviderModel] {
        []
    }

    func healthCheck() async -> ProviderStatus {
        .available("Fake connected")
    }

    nonisolated func streamChat(model: String, messages: [ProviderChatMessage]) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish()
        }
    }

    func createEmbeddings(model: String, input: [String]) async throws -> [[Double]] {
        input.map { text in
            let lowercased = text.lowercased()
            if lowercased.contains("apple") || lowercased.contains("fruit") || lowercased.contains("sweet") {
                return [1, 0]
            }
            if lowercased.contains("engine") || lowercased.contains("torque") {
                return [0, 1]
            }
            return [0.5, 0.5]
        }
    }
}
