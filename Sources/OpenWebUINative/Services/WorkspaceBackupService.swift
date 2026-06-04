import Foundation

struct WorkspaceBackup: Codable, Equatable, Sendable {
    var format: String
    var version: Int
    var exportedAt: Date
    var excludesSecrets: Bool
    var secretNotice: String
    var settings: AppSettings
    var threads: [ChatThread]
    var folders: [ChatFolder]
    var files: [AppFile]
    var prompts: [SavedPrompt]
    var notes: [AppNote]
    var tools: [AppTool]
    var toolRuns: [AppToolRun]
    var toolServers: [AppToolServer]
    var toolServerRuns: [AppToolServerRun]
    var functions: [AppFunction]
    var functionRuns: [AppFunctionRun]
    var skills: [AppSkill]
    var feedbacks: [AppFeedback]
    var adminDirectory: AdminDirectorySnapshot
    var channels: [AppChannel]
    var automations: [AppAutomation]
    var automationRuns: [AppAutomationRun]
    var calendar: CalendarSnapshot
    var playgroundHistory: [PlaygroundHistoryItem]
    var generatedImages: [AppGeneratedImage]
    var codeExecutionRuns: [AppCodeExecutionRun]
    var terminalSessions: [AppTerminalSession]
    var terminalCommands: [AppTerminalCommand]
    var audioHistory: [AppAudioHistoryItem]
    var auditEvents: [AppAuditEvent]
    var knowledge: KnowledgeSnapshot

    enum CodingKeys: String, CodingKey {
        case format
        case version
        case exportedAt
        case excludesSecrets
        case secretNotice
        case settings
        case threads
        case folders
        case files
        case prompts
        case notes
        case tools
        case toolRuns
        case toolServers
        case toolServerRuns
        case functions
        case functionRuns
        case skills
        case feedbacks
        case adminDirectory
        case channels
        case automations
        case automationRuns
        case calendar
        case playgroundHistory
        case generatedImages
        case codeExecutionRuns
        case terminalSessions
        case terminalCommands
        case audioHistory
        case auditEvents
        case knowledge
    }

    init(
        format: String = "open-webui-native-workspace",
        version: Int = 1,
        exportedAt: Date = Date(),
        excludesSecrets: Bool = true,
        secretNotice: String = "Keychain secret values are not exported. Re-enter provider API keys after restoring on another Mac.",
        settings: AppSettings,
        threads: [ChatThread],
        folders: [ChatFolder],
        files: [AppFile] = [],
        prompts: [SavedPrompt],
        notes: [AppNote],
        tools: [AppTool],
        toolRuns: [AppToolRun] = [],
        toolServers: [AppToolServer] = [],
        toolServerRuns: [AppToolServerRun] = [],
        functions: [AppFunction],
        functionRuns: [AppFunctionRun] = [],
        skills: [AppSkill],
        feedbacks: [AppFeedback],
        adminDirectory: AdminDirectorySnapshot,
        channels: [AppChannel],
        automations: [AppAutomation],
        automationRuns: [AppAutomationRun] = [],
        calendar: CalendarSnapshot,
        playgroundHistory: [PlaygroundHistoryItem],
        generatedImages: [AppGeneratedImage] = [],
        codeExecutionRuns: [AppCodeExecutionRun] = [],
        terminalSessions: [AppTerminalSession] = [],
        terminalCommands: [AppTerminalCommand] = [],
        audioHistory: [AppAudioHistoryItem] = [],
        auditEvents: [AppAuditEvent] = [],
        knowledge: KnowledgeSnapshot
    ) {
        self.format = format
        self.version = version
        self.exportedAt = exportedAt
        self.excludesSecrets = excludesSecrets
        self.secretNotice = secretNotice
        self.settings = settings
        self.threads = threads
        self.folders = folders
        self.files = files
        self.prompts = prompts
        self.notes = notes
        self.tools = tools
        self.toolRuns = toolRuns
        self.toolServers = toolServers
        self.toolServerRuns = toolServerRuns
        self.functions = functions
        self.functionRuns = functionRuns
        self.skills = skills
        self.feedbacks = feedbacks
        self.adminDirectory = adminDirectory
        self.channels = channels
        self.automations = automations
        self.automationRuns = automationRuns
        self.calendar = calendar
        self.playgroundHistory = playgroundHistory
        self.generatedImages = generatedImages
        self.codeExecutionRuns = codeExecutionRuns
        self.terminalSessions = terminalSessions
        self.terminalCommands = terminalCommands
        self.audioHistory = audioHistory
        self.auditEvents = auditEvents
        self.knowledge = knowledge
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        format = try container.decode(String.self, forKey: .format)
        version = try container.decode(Int.self, forKey: .version)
        exportedAt = try container.decode(Date.self, forKey: .exportedAt)
        excludesSecrets = try container.decode(Bool.self, forKey: .excludesSecrets)
        secretNotice = try container.decode(String.self, forKey: .secretNotice)
        settings = try container.decode(AppSettings.self, forKey: .settings)
        threads = try container.decode([ChatThread].self, forKey: .threads)
        folders = try container.decode([ChatFolder].self, forKey: .folders)
        files = try container.decodeIfPresent([AppFile].self, forKey: .files) ?? []
        prompts = try container.decode([SavedPrompt].self, forKey: .prompts)
        notes = try container.decode([AppNote].self, forKey: .notes)
        tools = try container.decode([AppTool].self, forKey: .tools)
        toolRuns = try container.decodeIfPresent([AppToolRun].self, forKey: .toolRuns) ?? []
        toolServers = try container.decodeIfPresent([AppToolServer].self, forKey: .toolServers) ?? []
        toolServerRuns = try container.decodeIfPresent([AppToolServerRun].self, forKey: .toolServerRuns) ?? []
        functions = try container.decode([AppFunction].self, forKey: .functions)
        functionRuns = try container.decodeIfPresent([AppFunctionRun].self, forKey: .functionRuns) ?? []
        skills = try container.decode([AppSkill].self, forKey: .skills)
        feedbacks = try container.decode([AppFeedback].self, forKey: .feedbacks)
        adminDirectory = try container.decode(AdminDirectorySnapshot.self, forKey: .adminDirectory)
        channels = try container.decode([AppChannel].self, forKey: .channels)
        automations = try container.decode([AppAutomation].self, forKey: .automations)
        automationRuns = try container.decodeIfPresent([AppAutomationRun].self, forKey: .automationRuns) ?? []
        calendar = try container.decode(CalendarSnapshot.self, forKey: .calendar)
        playgroundHistory = try container.decode([PlaygroundHistoryItem].self, forKey: .playgroundHistory)
        generatedImages = try container.decodeIfPresent([AppGeneratedImage].self, forKey: .generatedImages) ?? []
        codeExecutionRuns = try container.decodeIfPresent([AppCodeExecutionRun].self, forKey: .codeExecutionRuns) ?? []
        terminalSessions = try container.decodeIfPresent([AppTerminalSession].self, forKey: .terminalSessions) ?? []
        terminalCommands = try container.decodeIfPresent([AppTerminalCommand].self, forKey: .terminalCommands) ?? []
        audioHistory = try container.decodeIfPresent([AppAudioHistoryItem].self, forKey: .audioHistory) ?? []
        auditEvents = try container.decodeIfPresent([AppAuditEvent].self, forKey: .auditEvents) ?? []
        knowledge = try container.decode(KnowledgeSnapshot.self, forKey: .knowledge)
    }
}

