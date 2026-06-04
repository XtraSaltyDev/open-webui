import Foundation

struct ChatSearchResult: Identifiable, Equatable, Sendable {
    var id: UUID { messageID }
    let threadID: UUID
    let messageID: UUID
    let threadTitle: String
    let role: ChatRole
    let snippet: String
    let createdAt: Date
}

struct ChatSearchService: Sendable {
    func search(_ query: String, in threads: [ChatThread]) -> [ChatSearchResult] {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedQuery.isEmpty else {
            return []
        }
        let terms = searchTerms(in: normalizedQuery)

        return threads
            .flatMap { thread in
                thread.messages.compactMap { message in
                    let document = indexedDocument(for: message, in: thread)
                    guard terms.allSatisfy({ document.indexText.localizedStandardContains($0) }) else {
                        return nil
                    }
                    return ChatSearchResult(
                        threadID: thread.id,
                        messageID: message.id,
                        threadTitle: thread.title,
                        role: message.role,
                        snippet: snippet(for: document.snippetText, query: normalizedQuery, terms: terms),
                        createdAt: message.createdAt
                    )
                }
            }
            .sorted {
                if $0.createdAt == $1.createdAt {
                    return $0.threadTitle.localizedStandardCompare($1.threadTitle) == .orderedAscending
                }
                return $0.createdAt > $1.createdAt
            }
    }

    private func searchTerms(in query: String) -> [String] {
        query
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)
            .filter { !$0.isEmpty }
    }

    private func indexedDocument(for message: ChatMessage, in thread: ChatThread) -> ChatSearchDocument {
        let attachmentText = message.attachments
            .map { attachment in
                [
                    attachment.fileName,
                    attachment.contentType,
                    attachment.textContent ?? ""
                ].joined(separator: " ")
            }
            .joined(separator: "\n")
        let citationText = message.citations
            .map { citation in
                [
                    citation.collectionName,
                    citation.collectionSlug,
                    citation.sourceName,
                    citation.text
                ].joined(separator: " ")
            }
            .joined(separator: "\n")
        let indexText = [
            thread.title,
            thread.tags.joined(separator: " "),
            message.role.rawValue,
            message.modelID ?? "",
            message.content,
            attachmentText,
            citationText
        ]
        .joined(separator: "\n")
        let snippetText = [
            message.content,
            attachmentText,
            citationText
        ]
        .joined(separator: "\n")
        return ChatSearchDocument(indexText: indexText, snippetText: snippetText)
    }

    private func snippet(for content: String, query: String, terms: [String]) -> String {
        let trimmedContent = content.trimmingCharacters(in: .whitespacesAndNewlines)
        let matchRange = trimmedContent.range(of: query, options: [.caseInsensitive, .diacriticInsensitive])
            ?? terms.lazy.compactMap { term in
                trimmedContent.range(of: term, options: [.caseInsensitive, .diacriticInsensitive])
            }.first
        guard trimmedContent.count > 120,
              let matchRange else {
            return trimmedContent
        }

        let contextBefore = 48
        let contextAfter = 72
        let start = trimmedContent.index(
            matchRange.lowerBound,
            offsetBy: -contextBefore,
            limitedBy: trimmedContent.startIndex
        ) ?? trimmedContent.startIndex
        let end = trimmedContent.index(
            matchRange.upperBound,
            offsetBy: contextAfter,
            limitedBy: trimmedContent.endIndex
        ) ?? trimmedContent.endIndex
        var snippet = String(trimmedContent[start..<end]).trimmingCharacters(in: .whitespacesAndNewlines)
        if start > trimmedContent.startIndex {
            snippet = "..." + snippet
        }
        if end < trimmedContent.endIndex {
            snippet += "..."
        }
        return snippet
    }
}

private struct ChatSearchDocument {
    var indexText: String
    var snippetText: String
}
