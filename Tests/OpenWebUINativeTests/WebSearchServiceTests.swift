import AppKit
import Foundation
import XCTest
@testable import OpenWebUINative

final class WebSearchServiceTests: XCTestCase {
    func testTelemetryStatusSummaryIncludesSuccessAndPageContentCounts() {
        let telemetry = WebSearchTelemetry(
            query: "swift",
            engine: .duckDuckGoHTML,
            resultCount: 3,
            status: .succeeded,
            wasPageContentLoadingEnabled: true,
            pageContentResultCount: 2,
            errorMessage: nil,
            completedAt: Date(timeIntervalSince1970: 0)
        )

        XCTAssertEqual(telemetry.statusSummary, "3 DuckDuckGo HTML results, 2 with page text")
    }

    func testTelemetryStatusSummaryIncludesFailureMessage() {
        let telemetry = WebSearchTelemetry(
            query: "swift",
            engine: .searxng,
            resultCount: 0,
            status: .failed,
            wasPageContentLoadingEnabled: true,
            pageContentResultCount: 0,
            errorMessage: "Search unavailable",
            completedAt: Date(timeIntervalSince1970: 0)
        )

        XCTAssertEqual(telemetry.statusSummary, "SearXNG search failed: Search unavailable")
    }

    func testTelemetryNetworkSummaryIncludesHostsAndKeychainAuthState() {
        let telemetry = WebSearchTelemetry(
            query: "swift",
            engine: .brave,
            resultCount: 2,
            status: .succeeded,
            wasPageContentLoadingEnabled: true,
            pageContentResultCount: 1,
            errorMessage: nil,
            completedAt: Date(timeIntervalSince1970: 0),
            contactedHosts: ["api.search.brave.com", "developer.apple.com"],
            usedAPIKey: true
        )

        XCTAssertEqual(
            telemetry.networkSummary,
            "Hosts: api.search.brave.com, developer.apple.com; API key used from Keychain"
        )
    }

    func testTelemetryNetworkSummaryHandlesNoNetworkHosts() {
        let telemetry = WebSearchTelemetry(
            query: "swift",
            engine: .duckDuckGoHTML,
            resultCount: 0,
            status: .failed,
            wasPageContentLoadingEnabled: false,
            pageContentResultCount: 0,
            errorMessage: "Web Search is disabled.",
            completedAt: Date(timeIntervalSince1970: 0),
            contactedHosts: [],
            usedAPIKey: false
        )

        XCTAssertEqual(telemetry.networkSummary, "No network hosts contacted; No API key")
    }

