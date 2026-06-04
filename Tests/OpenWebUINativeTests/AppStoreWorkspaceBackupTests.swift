import XCTest
@testable import OpenWebUINative

@MainActor
final class AppStoreWorkspaceBackupTests: XCTestCase {
    func testWorkspaceBackupJSONRoundTripsMajorWorkspaceSurfaces() async throws {
        let fixture = try WorkspaceBackupFixture()
        let store = fixture.makeStore()
        await store.load()
        await store.createPrompt(title: "Bug triage", content: "Summarize the bug.")
        await store.createNote(title: "Release note", content: "Ship native backup.")
        store.createThread()
        await store.send("Remember this thread.")
        await store.createCalendar(name: "Team", color: "#22c55e")
        let image = AppGeneratedImage(
            prompt: "Workspace image",
            modelID: "gpt-image-1",
            imageData: Data("workspace-image".utf8),
            createdAt: Date(timeIntervalSince1970: 600)
        )
        let codeRun = AppCodeExecutionRun(
            language: .shell,
            code: "printf workspace",
            stdout: "workspace",
            status: .succeeded,
            exitCode: 0,
            startedAt: Date(timeIntervalSince1970: 800),
            completedAt: Date(timeIntervalSince1970: 801)
        )
        let toolRun = AppToolRun(
            toolID: "workspace-tool",
            toolName: "Workspace Tool",
            functionName: "run",
            argumentsBody: "{}",
            output: "workspace tool",
            stderr: "",
            status: .succeeded,
            exitCode: 0,
            startedAt: Date(timeIntervalSince1970: 825),
            completedAt: Date(timeIntervalSince1970: 826)
        )
        let functionRun = AppFunctionRun(
            functionID: "workspace-function",
            functionName: "Workspace Function",
            functionKind: .filter,
            methodName: "inlet",
            inputBody: "{}",
            output: "workspace function",
            stderr: "",
            status: .succeeded,
            exitCode: 0,
            startedAt: Date(timeIntervalSince1970: 835),
            completedAt: Date(timeIntervalSince1970: 836)
        )
        let audioItem = AppAudioHistoryItem(
            kind: .speech,
            title: "workspace-speech.mp3",
            text: "Workspace speech",
            modelID: "gpt-4o-mini-tts",
            voice: "coral",
            outputFormat: "mp3",
            audioData: Data("workspace-speech".utf8),
            createdAt: Date(timeIntervalSince1970: 850),
            updatedAt: Date(timeIntervalSince1970: 851)
        )
        let auditEvent = AppAuditEvent(
            action: .workspaceBackupExported,
            outcome: .succeeded,
            summary: "Exported workspace backup",
            metadata: ["surface": "settings"],
            createdAt: Date(timeIntervalSince1970: 860)
        )
        let toolServer = AppToolServer(
            id: "workspace-mcp",
            name: "Workspace MCP",
            kind: .stdio,
            command: "uvx",
            arguments: ["workspace-server"],
            environment: ["ROOT": "/tmp"],
            isEnabled: true,
            createdAt: Date(timeIntervalSince1970: 870),
            updatedAt: Date(timeIntervalSince1970: 871)
        )
        let toolServerRun = AppToolServerRun(
            serverID: "workspace-mcp",
            serverName: "Workspace MCP",
            serverKind: .stdio,
            requestBody: "{}",
            responseBody: "partial stdout",
            statusCode: 7,
            status: .failed,
            errorMessage: "fixture failed",
            startedAt: Date(timeIntervalSince1970: 880),
            completedAt: Date(timeIntervalSince1970: 881)
        )
        let file = AppFile(
            fileName: "workspace-brief.md",
            contentType: "text/markdown",
            byteCount: Data("Workspace file context.".utf8).count,
            textContent: "Workspace file context.",
            createdAt: Date(timeIntervalSince1970: 890),
            updatedAt: Date(timeIntervalSince1970: 891)
        )
        store.files = [file]
        store.generatedImages = [image]
        store.codeExecutionRuns = [codeRun]
        store.toolRuns = [toolRun]
        store.functionRuns = [functionRun]
        store.audioHistory = [audioItem]
        store.auditEvents = [auditEvent]
        store.toolServers = [toolServer]
        store.toolServerRuns = [toolServerRun]

        let data = try await store.exportWorkspaceBackupJSONData()
        let backup = try WorkspaceBackupService().backup(fromJSONData: data)

        XCTAssertEqual(backup.format, "open-webui-native-workspace")
        XCTAssertEqual(backup.prompts.map(\.title), ["Bug triage"])
        XCTAssertEqual(backup.notes.map(\.title), ["Release note"])
        XCTAssertEqual(backup.threads.first?.messages.first?.content, "Remember this thread.")
        XCTAssertTrue(backup.calendar.calendars.contains { $0.name == "Team" })
        XCTAssertEqual(backup.generatedImages, [image])
        XCTAssertEqual(backup.codeExecutionRuns, [codeRun])
        XCTAssertEqual(backup.toolRuns, [toolRun])
        XCTAssertEqual(backup.functionRuns, [functionRun])
        XCTAssertEqual(backup.audioHistory, [audioItem])
        XCTAssertEqual(backup.auditEvents, [auditEvent])
        XCTAssertEqual(backup.toolServers, [toolServer])
        XCTAssertEqual(backup.toolServerRuns, [toolServerRun])
        XCTAssertEqual(backup.files, [file])
        XCTAssertTrue(backup.excludesSecrets)
    }

