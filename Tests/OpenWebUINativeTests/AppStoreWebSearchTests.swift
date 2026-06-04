import Foundation
import XCTest
@testable import OpenWebUINative

@MainActor
final class AppStoreWebSearchTests: XCTestCase {
    func testSendPromptWithWebSearchAddsCitationsAndProviderContext() async throws {
        let provider = CapturingWebSearchProvider(chunks: ["answer"])
        let webSearch = StubWebSearchService(results: [
            WebSearchResult(
                title: "SwiftUI Search",
                url: URL(string: "https://developer.apple.com/swiftui/")!,
                snippet: "SwiftUI helps build native apps.",
                pageContent: "SwiftUI is a framework for building native app interfaces."
            )
        ])
        let fixture = try WebSearchFixture(provider: provider, webSearchService: webSearch)
        let store = fixture.makeStore()
        await store.load()
        await store.selectModel("fake-model")
        await store.setFeatureToggle(.webSearch, isEnabled: true)
        await store.updateWebSearchSettings(WebSearchSettings(isPageContentLoadingEnabled: true))
        store.isWebSearchEnabledForNextPrompt = true

        await store.send("Find current SwiftUI guidance")

        let sentContent = await provider.capturedMessages.first { $0.role == "user" }?.content
        let failureContext = sentContent ?? store.errorMessage ?? "No provider content or store error"
        XCTAssertTrue(sentContent?.contains("Web search context") ?? false, failureContext)
        XCTAssertTrue(sentContent?.contains("SwiftUI Search") ?? false, failureContext)
        XCTAssertTrue(sentContent?.contains("https://developer.apple.com/swiftui/") ?? false, failureContext)
        XCTAssertTrue(sentContent?.contains("SwiftUI is a framework for building native app interfaces.") ?? false, failureContext)

        let userMessage = try XCTUnwrap(store.selectedThread?.messages.first { $0.role == .user })
        let citation = try XCTUnwrap(userMessage.citations.first)
        XCTAssertEqual(citation.collectionName, "Web Search")
        XCTAssertEqual(citation.collectionSlug, "web")
        XCTAssertEqual(citation.sourceName, "SwiftUI Search")
        XCTAssertNil(citation.documentID)
        XCTAssertNil(citation.chunkID)
        XCTAssertEqual(store.recentWebSearchResults, [
            WebSearchResult(
                title: "SwiftUI Search",
                url: URL(string: "https://developer.apple.com/swiftui/")!,
                snippet: "SwiftUI helps build native apps.",
                pageContent: "SwiftUI is a framework for building native app interfaces."
            )
        ])
        let telemetry = try XCTUnwrap(store.recentWebSearchTelemetry)
        XCTAssertEqual(telemetry.query, "Find current SwiftUI guidance")
        XCTAssertEqual(telemetry.engine, .duckDuckGoHTML)
        XCTAssertEqual(telemetry.resultCount, 1)
        XCTAssertEqual(telemetry.status, .succeeded)
        XCTAssertTrue(telemetry.wasPageContentLoadingEnabled)
        XCTAssertEqual(telemetry.pageContentResultCount, 1)
        XCTAssertEqual(telemetry.contactedHosts, ["html.duckduckgo.com", "developer.apple.com"])
        XCTAssertFalse(telemetry.usedAPIKey)
        XCTAssertNil(telemetry.errorMessage)
        XCTAssertLessThan(abs(telemetry.completedAt.timeIntervalSinceNow), 5)
        XCTAssertFalse(store.isWebSearchEnabledForNextPrompt)
    }

