import Foundation

struct KnowledgeTextChunker: Sendable {
    var maxCharacters: Int

    init(maxCharacters: Int = 1_200) {
        self.maxCharacters = max(1, maxCharacters)
    }

    func chunks(
        for text: String,
        collectionID: UUID,
        documentID: UUID,
        sourceName: String
    ) -> [KnowledgeChunk] {
        let paragraphs = text
            .components(separatedBy: CharacterSet.newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        let units = (paragraphs.isEmpty ? [text] : paragraphs)
            .flatMap(splitLongUnit)
        var chunks: [String] = []
        var current = ""

        for unit in units {
            if current.isEmpty {
                current = unit
            } else if current.count + unit.count + 2 <= maxCharacters {
                current += "\n\n\(unit)"
            } else {
                chunks.append(current)
                current = unit
            }
        }

        if !current.isEmpty {
            chunks.append(current)
        }

        return chunks.enumerated().map { index, text in
            KnowledgeChunk(
                collectionID: collectionID,
                documentID: documentID,
                sourceName: sourceName,
                index: index,
                text: text
            )
        }
    }

    private func splitLongUnit(_ unit: String) -> [String] {
        guard unit.count > maxCharacters else {
            return [unit]
        }

        let words = unit.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        var parts: [String] = []
        var current = ""

        for word in words {
            if current.isEmpty {
                current = word
            } else if current.count + word.count + 1 <= maxCharacters {
                current += " \(word)"
            } else {
                parts.append(current)
                current = word
            }
        }

        if !current.isEmpty {
            parts.append(current)
        }
        return parts.isEmpty ? [unit] : parts
    }
}

struct KnowledgeService: Sendable {
    private let storage: JSONKnowledgeStorageService
    private let chunker: KnowledgeTextChunker
    private let now: @Sendable () -> Date

    init(
        storage: JSONKnowledgeStorageService = JSONKnowledgeStorageService(),
        chunker: KnowledgeTextChunker = KnowledgeTextChunker(),
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.storage = storage
        self.chunker = chunker
        self.now = now
    }

