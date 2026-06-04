import XCTest
@testable import OpenWebUINative

@MainActor
final class AppStoreAutomationTests: XCTestCase {
    func testCreateAutomationPersistsAndReloads() async throws {
        let fixture = try AutomationFixture()
        let store = fixture.makeStore()
        await store.load()

        await store.createAutomation(
            name: "Daily summary",
            prompt: "Summarize yesterday's notes.",
            modelID: "llama3.2",
            rrule: "FREQ=DAILY;INTERVAL=1",
            isActive: true
        )

        XCTAssertEqual(store.automations.map(\.name), ["Daily summary"])
        XCTAssertEqual(store.automations.first?.prompt, "Summarize yesterday's notes.")
        XCTAssertEqual(store.automations.first?.modelID, "llama3.2")
        XCTAssertEqual(store.automations.first?.rrule, "FREQ=DAILY;INTERVAL=1")
        XCTAssertTrue(store.automations.first?.isActive ?? false)

        let reloadedStore = fixture.makeStore()
        await reloadedStore.load()

        XCTAssertEqual(reloadedStore.automations.map(\.name), ["Daily summary"])
        XCTAssertEqual(reloadedStore.automations.first?.prompt, "Summarize yesterday's notes.")
    }

    func testCreateAutomationRejectsUnsupportedSchedule() async throws {
        let fixture = try AutomationFixture()
        let store = fixture.makeStore()
        await store.load()

        await store.createAutomation(
            name: "Monthly summary",
            prompt: "Summarize this month's notes.",
            modelID: "llama3.2",
            rrule: "FREQ=MONTHLY;BYMONTHDAY=1",
            isActive: true
        )

        XCTAssertTrue(store.automations.isEmpty)
        XCTAssertEqual(store.errorMessage, "Only DAILY and WEEKLY schedules are supported.")
    }

    func testUpdateToggleAndDeleteAutomationPersists() async throws {
        let fixture = try AutomationFixture()
        let store = fixture.makeStore()
        await store.load()
        await store.createAutomation(
            name: "Draft",
            prompt: "Initial prompt",
            modelID: "llama3.2",
            rrule: "FREQ=WEEKLY",
            isActive: true
        )
        let automation = try XCTUnwrap(store.automations.first)

        await store.updateAutomation(
            automation.id,
            name: "  Weekly research  ",
            prompt: "  Prepare the research brief.  ",
            modelID: "  gpt-4.1-mini  ",
            rrule: "  FREQ=WEEKLY;BYDAY=MO  ",
            isActive: false
        )

        XCTAssertEqual(store.automations.first?.name, "Weekly research")
        XCTAssertEqual(store.automations.first?.prompt, "Prepare the research brief.")
        XCTAssertEqual(store.automations.first?.modelID, "gpt-4.1-mini")
        XCTAssertEqual(store.automations.first?.rrule, "FREQ=WEEKLY;BYDAY=MO")
        XCTAssertFalse(store.automations.first?.isActive ?? true)

        await store.toggleAutomation(automation.id)
        XCTAssertTrue(store.automations.first?.isActive ?? false)

        let reloadedStore = fixture.makeStore()
        await reloadedStore.load()
        XCTAssertTrue(reloadedStore.automations.first?.isActive ?? false)

        await reloadedStore.deleteAutomation(automation.id)

        let deletedStore = fixture.makeStore()
        await deletedStore.load()
        XCTAssertTrue(deletedStore.automations.isEmpty)
    }

