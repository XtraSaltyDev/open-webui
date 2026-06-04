import XCTest
@testable import OpenWebUINative

@MainActor
final class AppStoreToolLibraryTests: XCTestCase {
    func testCreateToolPersistsAndReloads() async throws {
        let fixture = try ToolLibraryFixture()
        let store = fixture.makeStore()
        await store.load()

        await store.createTool(
            name: "Weather lookup",
            content: "class Tools:\n    pass",
            description: "Fetch weather for a city."
        )

        XCTAssertEqual(store.tools.map(\.name), ["Weather lookup"])
        XCTAssertEqual(store.tools.first?.content, "class Tools:\n    pass")
        XCTAssertEqual(store.tools.first?.description, "Fetch weather for a city.")

        let reloadedStore = fixture.makeStore()
        await reloadedStore.load()

        XCTAssertEqual(reloadedStore.tools.map(\.name), ["Weather lookup"])
        XCTAssertEqual(reloadedStore.tools.first?.content, "class Tools:\n    pass")
    }

    func testCreateToolCreatesAuditEvent() async throws {
        let fixture = try ToolLibraryFixture()
        let store = fixture.makeStore()
        await store.load()

        await store.createTool(
            name: "Weather lookup",
            content: "class Tools:\n    pass",
            description: "Fetch weather for a city."
        )

        let tool = try XCTUnwrap(store.tools.first)
        let event = try XCTUnwrap(store.auditEvents.first { $0.action.rawValue == "toolCreated" })
        XCTAssertEqual(event.outcome, .succeeded)
        XCTAssertEqual(event.metadata["toolID"], tool.id)
        XCTAssertEqual(event.metadata["name"], "Weather lookup")
        XCTAssertEqual(event.metadata["description"], "Fetch weather for a city.")
        XCTAssertNil(event.metadata["content"])

        let reloadedStore = fixture.makeStore()
        await reloadedStore.load()
        XCTAssertEqual(reloadedStore.auditEvents.first?.action.rawValue, "toolCreated")
        XCTAssertEqual(reloadedStore.auditEvents.first?.metadata["toolID"], tool.id)
    }

    func testUpdateToolTrimsInputAndSortsMostRecentlyUpdatedFirst() async throws {
        let fixture = try ToolLibraryFixture()
        let store = fixture.makeStore()
        await store.load()

        await store.createTool(name: "First", content: "first()", description: "First tool")
        await store.createTool(name: "Second", content: "second()", description: "Second tool")
        let firstTool = try XCTUnwrap(store.tools.first { $0.name == "First" })

        await store.updateTool(
            firstTool.id,
            name: "  Updated first  ",
            content: "  better()  ",
            description: "  Better tool  "
        )

        XCTAssertEqual(store.tools.map(\.name), ["Updated first", "Second"])
        XCTAssertEqual(store.tools.first?.content, "better()")
        XCTAssertEqual(store.tools.first?.description, "Better tool")
    }

    func testUpdateToolStoresValvesJSONAndPersistsReload() async throws {
        let fixture = try ToolLibraryFixture()
        let store = fixture.makeStore()
        await store.load()
        await store.createTool(name: "Configurable lookup", content: "class Tools:\n    pass", description: nil)
        let tool = try XCTUnwrap(store.tools.first)

        await store.updateTool(
            tool.id,
            name: tool.name,
            content: tool.content,
            description: tool.description,
            valvesJSON: #"{"apiKey":"secret","limit":3}"#
        )

        let updatedTool = try XCTUnwrap(store.tools.first)
        XCTAssertEqual(updatedTool.valves?.objectValue?["apiKey"], .string("secret"))
        XCTAssertEqual(updatedTool.valves?.objectValue?["limit"], .number(3))
        XCTAssertNil(store.errorMessage)

        let reloadedStore = fixture.makeStore()
        await reloadedStore.load()

        XCTAssertEqual(reloadedStore.tools.first?.valves?.objectValue?["apiKey"], .string("secret"))
        XCTAssertEqual(reloadedStore.tools.first?.valves?.objectValue?["limit"], .number(3))
    }

