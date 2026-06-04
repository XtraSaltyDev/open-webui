import Foundation
import XCTest
@testable import OpenWebUINative

@MainActor
final class AppStoreTerminalSessionTests: XCTestCase {
    func testCreateTerminalSessionPersistsSelectsAndAuditsSession() async throws {
        let fixture = try TerminalSessionFixture(executor: FakeTerminalCodeExecutor())
        let store = fixture.makeStore()
        await store.load()
        await store.setFeatureToggle(.terminalSessions, isEnabled: true)

        let session = await store.createTerminalSession(
            title: "Build Logs",
            workingDirectoryPath: "  /tmp  "
        )

        let createdSession = try XCTUnwrap(session)
        XCTAssertEqual(createdSession.title, "Build Logs")
        XCTAssertEqual(createdSession.workingDirectoryPath, "/tmp")
        XCTAssertEqual(store.terminalSessions.map(\.id), [createdSession.id])
        XCTAssertEqual(store.selectedTerminalSessionID, createdSession.id)
        XCTAssertNil(store.terminalError)

        let event = try XCTUnwrap(store.auditEvents.first(where: { $0.action == .terminalSessionCreated }))
        XCTAssertEqual(event.outcome, .succeeded)
        XCTAssertEqual(event.summary, "Created terminal session")
        XCTAssertEqual(event.metadata["sessionID"], createdSession.id.uuidString)
        XCTAssertEqual(event.metadata["workingDirectory"], "/tmp")

        let reloadedStore = fixture.makeStore()
        await reloadedStore.load()

        XCTAssertEqual(reloadedStore.terminalSessions.map(\.id), [createdSession.id])
        XCTAssertEqual(reloadedStore.terminalSessions.first?.title, "Build Logs")
    }

    func testRunTerminalCommandUsesShellPolicyPersistsTranscriptAndAuditsCommand() async throws {
        let commandID = UUID(uuidString: "00000000-0000-0000-0000-0000000C0A11")!
        let executor = FakeTerminalCodeExecutor(
            run: AppCodeExecutionRun(
                id: commandID,
                language: .shell,
                code: "pwd",
                workingDirectoryPath: "/tmp",
                stdout: "/tmp\n",
                status: .succeeded,
                exitCode: 0,
                startedAt: Date(timeIntervalSince1970: 10),
                completedAt: Date(timeIntervalSince1970: 11)
            )
        )
        let fixture = try TerminalSessionFixture(executor: executor)
        let store = fixture.makeStore()
        await store.load()
        await store.setFeatureToggle(.terminalSessions, isEnabled: true)
        store.settings.codeExecution = CodeExecutionSettings(
            allowedLanguages: [.shell],
            allowedWorkingDirectoryRoots: ["/tmp"],
            maxTimeoutSeconds: 4
        )
        let createdSession = await store.createTerminalSession(title: "Shell", workingDirectoryPath: "/tmp")
        let session = try XCTUnwrap(createdSession)
        store.terminalCommandInput = "  pwd  "
        store.terminalTimeoutSeconds = 60

        await store.runTerminalCommand()

        let captured = await executor.capturedRequests
        XCTAssertEqual(captured.count, 1)
        XCTAssertEqual(captured.first?.language, .shell)
        XCTAssertEqual(captured.first?.code, "pwd")
        XCTAssertEqual(captured.first?.workingDirectoryPath, "/tmp")
        XCTAssertEqual(captured.first?.timeoutSeconds, 4)
        XCTAssertFalse(store.isRunningTerminalCommand)
        XCTAssertNil(store.terminalError)
        XCTAssertEqual(store.terminalCommands.map(\.id), [commandID])
        XCTAssertEqual(store.terminalCommands.first?.sessionID, session.id)
        XCTAssertEqual(store.terminalCommands.first?.stdout, "/tmp\n")
        XCTAssertEqual(store.terminalCommandInput, "")

        let event = try XCTUnwrap(store.auditEvents.first(where: { $0.action == .terminalCommandRun }))
        XCTAssertEqual(event.outcome, .succeeded)
        XCTAssertEqual(event.summary, "Terminal command succeeded")
        XCTAssertEqual(event.metadata["sessionID"], session.id.uuidString)
        XCTAssertEqual(event.metadata["commandID"], commandID.uuidString)
        XCTAssertEqual(event.metadata["status"], "succeeded")

        let reloadedStore = fixture.makeStore()
        await reloadedStore.load()

        XCTAssertEqual(reloadedStore.terminalCommands.map(\.id), [commandID])
        XCTAssertEqual(reloadedStore.terminalCommands.first?.stdout, "/tmp\n")
    }

