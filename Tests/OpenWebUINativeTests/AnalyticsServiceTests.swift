import XCTest
@testable import OpenWebUINative

@MainActor
final class AnalyticsServiceTests: XCTestCase {
    func testSummaryCountsChatsMessagesModelsAndWorkspaceRecords() {
        let collectionID = UUID()
        let documentID = UUID()
        let summary = AnalyticsService().summary(
            threads: [
                ChatThread(
                    title: "Swift plan",
                    modelIDs: ["llama3.2:latest", "mistral:latest"],
                    isPinned: true,
                    messages: [
                        ChatMessage(role: .user, content: "Plan the app"),
                        ChatMessage(role: .assistant, content: "Here is a plan.", modelID: "llama3.2:latest"),
                        ChatMessage(role: .assistant, content: "Alternative plan.", modelID: "mistral:latest")
                    ]
                ),
                ChatThread(
                    title: "Archived",
                    modelIDs: ["llama3.2:latest"],
                    isArchived: true,
                    messages: [
                        ChatMessage(role: .user, content: "Archive this"),
                        ChatMessage(role: .assistant, content: "Archived.", modelID: "llama3.2:latest")
                    ]
                )
            ],
            feedbacks: [
                AppFeedback(data: AppFeedbackData(rating: .positive, modelID: "llama3.2:latest"), meta: AppFeedbackMeta()),
                AppFeedback(data: AppFeedbackData(rating: .negative, modelID: "mistral:latest"), meta: AppFeedbackMeta())
            ],
            knowledgeCollections: [
                KnowledgeCollection(id: collectionID, name: "Docs")
            ],
            knowledgeDocuments: [
                collectionID: [
                    KnowledgeDocument(
                        id: documentID,
                        collectionID: collectionID,
                        fileName: "guide.md",
                        contentType: "text/markdown",
                        byteCount: 256
                    )
                ]
            ],
            channels: [
                AppChannel(name: "Team", messages: [ChannelMessage(content: "Ship it")])
            ],
            notes: [
                AppNote(title: "Release note", content: "Native analytics")
            ],
            automations: [
                AppAutomation(name: "Daily summary", prompt: "Summarize", modelID: "llama3.2:latest", rrule: "FREQ=DAILY")
            ],
            calendars: [
                AppCalendar(name: "Personal")
            ],
            calendarEvents: [
                AppCalendarEvent(calendarID: "calendar-id", title: "Review", startAt: Date(timeIntervalSince1970: 1_000))
            ]
        )

        XCTAssertEqual(summary.totalChats, 2)
        XCTAssertEqual(summary.activeChats, 1)
        XCTAssertEqual(summary.archivedChats, 1)
        XCTAssertEqual(summary.pinnedChats, 1)
        XCTAssertEqual(summary.totalMessages, 5)
        XCTAssertEqual(summary.userMessages, 2)
        XCTAssertEqual(summary.assistantMessages, 3)
        XCTAssertEqual(summary.totalModels, 2)
        XCTAssertEqual(summary.positiveFeedback, 1)
        XCTAssertEqual(summary.negativeFeedback, 1)
        XCTAssertEqual(summary.knowledgeCollections, 1)
        XCTAssertEqual(summary.knowledgeDocuments, 1)
        XCTAssertEqual(summary.channels, 1)
        XCTAssertEqual(summary.channelMessages, 1)
        XCTAssertEqual(summary.notes, 1)
        XCTAssertEqual(summary.automations, 1)
        XCTAssertEqual(summary.calendars, 1)
        XCTAssertEqual(summary.calendarEvents, 1)
    }

    func testSummaryBuildsModelUsageSortedByMessageVolume() {
        let summary = AnalyticsService().summary(
            threads: [
                ChatThread(
                    title: "Models",
                    modelIDs: ["zeta", "alpha"],
                    messages: [
                        ChatMessage(role: .assistant, content: "A", modelID: "zeta"),
                        ChatMessage(role: .assistant, content: "B", modelID: "alpha"),
                        ChatMessage(role: .assistant, content: "C", modelID: "zeta"),
                        ChatMessage(role: .assistant, content: "D", modelID: "beta")
                    ]
                )
            ],
            feedbacks: [],
            knowledgeCollections: [],
            knowledgeDocuments: [:],
            channels: [],
            notes: [],
            automations: [],
            calendars: [],
            calendarEvents: []
        )

        XCTAssertEqual(summary.modelUsage.map(\.modelID), ["zeta", "alpha", "beta"])
        XCTAssertEqual(summary.modelUsage.map(\.messageCount), [2, 1, 1])
    }

