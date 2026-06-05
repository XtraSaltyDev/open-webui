import Foundation
import XCTest
@testable import OpenWebUINative

@MainActor
final class AppStoreCodeInterpreterTests: XCTestCase {
    func testRunCodeExecutionRoutesRequestPersistsHistoryAndClearsRunningState() async throws {
        let runID = UUID(uuidString: "00000000-0000-0000-0000-00000000C0DE")!
        let executor = FakeCodeExecutor(
            run: AppCodeExecutionRun(
                id: runID,
                language: .shell,
                code: "printf hello",
                workingDirectoryPath: "/tmp",
                stdout: "hello",
                status: .succeeded,
                exitCode: 0,
                startedAt: Date(timeIntervalSince1970: 10),
                completedAt: Date(timeIntervalSince1970: 11)
            )
        )
        let fixture = try CodeInterpreterFixture(executor: executor)
        let store = fixture.makeStore()
        await store.load()
        store.enableLocalExecutionForTests(sandboxRootPath: "/tmp")
        await store.setFeatureToggle(.codeInterpreter, isEnabled: true)
        store.codeExecutionLanguage = .shell
        store.codeExecutionInput = "  printf hello  "
        store.codeExecutionWorkingDirectory = "  /tmp  "
        store.codeExecutionTimeoutSeconds = 3

        await store.runCodeExecution()

        let captured = await executor.capturedRequests
        XCTAssertEqual(captured.count, 1)
        XCTAssertEqual(captured.first?.language, .shell)
        XCTAssertEqual(captured.first?.code, "printf hello")
        XCTAssertEqual(captured.first?.workingDirectoryPath, "/tmp")
        XCTAssertEqual(captured.first?.timeoutSeconds, 3)
        XCTAssertEqual(store.codeExecutionRuns.map(\.id), [runID])
        XCTAssertEqual(store.selectedCodeExecutionRunID, runID)
        XCTAssertFalse(store.isRunningCodeExecution)
        XCTAssertNil(store.codeExecutionError)

        let reloadedStore = fixture.makeStore()
        await reloadedStore.load()

        XCTAssertEqual(reloadedStore.codeExecutionRuns.map(\.id), [runID])
        XCTAssertEqual(reloadedStore.codeExecutionRuns.first?.stdout, "hello")
    }

    func testRunCodeExecutionBlocksDisabledFeatureBeforeCallingExecutor() async throws {
        let executor = FakeCodeExecutor()
        let fixture = try CodeInterpreterFixture(executor: executor)
        let store = fixture.makeStore()
        await store.load()
        await store.setFeatureToggle(.codeInterpreter, isEnabled: false)
        store.codeExecutionLanguage = .shell
        store.codeExecutionInput = "printf hello"
        store.codeExecutionWorkingDirectory = ""

        await store.runCodeExecution()

        let captured = await executor.capturedRequests
        XCTAssertTrue(captured.isEmpty)
        XCTAssertTrue(store.codeExecutionRuns.isEmpty)
        XCTAssertEqual(store.codeExecutionError, "Code Interpreter is disabled.")
        XCTAssertEqual(store.errorMessage, "Code Interpreter is disabled.")
        XCTAssertFalse(store.isRunningCodeExecution)
        let persistedRuns = try await fixture.codeExecutionStorage.loadRuns()
        XCTAssertTrue(persistedRuns.isEmpty)
    }

    func testRunCodeExecutionBlocksDisabledLocalExecutionBeforeCallingExecutor() async throws {
        let executor = FakeCodeExecutor()
        let fixture = try CodeInterpreterFixture(executor: executor)
        let store = fixture.makeStore()
        await store.load()
        await store.setFeatureToggle(.codeInterpreter, isEnabled: true)
        store.codeExecutionLanguage = .shell
        store.codeExecutionInput = "printf hello"
        store.codeExecutionWorkingDirectory = LocalExecutionSettings.defaultSandboxRootPath()

        await store.runCodeExecution()

        let captured = await executor.capturedRequests
        XCTAssertTrue(captured.isEmpty)
        XCTAssertTrue(store.codeExecutionRuns.isEmpty)
        XCTAssertEqual(store.codeExecutionError, LocalExecutionSettings.disabledMessage)
        XCTAssertEqual(store.errorMessage, LocalExecutionSettings.disabledMessage)
        XCTAssertFalse(store.isRunningCodeExecution)
    }

