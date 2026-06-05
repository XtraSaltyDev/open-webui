import XCTest
@testable import OpenWebUINative

@MainActor
final class AppStoreAuditLogTests: XCTestCase {
    func testAuditStorageRoundTripsEventsNewestFirst() async throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let storage = JSONAuditLogStorageService(rootURL: rootURL)
        let older = AppAuditEvent(
            action: .featureToggleUpdated,
            outcome: .succeeded,
            summary: "Disabled Notes",
            metadata: ["feature": "notes", "enabled": "false"],
            createdAt: Date(timeIntervalSince1970: 10)
        )
        let newer = AppAuditEvent(
            action: .workspaceBackupExported,
            outcome: .succeeded,
            summary: "Exported workspace backup",
            metadata: ["surface": "settings"],
            createdAt: Date(timeIntervalSince1970: 20)
        )

        try await storage.save(older)
        try await storage.save(newer)

        let events = try await storage.loadEvents()

        XCTAssertEqual(events, [newer, older])
    }

    func testSetFeatureTogglePersistsLocalAuditEvent() async throws {
        let fixture = try AuditLogFixture()
        let store = fixture.makeStore()
        await store.load()

        await store.setFeatureToggle(.notes, isEnabled: false)

        let event = try XCTUnwrap(store.auditEvents.first)
        XCTAssertEqual(event.action, .featureToggleUpdated)
        XCTAssertEqual(event.outcome, .succeeded)
        XCTAssertEqual(event.metadata["feature"], "notes")
        XCTAssertEqual(event.metadata["enabled"], "false")
        XCTAssertTrue(event.summary.contains("Notes"))

        let reloadedStore = fixture.makeStore()
        await reloadedStore.load()

        XCTAssertEqual(reloadedStore.auditEvents.first?.action, .featureToggleUpdated)
        XCTAssertEqual(reloadedStore.auditEvents.first?.metadata["feature"], "notes")
    }

    func testRunCodeExecutionCreatesSucceededAuditEvent() async throws {
        let runID = UUID(uuidString: "00000000-0000-0000-0000-00000000A11D")!
        let executor = FakeAuditCodeExecutor(
            run: AppCodeExecutionRun(
                id: runID,
                language: .shell,
                code: "printf audit",
                stdout: "audit",
                status: .succeeded,
                exitCode: 0
            )
        )
        let fixture = try AuditLogFixture(codeExecutor: executor)
        let store = fixture.makeStore()
        await store.load()
        store.enableLocalExecutionForTests(sandboxRootPath: "/tmp")
        await store.setFeatureToggle(.codeInterpreter, isEnabled: true)
        store.codeExecutionInput = "printf audit"

        await store.runCodeExecution()

        let event = try XCTUnwrap(store.auditEvents.first)
        XCTAssertEqual(event.action, .codeExecutionRun)
        XCTAssertEqual(event.outcome, .succeeded)
        XCTAssertEqual(event.metadata["language"], "shell")
        XCTAssertEqual(event.metadata["runID"], runID.uuidString)
    }

    func testExportAndDeleteAuditEvents() async throws {
        let fixture = try AuditLogFixture()
        let store = fixture.makeStore()
        await store.load()

        await store.setFeatureToggle(.webSearch, isEnabled: false)
        let event = try XCTUnwrap(store.auditEvents.first)

        let data = try store.exportAuditLogJSONData()
        let bundle = try AuditLogExportService().importBundle(from: data)
        XCTAssertEqual(bundle.events.map(\.id), [event.id])

        await store.deleteAuditEvent(event.id)

        let deletionEvent = try XCTUnwrap(store.auditEvents.first)
        XCTAssertEqual(store.auditEvents.count, 1)
        XCTAssertEqual(deletionEvent.action.rawValue, "auditEventDeleted")
        XCTAssertEqual(deletionEvent.outcome, .succeeded)
        XCTAssertEqual(deletionEvent.summary, "Deleted audit event")
        XCTAssertEqual(deletionEvent.metadata["deletedEventID"], event.id.uuidString)
        XCTAssertEqual(deletionEvent.metadata["deletedAction"], AppAuditAction.featureToggleUpdated.rawValue)
        XCTAssertEqual(deletionEvent.metadata["deletedOutcome"], AppAuditOutcome.succeeded.rawValue)

        let reloaded = try await fixture.auditStorage.loadEvents()
        XCTAssertEqual(reloaded.map(\.id), [deletionEvent.id])
        XCTAssertEqual(reloaded.first?.metadata["deletedEventID"], event.id.uuidString)
    }

    func testExportAuditLogJSONForUserActionCreatesAuditEventWithoutCopiedEventContent() async throws {
        let fixture = try AuditLogFixture()
        let store = fixture.makeStore()
        await store.load()

        await store.setFeatureToggle(.webSearch, isEnabled: false)
        let originalEvent = try XCTUnwrap(store.auditEvents.first)

        let data = try await store.exportAuditLogJSONDataForUserAction()
        let bundle = try AuditLogExportService().importBundle(from: data)

        XCTAssertEqual(bundle.events.count, 2)
        XCTAssertEqual(bundle.events.map(\.action), [.auditLogExported, .featureToggleUpdated])
        let exportEvent = try XCTUnwrap(bundle.events.first)
        XCTAssertEqual(exportEvent.outcome, .succeeded)
        XCTAssertEqual(exportEvent.summary, "Exported audit log")
        XCTAssertEqual(exportEvent.metadata["exportedAuditEventCount"], "2")
        XCTAssertEqual(exportEvent.metadata["includedExportEvent"], "true")
        XCTAssertNil(exportEvent.metadata["summary"])
        XCTAssertNil(exportEvent.metadata["deletedEventID"])
        XCTAssertFalse(exportEvent.metadata.values.contains(originalEvent.summary))

        let reloaded = try await fixture.auditStorage.loadEvents()
        XCTAssertEqual(reloaded.map(\.action), [.auditLogExported, .featureToggleUpdated])
    }

    func testExportAnalyticsJSONForUserActionCreatesAuditEventWithoutReportContent() async throws {
        let fixture = try AuditLogFixture()
        let store = fixture.makeStore()
        await store.load()
        store.threads = [
            ChatThread(
                title: "Private analytics chat",
                messages: [
                    ChatMessage(role: .assistant, content: "Confidential answer", modelID: "llama3.2:latest")
                ]
            )
        ]

        let data = try await store.exportAnalyticsJSONDataForUserAction()
        let bundle = try JSONDecoder().decode(AnalyticsExportBundle.self, from: data)

        XCTAssertEqual(bundle.summary.totalChats, 1)
        XCTAssertEqual(bundle.summary.totalMessages, 1)
        let event = try XCTUnwrap(store.auditEvents.filter { $0.action == .analyticsExported }.first)
        XCTAssertEqual(event.outcome, .succeeded)
        XCTAssertEqual(event.summary, "Exported analytics report")
        XCTAssertEqual(event.metadata["exportedChatCount"], "1")
        XCTAssertEqual(event.metadata["exportedMessageCount"], "1")
        XCTAssertEqual(event.metadata["exportedModelCount"], "1")
        XCTAssertNil(event.metadata["title"])
        XCTAssertNil(event.metadata["content"])
        XCTAssertNil(event.metadata["message"])
        XCTAssertFalse(event.metadata.values.contains("Private analytics chat"))
        XCTAssertFalse(event.metadata.values.contains("Confidential answer"))
    }

    func testExportAnalyticsJSONForUserActionIncludesSecretlessWebSearchNetworkSummary() async throws {
        let fixture = try AuditLogFixture()
        let store = fixture.makeStore()
        await store.load()
        store.auditEvents = [
            AppAuditEvent(
                action: .webSearchRun,
                outcome: .succeeded,
                summary: "Web search completed",
                metadata: [
                    "contactedHosts": "api.search.brave.com, example.com",
                    "usedAPIKey": "true"
                ]
            ),
            AppAuditEvent(
                action: .webSearchRun,
                outcome: .failed,
                summary: "Web search failed",
                metadata: [
                    "contactedHosts": "api.search.brave.com",
                    "usedAPIKey": "true"
                ]
            ),
            AppAuditEvent(
                action: .webSearchRun,
                outcome: .blocked,
                summary: "Web search blocked",
                metadata: [
                    "contactedHosts": "none",
                    "usedAPIKey": "false"
                ]
            )
        ]

        let data = try await store.exportAnalyticsJSONDataForUserAction()
        let bundle = try JSONDecoder().decode(AnalyticsExportBundle.self, from: data)

        XCTAssertEqual(bundle.webSearchNetworkSummary.totalRuns, 3)
        XCTAssertEqual(bundle.webSearchNetworkSummary.failedRuns, 1)
        XCTAssertEqual(bundle.webSearchNetworkSummary.blockedRuns, 1)
        XCTAssertEqual(bundle.webSearchNetworkSummary.apiKeyRuns, 2)
        XCTAssertEqual(bundle.webSearchNetworkSummary.uniqueHostCount, 2)
        let event = try XCTUnwrap(store.auditEvents.filter { $0.action == .analyticsExported }.first)
        XCTAssertEqual(event.metadata["exportedWebSearchRunCount"], "3")
        XCTAssertEqual(event.metadata["exportedWebSearchHostCount"], "2")
        XCTAssertEqual(event.metadata["exportedWebSearchAPIKeyRunCount"], "2")
        XCTAssertEqual(event.metadata["exportedWebSearchFailedRunCount"], "1")
        XCTAssertEqual(event.metadata["exportedWebSearchBlockedRunCount"], "1")
        XCTAssertNil(event.metadata["query"])
    }

    func testAuditMetadataFormatterHighlightsAutomationErrors() {
        let event = AppAuditEvent(
            action: .automationRun,
            outcome: .failed,
            summary: "Daily summary automation failed",
            metadata: [
                "automationID": "automation-1",
                "error": "The provider returned an invalid response.",
                "modelID": "llama3.2:latest",
                "runID": "run-1",
                "status": "failed"
            ]
        )

        let rows = AuditEventMetadataFormatter.rows(for: event)

        XCTAssertEqual(rows.first?.label, "Error")
        XCTAssertEqual(rows.first?.value, "The provider returned an invalid response.")
        XCTAssertEqual(rows.map(\.label), ["Error", "Status", "Model", "Run", "Automation"])
    }

    func testAuditMetadataFormatterPromotesFeedbackAdminRows() {
        let event = AppAuditEvent(
            action: .feedbackModerationUpdated,
            outcome: .succeeded,
            summary: "Marked feedback reviewed",
            metadata: [
                "feedbackID": "feedback-id",
                "modelID": "llama3.2:latest",
                "rating": "negative",
                "moderationStatus": "dismissed",
                "fromStatus": "pending",
                "toStatus": "reviewed"
            ]
        )

        let rows = AuditEventMetadataFormatter.rows(for: event)

        XCTAssertEqual(rows.map(\.label), ["Feedback", "Model", "Rating", "Moderation", "From", "To"])
        XCTAssertEqual(rows.map(\.value), ["feedback-id", "llama3.2:latest", "negative", "dismissed", "pending", "reviewed"])
    }

    func testAuditMetadataFormatterPromotesPromptRows() {
        let event = AppAuditEvent(
            action: .promptUpdated,
            outcome: .succeeded,
            summary: "Updated prompt Bug triage",
            metadata: [
                "promptID": "prompt-id",
                "fromTitle": "Old bug triage",
                "title": "Bug triage",
                "command": "/triage",
                "tags": "debug, triage"
            ]
        )

        let rows = AuditEventMetadataFormatter.rows(for: event)

        XCTAssertEqual(rows.map(\.label), ["Prompt", "Title", "From", "Command", "Tags"])
        XCTAssertEqual(rows.map(\.value), ["prompt-id", "Bug triage", "Old bug triage", "/triage", "debug, triage"])
    }

    func testAuditMetadataFormatterPromotesToolRows() {
        let event = AppAuditEvent(
            action: .toolUpdated,
            outcome: .succeeded,
            summary: "Updated tool Weather lookup",
            metadata: [
                "toolID": "tool-id",
                "fromName": "Old weather lookup",
                "name": "Weather lookup",
                "description": "Fetch weather for a city."
            ]
        )

        let rows = AuditEventMetadataFormatter.rows(for: event)

        XCTAssertEqual(rows.map(\.label), ["Tool", "Name", "From", "Description"])
        XCTAssertEqual(rows.map(\.value), ["tool-id", "Weather lookup", "Old weather lookup", "Fetch weather for a city."])
    }

    func testAuditMetadataFormatterPromotesSkillRows() {
        let event = AppAuditEvent(
            action: .skillUpdated,
            outcome: .succeeded,
            summary: "Updated skill Bug triage",
            metadata: [
                "skillID": "skill-id",
                "fromName": "Old bug triage",
                "name": "Bug triage",
                "description": "Triage incoming bug reports.",
                "tags": "debug, support",
                "isActive": "false"
            ]
        )

        let rows = AuditEventMetadataFormatter.rows(for: event)

        XCTAssertEqual(rows.map(\.label), ["Skill", "Name", "From", "Description", "Tags", "Active"])
        XCTAssertEqual(rows.map(\.value), ["skill-id", "Bug triage", "Old bug triage", "Triage incoming bug reports.", "debug, support", "false"])
    }

    func testAuditMetadataFormatterPromotesFunctionRows() {
        let event = AppAuditEvent(
            action: .functionUpdated,
            outcome: .succeeded,
            summary: "Updated function Safety filter",
            metadata: [
                "functionID": "function-id",
                "fromName": "Old safety filter",
                "name": "Safety filter",
                "kind": "filter",
                "description": "Review prompts before sending.",
                "isActive": "true",
                "isGlobal": "false"
            ]
        )

        let rows = AuditEventMetadataFormatter.rows(for: event)

        XCTAssertEqual(rows.map(\.label), ["Function", "Name", "From", "Kind", "Description", "Active", "Global"])
        XCTAssertEqual(rows.map(\.value), ["function-id", "Safety filter", "Old safety filter", "filter", "Review prompts before sending.", "true", "false"])
    }

    func testAuditMetadataFormatterPromotesAdminUserRows() throws {
        let action = try XCTUnwrap(AppAuditAction(rawValue: "adminUserUpdated"))
        let event = AppAuditEvent(
            action: action,
            outcome: .succeeded,
            summary: "Updated admin user Admiral Grace",
            metadata: [
                "userID": "user-id",
                "fromName": "Grace Hopper",
                "name": "Admiral Grace",
                "fromEmail": "grace@example.com",
                "email": "grace@navy.example",
                "fromRole": "pending",
                "role": "admin"
            ]
        )

        let rows = AuditEventMetadataFormatter.rows(for: event)

        XCTAssertEqual(rows.map(\.label), ["User", "Name", "From", "Email", "From Email", "Role", "From Role"])
        XCTAssertEqual(rows.map(\.value), ["user-id", "Admiral Grace", "Grace Hopper", "grace@navy.example", "grace@example.com", "admin", "pending"])
    }

    func testAuditMetadataFormatterPromotesAdminGroupRows() throws {
        let action = try XCTUnwrap(AppAuditAction(rawValue: "adminGroupUpdated"))
        let event = AppAuditEvent(
            action: action,
            outcome: .succeeded,
            summary: "Updated admin group Workspace Editors",
            metadata: [
                "groupID": "group-id",
                "fromName": "Knowledge Editors",
                "name": "Workspace Editors",
                "description": "Can edit workspace records.",
                "permissions": "workspace.write",
                "memberCount": "2",
                "fromMemberCount": "1"
            ]
        )

        let rows = AuditEventMetadataFormatter.rows(for: event)

        XCTAssertEqual(rows.map(\.label), ["Group", "Name", "From", "Description", "Permissions", "Members", "From Members"])
        XCTAssertEqual(rows.map(\.value), ["group-id", "Workspace Editors", "Knowledge Editors", "Can edit workspace records.", "workspace.write", "2", "1"])
    }

    func testAuditMetadataFormatterPromotesAdminDirectoryExportRows() throws {
        let action = try XCTUnwrap(AppAuditAction(rawValue: "adminDirectoryExported"))
        let event = AppAuditEvent(
            action: action,
            outcome: .succeeded,
            summary: "Exported admin directory",
            metadata: [
                "exportedUserCount": "2",
                "exportedGroupCount": "1"
            ]
        )

        let rows = AuditEventMetadataFormatter.rows(for: event)

        XCTAssertEqual(rows.map(\.label), ["Exported Users", "Exported Groups"])
        XCTAssertEqual(rows.map(\.value), ["2", "1"])
    }

    func testAuditMetadataFormatterPromotesAdminDirectoryImportRows() throws {
        let action = try XCTUnwrap(AppAuditAction(rawValue: "adminDirectoryImported"))
        let event = AppAuditEvent(
            action: action,
            outcome: .succeeded,
            summary: "Imported admin directory",
            metadata: [
                "importedUserCount": "2",
                "importedGroupCount": "1",
                "totalUserCount": "4",
                "totalGroupCount": "3"
            ]
        )

        let rows = AuditEventMetadataFormatter.rows(for: event)

        XCTAssertEqual(rows.map(\.label), ["Imported Users", "Imported Groups", "Total Users", "Total Groups"])
        XCTAssertEqual(rows.map(\.value), ["2", "1", "4", "3"])
    }

    func testAuditMetadataFormatterPromotesWorkspaceBackupRows() throws {
        let event = AppAuditEvent(
            action: .workspaceBackupExported,
            outcome: .succeeded,
            summary: "Exported workspace backup",
            metadata: [
                "exportedThreadCount": "3",
                "exportedPromptCount": "2",
                "exportedNoteCount": "1",
                "exportedKnowledgeCollectionCount": "4",
                "excludedSecrets": "true"
            ]
        )

        let rows = AuditEventMetadataFormatter.rows(for: event)

        XCTAssertEqual(
            rows.map(\.label),
            ["Threads", "Prompts", "Notes", "Knowledge Collections", "Secrets Excluded"]
        )
        XCTAssertEqual(rows.map(\.value), ["3", "2", "1", "4", "true"])
    }

    func testAuditMetadataFormatterPromotesAuditLogExportRows() {
        let event = AppAuditEvent(
            action: .auditLogExported,
            outcome: .succeeded,
            summary: "Exported audit log",
            metadata: [
                "exportedAuditEventCount": "12",
                "includedExportEvent": "true"
            ]
        )

        let rows = AuditEventMetadataFormatter.rows(for: event)

        XCTAssertEqual(rows.map(\.label), ["Exported Events", "Includes Export Event"])
        XCTAssertEqual(rows.map(\.value), ["12", "true"])
    }

    func testAuditMetadataFormatterPromotesAnalyticsExportRows() {
        let event = AppAuditEvent(
            action: .analyticsExported,
            outcome: .succeeded,
            summary: "Exported analytics report",
            metadata: [
                "exportedChatCount": "5",
                "exportedMessageCount": "20",
                "exportedModelCount": "3",
                "exportedFeedbackCount": "2",
                "exportedKnowledgeCollectionCount": "4",
                "exportedWebSearchRunCount": "6",
                "exportedWebSearchHostCount": "3",
                "exportedWebSearchAPIKeyRunCount": "2",
                "exportedWebSearchFailedRunCount": "1",
                "exportedWebSearchBlockedRunCount": "2"
            ]
        )

        let rows = AuditEventMetadataFormatter.rows(for: event)

        XCTAssertEqual(
            rows.map(\.label),
            [
                "Chats",
                "Messages",
                "Models",
                "Feedback",
                "Knowledge Collections",
                "Web Search Runs",
                "Web Search Hosts",
                "Web Search API Key Runs",
                "Web Search Failed Runs",
                "Web Search Blocked Runs"
            ]
        )
        XCTAssertEqual(rows.map(\.value), ["5", "20", "3", "2", "4", "6", "3", "2", "1", "2"])
    }

    func testAuditMetadataFormatterPromotesCodeExecutionRunRows() {
        let event = AppAuditEvent(
            action: .codeExecutionRunDeleted,
            outcome: .succeeded,
            summary: "Deleted code execution run",
            metadata: [
                "runID": "run-id",
                "language": "python",
                "status": "failed"
            ]
        )

        let rows = AuditEventMetadataFormatter.rows(for: event)

        XCTAssertEqual(rows.map(\.label), ["Run", "Language", "Status"])
        XCTAssertEqual(rows.map(\.value), ["run-id", "python", "failed"])
    }

    func testAuditMetadataFormatterPromotesTerminalCommandRows() {
        let event = AppAuditEvent(
            action: .terminalCommandDeleted,
            outcome: .succeeded,
            summary: "Deleted terminal command",
            metadata: [
                "sessionID": "session-id",
                "commandID": "command-id",
                "status": "succeeded"
            ]
        )

        let rows = AuditEventMetadataFormatter.rows(for: event)

        XCTAssertEqual(rows.map(\.label), ["Session", "Command", "Status"])
        XCTAssertEqual(rows.map(\.value), ["session-id", "command-id", "succeeded"])
    }

    func testAuditMetadataFormatterPromotesToolServerRunRows() {
        let event = AppAuditEvent(
            action: .toolServerInvoked,
            outcome: .succeeded,
            summary: "Gateway tool search_docs call succeeded",
            metadata: [
                "serverID": "server-id",
                "serverKind": "http",
                "runID": "run-id",
                "toolName": "search_docs",
                "status": "succeeded"
            ]
        )

        let rows = AuditEventMetadataFormatter.rows(for: event)

        XCTAssertEqual(rows.map(\.label), ["Server", "Kind", "Run", "Tool", "Status"])
        XCTAssertEqual(rows.map(\.value), ["server-id", "http", "run-id", "search_docs", "succeeded"])
    }

    func testWebSearchNetworkHistorySummaryCountsOutcomesHostsAndAPIKeyUse() {
        let events = [
            AppAuditEvent(
                action: .webSearchRun,
                outcome: .succeeded,
                summary: "Web search completed",
                metadata: [
                    "contactedHosts": "api.search.brave.com, example.com",
                    "usedAPIKey": "true"
                ],
                createdAt: Date(timeIntervalSince1970: 30)
            ),
            AppAuditEvent(
                action: .webSearchRun,
                outcome: .blocked,
                summary: "Web search blocked",
                metadata: [
                    "contactedHosts": "none",
                    "usedAPIKey": "false"
                ],
                createdAt: Date(timeIntervalSince1970: 20)
            ),
            AppAuditEvent(
                action: .webSearchRun,
                outcome: .failed,
                summary: "Web search failed",
                metadata: [
                    "contactedHosts": "html.duckduckgo.com, example.com",
                    "usedAPIKey": "false"
                ],
                createdAt: Date(timeIntervalSince1970: 10)
            ),
            AppAuditEvent(
                action: .codeExecutionRun,
                outcome: .succeeded,
                summary: "Ran code",
                metadata: ["contactedHosts": "ignored.example.com"],
                createdAt: Date(timeIntervalSince1970: 40)
            )
        ]

        let summary = WebSearchNetworkHistorySummary(events: events)

        XCTAssertTrue(summary.hasHistory)
        XCTAssertEqual(summary.totalRuns, 3)
        XCTAssertEqual(summary.succeededRuns, 1)
        XCTAssertEqual(summary.failedRuns, 1)
        XCTAssertEqual(summary.blockedRuns, 1)
        XCTAssertEqual(summary.apiKeyRuns, 1)
        XCTAssertEqual(summary.uniqueHostCount, 3)
        XCTAssertEqual(summary.mostRecentRunAt, Date(timeIntervalSince1970: 30))
        XCTAssertEqual(summary.topHosts, [
            WebSearchNetworkHostSummary(host: "example.com", runCount: 2),
            WebSearchNetworkHostSummary(host: "api.search.brave.com", runCount: 1),
            WebSearchNetworkHostSummary(host: "html.duckduckgo.com", runCount: 1)
        ])
    }

    func testWebSearchNetworkHistorySummaryNormalizesAndDeduplicatesHostsPerRun() {
        let events = [
            AppAuditEvent(
                action: .webSearchRun,
                outcome: .succeeded,
                summary: "Web search completed",
                metadata: [
                    "contactedHosts": " Example.com, example.com, HTML.DuckDuckGo.com ",
                    "usedAPIKey": "TRUE"
                ],
                createdAt: Date(timeIntervalSince1970: 1)
            )
        ]

        let summary = WebSearchNetworkHistorySummary(events: events)

        XCTAssertEqual(summary.totalRuns, 1)
        XCTAssertEqual(summary.apiKeyRuns, 1)
        XCTAssertEqual(summary.uniqueHostCount, 2)
        XCTAssertEqual(summary.topHosts, [
            WebSearchNetworkHostSummary(host: "example.com", runCount: 1),
            WebSearchNetworkHostSummary(host: "html.duckduckgo.com", runCount: 1)
        ])
    }

    func testAuditMetadataFormatterSplitsUnknownCamelCaseKeys() {
        let event = AppAuditEvent(
            action: .workspaceBackupImported,
            outcome: .succeeded,
            summary: "Imported workspace backup",
            metadata: [
                "calendarID": "calendar-id",
                "createdByUserID": "user-id"
            ]
        )

        let rows = AuditEventMetadataFormatter.rows(for: event)

        XCTAssertEqual(rows.map(\.label), ["Calendar ID", "Created By User ID"])
    }

    func testAuditMetadataFormatterSplitsAcronymBoundariesInUnknownKeys() {
        let event = AppAuditEvent(
            action: .workspaceBackupImported,
            outcome: .succeeded,
            summary: "Imported workspace backup",
            metadata: [
                "createdURLValue": "https://example.test"
            ]
        )

        let rows = AuditEventMetadataFormatter.rows(for: event)

        XCTAssertEqual(rows.map(\.label), ["Created URL Value"])
    }

    func testAuditMetadataFormatterSeparatesPreviewAndOverflowRows() {
        let event = AppAuditEvent(
            action: .automationRun,
            outcome: .failed,
            summary: "Daily summary automation failed",
            metadata: [
                "automationID": "automation-1",
                "error": "The provider returned an invalid response.",
                "modelID": "llama3.2:latest",
                "runID": "run-1",
                "status": "failed",
                "trigger": "manual"
            ]
        )

        let presentation = AuditEventMetadataFormatter.presentation(for: event, previewLimit: 4)

        XCTAssertEqual(presentation.previewRows.map(\.label), ["Error", "Status", "Model", "Run"])
        XCTAssertEqual(presentation.overflowRows.map(\.label), ["Automation", "Trigger"])
        XCTAssertEqual(presentation.overflowCount, 2)
    }

    func testAuditEventFilterMatchesActionOutcomeSummaryAndMetadata() {
        let automation = AppAuditEvent(
            action: .automationRun,
            outcome: .failed,
            summary: "Daily summary automation failed",
            metadata: [
                "error": "The provider returned an invalid response.",
                "modelID": "llama3.2:latest"
            ]
        )
        let featureToggle = AppAuditEvent(
            action: .featureToggleUpdated,
            outcome: .succeeded,
            summary: "Disabled Web Search",
            metadata: ["feature": "webSearch"]
        )
        let events = [automation, featureToggle]

        XCTAssertEqual(AuditEventFilter.filteredEvents(events, query: "invalid response").map(\.id), [automation.id])
        XCTAssertEqual(AuditEventFilter.filteredEvents(events, query: "Automation run").map(\.id), [automation.id])
        XCTAssertEqual(AuditEventFilter.filteredEvents(events, query: "failed").map(\.id), [automation.id])
        XCTAssertEqual(AuditEventFilter.filteredEvents(events, query: "webSearch").map(\.id), [featureToggle.id])
    }

    func testAuditEventFilterMatchesRawActionAndFeedbackMetadata() {
        let feedback = AppAuditEvent(
            action: .feedbackDeleted,
            outcome: .succeeded,
            summary: "Deleted feedback for llama3.2:latest",
            metadata: [
                "feedbackID": "feedback-id",
                "modelID": "llama3.2:latest"
            ]
        )
        let automation = AppAuditEvent(
            action: .automationRun,
            outcome: .succeeded,
            summary: "Daily summary automation succeeded"
        )
        let events = [feedback, automation]

        XCTAssertEqual(AuditEventFilter.filteredEvents(events, query: "feedbackDeleted").map(\.id), [feedback.id])
        XCTAssertEqual(AuditEventFilter.filteredEvents(events, query: "feedback-id").map(\.id), [feedback.id])
    }

    func testAuditEventFilterKeepsEventsForBlankQuery() {
        let events = [
            AppAuditEvent(action: .automationRun, outcome: .failed, summary: "Failed automation"),
            AppAuditEvent(action: .codeExecutionRun, outcome: .succeeded, summary: "Ran code")
        ]

        XCTAssertEqual(AuditEventFilter.filteredEvents(events, query: "   "), events)
    }

    func testAuditEventFilterResultSummaryDescribesTotalAndMatches() {
        XCTAssertEqual(
            AuditEventFilter.resultSummary(totalCount: 5, filteredCount: 5, query: ""),
            "5 events"
        )
        XCTAssertEqual(
            AuditEventFilter.resultSummary(totalCount: 5, filteredCount: 1, query: "failed"),
            "1 match"
        )
        XCTAssertEqual(
            AuditEventFilter.resultSummary(totalCount: 5, filteredCount: 0, query: "missing"),
            "0 matches"
        )
    }

    func testAuditEventFilterDetectsActiveQueries() {
        XCTAssertFalse(AuditEventFilter.isQueryActive(""))
        XCTAssertFalse(AuditEventFilter.isQueryActive("   "))
        XCTAssertTrue(AuditEventFilter.isQueryActive("failed"))
    }

    func testAuditEventFilterClearsQueries() {
        XCTAssertEqual(AuditEventFilter.clearedQuery(from: "failed"), "")
        XCTAssertEqual(AuditEventFilter.clearedQuery(from: "   "), "")
    }

    func testAuditEventFilterClearSearchHelpTextMentionsEscape() {
        XCTAssertEqual(AuditEventFilter.clearSearchHelpText, "Clear audit search (Esc)")
    }

    func testAuditEventFilterEmptyResultTextMentionsEscape() {
        XCTAssertEqual(
            AuditEventFilter.emptyResultText,
            "No audit events match this search. Press Esc to clear."
        )
    }
}