    func testSummaryAggregatesProviderTokenUsageByModel() {
        let summary = AnalyticsService().summary(
            threads: [
                ChatThread(
                    title: "Token usage",
                    messages: [
                        ChatMessage(
                            role: .assistant,
                            content: "A",
                            modelID: "llama3.2:latest",
                            tokenUsage: ChatTokenUsage(promptTokens: 10, completionTokens: 5, totalTokens: 15)
                        ),
                        ChatMessage(
                            role: .assistant,
                            content: "B",
                            modelID: "llama3.2:latest",
                            tokenUsage: ChatTokenUsage(promptTokens: 12, completionTokens: 8, totalTokens: 20)
                        ),
                        ChatMessage(
                            role: .assistant,
                            content: "C",
                            modelID: "mistral:latest",
                            tokenUsage: ChatTokenUsage(promptTokens: 6, completionTokens: 4, totalTokens: 10)
                        )
                    ]
                )
            ],
            feedbacks: [],
            knowledgeCollections: [],
            knowledgeDocuments: [:],
            channels: [],
            notes: [],
            automations: [],
            calendars: [],
            calendarEvents: []
        )

        XCTAssertEqual(summary.totalPromptTokens, 28)
        XCTAssertEqual(summary.totalCompletionTokens, 17)
        XCTAssertEqual(summary.totalTokens, 45)
        XCTAssertEqual(summary.modelUsage.first?.modelID, "llama3.2:latest")
        XCTAssertEqual(summary.modelUsage.first?.promptTokens, 22)
        XCTAssertEqual(summary.modelUsage.first?.completionTokens, 13)
        XCTAssertEqual(summary.modelUsage.first?.totalTokens, 35)
    }

    func testSummaryFiltersChatsByUserID() {
        let summary = AnalyticsService().summary(
            threads: [
                ChatThread(
                    title: "Ada chat",
                    userID: "user-ada",
                    messages: [
                        ChatMessage(role: .user, content: "Question"),
                        ChatMessage(role: .assistant, content: "Answer", modelID: "llama3.2:latest")
                    ]
                ),
                ChatThread(
                    title: "Grace chat",
                    userID: "user-grace",
                    messages: [
                        ChatMessage(role: .user, content: "Other question"),
                        ChatMessage(role: .assistant, content: "Other answer", modelID: "mistral:latest")
                    ]
                )
            ],
            feedbacks: [],
            knowledgeCollections: [],
            knowledgeDocuments: [:],
            channels: [],
            notes: [],
            automations: [],
            calendars: [],
            calendarEvents: [],
            filter: AnalyticsFilter(userIDs: [" user-ada "])
        )

        XCTAssertEqual(summary.totalChats, 1)
        XCTAssertEqual(summary.totalMessages, 2)
        XCTAssertEqual(summary.modelUsage.map(\.modelID), ["llama3.2:latest"])
    }

    func testSummaryFiltersChatsByAdminGroupMembership() {
        let group = AdminGroup(
            id: "knowledge-editors",
            name: "Knowledge Editors",
            description: "",
            memberIDs: ["user-ada", "user-linus"]
        )

        let summary = AnalyticsService().summary(
            threads: [
                ChatThread(
                    title: "Ada chat",
                    userID: "user-ada",
                    messages: [
                        ChatMessage(role: .assistant, content: "Answer", modelID: "llama3.2:latest")
                    ]
                ),
                ChatThread(
                    title: "Grace chat",
                    userID: "user-grace",
                    messages: [
                        ChatMessage(role: .assistant, content: "Other answer", modelID: "mistral:latest")
                    ]
                )
            ],
            feedbacks: [],
            knowledgeCollections: [],
            knowledgeDocuments: [:],
            channels: [],
            notes: [],
            automations: [],
            calendars: [],
            calendarEvents: [],
            adminGroups: [group],
            filter: AnalyticsFilter(groupIDs: ["knowledge-editors"])
        )

        XCTAssertEqual(summary.totalChats, 1)
        XCTAssertEqual(summary.assistantMessages, 1)
        XCTAssertEqual(summary.modelUsage.map(\.modelID), ["llama3.2:latest"])
    }