    func testWebSearchTelemetryRecordsBraveHostAndKeychainAuthWithoutSecretValue() async throws {
        let provider = CapturingWebSearchProvider(chunks: ["answer"])
        let webSearch = StubWebSearchService(results: [
            WebSearchResult(
                title: "Brave Result",
                url: URL(string: "https://example.com/brave")!,
                snippet: "Brave web context.",
                pageContent: "Loaded Brave web context."
            )
        ])
        let fixture = try WebSearchFixture(provider: provider, webSearchService: webSearch)
        let store = fixture.makeStore()
        await store.load()
        await store.selectModel("fake-model")
        await store.setFeatureToggle(.webSearch, isEnabled: true)
        await store.updateWebSearchSettings(WebSearchSettings(
            engine: .brave,
            resultCount: 3,
            braveAPIKeySecretID: "web-search-brave-key",
            domainFilterList: [],
            isPageContentLoadingEnabled: true
        ))
        store.isWebSearchEnabledForNextPrompt = true

        await store.send("Find Brave context")

        let telemetry = try XCTUnwrap(store.recentWebSearchTelemetry)
        XCTAssertEqual(telemetry.engine, .brave)
        XCTAssertEqual(telemetry.contactedHosts, ["api.search.brave.com", "example.com"])
        XCTAssertTrue(telemetry.usedAPIKey)
        XCTAssertFalse(telemetry.networkSummary.contains("web-search-brave-key"))
        XCTAssertFalse(telemetry.networkSummary.contains("brave-secret"))
    }

    func testWebSearchTelemetryRecordsTavilyHostAndKeychainAuthWithoutSecretValue() async throws {
        let provider = CapturingWebSearchProvider(chunks: ["answer"])
        let webSearch = StubWebSearchService(results: [
            WebSearchResult(
                title: "Tavily Result",
                url: URL(string: "https://example.com/tavily")!,
                snippet: "Tavily web context.",
                pageContent: "Loaded Tavily web context."
            )
        ])
        let fixture = try WebSearchFixture(provider: provider, webSearchService: webSearch)
        let store = fixture.makeStore()
        await store.load()
        await store.selectModel("fake-model")
        await store.setFeatureToggle(.webSearch, isEnabled: true)
        await store.updateWebSearchSettings(WebSearchSettings(
            engine: .tavily,
            resultCount: 3,
            tavilyAPIKeySecretID: "web-search-tavily-key",
            domainFilterList: [],
            isPageContentLoadingEnabled: true
        ))
        store.isWebSearchEnabledForNextPrompt = true

        await store.send("Find Tavily context")

        let telemetry = try XCTUnwrap(store.recentWebSearchTelemetry)
        XCTAssertEqual(telemetry.engine, .tavily)
        XCTAssertEqual(telemetry.contactedHosts, ["api.tavily.com", "example.com"])
        XCTAssertTrue(telemetry.usedAPIKey)
        XCTAssertFalse(telemetry.networkSummary.contains("web-search-tavily-key"))
        XCTAssertFalse(telemetry.networkSummary.contains("tavily-secret"))
    }