    func testRunTerminalCommandBlocksDisabledFeatureBeforeCallingExecutor() async throws {
        let executor = FakeTerminalCodeExecutor()
        let fixture = try TerminalSessionFixture(executor: executor)
        let store = fixture.makeStore()
        await store.load()
        await store.setFeatureToggle(.terminalSessions, isEnabled: false)
        store.terminalCommandInput = "pwd"

        await store.runTerminalCommand()

        let captured = await executor.capturedRequests
        XCTAssertTrue(captured.isEmpty)
        XCTAssertTrue(store.terminalCommands.isEmpty)
        XCTAssertEqual(store.terminalError, "Terminal Sessions is disabled.")
        XCTAssertEqual(store.errorMessage, "Terminal Sessions is disabled.")
    }

    func testTerminalExecutePermissionBlocksCommandBeforeCallingExecutor() async throws {
        let executor = FakeTerminalCodeExecutor()
        let fixture = try TerminalSessionFixture(executor: executor)
        let store = fixture.makeStore()
        await store.load()
        await store.setFeatureToggle(.terminalSessions, isEnabled: true)
        await store.createAdminUser(name: "Workspace User", email: "user@example.com", role: .user)
        let user = try XCTUnwrap(store.adminUsers.first)
        store.currentUserID = user.id
        store.terminalCommandInput = "pwd"

        await store.runTerminalCommand()

        let captured = await executor.capturedRequests
        XCTAssertTrue(captured.isEmpty)
        XCTAssertTrue(store.terminalCommands.isEmpty)
        XCTAssertEqual(store.terminalError, "You do not have permission to use terminal sessions.")
        XCTAssertEqual(store.errorMessage, "You do not have permission to use terminal sessions.")
    }

    func testTerminalExecutePermissionAllowsAutoSessionCreationWithoutWritePermission() async throws {
        let commandID = UUID(uuidString: "00000000-0000-0000-0000-0000000E0EEC")!
        let executor = FakeTerminalCodeExecutor(
            run: AppCodeExecutionRun(
                id: commandID,
                language: .shell,
                code: "pwd",
                workingDirectoryPath: nil,
                stdout: "/Users/example\n",
                status: .succeeded,
                exitCode: 0,
                startedAt: Date(timeIntervalSince1970: 45),
                completedAt: Date(timeIntervalSince1970: 46)
            )
        )
        let fixture = try TerminalSessionFixture(executor: executor)
        let store = fixture.makeStore()
        await store.load()
        await store.setFeatureToggle(.terminalSessions, isEnabled: true)
        await store.createAdminUser(name: "Workspace User", email: "user@example.com", role: .user)
        let user = try XCTUnwrap(store.adminUsers.first)
        await store.createAdminGroup(
            name: "Terminal Runners",
            description: "Can run terminal commands.",
            permissions: ["terminal.execute"]
        )
        let group = try XCTUnwrap(store.adminGroups.first)
        await store.setAdminGroupMembers(group.id, memberIDs: [user.id])
        store.currentUserID = user.id
        store.terminalCommandInput = "pwd"

        await store.runTerminalCommand()

        let captured = await executor.capturedRequests
        XCTAssertEqual(captured.count, 1)
        XCTAssertEqual(store.terminalSessions.count, 1)
        XCTAssertEqual(store.terminalCommands.map(\.id), [commandID])
        XCTAssertNil(store.terminalError)
    }

