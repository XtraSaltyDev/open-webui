import Foundation

enum AuditEventFilter {
    static let clearSearchHelpText = "Clear audit search (Esc)"
    static let emptyResultText = "No audit events match this search. Press Esc to clear."

    static func filteredEvents(_ events: [AppAuditEvent], query: String) -> [AppAuditEvent] {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isQueryActive(trimmedQuery) else {
            return events
        }

        let normalizedQuery = trimmedQuery.localizedLowercase
        return events.filter { event in
            searchableText(for: event).localizedLowercase.contains(normalizedQuery)
        }
    }

    static func resultSummary(totalCount: Int, filteredCount: Int, query: String) -> String {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if !isQueryActive(trimmedQuery) {
            return countText(totalCount, singular: "event", plural: "events")
        }
        return countText(filteredCount, singular: "match", plural: "matches")
    }

    static func isQueryActive(_ query: String) -> Bool {
        !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    static func clearedQuery(from _: String) -> String {
        ""
    }

    private static func searchableText(for event: AppAuditEvent) -> String {
        let metadataText = AuditEventMetadataFormatter.rows(for: event)
            .flatMap { [$0.label, $0.value] }
            .joined(separator: " ")

        return [
            event.action.label,
            event.action.rawValue,
            event.outcome.label,
            event.outcome.rawValue,
            event.summary,
            metadataText
        ]
        .joined(separator: " ")
    }

    private static func countText(_ count: Int, singular: String, plural: String) -> String {
        "\(count) \(count == 1 ? singular : plural)"
    }
}
