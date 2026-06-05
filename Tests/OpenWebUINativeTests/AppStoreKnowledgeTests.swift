import Foundation
import AppKit
import XCTest
@testable import OpenWebUINative

@MainActor
final class AppStoreKnowledgeTests: XCTestCase {
    func testSendPromptWithCollectionMentionAddsRetrievedKnowledgeContext() async throws {
        let provider = CapturingKnowledgeProvider(chunks: ["answer"])
        let fixture = try KnowledgeStoreFixture(provider: provider)
        let store = fixture.makeStore()
        await store.load()
        await store.selectModel("fake-model")

        let collection = try await fixture.knowledgeService.createCollection(named: "Research")
        try await fixture.knowledgeService.importTextDocument(
            collectionID: collection.id,
            fileName: "fruit.txt",
            contentType: "text/plain",
            text: "Apples are red and sweet.",
            embeddingModel: "fake-model",
            provider: provider
        )
        await store.loadKnowledgeCollections()
        XCTAssertEqual(store.knowledgeCollections.first?.slug, "research")

        await store.send("Use #research to answer: which fruit is sweet?")

        let sentContent = await provider.capturedMessages.first { $0.role == "user" }?.content
        let failureContext = sentContent ?? store.errorMessage ?? "No provider content or store error"
        XCTAssertTrue(sentContent?.contains("Knowledge context from #research") ?? false, failureContext)
        XCTAssertTrue(sentContent?.contains("fruit.txt") ?? false, failureContext)
        XCTAssertTrue(sentContent?.contains("Apples are red and sweet.") ?? false, failureContext)
    }

    func testKnowledgeCitationsCarrySourceIDsAndOpenDocumentPreview() async throws {
        let provider = CapturingKnowledgeProvider(chunks: ["answer"])
        let fixture = try KnowledgeStoreFixture(provider: provider)
        let store = fixture.makeStore()
        await store.load()
        await store.selectModel("fake-model")

        let collection = try await fixture.knowledgeService.createCollection(named: "Research")
        try await fixture.knowledgeService.importTextDocument(
            collectionID: collection.id,
            fileName: "fruit.txt",
            contentType: "text/plain",
            text: "Apples are red and sweet.",
            embeddingModel: "fake-model",
            provider: provider
        )
        await store.loadKnowledgeCollections()

        await store.send("Use #research to answer: which fruit is sweet?")

        let userMessage = try XCTUnwrap(store.selectedThread?.messages.first { $0.role == .user })
        let citation = try XCTUnwrap(userMessage.citations.first)
        XCTAssertEqual(citation.collectionID, collection.id)
        XCTAssertNotNil(citation.documentID)
        XCTAssertNotNil(citation.chunkID)

        await store.openCitationSource(citation)

        XCTAssertEqual(store.selectedKnowledgeDocumentDetail?.document.id, citation.documentID)
        XCTAssertEqual(store.selectedKnowledgeChunkID, citation.chunkID)
        XCTAssertTrue(store.selectedKnowledgeDocumentDetail?.previewText.contains("Apples are red and sweet.") ?? false)

        try await store.selectKnowledgeDocument(XCTUnwrap(citation.documentID))

        XCTAssertNil(store.selectedKnowledgeChunkID)
    }

    func testKnowledgeImportAndRetrievalUseEmbeddingModelSetting() async throws {
        let provider = CapturingKnowledgeProvider(chunks: ["answer"])
        let fixture = try KnowledgeStoreFixture(provider: provider)
        let store = fixture.makeStore()
        await store.load()
        await store.selectModel("chat-model")
        await store.selectEmbeddingModel("embedding-model")
        await store.createKnowledgeCollection(named: "Research")
        let collectionID = try XCTUnwrap(store.knowledgeCollections.first?.id)
        let documentURL = fixture.rootURL.appendingPathComponent("fruit.txt")
        try Data("Apples are red and sweet.".utf8).write(to: documentURL)

        await store.importKnowledgeDocument(from: documentURL, toCollectionID: collectionID)
        await store.send("Use #research to answer: which fruit is sweet?")

        let embeddingModelIDs = await provider.embeddingModelIDs
        XCTAssertEqual(embeddingModelIDs, ["embedding-model", "embedding-model"])
    }

    func testKnowledgeImportDefaultsToEmbeddingModelCandidate() async throws {
        let provider = CapturingKnowledgeProvider(chunks: ["answer"])
        let fixture = try KnowledgeStoreFixture(provider: provider)
        let store = fixture.makeStore()
        await store.load()
        await store.selectModel("chat-model")
        await store.createKnowledgeCollection(named: "Research")
        let collectionID = try XCTUnwrap(store.knowledgeCollections.first?.id)
        let documentURL = fixture.rootURL.appendingPathComponent("fruit.txt")
        try Data("Apples are red and sweet.".utf8).write(to: documentURL)

        await store.importKnowledgeDocument(from: documentURL, toCollectionID: collectionID)

        let embeddingModelIDs = await provider.embeddingModelIDs
        XCTAssertEqual(embeddingModelIDs, ["embedding-model"])
    }