    func testAutomationLifecycleChangesCreateAuditEventsWithoutPromptContent() async throws {
        let fixture = try AutomationFixture()
        let store = fixture.makeStore()
        await store.load()

        await store.createAutomation(
            name: "Private strategy summary",
            prompt: "Summarize confidential roadmap details.",
            modelID: "llama3.2",
            rrule: "FREQ=DAILY",
            isActive: true
        )
        let automation = try XCTUnwrap(store.automations.first)
        await store.updateAutomation(
            automation.id,
            name: "Private strategy digest",
            prompt: "Summarize confidential roadmap details.",
            modelID: "gpt-4.1-mini",
            rrule: "FREQ=WEEKLY;BYDAY=MO",
            isActive: false
        )
        await store.toggleAutomation(automation.id)
        await store.deleteAutomation(automation.id)

        let lifecycleEvents = store.auditEvents.filter {
            [
                "automationCreated",
                "automationUpdated",
                "automationStatusUpdated",
                "automationDeleted"
            ].contains($0.action.rawValue)
        }
        XCTAssertEqual(Set(lifecycleEvents.map(\.action.rawValue)), [
            "automationCreated",
            "automationUpdated",
            "automationStatusUpdated",
            "automationDeleted"
        ])

        let createdEvent = try XCTUnwrap(lifecycleEvents.first { $0.action.rawValue == "automationCreated" })
        XCTAssertEqual(createdEvent.summary, "Created automation")
        XCTAssertEqual(createdEvent.metadata["automationID"], automation.id)
        XCTAssertEqual(createdEvent.metadata["modelID"], "llama3.2")
        XCTAssertEqual(createdEvent.metadata["rrule"], "FREQ=DAILY")
        XCTAssertEqual(createdEvent.metadata["isActive"], "true")

        let updatedEvent = try XCTUnwrap(lifecycleEvents.first { $0.action.rawValue == "automationUpdated" })
        XCTAssertEqual(updatedEvent.summary, "Updated automation")
        XCTAssertEqual(updatedEvent.metadata["modelID"], "gpt-4.1-mini")
        XCTAssertEqual(updatedEvent.metadata["previousModelID"], "llama3.2")
        XCTAssertEqual(updatedEvent.metadata["rrule"], "FREQ=WEEKLY;BYDAY=MO")
        XCTAssertEqual(updatedEvent.metadata["previousRRule"], "FREQ=DAILY")
        XCTAssertEqual(updatedEvent.metadata["isActive"], "false")
        XCTAssertEqual(updatedEvent.metadata["previousIsActive"], "true")

        let statusEvent = try XCTUnwrap(lifecycleEvents.first { $0.action.rawValue == "automationStatusUpdated" })
        XCTAssertEqual(statusEvent.summary, "Updated automation status")
        XCTAssertEqual(statusEvent.metadata["isActive"], "true")
        XCTAssertEqual(statusEvent.metadata["previousIsActive"], "false")

        let deletedEvent = try XCTUnwrap(lifecycleEvents.first { $0.action.rawValue == "automationDeleted" })
        XCTAssertEqual(deletedEvent.summary, "Deleted automation")
        XCTAssertEqual(deletedEvent.metadata["automationID"], automation.id)

        for auditEvent in lifecycleEvents {
            XCTAssertFalse(auditEvent.summary.contains("Private strategy"))
            XCTAssertFalse(auditEvent.metadata.values.contains("Private strategy summary"))
            XCTAssertFalse(auditEvent.metadata.values.contains("Private strategy digest"))
            XCTAssertFalse(auditEvent.metadata.values.contains("Summarize confidential roadmap details."))
        }

        let reloadedEvents = try await fixture.auditStorage.loadEvents()
        XCTAssertTrue(reloadedEvents.contains { $0.action.rawValue == "automationCreated" && $0.metadata["automationID"] == automation.id })
        XCTAssertTrue(reloadedEvents.contains { $0.action.rawValue == "automationUpdated" && $0.metadata["automationID"] == automation.id })
        XCTAssertTrue(reloadedEvents.contains { $0.action.rawValue == "automationStatusUpdated" && $0.metadata["automationID"] == automation.id })
        XCTAssertTrue(reloadedEvents.contains { $0.action.rawValue == "automationDeleted" && $0.metadata["automationID"] == automation.id })
    }

    func testUpdateAutomationRejectsUnsupportedScheduleAndKeepsExistingRule() async throws {
        let fixture = try AutomationFixture()
        let store = fixture.makeStore()
        await store.load()
        await store.createAutomation(
            name: "Daily summary",
            prompt: "Summarize notes.",
            modelID: "llama3.2",
            rrule: "FREQ=DAILY",
            isActive: true
        )
        let automation = try XCTUnwrap(store.automations.first)

        await store.updateAutomation(
            automation.id,
            name: "Monthly summary",
            prompt: "Summarize this month.",
            modelID: "llama3.2",
            rrule: "FREQ=MONTHLY;BYMONTHDAY=1",
            isActive: true
        )

        XCTAssertEqual(store.automations.first?.name, "Daily summary")
        XCTAssertEqual(store.automations.first?.rrule, "FREQ=DAILY")
        XCTAssertEqual(store.errorMessage, "Only DAILY and WEEKLY schedules are supported.")
    }

    func testExportAndImportAutomationsJSONRoundTripsAutomations() async throws {
        let fixture = try AutomationFixture()
        let store = fixture.makeStore()
        await store.load()
        await store.createAutomation(
            name: "Daily summary",
            prompt: "Summarize yesterday's notes.",
            modelID: "llama3.2",
            rrule: "FREQ=DAILY",
            isActive: true
        )
        await store.createAutomation(
            name: "Weekly plan",
            prompt: "Prepare the weekly plan.",
            modelID: "mistral",
            rrule: "FREQ=WEEKLY;BYDAY=MO",
            isActive: false
        )

        let data = try store.exportAutomationsJSONData()

        let importFixture = try AutomationFixture()
        let importStore = importFixture.makeStore()
        await importStore.load()
        try await importStore.importAutomationsJSONData(data)

        XCTAssertEqual(Set(importStore.automations.map(\.name)), ["Daily summary", "Weekly plan"])
        XCTAssertEqual(importStore.automations.first { $0.name == "Weekly plan" }?.prompt, "Prepare the weekly plan.")
        XCTAssertFalse(importStore.automations.first { $0.name == "Weekly plan" }?.isActive ?? true)
    }

