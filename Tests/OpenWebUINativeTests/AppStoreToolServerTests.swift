import XCTest
@testable import OpenWebUINative

@MainActor
final class AppStoreToolServerTests: XCTestCase {
    func testCreateToolServerPersistsAndReloads() async throws {
        let fixture = try ToolServerFixture()
        let store = fixture.makeStore()
        await store.load()

        await store.createToolServer(
            name: " Local MCP ",
            kind: .stdio,
            command: "  uvx  ",
            argumentsText: "mcp-server-filesystem, /Users/xtrasalty",
            baseURL: "",
            environmentText: "TOKEN=secret\nEMPTY=",
            isEnabled: true
        )

        let server = try XCTUnwrap(store.toolServers.first)
        XCTAssertEqual(server.name, "Local MCP")
        XCTAssertEqual(server.kind, .stdio)
        XCTAssertEqual(server.command, "uvx")
        XCTAssertEqual(server.arguments, ["mcp-server-filesystem", "/Users/xtrasalty"])
        XCTAssertEqual(server.environment["TOKEN"], "secret")
        XCTAssertNil(server.environment["EMPTY"])
        XCTAssertTrue(server.isEnabled)

        let reloadedStore = fixture.makeStore()
        await reloadedStore.load()

        XCTAssertEqual(reloadedStore.toolServers.first?.name, "Local MCP")
        XCTAssertEqual(reloadedStore.toolServers.first?.command, "uvx")
    }

    func testCreateHTTPToolServerRequiresURLAndClearsCommandFields() async throws {
        let fixture = try ToolServerFixture()
        let store = fixture.makeStore()
        await store.load()

        await store.createToolServer(
            name: "Tool Gateway",
            kind: .http,
            command: "uvx",
            argumentsText: "ignored",
            baseURL: "  http://localhost:3333/mcp  ",
            environmentText: "IGNORED=value",
            isEnabled: false
        )

        let server = try XCTUnwrap(store.toolServers.first)
        XCTAssertEqual(server.kind, .http)
        XCTAssertEqual(server.baseURL, "http://localhost:3333/mcp")
        XCTAssertNil(server.command)
        XCTAssertTrue(server.arguments.isEmpty)
        XCTAssertTrue(server.environment.isEmpty)
        XCTAssertFalse(server.isEnabled)
    }

    func testUpdateToolServerSortsMostRecentlyUpdatedFirst() async throws {
        let fixture = try ToolServerFixture()
        let store = fixture.makeStore()
        await store.load()
        await store.createToolServer(name: "First", kind: .stdio, command: "first", argumentsText: "", baseURL: "", environmentText: "", isEnabled: true)
        await store.createToolServer(name: "Second", kind: .stdio, command: "second", argumentsText: "", baseURL: "", environmentText: "", isEnabled: true)
        let first = try XCTUnwrap(store.toolServers.first { $0.name == "First" })

        await store.updateToolServer(
            first.id,
            name: "Updated first",
            kind: .http,
            command: "",
            argumentsText: "",
            baseURL: "http://localhost:7777",
            environmentText: "",
            isEnabled: false
        )

        XCTAssertEqual(store.toolServers.map(\.name), ["Updated first", "Second"])
        XCTAssertEqual(store.toolServers.first?.kind, .http)
        XCTAssertEqual(store.toolServers.first?.baseURL, "http://localhost:7777")
        XCTAssertFalse(store.toolServers.first?.isEnabled ?? true)
    }

    func testDeleteToolServerRemovesPersistedRecord() async throws {
        let fixture = try ToolServerFixture()
        let store = fixture.makeStore()
        await store.load()
        await store.createToolServer(name: "Temporary", kind: .stdio, command: "temp", argumentsText: "", baseURL: "", environmentText: "", isEnabled: true)
        let server = try XCTUnwrap(store.toolServers.first)

        await store.deleteToolServer(server.id)

        let reloadedStore = fixture.makeStore()
        await reloadedStore.load()
        XCTAssertTrue(reloadedStore.toolServers.isEmpty)
    }

    func testExportAndImportToolServersJSONRoundTripsRegistry() async throws {
        let fixture = try ToolServerFixture()
        let store = fixture.makeStore()
        await store.load()
        await store.createToolServer(name: "Local MCP", kind: .stdio, command: "uvx", argumentsText: "server", baseURL: "", environmentText: "", isEnabled: true)
        await store.createToolServer(name: "HTTP MCP", kind: .http, command: "", argumentsText: "", baseURL: "http://localhost:3333/mcp", environmentText: "", isEnabled: false)

        let data = try store.exportToolServersJSONData()

        let importFixture = try ToolServerFixture()
        let importStore = importFixture.makeStore()
        await importStore.load()
        try await importStore.importToolServersJSONData(data)

        XCTAssertEqual(Set(importStore.toolServers.map(\.name)), ["Local MCP", "HTTP MCP"])
        XCTAssertEqual(importStore.toolServers.first { $0.name == "HTTP MCP" }?.baseURL, "http://localhost:3333/mcp")
    }

