import Foundation
import PDFKit

protocol WebSearching: Sendable {
    func search(query: String, settings: WebSearchSettings) async throws -> [WebSearchResult]
}

struct WebSearchResult: Equatable, Sendable {
    var title: String
    var url: URL
    var snippet: String
    var pageContent: String? = nil
}

enum WebSearchTelemetryStatus: String, Equatable, Sendable {
    case succeeded
    case failed
}

enum WebSearchServiceError: Error, LocalizedError, Equatable {
    case missingBraveAPIKey

    var errorDescription: String? {
        switch self {
        case .missingBraveAPIKey:
            return "Add a Brave Search API key before searching with Brave."
        }
    }
}

struct WebSearchTelemetry: Equatable, Sendable {
    var query: String
    var engine: WebSearchEngine
    var resultCount: Int
    var status: WebSearchTelemetryStatus
    var wasPageContentLoadingEnabled: Bool
    var pageContentResultCount: Int
    var errorMessage: String?
    var completedAt: Date
    var contactedHosts: [String]
    var usedAPIKey: Bool

    init(
        query: String,
        engine: WebSearchEngine,
        resultCount: Int,
        status: WebSearchTelemetryStatus = .succeeded,
        wasPageContentLoadingEnabled: Bool = false,
        pageContentResultCount: Int = 0,
        errorMessage: String? = nil,
        completedAt: Date,
        contactedHosts: [String] = [],
        usedAPIKey: Bool = false
    ) {
        self.query = query
        self.engine = engine
        self.resultCount = resultCount
        self.status = status
        self.wasPageContentLoadingEnabled = wasPageContentLoadingEnabled
        self.pageContentResultCount = pageContentResultCount
        self.errorMessage = errorMessage
        self.completedAt = completedAt
        self.contactedHosts = Self.normalizedHosts(contactedHosts)
        self.usedAPIKey = usedAPIKey
    }

    var statusSummary: String {
        switch status {
        case .succeeded:
            let resultLabel = resultCount == 1 ? "result" : "results"
            guard wasPageContentLoadingEnabled else {
                return "\(resultCount) \(engine.label) \(resultLabel)"
            }
            return "\(resultCount) \(engine.label) \(resultLabel), \(pageContentResultCount) with page text"
        case .failed:
            let message = errorMessage?.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let message, !message.isEmpty else {
                return "\(engine.label) search failed"
            }
            return "\(engine.label) search failed: \(message)"
        }
    }

    var networkSummary: String {
        let hostSummary = contactedHosts.isEmpty
            ? "No network hosts contacted"
            : "Hosts: \(contactedHosts.joined(separator: ", "))"
        let authSummary = usedAPIKey ? "API key used from Keychain" : "No API key"
        return "\(hostSummary); \(authSummary)"
    }

    private static func normalizedHosts(_ hosts: [String]) -> [String] {
        var seen: Set<String> = []
        var result: [String] = []
        for host in hosts {
            let normalized = host.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !normalized.isEmpty, !seen.contains(normalized) else {
                continue
            }
            seen.insert(normalized)
            result.append(normalized)
        }
        return result
    }
}

struct WebSearchService: WebSearching {
    typealias DataLoader = @Sendable (URLRequest) async throws -> (Data, URLResponse)

    private let secretStore: SecretStoring
    private let dataLoader: DataLoader

    init(
        secretStore: SecretStoring = KeychainSecretStore(),
        dataLoader: @escaping DataLoader = { request in
            try await WebSearchService.defaultDataLoader(request)
        }
    ) {
        self.secretStore = secretStore
        self.dataLoader = dataLoader
    }

    func search(query: String, settings: WebSearchSettings) async throws -> [WebSearchResult] {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else {
            return []
        }

        let results: [WebSearchResult]
        switch settings.engine {
        case .duckDuckGoHTML:
            results = try await searchDuckDuckGoHTML(query: trimmedQuery)
        case .searxng:
            results = try await searchSearXNG(query: trimmedQuery, baseURLString: settings.searxngBaseURL)
        case .brave:
            results = try await searchBrave(query: trimmedQuery, settings: settings)
        }

        let filteredResults = Array(results
            .filter { matchesDomainFilter($0.url, filters: settings.domainFilterList) }
            .prefix(max(settings.resultCount, 1)))

        guard settings.isPageContentLoadingEnabled else {
            return filteredResults
        }

        var enrichedResults: [WebSearchResult] = []
        for result in filteredResults {
            var enrichedResult = result
            enrichedResult.pageContent = try? await loadPageContent(
                from: result.url,
                maxCharacters: max(settings.maxPageContentCharacters, 1)
            )
            enrichedResults.append(enrichedResult)
        }
        return enrichedResults
    }

