import XCTest
@testable import OpenWebUINative

@MainActor
final class AppStoreFunctionLibraryTests: XCTestCase {
    func testCreateFunctionPersistsAndReloads() async throws {
        let fixture = try FunctionLibraryFixture()
        let store = fixture.makeStore()
        await store.load()

        await store.createFunction(
            name: "Safety filter",
            kind: .filter,
            content: "def inlet(body):\n    return body",
            description: "Review prompts before sending."
        )

        XCTAssertEqual(store.functions.map(\.name), ["Safety filter"])
        XCTAssertEqual(store.functions.first?.kind, .filter)
        XCTAssertEqual(store.functions.first?.content, "def inlet(body):\n    return body")
        XCTAssertEqual(store.functions.first?.description, "Review prompts before sending.")
        XCTAssertEqual(store.functions.first?.isActive, false)
        XCTAssertEqual(store.functions.first?.isGlobal, false)

        let reloadedStore = fixture.makeStore()
        await reloadedStore.load()

        XCTAssertEqual(reloadedStore.functions.map(\.name), ["Safety filter"])
        XCTAssertEqual(reloadedStore.functions.first?.kind, .filter)
    }

    func testCreateFunctionCreatesAuditEvent() async throws {
        let fixture = try FunctionLibraryFixture()
        let store = fixture.makeStore()
        await store.load()

        await store.createFunction(
            name: "Safety filter",
            kind: .filter,
            content: "def inlet(body):\n    return body",
            description: "Review prompts before sending."
        )

        let function = try XCTUnwrap(store.functions.first)
        let event = try XCTUnwrap(store.auditEvents.first { $0.action.rawValue == "functionCreated" })
        XCTAssertEqual(event.outcome, .succeeded)
        XCTAssertEqual(event.metadata["functionID"], function.id)
        XCTAssertEqual(event.metadata["name"], "Safety filter")
        XCTAssertEqual(event.metadata["kind"], "filter")
        XCTAssertEqual(event.metadata["description"], "Review prompts before sending.")
        XCTAssertEqual(event.metadata["isActive"], "false")
        XCTAssertEqual(event.metadata["isGlobal"], "false")
        XCTAssertNil(event.metadata["content"])
        XCTAssertNil(event.metadata["manifest"])
        XCTAssertNil(event.metadata["valves"])

        let reloadedStore = fixture.makeStore()
        await reloadedStore.load()
        XCTAssertEqual(reloadedStore.auditEvents.first?.action.rawValue, "functionCreated")
        XCTAssertEqual(reloadedStore.auditEvents.first?.metadata["functionID"], function.id)
    }

    func testUpdateFunctionTrimsInputSortsAndUpdatesFlags() async throws {
        let fixture = try FunctionLibraryFixture()
        let store = fixture.makeStore()
        await store.load()

        await store.createFunction(name: "First", kind: .filter, content: "first()", description: "First function")
        await store.createFunction(name: "Second", kind: .action, content: "second()", description: "Second function")
        let firstFunction = try XCTUnwrap(store.functions.first { $0.name == "First" })

        await store.updateFunction(
            firstFunction.id,
            name: "  Updated first  ",
            kind: .pipe,
            content: "  better()  ",
            description: "  Better function  ",
            isActive: true,
            isGlobal: true
        )

        XCTAssertEqual(store.functions.map(\.name), ["Updated first", "Second"])
        XCTAssertEqual(store.functions.first?.kind, .pipe)
        XCTAssertEqual(store.functions.first?.content, "better()")
        XCTAssertEqual(store.functions.first?.description, "Better function")
        XCTAssertEqual(store.functions.first?.isActive, true)
        XCTAssertEqual(store.functions.first?.isGlobal, true)
    }

    func testUpdateFunctionStoresValvesJSONAndPersistsReload() async throws {
        let fixture = try FunctionLibraryFixture()
        let store = fixture.makeStore()
        await store.load()
        await store.createFunction(name: "Configurable action", kind: .action, content: "def action(body):\n    return body", description: nil)
        let function = try XCTUnwrap(store.functions.first)

        await store.updateFunction(
            function.id,
            name: function.name,
            kind: function.kind,
            content: function.content,
            description: function.description,
            isActive: true,
            isGlobal: true,
            valvesJSON: #"{"strict":true,"limit":3}"#
        )

        let updatedFunction = try XCTUnwrap(store.functions.first)
        XCTAssertEqual(updatedFunction.valves?.objectValue?["strict"], .bool(true))
        XCTAssertEqual(updatedFunction.valves?.objectValue?["limit"], .number(3))
        XCTAssertNil(store.functionExecutionError)
        XCTAssertNil(store.errorMessage)

        let reloadedStore = fixture.makeStore()
        await reloadedStore.load()

        XCTAssertEqual(reloadedStore.functions.first?.valves?.objectValue?["strict"], .bool(true))
        XCTAssertEqual(reloadedStore.functions.first?.valves?.objectValue?["limit"], .number(3))
    }

    func testUpdateFunctionRejectsInvalidValvesJSONWithoutChangingFunction() async throws {
        let fixture = try FunctionLibraryFixture()
        let store = fixture.makeStore()
        await store.load()
        let data = Data(
            """
            [
              {
                "id": "configurable_action",
                "name": "Configurable action",
                "type": "action",
                "content": "def action(body):\\n    return body",
                "valves": { "strict": true }
              }
            ]
            """.utf8
        )
        try await store.importFunctionsJSONData(data)
        let function = try XCTUnwrap(store.functions.first)

        await store.updateFunction(
            function.id,
            name: "Changed name",
            kind: .pipe,
            content: "def pipe(body):\n    return body",
            description: "Changed",
            isActive: true,
            isGlobal: true,
            valvesJSON: #"[{"not":"an object"}]"#
        )

        let unchangedFunction = try XCTUnwrap(store.functions.first)
        XCTAssertEqual(unchangedFunction.name, "Configurable action")
        XCTAssertEqual(unchangedFunction.kind, .action)
        XCTAssertEqual(unchangedFunction.valves?.objectValue?["strict"], .bool(true))
        XCTAssertEqual(store.errorMessage, "Function valves must be a JSON object.")
    }