    func testRunCodeExecutionShowsEmptyCodeErrorWithoutCallingExecutor() async throws {
        let executor = FakeCodeExecutor()
        let store = AppStore(secretStore: InMemorySecretStore(), codeExecutor: executor)
        await store.setFeatureToggle(.codeInterpreter, isEnabled: true)
        store.codeExecutionInput = "   "

        await store.runCodeExecution()

        let captured = await executor.capturedRequests
        XCTAssertTrue(captured.isEmpty)
        XCTAssertEqual(store.codeExecutionError, "Enter code to run.")
        XCTAssertEqual(store.errorMessage, "Enter code to run.")
        XCTAssertFalse(store.isRunningCodeExecution)
    }

    func testRunCodeExecutionBlocksDisabledLanguageWithoutCallingExecutor() async throws {
        let executor = FakeCodeExecutor()
        let store = AppStore(secretStore: InMemorySecretStore(), codeExecutor: executor)
        store.enableLocalExecutionForTests(sandboxRootPath: "/tmp")
        await store.setFeatureToggle(.codeInterpreter, isEnabled: true)
        store.settings.codeExecution = CodeExecutionSettings(
            allowedLanguages: [.python],
            allowedWorkingDirectoryRoots: ["/tmp"],
            maxTimeoutSeconds: 5
        )
        store.codeExecutionLanguage = .shell
        store.codeExecutionInput = "printf hello"
        store.codeExecutionWorkingDirectory = "/tmp"

        await store.runCodeExecution()

        let captured = await executor.capturedRequests
        XCTAssertTrue(captured.isEmpty)
        XCTAssertEqual(store.codeExecutionError, "Shell execution is disabled by policy.")
        XCTAssertEqual(store.errorMessage, "Shell execution is disabled by policy.")
        XCTAssertTrue(store.codeExecutionRuns.isEmpty)
    }

    func testRunCodeExecutionBlocksDeniedExecutableWithoutCallingExecutor() async throws {
        let executor = FakeCodeExecutor()
        let store = AppStore(secretStore: InMemorySecretStore(), codeExecutor: executor)
        store.enableLocalExecutionForTests(sandboxRootPath: "/tmp")
        await store.setFeatureToggle(.codeInterpreter, isEnabled: true)
        store.settings.codeExecution = CodeExecutionSettings(
            allowedLanguages: [.shell],
            allowedWorkingDirectoryRoots: ["/tmp"],
            deniedExecutableNames: ["rm"],
            maxTimeoutSeconds: 5
        )
        store.codeExecutionLanguage = .shell
        store.codeExecutionInput = "printf hello\nrm -rf ./build"
        store.codeExecutionWorkingDirectory = "/tmp"

        await store.runCodeExecution()

        let captured = await executor.capturedRequests
        XCTAssertTrue(captured.isEmpty)
        XCTAssertEqual(store.codeExecutionError, "Executable 'rm' is blocked by code execution policy.")
        XCTAssertEqual(store.errorMessage, "Executable 'rm' is blocked by code execution policy.")
        XCTAssertTrue(store.codeExecutionRuns.isEmpty)
    }

    func testRunCodeExecutionCapsTimeoutBeforeCallingExecutor() async throws {
        let executor = FakeCodeExecutor()
        let store = AppStore(secretStore: InMemorySecretStore(), codeExecutor: executor)
        store.enableLocalExecutionForTests(sandboxRootPath: "/tmp")
        await store.setFeatureToggle(.codeInterpreter, isEnabled: true)
        store.settings.codeExecution = CodeExecutionSettings(
            allowedLanguages: [.shell],
            allowedWorkingDirectoryRoots: ["/tmp"],
            maxTimeoutSeconds: 4
        )
        store.codeExecutionLanguage = .shell
        store.codeExecutionInput = "printf hello"
        store.codeExecutionWorkingDirectory = "/tmp"
        store.codeExecutionTimeoutSeconds = 60

        await store.runCodeExecution()

        let captured = await executor.capturedRequests
        XCTAssertEqual(captured.first?.timeoutSeconds, 4)
    }

    func testCodeExecutePermissionAllowsCurrentUserToRunCode() async throws {
        let executor = FakeCodeExecutor()
        let fixture = try CodeInterpreterFixture(executor: executor)
        let store = fixture.makeStore()
        await store.load()
        store.enableLocalExecutionForTests(sandboxRootPath: "/tmp")
        await store.setFeatureToggle(.codeInterpreter, isEnabled: true)
        await store.createAdminUser(name: "Workspace User", email: "user@example.com", role: .user)
        let user = try XCTUnwrap(store.adminUsers.first)
        await store.createAdminGroup(name: "Code Runners", description: "Can run local code.", permissions: ["code.execute"])
        let group = try XCTUnwrap(store.adminGroups.first)
        await store.setAdminGroupMembers(group.id, memberIDs: [user.id])
        store.currentUserID = user.id
        store.codeExecutionLanguage = .shell
        store.codeExecutionInput = "printf hello"
        store.codeExecutionWorkingDirectory = ""

        await store.runCodeExecution()

        let captured = await executor.capturedRequests
        XCTAssertEqual(captured.count, 1)
        XCTAssertNil(store.codeExecutionError)
        XCTAssertNil(store.errorMessage)
    }