    private func searchDuckDuckGoHTML(query: String) async throws -> [WebSearchResult] {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "html.duckduckgo.com"
        components.percentEncodedPath = "/html/"
        components.queryItems = [URLQueryItem(name: "q", value: query)]
        guard let url = components.url else {
            throw ProviderError.invalidBaseURL("https://html.duckduckgo.com/html/")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("text/html", forHTTPHeaderField: "Accept")
        let (data, response) = try await dataLoader(request)
        try Self.validate(response)
        guard let html = String(data: data, encoding: .utf8) else {
            return []
        }
        return parseDuckDuckGoHTML(html)
    }

    private func searchSearXNG(query: String, baseURLString: String) async throws -> [WebSearchResult] {
        guard let baseURL = URL(string: baseURLString), baseURL.scheme != nil else {
            throw ProviderError.invalidBaseURL(baseURLString.isEmpty ? "SearXNG base URL" : baseURLString)
        }
        let searchURL = baseURL.appendingPathComponent("search")
        guard var components = URLComponents(url: searchURL, resolvingAgainstBaseURL: false) else {
            throw ProviderError.invalidBaseURL(baseURLString)
        }
        components.queryItems = [
            URLQueryItem(name: "format", value: "json"),
            URLQueryItem(name: "q", value: query)
        ]
        guard let url = components.url else {
            throw ProviderError.invalidBaseURL(baseURLString)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await dataLoader(request)
        try Self.validate(response)
        let payload = try JSONDecoder().decode(SearXNGResponse.self, from: data)
        return payload.results.compactMap { item in
            guard let url = URL(string: item.url) else {
                return nil
            }
            return WebSearchResult(
                title: item.title.trimmingCharacters(in: .whitespacesAndNewlines),
                url: url,
                snippet: item.content.trimmingCharacters(in: .whitespacesAndNewlines),
                pageContent: nil
            )
        }
    }

    private func searchBrave(query: String, settings: WebSearchSettings) async throws -> [WebSearchResult] {
        guard let secretID = settings.braveAPIKeySecretID,
              let apiKey = try await secretStore.readSecret(id: secretID)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
              !apiKey.isEmpty else {
            throw WebSearchServiceError.missingBraveAPIKey
        }

        var components = URLComponents()
        components.scheme = "https"
        components.host = "api.search.brave.com"
        components.path = "/res/v1/web/search"
        components.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "count", value: String(max(settings.resultCount, 1)))
        ]
        guard let url = components.url else {
            throw ProviderError.invalidBaseURL("https://api.search.brave.com/res/v1/web/search")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(apiKey, forHTTPHeaderField: "X-Subscription-Token")
        let (data, response) = try await dataLoader(request)
        try Self.validate(response)
        let payload = try JSONDecoder().decode(BraveSearchResponse.self, from: data)
        return payload.web.results.compactMap { item in
            guard let url = URL(string: item.url) else {
                return nil
            }
            return WebSearchResult(
                title: item.title.trimmingCharacters(in: .whitespacesAndNewlines),
                url: url,
                snippet: item.description.trimmingCharacters(in: .whitespacesAndNewlines),
                pageContent: nil
            )
        }
    }

    private func loadPageContent(from url: URL, maxCharacters: Int) async throws -> String? {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("text/html,text/plain,application/pdf", forHTTPHeaderField: "Accept")
        let (data, response) = try await dataLoader(request)
        try Self.validate(response)
        if Self.isPDFResponse(response, url: url) {
            guard let pdfText = extractPDFText(from: data) else {
                return nil
            }
            return limitedText(pdfText, maxCharacters: maxCharacters)
        }
        guard let rawText = String(data: data, encoding: .utf8) else {
            return nil
        }
        let cleanedText = cleanPageText(rawText)
        guard !cleanedText.isEmpty else {
            return nil
        }
        return limitedText(cleanedText, maxCharacters: maxCharacters)
    }

    private static func isPDFResponse(_ response: URLResponse, url: URL) -> Bool {
        if url.pathExtension.lowercased() == "pdf" {
            return true
        }
        guard let httpResponse = response as? HTTPURLResponse,
              let contentType = httpResponse.value(forHTTPHeaderField: "Content-Type")?.lowercased() else {
            return false
        }
        return contentType.contains("application/pdf")
    }

    private func extractPDFText(from data: Data) -> String? {
        guard let document = PDFDocument(data: data) else {
            return nil
        }
        let text = (0..<document.pageCount)
            .compactMap { document.page(at: $0)?.string }
            .joined(separator: "\n")
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }

    private func parseDuckDuckGoHTML(_ html: String) -> [WebSearchResult] {
        let anchorPattern = #"<a[^>]*class="[^"]*result__a[^"]*"[^>]*href="([^"]+)"[^>]*>(.*?)</a>"#
        guard let anchorRegex = try? NSRegularExpression(pattern: anchorPattern, options: [.dotMatchesLineSeparators, .caseInsensitive]) else {
            return []
        }
        let nsHTML = html as NSString
        let matches = anchorRegex.matches(in: html, range: NSRange(location: 0, length: nsHTML.length))

        return matches.compactMap { match in
            guard match.numberOfRanges >= 3,
                  let hrefRange = Range(match.range(at: 1), in: html),
                  let titleRange = Range(match.range(at: 2), in: html),
                  let url = duckDuckGoDestinationURL(String(html[hrefRange])) else {
                return nil
            }

            let title = cleanHTML(String(html[titleRange]))
            let snippet = snippetAfter(match: match, in: html, nsHTML: nsHTML)
            guard !title.isEmpty else {
                return nil
            }
            return WebSearchResult(title: title, url: url, snippet: snippet, pageContent: nil)
        }
    }

    private func cleanPageText(_ value: String) -> String {
        let withoutHTML = value
            .replacingOccurrences(of: #"<script\b[^>]*>.*?</script>"#, with: " ", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: #"<style\b[^>]*>.*?</style>"#, with: " ", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: #"<[^>]+>"#, with: " ", options: .regularExpression)

        return decodeHTMLEntities(withoutHTML)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func limitedText(_ value: String, maxCharacters: Int) -> String {
        guard value.count > maxCharacters else {
            return value
        }
        let endIndex = value.index(value.startIndex, offsetBy: maxCharacters)
        let prefix = String(value[..<endIndex])
        if let lastWhitespace = prefix.lastIndex(where: { $0.isWhitespace }) {
            return String(prefix[..<lastWhitespace]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return prefix.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func snippetAfter(match: NSTextCheckingResult, in html: String, nsHTML: NSString) -> String {
        let start = match.range.location + match.range.length
        let remainingRange = NSRange(location: start, length: max(nsHTML.length - start, 0))
        let snippetPattern = #"<a[^>]*class="[^"]*result__snippet[^"]*"[^>]*>(.*?)</a>"#
        guard let snippetRegex = try? NSRegularExpression(pattern: snippetPattern, options: [.dotMatchesLineSeparators, .caseInsensitive]),
              let snippetMatch = snippetRegex.firstMatch(in: html, range: remainingRange),
              snippetMatch.numberOfRanges >= 2,
              let snippetRange = Range(snippetMatch.range(at: 1), in: html) else {
            return ""
        }
        return cleanHTML(String(html[snippetRange]))
    }

    private func duckDuckGoDestinationURL(_ href: String) -> URL? {
        let decodedHref = decodeHTMLEntities(href)
        guard let url = URL(string: decodedHref) else {
            return nil
        }
        if url.host?.contains("duckduckgo.com") == true,
           let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
           let destination = components.queryItems?.first(where: { $0.name == "uddg" })?.value,
           let destinationURL = URL(string: destination) {
            return destinationURL
        }
        return url
    }

    private func cleanHTML(_ value: String) -> String {
        let withoutTags = value.replacingOccurrences(
            of: #"<[^>]+>"#,
            with: "",
            options: .regularExpression
        )
        return decodeHTMLEntities(withoutTags)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func decodeHTMLEntities(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&apos;", with: "'")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
    }

    private func matchesDomainFilter(_ url: URL, filters: [String]) -> Bool {
        let normalizedFilters = filters
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty }
        guard !normalizedFilters.isEmpty else {
            return true
        }
        guard let host = url.host?.lowercased() else {
            return false
        }
        return normalizedFilters.contains { filter in
            host == filter || host.hasSuffix(".\(filter)")
        }
    }

    private static func validate(_ response: URLResponse) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ProviderError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw ProviderError.httpStatus(httpResponse.statusCode)
        }
    }

    static func defaultDataLoader(_ request: URLRequest) async throws -> (Data, URLResponse) {
        try await URLSession.shared.data(for: request)
    }
}

private struct SearXNGResponse: Decodable {
    var results: [SearXNGResult]
}

private struct SearXNGResult: Decodable {
    var title: String
    var url: String
    var content: String
}

private struct BraveSearchResponse: Decodable {
    var web: BraveSearchWebResults
}

private struct BraveSearchWebResults: Decodable {
    var results: [BraveSearchResult]
}

private struct BraveSearchResult: Decodable {
    var title: String
    var url: String
    var description: String
}