    func testExportAutomationJSONDataExportsOnlySelectedAutomation() async throws {
        let fixture = try AutomationFixture()
        let selectedAutomation = AppAutomation(
            id: "daily-summary",
            userID: "user-id",
            name: "Daily summary",
            prompt: "Summarize yesterday's notes.",
            modelID: "llama3.2",
            rrule: "FREQ=DAILY;COUNT=3",
            meta: .object(["system_prompt": .string("Be concise.")]),
            isActive: true,
            lastRunAt: Date(timeIntervalSince1970: 1_000),
            nextRunAt: Date(timeIntervalSince1970: 2_000),
            createdAt: Date(timeIntervalSince1970: 500),
            updatedAt: Date(timeIntervalSince1970: 700)
        )
        try await fixture.automationStorage.save(selectedAutomation)
        try await fixture.automationStorage.save(
            AppAutomation(
                id: "weekly-plan",
                name: "Weekly plan",
                prompt: "Prepare the weekly plan.",
                modelID: "mistral",
                rrule: "FREQ=WEEKLY;BYDAY=MO",
                isActive: false,
                createdAt: Date(timeIntervalSince1970: 500),
                updatedAt: Date(timeIntervalSince1970: 600)
            )
        )
        let store = fixture.makeStore()
        await store.load()

        let data = try XCTUnwrap(store.exportAutomationJSONData(selectedAutomation.id))

        let importFixture = try AutomationFixture()
        let importStore = importFixture.makeStore()
        await importStore.load()
        try await importStore.importAutomationsJSONData(data)

        XCTAssertEqual(importStore.automations.map(\.name), ["Daily summary"])
        let imported = try XCTUnwrap(importStore.automations.first)
        XCTAssertEqual(imported.userID, "user-id")
        XCTAssertEqual(imported.prompt, "Summarize yesterday's notes.")
        XCTAssertEqual(imported.modelID, "llama3.2")
        XCTAssertEqual(imported.rrule, "FREQ=DAILY;COUNT=3")
        XCTAssertEqual(imported.meta?.objectValue?["system_prompt"], .string("Be concise."))
        XCTAssertTrue(imported.isActive)
        XCTAssertEqual(imported.lastRunAt, Date(timeIntervalSince1970: 1_000))
        XCTAssertEqual(imported.nextRunAt, Date(timeIntervalSince1970: 2_000))
    }