    func testFunctionValvesTemplateUsesValvesSchemaDefaults() async throws {
        let schemaRun = AppFunctionRun(
            functionID: "function-id",
            functionName: "Schema filter",
            functionKind: .filter,
            methodName: "__native_valves_schema",
            inputBody: "{}",
            output: """
            {
              "type": "object",
              "properties": {
                "limit": { "type": "integer", "default": 5 },
                "mode": { "type": "string", "default": "safe" },
                "strict": { "type": "boolean" }
              }
            }
            """,
            stderr: "",
            status: .succeeded,
            exitCode: 0
        )
        let executor = FakeLocalFunctionExecutor(methodRuns: ["__native_valves_schema": schemaRun])
        let fixture = try FunctionLibraryFixture(functionExecutor: executor)
        let store = fixture.makeStore()
        await store.load()

        let template = await store.functionValvesTemplateJSON(
            name: "Schema filter",
            kind: .filter,
            content: "class Valves:\n    pass\ndef inlet(body):\n    return body"
        )

        let value = try XCTUnwrap(template.flatMap { Data($0.utf8) })
        let decoded = try JSONDecoder.openWebUIDecoder.decode(JSONValue.self, from: value)
        XCTAssertEqual(decoded.objectValue?["limit"], .number(5))
        XCTAssertEqual(decoded.objectValue?["mode"], .string("safe"))
        XCTAssertEqual(decoded.objectValue?["strict"], .bool(false))
        XCTAssertTrue(store.functionRuns.isEmpty)
        let capturedRequests = await executor.capturedRequests
        XCTAssertEqual(capturedRequests.map(\.methodName), ["__native_valves_schema"])
    }

    func testUpdateFunctionRejectsValvesThatDoNotMatchValvesSchema() async throws {
        let schemaRun = AppFunctionRun(
            functionID: "function-id",
            functionName: "Schema filter",
            functionKind: .filter,
            methodName: "__native_valves_schema",
            inputBody: "{}",
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
        let executor = FakeLocalFunctionExecutor(methodRuns: ["__native_valves_schema": schemaRun])
        let fixture = try FunctionLibraryFixture(functionExecutor: executor)
        let store = fixture.makeStore()
        await store.load()
        await store.createFunction(
            name: "Schema filter",
            kind: .filter,
            content: "class Valves:\n    pass\ndef inlet(body):\n    return body",
            description: nil
        )
        let function = try XCTUnwrap(store.functions.first)

        await store.updateFunction(
            function.id,
            name: function.name,
            kind: function.kind,
            content: function.content,
            description: function.description,
            isActive: function.isActive,
            isGlobal: function.isGlobal,
            valvesJSON: #"{"limit":"many","mode":"safe"}"#
        )

        let unchangedFunction = try XCTUnwrap(store.functions.first)
        XCTAssertNil(unchangedFunction.valves)
        XCTAssertEqual(store.errorMessage, "Function valve 'limit' must be a number.")
        let capturedRequests = await executor.capturedRequests
        XCTAssertEqual(capturedRequests.map(\.methodName), ["__native_valves_schema"])
    }

    func testUpdateFunctionCreatesAuditEvent() async throws {
        let fixture = try FunctionLibraryFixture()
        let store = fixture.makeStore()
        await store.load()
        await store.createFunction(name: "First", kind: .filter, content: "first()", description: "First function")
        let function = try XCTUnwrap(store.functions.first)

        await store.updateFunction(
            function.id,
            name: "Updated first",
            kind: .pipe,
            content: "better()",
            description: "Better function",
            isActive: true,
            isGlobal: true
        )

        let event = try XCTUnwrap(store.auditEvents.first { $0.action.rawValue == "functionUpdated" })
        XCTAssertEqual(event.outcome, .succeeded)
        XCTAssertEqual(event.metadata["functionID"], function.id)
        XCTAssertEqual(event.metadata["fromName"], "First")
        XCTAssertEqual(event.metadata["name"], "Updated first")
        XCTAssertEqual(event.metadata["kind"], "pipe")
        XCTAssertEqual(event.metadata["description"], "Better function")
        XCTAssertEqual(event.metadata["isActive"], "true")
        XCTAssertEqual(event.metadata["isGlobal"], "true")
        XCTAssertNil(event.metadata["content"])
        XCTAssertNil(event.metadata["manifest"])
        XCTAssertNil(event.metadata["valves"])
    }

    func testDeleteFunctionRemovesItFromStorage() async throws {
        let fixture = try FunctionLibraryFixture()
        let store = fixture.makeStore()
        await store.load()
        await store.createFunction(name: "Temporary", kind: .action, content: "temp()", description: nil)
        let function = try XCTUnwrap(store.functions.first)

        await store.deleteFunction(function.id)

        let reloadedStore = fixture.makeStore()
        await reloadedStore.load()
        XCTAssertTrue(reloadedStore.functions.isEmpty)
    }

    func testDeleteFunctionCreatesAuditEvent() async throws {
        let fixture = try FunctionLibraryFixture()
        let store = fixture.makeStore()
        await store.load()
        await store.createFunction(
            name: "Temporary",
            kind: .action,
            content: "temp()",
            description: "Remove after testing."
        )
        let function = try XCTUnwrap(store.functions.first)

        await store.deleteFunction(function.id)

        let event = try XCTUnwrap(store.auditEvents.first { $0.action.rawValue == "functionDeleted" })
        XCTAssertEqual(event.outcome, .succeeded)
        XCTAssertEqual(event.metadata["functionID"], function.id)
        XCTAssertEqual(event.metadata["name"], "Temporary")
        XCTAssertEqual(event.metadata["kind"], "action")
        XCTAssertEqual(event.metadata["description"], "Remove after testing.")
        XCTAssertEqual(event.metadata["isActive"], "false")
        XCTAssertEqual(event.metadata["isGlobal"], "false")
        XCTAssertNil(event.metadata["content"])
        XCTAssertNil(event.metadata["manifest"])
        XCTAssertNil(event.metadata["valves"])

        let reloadedStore = fixture.makeStore()
        await reloadedStore.load()
        let reloadedEvent = try XCTUnwrap(reloadedStore.auditEvents.first { $0.action.rawValue == "functionDeleted" })
        XCTAssertEqual(reloadedEvent.metadata["functionID"], function.id)
    }

    func testExportAndImportFunctionsJSONRoundTripsFunctionLibrary() async throws {
        let fixture = try FunctionLibraryFixture()
        let store = fixture.makeStore()
        await store.load()
        await store.createFunction(name: "Safety filter", kind: .filter, content: "inlet()", description: "Filter")
        await store.createFunction(name: "Summarize action", kind: .action, content: "action()", description: "Action")

        let data = try store.exportFunctionsJSONData()

        let importFixture = try FunctionLibraryFixture()
        let importStore = importFixture.makeStore()
        await importStore.load()
        try await importStore.importFunctionsJSONData(data)

        XCTAssertEqual(Set(importStore.functions.map(\.name)), ["Safety filter", "Summarize action"])
        XCTAssertEqual(importStore.functions.first { $0.name == "Summarize action" }?.kind, .action)
    }

    func testExportFunctionJSONDataExportsOnlySelectedFunction() async throws {
        let fixture = try FunctionLibraryFixture()
        let selectedFunction = AppFunction(
            id: "safety-filter",
            name: "Safety filter",
            kind: .filter,
            content: "def inlet(body):\n    return body",
            description: "Review prompts before sending.",
            manifest: .object(["version": .string("1.0")]),
            valves: .object(["strict": .bool(true)]),
            isActive: true,
            isGlobal: false,
            createdAt: Date(timeIntervalSince1970: 100),
            updatedAt: Date(timeIntervalSince1970: 200)
        )
        try await fixture.functionStorage.save(selectedFunction)
        try await fixture.functionStorage.save(
            AppFunction(
                id: "summarize-action",
                name: "Summarize action",
                kind: .action,
                content: "def action(body):\n    return body",
                description: "Summarize selected content.",
                createdAt: Date(timeIntervalSince1970: 100),
                updatedAt: Date(timeIntervalSince1970: 150)
            )
        )
        let store = fixture.makeStore()
        await store.load()

        let data = try XCTUnwrap(store.exportFunctionJSONData(selectedFunction.id))

        let importFixture = try FunctionLibraryFixture()
        let importStore = importFixture.makeStore()
        await importStore.load()
        try await importStore.importFunctionsJSONData(data)

        XCTAssertEqual(importStore.functions.map(\.name), ["Safety filter"])
        let importedFunction = try XCTUnwrap(importStore.functions.first)
        XCTAssertEqual(importedFunction.kind, .filter)
        XCTAssertEqual(importedFunction.content, "def inlet(body):\n    return body")
        XCTAssertEqual(importedFunction.description, "Review prompts before sending.")
        XCTAssertEqual(importedFunction.manifest?.objectValue?["version"], .string("1.0"))
        XCTAssertEqual(importedFunction.valves?.objectValue?["strict"], .bool(true))
        XCTAssertEqual(importedFunction.isActive, true)
        XCTAssertEqual(importedFunction.isGlobal, false)
    }

    func testExportFunctionsOpenWebUIJSONDataBuildsRawFunctionRecords() async throws {
        let fixture = try FunctionLibraryFixture()
        try await fixture.functionStorage.save(
            AppFunction(
                id: "safety-filter",
                name: "Safety Filter",
                kind: .filter,
                content: "def inlet(body):\n    return body",
                description: "Review prompts before sending.",
                manifest: .object(["version": .string("1.0")]),
                valves: .object(["strict": .bool(true), "limit": .number(3)]),
                isActive: true,
                isGlobal: false,
                createdAt: Date(timeIntervalSince1970: 1_000),
                updatedAt: Date(timeIntervalSince1970: 2_000)
            )
        )
        let store = fixture.makeStore()
        await store.load()

        let data = try store.exportFunctionsOpenWebUIJSONData()
        let records = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [[String: Any]])
        let record = try XCTUnwrap(records.first)
        let meta = try XCTUnwrap(record["meta"] as? [String: Any])
        let manifest = try XCTUnwrap(meta["manifest"] as? [String: Any])
        let valves = try XCTUnwrap(record["valves"] as? [String: Any])

        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(record["id"] as? String, "safety-filter")
        XCTAssertEqual(record["user_id"] as? String, store.currentUserID)
        XCTAssertEqual(record["name"] as? String, "Safety Filter")
        XCTAssertEqual(record["type"] as? String, "filter")
        XCTAssertEqual(record["content"] as? String, "def inlet(body):\n    return body")
        XCTAssertEqual(meta["description"] as? String, "Review prompts before sending.")
        XCTAssertEqual(manifest["version"] as? String, "1.0")
        XCTAssertEqual(valves["strict"] as? Bool, true)
        XCTAssertEqual(valves["limit"] as? Int, 3)
        XCTAssertEqual(record["is_active"] as? Bool, true)
        XCTAssertEqual(record["is_global"] as? Bool, false)
        XCTAssertEqual(record["created_at"] as? Int, 1_000)
        XCTAssertEqual(record["updated_at"] as? Int, 2_000)
    }