    func testModelChatDrilldownFiltersByAnalyticsFilter() {
        let service = AnalyticsService()
        let adaThreadID = UUID()

        let chats = service.modelChats(
            modelID: "llama3.2:latest",
            threads: [
                ChatThread(
                    id: adaThreadID,
                    title: "Ada llama chat",
                    userID: "user-ada",
                    messages: [
                        ChatMessage(role: .assistant, content: "Answer", modelID: "llama3.2:latest")
                    ]
                ),
                ChatThread(
                    title: "Grace llama chat",
                    userID: "user-grace",
                    messages: [
                        ChatMessage(role: .assistant, content: "Other answer", modelID: "llama3.2:latest")
                    ]
                )
            ],
            filter: AnalyticsFilter(userIDs: ["user-ada"])
        )

        XCTAssertEqual(chats.map(\.threadID), [adaThreadID])
        XCTAssertEqual(chats.map(\.title), ["Ada llama chat"])
    }

    func testModelChatDrilldownBuildsRecentChatsForModel() {
        let olderDate = Date(timeIntervalSince1970: 100)
        let newerDate = Date(timeIntervalSince1970: 200)
        let firstThreadID = UUID()
        let secondThreadID = UUID()
        let service = AnalyticsService()

        let chats = service.modelChats(
            modelID: "llama3.2:latest",
            threads: [
                ChatThread(
                    id: firstThreadID,
                    title: "Older llama chat",
                    messages: [
                        ChatMessage(
                            role: .assistant,
                            content: "Older answer",
                            modelID: "llama3.2:latest",
                            createdAt: olderDate,
                            tokenUsage: ChatTokenUsage(promptTokens: 5, completionTokens: 4, totalTokens: 9)
                        ),
                        ChatMessage(role: .assistant, content: "Other model", modelID: "mistral:latest")
                    ]
                ),
                ChatThread(
                    id: secondThreadID,
                    title: "Newer llama chat",
                    messages: [
                        ChatMessage(
                            role: .assistant,
                            content: "Newer answer one",
                            modelID: "llama3.2:latest",
                            createdAt: newerDate.addingTimeInterval(-10),
                            tokenUsage: ChatTokenUsage(promptTokens: 7, completionTokens: 3, totalTokens: 10)
                        ),
                        ChatMessage(
                            role: .assistant,
                            content: "Newer answer two",
                            modelID: "llama3.2:latest",
                            createdAt: newerDate,
                            tokenUsage: ChatTokenUsage(promptTokens: 11, completionTokens: 9, totalTokens: 20)
                        )
                    ]
                )
            ]
        )

        XCTAssertEqual(chats.map(\.threadID), [secondThreadID, firstThreadID])
        XCTAssertEqual(chats.map(\.title), ["Newer llama chat", "Older llama chat"])
        XCTAssertEqual(chats.map(\.messageCount), [2, 1])
        XCTAssertEqual(chats.map(\.totalTokens), [30, 9])
        XCTAssertEqual(chats.first?.lastMessageAt, newerDate)
    }