    func testTerminalWritePermissionAllowsSessionManagementWithoutExecutePermission() async throws {
        let fixture = try TerminalSessionFixture(executor: FakeTerminalCodeExecutor())
        let store = fixture.makeStore()
        await store.load()
        await store.setFeatureToggle(.terminalSessions, isEnabled: true)
        await store.createAdminUser(name: "Workspace User", email: "user@example.com", role: .user)
        let user = try XCTUnwrap(store.adminUsers.first)
        await store.createAdminGroup(
            name: "Terminal Editors",
            description: "Can manage terminal history.",
            permissions: ["terminal.write"]
        )
        let group = try XCTUnwrap(store.adminGroups.first)
        await store.setAdminGroupMembers(group.id, memberIDs: [user.id])
        store.currentUserID = user.id

        XCTAssertTrue(store.currentUserCanManageTerminalSessions)
        XCTAssertFalse(store.currentUserCanUseTerminal)

        let session = await store.createTerminalSession(title: "Managed Session", workingDirectoryPath: "/tmp")

        let createdSession = try XCTUnwrap(session)
        XCTAssertEqual(store.terminalSessions.map(\.id), [createdSession.id])
        XCTAssertNil(store.terminalError)

        await store.deleteTerminalSession(createdSession.id)

        let persistedSessions = try await fixture.terminalStorage.loadSessions()
        XCTAssertTrue(store.terminalSessions.isEmpty)
        XCTAssertTrue(persistedSessions.isEmpty)
        XCTAssertNil(store.terminalError)
    }

    func testTerminalWritePermissionAllowsTranscriptDeletionWithoutExecutePermission() async throws {
        let commandID = UUID(uuidString: "00000000-0000-0000-0000-0000000D3120")!
        let executor = FakeTerminalCodeExecutor(
            run: AppCodeExecutionRun(
                id: commandID,
                language: .shell,
                code: "pwd",
                workingDirectoryPath: "/tmp",
                stdout: "/tmp\n",
                status: .succeeded,
                exitCode: 0,
                startedAt: Date(timeIntervalSince1970: 50),
                completedAt: Date(timeIntervalSince1970: 51)
            )
        )
        let fixture = try TerminalSessionFixture(executor: executor)
        let store = fixture.makeStore()
        await store.load()
        await store.setFeatureToggle(.terminalSessions, isEnabled: true)
        let createdSession = await store.createTerminalSession(title: "Delete Transcript", workingDirectoryPath: "/tmp")
        _ = try XCTUnwrap(createdSession)
        store.terminalCommandInput = "pwd"
        await store.runTerminalCommand()

        await store.createAdminUser(name: "Workspace User", email: "user@example.com", role: .user)
        let user = try XCTUnwrap(store.adminUsers.first)
        await store.createAdminGroup(
            name: "Terminal Editors",
            description: "Can manage terminal history.",
            permissions: ["terminal.write"]
        )
        let group = try XCTUnwrap(store.adminGroups.first)
        await store.setAdminGroupMembers(group.id, memberIDs: [user.id])
        store.currentUserID = user.id

        await store.deleteTerminalCommand(commandID)

        let persistedCommands = try await fixture.terminalStorage.loadCommands()
        XCTAssertTrue(store.terminalCommands.isEmpty)
        XCTAssertTrue(persistedCommands.isEmpty)
        XCTAssertNil(store.terminalError)

        store.terminalCommandInput = "pwd"
        await store.runTerminalCommand()

        let captured = await executor.capturedRequests
        XCTAssertEqual(captured.count, 1)
        XCTAssertEqual(store.terminalError, "You do not have permission to use terminal sessions.")
    }