    func testDuckDuckGoSearchBuildsQueryParsesResultsAndAppliesDomainFilter() async throws {
        let html = """
        <div class="result">
          <a class="result__a" href="https://duckduckgo.com/l/?uddg=https%3A%2F%2Fdeveloper.apple.com%2Fswift%2F">Swift &amp; Apple</a>
          <a class="result__snippet">Swift concurrency documentation.</a>
        </div>
        <div class="result">
          <a class="result__a" href="https://example.com/ignored">Ignored</a>
          <a class="result__snippet">Filtered out.</a>
        </div>
        """.data(using: .utf8)!
        let requestCapture = WebSearchRequestCapture()
        let service = WebSearchService { request in
            await requestCapture.set(request)
            return (html, HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
        let settings = WebSearchSettings(
            engine: .duckDuckGoHTML,
            resultCount: 3,
            searxngBaseURL: "",
            domainFilterList: ["developer.apple.com"]
        )

        let results = try await service.search(query: "swift concurrency", settings: settings)
        let capturedRequest = await requestCapture.request

        XCTAssertEqual(capturedRequest?.url?.host, "html.duckduckgo.com")
        XCTAssertEqual(capturedRequest?.url?.path, "/html")
        XCTAssertTrue(capturedRequest?.url?.query?.contains("q=swift%20concurrency") ?? false)
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.title, "Swift & Apple")
        XCTAssertEqual(results.first?.url.absoluteString, "https://developer.apple.com/swift/")
        XCTAssertEqual(results.first?.snippet, "Swift concurrency documentation.")
    }

    func testSearXNGSearchUsesConfiguredBaseURLAndResultLimit() async throws {
        let payload = """
        {
          "results": [
            {"title": "One", "url": "https://one.example/post", "content": "First snippet"},
            {"title": "Two", "url": "https://two.example/post", "content": "Second snippet"}
          ]
        }
        """.data(using: .utf8)!
        let requestCapture = WebSearchRequestCapture()
        let service = WebSearchService { request in
            await requestCapture.set(request)
            return (payload, HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
        let settings = WebSearchSettings(
            engine: .searxng,
            resultCount: 1,
            searxngBaseURL: "http://localhost:8888",
            domainFilterList: []
        )

        let results = try await service.search(query: "native macOS", settings: settings)
        let capturedRequest = await requestCapture.request

        XCTAssertEqual(capturedRequest?.url?.absoluteString, "http://localhost:8888/search?format=json&q=native%20macOS")
        XCTAssertEqual(results, [
            WebSearchResult(title: "One", url: URL(string: "https://one.example/post")!, snippet: "First snippet")
        ])
    }

    func testBraveSearchUsesOfficialEndpointSubscriptionTokenAndResultLimit() async throws {
        let payload = """
        {
          "web": {
            "results": [
              {"title": "One", "url": "https://one.example/post", "description": "First snippet"},
              {"title": "Two", "url": "https://two.example/post", "description": "Second snippet"}
            ]
          }
        }
        """.data(using: .utf8)!
        let requestCapture = WebSearchRequestCapture()
        let service = WebSearchService(
            secretStore: InMemorySecretStore(["web-search-brave-key": "brave-token"])
        ) { request in
            await requestCapture.set(request)
            return (payload, HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
        let settings = WebSearchSettings(
            engine: .brave,
            resultCount: 1,
            braveAPIKeySecretID: "web-search-brave-key",
            domainFilterList: []
        )

        let results = try await service.search(query: "native macOS", settings: settings)
        let capturedRequest = await requestCapture.request

        XCTAssertEqual(capturedRequest?.url?.absoluteString, "https://api.search.brave.com/res/v1/web/search?q=native%20macOS&count=1")
        XCTAssertEqual(capturedRequest?.value(forHTTPHeaderField: "Accept"), "application/json")
        XCTAssertEqual(capturedRequest?.value(forHTTPHeaderField: "X-Subscription-Token"), "brave-token")
        XCTAssertEqual(results, [
            WebSearchResult(title: "One", url: URL(string: "https://one.example/post")!, snippet: "First snippet")
        ])
    }

    func testBraveSearchRequiresStoredAPIKey() async throws {
        let service = WebSearchService(
            secretStore: InMemorySecretStore()
        ) { request in
            XCTFail("Unexpected request: \(request)")
            return (Data(), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
        let settings = WebSearchSettings(
            engine: .brave,
            resultCount: 1,
            braveAPIKeySecretID: "missing-key",
            domainFilterList: []
        )

        do {
            _ = try await service.search(query: "native macOS", settings: settings)
            XCTFail("Expected missing Brave API key error.")
        } catch {
            XCTAssertEqual(error.localizedDescription, "Add a Brave Search API key before searching with Brave.")
        }
    }

    func testTavilySearchUsesOfficialEndpointBearerTokenAndParsesResults() async throws {
        let payload = """
        {
          "results": [
            {"title": "One", "url": "https://one.example/post", "content": "First snippet"},
            {"title": "Two", "url": "https://two.example/post", "content": "Second snippet"}
          ]
        }
        """.data(using: .utf8)!
        let requestCapture = WebSearchRequestCapture()
        let service = WebSearchService(
            secretStore: InMemorySecretStore(["web-search-tavily-key": "tavily-token"])
        ) { request in
            await requestCapture.set(request)
            return (payload, HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
        let settings = WebSearchSettings(
            engine: .tavily,
            resultCount: 1,
            tavilyAPIKeySecretID: "web-search-tavily-key",
            domainFilterList: []
        )

        let results = try await service.search(query: "native macOS", settings: settings)
        let capturedRequest = await requestCapture.request
        let requestBody = try XCTUnwrap(capturedRequest?.httpBody)
        let requestJSON = try XCTUnwrap(JSONSerialization.jsonObject(with: requestBody) as? [String: Any])

        XCTAssertEqual(capturedRequest?.url?.absoluteString, "https://api.tavily.com/search")
        XCTAssertEqual(capturedRequest?.httpMethod, "POST")
        XCTAssertEqual(capturedRequest?.value(forHTTPHeaderField: "Content-Type"), "application/json")
        XCTAssertEqual(capturedRequest?.value(forHTTPHeaderField: "Accept"), "application/json")
        XCTAssertEqual(capturedRequest?.value(forHTTPHeaderField: "Authorization"), "Bearer tavily-token")
        XCTAssertEqual(requestJSON["query"] as? String, "native macOS")
        XCTAssertEqual(requestJSON["max_results"] as? Int, 1)
        XCTAssertEqual(results, [
            WebSearchResult(title: "One", url: URL(string: "https://one.example/post")!, snippet: "First snippet")
        ])
    }

    func testTavilySearchRequiresStoredAPIKey() async throws {
        let service = WebSearchService(secretStore: InMemorySecretStore()) { request in
            XCTFail("Unexpected request: \(request)")
            return (Data(), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
        let settings = WebSearchSettings(
            engine: .tavily,
            resultCount: 1,
            tavilyAPIKeySecretID: "missing-key",
            domainFilterList: []
        )

        do {
            _ = try await service.search(query: "native macOS", settings: settings)
            XCTFail("Expected missing Tavily API key error.")
        } catch {
            XCTAssertEqual(error.localizedDescription, "Add a Tavily API key before searching with Tavily.")
        }
    }

    func testSearchLoadsPageContentWhenEnabled() async throws {
        let searchHTML = """
        <div class="result">
          <a class="result__a" href="https://example.com/article">Article</a>
          <a class="result__snippet">Short snippet.</a>
        </div>
        """.data(using: .utf8)!
        let pageHTML = """
        <html>
          <head><script>ignore()</script><style>body { color: red; }</style></head>
          <body>
            <nav>Navigation</nav>
            <main>
              <h1>Article title</h1>
              <p>First useful paragraph.</p>
              <p>Second useful paragraph with more detail.</p>
            </main>
          </body>
        </html>
        """.data(using: .utf8)!
        let requestCapture = WebSearchRequestCapture()
        let service = WebSearchService { request in
            await requestCapture.append(request)
            if request.url?.host == "example.com" {
                return (pageHTML, HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
            }
            return (searchHTML, HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
        let settings = WebSearchSettings(
            engine: .duckDuckGoHTML,
            resultCount: 1,
            searxngBaseURL: "",
            domainFilterList: [],
            isPageContentLoadingEnabled: true,
            maxPageContentCharacters: 60
        )

        let results = try await service.search(query: "article", settings: settings)
        let capturedRequests = await requestCapture.requests

        XCTAssertEqual(capturedRequests.map { $0.url?.host }, ["html.duckduckgo.com", "example.com"])
        XCTAssertEqual(results.first?.snippet, "Short snippet.")
        XCTAssertEqual(results.first?.pageContent, "Navigation Article title First useful paragraph. Second")
        XCTAssertFalse(results.first?.pageContent?.contains("more detail") ?? true)
        XCTAssertFalse(results.first?.pageContent?.contains("ignore") ?? true)
        XCTAssertFalse(results.first?.pageContent?.contains("color") ?? true)
    }

    func testSearchLoadsPDFPageContentWhenEnabled() async throws {
        let searchHTML = """
        <div class="result">
          <a class="result__a" href="https://example.com/report.pdf">Report PDF</a>
          <a class="result__snippet">PDF snippet.</a>
        </div>
        """.data(using: .utf8)!
        let pdfData = try makePDFData(text: "PDF web context for native search results.")
        let requestCapture = WebSearchRequestCapture()
        let service = WebSearchService { request in
            await requestCapture.append(request)
            if request.url?.path == "/report.pdf" {
                return (
                    pdfData,
                    HTTPURLResponse(
                        url: request.url!,
                        statusCode: 200,
                        httpVersion: nil,
                        headerFields: ["Content-Type": "application/pdf"]
                    )!
                )
            }
            return (searchHTML, HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
        let settings = WebSearchSettings(
            engine: .duckDuckGoHTML,
            resultCount: 1,
            searxngBaseURL: "",
            domainFilterList: [],
            isPageContentLoadingEnabled: true,
            maxPageContentCharacters: 200
        )

        let results = try await service.search(query: "pdf report", settings: settings)
        let capturedRequests = await requestCapture.requests

        XCTAssertEqual(capturedRequests.map { $0.url?.host }, ["html.duckduckgo.com", "example.com"])
        XCTAssertEqual(capturedRequests.last?.value(forHTTPHeaderField: "Accept"), "text/html,text/plain,application/pdf")
        XCTAssertEqual(results.first?.pageContent, "PDF web context for native search results.")
    }
}

private actor WebSearchRequestCapture {
    private(set) var requests: [URLRequest] = []

    var request: URLRequest? {
        requests.last
    }

    func set(_ request: URLRequest) {
        requests = [request]
    }

    func append(_ request: URLRequest) {
        requests.append(request)
    }
}

private func makePDFData(text: String) throws -> Data {
    let data = NSMutableData()
    var mediaBox = CGRect(x: 0, y: 0, width: 612, height: 792)
    guard
        let consumer = CGDataConsumer(data: data as CFMutableData),
        let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil)
    else {
        throw NSError(domain: "PDFTestFixture", code: 1)
    }

    context.beginPDFPage(nil)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
    let attributedString = NSAttributedString(
        string: text,
        attributes: [.font: NSFont.systemFont(ofSize: 14)]
    )
    attributedString.draw(in: CGRect(x: 72, y: 700, width: 468, height: 48))
    NSGraphicsContext.restoreGraphicsState()
    context.endPDFPage()
    context.closePDF()

    return data as Data
}