    func testWebSearchRecordsSecretlessNetworkAuditHistory() async throws {
        let provider = CapturingWebSearchProvider(chunks: ["answer"])
        let webSearch = StubWebSearchService(results: [
            WebSearchResult(
                title: "Brave Result",
                url: URL(string: "https://example.com/brave")!,
                snippet: "Brave web context.",
                pageContent: "Loaded Brave web context."
            )
        ])
        let fixture = try WebSearchFixture(provider: provider, webSearchService: webSearch)
        let store = fixture.makeStore()
        await store.load()
        await store.selectModel("fake-model")
        await store.setFeatureToggle(.webSearch, isEnabled: true)
        await store.updateWebSearchSettings(WebSearchSettings(
            engine: .brave,
            resultCount: 3,
            braveAPIKeySecretID: "web-search-brave-key",
            domainFilterList: [],
            isPageContentLoadingEnabled: true
        ))
        store.isWebSearchEnabledForNextPrompt = true

        await store.send("Find private Brave context")

        let event = try XCTUnwrap(store.auditEvents.filter { $0.action == .webSearchRun }.first)
        XCTAssertEqual(event.outcome, .succeeded)
        XCTAssertEqual(event.summary, "Web search completed")
        XCTAssertEqual(event.metadata["engine"], "brave")
        XCTAssertEqual(event.metadata["status"], "succeeded")
        XCTAssertEqual(event.metadata["resultCount"], "1")
        XCTAssertEqual(event.metadata["pageContentResultCount"], "1")
        XCTAssertEqual(event.metadata["contactedHosts"], "api.search.brave.com, example.com")
        XCTAssertEqual(event.metadata["usedAPIKey"], "true")
        XCTAssertNil(event.metadata["query"])
        XCTAssertFalse(event.metadata.values.contains("Find private Brave context"))
        XCTAssertFalse(event.metadata.values.contains("web-search-brave-key"))
        XCTAssertFalse(event.metadata.values.contains("brave-secret"))

        let persistedEvents = try await fixture.auditStorage.loadEvents()
        let persistedEvent = try XCTUnwrap(persistedEvents.filter { $0.action == .webSearchRun }.first)
        XCTAssertEqual(persistedEvent.metadata["contactedHosts"], "api.search.brave.com, example.com")
    }

    func testBlockedWebSearchRecordsAuditHistoryWithoutNetworkHosts() async throws {
        let provider = CapturingWebSearchProvider(chunks: ["answer"])
        let webSearch = CapturingStubWebSearchService(results: [
            WebSearchResult(
                title: "Blocked Result",
                url: URL(string: "https://example.com/blocked")!,
                snippet: "Blocked web context."
            )
        ])
        let fixture = try WebSearchFixture(provider: provider, webSearchService: webSearch)
        let store = fixture.makeStore()
        await store.load()
        await store.selectModel("fake-model")
        await store.setFeatureToggle(.webSearch, isEnabled: false)
        store.isWebSearchEnabledForNextPrompt = true

        await store.send("Find disabled context")

        let event = try XCTUnwrap(store.auditEvents.filter { $0.action == .webSearchRun }.first)
        XCTAssertEqual(event.outcome, .blocked)
        XCTAssertEqual(event.summary, "Web search blocked")
        XCTAssertEqual(event.metadata["engine"], "duckDuckGoHTML")
        XCTAssertEqual(event.metadata["status"], "failed")
        XCTAssertEqual(event.metadata["resultCount"], "0")
        XCTAssertEqual(event.metadata["contactedHosts"], "none")
        XCTAssertEqual(event.metadata["usedAPIKey"], "false")
        XCTAssertNil(event.metadata["query"])

        let queries = await webSearch.searchedQueries()
        XCTAssertEqual(queries, [])
    }

    func testSendPromptFallsBackToSnippetWhenPageContentIsMissing() async throws {
        let provider = CapturingWebSearchProvider(chunks: ["answer"])
        let webSearch = StubWebSearchService(results: [
            WebSearchResult(
                title: "Snippet Result",
                url: URL(string: "https://example.com/snippet")!,
                snippet: "Use the snippet when page text is unavailable."
            )
        ])
        let fixture = try WebSearchFixture(provider: provider, webSearchService: webSearch)
        let store = fixture.makeStore()
        await store.load()
        await store.selectModel("fake-model")
        await store.setFeatureToggle(.webSearch, isEnabled: true)
        store.isWebSearchEnabledForNextPrompt = true

        await store.send("Find snippet context")

        let sentContent = await provider.capturedMessages.first { $0.role == "user" }?.content
        XCTAssertTrue(sentContent?.contains("Use the snippet when page text is unavailable.") ?? false)
    }