private struct AuditLogFixture {
    let rootURL: URL
    let storage: JSONStorageService
    let folderStorage: JSONFolderStorageService
    let settingsStore: SettingsStore
    let codeExecutionStorage: JSONCodeExecutionStorageService
    let auditStorage: JSONAuditLogStorageService
    let codeExecutor: any CodeExecuting

    init(codeExecutor: any CodeExecuting = FakeAuditCodeExecutor()) throws {
        rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        storage = JSONStorageService(rootURL: rootURL.appendingPathComponent("Chats", isDirectory: true))
        folderStorage = JSONFolderStorageService(rootURL: rootURL.appendingPathComponent("Folders", isDirectory: true))
        settingsStore = SettingsStore(settingsURL: rootURL.appendingPathComponent("settings.json"))
        codeExecutionStorage = JSONCodeExecutionStorageService(
            rootURL: rootURL.appendingPathComponent("CodeExecution", isDirectory: true)
        )
        auditStorage = JSONAuditLogStorageService(rootURL: rootURL.appendingPathComponent("AuditLog", isDirectory: true))
        self.codeExecutor = codeExecutor
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
    }

    @MainActor
    func makeStore() -> AppStore {
        AppStore(
            storage: storage,
            folderStorage: folderStorage,
            settingsStore: settingsStore,
            secretStore: InMemorySecretStore(),
            codeExecutionStorage: codeExecutionStorage,
            auditLogStorage: auditStorage,
            codeExecutor: codeExecutor
        )
    }
}

private actor FakeAuditCodeExecutor: CodeExecuting {
    private let run: AppCodeExecutionRun

    init(
        run: AppCodeExecutionRun = AppCodeExecutionRun(
            language: .shell,
            code: "",
            stdout: "",
            status: .succeeded,
            exitCode: 0
        )
    ) {
        self.run = run
    }

    func execute(_ request: CodeExecutionRequest) async -> AppCodeExecutionRun {
        run
    }
}