    func testExportAutomationsOpenWebUIJSONDataBuildsRawAutomationRecords() async throws {
        let fixture = try AutomationFixture()
        let automation = AppAutomation(
            id: "daily-summary",
            userID: "user-id",
            name: "Daily summary",
            prompt: "Summarize yesterday's notes.",
            modelID: "llama3.2",
            rrule: "FREQ=DAILY;COUNT=3",
            meta: .object(["system_prompt": .string("Be concise.")]),
            isActive: false,
            lastRunAt: Date(timeIntervalSince1970: 1_000),
            nextRunAt: Date(timeIntervalSince1970: 2_000),
            createdAt: Date(timeIntervalSince1970: 500),
            updatedAt: Date(timeIntervalSince1970: 700)
        )
        try await fixture.automationStorage.save(automation)
        let store = fixture.makeStore()
        await store.load()

        let data = try store.exportAutomationsOpenWebUIJSONData()
        let records = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [[String: Any]])
        let record = try XCTUnwrap(records.first)
        let recordData = try XCTUnwrap(record["data"] as? [String: Any])
        let meta = try XCTUnwrap(record["meta"] as? [String: Any])

        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(record["id"] as? String, "daily-summary")
        XCTAssertEqual(record["user_id"] as? String, "user-id")
        XCTAssertEqual(record["name"] as? String, "Daily summary")
        XCTAssertEqual(recordData["prompt"] as? String, "Summarize yesterday's notes.")
        XCTAssertEqual(recordData["model_id"] as? String, "llama3.2")
        XCTAssertEqual(recordData["rrule"] as? String, "FREQ=DAILY;COUNT=3")
        XCTAssertEqual(meta["system_prompt"] as? String, "Be concise.")
        XCTAssertEqual(record["is_active"] as? Bool, false)
        XCTAssertEqual(record["last_run_at"] as? Int, 1_000_000_000_000)
        XCTAssertEqual(record["next_run_at"] as? Int, 2_000_000_000_000)
        XCTAssertEqual(record["created_at"] as? Int, 500_000_000_000)
        XCTAssertEqual(record["updated_at"] as? Int, 700_000_000_000)
    }

    func testShareAutomationSharesSelectedAutomationJSON() async throws {
        let shareService = FakeAutomationShareService()
        let fixture = try AutomationFixture(shareService: shareService)
        let store = fixture.makeStore()
        await store.load()
        await store.createAutomation(
            name: "Daily summary",
            prompt: "Summarize yesterday's notes.",
            modelID: "llama3.2",
            rrule: "FREQ=DAILY",
            isActive: true
        )
        await store.createAutomation(
            name: "Weekly plan",
            prompt: "Prepare the weekly plan.",
            modelID: "mistral",
            rrule: "FREQ=WEEKLY;BYDAY=MO",
            isActive: false
        )
        let automation = try XCTUnwrap(store.automations.first { $0.name == "Daily summary" })

        store.shareAutomation(automation.id)

        XCTAssertEqual(shareService.sharedTitle, "Daily summary")
        let sharedText = try XCTUnwrap(shareService.sharedText)
        let sharedAutomations = try AutomationExportService().automations(fromJSONData: Data(sharedText.utf8))
        XCTAssertEqual(sharedAutomations.map(\.name), ["Daily summary"])
        XCTAssertEqual(sharedAutomations.first?.prompt, "Summarize yesterday's notes.")
        XCTAssertEqual(sharedAutomations.first?.modelID, "llama3.2")
    }

    func testImportAutomationsJSONAcceptsOpenWebUIAutomationRecords() async throws {
        let fixture = try AutomationFixture()
        let store = fixture.makeStore()
        await store.load()
        let data = Data(
            """
            [
              {
                "id": "automation-id",
                "user_id": "user-id",
                "name": "Migration summary",
                "data": {
                  "prompt": "Summarize imported Open WebUI activity.",
                  "model_id": "gpt-4.1-mini",
                  "rrule": "FREQ=DAILY;COUNT=1"
                },
                "meta": {
                  "system_prompt": "Be concise."
                },
                "is_active": false,
                "last_run_at": 1000,
                "next_run_at": 2000,
                "created_at": 3000,
                "updated_at": 4000
              }
            ]
            """.utf8
        )

        try await store.importAutomationsJSONData(data)

        let imported = try XCTUnwrap(store.automations.first)
        XCTAssertEqual(imported.id, "automation-id")
        XCTAssertEqual(imported.userID, "user-id")
        XCTAssertEqual(imported.name, "Migration summary")
        XCTAssertEqual(imported.prompt, "Summarize imported Open WebUI activity.")
        XCTAssertEqual(imported.modelID, "gpt-4.1-mini")
        XCTAssertEqual(imported.rrule, "FREQ=DAILY;COUNT=1")
        XCTAssertFalse(imported.isActive)
        XCTAssertEqual(imported.lastRunAt, Date(timeIntervalSince1970: 1000))
        XCTAssertEqual(imported.nextRunAt, Date(timeIntervalSince1970: 2000))
        XCTAssertEqual(imported.createdAt, Date(timeIntervalSince1970: 3000))
        XCTAssertEqual(imported.updatedAt, Date(timeIntervalSince1970: 4000))
        XCTAssertEqual(imported.meta, .object(["system_prompt": .string("Be concise.")]))
    }

    func testFilteredAutomationsSearchesNamePromptModelAndStatus() async throws {
        let fixture = try AutomationFixture()
        let store = fixture.makeStore()
        await store.load()
        await store.createAutomation(
            name: "Daily summary",
            prompt: "Summarize release feedback.",
            modelID: "llama3.2",
            rrule: "FREQ=DAILY",
            isActive: true
        )
        await store.createAutomation(
            name: "Paused research",
            prompt: "Read design notes.",
            modelID: "mistral",
            rrule: "FREQ=WEEKLY",
            isActive: false
        )

        XCTAssertEqual(Set(store.filteredAutomations().map(\.name)), ["Daily summary", "Paused research"])

        store.automationSearchText = "feedback"
        XCTAssertEqual(store.filteredAutomations().map(\.name), ["Daily summary"])

        store.automationSearchText = "model:mistral"
        XCTAssertEqual(store.filteredAutomations().map(\.name), ["Paused research"])

        store.automationSearchText = "status:paused"
        XCTAssertEqual(store.filteredAutomations().map(\.name), ["Paused research"])

        store.automationSearchText = "status:active"
        XCTAssertEqual(store.filteredAutomations().map(\.name), ["Daily summary"])
    }

    func testRunAutomationNowStreamsProviderResponsePersistsRunAndUpdatesLastRun() async throws {
        let provider = CapturingAutomationProvider(chunks: ["Drafted ", "summary."])
        let fixture = try AutomationFixture(provider: provider)
        let store = fixture.makeStore()
        await store.load()
        await store.createAutomation(
            name: "Daily summary",
            prompt: "Summarize release feedback.",
            modelID: "fake-model",
            rrule: "FREQ=DAILY",
            isActive: true
        )
        let automation = try XCTUnwrap(store.automations.first)

        await store.runAutomationNow(automation.id)

        let run = try XCTUnwrap(store.automationRuns.first)
        XCTAssertEqual(run.automationID, automation.id)
        XCTAssertEqual(run.automationName, "Daily summary")
        XCTAssertEqual(run.modelID, "fake-model")
        XCTAssertEqual(run.status, .succeeded)
        XCTAssertEqual(run.prompt, "Summarize release feedback.")
        XCTAssertEqual(run.output, "Drafted summary.")
        XCTAssertNil(run.errorMessage)
        XCTAssertNotNil(store.automations.first?.lastRunAt)
        XCTAssertEqual(provider.capturedPrompts, ["Summarize release feedback."])

        let reloadedStore = fixture.makeStore()
        await reloadedStore.load()

        XCTAssertEqual(reloadedStore.automationRuns.first?.output, "Drafted summary.")
        XCTAssertNotNil(reloadedStore.automations.first?.lastRunAt)
    }

    func testRunAutomationNowCreatesSucceededAuditEvent() async throws {
        let provider = CapturingAutomationProvider(chunks: ["Drafted summary."])
        let fixture = try AutomationFixture(provider: provider)
        let store = fixture.makeStore()
        await store.load()
        await store.createAutomation(
            name: "Daily summary",
            prompt: "Summarize release feedback.",
            modelID: "fake-model",
            rrule: "FREQ=DAILY",
            isActive: true
        )
        let automation = try XCTUnwrap(store.automations.first)

        await store.runAutomationNow(automation.id)

        let event = try XCTUnwrap(store.auditEvents.first)
        let run = try XCTUnwrap(store.automationRuns.first)
        XCTAssertEqual(event.action, .automationRun)
        XCTAssertEqual(event.outcome, .succeeded)
        XCTAssertEqual(event.metadata["automationID"], automation.id)
        XCTAssertEqual(event.metadata["modelID"], "fake-model")
        XCTAssertEqual(event.metadata["runID"], run.id)
        XCTAssertTrue(event.summary.contains("Daily summary"))
    }

    func testRunAutomationNowPersistsFailedRunWhenProviderThrows() async throws {
        let provider = CapturingAutomationProvider(chunks: [], error: ProviderError.invalidResponse)
        let fixture = try AutomationFixture(provider: provider)
        let store = fixture.makeStore()
        await store.load()
        await store.createAutomation(
            name: "Daily summary",
            prompt: "Summarize release feedback.",
            modelID: "fake-model",
            rrule: "FREQ=DAILY",
            isActive: true
        )
        let automation = try XCTUnwrap(store.automations.first)

        await store.runAutomationNow(automation.id)

        let run = try XCTUnwrap(store.automationRuns.first)
        XCTAssertEqual(run.status, .failed)
        XCTAssertEqual(run.output, "")
        XCTAssertNotNil(run.errorMessage)
        XCTAssertNotNil(run.completedAt)
        XCTAssertNotNil(store.errorMessage)
    }

    func testRunAutomationNowBlocksUnsupportedChatProviderBeforeStreaming() async throws {
        let provider = UnsupportedAutomationChatProvider()
        let fixture = try AutomationFixture(provider: provider)
        let store = fixture.makeStore()
        await store.load()
        await store.createAutomation(
            name: "Daily summary",
            prompt: "Summarize release feedback.",
            modelID: "fake-model",
            rrule: "FREQ=DAILY",
            isActive: true
        )
        let automation = try XCTUnwrap(store.automations.first)

        await store.runAutomationNow(automation.id)

        let run = try XCTUnwrap(store.automationRuns.first)
        XCTAssertEqual(run.status, .failed)
        XCTAssertEqual(run.output, "")
        XCTAssertEqual(run.errorMessage, "Ollama does not support native chat.")
        XCTAssertEqual(store.errorMessage, "Ollama does not support native chat.")
        XCTAssertNil(store.automations.first?.lastRunAt)
        XCTAssertEqual(provider.streamCallCount, 0)
    }

    func testRunAutomationNowCreatesFailedAuditEvent() async throws {
        let provider = CapturingAutomationProvider(chunks: [], error: ProviderError.invalidResponse)
        let fixture = try AutomationFixture(provider: provider)
        let store = fixture.makeStore()
        await store.load()
        await store.createAutomation(
            name: "Daily summary",
            prompt: "Summarize release feedback.",
            modelID: "fake-model",
            rrule: "FREQ=DAILY",
            isActive: true
        )
        let automation = try XCTUnwrap(store.automations.first)

        await store.runAutomationNow(automation.id)

        let event = try XCTUnwrap(store.auditEvents.first)
        let run = try XCTUnwrap(store.automationRuns.first)
        XCTAssertEqual(event.action, .automationRun)
        XCTAssertEqual(event.outcome, .failed)
        XCTAssertEqual(event.metadata["automationID"], automation.id)
        XCTAssertEqual(event.metadata["modelID"], "fake-model")
        XCTAssertEqual(event.metadata["runID"], run.id)
        XCTAssertEqual(try XCTUnwrap(event.metadata["error"]), "The provider returned an invalid response.")
        XCTAssertEqual(event.metadata["error"], run.errorMessage)
        XCTAssertTrue(event.summary.contains("Daily summary"))
    }

    func testRunDueAutomationsRunsOnlyPastDueActiveAutomationsAndSchedulesNextRun() async throws {
        let provider = CapturingAutomationProvider(chunks: ["done"])
        let fixture = try AutomationFixture(provider: provider)
        let store = fixture.makeStore()
        await store.load()
        let now = Date(timeIntervalSince1970: 2_000)
        try await fixture.automationStorage.save(
            AppAutomation(
                id: "due",
                name: "Due summary",
                prompt: "Summarize release feedback.",
                modelID: "fake-model",
                rrule: "FREQ=DAILY",
                isActive: true,
                nextRunAt: Date(timeIntervalSince1970: 1_000),
                createdAt: Date(timeIntervalSince1970: 500),
                updatedAt: Date(timeIntervalSince1970: 500)
            )
        )
        try await fixture.automationStorage.save(
            AppAutomation(
                id: "paused",
                name: "Paused summary",
                prompt: "Do not run.",
                modelID: "fake-model",
                rrule: "FREQ=DAILY",
                isActive: false,
                nextRunAt: Date(timeIntervalSince1970: 1_000),
                createdAt: Date(timeIntervalSince1970: 500),
                updatedAt: Date(timeIntervalSince1970: 500)
            )
        )
        await store.load()

        await store.runDueAutomations(at: now)

        XCTAssertEqual(provider.capturedPrompts, ["Summarize release feedback."])
        XCTAssertEqual(store.automationRuns.map(\.automationID), ["due"])
        let dueAutomation = try XCTUnwrap(store.automations.first { $0.id == "due" })
        XCTAssertNotNil(dueAutomation.lastRunAt)
        XCTAssertNotNil(dueAutomation.nextRunAt)
        XCTAssertGreaterThan(dueAutomation.nextRunAt ?? .distantPast, now)
        XCTAssertNil(store.automations.first { $0.id == "paused" }?.lastRunAt)
    }

    func testAutomationSchedulerRunsDueAutomationsWhileActiveAndCanStop() async throws {
        let provider = CapturingAutomationProvider(chunks: ["scheduled"])
        let fixture = try AutomationFixture(provider: provider)
        let store = fixture.makeStore()
        try await fixture.automationStorage.save(
            AppAutomation(
                id: "due",
                name: "Scheduled summary",
                prompt: "Run on schedule.",
                modelID: "fake-model",
                rrule: "FREQ=DAILY",
                isActive: true,
                nextRunAt: Date(timeIntervalSince1970: 1_000),
                createdAt: Date(timeIntervalSince1970: 500),
                updatedAt: Date(timeIntervalSince1970: 500)
            )
        )
        await store.load()

        store.startAutomationScheduler(intervalNanoseconds: 1_000_000)
        for _ in 0..<50 where provider.capturedPrompts.isEmpty {
            try await Task.sleep(nanoseconds: 20_000_000)
        }

        XCTAssertTrue(store.isAutomationSchedulerRunning)
        XCTAssertEqual(provider.capturedPrompts, ["Run on schedule."])
        store.stopAutomationScheduler()
        XCTAssertFalse(store.isAutomationSchedulerRunning)
    }

    func testAutomationSchedulerDoesNotRunWhenAutomationFeatureIsDisabled() async throws {
        let provider = CapturingAutomationProvider(chunks: ["scheduled"])
        let fixture = try AutomationFixture(provider: provider)
        let store = fixture.makeStore()
        try await fixture.automationStorage.save(
            AppAutomation(
                id: "due",
                name: "Disabled feature summary",
                prompt: "Do not run.",
                modelID: "fake-model",
                rrule: "FREQ=DAILY",
                isActive: true,
                nextRunAt: Date(timeIntervalSince1970: 1_000),
                createdAt: Date(timeIntervalSince1970: 500),
                updatedAt: Date(timeIntervalSince1970: 500)
            )
        )
        await store.load()
        await store.setFeatureToggle(.automations, isEnabled: false)

        store.startAutomationScheduler(intervalNanoseconds: 1_000_000)
        try await Task.sleep(nanoseconds: 30_000_000)

        XCTAssertFalse(store.isAutomationSchedulerRunning)
        XCTAssertTrue(provider.capturedPrompts.isEmpty)
        XCTAssertTrue(store.automationRuns.isEmpty)
    }

    func testDisablingAutomationFeatureStopsRunningScheduler() async throws {
        let fixture = try AutomationFixture()
        let store = fixture.makeStore()
        await store.load()
        store.startAutomationScheduler(intervalNanoseconds: 1_000_000)
        XCTAssertTrue(store.isAutomationSchedulerRunning)

        await store.setFeatureToggle(.automations, isEnabled: false)

        XCTAssertFalse(store.isAutomationSchedulerRunning)
    }

    func testAutomationActionsBlockDisabledFeatureBeforeProviderOrPersistenceChanges() async throws {
        let provider = CapturingAutomationProvider(chunks: ["Should not stream."])
        let shareService = FakeAutomationShareService()
        let fixture = try AutomationFixture(provider: provider, shareService: shareService)
        let store = fixture.makeStore()
        await store.load()
        await store.createAutomation(
            name: "Existing",
            prompt: "Existing prompt.",
            modelID: "fake-model",
            rrule: "FREQ=DAILY",
            isActive: false
        )
        let automation = try XCTUnwrap(store.automations.first)
        let importData = try AutomationExportService().jsonData(for: [
            AppAutomation(name: "Blocked import", prompt: "Imported prompt.", modelID: "fake-model", rrule: "FREQ=DAILY")
        ])

        await store.setFeatureToggle(.automations, isEnabled: false)
        await store.createAutomation(
            name: "Blocked create",
            prompt: "Created prompt.",
            modelID: "fake-model",
            rrule: "FREQ=DAILY",
            isActive: true
        )
        await store.updateAutomation(
            automation.id,
            name: "Blocked update",
            prompt: "Updated prompt.",
            modelID: "fake-model",
            rrule: "FREQ=WEEKLY",
            isActive: true
        )
        await store.toggleAutomation(automation.id)
        await store.runAutomationNow(automation.id)
        await store.runDueAutomations(at: Date(timeIntervalSince1970: 4_000))
        try await store.importAutomationsJSONData(importData)
        store.shareAutomation(automation.id)
        await store.deleteAutomation(automation.id)

        let unchangedAutomation = try XCTUnwrap(store.automations.first)
        XCTAssertEqual(store.automations.count, 1)
        XCTAssertEqual(unchangedAutomation.name, "Existing")
        XCTAssertEqual(unchangedAutomation.prompt, "Existing prompt.")
        XCTAssertEqual(unchangedAutomation.rrule, "FREQ=DAILY")
        XCTAssertFalse(unchangedAutomation.isActive)
        XCTAssertNil(unchangedAutomation.lastRunAt)
        XCTAssertTrue(store.automationRuns.isEmpty)
        XCTAssertTrue(provider.capturedPrompts.isEmpty)
        XCTAssertNil(shareService.sharedText)
        XCTAssertNil(shareService.sharedTitle)
        XCTAssertEqual(store.errorMessage, "Automations is disabled.")

        let persistedAutomations = try await fixture.automationStorage.loadAutomations()
        let persistedRuns = try await fixture.automationRunStorage.loadRuns()
        XCTAssertEqual(persistedAutomations.map(\.name), ["Existing"])
        XCTAssertTrue(persistedRuns.isEmpty)
    }

    func testAutomationWritePermissionAllowsCreateUpdateToggleRunDeleteAndImportForCurrentUser() async throws {
        let provider = CapturingAutomationProvider(chunks: ["Done."])
        let fixture = try AutomationFixture(provider: provider)
        let store = fixture.makeStore()
        await store.load()
        await store.createAdminUser(name: "Workspace User", email: "user@example.com", role: .user)
        let user = try XCTUnwrap(store.adminUsers.first)
        await store.createAdminGroup(name: "Automation Editors", description: "Can manage automations.", permissions: ["automations.write"])
        let group = try XCTUnwrap(store.adminGroups.first)
        await store.setAdminGroupMembers(group.id, memberIDs: [user.id])
        store.currentUserID = user.id

        await store.createAutomation(
            name: "Daily summary",
            prompt: "Summarize release feedback.",
            modelID: "fake-model",
            rrule: "FREQ=DAILY",
            isActive: false
        )
        let automation = try XCTUnwrap(store.automations.first)
        await store.updateAutomation(
            automation.id,
            name: "Release summary",
            prompt: "Summarize release notes.",
            modelID: "fake-model",
            rrule: "FREQ=WEEKLY;BYDAY=MO",
            isActive: false
        )
        await store.toggleAutomation(automation.id)
        await store.runAutomationNow(automation.id)
        await store.deleteAutomation(automation.id)

        let data = try AutomationExportService().jsonData(for: [
            AppAutomation(name: "Imported", prompt: "Imported prompt.", modelID: "fake-model", rrule: "FREQ=DAILY")
        ])
        try await store.importAutomationsJSONData(data)

        XCTAssertEqual(store.automations.map(\.name), ["Imported"])
        XCTAssertEqual(provider.capturedPrompts, ["Summarize release notes."])
        XCTAssertNil(store.errorMessage)
    }

    func testAutomationWritePermissionBlocksCreateUpdateToggleRunDeleteAndImportForCurrentUser() async throws {
        let provider = CapturingAutomationProvider(chunks: ["Blocked."])
        let fixture = try AutomationFixture(provider: provider)
        let store = fixture.makeStore()
        await store.load()
        await store.createAdminUser(name: "Workspace User", email: "user@example.com", role: .user)
        let user = try XCTUnwrap(store.adminUsers.first)
        store.currentUserID = user.id

        await store.createAutomation(
            name: "Blocked",
            prompt: "Should not persist.",
            modelID: "fake-model",
            rrule: "FREQ=DAILY",
            isActive: true
        )

        XCTAssertTrue(store.automations.isEmpty)
        XCTAssertEqual(store.errorMessage, "You do not have permission to manage automations.")

        store.errorMessage = nil
        store.currentUserID = "local-admin"
        await store.createAdminUser(name: "Local Admin", email: "admin@example.com", role: .admin)
        let admin = try XCTUnwrap(store.adminUsers.first { $0.role == .admin })
        store.currentUserID = admin.id
        await store.createAutomation(
            name: "Existing",
            prompt: "Existing prompt.",
            modelID: "fake-model",
            rrule: "FREQ=DAILY",
            isActive: false
        )
        let automation = try XCTUnwrap(store.automations.first)
        let importData = try AutomationExportService().jsonData(for: [
            AppAutomation(name: "Blocked Import", prompt: "Imported prompt.", modelID: "fake-model", rrule: "FREQ=DAILY")
        ])

        store.currentUserID = user.id
        await store.updateAutomation(
            automation.id,
            name: "Blocked update",
            prompt: "Blocked prompt.",
            modelID: "fake-model",
            rrule: "FREQ=WEEKLY",
            isActive: true
        )
        await store.toggleAutomation(automation.id)
        await store.runAutomationNow(automation.id)
        await store.runDueAutomations(at: Date(timeIntervalSince1970: 4_000))
        try await store.importAutomationsJSONData(importData)
        await store.deleteAutomation(automation.id)

        let unchangedAutomation = try XCTUnwrap(store.automations.first)
        XCTAssertEqual(store.automations.count, 1)
        XCTAssertEqual(unchangedAutomation.name, "Existing")
        XCTAssertEqual(unchangedAutomation.prompt, "Existing prompt.")
        XCTAssertEqual(unchangedAutomation.rrule, "FREQ=DAILY")
        XCTAssertFalse(unchangedAutomation.isActive)
        XCTAssertNil(unchangedAutomation.lastRunAt)
        XCTAssertTrue(store.automationRuns.isEmpty)
        XCTAssertTrue(provider.capturedPrompts.isEmpty)
        XCTAssertEqual(store.errorMessage, "You do not have permission to manage automations.")

        let reloadedStore = fixture.makeStore()
        await reloadedStore.load()
        let reloadedAutomation = try XCTUnwrap(reloadedStore.automations.first)
        XCTAssertEqual(reloadedStore.automations.count, 1)
        XCTAssertEqual(reloadedAutomation.name, "Existing")
        XCTAssertFalse(reloadedAutomation.isActive)
        XCTAssertTrue(reloadedStore.automationRuns.isEmpty)
    }

    func testUnmanagedLocalUserCanManageAutomationsWhenAdminDirectoryExists() async throws {
        let fixture = try AutomationFixture()
        let store = fixture.makeStore()
        await store.load()
        await store.createAdminUser(name: "Workspace User", email: "user@example.com", role: .user)

        await store.createAutomation(
            name: "Local",
            prompt: "Local prompt.",
            modelID: "fake-model",
            rrule: "FREQ=DAILY",
            isActive: false
        )

        XCTAssertEqual(store.automations.map(\.name), ["Local"])
        XCTAssertNil(store.errorMessage)
    }
}

