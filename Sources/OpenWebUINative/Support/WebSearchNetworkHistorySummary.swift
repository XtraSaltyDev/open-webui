import Foundation

struct WebSearchNetworkHostSummary: Identifiable, Codable, Equatable, Sendable {
    var id: String { host }
    var host: String
    var runCount: Int
}

struct WebSearchNetworkHistorySummary: Codable, Equatable, Sendable {
    static let empty = WebSearchNetworkHistorySummary(events: [])

    var totalRuns: Int
    var succeededRuns: Int
    var failedRuns: Int
    var blockedRuns: Int
    var apiKeyRuns: Int
    var uniqueHostCount: Int
    var topHosts: [WebSearchNetworkHostSummary]
    var mostRecentRunAt: Date?

    var hasHistory: Bool {
        totalRuns > 0
    }

    init(events: [AppAuditEvent]) {
        let webSearchEvents = events.filter { $0.action == .webSearchRun }
        totalRuns = webSearchEvents.count
        succeededRuns = webSearchEvents.filter { $0.outcome == .succeeded }.count
        failedRuns = webSearchEvents.filter { $0.outcome == .failed }.count
        blockedRuns = webSearchEvents.filter { $0.outcome == .blocked }.count
        apiKeyRuns = webSearchEvents.filter { Self.boolValue($0.metadata["usedAPIKey"]) }.count
        mostRecentRunAt = webSearchEvents.map(\.createdAt).max()

        var hostCounts: [String: Int] = [:]
        for event in webSearchEvents {
            for host in Self.hosts(from: event.metadata["contactedHosts"]) {
                hostCounts[host, default: 0] += 1
            }
        }
        uniqueHostCount = hostCounts.count
        topHosts = hostCounts
            .map { WebSearchNetworkHostSummary(host: $0.key, runCount: $0.value) }
            .sorted { lhs, rhs in
                if lhs.runCount != rhs.runCount {
                    return lhs.runCount > rhs.runCount
                }
                return lhs.host.localizedStandardCompare(rhs.host) == .orderedAscending
            }
    }

    private static func boolValue(_ value: String?) -> Bool {
        value?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "true"
    }

    private static func hosts(from value: String?) -> [String] {
        let rawHosts = value?
            .split(separator: ",")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines).lowercased() } ?? []
        var seen: Set<String> = []
        var hosts: [String] = []
        for host in rawHosts {
            guard !host.isEmpty, host != "none", !seen.contains(host) else {
                continue
            }
            seen.insert(host)
            hosts.append(host)
        }
        return hosts
    }
}