    func testWebSearchErrorsSurfaceClearlyBeforeProviderSend() async throws {
        let provider = CapturingWebSearchProvider(chunks: ["answer"])
        let webSearch = StubWebSearchService(errorMessage: "Search unavailable")
        let fixture = try WebSearchFixture(provider: provider, webSearchService: webSearch)
        let store = fixture.makeStore()
        await store.load()
        await store.selectModel("fake-model")
        await store.setFeatureToggle(.webSearch, isEnabled: true)
        await store.updateWebSearchSettings(WebSearchSettings(isPageContentLoadingEnabled: true))
        store.isWebSearchEnabledForNextPrompt = true

        await store.send("Search before answering")

        XCTAssertEqual(store.errorMessage, "Search unavailable")
        XCTAssertTrue(store.selectedThread?.messages.isEmpty ?? false)
        let capturedMessages = await provider.messages()
        XCTAssertEqual(capturedMessages, [])
        XCTAssertEqual(store.recentWebSearchResults, [])
        let telemetry = try XCTUnwrap(store.recentWebSearchTelemetry)
        XCTAssertEqual(telemetry.query, "Search before answering")
        XCTAssertEqual(telemetry.engine, .duckDuckGoHTML)
        XCTAssertEqual(telemetry.resultCount, 0)
        XCTAssertEqual(telemetry.status, .failed)
        XCTAssertTrue(telemetry.wasPageContentLoadingEnabled)
        XCTAssertEqual(telemetry.pageContentResultCount, 0)
        XCTAssertEqual(telemetry.errorMessage, "Search unavailable")
        XCTAssertTrue(store.isWebSearchEnabledForNextPrompt)
    }

    func testWebSearchFailureClearsStalePreviewResults() async throws {
        let provider = CapturingWebSearchProvider(chunks: ["answer"])
        let webSearch = StubWebSearchService(errorMessage: "Search unavailable")
        let fixture = try WebSearchFixture(provider: provider, webSearchService: webSearch)
        let store = fixture.makeStore()
        store.recentWebSearchResults = [
            WebSearchResult(
                title: "Old Result",
                url: URL(string: "https://example.com/old")!,
                snippet: "Stale preview."
            )
        ]
        store.recentWebSearchTelemetry = WebSearchTelemetry(
            query: "Old search",
            engine: .duckDuckGoHTML,
            resultCount: 1,
            status: .succeeded,
            wasPageContentLoadingEnabled: false,
            pageContentResultCount: 0,
            errorMessage: nil,
            completedAt: Date(timeIntervalSince1970: 10)
        )
        await store.load()
        await store.selectModel("fake-model")
        await store.setFeatureToggle(.webSearch, isEnabled: true)
        store.isWebSearchEnabledForNextPrompt = true

        await store.send("Search before answering")

        XCTAssertEqual(store.recentWebSearchResults, [])
        let telemetry = try XCTUnwrap(store.recentWebSearchTelemetry)
        XCTAssertEqual(telemetry.status, .failed)
        XCTAssertEqual(telemetry.errorMessage, "Search unavailable")
        XCTAssertEqual(store.webSearchError, "Search unavailable")
    }

    func testDisablingWebSearchClearsPendingPreviewResults() async throws {
        let fixture = try WebSearchFixture(
            provider: CapturingWebSearchProvider(chunks: ["answer"]),
            webSearchService: StubWebSearchService()
        )
        let store = fixture.makeStore()
        store.isWebSearchEnabledForNextPrompt = true
        store.webSearchError = "Previous search failed"
        store.recentWebSearchResults = [
            WebSearchResult(
                title: "Previous Result",
                url: URL(string: "https://example.com/previous")!,
                snippet: "Previous preview."
            )
        ]
        store.recentWebSearchTelemetry = WebSearchTelemetry(
            query: "Previous search",
            engine: .duckDuckGoHTML,
            resultCount: 1,
            status: .succeeded,
            wasPageContentLoadingEnabled: false,
            pageContentResultCount: 0,
            errorMessage: nil,
            completedAt: Date(timeIntervalSince1970: 10)
        )

        await store.setFeatureToggle(.webSearch, isEnabled: false)

        XCTAssertFalse(store.isWebSearchEnabledForNextPrompt)
        XCTAssertNil(store.webSearchError)
        XCTAssertEqual(store.recentWebSearchResults, [])
        XCTAssertNil(store.recentWebSearchTelemetry)
    }