    func testImportKnowledgePDFExtractsTextIntoChunks() async throws {
        let provider = CapturingKnowledgeProvider(chunks: ["answer"])
        let fixture = try KnowledgeStoreFixture(provider: provider)
        let store = fixture.makeStore()
        await store.load()
        await store.selectModel("fake-model")
        await store.createKnowledgeCollection(named: "Research")
        let collectionID = try XCTUnwrap(store.knowledgeCollections.first?.id)
        let documentURL = fixture.rootURL.appendingPathComponent("research.pdf")
        try makePDFData(text: "PDF knowledge about native macOS apps.").write(to: documentURL)

        await store.importKnowledgeDocument(from: documentURL, toCollectionID: collectionID)

        let snapshot = try await fixture.knowledgeStorage.load()
        XCTAssertEqual(snapshot.documents.first?.fileName, "research.pdf")
        XCTAssertEqual(snapshot.documents.first?.contentType, "application/pdf")
        XCTAssertEqual(snapshot.documents.first?.metadata.sourceKind, .pdf)
        XCTAssertTrue(snapshot.chunks.contains { $0.text.contains("PDF knowledge about native macOS apps.") })
    }

    func testKnowledgeDocumentsRefreshAfterImportAndDelete() async throws {
        let provider = CapturingKnowledgeProvider(chunks: ["answer"])
        let fixture = try KnowledgeStoreFixture(provider: provider)
        let store = fixture.makeStore()
        await store.load()
        await store.selectModel("fake-model")
        await store.createKnowledgeCollection(named: "Research")
        let collectionID = try XCTUnwrap(store.knowledgeCollections.first?.id)
        let documentURL = fixture.rootURL.appendingPathComponent("notes.txt")
        try Data("Apples are sweet.".utf8).write(to: documentURL)

        await store.importKnowledgeDocument(from: documentURL, toCollectionID: collectionID)
        let importedDocument = try XCTUnwrap(store.knowledgeDocuments[collectionID]?.first)
        XCTAssertEqual(importedDocument.fileName, "notes.txt")

        await store.deleteKnowledgeDocument(importedDocument.id)

        let snapshot = try await fixture.knowledgeStorage.load()
        XCTAssertTrue(store.knowledgeDocuments[collectionID]?.isEmpty ?? false)
        XCTAssertTrue(snapshot.documents.isEmpty)
        XCTAssertTrue(snapshot.chunks.isEmpty)
        XCTAssertEqual(snapshot.collections.first?.id, collectionID)
    }

    func testImportNoteToKnowledgeIndexesNoteAsMarkdownDocument() async throws {
        let provider = CapturingKnowledgeProvider(chunks: ["answer"])
        let fixture = try KnowledgeStoreFixture(provider: provider)
        let store = fixture.makeStore()
        await store.load()
        await store.selectModel("fake-model")
        await store.createKnowledgeCollection(named: "Research")
        let collectionID = try XCTUnwrap(store.knowledgeCollections.first?.id)
        let note = AppNote(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000789")!,
            title: "Launch Research",
            content: "Native notes can become searchable knowledge."
        )
        store.notes = [note]

        await store.importNoteToKnowledge(note.id, toCollectionID: collectionID)

        let snapshot = try await fixture.knowledgeStorage.load()
        let document = try XCTUnwrap(snapshot.documents.first)
        XCTAssertEqual(document.fileName, "Launch Research.md")
        XCTAssertEqual(document.contentType, "text/markdown")
        XCTAssertEqual(document.byteCount, Data(note.content.utf8).count)
        XCTAssertEqual(document.metadata.importedFileName, "Launch Research.md")
        XCTAssertEqual(document.metadata.mimeTypeHint, "text/markdown")
        XCTAssertEqual(document.metadata.sourceKind, .nativeNote)
        XCTAssertEqual(store.knowledgeDocuments[collectionID]?.map(\.id), [document.id])
        XCTAssertTrue(snapshot.chunks.contains { chunk in
            chunk.documentID == document.id && chunk.text.contains("Native notes can become searchable knowledge.")
        })
    }

    func testSelectKnowledgeDocumentLoadsPreviewAndClearsChatSelection() async throws {
        let provider = CapturingKnowledgeProvider(chunks: ["answer"])
        let fixture = try KnowledgeStoreFixture(provider: provider)
        let store = fixture.makeStore()
        await store.load()
        await store.selectModel("fake-model")
        store.createThread()
        await store.createKnowledgeCollection(named: "Research")
        let collectionID = try XCTUnwrap(store.knowledgeCollections.first?.id)
        let documentURL = fixture.rootURL.appendingPathComponent("notes.txt")
        try Data("Apples are sweet.\n\nEngines make torque.".utf8).write(to: documentURL)
        await store.importKnowledgeDocument(from: documentURL, toCollectionID: collectionID)
        let document = try XCTUnwrap(store.knowledgeDocuments[collectionID]?.first)
        XCTAssertNotNil(store.selectedThreadID)

        await store.selectKnowledgeDocument(document.id)

        XCTAssertNil(store.selectedThreadID)
        XCTAssertEqual(store.selectedKnowledgeDocumentDetail?.document.id, document.id)
        XCTAssertTrue(store.selectedKnowledgeDocumentDetail?.previewText.contains("Apples are sweet.") ?? false)
    }

