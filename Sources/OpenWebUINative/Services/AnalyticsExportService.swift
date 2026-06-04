import Foundation

struct AnalyticsExportBundle: Codable, Equatable, Sendable {
    var version: Int
    var exportedAt: Date
    var summary: AnalyticsSummary
    var webSearchNetworkSummary: WebSearchNetworkHistorySummary

    private enum CodingKeys: String, CodingKey {
        case version
        case exportedAt
        case summary
        case webSearchNetworkSummary
    }

    init(
        version: Int = 1,
        exportedAt: Date = Date(),
        summary: AnalyticsSummary,
        webSearchNetworkSummary: WebSearchNetworkHistorySummary = .empty
    ) {
        self.version = version
        self.exportedAt = exportedAt
        self.summary = summary
        self.webSearchNetworkSummary = webSearchNetworkSummary
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decode(Int.self, forKey: .version)
        exportedAt = try container.decode(Date.self, forKey: .exportedAt)
        summary = try container.decode(AnalyticsSummary.self, forKey: .summary)
        webSearchNetworkSummary = try container.decodeIfPresent(
            WebSearchNetworkHistorySummary.self,
            forKey: .webSearchNetworkSummary
        ) ?? .empty
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(version, forKey: .version)
        try container.encode(exportedAt, forKey: .exportedAt)
        try container.encode(summary, forKey: .summary)
        try container.encode(webSearchNetworkSummary, forKey: .webSearchNetworkSummary)
    }
}

struct AnalyticsExportService: Sendable {
    func jsonData(
        for summary: AnalyticsSummary,
        webSearchNetworkSummary: WebSearchNetworkHistorySummary = .empty,
        exportedAt: Date = Date()
    ) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(
            AnalyticsExportBundle(
                exportedAt: exportedAt,
                summary: summary,
                webSearchNetworkSummary: webSearchNetworkSummary
            )
        )
    }
}