    func testUpdateTerminalSessionTrimsPersistsSelectsAndAuditsUpdate() async throws {
        let fixture = try TerminalSessionFixture(executor: FakeTerminalCodeExecutor())
        let store = fixture.makeStore()
        await store.load()
        await store.setFeatureToggle(.terminalSessions, isEnabled: true)
        let createdSession = await store.createTerminalSession(title: "Scratch", workingDirectoryPath: "/tmp")
        let session = try XCTUnwrap(createdSession)

        await store.updateTerminalSession(
            session.id,
            title: "  Build Output  ",
            workingDirectoryPath: "   "
        )

        let updatedSession = try XCTUnwrap(store.terminalSessions.first { $0.id == session.id })
        XCTAssertEqual(updatedSession.title, "Build Output")
        XCTAssertNil(updatedSession.workingDirectoryPath)
        XCTAssertEqual(store.selectedTerminalSessionID, session.id)
        XCTAssertNil(store.terminalError)

        let persistedSessions = try await fixture.terminalStorage.loadSessions()
        let persistedSession = try XCTUnwrap(persistedSessions.first)
        XCTAssertEqual(persistedSession.title, "Build Output")
        XCTAssertNil(persistedSession.workingDirectoryPath)

        let event = try XCTUnwrap(store.auditEvents.first(where: { $0.action == .terminalSessionUpdated }))
        XCTAssertEqual(event.outcome, .succeeded)
        XCTAssertEqual(event.summary, "Updated terminal session")
        XCTAssertEqual(event.metadata["sessionID"], session.id.uuidString)
        XCTAssertEqual(event.metadata["workingDirectory"], "")
    }

    func testTerminalWritePermissionBlocksSessionUpdateForCurrentUser() async throws {
        let fixture = try TerminalSessionFixture(executor: FakeTerminalCodeExecutor())
        let store = fixture.makeStore()
        await store.load()
        await store.setFeatureToggle(.terminalSessions, isEnabled: true)
        let createdSession = await store.createTerminalSession(title: "Original", workingDirectoryPath: "/tmp")
        let session = try XCTUnwrap(createdSession)
        await store.createAdminUser(name: "Workspace User", email: "user@example.com", role: .user)
        let user = try XCTUnwrap(store.adminUsers.first)
        store.currentUserID = user.id

        await store.updateTerminalSession(
            session.id,
            title: "Blocked",
            workingDirectoryPath: "/Users/example"
        )

        let unchangedSession = try XCTUnwrap(store.terminalSessions.first { $0.id == session.id })
        XCTAssertEqual(unchangedSession.title, "Original")
        XCTAssertEqual(unchangedSession.workingDirectoryPath, "/tmp")
        XCTAssertEqual(store.terminalError, "You do not have permission to manage terminal sessions.")
        XCTAssertNil(store.auditEvents.first(where: { $0.action == .terminalSessionUpdated }))

        let persistedSessions = try await fixture.terminalStorage.loadSessions()
        let persistedSession = try XCTUnwrap(persistedSessions.first)
        XCTAssertEqual(persistedSession.title, "Original")
        XCTAssertEqual(persistedSession.workingDirectoryPath, "/tmp")
    }

    func testPrepareTerminalCommandForRerunSelectsSessionAndFillsDraftWithoutExecuting() async throws {
        let commandID = UUID(uuidString: "00000000-0000-0000-0000-0000000E1201")!
        let executor = FakeTerminalCodeExecutor(
            run: AppCodeExecutionRun(
                id: commandID,
                language: .shell,
                code: "pwd",
                workingDirectoryPath: "/tmp",
                stdout: "/tmp\n",
                status: .succeeded,
                exitCode: 0,
                startedAt: Date(timeIntervalSince1970: 60),
                completedAt: Date(timeIntervalSince1970: 61)
            )
        )
        let fixture = try TerminalSessionFixture(executor: executor)
        let store = fixture.makeStore()
        await store.load()
        await store.setFeatureToggle(.terminalSessions, isEnabled: true)
        let createdSourceSession = await store.createTerminalSession(title: "Source", workingDirectoryPath: "/tmp")
        let sourceSession = try XCTUnwrap(createdSourceSession)
        store.terminalCommandInput = "pwd"
        await store.runTerminalCommand()
        let createdTargetSession = await store.createTerminalSession(title: "Target", workingDirectoryPath: nil)
        let targetSession = try XCTUnwrap(createdTargetSession)
        store.selectedTerminalSessionID = targetSession.id
        store.terminalCommandInput = ""

        store.prepareTerminalCommandForRerun(commandID)

        let captured = await executor.capturedRequests
        XCTAssertEqual(captured.count, 1)
        XCTAssertEqual(store.selectedTerminalSessionID, sourceSession.id)
        XCTAssertEqual(store.terminalCommandInput, "pwd")
        XCTAssertNil(store.terminalError)
    }