    func testWebSearchDisabledFeatureBlocksSearchAndProviderSend() async throws {
        let provider = CapturingWebSearchProvider(chunks: ["answer"])
        let webSearch = CapturingStubWebSearchService(results: [
            WebSearchResult(
                title: "Disabled Result",
                url: URL(string: "https://example.com/disabled")!,
                snippet: "Disabled web context."
            )
        ])
        let fixture = try WebSearchFixture(provider: provider, webSearchService: webSearch)
        let store = fixture.makeStore()
        await store.load()
        await store.selectModel("fake-model")
        store.recentWebSearchResults = [
            WebSearchResult(
                title: "Old Disabled Result",
                url: URL(string: "https://example.com/old-disabled")!,
                snippet: "Old disabled preview."
            )
        ]
        store.recentWebSearchTelemetry = WebSearchTelemetry(
            query: "Old disabled search",
            engine: .duckDuckGoHTML,
            resultCount: 1,
            status: .succeeded,
            wasPageContentLoadingEnabled: false,
            pageContentResultCount: 0,
            errorMessage: nil,
            completedAt: Date(timeIntervalSince1970: 10)
        )
        await store.setFeatureToggle(.webSearch, isEnabled: false)
        store.isWebSearchEnabledForNextPrompt = true

        await store.send("Find disabled context")

        let queries = await webSearch.searchedQueries()
        let capturedMessages = await provider.messages()
        XCTAssertEqual(queries, [])
        XCTAssertTrue(store.selectedThread?.messages.isEmpty ?? false)
        XCTAssertEqual(capturedMessages, [])
        XCTAssertEqual(store.webSearchError, "Web Search is disabled.")
        XCTAssertEqual(store.errorMessage, "Web Search is disabled.")
        XCTAssertEqual(store.recentWebSearchResults, [])
        let telemetry = try XCTUnwrap(store.recentWebSearchTelemetry)
        XCTAssertEqual(telemetry.query, "Find disabled context")
        XCTAssertEqual(telemetry.status, .failed)
        XCTAssertEqual(telemetry.errorMessage, "Web Search is disabled.")
        XCTAssertEqual(telemetry.contactedHosts, [])
        XCTAssertFalse(telemetry.usedAPIKey)
        XCTAssertTrue(store.isWebSearchEnabledForNextPrompt)
    }

    func testWebSearchExecutePermissionAllowsCurrentUserToSearchBeforeSending() async throws {
        let provider = CapturingWebSearchProvider(chunks: ["answer"])
        let webSearch = CapturingStubWebSearchService(results: [
            WebSearchResult(
                title: "Allowed Result",
                url: URL(string: "https://example.com/allowed")!,
                snippet: "Allowed web context."
            )
        ])
        let fixture = try WebSearchFixture(provider: provider, webSearchService: webSearch)
        let store = fixture.makeStore()
        await store.load()
        await store.selectModel("fake-model")
        await store.setFeatureToggle(.webSearch, isEnabled: true)
        await store.createAdminUser(name: "Workspace User", email: "user@example.com", role: .user)
        let user = try XCTUnwrap(store.adminUsers.first)
        await store.createAdminGroup(name: "Web Search Users", description: "Can search.", permissions: ["web_search.execute"])
        let group = try XCTUnwrap(store.adminGroups.first)
        await store.setAdminGroupMembers(group.id, memberIDs: [user.id])
        store.currentUserID = user.id
        store.isWebSearchEnabledForNextPrompt = true

        await store.send("Find allowed context")

        let queries = await webSearch.searchedQueries()
        XCTAssertEqual(queries, ["Find allowed context"])
        let sentContent = await provider.capturedMessages.first { $0.role == "user" }?.content
        XCTAssertTrue(sentContent?.contains("Allowed web context.") ?? false, sentContent ?? store.errorMessage ?? "No sent content")
        XCTAssertFalse(store.isWebSearchEnabledForNextPrompt)
        XCTAssertNil(store.webSearchError)
        XCTAssertNil(store.errorMessage)
    }