    func testExportWorkspaceBackupJSONForUserActionCreatesAuditEventWithoutWorkspaceContent() async throws {
        let fixture = try WorkspaceBackupFixture()
        let store = fixture.makeStore()
        await store.load()
        await store.createPrompt(title: "Private prompt", content: "Do not leak this prompt.")
        await store.createNote(title: "Private note", content: "Do not leak this note.")
        store.createThread()
        await store.send("Do not leak this chat message.")

        let data = try await store.exportWorkspaceBackupJSONDataForUserAction()
        let backup = try WorkspaceBackupService().backup(fromJSONData: data)

        XCTAssertEqual(backup.prompts.map(\.title), ["Private prompt"])
        XCTAssertTrue(backup.threads.contains { thread in
            thread.messages.contains { $0.content == "Do not leak this chat message." }
        })
        let event = try XCTUnwrap(store.auditEvents.filter { $0.action == .workspaceBackupExported }.first)
        XCTAssertEqual(event.outcome, .succeeded)
        XCTAssertEqual(event.summary, "Exported workspace backup")
        XCTAssertEqual(event.metadata["exportedThreadCount"], "1")
        XCTAssertEqual(event.metadata["exportedPromptCount"], "1")
        XCTAssertEqual(event.metadata["exportedNoteCount"], "1")
        XCTAssertEqual(event.metadata["excludedSecrets"], "true")
        XCTAssertNil(event.metadata["title"])
        XCTAssertNil(event.metadata["content"])
        XCTAssertNil(event.metadata["message"])
    }