    func testReindexKnowledgeDocumentFromFileUpdatesChunksAndPreservesDocumentID() async throws {
        let provider = CapturingKnowledgeProvider(chunks: ["answer"])
        let fixture = try KnowledgeStoreFixture(provider: provider)
        let store = fixture.makeStore()
        await store.load()
        await store.selectModel("fake-model")
        await store.createKnowledgeCollection(named: "Research")
        let collectionID = try XCTUnwrap(store.knowledgeCollections.first?.id)
        let documentURL = fixture.rootURL.appendingPathComponent("notes.txt")
        try Data("Apples are sweet.".utf8).write(to: documentURL)
        await store.importKnowledgeDocument(from: documentURL, toCollectionID: collectionID)
        let originalSnapshot = try await fixture.knowledgeStorage.load()
        let originalDocumentID = try XCTUnwrap(originalSnapshot.documents.first?.id)

        try Data("Engines make torque.".utf8).write(to: documentURL)
        await store.reindexKnowledgeDocument(from: documentURL, toCollectionID: collectionID)

        let reindexedSnapshot = try await fixture.knowledgeStorage.load()
        XCTAssertNil(store.errorMessage)
        XCTAssertEqual(reindexedSnapshot.documents.first?.id, originalDocumentID)
        XCTAssertFalse(reindexedSnapshot.chunks.contains { $0.text.contains("Apples") })
        XCTAssertTrue(reindexedSnapshot.chunks.contains { $0.text.contains("Engines") })
    }

    func testUpdateKnowledgeCollectionRenamesCollectionAndSlug() async throws {
        let provider = CapturingKnowledgeProvider(chunks: ["answer"])
        let fixture = try KnowledgeStoreFixture(provider: provider)
        let store = fixture.makeStore()
        await store.load()
        await store.createKnowledgeCollection(named: "Research Notes")
        let collectionID = try XCTUnwrap(store.knowledgeCollections.first?.id)

        await store.updateKnowledgeCollection(collectionID, name: "  Launch Research  ")

        XCTAssertEqual(store.knowledgeCollections.map(\.name), ["Launch Research"])
        XCTAssertEqual(store.knowledgeCollections.first?.slug, "launch-research")
        let snapshot = try await fixture.knowledgeStorage.load()
        XCTAssertEqual(snapshot.collections.first?.id, collectionID)
        XCTAssertEqual(snapshot.collections.first?.name, "Launch Research")
        XCTAssertEqual(snapshot.collections.first?.slug, "launch-research")
    }

    func testKnowledgeCollectionsVisibleWhenGrantedToCurrentUser() async throws {
        let provider = CapturingKnowledgeProvider(chunks: ["answer"])
        let fixture = try KnowledgeStoreFixture(provider: provider)
        let store = fixture.makeStore()
        await store.load()
        await store.createAdminUser(name: "Local Admin", email: "admin@example.com", role: .admin)
        await store.createAdminUser(name: "Workspace User", email: "user@example.com", role: .user)
        let admin = try XCTUnwrap(store.adminUsers.first { $0.role == .admin })
        let user = try XCTUnwrap(store.adminUsers.first { $0.role == .user })
        store.currentUserID = admin.id
        await store.createKnowledgeCollection(
            named: "Private Research",
            allowedUserIDs: [user.id],
            allowedGroupIDs: []
        )

        store.currentUserID = user.id
        await store.loadKnowledgeCollections()

        XCTAssertEqual(store.knowledgeCollections.map(\.name), ["Private Research"])
    }

    func testKnowledgeCollectionsHiddenWithoutUserOrGroupGrant() async throws {
        let provider = CapturingKnowledgeProvider(chunks: ["answer"])
        let fixture = try KnowledgeStoreFixture(provider: provider)
        let store = fixture.makeStore()
        await store.load()
        await store.createAdminUser(name: "Local Admin", email: "admin@example.com", role: .admin)
        await store.createAdminUser(name: "Workspace User", email: "user@example.com", role: .user)
        let admin = try XCTUnwrap(store.adminUsers.first { $0.role == .admin })
        let user = try XCTUnwrap(store.adminUsers.first { $0.role == .user })
        store.currentUserID = admin.id
        await store.createKnowledgeCollection(
            named: "Private Research",
            allowedUserIDs: ["someone-else"],
            allowedGroupIDs: []
        )

        store.currentUserID = user.id
        await store.loadKnowledgeCollections()

        XCTAssertTrue(store.knowledgeCollections.isEmpty)
    }

    func testKnowledgeCollectionsVisibleWhenGrantedToCurrentUsersGroup() async throws {
        let provider = CapturingKnowledgeProvider(chunks: ["answer"])
        let fixture = try KnowledgeStoreFixture(provider: provider)
        let store = fixture.makeStore()
        await store.load()
        await store.createAdminUser(name: "Local Admin", email: "admin@example.com", role: .admin)
        await store.createAdminUser(name: "Workspace User", email: "user@example.com", role: .user)
        let admin = try XCTUnwrap(store.adminUsers.first { $0.role == .admin })
        let user = try XCTUnwrap(store.adminUsers.first { $0.role == .user })
        store.currentUserID = admin.id
        await store.createAdminGroup(name: "Research Team", description: "Can use research.", permissions: [])
        let group = try XCTUnwrap(store.adminGroups.first)
        await store.setAdminGroupMembers(group.id, memberIDs: [user.id])
        await store.createKnowledgeCollection(
            named: "Team Research",
            allowedUserIDs: [],
            allowedGroupIDs: [group.id]
        )

        store.currentUserID = user.id
        await store.loadKnowledgeCollections()

        XCTAssertEqual(store.knowledgeCollections.map(\.name), ["Team Research"])
    }