    func testWebSearchExecutePermissionBlocksCurrentUserBeforeSearchAndProviderSend() async throws {
        let provider = CapturingWebSearchProvider(chunks: ["answer"])
        let webSearch = CapturingStubWebSearchService(results: [
            WebSearchResult(
                title: "Blocked Result",
                url: URL(string: "https://example.com/blocked")!,
                snippet: "Blocked web context."
            )
        ])
        let fixture = try WebSearchFixture(provider: provider, webSearchService: webSearch)
        let store = fixture.makeStore()
        await store.load()
        await store.selectModel("fake-model")
        await store.setFeatureToggle(.webSearch, isEnabled: true)
        store.recentWebSearchResults = [
            WebSearchResult(
                title: "Old Permission Result",
                url: URL(string: "https://example.com/old-permission")!,
                snippet: "Old permission preview."
            )
        ]
        store.recentWebSearchTelemetry = WebSearchTelemetry(
            query: "Old permission search",
            engine: .duckDuckGoHTML,
            resultCount: 1,
            status: .succeeded,
            wasPageContentLoadingEnabled: false,
            pageContentResultCount: 0,
            errorMessage: nil,
            completedAt: Date(timeIntervalSince1970: 10)
        )
        await store.createAdminUser(name: "Workspace User", email: "user@example.com", role: .user)
        let user = try XCTUnwrap(store.adminUsers.first)
        store.currentUserID = user.id
        store.isWebSearchEnabledForNextPrompt = true

        await store.send("Find blocked context")

        let queries = await webSearch.searchedQueries()
        let capturedMessages = await provider.messages()
        XCTAssertEqual(queries, [])
        XCTAssertTrue(store.selectedThread?.messages.isEmpty ?? false)
        XCTAssertEqual(capturedMessages, [])
        XCTAssertEqual(store.webSearchError, "You do not have permission to use web search.")
        XCTAssertEqual(store.errorMessage, "You do not have permission to use web search.")
        XCTAssertEqual(store.recentWebSearchResults, [])
        let telemetry = try XCTUnwrap(store.recentWebSearchTelemetry)
        XCTAssertEqual(telemetry.query, "Find blocked context")
        XCTAssertEqual(telemetry.status, .failed)
        XCTAssertEqual(telemetry.errorMessage, "You do not have permission to use web search.")
        XCTAssertEqual(telemetry.contactedHosts, [])
        XCTAssertFalse(telemetry.usedAPIKey)
        XCTAssertTrue(store.isWebSearchEnabledForNextPrompt)
    }

    func testUnmanagedLocalUserCanUseWebSearchWhenAdminDirectoryExists() async throws {
        let provider = CapturingWebSearchProvider(chunks: ["answer"])
        let webSearch = CapturingStubWebSearchService(results: [
            WebSearchResult(
                title: "Local Result",
                url: URL(string: "https://example.com/local")!,
                snippet: "Local web context."
            )
        ])
        let fixture = try WebSearchFixture(provider: provider, webSearchService: webSearch)
        let store = fixture.makeStore()
        await store.load()
        await store.selectModel("fake-model")
        await store.setFeatureToggle(.webSearch, isEnabled: true)
        await store.createAdminUser(name: "Workspace User", email: "user@example.com", role: .user)
        store.isWebSearchEnabledForNextPrompt = true

        await store.send("Find local context")

        let queries = await webSearch.searchedQueries()
        XCTAssertEqual(queries, ["Find local context"])
        let sentContent = await provider.capturedMessages.first { $0.role == "user" }?.content
        XCTAssertTrue(sentContent?.contains("Local web context.") ?? false)
        XCTAssertNil(store.webSearchError)
    }

