import Foundation

struct ChatExportService {
    func markdown(for thread: ChatThread) -> String {
        var lines: [String] = []
        lines.append("# \(thread.title)")
        lines.append("")

        if !thread.modelIDs.isEmpty {
            lines.append("Models: \(thread.modelIDs.joined(separator: ", "))")
            lines.append("")
        }

        for message in thread.messages {
            lines.append("## \(heading(for: message.role))")
            if let modelID = message.modelID {
                lines.append("")
                lines.append("Model: \(modelID)")
            }
            if let rating = message.rating {
                lines.append("")
                lines.append("Rating: \(rating.label)")
            }
            lines.append("")
            lines.append(message.content)
            if !message.attachments.isEmpty {
                lines.append("")
                lines.append("Attachments:")
                for attachment in message.attachments {
                    let size = ByteCountFormatter.string(fromByteCount: Int64(attachment.byteCount), countStyle: .file)
                    lines.append("- \(attachment.fileName) (\(attachment.contentType), \(size))")
                    if let textContent = attachment.textContent, !textContent.isEmpty {
                        lines.append("")
                        lines.append("```")
                        lines.append(textContent)
                        lines.append("```")
                    }
                }
            }
            if !message.citations.isEmpty {
                lines.append("")
                lines.append("Citations:")
                for citation in message.citations {
                    lines.append("- #\(citation.collectionSlug) / \(citation.sourceName)")
                    lines.append("")
                    lines.append("```")
                    lines.append(citation.text)
                    lines.append("```")
                }
            }
            lines.append("")
        }

        return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines) + "\n"
    }

    func jsonData(for thread: ChatThread) throws -> Data {
        try JSONEncoder.openWebUIEncoder.encode(thread)
    }

    func openWebUIJSONData(for thread: ChatThread) throws -> Data {
        try openWebUIJSONData(for: [thread])
    }

    func openWebUIJSONData(for threads: [ChatThread]) throws -> Data {
        let envelope = OpenWebUIChatExportEnvelope(chats: threads.map(OpenWebUIChatExportRecord.init(thread:)))
        return try JSONEncoder.openWebUIEncoder.encode(envelope)
    }

    func thread(fromJSONData data: Data) throws -> ChatThread {
        do {
            return try JSONDecoder.openWebUIDecoder.decode(ChatThread.self, from: data)
        } catch {
            return try JSONDecoder.openWebUIDecoder.decode(OpenWebUIChatRecord.self, from: data).thread
        }
    }

    func threads(fromJSONData data: Data) throws -> [ChatThread] {
        do {
            return try JSONDecoder.openWebUIDecoder.decode([ChatThread].self, from: data)
        } catch {
            do {
                return try JSONDecoder.openWebUIDecoder.decode([OpenWebUIChatRecord].self, from: data).map(\.thread)
            } catch {
                return try JSONDecoder.openWebUIDecoder.decode(OpenWebUIChatsEnvelope.self, from: data).chats.map(\.thread)
            }
        }
    }

    private func heading(for role: ChatRole) -> String {
        switch role {
        case .user:
            return "User"
        case .assistant:
            return "Assistant"
        case .system:
            return "System"
        }
    }
}

private struct OpenWebUIChatExportEnvelope: Encodable {
    var chats: [OpenWebUIChatExportRecord]
}

private struct OpenWebUIChatExportRecord: Encodable {
    var chat: OpenWebUIChatExportBody
    var folderID: String?
    var meta: OpenWebUIChatExportMeta
    var pinned: Bool
    var createdAt: Int
    var updatedAt: Int

    enum CodingKeys: String, CodingKey {
        case chat
        case folderID = "folder_id"
        case meta
        case pinned
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    init(thread: ChatThread) {
        chat = OpenWebUIChatExportBody(thread: thread)
        folderID = thread.folderID?.uuidString
        meta = OpenWebUIChatExportMeta(tags: thread.tags)
        pinned = thread.isPinned
        createdAt = Int(thread.createdAt.timeIntervalSince1970)
        updatedAt = Int(thread.updatedAt.timeIntervalSince1970)
    }
}

private struct OpenWebUIChatExportMeta: Encodable {
    var tags: [String]
}

private struct OpenWebUIChatExportBody: Encodable {
    var title: String
    var models: [String]
    var history: OpenWebUIChatExportHistory