    func testShareFunctionSharesSelectedFunctionJSON() async throws {
        let shareService = FakeFunctionShareService()
        let fixture = try FunctionLibraryFixture(shareService: shareService)
        let store = fixture.makeStore()
        await store.load()
        await store.createFunction(
            name: "Safety filter",
            kind: .filter,
            content: "def inlet(body):\n    return body",
            description: "Review prompts before sending."
        )
        await store.createFunction(
            name: "Summarize action",
            kind: .action,
            content: "def action(body):\n    return body",
            description: "Summarize selected content."
        )
        let function = try XCTUnwrap(store.functions.first { $0.name == "Safety filter" })

        store.shareFunction(function.id)

        XCTAssertEqual(shareService.sharedTitle, "Safety filter")
        let sharedText = try XCTUnwrap(shareService.sharedText)
        let sharedFunctions = try FunctionExportService().functions(fromJSONData: Data(sharedText.utf8))
        XCTAssertEqual(sharedFunctions.map(\.name), ["Safety filter"])
        XCTAssertEqual(sharedFunctions.first?.kind, .filter)
        XCTAssertEqual(sharedFunctions.first?.description, "Review prompts before sending.")
    }

    func testImportFunctionsJSONAcceptsOpenWebUIFunctionRecords() async throws {
        let fixture = try FunctionLibraryFixture()
        let store = fixture.makeStore()
        await store.load()
        let data = Data(
            """
            [
              {
                "id": "safety_filter",
                "user_id": "user-id",
                "name": "Safety Filter",
                "type": "filter",
                "content": "def inlet(body):\\n    return body",
                "meta": {
                  "description": "Review prompts before sending.",
                  "manifest": { "version": "1.0", "author": "Open WebUI" },
                  "toggle": true
                },
                "valves": {
                  "strict": true
                },
                "is_active": true,
                "is_global": false,
                "created_at": 1000,
                "updated_at": 2000
              }
            ]
            """.utf8
        )

        try await store.importFunctionsJSONData(data)

        let function = try XCTUnwrap(store.functions.first)
        XCTAssertEqual(function.id, "safety_filter")
        XCTAssertEqual(function.name, "Safety Filter")
        XCTAssertEqual(function.kind, .filter)
        XCTAssertEqual(function.description, "Review prompts before sending.")
        XCTAssertEqual(function.manifest?.objectValue?["version"], .string("1.0"))
        XCTAssertEqual(function.valves?.objectValue?["strict"], .bool(true))
        XCTAssertEqual(function.isActive, true)
        XCTAssertEqual(function.isGlobal, false)
    }