    func testUpdateWebSearchSettingsPersistsNormalizedAdminControls() async throws {
        let fixture = try WebSearchFixture(
            provider: CapturingWebSearchProvider(chunks: ["answer"]),
            webSearchService: StubWebSearchService()
        )
        let store = fixture.makeStore()
        await store.load()

        await store.updateWebSearchSettings(WebSearchSettings(
            engine: .searxng,
            resultCount: 25,
            searxngBaseURL: " http://localhost:8888 ",
            domainFilterList: [" Developer.Apple.com ", "developer.apple.com", "", "SWIFT.ORG"],
            isPageContentLoadingEnabled: true,
            maxPageContentCharacters: 25_000
        ))

        XCTAssertEqual(store.settings.webSearch.resultCount, 10)
        XCTAssertEqual(store.settings.webSearch.searxngBaseURL, "http://localhost:8888")
        XCTAssertEqual(store.settings.webSearch.domainFilterList, ["developer.apple.com", "swift.org"])
        XCTAssertEqual(store.settings.webSearch.maxPageContentCharacters, 12_000)

        let reloadedStore = fixture.makeStore()
        await reloadedStore.load()

        XCTAssertEqual(reloadedStore.settings.webSearch.resultCount, 10)
        XCTAssertEqual(reloadedStore.settings.webSearch.searxngBaseURL, "http://localhost:8888")
        XCTAssertEqual(reloadedStore.settings.webSearch.domainFilterList, ["developer.apple.com", "swift.org"])
        XCTAssertEqual(reloadedStore.settings.webSearch.maxPageContentCharacters, 12_000)
    }

    func testUpdateWebSearchSettingsStoresBraveAPIKeyInSecretStore() async throws {
        let fixture = try WebSearchFixture(
            provider: CapturingWebSearchProvider(chunks: ["answer"]),
            webSearchService: StubWebSearchService()
        )
        let store = fixture.makeStore()
        await store.load()

        await store.updateWebSearchSettings(
            WebSearchSettings(
                engine: .brave,
                resultCount: 3,
                braveAPIKeySecretID: nil,
                domainFilterList: []
            ),
            braveAPIKey: "  brave-secret  "
        )

        let secretID = try XCTUnwrap(store.settings.webSearch.braveAPIKeySecretID)
        XCTAssertEqual(secretID, "web-search-brave-api-key")
        let savedSecret = try await fixture.secretStore.readSecret(id: secretID)
        XCTAssertEqual(savedSecret, "brave-secret")

        let reloadedStore = fixture.makeStore()
        await reloadedStore.load()
        XCTAssertEqual(reloadedStore.settings.webSearch.engine, .brave)
        XCTAssertEqual(reloadedStore.settings.webSearch.braveAPIKeySecretID, secretID)
    }

    func testUpdateWebSearchSettingsStoresTavilyAPIKeyInSecretStore() async throws {
        let fixture = try WebSearchFixture(
            provider: CapturingWebSearchProvider(chunks: ["answer"]),
            webSearchService: StubWebSearchService()
        )
        let store = fixture.makeStore()
        await store.load()

        await store.updateWebSearchSettings(
            WebSearchSettings(
                engine: .tavily,
                resultCount: 3,
                tavilyAPIKeySecretID: nil,
                domainFilterList: []
            ),
            tavilyAPIKey: "  tavily-secret  "
        )

        let secretID = try XCTUnwrap(store.settings.webSearch.tavilyAPIKeySecretID)
        XCTAssertEqual(secretID, "web-search-tavily-api-key")
        let savedSecret = try await fixture.secretStore.readSecret(id: secretID)
        XCTAssertEqual(savedSecret, "tavily-secret")

        let reloadedStore = fixture.makeStore()
        await reloadedStore.load()
        XCTAssertEqual(reloadedStore.settings.webSearch.engine, .tavily)
        XCTAssertEqual(reloadedStore.settings.webSearch.tavilyAPIKeySecretID, secretID)
    }
}