    func testKnowledgeMentionSkipsCollectionWithoutCurrentUserGrant() async throws {
        let provider = CapturingKnowledgeProvider(chunks: ["answer"])
        let fixture = try KnowledgeStoreFixture(provider: provider)
        let store = fixture.makeStore()
        await store.load()
        await store.selectModel("fake-model")
        await store.createAdminUser(name: "Local Admin", email: "admin@example.com", role: .admin)
        await store.createAdminUser(name: "Workspace User", email: "user@example.com", role: .user)
        let admin = try XCTUnwrap(store.adminUsers.first { $0.role == .admin })
        let user = try XCTUnwrap(store.adminUsers.first { $0.role == .user })
        store.currentUserID = admin.id
        await store.createKnowledgeCollection(
            named: "Private Research",
            allowedUserIDs: ["someone-else"],
            allowedGroupIDs: []
        )
        let collectionID = try XCTUnwrap(store.knowledgeCollections.first?.id)
        let documentURL = fixture.rootURL.appendingPathComponent("fruit.txt")
        try Data("Apples are red and sweet.".utf8).write(to: documentURL)
        await store.importKnowledgeDocument(from: documentURL, toCollectionID: collectionID)

        store.currentUserID = user.id
        await store.send("Use #private-research to answer: which fruit is sweet?")

        let sentContent = await provider.capturedMessages.first { $0.role == "user" }?.content
        XCTAssertFalse(sentContent?.contains("Knowledge context from #private-research") ?? false)
        XCTAssertFalse(sentContent?.contains("Apples are red and sweet.") ?? false)
    }

    func testKnowledgeJSONRoundTripsCollectionAccessGrants() async throws {
        let provider = CapturingKnowledgeProvider(chunks: ["answer"])
        let fixture = try KnowledgeStoreFixture(provider: provider)
        let store = fixture.makeStore()
        await store.load()
        await store.createKnowledgeCollection(
            named: "Private Research",
            allowedUserIDs: ["user-id"],
            allowedGroupIDs: ["group-id"]
        )

        let data = try await store.exportKnowledgeJSONData()
        let importFixture = try KnowledgeStoreFixture(provider: provider)
        let importStore = importFixture.makeStore()
        await importStore.load()
        try await importStore.importKnowledgeJSONData(data)

        let collection = try XCTUnwrap(importStore.knowledgeCollections.first)
        XCTAssertEqual(collection.allowedUserIDs, ["user-id"])
        XCTAssertEqual(collection.allowedGroupIDs, ["group-id"])
    }

    func testExportKnowledgeCollectionJSONDataIncludesOnlySelectedCollection() async throws {
        let provider = CapturingKnowledgeProvider(chunks: ["answer"])
        let fixture = try KnowledgeStoreFixture(provider: provider)
        let store = fixture.makeStore()
        await store.load()
        await store.selectModel("fake-model")
        await store.createKnowledgeCollection(
            named: "Private Research",
            allowedUserIDs: ["user-id"],
            allowedGroupIDs: ["group-id"]
        )
        await store.createKnowledgeCollection(named: "Public Research")
        let privateCollectionID = try XCTUnwrap(store.knowledgeCollections.first { $0.name == "Private Research" }?.id)
        let publicCollectionID = try XCTUnwrap(store.knowledgeCollections.first { $0.name == "Public Research" }?.id)
        let privateDocumentURL = fixture.rootURL.appendingPathComponent("private.txt")
        let publicDocumentURL = fixture.rootURL.appendingPathComponent("public.txt")
        try Data("Private knowledge should travel.".utf8).write(to: privateDocumentURL)
        try Data("Public knowledge should stay behind.".utf8).write(to: publicDocumentURL)
        await store.importKnowledgeDocument(from: privateDocumentURL, toCollectionID: privateCollectionID)
        await store.importKnowledgeDocument(from: publicDocumentURL, toCollectionID: publicCollectionID)

        let data = try await store.exportKnowledgeCollectionJSONData(privateCollectionID)
        let importFixture = try KnowledgeStoreFixture(provider: provider)
        let importStore = importFixture.makeStore()
        await importStore.load()
        try await importStore.importKnowledgeJSONData(data)

        let importedCollection = try XCTUnwrap(importStore.knowledgeCollections.first)
        XCTAssertEqual(importStore.knowledgeCollections.map(\.name), ["Private Research"])
        XCTAssertEqual(importedCollection.allowedUserIDs, ["user-id"])
        XCTAssertEqual(importedCollection.allowedGroupIDs, ["group-id"])
        XCTAssertEqual(importStore.knowledgeDocuments[privateCollectionID]?.map(\.fileName), ["private.txt"])
        let importedSnapshot = try await importFixture.knowledgeStorage.load()
        XCTAssertTrue(importedSnapshot.chunks.contains { $0.text.contains("Private knowledge should travel.") })
        XCTAssertFalse(importedSnapshot.chunks.contains { $0.text.contains("Public knowledge should stay behind.") })
    }