    func testUpdateToolRejectsInvalidValvesJSONWithoutChangingTool() async throws {
        let fixture = try ToolLibraryFixture()
        let store = fixture.makeStore()
        await store.load()
        await store.createTool(
            name: "Configurable lookup",
            content: "class Tools:\n    pass",
            description: nil,
            valvesJSON: #"{"apiKey":"secret"}"#
        )
        let tool = try XCTUnwrap(store.tools.first)

        await store.updateTool(
            tool.id,
            name: "Changed lookup",
            content: "changed()",
            description: "Changed",
            valvesJSON: #"[{"not":"an object"}]"#
        )

        let unchangedTool = try XCTUnwrap(store.tools.first)
        XCTAssertEqual(unchangedTool.name, "Configurable lookup")
        XCTAssertEqual(unchangedTool.content, "class Tools:\n    pass")
        XCTAssertEqual(unchangedTool.valves?.objectValue?["apiKey"], .string("secret"))
        XCTAssertEqual(store.errorMessage, "Tool valves must be a JSON object.")
    }

    func testToolValvesTemplateUsesValvesSchemaDefaults() async throws {
        let schemaRun = AppToolRun(
            toolID: "tool-id",
            toolName: "Schema tool",
            functionName: "__native_valves_schema",
            argumentsBody: "{}",
            output: """
            {
              "type": "object",
              "properties": {
                "api_key": { "type": "string", "default": "secret" },
                "limit": { "type": "integer", "default": 5 },
                "strict": { "type": "boolean" }
              }
            }
            """,
            stderr: "",
            status: .succeeded,
            exitCode: 0
        )
        let executor = FakeLocalToolExecutor(methodRuns: ["__native_valves_schema": schemaRun])
        let fixture = try ToolLibraryFixture(toolExecutor: executor)
        let store = fixture.makeStore()
        await store.load()

        let template = await store.toolValvesTemplateJSON(
            name: "Schema tool",
            content: "class Valves:\n    pass\nclass Tools:\n    pass"
        )

        let value = try XCTUnwrap(template.flatMap { Data($0.utf8) })
        let decoded = try JSONDecoder.openWebUIDecoder.decode(JSONValue.self, from: value)
        XCTAssertEqual(decoded.objectValue?["api_key"], .string("secret"))
        XCTAssertEqual(decoded.objectValue?["limit"], .number(5))
        XCTAssertEqual(decoded.objectValue?["strict"], .bool(false))
        XCTAssertTrue(store.toolRuns.isEmpty)
        let capturedRequests = await executor.capturedRequests
        XCTAssertEqual(capturedRequests.map(\.functionName), ["__native_valves_schema"])
    }

    func testUpdateToolRejectsValvesThatDoNotMatchValvesSchema() async throws {
        let schemaRun = AppToolRun(
            toolID: "tool-id",
            toolName: "Schema tool",
            functionName: "__native_valves_schema",
            argumentsBody: "{}",
            output: """
            {
              "type": "object",
              "required": ["limit"],
              "properties": {
                "limit": { "type": "integer", "minimum": 1 },
                "mode": { "type": "string", "enum": ["safe", "fast"] }
              }
            }
            """,
            stderr: "",
            status: .succeeded,
            exitCode: 0
        )
        let executor = FakeLocalToolExecutor(methodRuns: ["__native_valves_schema": schemaRun])
        let fixture = try ToolLibraryFixture(toolExecutor: executor)
        let store = fixture.makeStore()
        await store.load()
        await store.createTool(
            name: "Schema tool",
            content: "class Valves:\n    pass\nclass Tools:\n    pass",
            description: nil
        )
        let tool = try XCTUnwrap(store.tools.first)

        await store.updateTool(
            tool.id,
            name: tool.name,
            content: tool.content,
            description: tool.description,
            valvesJSON: #"{"limit":"many","mode":"safe"}"#
        )

        let unchangedTool = try XCTUnwrap(store.tools.first)
        XCTAssertNil(unchangedTool.valves)
        XCTAssertEqual(store.errorMessage, "Tool valve 'limit' must be a number.")
        let capturedRequests = await executor.capturedRequests
        XCTAssertEqual(capturedRequests.map(\.functionName), ["__native_valves_schema"])
    }