    init(thread: ChatThread) {
        title = thread.title
        models = thread.modelIDs
        history = OpenWebUIChatExportHistory(messages: thread.messages)
    }
}

private struct OpenWebUIChatExportHistory: Encodable {
    var messages: [String: OpenWebUIChatExportMessage]
    var currentID: String?

    enum CodingKeys: String, CodingKey {
        case messages
        case currentID = "currentId"
    }

    init(messages chatMessages: [ChatMessage]) {
        var exportMessages: [String: OpenWebUIChatExportMessage] = [:]
        for index in chatMessages.indices {
            let message = chatMessages[index]
            exportMessages[message.id.uuidString] = OpenWebUIChatExportMessage(
                message: message,
                parentID: index > chatMessages.startIndex ? chatMessages[chatMessages.index(before: index)].id.uuidString : nil,
                childrenIDs: index < chatMessages.index(before: chatMessages.endIndex)
                    ? [chatMessages[chatMessages.index(after: index)].id.uuidString]
                    : []
            )
        }
        messages = exportMessages
        currentID = chatMessages.last?.id.uuidString
    }
}

private struct OpenWebUIChatExportMessage: Encodable {
    var id: String
    var parentID: String?
    var childrenIDs: [String]
    var role: String
    var content: String
    var model: String?
    var timestamp: Int
    var annotation: OpenWebUIChatExportAnnotation?

    enum CodingKeys: String, CodingKey {
        case id
        case parentID = "parentId"
        case childrenIDs = "childrenIds"
        case role
        case content
        case model
        case timestamp
        case annotation
    }

    init(message: ChatMessage, parentID: String?, childrenIDs: [String]) {
        id = message.id.uuidString
        self.parentID = parentID
        self.childrenIDs = childrenIDs
        role = message.role.rawValue
        content = message.content
        model = message.modelID
        timestamp = Int(message.createdAt.timeIntervalSince1970)
        annotation = message.rating.map(OpenWebUIChatExportAnnotation.init(rating:))
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        if let parentID {
            try container.encode(parentID, forKey: .parentID)
        } else {
            try container.encodeNil(forKey: .parentID)
        }
        try container.encode(childrenIDs, forKey: .childrenIDs)
        try container.encode(role, forKey: .role)
        try container.encode(content, forKey: .content)
        try container.encodeIfPresent(model, forKey: .model)
        try container.encode(timestamp, forKey: .timestamp)
        try container.encodeIfPresent(annotation, forKey: .annotation)
    }
}

private struct OpenWebUIChatExportAnnotation: Encodable {
    var rating: Int

    init(rating: MessageRating) {
        switch rating {
        case .positive:
            self.rating = 1
        case .negative:
            self.rating = -1
        }
    }
}

private struct OpenWebUIChatsEnvelope: Decodable {
    var chats: [OpenWebUIChatRecord]
}

private struct OpenWebUIChatRecord: Decodable {
    var id: String?
    var userID: String?
    var title: String?
    var chat: OpenWebUIChatBody
    var createdAt: Double?
    var updatedAt: Double?
    var archived: Bool?
    var pinned: Bool?
    var meta: OpenWebUIChatMeta?
    var folderID: String?

    enum CodingKeys: String, CodingKey {
        case id
        case userID = "user_id"
        case title
        case chat
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case archived
        case pinned
        case meta
        case folderID = "folder_id"
    }

    var thread: ChatThread {
        let messages = chat.activeMessages.map(\.chatMessage)
        let modelIDs = chat.models.isEmpty
            ? uniqueModelIDs(from: messages)
            : chat.models
        return ChatThread(
            id: id.flatMap(UUID.init(uuidString:)) ?? UUID(),
            title: title ?? "Imported Chat",
            userID: userID ?? "local-user",
            createdAt: Date(timeIntervalSince1970: createdAt ?? Date().timeIntervalSince1970),
            updatedAt: Date(timeIntervalSince1970: updatedAt ?? createdAt ?? Date().timeIntervalSince1970),
            folderID: folderID.flatMap(UUID.init(uuidString:)),
            modelIDs: modelIDs,
            tags: meta?.tags ?? [],
            isPinned: pinned ?? false,
            isArchived: archived ?? false,
            messages: messages
        )
    }