    func testShareKnowledgeCollectionSharesSelectedCollectionJSON() async throws {
        let provider = CapturingKnowledgeProvider(chunks: ["answer"])
        let shareService = FakeKnowledgeShareService()
        let fixture = try KnowledgeStoreFixture(provider: provider, shareService: shareService)
        let store = fixture.makeStore()
        await store.load()
        await store.selectModel("fake-model")
        await store.createKnowledgeCollection(named: "Research")
        let collectionID = try XCTUnwrap(store.knowledgeCollections.first?.id)
        let documentURL = fixture.rootURL.appendingPathComponent("notes.txt")
        try Data("Shared knowledge.".utf8).write(to: documentURL)
        await store.importKnowledgeDocument(from: documentURL, toCollectionID: collectionID)

        await store.shareKnowledgeCollection(collectionID)

        XCTAssertEqual(shareService.sharedTitle, "Research")
        let sharedText = try XCTUnwrap(shareService.sharedText)
        let importFixture = try KnowledgeStoreFixture(provider: provider)
        let importStore = importFixture.makeStore()
        await importStore.load()
        try await importStore.importKnowledgeJSONData(Data(sharedText.utf8))
        XCTAssertEqual(importStore.knowledgeCollections.map(\.name), ["Research"])
        XCTAssertEqual(importStore.knowledgeDocuments[collectionID]?.map(\.fileName), ["notes.txt"])
    }

    func testKnowledgeActionsBlockDisabledFeatureBeforeProviderSharingOrPersistenceChanges() async throws {
        let provider = CapturingKnowledgeProvider(chunks: ["answer"])
        let shareService = FakeKnowledgeShareService()
        let fixture = try KnowledgeStoreFixture(provider: provider, shareService: shareService)
        let store = fixture.makeStore()
        await store.load()
        await store.selectModel("fake-model")
        await store.createKnowledgeCollection(named: "Existing")
        let collectionID = try XCTUnwrap(store.knowledgeCollections.first?.id)
        let documentURL = fixture.rootURL.appendingPathComponent("notes.txt")
        try Data("Apples are sweet.".utf8).write(to: documentURL)
        await store.importKnowledgeDocument(from: documentURL, toCollectionID: collectionID)
        let document = try XCTUnwrap(store.knowledgeDocuments[collectionID]?.first)
        let importData = try await makeKnowledgeExportData(named: "Blocked Import", provider: provider)
        let embeddingCallCountBeforeDisable = await provider.embeddingModelIDs.count
        try Data("Engines make torque.".utf8).write(to: documentURL)

        await store.setFeatureToggle(.knowledge, isEnabled: false)
        await store.createKnowledgeCollection(named: "Blocked Create")
        await store.updateKnowledgeCollection(collectionID, name: "Blocked Rename")
        await store.importKnowledgeDocument(from: documentURL, toCollectionID: collectionID)
        await store.reindexKnowledgeDocument(from: documentURL, toCollectionID: collectionID)
        try await store.importKnowledgeJSONData(importData)
        await store.shareKnowledgeCollection(collectionID)
        await store.updateKnowledgeDocument(document.id, fileName: "blocked.txt")
        await store.deleteKnowledgeDocument(document.id)
        await store.deleteKnowledgeCollection(collectionID)

        let snapshot = try await fixture.knowledgeStorage.load()
        XCTAssertEqual(store.knowledgeCollections.map(\.name), ["Existing"])
        XCTAssertEqual(store.knowledgeDocuments[collectionID]?.map(\.fileName), ["notes.txt"])
        XCTAssertEqual(snapshot.collections.map(\.name), ["Existing"])
        XCTAssertEqual(snapshot.documents.map(\.fileName), ["notes.txt"])
        XCTAssertTrue(snapshot.chunks.contains { $0.text.contains("Apples are sweet.") })
        XCTAssertFalse(snapshot.chunks.contains { $0.text.contains("Engines make torque.") })
        XCTAssertFalse(snapshot.collections.contains { $0.name == "Blocked Import" })
        let embeddingCallCountAfterDisabledActions = await provider.embeddingModelIDs.count
        XCTAssertEqual(embeddingCallCountAfterDisabledActions, embeddingCallCountBeforeDisable)
        XCTAssertNil(shareService.sharedText)
        XCTAssertNil(shareService.sharedTitle)
        XCTAssertEqual(store.errorMessage, "Knowledge is disabled.")
    }

    func testUpdateKnowledgeDocumentRenamesDocumentAndChunkSources() async throws {
        let provider = CapturingKnowledgeProvider(chunks: ["answer"])
        let fixture = try KnowledgeStoreFixture(provider: provider)
        let store = fixture.makeStore()
        await store.load()
        await store.selectModel("fake-model")
        await store.createKnowledgeCollection(named: "Research")
        let collectionID = try XCTUnwrap(store.knowledgeCollections.first?.id)
        let documentURL = fixture.rootURL.appendingPathComponent("notes.txt")
        try Data("Apples are sweet.".utf8).write(to: documentURL)
        await store.importKnowledgeDocument(from: documentURL, toCollectionID: collectionID)
        let document = try XCTUnwrap(store.knowledgeDocuments[collectionID]?.first)
        await store.selectKnowledgeDocument(document.id)

        await store.updateKnowledgeDocument(document.id, fileName: "  launch-notes.md  ")

        XCTAssertEqual(store.knowledgeDocuments[collectionID]?.map(\.fileName), ["launch-notes.md"])
        XCTAssertEqual(store.selectedKnowledgeDocumentDetail?.document.fileName, "launch-notes.md")
        let snapshot = try await fixture.knowledgeStorage.load()
        XCTAssertEqual(snapshot.documents.first?.id, document.id)
        XCTAssertEqual(snapshot.documents.first?.fileName, "launch-notes.md")
        XCTAssertEqual(Set(snapshot.chunks.map(\.sourceName)), ["launch-notes.md"])
    }