    func testImportWorkspaceBackupReplacesLocalDataAndPersists() async throws {
        let sourceFixture = try WorkspaceBackupFixture()
        let sourceStore = sourceFixture.makeStore()
        await sourceStore.load()
        await sourceStore.createPrompt(title: "Restored prompt", content: "Use this.")
        await sourceStore.createNote(title: "Restored note", content: "Keep this.")
        sourceStore.createThread()
        await sourceStore.send("Restored chat.")
        await sourceStore.createCalendar(name: "Restored calendar", color: "#3b82f6")
        let restoredImage = AppGeneratedImage(
            prompt: "Restored image",
            modelID: "gpt-image-1",
            imageData: Data("restored-image".utf8),
            createdAt: Date(timeIntervalSince1970: 700)
        )
        let restoredCodeRun = AppCodeExecutionRun(
            language: .python,
            code: "print('restored')",
            stdout: "restored\n",
            status: .succeeded,
            exitCode: 0,
            startedAt: Date(timeIntervalSince1970: 900),
            completedAt: Date(timeIntervalSince1970: 901)
        )
        let restoredToolRun = AppToolRun(
            toolID: "restored-tool",
            toolName: "Restored Tool",
            functionName: "lookup",
            argumentsBody: #"{"q":"restored"}"#,
            output: "restored tool",
            stderr: "",
            status: .succeeded,
            exitCode: 0,
            startedAt: Date(timeIntervalSince1970: 925),
            completedAt: Date(timeIntervalSince1970: 926)
        )
        let restoredFunctionRun = AppFunctionRun(
            functionID: "restored-function",
            functionName: "Restored Function",
            functionKind: .action,
            methodName: "action",
            inputBody: #"{"body":{"model":"restored"}}"#,
            output: "restored function",
            stderr: "",
            status: .succeeded,
            exitCode: 0,
            startedAt: Date(timeIntervalSince1970: 935),
            completedAt: Date(timeIntervalSince1970: 936)
        )
        let restoredAudioItem = AppAudioHistoryItem(
            kind: .transcription,
            title: "restored-meeting.wav",
            text: "Restored transcript.",
            modelID: "gpt-4o-mini-transcribe",
            sourceFileName: "restored-meeting.wav",
            sourceContentType: "audio/wav",
            createdAt: Date(timeIntervalSince1970: 950),
            updatedAt: Date(timeIntervalSince1970: 951)
        )
        let restoredAuditEvent = AppAuditEvent(
            action: .workspaceBackupImported,
            outcome: .succeeded,
            summary: "Imported workspace backup",
            metadata: ["surface": "settings"],
            createdAt: Date(timeIntervalSince1970: 960)
        )
        let restoredToolServer = AppToolServer(
            id: "restored-mcp",
            name: "Restored MCP",
            kind: .http,
            baseURL: "http://localhost:9999/mcp",
            isEnabled: false,
            createdAt: Date(timeIntervalSince1970: 970),
            updatedAt: Date(timeIntervalSince1970: 971)
        )
        let restoredToolServerRun = AppToolServerRun(
            serverID: "restored-mcp",
            serverName: "Restored MCP",
            serverKind: .http,
            requestBody: "{}",
            responseBody: #"{"ok":true}"#,
            statusCode: 200,
            status: .succeeded,
            startedAt: Date(timeIntervalSince1970: 980),
            completedAt: Date(timeIntervalSince1970: 981)
        )
        let restoredFile = AppFile(
            fileName: "restored-file.md",
            contentType: "text/markdown",
            byteCount: Data("Restored file context.".utf8).count,
            textContent: "Restored file context.",
            createdAt: Date(timeIntervalSince1970: 990),
            updatedAt: Date(timeIntervalSince1970: 991)
        )
        sourceStore.generatedImages = [restoredImage]
        sourceStore.codeExecutionRuns = [restoredCodeRun]
        sourceStore.toolRuns = [restoredToolRun]
        sourceStore.functionRuns = [restoredFunctionRun]
        sourceStore.audioHistory = [restoredAudioItem]
        sourceStore.auditEvents = [restoredAuditEvent]
        sourceStore.toolServers = [restoredToolServer]
        sourceStore.toolServerRuns = [restoredToolServerRun]
        sourceStore.files = [restoredFile]
        let data = try await sourceStore.exportWorkspaceBackupJSONData()

        let destinationFixture = try WorkspaceBackupFixture()
        let destinationStore = destinationFixture.makeStore()
        await destinationStore.load()
        await destinationStore.createPrompt(title: "Stale prompt", content: "Remove me.")
        await destinationStore.createNote(title: "Stale note", content: "Remove me.")
        destinationStore.createThread()
        await destinationStore.send("Stale chat.")
        let staleImage = AppGeneratedImage(
            prompt: "Stale image",
            modelID: "gpt-image-1",
            imageData: Data("stale-image".utf8),
            createdAt: Date(timeIntervalSince1970: 100)
        )
        try await destinationFixture.generatedImageStorage.save(staleImage)
        let staleCodeRun = AppCodeExecutionRun(
            language: .shell,
            code: "printf stale",
            stdout: "stale",
            status: .succeeded,
            exitCode: 0,
            startedAt: Date(timeIntervalSince1970: 200),
            completedAt: Date(timeIntervalSince1970: 201)
        )
        try await destinationFixture.codeExecutionStorage.save(staleCodeRun)
        let staleToolRun = AppToolRun(
            toolID: "stale-tool",
            toolName: "Stale Tool",
            functionName: "run",
            argumentsBody: "{}",
            output: "stale tool",
            stderr: "",
            status: .succeeded,
            exitCode: 0
        )
        try await destinationFixture.toolRunStorage.save(staleToolRun)
        let staleFunctionRun = AppFunctionRun(
            functionID: "stale-function",
            functionName: "Stale Function",
            functionKind: .filter,
            methodName: "inlet",
            inputBody: "{}",
            output: "stale function",
            stderr: "",
            status: .succeeded,
            exitCode: 0
        )
        try await destinationFixture.functionRunStorage.save(staleFunctionRun)
        let staleAudioItem = AppAudioHistoryItem(
            kind: .speech,
            title: "stale-speech.mp3",
            text: "Stale speech.",
            modelID: "gpt-4o-mini-tts",
            outputFormat: "mp3",
            audioData: Data("stale-speech".utf8)
        )
        try await destinationFixture.audioHistoryStorage.save(staleAudioItem)
        let staleAuditEvent = AppAuditEvent(
            action: .featureToggleUpdated,
            outcome: .succeeded,
            summary: "Stale audit event"
        )
        try await destinationFixture.auditStorage.save(staleAuditEvent)
        let staleToolServer = AppToolServer(
            id: "stale-mcp",
            name: "Stale MCP",
            kind: .stdio,
            command: "stale",
            isEnabled: true
        )
        try await destinationFixture.toolServerStorage.save(staleToolServer)
        let staleToolServerRun = AppToolServerRun(
            serverID: "stale-mcp",
            serverName: "Stale MCP",
            serverKind: .stdio,
            requestBody: "{}",
            responseBody: "",
            statusCode: nil,
            status: .failed
        )
        try await destinationFixture.toolServerRunStorage.save(staleToolServerRun)
        let staleFile = AppFile(
            fileName: "stale-file.md",
            contentType: "text/markdown",
            byteCount: Data("Stale file context.".utf8).count,
            textContent: "Stale file context."
        )
        try await destinationFixture.fileStorage.save(staleFile)

        try await destinationStore.importWorkspaceBackupJSONData(data)

        XCTAssertEqual(destinationStore.prompts.map(\.title), ["Restored prompt"])
        XCTAssertEqual(destinationStore.notes.map(\.title), ["Restored note"])
        XCTAssertEqual(destinationStore.threads.map(\.title), sourceStore.threads.map(\.title))
        XCTAssertFalse(destinationStore.threads.contains { thread in
            thread.messages.contains { $0.content == "Stale chat." }
        })
        XCTAssertTrue(destinationStore.calendars.contains { $0.name == "Restored calendar" })
        XCTAssertEqual(destinationStore.generatedImages, [restoredImage])
        XCTAssertEqual(destinationStore.codeExecutionRuns, [restoredCodeRun])
        XCTAssertEqual(destinationStore.toolRuns, [restoredToolRun])
        XCTAssertEqual(destinationStore.functionRuns, [restoredFunctionRun])
        XCTAssertEqual(destinationStore.audioHistory, [restoredAudioItem])
        XCTAssertEqual(destinationStore.auditEvents, [restoredAuditEvent])
        XCTAssertEqual(destinationStore.toolServers, [restoredToolServer])
        XCTAssertEqual(destinationStore.toolServerRuns, [restoredToolServerRun])
        XCTAssertEqual(destinationStore.files, [restoredFile])

        let reloadedStore = destinationFixture.makeStore()
        await reloadedStore.load()

        XCTAssertEqual(reloadedStore.prompts.map(\.title), ["Restored prompt"])
        XCTAssertEqual(reloadedStore.notes.map(\.title), ["Restored note"])
        XCTAssertTrue(reloadedStore.threads.contains { thread in
            thread.messages.contains { $0.content == "Restored chat." }
        })
        XCTAssertFalse(reloadedStore.prompts.contains { $0.title == "Stale prompt" })
        XCTAssertEqual(reloadedStore.generatedImages, [restoredImage])
        XCTAssertEqual(reloadedStore.codeExecutionRuns, [restoredCodeRun])
        XCTAssertEqual(reloadedStore.toolRuns, [restoredToolRun])
        XCTAssertEqual(reloadedStore.functionRuns, [restoredFunctionRun])
        XCTAssertEqual(reloadedStore.audioHistory, [restoredAudioItem])
        XCTAssertEqual(reloadedStore.auditEvents, [restoredAuditEvent])
        XCTAssertEqual(reloadedStore.toolServers, [restoredToolServer])
        XCTAssertEqual(reloadedStore.toolServerRuns, [restoredToolServerRun])
        XCTAssertEqual(reloadedStore.files, [restoredFile])
    }