struct WorkspaceBackupService: Sendable {
    func backup(
        settings: AppSettings,
        threads: [ChatThread],
        folders: [ChatFolder],
        files: [AppFile],
        prompts: [SavedPrompt],
        notes: [AppNote],
        tools: [AppTool],
        toolRuns: [AppToolRun],
        toolServers: [AppToolServer],
        toolServerRuns: [AppToolServerRun],
        functions: [AppFunction],
        functionRuns: [AppFunctionRun],
        skills: [AppSkill],
        feedbacks: [AppFeedback],
        adminDirectory: AdminDirectorySnapshot,
        channels: [AppChannel],
        automations: [AppAutomation],
        automationRuns: [AppAutomationRun],
        calendar: CalendarSnapshot,
        playgroundHistory: [PlaygroundHistoryItem],
        generatedImages: [AppGeneratedImage],
        codeExecutionRuns: [AppCodeExecutionRun],
        terminalSessions: [AppTerminalSession],
        terminalCommands: [AppTerminalCommand],
        audioHistory: [AppAudioHistoryItem],
        auditEvents: [AppAuditEvent],
        knowledge: KnowledgeSnapshot,
        exportedAt: Date = Date()
    ) -> WorkspaceBackup {
        WorkspaceBackup(
            exportedAt: exportedAt,
            settings: settings,
            threads: threads,
            folders: folders,
            files: files,
            prompts: prompts,
            notes: notes,
            tools: tools,
            toolRuns: toolRuns,
            toolServers: toolServers,
            toolServerRuns: toolServerRuns,
            functions: functions,
            functionRuns: functionRuns,
            skills: skills,
            feedbacks: feedbacks,
            adminDirectory: adminDirectory,
            channels: channels,
            automations: automations,
            automationRuns: automationRuns,
            calendar: calendar,
            playgroundHistory: playgroundHistory,
            generatedImages: generatedImages,
            codeExecutionRuns: codeExecutionRuns,
            terminalSessions: terminalSessions,
            terminalCommands: terminalCommands,
            audioHistory: audioHistory,
            auditEvents: auditEvents,
            knowledge: knowledge
        )
    }

    func jsonData(for backup: WorkspaceBackup) throws -> Data {
        try JSONEncoder.openWebUIEncoder.encode(backup)
    }

    func backup(fromJSONData data: Data) throws -> WorkspaceBackup {
        try JSONDecoder.openWebUIDecoder.decode(WorkspaceBackup.self, from: data)
    }
}