    func testSummaryBuildsDailyModelUsageSortedByDate() {
        let firstDay = Date(timeIntervalSince1970: 1_704_067_200) // 2024-01-01T00:00:00Z
        let secondDay = Date(timeIntervalSince1970: 1_704_153_600) // 2024-01-02T00:00:00Z

        let summary = AnalyticsService().summary(
            threads: [
                ChatThread(
                    title: "Daily",
                    messages: [
                        ChatMessage(role: .assistant, content: "A", modelID: "llama3.2:latest", createdAt: firstDay),
                        ChatMessage(role: .assistant, content: "B", modelID: "mistral:latest", createdAt: firstDay.addingTimeInterval(60)),
                        ChatMessage(role: .assistant, content: "C", modelID: "llama3.2:latest", createdAt: firstDay.addingTimeInterval(120)),
                        ChatMessage(role: .user, content: "Ignored for model usage", createdAt: firstDay.addingTimeInterval(180)),
                        ChatMessage(role: .assistant, content: "D", modelID: "mistral:latest", createdAt: secondDay)
                    ]
                )
            ],
            feedbacks: [],
            knowledgeCollections: [],
            knowledgeDocuments: [:],
            channels: [],
            notes: [],
            automations: [],
            calendars: [],
            calendarEvents: []
        )

        XCTAssertEqual(summary.dailyModelUsage.map(\.date), ["2024-01-01", "2024-01-02"])
        XCTAssertEqual(summary.dailyModelUsage.first?.models, ["llama3.2:latest": 2, "mistral:latest": 1])
        XCTAssertEqual(summary.dailyModelUsage.last?.models, ["mistral:latest": 1])
    }

    func testAnalyticsExportJSONIncludesSummaryAndDailyModelUsage() throws {
        let summary = AnalyticsSummary(
            totalChats: 1,
            activeChats: 1,
            archivedChats: 0,
            pinnedChats: 0,
            totalMessages: 2,
            userMessages: 1,
            assistantMessages: 1,
            systemMessages: 0,
            totalModels: 1,
            totalPromptTokens: 0,
            totalCompletionTokens: 0,
            totalTokens: 0,
            modelUsage: [
                AnalyticsModelUsage(modelID: "llama3.2:latest", messageCount: 1, chatCount: 1)
            ],
            dailyModelUsage: [
                AnalyticsDailyModelUsage(date: "2024-01-01", models: ["llama3.2:latest": 1])
            ],
            feedbackRecords: 0,
            positiveFeedback: 0,
            negativeFeedback: 0,
            knowledgeCollections: 0,
            knowledgeDocuments: 0,
            channels: 0,
            channelMessages: 0,
            channelReplies: 0,
            notes: 0,
            automations: 0,
            activeAutomations: 0,
            calendars: 0,
            calendarEvents: 0
        )

        let data = try AnalyticsExportService().jsonData(
            for: summary,
            exportedAt: Date(timeIntervalSince1970: 1_704_067_200)
        )
        let bundle = try JSONDecoder().decode(AnalyticsExportBundle.self, from: data)

        XCTAssertEqual(bundle.version, 1)
        XCTAssertEqual(bundle.exportedAt, Date(timeIntervalSince1970: 1_704_067_200))
        XCTAssertEqual(bundle.summary.totalChats, 1)
        XCTAssertEqual(bundle.summary.modelUsage.first?.modelID, "llama3.2:latest")
        XCTAssertEqual(bundle.summary.dailyModelUsage.first?.models["llama3.2:latest"], 1)
    }

    func testAnalyticsExportJSONIncludesWebSearchNetworkSummary() throws {
        let networkSummary = WebSearchNetworkHistorySummary(events: [
            AppAuditEvent(
                action: .webSearchRun,
                outcome: .succeeded,
                summary: "Web search completed",
                metadata: [
                    "contactedHosts": "api.search.brave.com, example.com",
                    "usedAPIKey": "true"
                ],
                createdAt: Date(timeIntervalSince1970: 20)
            ),
            AppAuditEvent(
                action: .webSearchRun,
                outcome: .blocked,
                summary: "Web search blocked",
                metadata: [
                    "contactedHosts": "none",
                    "usedAPIKey": "false"
                ],
                createdAt: Date(timeIntervalSince1970: 10)
            )
        ])

        let data = try AnalyticsExportService().jsonData(
            for: .empty,
            webSearchNetworkSummary: networkSummary,
            exportedAt: Date(timeIntervalSince1970: 1_704_067_200)
        )
        let bundle = try JSONDecoder().decode(AnalyticsExportBundle.self, from: data)

        XCTAssertEqual(bundle.webSearchNetworkSummary.totalRuns, 2)
        XCTAssertEqual(bundle.webSearchNetworkSummary.blockedRuns, 1)
        XCTAssertEqual(bundle.webSearchNetworkSummary.apiKeyRuns, 1)
        XCTAssertEqual(bundle.webSearchNetworkSummary.topHosts, [
            WebSearchNetworkHostSummary(host: "api.search.brave.com", runCount: 1),
            WebSearchNetworkHostSummary(host: "example.com", runCount: 1)
        ])
    }