    func testCodeExecutePermissionBlocksCurrentUserBeforeCallingExecutor() async throws {
        let executor = FakeCodeExecutor()
        let fixture = try CodeInterpreterFixture(executor: executor)
        let store = fixture.makeStore()
        await store.load()
        await store.setFeatureToggle(.codeInterpreter, isEnabled: true)
        await store.createAdminUser(name: "Workspace User", email: "user@example.com", role: .user)
        let user = try XCTUnwrap(store.adminUsers.first)
        store.currentUserID = user.id
        store.codeExecutionLanguage = .shell
        store.codeExecutionInput = "printf hello"
        store.codeExecutionWorkingDirectory = ""

        await store.runCodeExecution()

        let captured = await executor.capturedRequests
        XCTAssertTrue(captured.isEmpty)
        XCTAssertTrue(store.codeExecutionRuns.isEmpty)
        XCTAssertEqual(store.codeExecutionError, "You do not have permission to run code.")
        XCTAssertEqual(store.errorMessage, "You do not have permission to run code.")
        XCTAssertFalse(store.isRunningCodeExecution)
    }

    func testUnmanagedLocalUserCanRunCodeWhenAdminDirectoryExists() async throws {
        let executor = FakeCodeExecutor()
        let fixture = try CodeInterpreterFixture(executor: executor)
        let store = fixture.makeStore()
        await store.load()
        store.enableLocalExecutionForTests(sandboxRootPath: "/tmp")
        await store.setFeatureToggle(.codeInterpreter, isEnabled: true)
        await store.createAdminUser(name: "Workspace User", email: "user@example.com", role: .user)
        store.codeExecutionLanguage = .shell
        store.codeExecutionInput = "printf hello"
        store.codeExecutionWorkingDirectory = ""

        await store.runCodeExecution()

        let captured = await executor.capturedRequests
        XCTAssertEqual(captured.count, 1)
        XCTAssertNil(store.codeExecutionError)
    }

    func testDeleteCodeExecutionRunCreatesAuditMarkerWithoutRunContent() async throws {
        let runID = UUID(uuidString: "00000000-0000-0000-0000-00000000D317")!
        let run = AppCodeExecutionRun(
            id: runID,
            language: .python,
            code: "print('secret')",
            workingDirectoryPath: "/tmp",
            stdout: "secret",
            stderr: "traceback",
            status: .failed,
            exitCode: 1,
            startedAt: Date(timeIntervalSince1970: 30),
            completedAt: Date(timeIntervalSince1970: 31)
        )
        let fixture = try CodeInterpreterFixture(executor: FakeCodeExecutor())
        let store = fixture.makeStore()
        await store.load()
        await store.setFeatureToggle(.codeInterpreter, isEnabled: true)
        try await fixture.codeExecutionStorage.save(run)
        store.codeExecutionRuns = [run]
        store.selectedCodeExecutionRunID = runID

        await store.deleteCodeExecutionRun(runID)

        let persistedRuns = try await fixture.codeExecutionStorage.loadRuns()
        XCTAssertTrue(store.codeExecutionRuns.isEmpty)
        XCTAssertTrue(persistedRuns.isEmpty)
        XCTAssertNil(store.selectedCodeExecutionRunID)

        let event = try XCTUnwrap(store.auditEvents.first(where: { $0.action == .codeExecutionRunDeleted }))
        XCTAssertEqual(event.outcome, .succeeded)
        XCTAssertEqual(event.summary, "Deleted code execution run")
        XCTAssertEqual(event.metadata["runID"], runID.uuidString)
        XCTAssertEqual(event.metadata["language"], "python")
        XCTAssertEqual(event.metadata["status"], "failed")
        XCTAssertNil(event.metadata["code"])
        XCTAssertNil(event.metadata["stdout"])
        XCTAssertNil(event.metadata["stderr"])
    }