    func testCreateFunctionIsBlockedWhenFunctionsFeatureIsDisabled() async throws {
        let fixture = try FunctionLibraryFixture()
        let store = fixture.makeStore()
        await store.load()
        await store.setFeatureToggle(.functions, isEnabled: false)

        await store.createFunction(
            name: "Hidden function",
            kind: .filter,
            content: "def inlet(body):\n    return body",
            description: "Should not persist."
        )

        XCTAssertTrue(store.functions.isEmpty)
        XCTAssertEqual(store.errorMessage, "Functions is disabled.")
        let saved = try await fixture.functionStorage.loadFunctions()
        XCTAssertTrue(saved.isEmpty)
    }

    func testFunctionLibraryActionsAreBlockedWhenFunctionsFeatureIsDisabled() async throws {
        let shareService = FakeFunctionShareService()
        let fixture = try FunctionLibraryFixture(shareService: shareService)
        let store = fixture.makeStore()
        await store.load()
        await store.createFunction(
            name: "Existing function",
            kind: .action,
            content: "def action(body):\n    return body",
            description: "Existing content."
        )
        let function = try XCTUnwrap(store.functions.first)
        await store.setFeatureToggle(.functions, isEnabled: false)

        await store.updateFunction(
            function.id,
            name: "Blocked update",
            kind: .pipe,
            content: "def pipe(body):\n    return body",
            description: "Blocked content.",
            isActive: true,
            isGlobal: true
        )
        await store.deleteFunction(function.id)
        let data = try FunctionExportService().jsonData(for: [
            AppFunction(name: "Blocked import", kind: .filter, content: "inlet()", description: nil)
        ])
        try await store.importFunctionsJSONData(data)
        store.shareFunction(function.id)

        let unchangedFunction = try XCTUnwrap(store.functions.first)
        XCTAssertEqual(store.functions.count, 1)
        XCTAssertEqual(unchangedFunction.name, "Existing function")
        XCTAssertEqual(unchangedFunction.kind, .action)
        XCTAssertEqual(unchangedFunction.content, "def action(body):\n    return body")
        XCTAssertEqual(unchangedFunction.description, "Existing content.")
        XCTAssertFalse(unchangedFunction.isActive)
        XCTAssertFalse(unchangedFunction.isGlobal)
        XCTAssertNil(shareService.sharedText)
        XCTAssertNil(shareService.sharedTitle)
        XCTAssertEqual(store.errorMessage, "Functions is disabled.")

        let saved = try await fixture.functionStorage.loadFunctions()
        let savedFunction = try XCTUnwrap(saved.first)
        XCTAssertEqual(saved.count, 1)
        XCTAssertEqual(savedFunction.name, "Existing function")
        XCTAssertEqual(savedFunction.content, "def action(body):\n    return body")
    }

    func testFunctionWritePermissionAllowsCreateUpdateDeleteAndImportForCurrentUser() async throws {
        let fixture = try FunctionLibraryFixture()
        let store = fixture.makeStore()
        await store.load()
        await store.createAdminUser(name: "Workspace User", email: "user@example.com", role: .user)
        let user = try XCTUnwrap(store.adminUsers.first)
        await store.createAdminGroup(name: "Function Editors", description: "Can manage functions.", permissions: ["functions.write"])
        let group = try XCTUnwrap(store.adminGroups.first)
        await store.setAdminGroupMembers(group.id, memberIDs: [user.id])
        store.currentUserID = user.id

        await store.createFunction(name: "Safety filter", kind: .filter, content: "inlet()", description: "Filter")
        let function = try XCTUnwrap(store.functions.first)
        await store.updateFunction(
            function.id,
            name: "Updated filter",
            kind: .pipe,
            content: "pipe()",
            description: "Pipe",
            isActive: true,
            isGlobal: true
        )
        let updatedFunction = try XCTUnwrap(store.functions.first)
        await store.deleteFunction(updatedFunction.id)

        let data = try FunctionExportService().jsonData(for: [
            AppFunction(name: "Imported action", kind: .action, content: "action()", description: "Action")
        ])
        try await store.importFunctionsJSONData(data)

        XCTAssertEqual(store.functions.map(\.name), ["Imported action"])
        XCTAssertNil(store.errorMessage)
        XCTAssertTrue(store.auditEvents.contains { $0.action.rawValue == "functionCreated" })
        XCTAssertTrue(store.auditEvents.contains { $0.action.rawValue == "functionUpdated" })
        XCTAssertTrue(store.auditEvents.contains { $0.action.rawValue == "functionDeleted" })
    }

    func testFunctionWritePermissionBlocksCreateUpdateDeleteAndImportForCurrentUser() async throws {
        let fixture = try FunctionLibraryFixture()
        let store = fixture.makeStore()
        await store.load()
        await store.createAdminUser(name: "Workspace User", email: "user@example.com", role: .user)
        let user = try XCTUnwrap(store.adminUsers.first)
        store.currentUserID = user.id

        await store.createFunction(name: "Blocked function", kind: .filter, content: "blocked()", description: nil)

        XCTAssertTrue(store.functions.isEmpty)
        XCTAssertEqual(store.errorMessage, "You do not have permission to manage functions.")

        store.errorMessage = nil
        store.currentUserID = "local-admin"
        await store.createAdminUser(name: "Local Admin", email: "admin@example.com", role: .admin)
        let admin = try XCTUnwrap(store.adminUsers.first { $0.role == .admin })
        store.currentUserID = admin.id
        await store.createFunction(name: "Existing function", kind: .action, content: "existing()", description: "Existing content.")
        let function = try XCTUnwrap(store.functions.first)

        store.currentUserID = user.id
        await store.updateFunction(
            function.id,
            name: "Blocked update",
            kind: .pipe,
            content: "updated()",
            description: nil,
            isActive: true,
            isGlobal: true
        )
        await store.deleteFunction(function.id)
        let data = try FunctionExportService().jsonData(for: [
            AppFunction(name: "Blocked import", kind: .filter, content: "imported()", description: nil)
        ])
        try await store.importFunctionsJSONData(data)

        XCTAssertEqual(store.functions.first?.name, "Existing function")
        XCTAssertEqual(store.functions.first?.content, "existing()")
        XCTAssertEqual(store.errorMessage, "You do not have permission to manage functions.")
        XCTAssertFalse(store.auditEvents.contains { $0.action.rawValue == "functionUpdated" })
        XCTAssertFalse(store.auditEvents.contains { $0.action.rawValue == "functionDeleted" })
    }