    private func uniqueModelIDs(from messages: [ChatMessage]) -> [String] {
        var seen: Set<String> = []
        var models: [String] = []
        for message in messages {
            guard let modelID = message.modelID, seen.insert(modelID).inserted else {
                continue
            }
            models.append(modelID)
        }
        return models
    }
}

private struct OpenWebUIChatMeta: Decodable {
    var tags: [String]

    enum CodingKeys: String, CodingKey {
        case tags
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        tags = try container.decodeIfPresent([String].self, forKey: .tags) ?? []
    }
}

private struct OpenWebUIChatBody: Decodable {
    var models: [String]
    var history: OpenWebUIChatHistory?

    enum CodingKeys: String, CodingKey {
        case models
        case history
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        models = try container.decodeIfPresent([String].self, forKey: .models) ?? []
        history = try container.decodeIfPresent(OpenWebUIChatHistory.self, forKey: .history)
    }

    var activeMessages: [OpenWebUIChatMessage] {
        guard let history else {
            return []
        }
        return history.activeMessages
    }
}

private struct OpenWebUIChatHistory: Decodable {
    var messages: [String: OpenWebUIChatMessage]
    var currentID: String?

    enum CodingKeys: String, CodingKey {
        case messages
        case currentID = "currentId"
    }

    var activeMessages: [OpenWebUIChatMessage] {
        guard let currentID,
              messages[currentID] != nil else {
            return messages.values.sortedByTimestamp()
        }

        var path: [OpenWebUIChatMessage] = []
        var visited: Set<String> = []
        var currentMessage = messages[currentID]

        while let message = currentMessage {
            let messageID = message.id
            if let messageID {
                guard visited.insert(messageID).inserted else {
                    break
                }
            }
            path.append(message)

            guard let parentID = message.parentID else {
                break
            }
            currentMessage = messages[parentID]
        }

        return path.reversed()
    }
}

private struct OpenWebUIChatMessage: Decodable {
    var id: String?
    var parentID: String?
    var role: ChatRole?
    var content: JSONValue?
    var model: String?
    var timestamp: Double?
    var annotation: OpenWebUIMessageAnnotation?

    enum CodingKeys: String, CodingKey {
        case id
        case parentID = "parentId"
        case role
        case content
        case model
        case timestamp
        case annotation
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id)
        parentID = try container.decodeIfPresent(String.self, forKey: .parentID)
        role = try container.decodeIfPresent(ChatRole.self, forKey: .role)
        content = try container.decodeIfPresent(JSONValue.self, forKey: .content)
        model = try container.decodeIfPresent(String.self, forKey: .model)
        timestamp = try container.decodeIfPresent(Double.self, forKey: .timestamp)
        annotation = try container.decodeIfPresent(OpenWebUIMessageAnnotation.self, forKey: .annotation)
    }

    var chatMessage: ChatMessage {
        ChatMessage(
            id: id.flatMap(UUID.init(uuidString:)) ?? UUID(),
            role: role ?? .user,
            content: content?.messageText ?? "",
            modelID: model,
            createdAt: Date(timeIntervalSince1970: timestamp ?? Date().timeIntervalSince1970),
            rating: annotation?.messageRating
        )
    }
}

private struct OpenWebUIMessageAnnotation: Decodable {
    var rating: Int?

    var messageRating: MessageRating? {
        switch rating {
        case 1:
            return .positive
        case -1:
            return .negative
        default:
            return nil
        }
    }
}

private extension JSONValue {
    var messageText: String {
        switch self {
        case .string(let value):
            return value
        case .array(let values):
            return values.compactMap(\.messageTextComponent).joined(separator: "\n")
        case .null:
            return ""
        default:
            return jsonString
        }
    }

    var messageTextComponent: String? {
        guard case .object(let object) = self else {
            return messageText
        }
        if case .string("text") = object["type"],
           case .string(let text) = object["text"] {
            return text
        }
        return nil
    }
}

private extension Collection where Element == OpenWebUIChatMessage {
    func sortedByTimestamp() -> [OpenWebUIChatMessage] {
        sorted { lhs, rhs in
            (lhs.timestamp ?? 0, lhs.id ?? "") < (rhs.timestamp ?? 0, rhs.id ?? "")
        }
    }
}

extension JSONEncoder {
    static var openWebUIEncoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

extension JSONDecoder {
    static var openWebUIDecoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