    func testDeleteCodeExecutionRunBlocksDisabledFeatureBeforeDeletingOrAuditing() async throws {
        let runID = UUID(uuidString: "00000000-0000-0000-0000-00000000D318")!
        let run = AppCodeExecutionRun(
            id: runID,
            language: .shell,
            code: "printf secret",
            stdout: "secret",
            status: .succeeded,
            exitCode: 0,
            startedAt: Date(timeIntervalSince1970: 40),
            completedAt: Date(timeIntervalSince1970: 41)
        )
        let fixture = try CodeInterpreterFixture(executor: FakeCodeExecutor())
        let store = fixture.makeStore()
        await store.load()
        await store.setFeatureToggle(.codeInterpreter, isEnabled: false)
        try await fixture.codeExecutionStorage.save(run)
        store.codeExecutionRuns = [run]
        store.selectedCodeExecutionRunID = runID

        await store.deleteCodeExecutionRun(runID)

        let persistedRuns = try await fixture.codeExecutionStorage.loadRuns()
        XCTAssertEqual(store.codeExecutionRuns, [run])
        XCTAssertEqual(persistedRuns, [run])
        XCTAssertEqual(store.selectedCodeExecutionRunID, runID)
        XCTAssertEqual(store.codeExecutionError, "Code Interpreter is disabled.")
        XCTAssertEqual(store.errorMessage, "Code Interpreter is disabled.")
        XCTAssertFalse(store.auditEvents.contains { $0.action == .codeExecutionRunDeleted })
    }

    func testDeleteCodeExecutionRunRequiresCodeExecuteBeforeDeletingOrAuditing() async throws {
        let runID = UUID(uuidString: "00000000-0000-0000-0000-00000000D319")!
        let run = AppCodeExecutionRun(
            id: runID,
            language: .python,
            code: "print('secret')",
            stdout: "secret",
            status: .succeeded,
            exitCode: 0,
            startedAt: Date(timeIntervalSince1970: 50),
            completedAt: Date(timeIntervalSince1970: 51)
        )
        let fixture = try CodeInterpreterFixture(executor: FakeCodeExecutor())
        let store = fixture.makeStore()
        await store.load()
        await store.setFeatureToggle(.codeInterpreter, isEnabled: true)
        try await fixture.codeExecutionStorage.save(run)
        store.codeExecutionRuns = [run]
        store.selectedCodeExecutionRunID = runID
        store.adminUsers = [
            AdminUser(id: "local-user", name: "Local User", email: "local@example.com", role: .user)
        ]

        await store.deleteCodeExecutionRun(runID)

        let persistedRuns = try await fixture.codeExecutionStorage.loadRuns()
        XCTAssertEqual(store.codeExecutionRuns, [run])
        XCTAssertEqual(persistedRuns, [run])
        XCTAssertEqual(store.selectedCodeExecutionRunID, runID)
        XCTAssertEqual(store.codeExecutionError, "You do not have permission to run code.")
        XCTAssertEqual(store.errorMessage, "You do not have permission to run code.")
        XCTAssertFalse(store.auditEvents.contains { $0.action == .codeExecutionRunDeleted })
    }

    func testSelectCodeInterpreterClearsOtherDetailSelections() throws {
        let store = AppStore(secretStore: InMemorySecretStore(), codeExecutor: FakeCodeExecutor())
        store.selectedThreadID = UUID()
        store.selectedChannelID = UUID()
        store.isShowingEvaluationDashboard = true
        store.isShowingAnalyticsDashboard = true
        store.isShowingPlayground = true
        store.isShowingImageGeneration = true
        store.isShowingAudio = true
        store.isShowingCalendar = true

        store.selectCodeInterpreter()

        XCTAssertNil(store.selectedThreadID)
        XCTAssertNil(store.selectedChannelID)
        XCTAssertFalse(store.isShowingEvaluationDashboard)
        XCTAssertFalse(store.isShowingAnalyticsDashboard)
        XCTAssertFalse(store.isShowingPlayground)
        XCTAssertFalse(store.isShowingImageGeneration)
        XCTAssertFalse(store.isShowingAudio)
        XCTAssertFalse(store.isShowingCalendar)
        XCTAssertTrue(store.isShowingCodeInterpreter)
    }
}

private struct CodeInterpreterFixture {
    let rootURL: URL
    let settingsStore: SettingsStore
    let codeExecutionStorage: JSONCodeExecutionStorageService
    let auditStorage: JSONAuditLogStorageService
    let adminStorage: JSONAdminDirectoryStorageService
    let executor: any CodeExecuting

    init(executor: any CodeExecuting) throws {
        rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        settingsStore = SettingsStore(settingsURL: rootURL.appendingPathComponent("settings.json"))
        codeExecutionStorage = JSONCodeExecutionStorageService(
            rootURL: rootURL.appendingPathComponent("CodeExecution", isDirectory: true)
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
            codeExecutionStorage: codeExecutionStorage,
            auditLogStorage: auditStorage,
            codeExecutor: executor,
            adminDirectoryStorage: adminStorage
        )
    }
}

private actor FakeCodeExecutor: CodeExecuting {
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