    func testDeleteKnowledgeCollectionRefreshesStoreAndRemovesIndexedData() async throws {
        let provider = CapturingKnowledgeProvider(chunks: ["answer"])
        let fixture = try KnowledgeStoreFixture(provider: provider)
        let store = fixture.makeStore()
        await store.load()
        await store.selectModel("fake-model")
        await store.createKnowledgeCollection(named: "Research")
        let collectionID = try XCTUnwrap(store.knowledgeCollections.first?.id)
        let documentURL = fixture.rootURL.appendingPathComponent("notes.txt")
        try Data("Apples are sweet.".utf8).write(to: documentURL)
        await store.importKnowledgeDocument(from: documentURL, toCollectionID: collectionID)

        await store.deleteKnowledgeCollection(collectionID)

        let snapshot = try await fixture.knowledgeStorage.load()
        XCTAssertTrue(store.knowledgeCollections.isEmpty)
        XCTAssertTrue(snapshot.collections.isEmpty)
        XCTAssertTrue(snapshot.documents.isEmpty)
        XCTAssertTrue(snapshot.chunks.isEmpty)
    }

    func testExportAndImportKnowledgeJSONRefreshesVisibleCollectionsAndDocuments() async throws {
        let provider = CapturingKnowledgeProvider(chunks: ["answer"])
        let fixture = try KnowledgeStoreFixture(provider: provider)
        let store = fixture.makeStore()
        await store.load()
        await store.selectModel("fake-model")
        await store.createKnowledgeCollection(named: "Research")
        let collectionID = try XCTUnwrap(store.knowledgeCollections.first?.id)
        let documentURL = fixture.rootURL.appendingPathComponent("notes.txt")
        try Data("Apples are sweet.".utf8).write(to: documentURL)
        await store.importKnowledgeDocument(from: documentURL, toCollectionID: collectionID)

        let data = try await store.exportKnowledgeJSONData()

        let importFixture = try KnowledgeStoreFixture(provider: provider)
        let importStore = importFixture.makeStore()
        await importStore.load()
        try await importStore.importKnowledgeJSONData(data)

        XCTAssertEqual(importStore.knowledgeCollections.map(\.id), [collectionID])
        XCTAssertEqual(importStore.knowledgeDocuments[collectionID]?.map(\.fileName), ["notes.txt"])
        let importedSnapshot = try await importFixture.knowledgeStorage.load()
        XCTAssertEqual(importedSnapshot.documents.first?.collectionID, collectionID)
        XCTAssertTrue(importedSnapshot.chunks.contains { $0.text.contains("Apples are sweet.") })
    }

    func testImportKnowledgeDocumentBlocksUnsupportedEmbeddingProviderBeforeCallingProvider() async throws {
        let provider = UnsupportedKnowledgeProvider()
        let fixture = try KnowledgeStoreFixture(provider: provider)
        let store = fixture.makeStore()
        await store.load()
        await store.selectModel("llama3.2")
        await store.createKnowledgeCollection(named: "Research")
        let collectionID = try XCTUnwrap(store.knowledgeCollections.first?.id)
        let documentURL = fixture.rootURL.appendingPathComponent("notes.txt")
        try Data("Apples are sweet.".utf8).write(to: documentURL)

        await store.importKnowledgeDocument(from: documentURL, toCollectionID: collectionID)

        XCTAssertEqual(
            store.errorMessage,
            "Ollama does not support native embeddings in this app. Choose an OpenAI-compatible provider with embedding models."
        )
        let snapshot = try await fixture.knowledgeStorage.load()
        XCTAssertTrue(snapshot.documents.isEmpty)
        XCTAssertTrue(snapshot.chunks.isEmpty)
        let embeddingCallCount = await provider.embeddingCallCount
        XCTAssertEqual(embeddingCallCount, 0)
    }

    func testSendWithKnowledgeMentionBlocksUnsupportedEmbeddingProviderBeforeRetrieval() async throws {
        let provider = UnsupportedKnowledgeProvider()
        let fixture = try KnowledgeStoreFixture(provider: provider)
        let store = fixture.makeStore()
        await store.load()
        await store.selectModel("llama3.2")
        await store.createKnowledgeCollection(named: "Research")

        await store.send("Use #research to answer: which fruit is sweet?")

        XCTAssertEqual(
            store.errorMessage,
            "Ollama does not support native embeddings in this app. Choose an OpenAI-compatible provider with embedding models."
        )
        XCTAssertTrue(store.selectedThread?.messages.isEmpty ?? false)
        let embeddingCallCount = await provider.embeddingCallCount
        XCTAssertEqual(embeddingCallCount, 0)
    }

    func testSendWithKnowledgeMentionBlocksDisabledFeatureBeforeRetrievalOrProviderChat() async throws {
        let provider = CapturingKnowledgeProvider(chunks: ["answer"])
        let fixture = try KnowledgeStoreFixture(provider: provider)
        let store = fixture.makeStore()
        await store.load()
        await store.selectModel("fake-model")
        await store.createKnowledgeCollection(named: "Research")
        let collectionID = try XCTUnwrap(store.knowledgeCollections.first?.id)
        let documentURL = fixture.rootURL.appendingPathComponent("fruit.txt")
        try Data("Apples are red and sweet.".utf8).write(to: documentURL)
        await store.importKnowledgeDocument(from: documentURL, toCollectionID: collectionID)
        let embeddingCallCountBeforeDisable = await provider.embeddingModelIDs.count

        await store.setFeatureToggle(.knowledge, isEnabled: false)
        await store.send("Use #research to answer: which fruit is sweet?")

        let embeddingCallCountAfterDisabledSend = await provider.embeddingModelIDs.count
        XCTAssertEqual(embeddingCallCountAfterDisabledSend, embeddingCallCountBeforeDisable)
        let capturedMessagesAfterDisabledSend = await provider.capturedMessages
        XCTAssertTrue(capturedMessagesAfterDisabledSend.isEmpty)
        XCTAssertTrue(store.selectedThread?.messages.isEmpty ?? false)
        XCTAssertEqual(store.errorMessage, "Knowledge is disabled.")
    }