    func testImportToolServersAcceptsOpenWebUIShapedRecords() async throws {
        let fixture = try ToolServerFixture()
        let store = fixture.makeStore()
        await store.load()
        let data = Data(
            """
            [
              {
                "id": "filesystem",
                "name": "Filesystem",
                "type": "stdio",
                "command": "uvx",
                "args": ["mcp-server-filesystem", "/tmp"],
                "env": { "ROOT": "/tmp" },
                "enabled": true
              },
              {
                "id": "gateway",
                "name": "Gateway",
                "type": "http",
                "url": "http://localhost:4444/mcp",
                "enabled": false
              }
            ]
            """.utf8
        )

        try await store.importToolServersJSONData(data)

        XCTAssertEqual(Set(store.toolServers.map(\.name)), ["Filesystem", "Gateway"])
        XCTAssertEqual(store.toolServers.first { $0.id == "filesystem" }?.arguments, ["mcp-server-filesystem", "/tmp"])
        XCTAssertEqual(store.toolServers.first { $0.id == "gateway" }?.baseURL, "http://localhost:4444/mcp")
    }

    func testToolWritePermissionAllowsToolServerCreateUpdateDeleteAndImportForCurrentUser() async throws {
        let fixture = try ToolServerFixture()
        let store = fixture.makeStore()
        await store.load()
        await store.createAdminUser(name: "Workspace User", email: "user@example.com", role: .user)
        let user = try XCTUnwrap(store.adminUsers.first)
        await store.createAdminGroup(name: "Tool Editors", description: "Can manage tools.", permissions: ["tools.write"])
        let group = try XCTUnwrap(store.adminGroups.first)
        await store.setAdminGroupMembers(group.id, memberIDs: [user.id])
        store.currentUserID = user.id

        await store.createToolServer(
            name: "Local MCP",
            kind: .stdio,
            command: "uvx",
            argumentsText: "filesystem",
            baseURL: "",
            environmentText: "",
            isEnabled: true
        )
        let server = try XCTUnwrap(store.toolServers.first)
        await store.updateToolServer(
            server.id,
            name: "Gateway",
            kind: .http,
            command: "",
            argumentsText: "",
            baseURL: "http://localhost:4444/mcp",
            environmentText: "",
            isEnabled: false
        )
        let updatedServer = try XCTUnwrap(store.toolServers.first)
        await store.deleteToolServer(updatedServer.id)

        let data = try ToolServerExportService().jsonData(for: [
            AppToolServer(name: "Imported Gateway", kind: .http, baseURL: "http://localhost:5555/mcp")
        ])
        try await store.importToolServersJSONData(data)

        XCTAssertEqual(store.toolServers.map(\.name), ["Imported Gateway"])
        XCTAssertEqual(store.toolServers.first?.baseURL, "http://localhost:5555/mcp")
        XCTAssertNil(store.errorMessage)
    }

    func testToolWritePermissionBlocksToolServerCreateUpdateDeleteAndImportForCurrentUser() async throws {
        let fixture = try ToolServerFixture()
        let store = fixture.makeStore()
        await store.load()
        await store.createAdminUser(name: "Workspace User", email: "user@example.com", role: .user)
        let user = try XCTUnwrap(store.adminUsers.first)
        store.currentUserID = user.id

        await store.createToolServer(
            name: "Blocked MCP",
            kind: .stdio,
            command: "blocked",
            argumentsText: "",
            baseURL: "",
            environmentText: "",
            isEnabled: true
        )

        XCTAssertTrue(store.toolServers.isEmpty)
        XCTAssertEqual(store.errorMessage, "You do not have permission to manage tool servers.")

        store.errorMessage = nil
        store.currentUserID = "local-admin"
        await store.createAdminUser(name: "Local Admin", email: "admin@example.com", role: .admin)
        let admin = try XCTUnwrap(store.adminUsers.first { $0.role == .admin })
        store.currentUserID = admin.id
        await store.createToolServer(
            name: "Existing MCP",
            kind: .stdio,
            command: "existing",
            argumentsText: "",
            baseURL: "",
            environmentText: "",
            isEnabled: true
        )
        let server = try XCTUnwrap(store.toolServers.first)

        store.currentUserID = user.id
        await store.updateToolServer(
            server.id,
            name: "Blocked Gateway",
            kind: .http,
            command: "",
            argumentsText: "",
            baseURL: "http://localhost:4444/mcp",
            environmentText: "",
            isEnabled: false
        )
        await store.deleteToolServer(server.id)
        let data = try ToolServerExportService().jsonData(for: [
            AppToolServer(name: "Blocked Import", kind: .http, baseURL: "http://localhost:5555/mcp")
        ])
        try await store.importToolServersJSONData(data)

        XCTAssertEqual(store.toolServers.first?.name, "Existing MCP")
        XCTAssertEqual(store.toolServers.first?.command, "existing")
        XCTAssertEqual(store.toolServers.first?.isEnabled, true)
        XCTAssertEqual(store.errorMessage, "You do not have permission to manage tool servers.")
    }

    func testUnmanagedLocalUserCanManageToolServersWhenAdminDirectoryExists() async throws {
        let fixture = try ToolServerFixture()
        let store = fixture.makeStore()
        await store.load()
        await store.createAdminUser(name: "Workspace User", email: "user@example.com", role: .user)

        await store.createToolServer(
            name: "Local MCP",
            kind: .stdio,
            command: "uvx",
            argumentsText: "",
            baseURL: "",
            environmentText: "",
            isEnabled: true
        )

        XCTAssertEqual(store.toolServers.map(\.name), ["Local MCP"])
        XCTAssertNil(store.errorMessage)
    }