    func testUnmanagedLocalUserCanManageFunctionsWhenAdminDirectoryExists() async throws {
        let fixture = try FunctionLibraryFixture()
        let store = fixture.makeStore()
        await store.load()
        await store.createAdminUser(name: "Workspace User", email: "user@example.com", role: .user)

        await store.createFunction(name: "Local function", kind: .filter, content: "local()", description: nil)

        XCTAssertEqual(store.functions.map(\.name), ["Local function"])
        XCTAssertNil(store.errorMessage)
    }

    func testFunctionExecutePermissionAllowsLocalFunctionRunForCurrentUser() async throws {
        let runID = UUID(uuidString: "00000000-0000-0000-0000-00000000F007")!
        let run = AppFunctionRun(
            id: runID,
            functionID: "function-id",
            functionName: "Safety filter",
            functionKind: .filter,
            methodName: "inlet",
            inputBody: #"{"body":{"messages":[]}}"#,
            output: #"{"body":{"messages":[]}}"#,
            stderr: "",
            status: .succeeded,
            exitCode: 0,
            startedAt: Date(timeIntervalSince1970: 300),
            completedAt: Date(timeIntervalSince1970: 301)
        )
        let executor = FakeLocalFunctionExecutor(run: run)
        let fixture = try FunctionLibraryFixture(functionExecutor: executor)
        let store = fixture.makeStore()
        await store.load()
        await store.createFunction(
            name: "Safety filter",
            kind: .filter,
            content: "def inlet(body):\n    return body",
            description: "Review prompts before sending."
        )
        let function = try XCTUnwrap(store.functions.first)
        await store.createAdminUser(name: "Workspace User", email: "user@example.com", role: .user)
        let user = try XCTUnwrap(store.adminUsers.first)
        await store.createAdminGroup(
            name: "Function Runners",
            description: "Can run functions.",
            permissions: ["functions.execute"]
        )
        let group = try XCTUnwrap(store.adminGroups.first)
        await store.setAdminGroupMembers(group.id, memberIDs: [user.id])
        store.currentUserID = user.id

        await store.runFunction(function.id, methodName: "inlet", inputBody: #" { "body": { "messages": [] } } "#)

        let capturedRequests = await executor.capturedRequests
        XCTAssertEqual(capturedRequests.map(\.function.id), [function.id])
        XCTAssertEqual(capturedRequests.first?.methodName, "inlet")
        XCTAssertEqual(capturedRequests.first?.input, .object(["body": .object(["messages": .array([])])]))
        XCTAssertEqual(store.functionRuns.map(\.id), [runID])
        XCTAssertEqual(store.selectedFunctionRunID, runID)
        XCTAssertFalse(store.isRunningFunction)
        XCTAssertNil(store.functionExecutionError)
        XCTAssertNil(store.errorMessage)
        XCTAssertEqual(store.auditEvents.first?.action, .functionInvoked)
        XCTAssertEqual(store.auditEvents.first?.metadata["functionID"], "function-id")

        let reloadedStore = fixture.makeStore()
        await reloadedStore.load()

        XCTAssertEqual(reloadedStore.functionRuns.map(\.id), [runID])
        XCTAssertEqual(reloadedStore.functionRuns.first?.output, #"{"body":{"messages":[]}}"#)
    }

    func testFunctionExecutePermissionBlocksLocalFunctionRunForCurrentUser() async throws {
        let executor = FakeLocalFunctionExecutor()
        let fixture = try FunctionLibraryFixture(functionExecutor: executor)
        let store = fixture.makeStore()
        await store.load()
        await store.createFunction(
            name: "Safety filter",
            kind: .filter,
            content: "def inlet(body):\n    return body",
            description: "Review prompts before sending."
        )
        let function = try XCTUnwrap(store.functions.first)
        await store.createAdminUser(name: "Workspace User", email: "user@example.com", role: .user)
        let user = try XCTUnwrap(store.adminUsers.first)
        await store.createAdminGroup(
            name: "Function Editors",
            description: "Can manage functions.",
            permissions: ["functions.write"]
        )
        let group = try XCTUnwrap(store.adminGroups.first)
        await store.setAdminGroupMembers(group.id, memberIDs: [user.id])
        store.currentUserID = user.id

        await store.runFunction(function.id, methodName: "inlet", inputBody: #"{"body":{"messages":[]}}"#)

        let capturedRequests = await executor.capturedRequests
        XCTAssertTrue(capturedRequests.isEmpty)
        XCTAssertTrue(store.functionRuns.isEmpty)
        XCTAssertEqual(store.functionExecutionError, "You do not have permission to run functions.")
        XCTAssertEqual(store.errorMessage, "You do not have permission to run functions.")
        XCTAssertFalse(store.isRunningFunction)
    }

    func testLocalFunctionExecutionBlocksDisabledFeatureBeforeCallingExecutor() async throws {
        let schemaRun = AppFunctionRun(
            functionID: "function-id",
            functionName: "Safety filter",
            functionKind: .filter,
            methodName: "__native_valves_schema",
            inputBody: "{}",
            output: #"{"type":"object","properties":{"limit":{"type":"integer"}}}"#,
            stderr: "",
            status: .succeeded,
            exitCode: 0
        )
        let executor = FakeLocalFunctionExecutor(methodRuns: ["__native_valves_schema": schemaRun])
        let fixture = try FunctionLibraryFixture(functionExecutor: executor)
        let store = fixture.makeStore()
        await store.load()
        await store.createFunction(
            name: "Assistant action",
            kind: .action,
            content: "class Valves:\n    pass\ndef action(body):\n    return body",
            description: "Run an assistant action."
        )
        let function = try XCTUnwrap(store.functions.first)
        await store.updateFunction(
            function.id,
            name: function.name,
            kind: function.kind,
            content: function.content,
            description: function.description,
            isActive: true,
            isGlobal: true
        )
        let activeFunction = try XCTUnwrap(store.functions.first)
        await store.setFeatureToggle(.functions, isEnabled: false)

        let template = await store.functionValvesTemplateJSON(
            name: activeFunction.name,
            kind: activeFunction.kind,
            content: activeFunction.content
        )
        await store.runFunction(activeFunction.id, methodName: "action", inputBody: #"{"body":{"messages":[]}}"#)

        let capturedRequests = await executor.capturedRequests
        XCTAssertNil(template)
        XCTAssertTrue(store.activeActionFunctions.isEmpty)
        XCTAssertTrue(capturedRequests.isEmpty)
        XCTAssertTrue(store.functionRuns.isEmpty)
        XCTAssertEqual(store.functionExecutionError, "Functions is disabled.")
        XCTAssertEqual(store.errorMessage, "Functions is disabled.")
        XCTAssertFalse(store.isRunningFunction)
        let persistedRuns = try await fixture.functionRunStorage.loadRuns()
        XCTAssertTrue(persistedRuns.isEmpty)
    }

    func testSendPromptAppliesActiveFilterInletBeforeProviderStream() async throws {
        let provider = CapturingFunctionChatProvider(chunks: ["provider answer"])
        let inletRun = AppFunctionRun(
            functionID: "function-id",
            functionName: "Rewrite prompt",
            functionKind: .filter,
            methodName: "inlet",
            inputBody: "{}",
            output: #"{"messages":[{"role":"user","content":"filtered prompt"}]}"#,
            stderr: "",
            status: .succeeded,
            exitCode: 0
        )
        let executor = FakeLocalFunctionExecutor(run: inletRun)
        let fixture = try FunctionLibraryFixture(functionExecutor: executor, provider: provider)
        let store = fixture.makeStore()
        await store.load()
        await store.selectModel("fake-model")
        await store.createFunction(
            name: "Rewrite prompt",
            kind: .filter,
            content: "def inlet(body):\n    return body",
            description: "Mutate outgoing chat body."
        )
        let function = try XCTUnwrap(store.functions.first)
        await store.updateFunction(
            function.id,
            name: function.name,
            kind: function.kind,
            content: function.content,
            description: function.description,
            isActive: true,
            isGlobal: true
        )

        await store.send("original prompt")

        let providerMessages = await provider.messages()
        XCTAssertEqual(providerMessages.last, ProviderChatMessage(role: "user", content: "filtered prompt"))
        XCTAssertEqual(store.selectedThread?.messages.first?.content, "original prompt")
        XCTAssertEqual(store.functionRuns.map(\.methodName), ["inlet"])
        XCTAssertEqual(store.auditEvents.first?.action, .functionInvoked)
    }

    func testSendPromptAppliesActiveFilterOutletAfterProviderStream() async throws {
        let provider = CapturingFunctionChatProvider(chunks: ["raw answer"])
        let outletRun = AppFunctionRun(
            functionID: "function-id",
            functionName: "Rewrite answer",
            functionKind: .filter,
            methodName: "outlet",
            inputBody: "{}",
            output: #"{"messages":[{"role":"user","content":"question"},{"role":"assistant","content":"filtered answer"}]}"#,
            stderr: "",
            status: .succeeded,
            exitCode: 0
        )
        let executor = FakeLocalFunctionExecutor(run: outletRun)
        let fixture = try FunctionLibraryFixture(functionExecutor: executor, provider: provider)
        let store = fixture.makeStore()
        await store.load()
        await store.selectModel("fake-model")
        await store.createFunction(
            name: "Rewrite answer",
            kind: .filter,
            content: "def outlet(body):\n    return body",
            description: "Mutate incoming chat body."
        )
        let function = try XCTUnwrap(store.functions.first)
        await store.updateFunction(
            function.id,
            name: function.name,
            kind: function.kind,
            content: function.content,
            description: function.description,
            isActive: true,
            isGlobal: true
        )

        await store.send("question")

        let assistant = try XCTUnwrap(store.selectedThread?.messages.last)
        XCTAssertEqual(assistant.role, .assistant)
        XCTAssertEqual(assistant.content, "filtered answer")
        XCTAssertEqual(store.functionRuns.map(\.methodName), ["outlet"])
        XCTAssertEqual(store.auditEvents.first?.action, .functionInvoked)
    }

    func testActivePipeFunctionAppearsAsSelectableModel() async throws {
        let provider = CapturingFunctionChatProvider(chunks: ["provider answer"])
        let fixture = try FunctionLibraryFixture(provider: provider)
        let store = fixture.makeStore()
        await store.load()
        await store.createFunction(
            name: "Local pipe",
            kind: .pipe,
            content: "def pipe(body):\n    return 'pipe answer'",
            description: "Answer through local Python."
        )
        let function = try XCTUnwrap(store.functions.first)
        await store.updateFunction(
            function.id,
            name: function.name,
            kind: function.kind,
            content: function.content,
            description: function.description,
            isActive: true,
            isGlobal: false
        )

        await store.refreshModels()

        let pipeModel = try XCTUnwrap(store.models.first { $0.id == function.id })
        XCTAssertEqual(pipeModel.name, "Local pipe")
        XCTAssertEqual(pipeModel.provider, .localFunction)
        XCTAssertEqual(pipeModel.details, "Native pipe function")
    }

    func testSendPromptStreamsSelectedPipeFunctionInsteadOfProvider() async throws {
        let provider = CapturingFunctionChatProvider(chunks: ["provider answer"])
        let pipeRun = AppFunctionRun(
            functionID: "function-id",
            functionName: "Local pipe",
            functionKind: .pipe,
            methodName: "pipe",
            inputBody: "{}",
            output: "pipe answer",
            stderr: "",
            status: .succeeded,
            exitCode: 0
        )
        let executor = FakeLocalFunctionExecutor(run: pipeRun)
        let fixture = try FunctionLibraryFixture(functionExecutor: executor, provider: provider)
        let store = fixture.makeStore()
        await store.load()
        await store.createFunction(
            name: "Local pipe",
            kind: .pipe,
            content: "def pipe(body):\n    return 'pipe answer'",
            description: "Answer through local Python."
        )
        let function = try XCTUnwrap(store.functions.first)
        await store.updateFunction(
            function.id,
            name: function.name,
            kind: function.kind,
            content: function.content,
            description: function.description,
            isActive: true,
            isGlobal: false
        )
        await store.selectModel(function.id)

        await store.send("Use the pipe")

        let assistant = try XCTUnwrap(store.selectedThread?.messages.last)
        XCTAssertEqual(assistant.role, .assistant)
        XCTAssertEqual(assistant.modelID, function.id)
        XCTAssertEqual(assistant.content, "pipe answer")
        XCTAssertNil(assistant.error)
        let capturedRequests = await executor.capturedRequests
        XCTAssertEqual(capturedRequests.map(\.methodName), ["pipe"])
        XCTAssertEqual(capturedRequests.first?.function.id, function.id)
        XCTAssertEqual(capturedRequests.first?.input.objectValue?["body"]?.objectValue?["model"], .string(function.id))
        XCTAssertEqual(store.functionRuns.map(\.methodName), ["pipe"])
        XCTAssertEqual(store.auditEvents.first?.action, .functionInvoked)
        let providerStreamCount = await provider.streamCallCount()
        XCTAssertEqual(providerStreamCount, 0)
    }

    func testActiveManifoldPipeFunctionAppearsAsSelectableSubModels() async throws {
        let provider = CapturingFunctionChatProvider(chunks: ["provider answer"])
        let pipesRun = AppFunctionRun(
            functionID: "function-id",
            functionName: "Router pipe",
            functionKind: .pipe,
            methodName: "pipes",
            inputBody: "{}",
            output: #"[{"id":"small","name":"Small"},{"id":"large","name":"Large"}]"#,
            stderr: "",
            status: .succeeded,
            exitCode: 0
        )
        let executor = FakeLocalFunctionExecutor(methodRuns: ["pipes": pipesRun])
        let fixture = try FunctionLibraryFixture(functionExecutor: executor, provider: provider)
        let store = fixture.makeStore()
        await store.load()
        await store.createFunction(
            name: "Router pipe",
            kind: .pipe,
            content: "def pipes():\n    return []\ndef pipe(body):\n    return 'answer'",
            description: "Expose multiple local pipe models."
        )
        let function = try XCTUnwrap(store.functions.first)
        await store.updateFunction(
            function.id,
            name: function.name,
            kind: function.kind,
            content: function.content,
            description: function.description,
            isActive: true,
            isGlobal: false
        )

        await store.refreshModels()

        let subModels = store.models.filter { $0.provider == .localFunction }
        XCTAssertEqual(subModels.map(\.id), ["\(function.id).small", "\(function.id).large"])
        XCTAssertEqual(subModels.map(\.name), ["Router pipe Small", "Router pipe Large"])
        XCTAssertEqual(subModels.map(\.details), ["Native manifold pipe function", "Native manifold pipe function"])
        XCTAssertTrue(store.functionRuns.isEmpty)
        let capturedRequests = await executor.capturedRequests
        XCTAssertEqual(capturedRequests.map(\.methodName), ["pipes"])
    }

    func testSendPromptStreamsSelectedManifoldPipeSubModelThroughParentFunction() async throws {
        let provider = CapturingFunctionChatProvider(chunks: ["provider answer"])
        let pipeRun = AppFunctionRun(
            functionID: "function-id",
            functionName: "Router pipe",
            functionKind: .pipe,
            methodName: "pipe",
            inputBody: "{}",
            output: "manifold answer",
            stderr: "",
            status: .succeeded,
            exitCode: 0
        )
        let executor = FakeLocalFunctionExecutor(methodRuns: ["pipe": pipeRun])
        let fixture = try FunctionLibraryFixture(functionExecutor: executor, provider: provider)
        let store = fixture.makeStore()
        await store.load()
        await store.createFunction(
            name: "Router pipe",
            kind: .pipe,
            content: "def pipes():\n    return []\ndef pipe(body):\n    return 'answer'",
            description: "Expose multiple local pipe models."
        )
        let function = try XCTUnwrap(store.functions.first)
        await store.updateFunction(
            function.id,
            name: function.name,
            kind: function.kind,
            content: function.content,
            description: function.description,
            isActive: true,
            isGlobal: false
        )
        await store.selectModel("\(function.id).small")

        await store.send("Use the small route")

        let assistant = try XCTUnwrap(store.selectedThread?.messages.last)
        XCTAssertEqual(assistant.modelID, "\(function.id).small")
        XCTAssertEqual(assistant.content, "manifold answer")
        let capturedRequests = await executor.capturedRequests
        XCTAssertEqual(capturedRequests.map(\.methodName), ["pipe"])
        XCTAssertEqual(capturedRequests.first?.function.id, function.id)
        XCTAssertEqual(capturedRequests.first?.input.objectValue?["body"]?.objectValue?["model"], .string("\(function.id).small"))
        XCTAssertEqual(store.functionRuns.map(\.methodName), ["pipe"])
        let providerStreamCount = await provider.streamCallCount()
        XCTAssertEqual(providerStreamCount, 0)
    }

    func testSelectedPipeFunctionDoesNotEnableOllamaModelDeletion() async throws {
        let fixture = try FunctionLibraryFixture(provider: CapturingFunctionChatProvider(chunks: ["provider answer"]))
        let store = fixture.makeStore()
        await store.load()
        await store.createFunction(
            name: "Local pipe",
            kind: .pipe,
            content: "def pipe(body):\n    return 'pipe answer'",
            description: nil
        )
        let function = try XCTUnwrap(store.functions.first)
        await store.updateFunction(
            function.id,
            name: function.name,
            kind: function.kind,
            content: function.content,
            description: function.description,
            isActive: true,
            isGlobal: false
        )
        await store.selectModel(function.id)

        XCTAssertFalse(store.canDeleteSelectedOllamaModel)
    }

    func testActiveActionFunctionsAreAvailableForAssistantMessages() async throws {
        let fixture = try FunctionLibraryFixture()
        let store = fixture.makeStore()
        await store.load()
        await store.createFunction(
            name: "Explain answer",
            kind: .action,
            content: "def action(body):\n    return body",
            description: "Explain the selected response."
        )
        await store.createFunction(
            name: "Inactive action",
            kind: .action,
            content: "def action(body):\n    return body",
            description: nil
        )
        await store.createFunction(
            name: "Active filter",
            kind: .filter,
            content: "def inlet(body):\n    return body",
            description: nil
        )
        let action = try XCTUnwrap(store.functions.first { $0.name == "Explain answer" })
        let filter = try XCTUnwrap(store.functions.first { $0.name == "Active filter" })
        await store.updateFunction(
            action.id,
            name: action.name,
            kind: action.kind,
            content: action.content,
            description: action.description,
            isActive: true,
            isGlobal: true
        )
        await store.updateFunction(
            filter.id,
            name: filter.name,
            kind: filter.kind,
            content: filter.content,
            description: filter.description,
            isActive: true,
            isGlobal: true
        )

        XCTAssertEqual(store.activeActionFunctions.map(\.name), ["Explain answer"])
    }

    func testRunActionFunctionSendsAssistantMessageContextAndPersistsRun() async throws {
        let actionRun = AppFunctionRun(
            functionID: "action-id",
            functionName: "Explain answer",
            functionKind: .action,
            methodName: "action",
            inputBody: "{}",
            output: "saved",
            stderr: "",
            status: .succeeded,
            exitCode: 0
        )
        let executor = FakeLocalFunctionExecutor(run: actionRun)
        let fixture = try FunctionLibraryFixture(functionExecutor: executor)
        let store = fixture.makeStore()
        await store.load()
        await store.createFunction(
            name: "Explain answer",
            kind: .action,
            content: "def action(body):\n    return 'saved'",
            description: "Run against an assistant response."
        )
        let function = try XCTUnwrap(store.functions.first)
        await store.updateFunction(
            function.id,
            name: function.name,
            kind: function.kind,
            content: function.content,
            description: function.description,
            isActive: true,
            isGlobal: true
        )
        let userID = UUID(uuidString: "00000000-0000-0000-0000-000000000101")!
        let assistantID = UUID(uuidString: "00000000-0000-0000-0000-000000000202")!
        let thread = ChatThread(
            title: "Action thread",
            messages: [
                ChatMessage(id: userID, role: .user, content: "Question"),
                ChatMessage(id: assistantID, role: .assistant, content: "Answer", modelID: "fake-model")
            ]
        )
        try await fixture.storage.save(thread)
        await store.load()
        store.selectedThreadID = thread.id

        await store.runActionFunction(function.id, messageID: assistantID)

        let capturedRequests = await executor.capturedRequests
        XCTAssertEqual(capturedRequests.map(\.function.id), [function.id])
        XCTAssertEqual(capturedRequests.first?.methodName, "action")
        let body = try XCTUnwrap(capturedRequests.first?.input.objectValue?["body"]?.objectValue)
        XCTAssertEqual(body["message"]?.objectValue?["id"], .string(assistantID.uuidString))
        XCTAssertEqual(body["message"]?.objectValue?["role"], .string("assistant"))
        XCTAssertEqual(body["message"]?.objectValue?["content"], .string("Answer"))
        XCTAssertEqual(body["thread"]?.objectValue?["id"], .string(thread.id.uuidString))
        XCTAssertEqual(body["thread"]?.objectValue?["title"], .string("Action thread"))
        if case .array(let messages)? = body["messages"] {
            XCTAssertEqual(messages.count, 2)
        } else {
            XCTFail("Expected action body to include message history.")
        }
        XCTAssertEqual(store.functionRuns.map(\.methodName), ["action"])
        XCTAssertEqual(store.auditEvents.first?.action, .functionInvoked)
        XCTAssertEqual(store.functionExecutionError, nil)
    }
}

private struct FunctionLibraryFixture {
    let rootURL: URL
    let storage: JSONStorageService
    let folderStorage: JSONFolderStorageService
    let promptStorage: JSONPromptStorageService
    let noteStorage: JSONNoteStorageService
    let toolStorage: JSONToolStorageService
    let functionStorage: JSONFunctionStorageService
    let functionRunStorage: JSONFunctionRunStorageService
    let functionExecutor: any LocalFunctionExecuting
    let auditStorage: JSONAuditLogStorageService
    let adminStorage: JSONAdminDirectoryStorageService
    let settingsStore: SettingsStore
    let provider: (any ChatProvider)?
    let shareService: FakeFunctionShareService?

    init(
        functionExecutor: any LocalFunctionExecuting = FakeLocalFunctionExecutor(),
        provider: (any ChatProvider)? = nil,
        shareService: FakeFunctionShareService? = nil
    ) throws {
        rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        storage = JSONStorageService(rootURL: rootURL.appendingPathComponent("Chats", isDirectory: true))
        folderStorage = JSONFolderStorageService(rootURL: rootURL.appendingPathComponent("Folders", isDirectory: true))
        promptStorage = JSONPromptStorageService(rootURL: rootURL.appendingPathComponent("Prompts", isDirectory: true))
        noteStorage = JSONNoteStorageService(rootURL: rootURL.appendingPathComponent("Notes", isDirectory: true))
        toolStorage = JSONToolStorageService(rootURL: rootURL.appendingPathComponent("Tools", isDirectory: true))
        functionStorage = JSONFunctionStorageService(
            rootURL: rootURL.appendingPathComponent("Functions", isDirectory: true)
        )
        functionRunStorage = JSONFunctionRunStorageService(
            rootURL: rootURL.appendingPathComponent("FunctionRuns", isDirectory: true)
        )
        self.functionExecutor = functionExecutor
        auditStorage = JSONAuditLogStorageService(rootURL: rootURL.appendingPathComponent("AuditLog", isDirectory: true))
        adminStorage = JSONAdminDirectoryStorageService(
            snapshotURL: rootURL.appendingPathComponent("admin-directory.json")
        )
        settingsStore = SettingsStore(settingsURL: rootURL.appendingPathComponent("settings.json"))
        self.provider = provider
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
            providerOverride: provider,
            shareService: shareService ?? FakeFunctionShareService(),
            auditLogStorage: auditStorage,
            promptStorage: promptStorage,
            noteStorage: noteStorage,
            toolStorage: toolStorage,
            functionStorage: functionStorage,
            functionRunStorage: functionRunStorage,
            functionExecutor: functionExecutor,
            adminDirectoryStorage: adminStorage
        )
    }
}

@MainActor
private final class FakeFunctionShareService: ChatSharing {
    private(set) var sharedText: String?
    private(set) var sharedTitle: String?

    func share(text: String, title: String) {
        sharedText = text
        sharedTitle = title
    }
}

private actor FakeLocalFunctionExecutor: LocalFunctionExecuting {
    private let run: AppFunctionRun
    private let methodRuns: [String: AppFunctionRun]
    private(set) var capturedRequests: [LocalFunctionInvocationRequest] = []

    init(
        run: AppFunctionRun = AppFunctionRun(
            functionID: "function-id",
            functionName: "Safety filter",
            functionKind: .filter,
            methodName: "inlet",
            inputBody: "{}",
            output: "{}",
            stderr: "",
            status: .succeeded,
            exitCode: 0
        )
    ) {
        self.run = run
        self.methodRuns = [:]
    }

    init(methodRuns: [String: AppFunctionRun]) {
        self.run = AppFunctionRun(
            functionID: "function-id",
            functionName: "Safety filter",
            functionKind: .filter,
            methodName: "inlet",
            inputBody: "{}",
            output: "{}",
            stderr: "",
            status: .succeeded,
            exitCode: 0
        )
        self.methodRuns = methodRuns
    }

    func invoke(_ request: LocalFunctionInvocationRequest) async -> AppFunctionRun {
        capturedRequests.append(request)
        return methodRuns[request.methodName] ?? run
    }
}

private actor CapturingFunctionChatProvider: ChatProvider {
    nonisolated let configuration = ProviderConfiguration.defaultOllama()
    private let chunks: [String]
    private var capturedMessages: [ProviderChatMessage] = []
    private var streamCount = 0

    init(chunks: [String]) {
        self.chunks = chunks
    }

    func listModels() async throws -> [ProviderModel] {
        [ProviderModel(id: "fake-model", name: "fake-model", provider: .ollama, providerID: configuration.id)]
    }

    func healthCheck() async -> ProviderStatus {
        .available("Fake connected")
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
        []
    }

    func messages() -> [ProviderChatMessage] {
        capturedMessages
    }

    func streamCallCount() -> Int {
        streamCount
    }

    private func capture(_ messages: [ProviderChatMessage]) {
        streamCount += 1
        capturedMessages = messages
    }
}