private struct AutomationFixture {
    let rootURL: URL
    let storage: JSONStorageService
    let folderStorage: JSONFolderStorageService
    let settingsStore: SettingsStore
    let automationStorage: JSONAutomationStorageService
    let automationRunStorage: JSONAutomationRunStorageService
    let auditStorage: JSONAuditLogStorageService
    let adminStorage: JSONAdminDirectoryStorageService
    let provider: (any ChatProvider)?
    let shareService: FakeAutomationShareService?

    init(provider: (any ChatProvider)? = nil, shareService: FakeAutomationShareService? = nil) throws {
        self.provider = provider
        self.shareService = shareService
        rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        storage = JSONStorageService(rootURL: rootURL.appendingPathComponent("Chats", isDirectory: true))
        folderStorage = JSONFolderStorageService(rootURL: rootURL.appendingPathComponent("Folders", isDirectory: true))
        settingsStore = SettingsStore(settingsURL: rootURL.appendingPathComponent("settings.json"))
        automationStorage = JSONAutomationStorageService(
            rootURL: rootURL.appendingPathComponent("Automations", isDirectory: true)
        )
        automationRunStorage = JSONAutomationRunStorageService(
            rootURL: rootURL.appendingPathComponent("AutomationRuns", isDirectory: true)
        )
        auditStorage = JSONAuditLogStorageService(
            rootURL: rootURL.appendingPathComponent("AuditLog", isDirectory: true)
        )
        adminStorage = JSONAdminDirectoryStorageService(
            snapshotURL: rootURL.appendingPathComponent("admin-directory.json")
        )
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
    }