    func testImportWorkspaceBackupJSONForUserActionCreatesAuditEventWithoutWorkspaceContent() async throws {
        let sourceFixture = try WorkspaceBackupFixture()
        let sourceStore = sourceFixture.makeStore()
        await sourceStore.load()
        await sourceStore.createPrompt(title: "Restored private prompt", content: "Do not leak restored prompt.")
        await sourceStore.createNote(title: "Restored private note", content: "Do not leak restored note.")
        sourceStore.createThread()
        await sourceStore.send("Do not leak restored chat message.")
        let data = try await sourceStore.exportWorkspaceBackupJSONData()

        let destinationFixture = try WorkspaceBackupFixture()
        let destinationStore = destinationFixture.makeStore()
        await destinationStore.load()

        try await destinationStore.importWorkspaceBackupJSONDataForUserAction(data)

        XCTAssertEqual(destinationStore.prompts.map(\.title), ["Restored private prompt"])
        XCTAssertTrue(destinationStore.threads.contains { thread in
            thread.messages.contains { $0.content == "Do not leak restored chat message." }
        })
        let event = try XCTUnwrap(destinationStore.auditEvents.filter { $0.action == .workspaceBackupImported }.first)
        XCTAssertEqual(event.outcome, .succeeded)
        XCTAssertEqual(event.summary, "Imported workspace backup")
        XCTAssertEqual(event.metadata["importedThreadCount"], "1")
        XCTAssertEqual(event.metadata["importedPromptCount"], "1")
        XCTAssertEqual(event.metadata["importedNoteCount"], "1")
        XCTAssertEqual(event.metadata["excludedSecrets"], "true")
        XCTAssertNil(event.metadata["title"])
        XCTAssertNil(event.metadata["content"])
        XCTAssertNil(event.metadata["message"])
    }
}

