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

        return threads
            .flatMap { thread in
                thread.messages.compactMap { message in
                    guard message.content.range(of: normalizedQuery, options: [.caseInsensitive, .diacriticInsensitive]) != nil else {
                        return nil
                    }
                    return ChatSearchResult(
                        threadID: thread.id,
                        messageID: message.id,
                        threadTitle: thread.title,
                        role: message.role,
                        snippet: snippet(for: message.content, query: normalizedQuery),
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

    private func snippet(for content: String, query: String) -> String {
        let trimmedContent = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedContent.count > 120,
              let matchRange = trimmedContent.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) else {
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
