import Foundation

struct KnowledgeCollection: Identifiable, Codable, Equatable, Sendable {
    var id: UUID
    var name: String
    var slug: String
    var allowedUserIDs: [String]
    var allowedGroupIDs: [String]
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        slug: String? = nil,
        allowedUserIDs: [String] = [],
        allowedGroupIDs: [String] = [],
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.slug = slug ?? KnowledgeCollection.slug(for: name)
        self.allowedUserIDs = KnowledgeCollection.normalizedAccessIDs(allowedUserIDs)
        self.allowedGroupIDs = KnowledgeCollection.normalizedAccessIDs(allowedGroupIDs)
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case slug
        case allowedUserIDs
        case allowedGroupIDs
        case createdAt
        case updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let name = try container.decode(String.self, forKey: .name)
        self.init(
            id: try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID(),
            name: name,
            slug: try container.decodeIfPresent(String.self, forKey: .slug),
            allowedUserIDs: try container.decodeIfPresent([String].self, forKey: .allowedUserIDs) ?? [],
            allowedGroupIDs: try container.decodeIfPresent([String].self, forKey: .allowedGroupIDs) ?? [],
            createdAt: try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date(),
            updatedAt: try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? Date()
        )
    }

    static func slug(for name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .trimmingCharacters(in: CharacterSet(charactersIn: "#"))
            .split(whereSeparator: { $0.isWhitespace || $0 == "_" })
            .joined(separator: "-")
    }

    static func normalizedAccessIDs(_ ids: [String]) -> [String] {
        Array(Set(ids.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }))
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }
}

struct KnowledgeDocument: Identifiable, Codable, Equatable, Sendable {
    var id: UUID
    var collectionID: UUID
    var fileName: String
    var contentType: String
    var byteCount: Int
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        collectionID: UUID,
        fileName: String,
        contentType: String,
        byteCount: Int,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.collectionID = collectionID
        self.fileName = fileName
        self.contentType = contentType
        self.byteCount = byteCount
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

struct KnowledgeChunk: Identifiable, Codable, Equatable, Sendable {
    var id: UUID
    var collectionID: UUID
    var documentID: UUID
    var sourceName: String
    var index: Int
    var text: String
    var embedding: [Double]
    var createdAt: Date

    init(
        id: UUID = UUID(),
        collectionID: UUID,
        documentID: UUID,
        sourceName: String,
        index: Int,
        text: String,
        embedding: [Double] = [],
        createdAt: Date = Date()
    ) {
        self.id = id
        self.collectionID = collectionID
        self.documentID = documentID
        self.sourceName = sourceName
        self.index = index
        self.text = text
        self.embedding = embedding
        self.createdAt = createdAt
    }
}

struct KnowledgeSnapshot: Codable, Equatable, Sendable {
    var collections: [KnowledgeCollection]
    var documents: [KnowledgeDocument]
    var chunks: [KnowledgeChunk]

    init(
        collections: [KnowledgeCollection] = [],
        documents: [KnowledgeDocument] = [],
        chunks: [KnowledgeChunk] = []
    ) {
        self.collections = collections
        self.documents = documents
        self.chunks = chunks
    }
}

struct RetrievedKnowledgeChunk: Equatable, Sendable {
    var collection: KnowledgeCollection
    var document: KnowledgeDocument?
    var chunk: KnowledgeChunk
    var score: Double

    var text: String {
        chunk.text
    }
}

struct KnowledgeDocumentDetail: Equatable, Sendable {
    var collection: KnowledgeCollection
    var document: KnowledgeDocument
    var chunks: [KnowledgeChunk]

    var previewText: String {
        chunks
            .sorted { $0.index < $1.index }
            .map(\.text)
            .joined(separator: "\n\n")
    }
}