    @MainActor
    func makeStore() -> AppStore {
        AppStore(
            storage: storage,
            folderStorage: folderStorage,
            settingsStore: settingsStore,
            secretStore: InMemorySecretStore(),
            providerOverride: provider,
            shareService: shareService ?? FakeAutomationShareService(),
            auditLogStorage: auditStorage,
            adminDirectoryStorage: adminStorage,
            automationStorage: automationStorage,
            automationRunStorage: automationRunStorage
        )
    }
}

@MainActor
private final class FakeAutomationShareService: ChatSharing {
    private(set) var sharedText: String?
    private(set) var sharedTitle: String?

    func share(text: String, title: String) {
        sharedText = text
        sharedTitle = title
    }
}

private final class CapturingAutomationProvider: ChatProvider {
    var configuration = ProviderConfiguration.defaultOllama()
    let chunks: [String]
    let error: Error?
    private(set) var capturedPrompts: [String] = []

    init(chunks: [String], error: Error? = nil) {
        self.chunks = chunks
        self.error = error
    }

    func listModels() async throws -> [ProviderModel] {
        [ProviderModel(id: "fake-model", name: "fake-model", provider: .ollama, providerID: configuration.id)]
    }

    func healthCheck() async -> ProviderStatus {
        .available("Fake connected")
    }