    func testUpdateToolCreatesAuditEvent() async throws {
        let fixture = try ToolLibraryFixture()
        let store = fixture.makeStore()
        await store.load()
        await store.createTool(name: "First", content: "first()", description: "First tool")
        let tool = try XCTUnwrap(store.tools.first)

        await store.updateTool(
            tool.id,
            name: "Updated first",
            content: "better()",
            description: "Better tool"
        )

        let event = try XCTUnwrap(store.auditEvents.first { $0.action.rawValue == "toolUpdated" })
        XCTAssertEqual(event.outcome, .succeeded)
        XCTAssertEqual(event.metadata["toolID"], tool.id)
        XCTAssertEqual(event.metadata["fromName"], "First")
        XCTAssertEqual(event.metadata["name"], "Updated first")
        XCTAssertEqual(event.metadata["description"], "Better tool")
        XCTAssertNil(event.metadata["content"])
    }

    func testDeleteToolRemovesItFromStorage() async throws {
        let fixture = try ToolLibraryFixture()
        let store = fixture.makeStore()
        await store.load()
        await store.createTool(name: "Temporary", content: "temp()", description: nil)
        let tool = try XCTUnwrap(store.tools.first)

        await store.deleteTool(tool.id)

        let reloadedStore = fixture.makeStore()
        await reloadedStore.load()
        XCTAssertTrue(reloadedStore.tools.isEmpty)
    }

    func testDeleteToolCreatesAuditEvent() async throws {
        let fixture = try ToolLibraryFixture()
        let store = fixture.makeStore()
        await store.load()
        await store.createTool(name: "Temporary", content: "temp()", description: "Remove after testing.")
        let tool = try XCTUnwrap(store.tools.first)

        await store.deleteTool(tool.id)

        let event = try XCTUnwrap(store.auditEvents.first { $0.action.rawValue == "toolDeleted" })
        XCTAssertEqual(event.outcome, .succeeded)
        XCTAssertEqual(event.metadata["toolID"], tool.id)
        XCTAssertEqual(event.metadata["name"], "Temporary")
        XCTAssertEqual(event.metadata["description"], "Remove after testing.")
        XCTAssertNil(event.metadata["content"])

        let reloadedStore = fixture.makeStore()
        await reloadedStore.load()
        let reloadedEvent = try XCTUnwrap(reloadedStore.auditEvents.first { $0.action.rawValue == "toolDeleted" })
        XCTAssertEqual(reloadedEvent.metadata["toolID"], tool.id)
    }

    func testExportAndImportToolsJSONRoundTripsToolLibrary() async throws {
        let fixture = try ToolLibraryFixture()
        let store = fixture.makeStore()
        await store.load()
        await store.createTool(name: "Weather lookup", content: "weather()", description: "Fetch weather.")
        await store.createTool(name: "Calculator", content: "calculate()", description: "Run calculations.")

        let data = try store.exportToolsJSONData()

        let importFixture = try ToolLibraryFixture()
        let importStore = importFixture.makeStore()
        await importStore.load()
        try await importStore.importToolsJSONData(data)

        XCTAssertEqual(Set(importStore.tools.map(\.name)), ["Weather lookup", "Calculator"])
        XCTAssertEqual(importStore.tools.first { $0.name == "Calculator" }?.content, "calculate()")
    }

    func testExportToolJSONDataExportsOnlySelectedTool() async throws {
        let fixture = try ToolLibraryFixture()
        let selectedTool = AppTool(
            id: "bug-helper",
            name: "Bug helper",
            content: "bug()",
            description: "Debug incoming reports.",
            specs: [
                .object([
                    "name": .string("triage_bug"),
                    "parameters": .object([
                        "type": .string("object"),
                        "required": .array([.string("summary")])
                    ])
                ])
            ],
            manifest: .object(["version": .string("1.0")]),
            valves: .object(["limit": .number(3)]),
            createdAt: Date(timeIntervalSince1970: 100),
            updatedAt: Date(timeIntervalSince1970: 200)
        )
        try await fixture.toolStorage.save(selectedTool)
        try await fixture.toolStorage.save(
            AppTool(
                id: "release-helper",
                name: "Release helper",
                content: "release()",
                description: "Draft release notes.",
                createdAt: Date(timeIntervalSince1970: 100),
                updatedAt: Date(timeIntervalSince1970: 150)
            )
        )
        let store = fixture.makeStore()
        await store.load()

        let data = try XCTUnwrap(store.exportToolJSONData(selectedTool.id))

        let importFixture = try ToolLibraryFixture()
        let importStore = importFixture.makeStore()
        await importStore.load()
        try await importStore.importToolsJSONData(data)

        XCTAssertEqual(importStore.tools.map(\.name), ["Bug helper"])
        let importedTool = try XCTUnwrap(importStore.tools.first)
        XCTAssertEqual(importedTool.content, "bug()")
        XCTAssertEqual(importedTool.description, "Debug incoming reports.")
        XCTAssertEqual(importedTool.specs.first?.objectValue?["name"], .string("triage_bug"))
        XCTAssertEqual(importedTool.manifest?.objectValue?["version"], .string("1.0"))
        XCTAssertEqual(importedTool.valves?.objectValue?["limit"], .number(3))
    }