    func testKnowledgeWritePermissionAllowsCreateUpdateImportReindexDeleteAndJSONImportForCurrentUser() async throws {
        let provider = CapturingKnowledgeProvider(chunks: ["answer"])
        let fixture = try KnowledgeStoreFixture(provider: provider)
        let store = fixture.makeStore()
        await store.load()
        await store.selectModel("fake-model")
        await store.createAdminUser(name: "Workspace User", email: "user@example.com", role: .user)
        let user = try XCTUnwrap(store.adminUsers.first)
        await store.createAdminGroup(name: "Knowledge Editors", description: "Can manage knowledge.", permissions: ["knowledge.write"])
        let group = try XCTUnwrap(store.adminGroups.first)
        await store.setAdminGroupMembers(group.id, memberIDs: [user.id])
        store.currentUserID = user.id
        let documentURL = fixture.rootURL.appendingPathComponent("notes.txt")
        try Data("Apples are sweet.".utf8).write(to: documentURL)

        await store.createKnowledgeCollection(named: "Research")
        let collectionID = try XCTUnwrap(store.knowledgeCollections.first?.id)
        await store.updateKnowledgeCollection(collectionID, name: "Updated Research")
        await store.importKnowledgeDocument(from: documentURL, toCollectionID: collectionID)
        let importedDocument = try XCTUnwrap(store.knowledgeDocuments[collectionID]?.first)
        await store.updateKnowledgeDocument(importedDocument.id, fileName: "updated-notes.txt")
        let renamedDocumentURL = fixture.rootURL.appendingPathComponent("updated-notes.txt")
        try Data("Engines make torque.".utf8).write(to: renamedDocumentURL)
        await store.reindexKnowledgeDocument(from: renamedDocumentURL, toCollectionID: collectionID)
        await store.deleteKnowledgeDocument(importedDocument.id)
        await store.deleteKnowledgeCollection(collectionID)

        let importData = try await makeKnowledgeExportData(named: "Imported", provider: provider)
        try await store.importKnowledgeJSONData(importData)

        XCTAssertEqual(store.knowledgeCollections.map(\.name), ["Imported"])
        XCTAssertNil(store.errorMessage)
    }

    func testKnowledgeWritePermissionBlocksCreateUpdateImportReindexDeleteAndJSONImportForCurrentUser() async throws {
        let provider = CapturingKnowledgeProvider(chunks: ["answer"])
        let fixture = try KnowledgeStoreFixture(provider: provider)
        let store = fixture.makeStore()
        await store.load()
        await store.selectModel("fake-model")
        await store.createAdminUser(name: "Workspace User", email: "user@example.com", role: .user)
        let user = try XCTUnwrap(store.adminUsers.first)
        store.currentUserID = user.id
        let documentURL = fixture.rootURL.appendingPathComponent("notes.txt")
        try Data("Apples are sweet.".utf8).write(to: documentURL)

        await store.createKnowledgeCollection(named: "Blocked")

        XCTAssertTrue(store.knowledgeCollections.isEmpty)
        XCTAssertEqual(store.errorMessage, "You do not have permission to manage knowledge.")

        store.errorMessage = nil
        store.currentUserID = "local-admin"
        await store.createAdminUser(name: "Local Admin", email: "admin@example.com", role: .admin)
        let admin = try XCTUnwrap(store.adminUsers.first { $0.role == .admin })
        store.currentUserID = admin.id
        await store.createKnowledgeCollection(named: "Existing")
        let collectionID = try XCTUnwrap(store.knowledgeCollections.first?.id)
        await store.importKnowledgeDocument(from: documentURL, toCollectionID: collectionID)
        let document = try XCTUnwrap(store.knowledgeDocuments[collectionID]?.first)
        let importData = try await makeKnowledgeExportData(named: "Imported", provider: provider)

        store.currentUserID = user.id
        try Data("Engines make torque.".utf8).write(to: documentURL)
        await store.updateKnowledgeCollection(collectionID, name: "Blocked Rename")
        await store.updateKnowledgeDocument(document.id, fileName: "blocked.txt")
        await store.importKnowledgeDocument(from: documentURL, toCollectionID: collectionID)
        await store.reindexKnowledgeDocument(from: documentURL, toCollectionID: collectionID)
        try await store.importKnowledgeJSONData(importData)
        await store.deleteKnowledgeDocument(document.id)
        await store.deleteKnowledgeCollection(collectionID)

        let snapshot = try await fixture.knowledgeStorage.load()
        XCTAssertEqual(store.knowledgeCollections.map(\.name), ["Existing"])
        XCTAssertEqual(store.knowledgeDocuments[collectionID]?.map(\.fileName), ["notes.txt"])
        XCTAssertEqual(snapshot.collections.map(\.id), [collectionID])
        XCTAssertEqual(snapshot.documents.map(\.id), [document.id])
        XCTAssertFalse(snapshot.chunks.contains { $0.text.contains("Engines") })
        XCTAssertEqual(store.errorMessage, "You do not have permission to manage knowledge.")
    }