    func testTerminalExecutePermissionBlocksPreparingCommandForRerun() async throws {
        let commandID = UUID(uuidString: "00000000-0000-0000-0000-0000000E1202")!
        let executor = FakeTerminalCodeExecutor(
            run: AppCodeExecutionRun(
                id: commandID,
                language: .shell,
                code: "pwd",
                workingDirectoryPath: "/tmp",
                stdout: "/tmp\n",
                status: .succeeded,
                exitCode: 0,
                startedAt: Date(timeIntervalSince1970: 70),
                completedAt: Date(timeIntervalSince1970: 71)
            )
        )
        let fixture = try TerminalSessionFixture(executor: executor)
        let store = fixture.makeStore()
        await store.load()
        await store.setFeatureToggle(.terminalSessions, isEnabled: true)
        let createdSession = await store.createTerminalSession(title: "Source", workingDirectoryPath: "/tmp")
        let session = try XCTUnwrap(createdSession)
        store.terminalCommandInput = "pwd"
        await store.runTerminalCommand()
        await store.createAdminUser(name: "Workspace User", email: "user@example.com", role: .user)
        let user = try XCTUnwrap(store.adminUsers.first)
        await store.createAdminGroup(
            name: "Terminal Editors",
            description: "Can manage terminal history.",
            permissions: ["terminal.write"]
        )
        let group = try XCTUnwrap(store.adminGroups.first)
        await store.setAdminGroupMembers(group.id, memberIDs: [user.id])
        store.currentUserID = user.id
        store.terminalCommandInput = ""

        store.prepareTerminalCommandForRerun(commandID)

        XCTAssertEqual(store.selectedTerminalSessionID, session.id)
        XCTAssertEqual(store.terminalCommandInput, "")
        XCTAssertEqual(store.terminalError, "You do not have permission to use terminal sessions.")
    }

    func testWorkspaceBackupIncludesTerminalSessionsAndCommands() async throws {
        let commandID = UUID(uuidString: "00000000-0000-0000-0000-0000000C0BEE")!
        let executor = FakeTerminalCodeExecutor(
            run: AppCodeExecutionRun(
                id: commandID,
                language: .shell,
                code: "pwd",
                workingDirectoryPath: "/tmp",
                stdout: "/tmp\n",
                status: .succeeded,
                exitCode: 0,
                startedAt: Date(timeIntervalSince1970: 20),
                completedAt: Date(timeIntervalSince1970: 21)
            )
        )
        let fixture = try TerminalSessionFixture(executor: executor)
        let store = fixture.makeStore()
        await store.load()
        await store.setFeatureToggle(.terminalSessions, isEnabled: true)
        let createdSession = await store.createTerminalSession(title: "Backup Terminal", workingDirectoryPath: "/tmp")
        let session = try XCTUnwrap(createdSession)
        store.terminalCommandInput = "pwd"

        await store.runTerminalCommand()

        let data = try await store.exportWorkspaceBackupJSONData()
        let backup = try WorkspaceBackupService().backup(fromJSONData: data)

        XCTAssertEqual(backup.terminalSessions.map(\.id), [session.id])
        XCTAssertEqual(backup.terminalCommands.map(\.id), [commandID])
        XCTAssertEqual(backup.terminalCommands.first?.stdout, "/tmp\n")
    }