    func testCheckToolServerUpdatesTransientStatus() async throws {
        let checker = FakeToolServerChecker(status: .available("Ready"))
        let fixture = try ToolServerFixture(toolServerChecker: checker)
        let store = fixture.makeStore()
        await store.load()
        await store.setFeatureToggle(.directToolServers, isEnabled: true)
        await store.createToolServer(name: "Local MCP", kind: .stdio, command: "uvx", argumentsText: "", baseURL: "", environmentText: "", isEnabled: true)
        let server = try XCTUnwrap(store.toolServers.first)

        await store.checkToolServer(server.id)

        XCTAssertEqual(store.toolServerStatuses[server.id], .available("Ready"))
        let checkedServers = await checker.checkedServers
        XCTAssertEqual(checkedServers.map(\.id), [server.id])
    }

    func testInvokeHTTPToolServerPersistsRunAndAuditEvent() async throws {
        let runID = UUID(uuidString: "00000000-0000-0000-0000-00000000D00D")!
        let run = AppToolServerRun(
            id: runID,
            serverID: "server-id",
            serverName: "Gateway",
            serverKind: .http,
            requestBody: #"{"ping":true}"#,
            responseBody: #"{"ok":true}"#,
            statusCode: 200,
            status: .succeeded,
            startedAt: Date(timeIntervalSince1970: 100),
            completedAt: Date(timeIntervalSince1970: 101)
        )
        let invoker = FakeToolServerInvoker(run: run)
        let fixture = try ToolServerFixture(toolServerInvoker: invoker)
        let store = fixture.makeStore()
        await store.load()
        await store.setFeatureToggle(.directToolServers, isEnabled: true)
        await store.createToolServer(
            name: "Gateway",
            kind: .http,
            command: "",
            argumentsText: "",
            baseURL: "http://localhost:4444/invoke",
            environmentText: "",
            isEnabled: true
        )
        let server = try XCTUnwrap(store.toolServers.first)

        await store.invokeToolServer(server.id, requestBody: "  {\"ping\":true}  ")

        let capturedRequests = await invoker.capturedRequests
        XCTAssertEqual(capturedRequests.map(\.server.id), [server.id])
        XCTAssertEqual(capturedRequests.first?.requestBody, #"{"ping":true}"#)
        XCTAssertEqual(store.toolServerRuns.map(\.id), [runID])
        XCTAssertEqual(store.selectedToolServerRunID, runID)
        XCTAssertFalse(store.isInvokingToolServer)
        XCTAssertNil(store.toolServerInvocationError)
        XCTAssertEqual(store.auditEvents.first?.action, .toolServerInvoked)
        XCTAssertEqual(store.auditEvents.first?.metadata["serverID"], "server-id")

        let reloadedStore = fixture.makeStore()
        await reloadedStore.load()

        XCTAssertEqual(reloadedStore.toolServerRuns.map(\.id), [runID])
        XCTAssertEqual(reloadedStore.toolServerRuns.first?.responseBody, #"{"ok":true}"#)
    }

    func testInvokeHTTPToolServerUsesDraftRequestBodyWhenNoOverrideIsPassed() async throws {
        let runID = UUID(uuidString: "00000000-0000-0000-0000-00000000D0A7")!
        let run = AppToolServerRun(
            id: runID,
            serverID: "server-id",
            serverName: "Gateway",
            serverKind: .http,
            requestBody: #"{"ping":true}"#,
            responseBody: #"{"ok":true}"#,
            statusCode: 200,
            status: .succeeded,
            startedAt: Date(timeIntervalSince1970: 120),
            completedAt: Date(timeIntervalSince1970: 121)
        )
        let invoker = FakeToolServerInvoker(run: run)
        let fixture = try ToolServerFixture(toolServerInvoker: invoker)
        let store = fixture.makeStore()
        await store.load()
        await store.setFeatureToggle(.directToolServers, isEnabled: true)
        await store.createToolServer(
            name: "Gateway",
            kind: .http,
            command: "",
            argumentsText: "",
            baseURL: "http://localhost:4444/invoke",
            environmentText: "",
            isEnabled: true
        )
        let server = try XCTUnwrap(store.toolServers.first)
        store.toolServerInvocationRequestBody = "  {\"ping\":true}  "

        await store.invokeToolServer(server.id)

        let capturedRequests = await invoker.capturedRequests
        XCTAssertEqual(capturedRequests.first?.requestBody, #"{"ping":true}"#)
        XCTAssertEqual(store.toolServerInvocationRequestBody, "  {\"ping\":true}  ")
        XCTAssertEqual(store.toolServerRuns.map(\.id), [runID])
        XCTAssertNil(store.toolServerInvocationError)
    }

    func testDirectToolServerActionsBlockDisabledFeatureBeforeCallingServices() async throws {
        let checker = FakeToolServerChecker(status: .available("Ready"))
        let discoverer = FakeToolServerToolDiscoverer(
            result: ToolServerToolDiscoveryResult(
                status: .available("Discovered 1 tool."),
                tools: [AppToolServerTool(name: "search_docs")]
            )
        )
        let invoker = FakeToolServerInvoker()
        let caller = FakeToolServerToolCaller()
        let fixture = try ToolServerFixture(
            toolServerChecker: checker,
            toolServerInvoker: invoker,
            toolServerDiscoverer: discoverer,
            toolServerToolCaller: caller
        )
        let store = fixture.makeStore()
        await store.load()
        await store.createToolServer(
            name: "Gateway",
            kind: .http,
            command: "",
            argumentsText: "",
            baseURL: "http://localhost:4444/mcp",
            environmentText: "",
            isEnabled: true
        )
        let server = try XCTUnwrap(store.toolServers.first)
        await store.setFeatureToggle(.directToolServers, isEnabled: false)

        await store.checkToolServer(server.id)
        await store.discoverToolServerTools(server.id)
        await store.invokeToolServer(server.id, requestBody: "{}")
        await store.callToolServerTool(server.id, toolName: "search_docs", argumentsBody: "{}")

        let checkedServers = await checker.checkedServers
        let discoveredServers = await discoverer.discoveredServers
        let capturedInvocations = await invoker.capturedRequests
        let capturedToolCalls = await caller.capturedRequests
        XCTAssertTrue(checkedServers.isEmpty)
        XCTAssertTrue(discoveredServers.isEmpty)
        XCTAssertTrue(capturedInvocations.isEmpty)
        XCTAssertTrue(capturedToolCalls.isEmpty)
        XCTAssertEqual(store.toolServerStatuses[server.id], .unavailable("Direct Tool Servers is disabled."))
        XCTAssertEqual(store.toolServerDiscoveryStatuses[server.id], .unavailable("Direct Tool Servers is disabled."))
        XCTAssertEqual(store.toolServerDiscoveryError, "Direct Tool Servers is disabled.")
        XCTAssertEqual(store.toolServerInvocationError, "Direct Tool Servers is disabled.")
        XCTAssertEqual(store.errorMessage, "Direct Tool Servers is disabled.")
        XCTAssertFalse(store.isDiscoveringToolServerTools)
        XCTAssertFalse(store.isInvokingToolServer)
        XCTAssertTrue(store.toolServerRuns.isEmpty)
        let persistedRuns = try await fixture.toolServerRunStorage.loadRuns()
        XCTAssertTrue(persistedRuns.isEmpty)
    }

    func testInvokeToolServerBlocksDisabledServersWithoutCallingInvoker() async throws {
        let invoker = FakeToolServerInvoker()
        let fixture = try ToolServerFixture(toolServerInvoker: invoker)
        let store = fixture.makeStore()
        await store.load()
        await store.setFeatureToggle(.directToolServers, isEnabled: true)
        await store.createToolServer(
            name: "Gateway",
            kind: .http,
            command: "",
            argumentsText: "",
            baseURL: "http://localhost:4444/invoke",
            environmentText: "",
            isEnabled: false
        )
        let server = try XCTUnwrap(store.toolServers.first)

        await store.invokeToolServer(server.id, requestBody: "{}")

        let capturedRequests = await invoker.capturedRequests
        XCTAssertTrue(capturedRequests.isEmpty)
        XCTAssertEqual(store.toolServerInvocationError, "Tool server is disabled.")
        XCTAssertEqual(store.errorMessage, "Tool server is disabled.")
    }

    func testStdioToolServerActionsBlockDisabledLocalExecutionBeforeCallingServices() async throws {
        let discoverer = FakeToolServerToolDiscoverer(
            result: ToolServerToolDiscoveryResult(
                status: .available("Discovered 1 tool."),
                tools: [AppToolServerTool(name: "search_docs")]
            )
        )
        let invoker = FakeToolServerInvoker()
        let caller = FakeToolServerToolCaller()
        let fixture = try ToolServerFixture(
            toolServerInvoker: invoker,
            toolServerDiscoverer: discoverer,
            toolServerToolCaller: caller
        )
        let store = fixture.makeStore()
        await store.load()
        await store.setFeatureToggle(.directToolServers, isEnabled: true)
        await store.createToolServer(
            name: "Stdio Gateway",
            kind: .stdio,
            command: "/usr/bin/python3",
            argumentsText: "",
            baseURL: "",
            environmentText: "",
            isEnabled: true
        )
        let server = try XCTUnwrap(store.toolServers.first)

        await store.discoverToolServerTools(server.id)
        await store.invokeToolServer(server.id, requestBody: "{}")
        await store.callToolServerTool(server.id, toolName: "search_docs", argumentsBody: "{}")

        let discoveredServers = await discoverer.discoveredServers
        let capturedInvocations = await invoker.capturedRequests
        let capturedToolCalls = await caller.capturedRequests
        XCTAssertTrue(discoveredServers.isEmpty)
        XCTAssertTrue(capturedInvocations.isEmpty)
        XCTAssertTrue(capturedToolCalls.isEmpty)
        XCTAssertEqual(store.toolServerDiscoveryStatuses[server.id], .unavailable(LocalExecutionSettings.disabledMessage))
        XCTAssertEqual(store.toolServerDiscoveryError, LocalExecutionSettings.disabledMessage)
        XCTAssertEqual(store.toolServerInvocationError, LocalExecutionSettings.disabledMessage)
        XCTAssertEqual(store.errorMessage, LocalExecutionSettings.disabledMessage)
        XCTAssertFalse(store.isDiscoveringToolServerTools)
        XCTAssertFalse(store.isInvokingToolServer)
        XCTAssertTrue(store.toolServerRuns.isEmpty)
    }

    func testToolExecutePermissionAllowsToolServerInvokeAndToolCallForCurrentUser() async throws {
        let invoker = FakeToolServerInvoker()
        let caller = FakeToolServerToolCaller()
        let fixture = try ToolServerFixture(toolServerInvoker: invoker, toolServerToolCaller: caller)
        let store = fixture.makeStore()
        await store.load()
        await store.setFeatureToggle(.directToolServers, isEnabled: true)
        await store.createToolServer(
            name: "Gateway",
            kind: .http,
            command: "",
            argumentsText: "",
            baseURL: "http://localhost:4444/mcp",
            environmentText: "",
            isEnabled: true
        )
        let server = try XCTUnwrap(store.toolServers.first)
        await store.createAdminUser(name: "Workspace User", email: "user@example.com", role: .user)
        let user = try XCTUnwrap(store.adminUsers.first)
        await store.createAdminGroup(name: "Tool Runners", description: "Can run tool servers.", permissions: ["tools.execute"])
        let group = try XCTUnwrap(store.adminGroups.first)
        await store.setAdminGroupMembers(group.id, memberIDs: [user.id])
        store.currentUserID = user.id

        await store.invokeToolServer(server.id, requestBody: "{}")
        await store.callToolServerTool(server.id, toolName: "search_docs", argumentsBody: "{}")

        let capturedInvocations = await invoker.capturedRequests
        let capturedToolCalls = await caller.capturedRequests
        XCTAssertEqual(capturedInvocations.map(\.server.id), [server.id])
        XCTAssertEqual(capturedToolCalls.map(\.server.id), [server.id])
        XCTAssertNil(store.toolServerInvocationError)
        XCTAssertNil(store.errorMessage)
    }

    func testToolExecutePermissionBlocksToolServerInvokeAndToolCallForCurrentUser() async throws {
        let invoker = FakeToolServerInvoker()
        let caller = FakeToolServerToolCaller()
        let fixture = try ToolServerFixture(toolServerInvoker: invoker, toolServerToolCaller: caller)
        let store = fixture.makeStore()
        await store.load()
        await store.setFeatureToggle(.directToolServers, isEnabled: true)
        await store.createToolServer(
            name: "Gateway",
            kind: .http,
            command: "",
            argumentsText: "",
            baseURL: "http://localhost:4444/mcp",
            environmentText: "",
            isEnabled: true
        )
        let server = try XCTUnwrap(store.toolServers.first)
        await store.createAdminUser(name: "Workspace User", email: "user@example.com", role: .user)
        let user = try XCTUnwrap(store.adminUsers.first)
        await store.createAdminGroup(name: "Tool Editors", description: "Can manage tools.", permissions: ["tools.write"])
        let group = try XCTUnwrap(store.adminGroups.first)
        await store.setAdminGroupMembers(group.id, memberIDs: [user.id])
        store.currentUserID = user.id

        await store.invokeToolServer(server.id, requestBody: "{}")
        await store.callToolServerTool(server.id, toolName: "search_docs", argumentsBody: "{}")

        let capturedInvocations = await invoker.capturedRequests
        let capturedToolCalls = await caller.capturedRequests
        XCTAssertTrue(capturedInvocations.isEmpty)
        XCTAssertTrue(capturedToolCalls.isEmpty)
        XCTAssertTrue(store.toolServerRuns.isEmpty)
        XCTAssertEqual(store.toolServerInvocationError, "You do not have permission to run tool servers.")
        XCTAssertEqual(store.errorMessage, "You do not have permission to run tool servers.")
        XCTAssertFalse(store.isInvokingToolServer)
    }

    func testDiscoverHTTPToolServerStoresToolsAndStatus() async throws {
        let discoverer = FakeToolServerToolDiscoverer(
            result: ToolServerToolDiscoveryResult(
                status: .available("Discovered 2 tools."),
                tools: [
                    AppToolServerTool(name: "search_docs", title: "Search Docs", description: "Search indexed documents."),
                    AppToolServerTool(name: "summarize", description: "Summarize a document.")
                ]
            )
        )
        let fixture = try ToolServerFixture(toolServerDiscoverer: discoverer)
        let store = fixture.makeStore()
        await store.load()
        await store.setFeatureToggle(.directToolServers, isEnabled: true)
        await store.createToolServer(
            name: "Gateway",
            kind: .http,
            command: "",
            argumentsText: "",
            baseURL: "http://localhost:4444/mcp",
            environmentText: "",
            isEnabled: true
        )
        let server = try XCTUnwrap(store.toolServers.first)

        await store.discoverToolServerTools(server.id)

        let discoveredServers = await discoverer.discoveredServers
        XCTAssertEqual(discoveredServers.map(\.id), [server.id])
        XCTAssertEqual(store.toolServerDiscoveryStatuses[server.id], .available("Discovered 2 tools."))
        XCTAssertEqual(store.toolServerTools[server.id]?.map(\.name), ["search_docs", "summarize"])
        XCTAssertFalse(store.isDiscoveringToolServerTools)
        XCTAssertNil(store.toolServerDiscoveryError)
    }

    func testDiscoverToolServerBlocksDisabledServersWithoutCallingDiscoverer() async throws {
        let discoverer = FakeToolServerToolDiscoverer()
        let fixture = try ToolServerFixture(toolServerDiscoverer: discoverer)
        let store = fixture.makeStore()
        await store.load()
        await store.setFeatureToggle(.directToolServers, isEnabled: true)
        await store.createToolServer(
            name: "Gateway",
            kind: .http,
            command: "",
            argumentsText: "",
            baseURL: "http://localhost:4444/mcp",
            environmentText: "",
            isEnabled: false
        )
        let server = try XCTUnwrap(store.toolServers.first)

        await store.discoverToolServerTools(server.id)

        let discoveredServers = await discoverer.discoveredServers
        XCTAssertTrue(discoveredServers.isEmpty)
        XCTAssertEqual(store.toolServerDiscoveryError, "Tool server is disabled.")
        XCTAssertEqual(store.errorMessage, "Tool server is disabled.")
    }

    func testCallDiscoveredToolPersistsRunAndAuditEvent() async throws {
        let runID = UUID(uuidString: "00000000-0000-0000-0000-00000000CA11")!
        let run = AppToolServerRun(
            id: runID,
            serverID: "server-id",
            serverName: "Gateway",
            serverKind: .http,
            requestBody: #"{"query":"SwiftUI"}"#,
            responseBody: #"{"content":[{"type":"text","text":"Found two documents."}]}"#,
            statusCode: 200,
            status: .succeeded,
            startedAt: Date(timeIntervalSince1970: 200),
            completedAt: Date(timeIntervalSince1970: 201)
        )
        let caller = FakeToolServerToolCaller(run: run)
        let fixture = try ToolServerFixture(toolServerToolCaller: caller)
        let store = fixture.makeStore()
        await store.load()
        await store.setFeatureToggle(.directToolServers, isEnabled: true)
        await store.createToolServer(
            name: "Gateway",
            kind: .http,
            command: "",
            argumentsText: "",
            baseURL: "http://localhost:4444/mcp",
            environmentText: "",
            isEnabled: true
        )
        let server = try XCTUnwrap(store.toolServers.first)

        await store.callToolServerTool(
            server.id,
            toolName: "search_docs",
            argumentsBody: #" { "query": "SwiftUI" } "#
        )

        let capturedRequests = await caller.capturedRequests
        XCTAssertEqual(capturedRequests.map(\.server.id), [server.id])
        XCTAssertEqual(capturedRequests.first?.toolName, "search_docs")
        XCTAssertEqual(capturedRequests.first?.arguments, .object(["query": .string("SwiftUI")]))
        XCTAssertEqual(store.toolServerRuns.map(\.id), [runID])
        XCTAssertEqual(store.selectedToolServerRunID, runID)
        XCTAssertFalse(store.isInvokingToolServer)
        XCTAssertNil(store.toolServerInvocationError)
        XCTAssertEqual(store.auditEvents.first?.action, .toolServerInvoked)
        XCTAssertEqual(store.auditEvents.first?.metadata["toolName"], "search_docs")

        let reloadedStore = fixture.makeStore()
        await reloadedStore.load()

        XCTAssertEqual(reloadedStore.toolServerRuns.map(\.id), [runID])
        XCTAssertEqual(reloadedStore.toolServerRuns.first?.responseBody, #"{"content":[{"type":"text","text":"Found two documents."}]}"#)
    }

    func testDeleteToolServerRunRemovesPersistedRunSelectionAndAuditsDeletion() async throws {
        let runID = UUID(uuidString: "00000000-0000-0000-0000-00000000DE17")!
        let run = AppToolServerRun(
            id: runID,
            serverID: "server-id",
            serverName: "Gateway",
            serverKind: .http,
            requestBody: #"{"ping":true}"#,
            responseBody: #"{"ok":true}"#,
            statusCode: 200,
            status: .succeeded,
            startedAt: Date(timeIntervalSince1970: 300),
            completedAt: Date(timeIntervalSince1970: 301)
        )
        let invoker = FakeToolServerInvoker(run: run)
        let fixture = try ToolServerFixture(toolServerInvoker: invoker)
        let store = fixture.makeStore()
        await store.load()
        await store.setFeatureToggle(.directToolServers, isEnabled: true)
        await store.createToolServer(
            name: "Gateway",
            kind: .http,
            command: "",
            argumentsText: "",
            baseURL: "http://localhost:4444/invoke",
            environmentText: "",
            isEnabled: true
        )
        let server = try XCTUnwrap(store.toolServers.first)
        await store.invokeToolServer(server.id, requestBody: #"{"ping":true}"#)

        await store.deleteToolServerRun(runID)

        let persistedRuns = try await fixture.toolServerRunStorage.loadRuns()
        XCTAssertTrue(store.toolServerRuns.isEmpty)
        XCTAssertNil(store.selectedToolServerRunID)
        XCTAssertTrue(persistedRuns.isEmpty)
        XCTAssertNil(store.errorMessage)

        let event = try XCTUnwrap(store.auditEvents.first(where: { $0.action == .toolServerRunDeleted }))
        XCTAssertEqual(event.outcome, .succeeded)
        XCTAssertEqual(event.summary, "Deleted tool-server run")
        XCTAssertEqual(event.metadata["runID"], runID.uuidString)
        XCTAssertEqual(event.metadata["serverID"], "server-id")
        XCTAssertEqual(event.metadata["serverKind"], "http")
        XCTAssertEqual(event.metadata["status"], "succeeded")
        XCTAssertNil(event.metadata["requestBody"])
        XCTAssertNil(event.metadata["responseBody"])
        XCTAssertNil(event.metadata["errorMessage"])
    }

    func testToolWritePermissionBlocksToolServerRunDeletionForExecuteOnlyUser() async throws {
        let runID = UUID(uuidString: "00000000-0000-0000-0000-00000000DE18")!
        let run = AppToolServerRun(
            id: runID,
            serverID: "server-id",
            serverName: "Gateway",
            serverKind: .http,
            requestBody: #"{"ping":true}"#,
            responseBody: #"{"ok":true}"#,
            statusCode: 200,
            status: .succeeded,
            startedAt: Date(timeIntervalSince1970: 310),
            completedAt: Date(timeIntervalSince1970: 311)
        )
        let invoker = FakeToolServerInvoker(run: run)
        let fixture = try ToolServerFixture(toolServerInvoker: invoker)
        let store = fixture.makeStore()
        await store.load()
        await store.setFeatureToggle(.directToolServers, isEnabled: true)
        await store.createToolServer(
            name: "Gateway",
            kind: .http,
            command: "",
            argumentsText: "",
            baseURL: "http://localhost:4444/invoke",
            environmentText: "",
            isEnabled: true
        )
        let server = try XCTUnwrap(store.toolServers.first)
        await store.invokeToolServer(server.id, requestBody: #"{"ping":true}"#)
        await store.createAdminUser(name: "Workspace User", email: "user@example.com", role: .user)
        let user = try XCTUnwrap(store.adminUsers.first)
        await store.createAdminGroup(
            name: "Tool Runners",
            description: "Can run tool servers.",
            permissions: ["tools.execute"]
        )
        let group = try XCTUnwrap(store.adminGroups.first)
        await store.setAdminGroupMembers(group.id, memberIDs: [user.id])
        store.currentUserID = user.id

        await store.deleteToolServerRun(runID)

        let persistedRuns = try await fixture.toolServerRunStorage.loadRuns()
        XCTAssertEqual(store.toolServerRuns.map(\.id), [runID])
        XCTAssertEqual(store.selectedToolServerRunID, runID)
        XCTAssertEqual(persistedRuns.map(\.id), [runID])
        XCTAssertEqual(store.errorMessage, "You do not have permission to manage tool servers.")
        XCTAssertNil(store.auditEvents.first(where: { $0.action == .toolServerRunDeleted }))
    }

    func testCallDiscoveredToolRejectsInvalidArgumentsJSONWithoutCallingTool() async throws {
        let caller = FakeToolServerToolCaller()
        let fixture = try ToolServerFixture(toolServerToolCaller: caller)
        let store = fixture.makeStore()
        await store.load()
        await store.setFeatureToggle(.directToolServers, isEnabled: true)
        await store.createToolServer(
            name: "Gateway",
            kind: .http,
            command: "",
            argumentsText: "",
            baseURL: "http://localhost:4444/mcp",
            environmentText: "",
            isEnabled: true
        )
        let server = try XCTUnwrap(store.toolServers.first)

        await store.callToolServerTool(server.id, toolName: "search_docs", argumentsBody: "{")

        let capturedRequests = await caller.capturedRequests
        XCTAssertTrue(capturedRequests.isEmpty)
        XCTAssertEqual(store.toolServerInvocationError, "Tool arguments must be a JSON object.")
        XCTAssertEqual(store.errorMessage, "Tool arguments must be a JSON object.")
    }

    func testCallDiscoveredToolValidatesKnownSchemaBeforeCallingTool() async throws {
        let caller = FakeToolServerToolCaller()
        let fixture = try ToolServerFixture(toolServerToolCaller: caller)
        let store = fixture.makeStore()
        await store.load()
        await store.setFeatureToggle(.directToolServers, isEnabled: true)
        await store.createToolServer(
            name: "Gateway",
            kind: .http,
            command: "",
            argumentsText: "",
            baseURL: "http://localhost:4444/mcp",
            environmentText: "",
            isEnabled: true
        )
        let server = try XCTUnwrap(store.toolServers.first)
        store.toolServerTools[server.id] = [
            AppToolServerTool(
                name: "search_docs",
                inputSchema: .object([
                    "type": .string("object"),
                    "required": .array([.string("query")]),
                    "properties": .object([
                        "query": .object(["type": .string("string")])
                    ])
                ])
            )
        ]

        await store.callToolServerTool(server.id, toolName: "search_docs", argumentsBody: "{}")

        let capturedRequests = await caller.capturedRequests
        XCTAssertTrue(capturedRequests.isEmpty)
        XCTAssertEqual(store.toolServerInvocationError, "Missing required tool argument: query.")
        XCTAssertEqual(store.errorMessage, "Missing required tool argument: query.")
    }
}

private struct ToolServerFixture {
    let rootURL: URL
    let storage: JSONStorageService
    let folderStorage: JSONFolderStorageService
    let settingsStore: SettingsStore
    let toolStorage: JSONToolStorageService
    let toolServerStorage: JSONToolServerStorageService
    let toolServerRunStorage: JSONToolServerRunStorageService
    let toolServerChecker: any ToolServerChecking
    let toolServerInvoker: any ToolServerInvoking
    let toolServerDiscoverer: any ToolServerToolDiscovering
    let toolServerToolCaller: any ToolServerToolCalling
    let auditStorage: JSONAuditLogStorageService
    let adminStorage: JSONAdminDirectoryStorageService

    init(
        toolServerChecker: any ToolServerChecking = FakeToolServerChecker(status: .unknown),
        toolServerInvoker: any ToolServerInvoking = FakeToolServerInvoker(),
        toolServerDiscoverer: any ToolServerToolDiscovering = FakeToolServerToolDiscoverer(),
        toolServerToolCaller: any ToolServerToolCalling = FakeToolServerToolCaller()
    ) throws {
        rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        storage = JSONStorageService(rootURL: rootURL.appendingPathComponent("Chats", isDirectory: true))
        folderStorage = JSONFolderStorageService(rootURL: rootURL.appendingPathComponent("Folders", isDirectory: true))
        settingsStore = SettingsStore(settingsURL: rootURL.appendingPathComponent("settings.json"))
        toolStorage = JSONToolStorageService(rootURL: rootURL.appendingPathComponent("Tools", isDirectory: true))
        toolServerStorage = JSONToolServerStorageService(rootURL: rootURL.appendingPathComponent("ToolServers", isDirectory: true))
        toolServerRunStorage = JSONToolServerRunStorageService(rootURL: rootURL.appendingPathComponent("ToolServerRuns", isDirectory: true))
        self.toolServerChecker = toolServerChecker
        self.toolServerInvoker = toolServerInvoker
        self.toolServerDiscoverer = toolServerDiscoverer
        self.toolServerToolCaller = toolServerToolCaller
        auditStorage = JSONAuditLogStorageService(rootURL: rootURL.appendingPathComponent("AuditLog", isDirectory: true))
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
            auditLogStorage: auditStorage,
            toolStorage: toolStorage,
            toolServerStorage: toolServerStorage,
            toolServerChecker: toolServerChecker,
            toolServerRunStorage: toolServerRunStorage,
            toolServerInvoker: toolServerInvoker,
            toolServerDiscoverer: toolServerDiscoverer,
            toolServerToolCaller: toolServerToolCaller,
            adminDirectoryStorage: adminStorage
        )
    }
}

private actor FakeToolServerChecker: ToolServerChecking {
    let status: ToolServerConnectionStatus
    private(set) var checkedServers: [AppToolServer] = []

    init(status: ToolServerConnectionStatus) {
        self.status = status
    }

    func check(_ server: AppToolServer) async -> ToolServerCheckResult {
        checkedServers.append(server)
        return ToolServerCheckResult(status: status)
    }
}

private actor FakeToolServerInvoker: ToolServerInvoking {
    private let run: AppToolServerRun
    private(set) var capturedRequests: [ToolServerInvocationRequest] = []

    init(
        run: AppToolServerRun = AppToolServerRun(
            serverID: "server-id",
            serverName: "Gateway",
            serverKind: .http,
            requestBody: "{}",
            responseBody: "{}",
            statusCode: 200,
            status: .succeeded
        )
    ) {
        self.run = run
    }

    func invoke(_ request: ToolServerInvocationRequest) async -> AppToolServerRun {
        capturedRequests.append(request)
        return run
    }
}

private actor FakeToolServerToolDiscoverer: ToolServerToolDiscovering {
    private let result: ToolServerToolDiscoveryResult
    private(set) var discoveredServers: [AppToolServer] = []

    init(
        result: ToolServerToolDiscoveryResult = ToolServerToolDiscoveryResult(
            status: .unknown,
            tools: []
        )
    ) {
        self.result = result
    }

    func discoverTools(
        for server: AppToolServer,
        workingDirectoryPath: String?,
        maxCapturedOutputBytes: Int?
    ) async -> ToolServerToolDiscoveryResult {
        discoveredServers.append(server)
        return result
    }
}

private actor FakeToolServerToolCaller: ToolServerToolCalling {
    private let run: AppToolServerRun
    private(set) var capturedRequests: [ToolServerToolCallRequest] = []

    init(
        run: AppToolServerRun = AppToolServerRun(
            serverID: "server-id",
            serverName: "Gateway",
            serverKind: .http,
            requestBody: "{}",
            responseBody: "{}",
            statusCode: 200,
            status: .succeeded
        )
    ) {
        self.run = run
    }

    func callTool(_ request: ToolServerToolCallRequest) async -> AppToolServerRun {
        capturedRequests.append(request)
        return run
    }
}