    func testUnmanagedLocalUserCanManageKnowledgeWhenAdminDirectoryExists() async throws {
        let provider = CapturingKnowledgeProvider(chunks: ["answer"])
        let fixture = try KnowledgeStoreFixture(provider: provider)
        let store = fixture.makeStore()
        await store.load()
        await store.selectModel("fake-model")
        await store.createAdminUser(name: "Workspace User", email: "user@example.com", role: .user)

        await store.createKnowledgeCollection(named: "Local")

        XCTAssertEqual(store.knowledgeCollections.map(\.name), ["Local"])
        XCTAssertNil(store.errorMessage)
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

private func makeKnowledgeExportData(named name: String, provider: any ChatProvider) async throws -> Data {
    let rootURL = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    let storage = JSONKnowledgeStorageService(rootURL: rootURL)
    let service = KnowledgeService(storage: storage, chunker: KnowledgeTextChunker(maxCharacters: 120))
    let collection = try await service.createCollection(named: name)
    try await service.importTextDocument(
        collectionID: collection.id,
        fileName: "imported.txt",
        contentType: "text/plain",
        text: "Imported knowledge.",
        embeddingModel: "fake-model",
        provider: provider
    )
    return try await service.exportKnowledgeJSONData()
}

private struct KnowledgeStoreFixture {
    let rootURL: URL
    let storage: JSONStorageService
    let settingsStore: SettingsStore
    let knowledgeStorage: JSONKnowledgeStorageService
    let knowledgeService: KnowledgeService
    let adminStorage: JSONAdminDirectoryStorageService
    let provider: (any ChatProvider)?
    let shareService: (any ChatSharing)?

    init(provider: (any ChatProvider)? = nil, shareService: (any ChatSharing)? = nil) throws {
        rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        storage = JSONStorageService(rootURL: rootURL.appendingPathComponent("Chats", isDirectory: true))
        settingsStore = SettingsStore(settingsURL: rootURL.appendingPathComponent("settings.json"))
        knowledgeStorage = JSONKnowledgeStorageService(rootURL: rootURL.appendingPathComponent("Knowledge", isDirectory: true))
        knowledgeService = KnowledgeService(
            storage: knowledgeStorage,
            chunker: KnowledgeTextChunker(maxCharacters: 120)
        )
        adminStorage = JSONAdminDirectoryStorageService(
            snapshotURL: rootURL.appendingPathComponent("admin-directory.json")
        )
        self.provider = provider
        self.shareService = shareService
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
    }

    @MainActor
    func makeStore() -> AppStore {
        AppStore(
            storage: storage,
            settingsStore: settingsStore,
            secretStore: InMemorySecretStore(),
            providerOverride: provider,
            shareService: shareService,
            knowledgeService: knowledgeService,
            adminDirectoryStorage: adminStorage
        )
    }
}

@MainActor
private final class FakeKnowledgeShareService: ChatSharing {
    private(set) var sharedText: String?
    private(set) var sharedTitle: String?

    func share(text: String, title: String) {
        sharedText = text
        sharedTitle = title
    }
}

private actor CapturingKnowledgeProvider: ChatProvider {
    nonisolated var configuration: ProviderConfiguration {
        ProviderConfiguration.defaultOllama()
    }

    nonisolated var capabilities: ProviderCapabilities {
        var capabilities = ProviderConfiguration.defaultOllama().capabilities
        capabilities.supportsEmbeddings = true
        return capabilities
    }

    private(set) var capturedMessages: [ProviderChatMessage] = []
    private(set) var embeddingModelIDs: [String] = []
    var chunks: [String]

    init(chunks: [String]) {
        self.chunks = chunks
    }

    func listModels() async throws -> [ProviderModel] {
        [
            ProviderModel(id: "fake-model", name: "fake-model", provider: .ollama, providerID: configuration.id),
            ProviderModel(id: "chat-model", name: "chat-model", provider: .ollama, providerID: configuration.id),
            ProviderModel(id: "embedding-model", name: "embedding-model", provider: .ollama, providerID: configuration.id)
        ]
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
        embeddingModelIDs.append(model)
        return input.map { text in
            let lowercased = text.lowercased()
            if lowercased.contains("apple") || lowercased.contains("fruit") || lowercased.contains("sweet") {
                return [1, 0]
            }
            return [0, 1]
        }
    }

    private func setCapturedMessages(_ messages: [ProviderChatMessage]) {
        capturedMessages = messages
    }
}

private actor UnsupportedKnowledgeProvider: ChatProvider {
    nonisolated let configuration = ProviderConfiguration.defaultOllama()
    private(set) var embeddingCallCount = 0

    func listModels() async throws -> [ProviderModel] {
        [ProviderModel(id: "llama3.2", name: "llama3.2", provider: .ollama, providerID: configuration.id)]
    }

    func healthCheck() async -> ProviderStatus {
        .available("Fake connected")
    }

    nonisolated func streamChat(model: String, messages: [ProviderChatMessage]) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            continuation.yield("answer")
            continuation.finish()
        }
    }

    func createEmbeddings(model: String, input: [String]) async throws -> [[Double]] {
        embeddingCallCount += 1
        return input.map { _ in [1, 0] }
    }
}