private struct WorkspaceBackupFixture {
    let rootURL: URL
    let storage: JSONStorageService
    let folderStorage: JSONFolderStorageService
    let fileStorage: JSONAppFileStorageService
    let promptStorage: JSONPromptStorageService
    let noteStorage: JSONNoteStorageService
    let toolStorage: JSONToolStorageService
    let toolRunStorage: JSONToolRunStorageService
    let functionStorage: JSONFunctionStorageService
    let functionRunStorage: JSONFunctionRunStorageService
    let skillStorage: JSONSkillStorageService
    let feedbackStorage: JSONFeedbackStorageService
    let adminDirectoryStorage: JSONAdminDirectoryStorageService
    let channelStorage: JSONChannelStorageService
    let automationStorage: JSONAutomationStorageService
    let calendarStorage: JSONCalendarStorageService
    let playgroundHistoryStorage: JSONPlaygroundHistoryStorageService
    let generatedImageStorage: JSONGeneratedImageStorageService
    let codeExecutionStorage: JSONCodeExecutionStorageService
    let audioHistoryStorage: JSONAudioHistoryStorageService
    let auditStorage: JSONAuditLogStorageService
    let toolServerStorage: JSONToolServerStorageService
    let toolServerRunStorage: JSONToolServerRunStorageService
    let knowledgeStorage: JSONKnowledgeStorageService
    let knowledgeService: KnowledgeService
    let settingsStore: SettingsStore