private struct WebSearchFixture {
    let rootURL: URL
    let chatStorage: JSONStorageService
    let folderStorage: JSONFolderStorageService
    let settingsStore: SettingsStore
    let adminStorage: JSONAdminDirectoryStorageService
    let auditStorage: JSONAuditLogStorageService
    let secretStore: InMemorySecretStore
    let provider: CapturingWebSearchProvider
    let webSearchService: any WebSearching

    init(provider: CapturingWebSearchProvider, webSearchService: any WebSearching) throws {
        rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        chatStorage = JSONStorageService(rootURL: rootURL.appendingPathComponent("Chats", isDirectory: true))
        folderStorage = JSONFolderStorageService(rootURL: rootURL.appendingPathComponent("Folders", isDirectory: true))
        settingsStore = SettingsStore(settingsURL: rootURL.appendingPathComponent("settings.json"))
        adminStorage = JSONAdminDirectoryStorageService(
            snapshotURL: rootURL.appendingPathComponent("admin-directory.json")
        )
        auditStorage = JSONAuditLogStorageService(rootURL: rootURL.appendingPathComponent("AuditLog", isDirectory: true))
        secretStore = InMemorySecretStore()
        self.provider = provider
        self.webSearchService = webSearchService
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
    }

    @MainActor
    func makeStore() -> AppStore {
        AppStore(
            storage: chatStorage,
            folderStorage: folderStorage,
            settingsStore: settingsStore,
            secretStore: secretStore,
            providerOverride: provider,
            webSearchService: webSearchService,
            auditLogStorage: auditStorage,
            adminDirectoryStorage: adminStorage
        )
    }
}

private actor CapturingWebSearchProvider: ChatProvider {
    nonisolated var configuration: ProviderConfiguration {
        ProviderConfiguration.defaultOllama()
    }

    private let chunks: [String]
    private var captured: [ProviderChatMessage] = []

    init(chunks: [String]) {
        self.chunks = chunks
    }

    var capturedMessages: [ProviderChatMessage] {
        captured
    }

    func messages() -> [ProviderChatMessage] {
        captured
    }

    func listModels() async throws -> [ProviderModel] {
        [ProviderModel(id: "fake-model", name: "fake-model", provider: .ollama, providerID: ProviderConfiguration.defaultOllamaID)]
    }

    func healthCheck() async -> ProviderStatus {
        .available("Online")
    }

    nonisolated func streamChat(model: String, messages: [ProviderChatMessage]) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task {
                await capture(messages)
                for chunk in chunks {
                    continuation.yield(chunk)
                }
                continuation.finish()
            }
        }
    }

    func createEmbeddings(model: String, input: [String]) async throws -> [[Double]] {
        input.map { _ in [1] }
    }

    private func capture(_ messages: [ProviderChatMessage]) {
        captured = messages
    }
}

private struct StubWebSearchService: WebSearching {
    var results: [WebSearchResult] = []
    var errorMessage: String?

    func search(query: String, settings: WebSearchSettings) async throws -> [WebSearchResult] {
        if let errorMessage {
            throw NSError(domain: "StubWebSearchService", code: 1, userInfo: [
                NSLocalizedDescriptionKey: errorMessage
            ])
        }
        return results
    }
}

private actor CapturingStubWebSearchService: WebSearching {
    let results: [WebSearchResult]
    private(set) var queries: [String] = []

    init(results: [WebSearchResult]) {
        self.results = results
    }

    func search(query: String, settings: WebSearchSettings) async throws -> [WebSearchResult] {
        queries.append(query)
        return results
    }

    func searchedQueries() -> [String] {
        queries
    }
}