    func testDeleteTerminalCommandRemovesPersistedTranscriptAndAuditsDeletion() async throws {
        let commandID = UUID(uuidString: "00000000-0000-0000-0000-0000000D3117")!
        let executor = FakeTerminalCodeExecutor(
            run: AppCodeExecutionRun(
                id: commandID,
                language: .shell,
                code: "pwd",
                workingDirectoryPath: "/tmp",
                stdout: "/tmp\n",
                status: .succeeded,
                exitCode: 0,
                startedAt: Date(timeIntervalSince1970: 30),
                completedAt: Date(timeIntervalSince1970: 31)
            )
        )
        let fixture = try TerminalSessionFixture(executor: executor)
        let store = fixture.makeStore()
        await store.load()
        await store.setFeatureToggle(.terminalSessions, isEnabled: true)
        let createdSession = await store.createTerminalSession(title: "Delete Command", workingDirectoryPath: "/tmp")
        let session = try XCTUnwrap(createdSession)
        store.terminalCommandInput = "pwd"
        await store.runTerminalCommand()

        await store.deleteTerminalCommand(commandID)

        let persistedCommands = try await fixture.terminalStorage.loadCommands()

        XCTAssertTrue(store.terminalCommands.isEmpty)
        XCTAssertTrue(persistedCommands.isEmpty)
        XCTAssertNil(store.terminalError)

        let event = try XCTUnwrap(store.auditEvents.first(where: { $0.action == .terminalCommandDeleted }))
        XCTAssertEqual(event.outcome, .succeeded)
        XCTAssertEqual(event.summary, "Deleted terminal command")
        XCTAssertEqual(event.metadata["sessionID"], session.id.uuidString)
        XCTAssertEqual(event.metadata["commandID"], commandID.uuidString)
        XCTAssertNil(event.metadata["command"])
        XCTAssertNil(event.metadata["stdout"])
        XCTAssertNil(event.metadata["stderr"])
    }

    func testDeleteTerminalSessionRemovesSessionCommandsSelectionAndAuditsDeletion() async throws {
        let commandID = UUID(uuidString: "00000000-0000-0000-0000-0000000D3118")!
        let executor = FakeTerminalCodeExecutor(
            run: AppCodeExecutionRun(
                id: commandID,
                language: .shell,
                code: "pwd",
                workingDirectoryPath: "/tmp",
                stdout: "/tmp\n",
                status: .succeeded,
                exitCode: 0,
                startedAt: Date(timeIntervalSince1970: 40),
                completedAt: Date(timeIntervalSince1970: 41)
            )
        )
        let fixture = try TerminalSessionFixture(executor: executor)
        let store = fixture.makeStore()
        await store.load()
        await store.setFeatureToggle(.terminalSessions, isEnabled: true)
        let createdSession = await store.createTerminalSession(title: "Delete Session", workingDirectoryPath: "/tmp")
        let session = try XCTUnwrap(createdSession)
        store.terminalCommandInput = "pwd"
        await store.runTerminalCommand()

        await store.deleteTerminalSession(session.id)

        let persistedSessions = try await fixture.terminalStorage.loadSessions()
        let persistedCommands = try await fixture.terminalStorage.loadCommands()

        XCTAssertTrue(store.terminalSessions.isEmpty)
        XCTAssertTrue(store.terminalCommands.isEmpty)
        XCTAssertNil(store.selectedTerminalSessionID)
        XCTAssertTrue(persistedSessions.isEmpty)
        XCTAssertTrue(persistedCommands.isEmpty)
        XCTAssertNil(store.terminalError)

        let event = try XCTUnwrap(store.auditEvents.first(where: { $0.action == .terminalSessionDeleted }))
        XCTAssertEqual(event.outcome, .succeeded)
        XCTAssertEqual(event.summary, "Deleted terminal session")
        XCTAssertEqual(event.metadata["sessionID"], session.id.uuidString)
        XCTAssertEqual(event.metadata["deletedCommandCount"], "1")
    }

    func testSelectTerminalSessionsClearsOtherDetailSelections() throws {
        let store = AppStore(secretStore: InMemorySecretStore(), codeExecutor: FakeTerminalCodeExecutor())
        store.selectedThreadID = UUID()
        store.selectedChannelID = UUID()
        store.isShowingEvaluationDashboard = true
        store.isShowingAnalyticsDashboard = true
        store.isShowingPlayground = true
        store.isShowingImageGeneration = true
        store.isShowingAudio = true
        store.isShowingCodeInterpreter = true
        store.isShowingCalendar = true

        store.selectTerminalSessions()

        XCTAssertNil(store.selectedThreadID)
        XCTAssertNil(store.selectedChannelID)
        XCTAssertFalse(store.isShowingEvaluationDashboard)
        XCTAssertFalse(store.isShowingAnalyticsDashboard)
        XCTAssertFalse(store.isShowingPlayground)
        XCTAssertFalse(store.isShowingImageGeneration)
        XCTAssertFalse(store.isShowingAudio)
        XCTAssertFalse(store.isShowingCodeInterpreter)
        XCTAssertFalse(store.isShowingCalendar)
        XCTAssertTrue(store.isShowingTerminalSessions)
    }
}