    func testAnalyticsExportBundleDecodesOlderBundlesWithoutNetworkSummary() throws {
        let legacyJSON = """
        {
          "version": 1,
          "exportedAt": 1704067200,
          "summary": {
            "totalChats": 0,
            "activeChats": 0,
            "archivedChats": 0,
            "pinnedChats": 0,
            "totalMessages": 0,
            "userMessages": 0,
            "assistantMessages": 0,
            "systemMessages": 0,
            "totalModels": 0,
            "totalPromptTokens": 0,
            "totalCompletionTokens": 0,
            "totalTokens": 0,
            "modelUsage": [],
            "dailyModelUsage": [],
            "feedbackRecords": 0,
            "positiveFeedback": 0,
            "negativeFeedback": 0,
            "knowledgeCollections": 0,
            "knowledgeDocuments": 0,
            "channels": 0,
            "channelMessages": 0,
            "channelReplies": 0,
            "notes": 0,
            "automations": 0,
            "activeAutomations": 0,
            "calendars": 0,
            "calendarEvents": 0
          }
        }
        """.data(using: .utf8)!

        let bundle = try JSONDecoder().decode(AnalyticsExportBundle.self, from: legacyJSON)

        XCTAssertEqual(bundle.webSearchNetworkSummary, WebSearchNetworkHistorySummary(events: []))
    }

    func testSelectAnalyticsDashboardClearsOtherSelections() async throws {
        let store = AppStore(secretStore: InMemorySecretStore())
        let threadID = UUID()
        let channelID = UUID()
        let collection = KnowledgeCollection(name: "Docs")
        let document = KnowledgeDocument(
            collectionID: collection.id,
            fileName: "guide.md",
            contentType: "text/markdown",
            byteCount: 10
        )

        store.threads = [ChatThread(id: threadID, title: "Selected")]
        store.channels = [AppChannel(id: channelID, name: "Team")]
        store.selectedThreadID = threadID
        store.selectedChannelID = channelID
        store.selectedKnowledgeDocumentDetail = KnowledgeDocumentDetail(collection: collection, document: document, chunks: [])
        store.isShowingEvaluationDashboard = true
        store.isShowingCalendar = true

        store.selectAnalyticsDashboard()

        XCTAssertTrue(store.isShowingAnalyticsDashboard)
        XCTAssertFalse(store.isShowingEvaluationDashboard)
        XCTAssertFalse(store.isShowingCalendar)
        XCTAssertNil(store.selectedThreadID)
        XCTAssertNil(store.selectedChannelID)
        XCTAssertNil(store.selectedKnowledgeDocumentDetail)
    }

    func testOpenAnalyticsModelChatSelectsThreadAndClosesAnalyticsDashboard() {
        let store = AppStore(secretStore: InMemorySecretStore())
        let threadID = UUID()
        store.threads = [ChatThread(id: threadID, title: "Model chat")]
        store.isShowingAnalyticsDashboard = true

        store.openAnalyticsModelChat(threadID: threadID)

        XCTAssertEqual(store.selectedThreadID, threadID)
        XCTAssertFalse(store.isShowingAnalyticsDashboard)
    }

    func testAppStoreAnalyticsSummaryUsesActiveUserFilter() {
        let store = AppStore(secretStore: InMemorySecretStore())
        store.threads = [
            ChatThread(
                title: "Ada chat",
                userID: "user-ada",
                messages: [
                    ChatMessage(role: .assistant, content: "Answer", modelID: "llama3.2:latest")
                ]
            ),
            ChatThread(
                title: "Grace chat",
                userID: "user-grace",
                messages: [
                    ChatMessage(role: .assistant, content: "Other answer", modelID: "mistral:latest")
                ]
            )
        ]

        store.setAnalyticsUserFilter("user-ada")

        XCTAssertEqual(store.analyticsSummary.totalChats, 1)
        XCTAssertEqual(store.analyticsSummary.modelUsage.map(\.modelID), ["llama3.2:latest"])
    }
}