    func streamChat(model: String, messages: [ProviderChatMessage]) -> AsyncThrowingStream<String, Error> {
        capturedPrompts.append(messages.last?.content ?? "")
        return AsyncThrowingStream { continuation in
            for chunk in chunks {
                continuation.yield(chunk)
            }
            if let error {
                continuation.finish(throwing: error)
            } else {
                continuation.finish()
            }
        }
    }

    func createEmbeddings(model: String, input: [String]) async throws -> [[Double]] {
        input.map { _ in [1.0] }
    }
}

private final class UnsupportedAutomationChatProvider: ChatProvider {
    var configuration = ProviderConfiguration.defaultOllama()
    private(set) var streamCallCount = 0

    var capabilities: ProviderCapabilities {
        var capabilities = configuration.capabilities
        capabilities.supportsChat = false
        return capabilities
    }

    func listModels() async throws -> [ProviderModel] {
        [ProviderModel(id: "fake-model", name: "fake-model", provider: .ollama, providerID: configuration.id)]
    }

    func healthCheck() async -> ProviderStatus {
        .available("Fake connected")
    }

    func streamChat(model: String, messages: [ProviderChatMessage]) -> AsyncThrowingStream<String, Error> {
        streamCallCount += 1
        return AsyncThrowingStream { continuation in
            continuation.yield("Unsupported automation")
            continuation.finish()
        }
    }

    func createEmbeddings(model: String, input: [String]) async throws -> [[Double]] {
        input.map { _ in [1.0] }
    }
}