final class TerminalSessionStorageTests: XCTestCase {
    func testSaveAndLoadSessionsAndCommandsRoundTripNewestFirst() async throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let storage = JSONTerminalSessionStorageService(rootURL: rootURL)
        let olderSession = AppTerminalSession(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            title: "Older",
            workingDirectoryPath: "/tmp",
            createdAt: Date(timeIntervalSince1970: 100),
            updatedAt: Date(timeIntervalSince1970: 100)
        )
        let newerSession = AppTerminalSession(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
            title: "Newer",
            workingDirectoryPath: "/Users/example",
            createdAt: Date(timeIntervalSince1970: 200),
            updatedAt: Date(timeIntervalSince1970: 250)
        )
        let olderCommand = AppTerminalCommand(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000003")!,
            sessionID: olderSession.id,
            command: "pwd",
            workingDirectoryPath: "/tmp",
            stdout: "/tmp\n",
            status: .succeeded,
            exitCode: 0,
            startedAt: Date(timeIntervalSince1970: 110),
            completedAt: Date(timeIntervalSince1970: 111)
        )
        let newerCommand = AppTerminalCommand(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000004")!,
            sessionID: newerSession.id,
            command: "ls",
            workingDirectoryPath: "/Users/example",
            stdout: "Project\n",
            status: .succeeded,
            exitCode: 0,
            startedAt: Date(timeIntervalSince1970: 260),
            completedAt: Date(timeIntervalSince1970: 261)
        )

        try await storage.saveSession(olderSession)
        try await storage.saveSession(newerSession)
        try await storage.saveCommand(olderCommand)
        try await storage.saveCommand(newerCommand)

        let sessions = try await storage.loadSessions()
        let commands = try await storage.loadCommands()

        XCTAssertEqual(sessions.map(\.id), [newerSession.id, olderSession.id])
        XCTAssertEqual(commands.map(\.id), [newerCommand.id, olderCommand.id])
        XCTAssertEqual(commands.first?.stdout, "Project\n")
    }
}

private struct TerminalSessionFixture {
    let rootURL: URL
    let settingsStore: SettingsStore
    let terminalStorage: JSONTerminalSessionStorageService
    let auditStorage: JSONAuditLogStorageService
    let adminStorage: JSONAdminDirectoryStorageService
    let executor: any CodeExecuting

    init(executor: any CodeExecuting) throws {
        rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        settingsStore = SettingsStore(settingsURL: rootURL.appendingPathComponent("settings.json"))
        terminalStorage = JSONTerminalSessionStorageService(
            rootURL: rootURL.appendingPathComponent("Terminal", isDirectory: true)
        )
        auditStorage = JSONAuditLogStorageService(rootURL: rootURL.appendingPathComponent("AuditLog", isDirectory: true))
        adminStorage = JSONAdminDirectoryStorageService(
            snapshotURL: rootURL.appendingPathComponent("admin-directory.json")
        )
        self.executor = executor
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
    }

    @MainActor
    func makeStore() -> AppStore {
        AppStore(
            settingsStore: settingsStore,
            secretStore: InMemorySecretStore(),
            terminalStorage: terminalStorage,
            auditLogStorage: auditStorage,
            codeExecutor: executor,
            adminDirectoryStorage: adminStorage
        )
    }
}

private actor FakeTerminalCodeExecutor: CodeExecuting {
    private let run: AppCodeExecutionRun
    private(set) var capturedRequests: [CodeExecutionRequest] = []

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
        capturedRequests.append(request)
        return run
    }
}