    func loadCollections() async throws -> [KnowledgeCollection] {
        let snapshot = try await storage.load()
        return snapshot.collections.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    func loadDocuments(collectionID: UUID) async throws -> [KnowledgeDocument] {
        let snapshot = try await storage.load()
        guard snapshot.collections.contains(where: { $0.id == collectionID }) else {
            throw KnowledgeError.collectionNotFound
        }

        return snapshot.documents
            .filter { $0.collectionID == collectionID }
            .sorted { lhs, rhs in
                if lhs.updatedAt == rhs.updatedAt {
                    return lhs.fileName.localizedCaseInsensitiveCompare(rhs.fileName) == .orderedAscending
                }
                return lhs.updatedAt > rhs.updatedAt
            }
    }

    func loadDocumentDetail(id documentID: UUID) async throws -> KnowledgeDocumentDetail {
        let snapshot = try await storage.load()
        guard let document = snapshot.documents.first(where: { $0.id == documentID }) else {
            throw KnowledgeError.documentNotFound
        }
        guard let collection = snapshot.collections.first(where: { $0.id == document.collectionID }) else {
            throw KnowledgeError.collectionNotFound
        }

        let chunks = snapshot.chunks
            .filter { $0.documentID == documentID }
            .sorted { $0.index < $1.index }
        return KnowledgeDocumentDetail(collection: collection, document: document, chunks: chunks)
    }

    func createCollection(
        named name: String,
        allowedUserIDs: [String] = [],
        allowedGroupIDs: [String] = []
    ) async throws -> KnowledgeCollection {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            throw KnowledgeError.emptyCollectionName
        }

        var snapshot = try await storage.load()
        let slug = KnowledgeCollection.slug(for: trimmedName)
        if let existing = snapshot.collections.first(where: { $0.slug == slug }) {
            return existing
        }

        let collection = KnowledgeCollection(
            name: trimmedName,
            slug: slug,
            allowedUserIDs: allowedUserIDs,
            allowedGroupIDs: allowedGroupIDs,
            createdAt: now(),
            updatedAt: now()
        )
        snapshot.collections.append(collection)
        snapshot.collections.sort {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
        try await storage.save(snapshot)
        return collection
    }

    func updateCollection(
        id collectionID: UUID,
        name: String,
        allowedUserIDs: [String]? = nil,
        allowedGroupIDs: [String]? = nil
    ) async throws -> KnowledgeCollection {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            throw KnowledgeError.emptyCollectionName
        }

        var snapshot = try await storage.load()
        guard let index = snapshot.collections.firstIndex(where: { $0.id == collectionID }) else {
            throw KnowledgeError.collectionNotFound
        }

        let slug = KnowledgeCollection.slug(for: trimmedName)
        if let existing = snapshot.collections.first(where: { $0.id != collectionID && $0.slug == slug }) {
            return existing
        }

        snapshot.collections[index].name = trimmedName
        snapshot.collections[index].slug = slug
        if let allowedUserIDs {
            snapshot.collections[index].allowedUserIDs = KnowledgeCollection.normalizedAccessIDs(allowedUserIDs)
        }
        if let allowedGroupIDs {
            snapshot.collections[index].allowedGroupIDs = KnowledgeCollection.normalizedAccessIDs(allowedGroupIDs)
        }
        snapshot.collections[index].updatedAt = now()
        snapshot.collections.sort {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
        try await storage.save(snapshot)
        return snapshot.collections.first { $0.id == collectionID } ?? snapshot.collections[index]
    }

    func updateDocument(id documentID: UUID, fileName: String) async throws -> KnowledgeDocument {
        let trimmedFileName = fileName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedFileName.isEmpty else {
            throw KnowledgeError.emptyDocumentName
        }

        var snapshot = try await storage.load()
        guard let documentIndex = snapshot.documents.firstIndex(where: { $0.id == documentID }) else {
            throw KnowledgeError.documentNotFound
        }

        let updatedAt = now()
        snapshot.documents[documentIndex].fileName = trimmedFileName
        snapshot.documents[documentIndex].updatedAt = updatedAt
        for index in snapshot.chunks.indices where snapshot.chunks[index].documentID == documentID {
            snapshot.chunks[index].sourceName = trimmedFileName
        }
        if let collectionIndex = snapshot.collections.firstIndex(where: { $0.id == snapshot.documents[documentIndex].collectionID }) {
            snapshot.collections[collectionIndex].updatedAt = updatedAt
        }
        try await storage.save(snapshot)
        return snapshot.documents[documentIndex]
    }

    func importTextDocument(
        collectionID: UUID,
        fileName: String,
        contentType: String,
        text: String,
        embeddingModel: String,
        provider: any ChatProvider
    ) async throws {
        try await upsertTextDocument(
            collectionID: collectionID,
            fileName: fileName,
            contentType: contentType,
            text: text,
            embeddingModel: embeddingModel,
            provider: provider,
            requireExistingDocument: false
        )
    }

    func reindexTextDocument(
        collectionID: UUID,
        fileName: String,
        contentType: String,
        text: String,
        embeddingModel: String,
        provider: any ChatProvider
    ) async throws {
        try await upsertTextDocument(
            collectionID: collectionID,
            fileName: fileName,
            contentType: contentType,
            text: text,
            embeddingModel: embeddingModel,
            provider: provider,
            requireExistingDocument: true
        )
    }

    func exportKnowledgeJSONData() async throws -> Data {
        let snapshot = try await storage.load()
        let bundle = KnowledgeExportBundle(exportedAt: now(), snapshot: snapshot)
        return try JSONEncoder.openWebUIEncoder.encode(bundle)
    }

    func exportCollectionJSONData(id collectionID: UUID) async throws -> Data {
        let snapshot = try await storage.load()
        guard let collection = snapshot.collections.first(where: { $0.id == collectionID }) else {
            throw KnowledgeError.collectionNotFound
        }

        let documents = snapshot.documents.filter { $0.collectionID == collectionID }
        let documentIDs = Set(documents.map(\.id))
        let chunks = snapshot.chunks.filter {
            $0.collectionID == collectionID && documentIDs.contains($0.documentID)
        }
        let bundle = KnowledgeExportBundle(
            exportedAt: now(),
            snapshot: KnowledgeSnapshot(collections: [collection], documents: documents, chunks: chunks)
        )
        return try JSONEncoder.openWebUIEncoder.encode(bundle)
    }

    func importKnowledgeJSONData(_ data: Data) async throws {
        let importedSnapshot = try KnowledgeExportBundle.snapshot(fromJSONData: data)
        let currentSnapshot = try await storage.load()
        try await storage.save(mergedSnapshot(currentSnapshot, importing: importedSnapshot))
    }

    func loadSnapshot() async throws -> KnowledgeSnapshot {
        try await storage.load()
    }

    func replaceSnapshot(_ snapshot: KnowledgeSnapshot) async throws {
        try await storage.save(snapshot)
    }

    func deleteCollection(id collectionID: UUID) async throws {
        var snapshot = try await storage.load()
        guard snapshot.collections.contains(where: { $0.id == collectionID }) else {
            throw KnowledgeError.collectionNotFound
        }

        snapshot.collections.removeAll { $0.id == collectionID }
        snapshot.documents.removeAll { $0.collectionID == collectionID }
        snapshot.chunks.removeAll { $0.collectionID == collectionID }
        try await storage.save(snapshot)
    }

    func deleteDocument(id documentID: UUID) async throws {
        var snapshot = try await storage.load()
        guard let document = snapshot.documents.first(where: { $0.id == documentID }) else {
            throw KnowledgeError.documentNotFound
        }

        snapshot.documents.removeAll { $0.id == documentID }
        snapshot.chunks.removeAll { $0.documentID == documentID }
        if let collectionIndex = snapshot.collections.firstIndex(where: { $0.id == document.collectionID }) {
            snapshot.collections[collectionIndex].updatedAt = now()
        }
        try await storage.save(snapshot)
    }

    private func upsertTextDocument(
        collectionID: UUID,
        fileName: String,
        contentType: String,
        text: String,
        embeddingModel: String,
        provider: any ChatProvider,
        requireExistingDocument: Bool
    ) async throws {
        var snapshot = try await storage.load()
        guard let collectionIndex = snapshot.collections.firstIndex(where: { $0.id == collectionID }) else {
            throw KnowledgeError.collectionNotFound
        }

        let existingDocumentIndex = snapshot.documents.firstIndex {
            $0.collectionID == collectionID && $0.fileName == fileName
        }
        if requireExistingDocument && existingDocumentIndex == nil {
            throw KnowledgeError.documentNotFound
        }

        let indexedAt = now()
        let document: KnowledgeDocument
        if let existingDocumentIndex {
            var existingDocument = snapshot.documents[existingDocumentIndex]
            existingDocument.contentType = contentType
            existingDocument.byteCount = Data(text.utf8).count
            existingDocument.updatedAt = indexedAt
            snapshot.documents[existingDocumentIndex] = existingDocument
            document = existingDocument
        } else {
            document = KnowledgeDocument(
                collectionID: collectionID,
                fileName: fileName,
                contentType: contentType,
                byteCount: Data(text.utf8).count,
                createdAt: indexedAt,
                updatedAt: indexedAt
            )
            snapshot.documents.append(document)
        }

        var chunks = chunker.chunks(
            for: text,
            collectionID: collectionID,
            documentID: document.id,
            sourceName: fileName
        )
        let embeddings = try await provider.createEmbeddings(model: embeddingModel, input: chunks.map(\.text))
        for index in chunks.indices {
            chunks[index].embedding = index < embeddings.count ? embeddings[index] : []
        }

        snapshot.chunks.removeAll {
            $0.collectionID == collectionID && ($0.documentID == document.id || $0.sourceName == fileName)
        }
        snapshot.chunks.append(contentsOf: chunks)
        snapshot.collections[collectionIndex].updatedAt = indexedAt
        try await storage.save(snapshot)
    }

    func retrieve(
        collectionID: UUID,
        query: String,
        embeddingModel: String,
        provider: any ChatProvider,
        limit: Int = 4
    ) async throws -> [RetrievedKnowledgeChunk] {
        let snapshot = try await storage.load()
        guard let collection = snapshot.collections.first(where: { $0.id == collectionID }) else {
            throw KnowledgeError.collectionNotFound
        }

        let queryEmbeddings = try await provider.createEmbeddings(model: embeddingModel, input: [query])
        let queryEmbedding = queryEmbeddings.first ?? []
        guard !queryEmbedding.isEmpty else {
            return []
        }

        let documentsByID = Dictionary(uniqueKeysWithValues: snapshot.documents.map { ($0.id, $0) })

        return snapshot.chunks
            .filter { $0.collectionID == collectionID && !$0.embedding.isEmpty }
            .map { chunk in
                RetrievedKnowledgeChunk(
                    collection: collection,
                    document: documentsByID[chunk.documentID],
                    chunk: chunk,
                    score: cosineSimilarity(queryEmbedding, chunk.embedding)
                )
            }
            .sorted { $0.score > $1.score }
            .prefix(limit)
            .map { $0 }
    }

    func collection(matchingMention mention: String) async throws -> KnowledgeCollection? {
        let slug = KnowledgeCollection.slug(for: mention)
        let snapshot = try await storage.load()
        return snapshot.collections.first { $0.slug == slug }
    }

    private func cosineSimilarity(_ lhs: [Double], _ rhs: [Double]) -> Double {
        let count = min(lhs.count, rhs.count)
        guard count > 0 else {
            return 0
        }

        let dot = (0..<count).reduce(0) { $0 + lhs[$1] * rhs[$1] }
        let lhsMagnitude = sqrt(lhs.prefix(count).reduce(0) { $0 + $1 * $1 })
        let rhsMagnitude = sqrt(rhs.prefix(count).reduce(0) { $0 + $1 * $1 })

        guard lhsMagnitude > 0, rhsMagnitude > 0 else {
            return 0
        }
        return dot / (lhsMagnitude * rhsMagnitude)
    }

    private func mergedSnapshot(_ current: KnowledgeSnapshot, importing imported: KnowledgeSnapshot) -> KnowledgeSnapshot {
        let importedCollectionIDs = Set(imported.collections.map(\.id))
        let importedDocumentIDs = Set(imported.documents.map(\.id))
        let importedChunkIDs = Set(imported.chunks.map(\.id))

        var collections = current.collections
            .filter { !importedCollectionIDs.contains($0.id) }
        collections.append(contentsOf: imported.collections)
        collections.sort {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }

        let validCollectionIDs = Set(collections.map(\.id))
        var documents = current.documents
            .filter { !importedDocumentIDs.contains($0.id) }
            .filter { !importedCollectionIDs.contains($0.collectionID) }
        documents.append(contentsOf: imported.documents)
        documents = documents.filter { validCollectionIDs.contains($0.collectionID) }

        let validDocumentIDs = Set(documents.map(\.id))
        var chunks = current.chunks
            .filter { !importedChunkIDs.contains($0.id) }
            .filter { !importedDocumentIDs.contains($0.documentID) }
            .filter { !importedCollectionIDs.contains($0.collectionID) }
        chunks.append(contentsOf: imported.chunks)
        chunks = chunks.filter {
            validCollectionIDs.contains($0.collectionID) && validDocumentIDs.contains($0.documentID)
        }

        return KnowledgeSnapshot(collections: collections, documents: documents, chunks: chunks)
    }
}

enum KnowledgeError: Error, LocalizedError, Equatable {
    case emptyCollectionName
    case emptyDocumentName
    case collectionNotFound
    case documentNotFound

    var errorDescription: String? {
        switch self {
        case .emptyCollectionName:
            return "Name the knowledge collection before saving."
        case .emptyDocumentName:
            return "Name the knowledge document before saving."
        case .collectionNotFound:
            return "The selected knowledge collection could not be found."
        case .documentNotFound:
            return "The selected knowledge document could not be found. Import it before reindexing."
        }
    }
}

private struct KnowledgeExportBundle: Codable {
    var format: String = "open-webui-native-knowledge"
    var version: Int = 1
    var exportedAt: Date
    var snapshot: KnowledgeSnapshot

    static func snapshot(fromJSONData data: Data) throws -> KnowledgeSnapshot {
        let decoder = JSONDecoder.openWebUIDecoder
        if let bundle = try? decoder.decode(KnowledgeExportBundle.self, from: data) {
            return bundle.snapshot
        }
        return try decoder.decode(KnowledgeSnapshot.self, from: data)
    }
}