    func testExportToolsOpenWebUIJSONDataBuildsRawToolRecords() async throws {
        let fixture = try ToolLibraryFixture()
        try await fixture.toolStorage.save(
            AppTool(
                id: "weather-tool",
                name: "Weather Lookup",
                content: "class Tools:\n    pass",
                description: "Fetch weather from a configured service.",
                specs: [
                    .object([
                        "name": .string("get_weather"),
                        "description": .string("Get weather"),
                        "parameters": .object([
                            "type": .string("object"),
                            "properties": .object([
                                "city": .object(["type": .string("string")])
                            ])
                        ])
                    ])
                ],
                manifest: .object(["version": .string("1.0")]),
                valves: .object(["apiKey": .string("secret")]),
                createdAt: Date(timeIntervalSince1970: 1_000),
                updatedAt: Date(timeIntervalSince1970: 2_000)
            )
        )
        let store = fixture.makeStore()
        await store.load()

        let data = try store.exportToolsOpenWebUIJSONData()
        let records = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [[String: Any]])
        let record = try XCTUnwrap(records.first)
        let specs = try XCTUnwrap(record["specs"] as? [[String: Any]])
        let meta = try XCTUnwrap(record["meta"] as? [String: Any])
        let manifest = try XCTUnwrap(meta["manifest"] as? [String: Any])
        let valves = try XCTUnwrap(record["valves"] as? [String: Any])
        let accessGrants = try XCTUnwrap(record["access_grants"] as? [[String: Any]])

        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(record["id"] as? String, "weather-tool")
        XCTAssertEqual(record["user_id"] as? String, store.currentUserID)
        XCTAssertEqual(record["name"] as? String, "Weather Lookup")
        XCTAssertEqual(record["content"] as? String, "class Tools:\n    pass")
        XCTAssertEqual(specs.first?["name"] as? String, "get_weather")
        XCTAssertEqual(meta["description"] as? String, "Fetch weather from a configured service.")
        XCTAssertEqual(manifest["version"] as? String, "1.0")
        XCTAssertEqual(valves["apiKey"] as? String, "secret")
        XCTAssertTrue(accessGrants.isEmpty)
        XCTAssertEqual(record["created_at"] as? Int, 1_000)
        XCTAssertEqual(record["updated_at"] as? Int, 2_000)
    }

    func testShareToolSharesSelectedToolJSON() async throws {
        let shareService = FakeToolShareService()
        let fixture = try ToolLibraryFixture(shareService: shareService)
        let store = fixture.makeStore()
        await store.load()
        await store.createTool(
            name: "Bug helper",
            content: "bug()",
            description: "Debug incoming reports.",
            valvesJSON: #"{"limit":3}"#
        )
        await store.createTool(name: "Release helper", content: "release()", description: "Draft release notes.")
        let tool = try XCTUnwrap(store.tools.first { $0.name == "Bug helper" })

        store.shareTool(tool.id)

        XCTAssertEqual(shareService.sharedTitle, "Bug helper")
        let sharedText = try XCTUnwrap(shareService.sharedText)
        let sharedTools = try ToolExportService().tools(fromJSONData: Data(sharedText.utf8))
        XCTAssertEqual(sharedTools.map(\.name), ["Bug helper"])
        XCTAssertEqual(sharedTools.first?.description, "Debug incoming reports.")
        XCTAssertEqual(sharedTools.first?.valves?.objectValue?["limit"], .number(3))
    }

    func testImportToolsJSONAcceptsOpenWebUIToolRecords() async throws {
        let fixture = try ToolLibraryFixture()
        let store = fixture.makeStore()
        await store.load()
        let data = Data(
            """
            [
              {
                "id": "weather_tool",
                "user_id": "user-id",
                "name": "Weather Lookup",
                "content": "class Tools:\\n    pass",
                "specs": [
                  {
                    "name": "get_weather",
                    "description": "Get weather",
                    "parameters": {
                      "type": "object",
                      "properties": {
                        "city": { "type": "string" }
                      }
                    }
                  }
                ],
                "meta": {
                  "description": "Fetch weather from a configured service.",
                  "manifest": { "version": "1.0" }
                },
                "valves": {
                  "apiKey": "secret"
                },
                "access_grants": [],
                "created_at": 1000,
                "updated_at": 2000
              }
            ]
            """.utf8
        )

        try await store.importToolsJSONData(data)

        let tool = try XCTUnwrap(store.tools.first)
        XCTAssertEqual(tool.id, "weather_tool")
        XCTAssertEqual(tool.name, "Weather Lookup")
        XCTAssertEqual(tool.description, "Fetch weather from a configured service.")
        XCTAssertEqual(tool.specs.first?.objectValue?["name"], .string("get_weather"))
        XCTAssertEqual(tool.valves?.objectValue?["apiKey"], .string("secret"))
    }

    func testCreateToolIsBlockedWhenToolsFeatureIsDisabled() async throws {
        let fixture = try ToolLibraryFixture()
        let store = fixture.makeStore()
        await store.load()
        await store.setFeatureToggle(.tools, isEnabled: false)

        await store.createTool(
            name: "Hidden tool",
            content: "class Tools:\n    pass",
            description: "Should not persist."
        )

        XCTAssertTrue(store.tools.isEmpty)
        XCTAssertEqual(store.errorMessage, "Tools is disabled.")
        let saved = try await fixture.toolStorage.loadTools()
        XCTAssertTrue(saved.isEmpty)
    }

    func testToolLibraryActionsAreBlockedWhenToolsFeatureIsDisabled() async throws {
        let shareService = FakeToolShareService()
        let fixture = try ToolLibraryFixture(shareService: shareService)
        let store = fixture.makeStore()
        await store.load()
        await store.createTool(
            name: "Existing tool",
            content: "existing()",
            description: "Existing content."
        )
        let tool = try XCTUnwrap(store.tools.first)
        await store.setFeatureToggle(.tools, isEnabled: false)

        await store.updateTool(
            tool.id,
            name: "Blocked update",
            content: "updated()",
            description: "Blocked content."
        )
        await store.deleteTool(tool.id)
        let data = try ToolExportService().jsonData(for: [
            AppTool(name: "Blocked import", content: "imported()", description: nil)
        ])
        try await store.importToolsJSONData(data)
        store.shareTool(tool.id)

        let unchangedTool = try XCTUnwrap(store.tools.first)
        XCTAssertEqual(store.tools.count, 1)
        XCTAssertEqual(unchangedTool.name, "Existing tool")
        XCTAssertEqual(unchangedTool.content, "existing()")
        XCTAssertEqual(unchangedTool.description, "Existing content.")
        XCTAssertNil(shareService.sharedText)
        XCTAssertNil(shareService.sharedTitle)
        XCTAssertEqual(store.errorMessage, "Tools is disabled.")

        let saved = try await fixture.toolStorage.loadTools()
        let savedTool = try XCTUnwrap(saved.first)
        XCTAssertEqual(saved.count, 1)
        XCTAssertEqual(savedTool.name, "Existing tool")
        XCTAssertEqual(savedTool.content, "existing()")
    }

    func testToolWritePermissionAllowsCreateUpdateAndDeleteForCurrentUser() async throws {
        let fixture = try ToolLibraryFixture()
        let store = fixture.makeStore()
        await store.load()
        await store.createAdminUser(name: "Workspace User", email: "user@example.com", role: .user)
        let user = try XCTUnwrap(store.adminUsers.first)
        await store.createAdminGroup(name: "Tool Editors", description: "Can manage tools.", permissions: ["tools.write"])
        let group = try XCTUnwrap(store.adminGroups.first)
        await store.setAdminGroupMembers(group.id, memberIDs: [user.id])
        store.currentUserID = user.id

        await store.createTool(name: "Weather lookup", content: "weather()", description: "Fetch weather.")
        let tool = try XCTUnwrap(store.tools.first)
        await store.updateTool(tool.id, name: "Updated weather", content: "betterWeather()", description: "Fetch better weather.")
        let updatedTool = try XCTUnwrap(store.tools.first)
        await store.deleteTool(updatedTool.id)

        XCTAssertTrue(store.tools.isEmpty)
        XCTAssertNil(store.errorMessage)
        XCTAssertTrue(store.auditEvents.contains { $0.action.rawValue == "toolCreated" })
        XCTAssertTrue(store.auditEvents.contains { $0.action.rawValue == "toolUpdated" })
        XCTAssertTrue(store.auditEvents.contains { $0.action.rawValue == "toolDeleted" })
    }

    func testToolWritePermissionBlocksCreateUpdateAndDeleteForCurrentUser() async throws {
        let fixture = try ToolLibraryFixture()
        let store = fixture.makeStore()
        await store.load()
        await store.createAdminUser(name: "Workspace User", email: "user@example.com", role: .user)
        let user = try XCTUnwrap(store.adminUsers.first)
        store.currentUserID = user.id

        await store.createTool(name: "Blocked tool", content: "blocked()", description: nil)

        XCTAssertTrue(store.tools.isEmpty)
        XCTAssertEqual(store.errorMessage, "You do not have permission to manage tools.")

        store.errorMessage = nil
        store.currentUserID = "local-admin"
        await store.createAdminUser(name: "Local Admin", email: "admin@example.com", role: .admin)
        let admin = try XCTUnwrap(store.adminUsers.first { $0.role == .admin })
        store.currentUserID = admin.id
        await store.createTool(name: "Existing tool", content: "existing()", description: "Existing content.")
        let tool = try XCTUnwrap(store.tools.first)

        store.currentUserID = user.id
        await store.updateTool(tool.id, name: "Blocked update", content: "updated()", description: nil)
        await store.deleteTool(tool.id)

        XCTAssertEqual(store.tools.first?.name, "Existing tool")
        XCTAssertEqual(store.tools.first?.content, "existing()")
        XCTAssertEqual(store.errorMessage, "You do not have permission to manage tools.")
        XCTAssertFalse(store.auditEvents.contains { $0.action.rawValue == "toolUpdated" })
        XCTAssertFalse(store.auditEvents.contains { $0.action.rawValue == "toolDeleted" })
    }

    func testUnmanagedLocalUserCanManageToolsWhenAdminDirectoryExists() async throws {
        let fixture = try ToolLibraryFixture()
        let store = fixture.makeStore()
        await store.load()
        await store.createAdminUser(name: "Workspace User", email: "user@example.com", role: .user)

        await store.createTool(name: "Local tool", content: "local()", description: nil)

        XCTAssertEqual(store.tools.map(\.name), ["Local tool"])
        XCTAssertNil(store.errorMessage)
    }

    func testToolExecutePermissionAllowsLocalToolRunForCurrentUser() async throws {
        let runID = UUID(uuidString: "00000000-0000-0000-0000-00000000B007")!
        let run = AppToolRun(
            id: runID,
            toolID: "tool-id",
            toolName: "Weather lookup",
            functionName: "get_weather",
            argumentsBody: #"{"city":"Chicago"}"#,
            output: "Weather in Chicago is clear.",
            stderr: "",
            status: .succeeded,
            exitCode: 0,
            startedAt: Date(timeIntervalSince1970: 300),
            completedAt: Date(timeIntervalSince1970: 301)
        )
        let executor = FakeLocalToolExecutor(run: run)
        let fixture = try ToolLibraryFixture(toolExecutor: executor)
        let store = fixture.makeStore()
        await store.load()
        await store.createTool(
            name: "Weather lookup",
            content: "class Tools:\n    def get_weather(self, city):\n        return city",
            description: "Fetch weather."
        )
        let tool = try XCTUnwrap(store.tools.first)
        await store.createAdminUser(name: "Workspace User", email: "user@example.com", role: .user)
        let user = try XCTUnwrap(store.adminUsers.first)
        await store.createAdminGroup(name: "Tool Runners", description: "Can run tools.", permissions: ["tools.execute"])
        let group = try XCTUnwrap(store.adminGroups.first)
        await store.setAdminGroupMembers(group.id, memberIDs: [user.id])
        store.currentUserID = user.id

        await store.runTool(tool.id, functionName: "get_weather", argumentsBody: #" { "city": "Chicago" } "#)

        let capturedRequests = await executor.capturedRequests
        XCTAssertEqual(capturedRequests.map(\.tool.id), [tool.id])
        XCTAssertEqual(capturedRequests.first?.functionName, "get_weather")
        XCTAssertEqual(capturedRequests.first?.arguments, .object(["city": .string("Chicago")]))
        XCTAssertEqual(store.toolRuns.map(\.id), [runID])
        XCTAssertEqual(store.selectedToolRunID, runID)
        XCTAssertFalse(store.isRunningTool)
        XCTAssertNil(store.toolExecutionError)
        XCTAssertNil(store.errorMessage)
        XCTAssertEqual(store.auditEvents.first?.action, .toolInvoked)
        XCTAssertEqual(store.auditEvents.first?.metadata["toolID"], "tool-id")

        let reloadedStore = fixture.makeStore()
        await reloadedStore.load()

        XCTAssertEqual(reloadedStore.toolRuns.map(\.id), [runID])
        XCTAssertEqual(reloadedStore.toolRuns.first?.output, "Weather in Chicago is clear.")
    }

    func testLocalToolExecutionBlocksDisabledFeatureBeforeCallingExecutor() async throws {
        let executor = FakeLocalToolExecutor(
            methodRuns: [
                "__native_valves_schema": AppToolRun(
                    toolID: "tool-id",
                    toolName: "Weather lookup",
                    functionName: "__native_valves_schema",
                    argumentsBody: "{}",
                    output: #"{"type":"object","properties":{"apiKey":{"type":"string"}}}"#,
                    stderr: "",
                    status: .succeeded,
                    exitCode: 0
                )
            ]
        )
        let fixture = try ToolLibraryFixture(toolExecutor: executor)
        let store = fixture.makeStore()
        await store.load()
        await store.createTool(
            name: "Weather lookup",
            content: "class Valves:\n    pass\nclass Tools:\n    def get_weather(self, city):\n        return city",
            description: "Fetch weather."
        )
        let tool = try XCTUnwrap(store.tools.first)
        await store.setFeatureToggle(.tools, isEnabled: false)

        let template = await store.toolValvesTemplateJSON(name: tool.name, content: tool.content)
        await store.runTool(tool.id, functionName: "get_weather", argumentsBody: #"{"city":"Chicago"}"#)

        let capturedRequests = await executor.capturedRequests
        XCTAssertNil(template)
        XCTAssertTrue(capturedRequests.isEmpty)
        XCTAssertTrue(store.toolRuns.isEmpty)
        XCTAssertEqual(store.toolExecutionError, "Tools is disabled.")
        XCTAssertEqual(store.errorMessage, "Tools is disabled.")
        XCTAssertFalse(store.isRunningTool)
        let persistedRuns = try await fixture.toolRunStorage.loadRuns()
        XCTAssertTrue(persistedRuns.isEmpty)
    }

    func testToolExecutePermissionBlocksLocalToolRunForCurrentUser() async throws {
        let executor = FakeLocalToolExecutor()
        let fixture = try ToolLibraryFixture(toolExecutor: executor)
        let store = fixture.makeStore()
        await store.load()
        await store.createTool(
            name: "Weather lookup",
            content: "class Tools:\n    def get_weather(self, city):\n        return city",
            description: "Fetch weather."
        )
        let tool = try XCTUnwrap(store.tools.first)
        await store.createAdminUser(name: "Workspace User", email: "user@example.com", role: .user)
        let user = try XCTUnwrap(store.adminUsers.first)
        await store.createAdminGroup(name: "Tool Editors", description: "Can manage tools.", permissions: ["tools.write"])
        let group = try XCTUnwrap(store.adminGroups.first)
        await store.setAdminGroupMembers(group.id, memberIDs: [user.id])
        store.currentUserID = user.id

        await store.runTool(tool.id, functionName: "get_weather", argumentsBody: #"{"city":"Chicago"}"#)

        let capturedRequests = await executor.capturedRequests
        XCTAssertTrue(capturedRequests.isEmpty)
        XCTAssertTrue(store.toolRuns.isEmpty)
        XCTAssertEqual(store.toolExecutionError, "You do not have permission to run tools.")
        XCTAssertEqual(store.errorMessage, "You do not have permission to run tools.")
        XCTAssertFalse(store.isRunningTool)
    }
}

private struct ToolLibraryFixture {
    let rootURL: URL
    let storage: JSONStorageService
    let folderStorage: JSONFolderStorageService
    let promptStorage: JSONPromptStorageService
    let noteStorage: JSONNoteStorageService
    let toolStorage: JSONToolStorageService
    let toolRunStorage: JSONToolRunStorageService
    let toolExecutor: any LocalToolExecuting
    let auditStorage: JSONAuditLogStorageService
    let adminStorage: JSONAdminDirectoryStorageService
    let settingsStore: SettingsStore
    let shareService: FakeToolShareService?

    init(
        toolExecutor: any LocalToolExecuting = FakeLocalToolExecutor(),
        shareService: FakeToolShareService? = nil
    ) throws {
        rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        storage = JSONStorageService(rootURL: rootURL.appendingPathComponent("Chats", isDirectory: true))
        folderStorage = JSONFolderStorageService(rootURL: rootURL.appendingPathComponent("Folders", isDirectory: true))
        promptStorage = JSONPromptStorageService(rootURL: rootURL.appendingPathComponent("Prompts", isDirectory: true))
        noteStorage = JSONNoteStorageService(rootURL: rootURL.appendingPathComponent("Notes", isDirectory: true))
        toolStorage = JSONToolStorageService(rootURL: rootURL.appendingPathComponent("Tools", isDirectory: true))
        toolRunStorage = JSONToolRunStorageService(rootURL: rootURL.appendingPathComponent("ToolRuns", isDirectory: true))
        self.toolExecutor = toolExecutor
        auditStorage = JSONAuditLogStorageService(rootURL: rootURL.appendingPathComponent("AuditLog", isDirectory: true))
        adminStorage = JSONAdminDirectoryStorageService(
            snapshotURL: rootURL.appendingPathComponent("admin-directory.json")
        )
        settingsStore = SettingsStore(settingsURL: rootURL.appendingPathComponent("settings.json"))
        self.shareService = shareService
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
    }

    @MainActor
    func makeStore() -> AppStore {
        AppStore(
            storage: storage,
            folderStorage: folderStorage,
            settingsStore: settingsStore,
            secretStore: InMemorySecretStore(),
            shareService: shareService ?? FakeToolShareService(),
            auditLogStorage: auditStorage,
            promptStorage: promptStorage,
            noteStorage: noteStorage,
            toolStorage: toolStorage,
            toolRunStorage: toolRunStorage,
            toolExecutor: toolExecutor,
            adminDirectoryStorage: adminStorage
        )
    }
}

@MainActor
private final class FakeToolShareService: ChatSharing {
    private(set) var sharedText: String?
    private(set) var sharedTitle: String?

    func share(text: String, title: String) {
        sharedText = text
        sharedTitle = title
    }
}

private actor FakeLocalToolExecutor: LocalToolExecuting {
    private let run: AppToolRun
    private let methodRuns: [String: AppToolRun]
    private(set) var capturedRequests: [LocalToolInvocationRequest] = []

    init(
        run: AppToolRun = AppToolRun(
            toolID: "tool-id",
            toolName: "Weather lookup",
            functionName: "get_weather",
            argumentsBody: "{}",
            output: "{}",
            stderr: "",
            status: .succeeded,
            exitCode: 0
        )
    ) {
        self.run = run
        self.methodRuns = [:]
    }

    init(methodRuns: [String: AppToolRun]) {
        self.run = AppToolRun(
            toolID: "tool-id",
            toolName: "Weather lookup",
            functionName: "get_weather",
            argumentsBody: "{}",
            output: "{}",
            stderr: "",
            status: .succeeded,
            exitCode: 0
        )
        self.methodRuns = methodRuns
    }

    func invoke(_ request: LocalToolInvocationRequest) async -> AppToolRun {
        capturedRequests.append(request)
        return methodRuns[request.functionName] ?? run
    }
}