    init() throws {
        rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        storage = JSONStorageService(rootURL: rootURL.appendingPathComponent("Chats", isDirectory: true))
        folderStorage = JSONFolderStorageService(rootURL: rootURL.appendingPathComponent("Folders", isDirectory: true))
        fileStorage = JSONAppFileStorageService(rootURL: rootURL.appendingPathComponent("Files", isDirectory: true))
        promptStorage = JSONPromptStorageService(rootURL: rootURL.appendingPathComponent("Prompts", isDirectory: true))
        noteStorage = JSONNoteStorageService(rootURL: rootURL.appendingPathComponent("Notes", isDirectory: true))
        toolStorage = JSONToolStorageService(rootURL: rootURL.appendingPathComponent("Tools", isDirectory: true))
        toolRunStorage = JSONToolRunStorageService(rootURL: rootURL.appendingPathComponent("ToolRuns", isDirectory: true))
        functionStorage = JSONFunctionStorageService(rootURL: rootURL.appendingPathComponent("Functions", isDirectory: true))
        functionRunStorage = JSONFunctionRunStorageService(
            rootURL: rootURL.appendingPathComponent("FunctionRuns", isDirectory: true)
        )
        skillStorage = JSONSkillStorageService(rootURL: rootURL.appendingPathComponent("Skills", isDirectory: true))
        feedbackStorage = JSONFeedbackStorageService(rootURL: rootURL.appendingPathComponent("Feedback", isDirectory: true))
        adminDirectoryStorage = JSONAdminDirectoryStorageService(
            snapshotURL: rootURL.appendingPathComponent("admin-directory.json")
        )
        channelStorage = JSONChannelStorageService(rootURL: rootURL.appendingPathComponent("Channels", isDirectory: true))
        automationStorage = JSONAutomationStorageService(rootURL: rootURL.appendingPathComponent("Automations", isDirectory: true))
        calendarStorage = JSONCalendarStorageService(
            snapshotURL: rootURL.appendingPathComponent("calendar.json")
        )
        playgroundHistoryStorage = JSONPlaygroundHistoryStorageService(
            rootURL: rootURL.appendingPathComponent("PlaygroundHistory", isDirectory: true)
        )
        generatedImageStorage = JSONGeneratedImageStorageService(
            rootURL: rootURL.appendingPathComponent("GeneratedImages", isDirectory: true)
        )
        codeExecutionStorage = JSONCodeExecutionStorageService(
            rootURL: rootURL.appendingPathComponent("CodeExecution", isDirectory: true)
        )
        audioHistoryStorage = JSONAudioHistoryStorageService(
            rootURL: rootURL.appendingPathComponent("AudioHistory", isDirectory: true)
        )
        auditStorage = JSONAuditLogStorageService(
            rootURL: rootURL.appendingPathComponent("AuditLog", isDirectory: true)
        )
        toolServerStorage = JSONToolServerStorageService(
            rootURL: rootURL.appendingPathComponent("ToolServers", isDirectory: true)
        )
        toolServerRunStorage = JSONToolServerRunStorageService(
            rootURL: rootURL.appendingPathComponent("ToolServerRuns", isDirectory: true)
        )
        knowledgeStorage = JSONKnowledgeStorageService(rootURL: rootURL.appendingPathComponent("Knowledge", isDirectory: true))
        knowledgeService = KnowledgeService(storage: knowledgeStorage)
        settingsStore = SettingsStore(settingsURL: rootURL.appendingPathComponent("settings.json"))
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
    }

    @MainActor
    func makeStore() -> AppStore {
        AppStore(
            storage: storage,
            folderStorage: folderStorage,
            fileStorage: fileStorage,
            settingsStore: settingsStore,
            secretStore: InMemorySecretStore(),
            providerOverride: FakeWorkspaceBackupProvider(),
            knowledgeService: knowledgeService,
            playgroundHistoryStorage: playgroundHistoryStorage,
            generatedImageStorage: generatedImageStorage,
            codeExecutionStorage: codeExecutionStorage,
            audioHistoryStorage: audioHistoryStorage,
            auditLogStorage: auditStorage,
            promptStorage: promptStorage,
            noteStorage: noteStorage,
            toolStorage: toolStorage,
            toolRunStorage: toolRunStorage,
            toolServerStorage: toolServerStorage,
            toolServerRunStorage: toolServerRunStorage,
            functionStorage: functionStorage,
            functionRunStorage: functionRunStorage,
            skillStorage: skillStorage,
            feedbackStorage: feedbackStorage,
            adminDirectoryStorage: adminDirectoryStorage,
            channelStorage: channelStorage,
            automationStorage: automationStorage,
            calendarStorage: calendarStorage
        )
    }
}

private struct FakeWorkspaceBackupProvider: ChatProvider {
    var configuration = ProviderConfiguration.defaultOllama()

    func listModels() async throws -> [ProviderModel] {
        [ProviderModel(id: "fake-model", name: "fake-model", provider: .ollama, providerID: configuration.id)]
    }

    func healthCheck() async -> ProviderStatus {
        .available("Fake connected")
    }

    func streamChat(model: String, messages: [ProviderChatMessage]) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            continuation.yield("ok")
            continuation.finish()
        }
    }

    func createEmbeddings(model: String, input: [String]) async throws -> [[Double]] {
        input.map { _ in [1.0] }
    }
}
