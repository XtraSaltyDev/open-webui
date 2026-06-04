import Foundation

struct KnowledgeDocumentMetadata: Codable, Equatable, Sendable {
    var mimeTypeHint: String
    var byteCount: Int
    var sourceKind: KnowledgeDocumentSourceKind
    var importedFileName: String
    var lastIndexedAt: Date

    init(
        mimeTypeHint: String,
        byteCount: Int,
        sourceKind: KnowledgeDocumentSourceKind,
        importedFileName: String,
        lastIndexedAt: Date
    ) {
        self.mimeTypeHint = mimeTypeHint
        self.byteCount = byteCount
        self.sourceKind = sourceKind
        self.importedFileName = importedFileName
        self.lastIndexedAt = lastIndexedAt
    }

    enum CodingKeys: String, CodingKey {
        case mimeTypeHint
        case byteCount
        case sourceKind
        case importedFileName
        case lastIndexedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            mimeTypeHint: try container.decodeIfPresent(String.self, forKey: .mimeTypeHint) ?? "",
            byteCount: try container.decodeIfPresent(Int.self, forKey: .byteCount) ?? 0,
            sourceKind: try container.decodeIfPresent(KnowledgeDocumentSourceKind.self, forKey: .sourceKind) ?? .unknown,
            importedFileName: try container.decodeIfPresent(String.self, forKey: .importedFileName) ?? "",
            lastIndexedAt: try container.decodeIfPresent(Date.self, forKey: .lastIndexedAt) ?? Date()
        )
    }

    static func inferred(
        fileName: String,
        contentType: String,
        byteCount: Int,
        lastIndexedAt: Date,
        sourceKind: KnowledgeDocumentSourceKind? = nil
    ) -> KnowledgeDocumentMetadata {
        KnowledgeDocumentMetadata(
            mimeTypeHint: contentType,
            byteCount: byteCount,
            sourceKind: sourceKind ?? KnowledgeDocumentSourceKind.inferred(from: contentType, fileName: fileName),
            importedFileName: fileName,
            lastIndexedAt: lastIndexedAt
        )
    }
}

enum KnowledgeDocumentSourceKind: String, Codable, Equatable, Sendable {
    case plainText = "plain-text"
    case markdown
    case pdf
    case nativeNote = "native-note"
    case unknown

    static func inferred(from contentType: String, fileName: String) -> KnowledgeDocumentSourceKind {
        let lowercasedContentType = contentType.lowercased()
        let pathExtension = URL(fileURLWithPath: fileName).pathExtension.lowercased()

        if lowercasedContentType == "application/pdf" || pathExtension == "pdf" {
            return .pdf
        }
        if lowercasedContentType == "text/markdown" || ["md", "markdown"].contains(pathExtension) {
            return .markdown
        }
        if lowercasedContentType.hasPrefix("text/") {
            return .plainText
        }
        return .unknown
    }

    var displayName: String {
        switch self {
        case .plainText:
            return "Plain text"
        case .markdown:
            return "Markdown"
        case .pdf:
            return "PDF"
        case .nativeNote:
            return "Native note"
        case .unknown:
            return "Unknown"
        }
    }
}

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
    var metadata: KnowledgeDocumentMetadata
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        collectionID: UUID,
        fileName: String,
        contentType: String,
        byteCount: Int,
        metadata: KnowledgeDocumentMetadata? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.collectionID = collectionID
        self.fileName = fileName
        self.contentType = contentType
        self.byteCount = byteCount
        self.metadata = metadata ?? KnowledgeDocumentMetadata.inferred(
            fileName: fileName,
            contentType: contentType,
            byteCount: byteCount,
            lastIndexedAt: updatedAt
        )
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    enum CodingKeys: String, CodingKey {
        case id
        case collectionID
        case fileName
        case contentType
        case byteCount
        case metadata
        case createdAt
        case updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let fileName = try container.decode(String.self, forKey: .fileName)
        let contentType = try container.decode(String.self, forKey: .contentType)
        let byteCount = try container.decode(Int.self, forKey: .byteCount)
        let updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? Date()
        let metadata = try container.decodeIfPresent(KnowledgeDocumentMetadata.self, forKey: .metadata)
        self.init(
            id: try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID(),
            collectionID: try container.decode(UUID.self, forKey: .collectionID),
            fileName: fileName,
            contentType: contentType,
            byteCount: byteCount,
            metadata: metadata.map {
                KnowledgeDocumentMetadata(
                    mimeTypeHint: $0.mimeTypeHint.isEmpty ? contentType : $0.mimeTypeHint,
                    byteCount: $0.byteCount,
                    sourceKind: $0.sourceKind == .unknown
                        ? KnowledgeDocumentSourceKind.inferred(from: contentType, fileName: fileName)
                        : $0.sourceKind,
                    importedFileName: $0.importedFileName.isEmpty ? fileName : $0.importedFileName,
                    lastIndexedAt: $0.lastIndexedAt
                )
            } ?? KnowledgeDocumentMetadata.inferred(
                fileName: fileName,
                contentType: contentType,
                byteCount: byteCount,
                lastIndexedAt: updatedAt
            ),
            createdAt: try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? updatedAt,
            updatedAt: updatedAt
        )
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
