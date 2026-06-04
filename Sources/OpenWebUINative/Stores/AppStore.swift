import Foundation
import AppKit
import PDFKit
import UniformTypeIdentifiers

private struct ChatSearchQuery {
    var text = ""
    var isPinned: Bool?
    var isArchived: Bool?
    var tags: Set<String> = []
    var folderSlugs: Set<String> = []
}

private struct CalendarSearchQuery {
    var textTerms: [String] = []
    var calendarTerms: Set<String> = []
    var status: String?
}

private struct SkillSearchQuery {
    var textTerms: [String] = []
    var tags: Set<String> = []
    var isActive: Bool?
}

@MainActor
final class AppStore: ObservableObject {
    @Published var threads: [ChatThread] = []
    @Published var folders: [ChatFolder] = []
    @Published var selectedThreadID: UUID?
    @Published var models: [ProviderModel] = []
    @Published var providerStatus: ProviderStatus = .unknown
    @Published var settings: AppSettings = AppSettings()
    @Published var draftPrompt: String = ""
    @Published var pendingAttachments: [ChatAttachment] = []
    @Published var files: [AppFile] = []
    @Published var fileSearchText: String = ""
    @Published var knowledgeCollections: [KnowledgeCollection] = []
    @Published var knowledgeDocuments: [UUID: [KnowledgeDocument]] = [:]
    @Published var selectedKnowledgeDocumentDetail: KnowledgeDocumentDetail?
    @Published var selectedKnowledgeChunkID: UUID?
    @Published var isShowingEvaluationDashboard = false
    @Published var isShowingAnalyticsDashboard = false
    @Published var isShowingPlayground = false
    @Published var isShowingFiles = false
    @Published var isShowingImageGeneration = false
    @Published var isShowingAudio = false
    @Published var isShowingCodeInterpreter = false
    @Published var isShowingTerminalSessions = false
    @Published var prompts: [SavedPrompt] = []
    @Published var notes: [AppNote] = []
    @Published var tools: [AppTool] = []
    @Published var toolRuns: [AppToolRun] = []
    @Published var selectedToolRunID: UUID?
    @Published var isRunningTool = false
    @Published var toolExecutionError: String?
    @Published var toolServers: [AppToolServer] = []
    @Published var toolServerStatuses: [String: ToolServerConnectionStatus] = [:]
    @Published var toolServerRuns: [AppToolServerRun] = []
    @Published var selectedToolServerRunID: UUID?
    @Published var isInvokingToolServer = false
    @Published var toolServerInvocationError: String?
    @Published var toolServerInvocationRequestBody = "{}"
    @Published var toolServerTools: [String: [AppToolServerTool]] = [:]
    @Published var toolServerDiscoveryStatuses: [String: ToolServerConnectionStatus] = [:]
    @Published var isDiscoveringToolServerTools = false
    @Published var toolServerDiscoveryError: String?
    @Published var functions: [AppFunction] = []
    @Published var functionRuns: [AppFunctionRun] = []
    @Published var selectedFunctionRunID: UUID?
    @Published var isRunningFunction = false
    @Published var functionExecutionError: String?
    @Published var skills: [AppSkill] = []
    @Published var feedbacks: [AppFeedback] = []
    @Published var adminUsers: [AdminUser] = []
    @Published var adminGroups: [AdminGroup] = []
    @Published var channels: [AppChannel] = []
    @Published var automations: [AppAutomation] = []
    @Published var automationRuns: [AppAutomationRun] = []
    @Published var isAutomationSchedulerRunning = false
    @Published var isCalendarReminderSchedulerRunning = false
    @Published var calendars: [AppCalendar] = []
    @Published var calendarEvents: [AppCalendarEvent] = []
    @Published var focusedChatMessageID: UUID?
    @Published var selectedChannelID: UUID?
    @Published var selectedCalendarID: String?
    @Published var isShowingCalendar = false
    @Published var currentUserID: String = "local-user"
    @Published var sidebarSearchText: String = ""
    @Published var chatTranscriptSearchText: String = "" {
        didSet {
            refreshChatTranscriptSearchResults()
        }
    }
    @Published private(set) var chatTranscriptSearchResults: [ChatSearchResult] = []
    @Published var noteSearchText: String = ""
    @Published var focusedNoteID: UUID?
    @Published var skillSearchText: String = ""
    @Published var channelSearchText: String = ""
    @Published var automationSearchText: String = ""
    @Published var calendarSearchText: String = ""
    @Published var analyticsFilter: AnalyticsFilter = .all
    @Published var playgroundPrompt: String = ""
    @Published var playgroundSystemPrompt: String = ""
    @Published var playgroundOutput: String = ""
    @Published var playgroundModelID: String?
    @Published var playgroundError: String?
    @Published var isRunningPlayground = false
    @Published var playgroundTemperature: Double = 0.7
    @Published var playgroundTopP: Double = 0.9
    @Published var playgroundMaxTokens: Int = 512
    @Published var playgroundMode: PlaygroundMode = .chat
    @Published var playgroundNoteTitle: String = ""
    @Published var selectedPlaygroundNoteID: UUID?
    @Published var isPlaygroundComparisonEnabled = false
    @Published var playgroundComparisonModelID: String?
    @Published var playgroundComparisonOutput: String = ""
    @Published var playgroundComparisonError: String?
    @Published var playgroundImageModelID: String?
    @Published var playgroundImageSize: String = "1024x1024"
    @Published var playgroundImageQuality: String = "high"
    @Published var playgroundImageCount: Int = 1
    @Published var playgroundImageOutputs: [PlaygroundImageOutput] = []
    @Published var playgroundHistory: [PlaygroundHistoryItem] = []
    @Published var selectedPlaygroundHistoryID: UUID?
    @Published var imageGenerationPrompt: String = ""
    @Published var imageGenerationModelID: String?
    @Published var imageGenerationSize: String = "1024x1024"
    @Published var imageGenerationQuality: String = "high"
    @Published var imageGenerationCount: Int = 1
    @Published var generatedImages: [AppGeneratedImage] = []
    @Published var isGeneratingImage = false
    @Published var isEditingImage = false
    @Published var isVaryingImage = false
    @Published var imageEditPrompt: String = ""
    @Published var selectedImageForEditingID: UUID?
    @Published var imageEditMaskData: Data?
    @Published var imageEditMaskFileName: String?
    @Published var imageEditMaskContentType: String?
    @Published var imageGenerationError: String?
    @Published var isWebSearchEnabledForNextPrompt = false
    @Published var webSearchError: String?
    @Published var recentWebSearchResults: [WebSearchResult] = []
    @Published var recentWebSearchTelemetry: WebSearchTelemetry?
    @Published var audioTranscriptionModelID: String = "gpt-4o-mini-transcribe"
    @Published var audioTranscriptionPrompt: String = ""
    @Published var audioTranscriptionLanguage: String = ""
    @Published var pendingAudioFileName: String?
    @Published var pendingAudioContentType: String?
    @Published var audioTranscriptText: String = ""
    @Published var audioSpeechModelID: String = "gpt-4o-mini-tts"
    @Published var audioSpeechInput: String = ""
    @Published var audioSpeechVoice: String = "coral"
    @Published var audioSpeechInstructions: String = ""
    @Published var audioSpeechFormat: String = "mp3"
    @Published var synthesizedSpeechData: Data?
    @Published var synthesizedSpeechFileName: String?
    @Published var audioHistory: [AppAudioHistoryItem] = []
    @Published var selectedAudioHistoryItemID: UUID?
    @Published var audioPlaybackState: AppAudioPlaybackState = .stopped
    @Published var audioPlaybackTitle: String?
    @Published var audioPlaybackItemID: UUID?
    @Published var isTranscribingAudio = false
    @Published var isSynthesizingSpeech = false
    @Published var isRunningVoiceMode = false
    @Published var isRecordingAudio = false
    @Published var audioRecordingPermissionStatus: AudioRecordingPermissionStatus = .notDetermined
    @Published var audioError: String?
    @Published var codeExecutionLanguage: CodeExecutionLanguage = .shell
    @Published var codeExecutionInput: String = CodeExecutionLanguage.shell.defaultCode
    @Published var codeExecutionWorkingDirectory: String = ""
    @Published var codeExecutionTimeoutSeconds: Double = 10
    @Published var codeExecutionRuns: [AppCodeExecutionRun] = []
    @Published var selectedCodeExecutionRunID: UUID?
    @Published var isRunningCodeExecution = false
    @Published var codeExecutionError: String?
    @Published var terminalSessions: [AppTerminalSession] = []
    @Published var terminalCommands: [AppTerminalCommand] = []
    @Published var selectedTerminalSessionID: UUID?
    @Published var terminalCommandInput: String = ""
    @Published var terminalTimeoutSeconds: Double = 10
    @Published var isRunningTerminalCommand = false
    @Published var terminalError: String?
    @Published var auditEvents: [AppAuditEvent] = []
    @Published var newOllamaModelName: String = ""
    @Published var modelPullStatus: String?
    @Published var isPullingModel: Bool = false
    @Published var isDeletingModel: Bool = false
    @Published var isSending: Bool = false
    @Published var isCancellingSend: Bool = false
    @Published var errorMessage: String?

    private let storage: JSONStorageService
    private let folderStorage: JSONFolderStorageService
    private let fileStorage: JSONAppFileStorageService
    private let promptStorage: JSONPromptStorageService
    private let noteStorage: JSONNoteStorageService
    private let toolStorage: JSONToolStorageService
    private let toolRunStorage: JSONToolRunStorageService
    private let toolExecutor: any LocalToolExecuting
    private let toolServerStorage: JSONToolServerStorageService
    private let toolServerChecker: any ToolServerChecking
    private let toolServerRunStorage: JSONToolServerRunStorageService
    private let toolServerInvoker: any ToolServerInvoking
    private let toolServerDiscoverer: any ToolServerToolDiscovering
    private let toolServerToolCaller: any ToolServerToolCalling
    private let functionStorage: JSONFunctionStorageService
    private let functionRunStorage: JSONFunctionRunStorageService
    private let functionExecutor: any LocalFunctionExecuting
    private let skillStorage: JSONSkillStorageService
    private let feedbackStorage: JSONFeedbackStorageService
    private let adminDirectoryStorage: JSONAdminDirectoryStorageService
    private let channelStorage: JSONChannelStorageService
    private let automationStorage: JSONAutomationStorageService
    private let automationRunStorage: JSONAutomationRunStorageService
    private let calendarStorage: JSONCalendarStorageService
    private let settingsStore: SettingsStore
    private let secretStore: SecretStoring
    private let providerOverride: (any ChatProvider)?
    private let exportService: ChatExportService
    private let shareService: any ChatSharing
    private let chatSearchService = ChatSearchService()
    private let knowledgeService: KnowledgeService
    private let fileExportService: FileExportService
    private let promptExportService: PromptExportService
    private let promptVariableResolver: PromptVariableResolver
    private let noteExportService: NoteExportService
    private let toolExportService: ToolExportService
    private let toolServerExportService: ToolServerExportService
    private let toolArgumentTemplateService = ToolArgumentTemplateService()
    private let functionExportService: FunctionExportService
    private let skillExportService: SkillExportService
    private let feedbackExportService: FeedbackExportService
    private let adminDirectoryExportService: AdminDirectoryExportService
    private let feedbackEvaluationService: FeedbackEvaluationService
    private let analyticsService: AnalyticsService
    private let analyticsExportService: AnalyticsExportService
    private let playgroundExportService: PlaygroundExportService
    private let generatedImageExportService: GeneratedImageExportService
    private let audioHistoryExportService: AudioHistoryExportService
    private let webSearchService: any WebSearching
    private let playgroundHistoryStorage: JSONPlaygroundHistoryStorageService
    private let generatedImageStorage: JSONGeneratedImageStorageService
    private let codeExecutionStorage: JSONCodeExecutionStorageService
    private let terminalStorage: JSONTerminalSessionStorageService
    private let audioHistoryStorage: JSONAudioHistoryStorageService
    private let audioPlayer: any AudioPlaybackControlling
    private let audioRecorder: any AudioRecordingControlling
    private let auditLogStorage: JSONAuditLogStorageService
    private let auditLogExportService: AuditLogExportService
    private let codeExecutor: any CodeExecuting
    private let channelExportService: ChannelExportService
    private let automationExportService: AutomationExportService
    private let automationScheduleService: AutomationScheduleService
    private let calendarExportService: CalendarExportService
    private let calendarReminderNotificationService: CalendarReminderNotificationService
    private let calendarReminderDeliverer: any CalendarReminderDelivering
    private let workspaceBackupService: WorkspaceBackupService
    private var activeSendID: UUID?
    private var cancelledSendIDs: Set<UUID> = []
    private var cancelledAssistantBranchIDs: Set<UUID> = []
    private var activeAssistantBranchTasks: [UUID: Task<Void, Never>] = [:]
    private var pendingAudioData: Data?
    private var automationSchedulerTask: Task<Void, Never>?
    private var calendarReminderSchedulerTask: Task<Void, Never>?
    private var deliveredCalendarReminderIDs: Set<String> = []

    init(
        storage: JSONStorageService = JSONStorageService(),
        folderStorage: JSONFolderStorageService = JSONFolderStorageService(),
        fileStorage: JSONAppFileStorageService = JSONAppFileStorageService(),
        settingsStore: SettingsStore = SettingsStore(),
        secretStore: SecretStoring = KeychainSecretStore(),
        providerOverride: (any ChatProvider)? = nil,
        exportService: ChatExportService = ChatExportService(),
        shareService: (any ChatSharing)? = nil,
        knowledgeService: KnowledgeService = KnowledgeService(),
        fileExportService: FileExportService = FileExportService(),
        promptExportService: PromptExportService = PromptExportService(),
        promptVariableResolver: PromptVariableResolver = PromptVariableResolver(),
        noteExportService: NoteExportService = NoteExportService(),
        toolExportService: ToolExportService = ToolExportService(),
        toolServerExportService: ToolServerExportService = ToolServerExportService(),
        functionExportService: FunctionExportService = FunctionExportService(),
        skillExportService: SkillExportService = SkillExportService(),
        feedbackExportService: FeedbackExportService = FeedbackExportService(),
        adminDirectoryExportService: AdminDirectoryExportService = AdminDirectoryExportService(),
        feedbackEvaluationService: FeedbackEvaluationService = FeedbackEvaluationService(),
        analyticsService: AnalyticsService = AnalyticsService(),
        analyticsExportService: AnalyticsExportService = AnalyticsExportService(),
        playgroundExportService: PlaygroundExportService = PlaygroundExportService(),
        generatedImageExportService: GeneratedImageExportService = GeneratedImageExportService(),
        audioHistoryExportService: AudioHistoryExportService = AudioHistoryExportService(),
        webSearchService: (any WebSearching)? = nil,
        playgroundHistoryStorage: JSONPlaygroundHistoryStorageService = JSONPlaygroundHistoryStorageService(),
        generatedImageStorage: JSONGeneratedImageStorageService = JSONGeneratedImageStorageService(),
        codeExecutionStorage: JSONCodeExecutionStorageService = JSONCodeExecutionStorageService(),
        terminalStorage: JSONTerminalSessionStorageService = JSONTerminalSessionStorageService(),
        audioHistoryStorage: JSONAudioHistoryStorageService = JSONAudioHistoryStorageService(),
        audioPlayer: any AudioPlaybackControlling = AVAudioPlaybackController(),
        audioRecorder: any AudioRecordingControlling = AVAudioRecordingController(),
        auditLogStorage: JSONAuditLogStorageService = JSONAuditLogStorageService(),
        auditLogExportService: AuditLogExportService = AuditLogExportService(),
        codeExecutor: any CodeExecuting = CodeExecutionService(),
        channelExportService: ChannelExportService = ChannelExportService(),
        automationExportService: AutomationExportService = AutomationExportService(),
        automationScheduleService: AutomationScheduleService = AutomationScheduleService(),
        calendarExportService: CalendarExportService = CalendarExportService(),
        calendarReminderNotificationService: CalendarReminderNotificationService = CalendarReminderNotificationService(),
        calendarReminderDeliverer: any CalendarReminderDelivering = UserNotificationCalendarReminderDeliverer(),
        workspaceBackupService: WorkspaceBackupService = WorkspaceBackupService(),
        promptStorage: JSONPromptStorageService = JSONPromptStorageService(),
        noteStorage: JSONNoteStorageService = JSONNoteStorageService(),
        toolStorage: JSONToolStorageService = JSONToolStorageService(),
        toolRunStorage: JSONToolRunStorageService = JSONToolRunStorageService(),
        toolExecutor: any LocalToolExecuting = LocalToolExecutionService(),
        toolServerStorage: JSONToolServerStorageService = JSONToolServerStorageService(),
        toolServerChecker: any ToolServerChecking = ToolServerCheckService(),
        toolServerRunStorage: JSONToolServerRunStorageService = JSONToolServerRunStorageService(),
        toolServerInvoker: any ToolServerInvoking = ToolServerInvocationService(),
        toolServerDiscoverer: any ToolServerToolDiscovering = ToolServerMCPDiscoveryService(),
        toolServerToolCaller: any ToolServerToolCalling = ToolServerMCPDiscoveryService(),
        functionStorage: JSONFunctionStorageService = JSONFunctionStorageService(),
        functionRunStorage: JSONFunctionRunStorageService = JSONFunctionRunStorageService(),
        functionExecutor: any LocalFunctionExecuting = LocalFunctionExecutionService(),
        skillStorage: JSONSkillStorageService = JSONSkillStorageService(),
        feedbackStorage: JSONFeedbackStorageService = JSONFeedbackStorageService(),
        adminDirectoryStorage: JSONAdminDirectoryStorageService = JSONAdminDirectoryStorageService(),
        channelStorage: JSONChannelStorageService = JSONChannelStorageService(),
        automationStorage: JSONAutomationStorageService = JSONAutomationStorageService(),
        automationRunStorage: JSONAutomationRunStorageService = JSONAutomationRunStorageService(),
        calendarStorage: JSONCalendarStorageService = JSONCalendarStorageService()
    ) {
        self.storage = storage
        self.folderStorage = folderStorage
        self.fileStorage = fileStorage
        self.promptStorage = promptStorage
        self.noteStorage = noteStorage
        self.toolStorage = toolStorage
        self.toolRunStorage = toolRunStorage
        self.toolExecutor = toolExecutor
        self.toolServerStorage = toolServerStorage
        self.toolServerChecker = toolServerChecker
        self.toolServerRunStorage = toolServerRunStorage
        self.toolServerInvoker = toolServerInvoker
        self.toolServerDiscoverer = toolServerDiscoverer
        self.toolServerToolCaller = toolServerToolCaller
        self.functionStorage = functionStorage
        self.functionRunStorage = functionRunStorage
        self.functionExecutor = functionExecutor
        self.skillStorage = skillStorage
        self.feedbackStorage = feedbackStorage
        self.adminDirectoryStorage = adminDirectoryStorage
        self.channelStorage = channelStorage
        self.automationStorage = automationStorage
        self.automationRunStorage = automationRunStorage
        self.calendarStorage = calendarStorage
        self.settingsStore = settingsStore
        self.secretStore = secretStore
        self.providerOverride = providerOverride
        self.exportService = exportService
        self.shareService = shareService ?? ChatShareService()
        self.knowledgeService = knowledgeService
        self.fileExportService = fileExportService
        self.promptExportService = promptExportService
        self.promptVariableResolver = promptVariableResolver
        self.noteExportService = noteExportService
        self.toolExportService = toolExportService
        self.toolServerExportService = toolServerExportService
        self.functionExportService = functionExportService
        self.skillExportService = skillExportService
        self.feedbackExportService = feedbackExportService
        self.adminDirectoryExportService = adminDirectoryExportService
        self.feedbackEvaluationService = feedbackEvaluationService
        self.analyticsService = analyticsService
        self.analyticsExportService = analyticsExportService
        self.playgroundExportService = playgroundExportService
        self.generatedImageExportService = generatedImageExportService
        self.audioHistoryExportService = audioHistoryExportService
        self.webSearchService = webSearchService ?? WebSearchService(secretStore: secretStore)
        self.playgroundHistoryStorage = playgroundHistoryStorage
        self.generatedImageStorage = generatedImageStorage
        self.codeExecutionStorage = codeExecutionStorage
        self.terminalStorage = terminalStorage
        self.audioHistoryStorage = audioHistoryStorage
        self.audioPlayer = audioPlayer
        self.audioRecorder = audioRecorder
        self.auditLogStorage = auditLogStorage
        self.auditLogExportService = auditLogExportService
        self.codeExecutor = codeExecutor
        self.channelExportService = channelExportService
        self.automationExportService = automationExportService
        self.automationScheduleService = automationScheduleService
        self.calendarExportService = calendarExportService
        self.calendarReminderNotificationService = calendarReminderNotificationService
        self.calendarReminderDeliverer = calendarReminderDeliverer
        self.workspaceBackupService = workspaceBackupService
    }

    var selectedThread: ChatThread? {
        guard let selectedThreadID else {
            return nil
        }
        return threads.first { $0.id == selectedThreadID }
    }

    var streamingAssistantBranchCount: Int {
        selectedThread?.messages.filter { $0.role == .assistant && $0.isStreaming }.count ?? 0
    }

    var chatGenerationProgressText: String? {
        let count = streamingAssistantBranchCount
        guard count > 0 else {
            return nil
        }
        return count == 1 ? "1 response generating" : "\(count) responses generating"
    }

    var selectedModelID: String? {
        settings.selectedModelID ?? settings.selectedModelIDs.first ?? models.first?.id
    }

    var selectedModelIDs: [String] {
        if !settings.selectedModelIDs.isEmpty {
            return settings.selectedModelIDs
        }
        if let selectedModelID = settings.selectedModelID {
            return [selectedModelID]
        }
        return models.first.map { [$0.id] } ?? []
    }

    var selectedEmbeddingModelID: String? {
        settings.embeddingModelID ?? embeddingModelCandidates.first?.id ?? selectedModelID
    }

    var activeProvider: ProviderConfiguration {
        settings.activeProvider
    }

    var openAICompatibleProvider: ProviderConfiguration? {
        settings.providers.first { $0.kind == .openAICompatible }
    }

    var modelEvaluationSummaries: [ModelEvaluationSummary] {
        feedbackEvaluationService.summaries(from: feedbacks)
    }

    func filteredFeedbacks(query: String) -> [AppFeedback] {
        FeedbackAdminFilter.filteredFeedbacks(feedbacks, query: query)
    }

    var analyticsSummary: AnalyticsSummary {
        analyticsService.summary(
            threads: threads,
            feedbacks: feedbacks,
            knowledgeCollections: knowledgeCollections,
            knowledgeDocuments: knowledgeDocuments,
            channels: channels,
            notes: notes,
            automations: automations,
            calendars: calendars,
            calendarEvents: calendarEvents,
            adminGroups: adminGroups,
            filter: analyticsFilter
        )
    }

    var webSearchNetworkHistorySummary: WebSearchNetworkHistorySummary {
        WebSearchNetworkHistorySummary(events: auditEvents)
    }

    func analyticsModelChats(modelID: String) -> [AnalyticsModelChat] {
        analyticsService.modelChats(
            modelID: modelID,
            threads: threads,
            adminGroups: adminGroups,
            filter: analyticsFilter
        )
    }

    func setAnalyticsUserFilter(_ userID: String?) {
        analyticsFilter = AnalyticsFilter(
            userIDs: userID.map { [$0] } ?? [],
            groupIDs: Array(analyticsFilter.groupIDs)
        )
    }

    func setAnalyticsGroupFilter(_ groupID: String?) {
        analyticsFilter = AnalyticsFilter(
            userIDs: Array(analyticsFilter.userIDs),
            groupIDs: groupID.map { [$0] } ?? []
        )
    }

    func clearAnalyticsFilter() {
        analyticsFilter = .all
    }

    var selectedChannel: AppChannel? {
        guard let selectedChannelID else {
            return nil
        }
        return channels.first { $0.id == selectedChannelID }
    }

    var canManageOllamaModels: Bool {
        activeProviderCapabilities.supportsModelManagement
    }

    var selectedModel: ProviderModel? {
        guard let selectedModelID else {
            return nil
        }
        return models.first { $0.id == selectedModelID }
    }

    var canDeleteSelectedOllamaModel: Bool {
        guard canManageOllamaModels, selectedModelID?.isEmpty == false else {
            return false
        }
        if selectedModel?.provider == .localFunction {
            return false
        }
        return selectedModel?.provider == .ollama || activeProvider.kind == .ollama
    }

    var activeActionFunctions: [AppFunction] {
        guard isFeatureEnabled(.functions) else {
            return []
        }

        return functions
            .filter { $0.kind == .action && $0.isActive && function($0, defines: "action") }
            .sorted { lhs, rhs in
                if lhs.isGlobal != rhs.isGlobal {
                    return lhs.isGlobal && !rhs.isGlobal
                }
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
    }

    var activeProviderCapabilities: ProviderCapabilities {
        providerOverride?.capabilities ?? activeProvider.capabilities
    }

    var canChat: Bool {
        activeProviderCapabilities.supportsChat
    }

    var canComplete: Bool {
        activeProviderCapabilities.supportsCompletions
    }

    var canGenerateImages: Bool {
        activeProviderCapabilities.supportsImageGeneration
    }

    var canEditImages: Bool {
        activeProviderCapabilities.supportsImageEditing
    }

    var canVaryImages: Bool {
        activeProviderCapabilities.supportsImageVariation
    }

    var canCreateEmbeddings: Bool {
        activeProviderCapabilities.supportsEmbeddings
    }

    var embeddingModelCandidates: [ProviderModel] {
        guard canCreateEmbeddings else {
            return []
        }
        let providerModels = models.filter { $0.provider != .localFunction }
        return providerModels.filter { $0.capabilityMetadata.supportsEmbeddings }
    }

    var canTranscribeAudio: Bool {
        activeProviderCapabilities.supportsAudioTranscription
    }

    var canSynthesizeSpeech: Bool {
        activeProviderCapabilities.supportsSpeechSynthesis
    }

    var canRunVoiceMode: Bool {
        isFeatureEnabled(.voiceMode)
            && isFeatureEnabled(.audio)
            && currentUserCanTranscribeAudio
            && currentUserCanSynthesizeSpeech
            && canTranscribeAudio
            && canChat
            && canSynthesizeSpeech
            && selectedModelIDs.first != nil
            && pendingAudioFileName != nil
            && !isRunningVoiceMode
            && !isRecordingAudio
            && !isTranscribingAudio
            && !isSynthesizingSpeech
            && !isSending
    }

    var audioTranscriptionModels: [ProviderModel] {
        guard canTranscribeAudio else {
            return []
        }
        return models.filter { $0.capabilityMetadata.supportsAudioTranscription }
    }

    var audioSpeechModels: [ProviderModel] {
        guard canSynthesizeSpeech else {
            return []
        }
        return models.filter { $0.capabilityMetadata.supportsSpeechSynthesis }
    }

    var openAIAccountAccessPolicy: OpenAIAccountAccessPolicy {
        .current
    }

    var visibleCalendars: [AppCalendar] {
        var result = calendars.filter { currentUserCanAccessCalendar($0) }
        if isFeatureEnabled(.automations),
           !result.contains(where: { $0.id == AppCalendar.scheduledTasksCalendarID }) {
            result.append(AppCalendar.scheduledTasks())
        }
        return sortedCalendars(result)
    }

    func calendarMonthGrid(containing date: Date) -> CalendarMonthGrid {
        let sourceEvents = filteredCalendarSourceEvents()
        let visibleEvents = selectedCalendarID.map { selectedCalendarID in
            sourceEvents.filter { $0.calendarID == selectedCalendarID }
        } ?? sourceEvents
        return CalendarMonthGridService().monthGrid(
            containing: date,
            events: visibleEvents
        )
    }

    func calendarWeekGrid(containing date: Date) -> CalendarWeekGrid {
        let sourceEvents = filteredCalendarSourceEvents()
        let visibleEvents = selectedCalendarID.map { selectedCalendarID in
            sourceEvents.filter { $0.calendarID == selectedCalendarID }
        } ?? sourceEvents
        return CalendarWeekGridService().weekGrid(
            containing: date,
            events: visibleEvents
        )
    }

    func calendarDaySchedule(containing date: Date) -> CalendarDaySchedule {
        let sourceEvents = filteredCalendarSourceEvents()
        let visibleEvents = selectedCalendarID.map { selectedCalendarID in
            sourceEvents.filter { $0.calendarID == selectedCalendarID }
        } ?? sourceEvents
        return CalendarDayScheduleService().daySchedule(
            containing: date,
            events: visibleEvents
        )
    }

    func exportWorkspaceBackupJSONData() async throws -> Data {
        let backup = workspaceBackupService.backup(
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
            adminDirectory: AdminDirectorySnapshot(users: adminUsers, groups: adminGroups),
            channels: channels,
            automations: automations,
            automationRuns: automationRuns,
            calendar: CalendarSnapshot(calendars: calendars, events: calendarEvents),
            playgroundHistory: playgroundHistory,
            generatedImages: generatedImages,
            codeExecutionRuns: codeExecutionRuns,
            terminalSessions: terminalSessions,
            terminalCommands: terminalCommands,
            audioHistory: audioHistory,
            auditEvents: auditEvents,
            knowledge: try await knowledgeService.loadSnapshot()
        )
        return try workspaceBackupService.jsonData(for: backup)
    }

    func exportWorkspaceBackupJSONDataForUserAction() async throws -> Data {
        let data = try await exportWorkspaceBackupJSONData()
        let backup = try workspaceBackupService.backup(fromJSONData: data)
        await recordAuditEvent(
            action: .workspaceBackupExported,
            outcome: .succeeded,
            summary: "Exported workspace backup",
            metadata: workspaceBackupAuditMetadata(prefix: "exported", backup: backup)
        )
        return data
    }

    func importWorkspaceBackupJSONData(_ data: Data) async throws {
        let backup = try workspaceBackupService.backup(fromJSONData: data)
        try await replaceWorkspace(with: backup)
    }

    func importWorkspaceBackupJSONDataForUserAction(_ data: Data) async throws {
        let backup = try workspaceBackupService.backup(fromJSONData: data)
        try await replaceWorkspace(with: backup)
        await recordAuditEvent(
            action: .workspaceBackupImported,
            outcome: .succeeded,
            summary: "Imported workspace backup",
            metadata: workspaceBackupAuditMetadata(prefix: "imported", backup: backup)
        )
    }

    func exportWorkspaceBackupJSONWithSavePanel() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "open-webui-native-workspace-backup.json"
        panel.canCreateDirectories = true
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else {
                return
            }
            Task { @MainActor in
                do {
                    let data = try await self?.exportWorkspaceBackupJSONDataForUserAction()
                    try data?.write(to: url, options: [.atomic])
                } catch {
                    self?.errorMessage = error.localizedDescription
                }
            }
        }
    }

    func importWorkspaceBackupJSON(from url: URL) async {
        let didStartAccessing = url.startAccessingSecurityScopedResource()
        defer {
            if didStartAccessing {
                url.stopAccessingSecurityScopedResource()
            }
        }

        do {
            let data = try Data(contentsOf: url)
            try await importWorkspaceBackupJSONDataForUserAction(data)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func importWorkspaceBackupJSONWithOpenPanel() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else {
                return
            }
            Task { @MainActor in
                await self?.importWorkspaceBackupJSON(from: url)
            }
        }
    }

    func isFeatureEnabled(_ feature: AppFeatureToggle) -> Bool {
        settings.featureToggles.isEnabled(feature)
    }

    func setFeatureToggle(_ feature: AppFeatureToggle, isEnabled: Bool) async {
        settings.featureToggles.set(feature, isEnabled: isEnabled)
        if feature == .webSearch, !isEnabled {
            isWebSearchEnabledForNextPrompt = false
            webSearchError = nil
            recentWebSearchResults = []
            recentWebSearchTelemetry = nil
        }
        if feature == .files, !isEnabled {
            isShowingFiles = false
        }
        if feature == .codeInterpreter, !isEnabled {
            isShowingCodeInterpreter = false
            codeExecutionError = nil
        }
        if feature == .terminalSessions, !isEnabled {
            isShowingTerminalSessions = false
            terminalError = nil
        }
        if feature == .channels, !isEnabled {
            selectedChannelID = nil
        }
        if feature == .automations, !isEnabled {
            stopAutomationScheduler()
        }
        if feature == .calendar, !isEnabled {
            stopCalendarReminderScheduler()
        }
        do {
            try await settingsStore.save(settings)
            await recordAuditEvent(
                action: .featureToggleUpdated,
                outcome: .succeeded,
                summary: "\(isEnabled ? "Enabled" : "Disabled") \(feature.label)",
                metadata: [
                    "feature": feature.rawValue,
                    "enabled": String(isEnabled)
                ]
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func updateWebSearchSettings(
        _ webSearch: WebSearchSettings,
        braveAPIKey: String = "",
        tavilyAPIKey: String = ""
    ) async {
        let trimmedBraveAPIKey = braveAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedTavilyAPIKey = tavilyAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        var updatedWebSearch = webSearch
        if !trimmedBraveAPIKey.isEmpty {
            let secretID = webSearch.braveAPIKeySecretID ?? "web-search-brave-api-key"
            updatedWebSearch.braveAPIKeySecretID = secretID
        }
        if !trimmedTavilyAPIKey.isEmpty {
            let secretID = webSearch.tavilyAPIKeySecretID ?? "web-search-tavily-api-key"
            updatedWebSearch.tavilyAPIKeySecretID = secretID
        }

        settings.webSearch = updatedWebSearch
        do {
            if !trimmedBraveAPIKey.isEmpty, let secretID = updatedWebSearch.braveAPIKeySecretID {
                try await secretStore.saveSecret(trimmedBraveAPIKey, id: secretID)
            }
            if !trimmedTavilyAPIKey.isEmpty, let secretID = updatedWebSearch.tavilyAPIKeySecretID {
                try await secretStore.saveSecret(trimmedTavilyAPIKey, id: secretID)
            }
            try await settingsStore.save(settings)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func updateCodeExecutionSettings(_ codeExecution: CodeExecutionSettings) async {
        let allowedLanguages = codeExecution.allowedLanguages.isEmpty
            ? CodeExecutionLanguage.allCases
            : Array(Set(codeExecution.allowedLanguages)).sorted { $0.rawValue < $1.rawValue }
        let allowedRoots = codeExecution.allowedWorkingDirectoryRoots
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let allowedExecutableNames = codeExecution.allowedExecutableNames
            .map { normalizedExecutableName($0) }
            .filter { !$0.isEmpty }
        let deniedExecutableNames = codeExecution.deniedExecutableNames
            .map { normalizedExecutableName($0) }
            .filter { !$0.isEmpty }
        settings.codeExecution = CodeExecutionSettings(
            allowedLanguages: allowedLanguages,
            allowedWorkingDirectoryRoots: allowedRoots.isEmpty
                ? CodeExecutionSettings.defaultAllowedWorkingDirectoryRoots()
                : allowedRoots,
            allowedExecutableNames: Array(Set(allowedExecutableNames)).sorted(),
            deniedExecutableNames: Array(Set(deniedExecutableNames)).sorted(),
            maxTimeoutSeconds: min(max(codeExecution.maxTimeoutSeconds, 0.1), 120),
            maxCapturedOutputBytes: max(codeExecution.maxCapturedOutputBytes, 1)
        )
        codeExecutionTimeoutSeconds = min(codeExecutionTimeoutSeconds, settings.codeExecution.maxTimeoutSeconds)
        do {
            try await settingsStore.save(settings)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func load() async {
        do {
            settings = try await settingsStore.load()
            folders = try await folderStorage.loadFolders()
            files = try await fileStorage.loadFiles()
            prompts = try await promptStorage.loadPrompts()
            notes = try await noteStorage.loadNotes()
            tools = try await toolStorage.loadTools()
            toolRuns = try await toolRunStorage.loadRuns()
            toolServers = try await toolServerStorage.loadServers()
            resetToolServerStatuses()
            resetToolServerDiscoveryState()
            toolServerRuns = try await toolServerRunStorage.loadRuns()
            functions = try await functionStorage.loadFunctions()
            functionRuns = try await functionRunStorage.loadRuns()
            skills = try await skillStorage.loadSkills()
            feedbacks = try await feedbackStorage.loadFeedbacks()
            let adminSnapshot = try await adminDirectoryStorage.loadSnapshot()
            adminUsers = adminSnapshot.users
            adminGroups = adminSnapshot.groups
            channels = try await channelStorage.loadChannels()
            automations = try await automationStorage.loadAutomations()
            automationRuns = try await automationRunStorage.loadRuns()
            playgroundHistory = try await playgroundHistoryStorage.loadHistory()
            generatedImages = try await generatedImageStorage.loadImages()
            codeExecutionRuns = try await codeExecutionStorage.loadRuns()
            terminalSessions = try await terminalStorage.loadSessions()
            terminalCommands = try await terminalStorage.loadCommands()
            audioHistory = try await audioHistoryStorage.loadHistory()
            auditEvents = try await auditLogStorage.loadEvents()
            var calendarSnapshot = try await calendarStorage.loadSnapshot()
            if calendarSnapshot.calendars.isEmpty {
                calendarSnapshot.calendars = [AppCalendar.defaultPersonal()]
                try await calendarStorage.saveSnapshot(calendarSnapshot)
            }
            calendars = calendarSnapshot.calendars
            calendarEvents = calendarSnapshot.events
            selectedCalendarID = calendars.first(where: \.isDefault)?.id ?? calendars.first?.id
            sortNotes()
            sortTools()
            sortToolRuns()
            sortToolServers()
            sortToolServerRuns()
            sortFunctions()
            sortFunctionRuns()
            sortSkills()
            sortFeedbacks()
            sortAdminDirectory()
            sortChannels()
            sortAutomations()
            sortAutomationRuns()
            sortCodeExecutionRuns()
            sortTerminalSessions()
            sortTerminalCommands()
            sortAudioHistory()
            sortCalendars()
            sortCalendarEvents()
            threads = try await storage.loadThreads()
            sortThreads()
            try await refreshKnowledgeState()
            selectedThreadID = firstVisibleThreadID()
            await refreshModels()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func refreshModels() async {
        providerStatus = .checking
        do {
            let provider = try makeActiveProvider()
            let fetchedModels = try await provider.listModels()
            models = await modelsIncludingActivePipeFunctions(fetchedModels)
            updateAudioModelDefaults(from: fetchedModels)
            let availableIDs = Set(models.map(\.id))
            let previousSelectedModelID = settings.selectedModelID
            let previousSelectedModelIDs = settings.selectedModelIDs
            let previousEmbeddingModelID = settings.embeddingModelID
            settings.selectedModelIDs = settings.selectedModelIDs.filter { availableIDs.contains($0) }
            if let selectedModelID = settings.selectedModelID, !availableIDs.contains(selectedModelID) {
                settings.selectedModelID = settings.selectedModelIDs.first
            }
            let embeddingCandidateIDs = Set(embeddingModelCandidates.map(\.id))
            if let embeddingModelID = settings.embeddingModelID,
               !availableIDs.contains(embeddingModelID)
                || (!embeddingCandidateIDs.isEmpty && !embeddingCandidateIDs.contains(embeddingModelID)) {
                settings.embeddingModelID = nil
            }
            if settings.selectedModelID == nil || settings.selectedModelIDs.isEmpty {
                settings.selectedModelID = models.first?.id
                settings.selectedModelIDs = settings.selectedModelID.map { [$0] } ?? []
            }
            if previousSelectedModelID != settings.selectedModelID
                || previousSelectedModelIDs != settings.selectedModelIDs
                || previousEmbeddingModelID != settings.embeddingModelID {
                try await settingsStore.save(settings)
            }
            providerStatus = .available("\(provider.configuration.name) connected (\(models.count) models)")
        } catch {
            models = await modelsIncludingActivePipeFunctions([])
            providerStatus = .unavailable(error.localizedDescription)
        }
    }

    func checkActiveProviderHealth() async {
        providerStatus = .checking
        do {
            let provider = try makeActiveProvider()
            providerStatus = await provider.healthCheck()
        } catch {
            providerStatus = .unavailable(error.localizedDescription)
        }
    }

    func selectProvider(_ providerID: UUID) async {
        guard settings.providers.contains(where: { $0.id == providerID && $0.isEnabled }) else {
            errorMessage = "Selected provider is not available."
            return
        }
        errorMessage = nil
        settings.activeProviderID = providerID
        settings.selectedModelID = nil
        settings.selectedModelIDs = []
        settings.embeddingModelID = nil
        do {
            try await settingsStore.save(settings)
            await refreshModels()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func selectModel(_ modelID: String?) async {
        settings.selectedModelID = modelID
        settings.selectedModelIDs = modelID.map { [$0] } ?? []
        do {
            try await settingsStore.save(settings)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func setModel(_ modelID: String, selected: Bool) async {
        var selectedIDs = settings.selectedModelIDs
        if selected {
            if !selectedIDs.contains(modelID) {
                selectedIDs.append(modelID)
            }
        } else {
            selectedIDs.removeAll { $0 == modelID }
        }

        settings.selectedModelIDs = selectedIDs
        settings.selectedModelID = selectedIDs.first
        do {
            try await settingsStore.save(settings)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func selectEmbeddingModel(_ modelID: String?) async {
        settings.embeddingModelID = modelID
        do {
            try await settingsStore.save(settings)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func pullOllamaModel() async {
        let modelName = newOllamaModelName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !modelName.isEmpty else {
            errorMessage = "Enter an Ollama model name to pull."
            return
        }
        guard canManageOllamaModels else {
            errorMessage = ProviderError.unsupportedModelManagement(activeProvider.name).localizedDescription
            return
        }

        isPullingModel = true
        modelPullStatus = "Starting pull..."
        errorMessage = nil

        do {
            let manager = try makeOllamaModelManager()
            for try await progress in manager.pullModel(named: modelName) {
                modelPullStatus = progress.status
            }
            newOllamaModelName = ""
            await refreshModels()
        } catch {
            errorMessage = error.localizedDescription
        }

        isPullingModel = false
    }

    func deleteSelectedOllamaModel() async {
        guard let modelID = selectedModelID, !modelID.isEmpty else {
            errorMessage = ProviderError.noModelSelected.localizedDescription
            return
        }
        guard canDeleteSelectedOllamaModel else {
            errorMessage = ProviderError.unsupportedModelManagement(activeProvider.name).localizedDescription
            return
        }

        isDeletingModel = true
        errorMessage = nil

        do {
            let manager = try makeOllamaModelManager()
            try await manager.deleteModel(named: modelID)
            await refreshModels()
        } catch {
            errorMessage = error.localizedDescription
        }

        isDeletingModel = false
    }

    func updateOllamaBaseURL(_ value: String) async {
        let trimmedBaseURL = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard Self.isValidProviderBaseURL(trimmedBaseURL) else {
            errorMessage = ProviderError.invalidBaseURL(trimmedBaseURL.isEmpty ? value : trimmedBaseURL).localizedDescription
            return
        }
        settings.ollamaBaseURL = trimmedBaseURL
        updateProvider(ProviderConfiguration.defaultOllama(baseURL: trimmedBaseURL))
        do {
            errorMessage = nil
            try await settingsStore.save(settings)
            await recordAuditEvent(
                action: .providerSettingsUpdated,
                outcome: .succeeded,
                summary: "Updated Ollama provider settings",
                metadata: [
                    "providerKind": ProviderKind.ollama.rawValue,
                    "providerName": "Ollama",
                    "baseURL": trimmedBaseURL
                ]
            )
            await refreshModels()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func saveOpenAICompatibleProvider(name: String, baseURL: String, apiKey: String, makeActive: Bool) async {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let providerName = trimmedName.isEmpty ? "OpenAI Compatible" : trimmedName
        let trimmedBaseURL = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard Self.isValidProviderBaseURL(trimmedBaseURL) else {
            errorMessage = ProviderError.invalidBaseURL(trimmedBaseURL.isEmpty ? baseURL : trimmedBaseURL).localizedDescription
            return
        }
        let existing = openAICompatibleProvider
        let providerID = existing?.id ?? UUID()
        let secretID = existing?.apiKeySecretID ?? "provider-\(providerID.uuidString)-api-key"

        var provider = ProviderConfiguration(
            id: providerID,
            name: providerName,
            kind: .openAICompatible,
            baseURL: trimmedBaseURL,
            apiKeySecretID: secretID
        )
        provider.isEnabled = true

        do {
            errorMessage = nil
            let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedKey.isEmpty {
                try await secretStore.saveSecret(trimmedKey, id: secretID)
            }
            updateProvider(provider)
            if makeActive {
                settings.activeProviderID = provider.id
                settings.selectedModelID = nil
                settings.selectedModelIDs = []
                settings.embeddingModelID = nil
            }
            try await settingsStore.save(settings)
            await recordAuditEvent(
                action: .providerSettingsUpdated,
                outcome: .succeeded,
                summary: "Saved OpenAI-compatible provider settings",
                metadata: [
                    "providerKind": ProviderKind.openAICompatible.rawValue,
                    "providerName": providerName,
                    "baseURL": trimmedBaseURL,
                    "apiKeyUpdated": String(!trimmedKey.isEmpty),
                    "madeActive": String(makeActive)
                ]
            )
            if makeActive {
                await refreshModels()
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func removeOpenAICompatibleProvider() async {
        guard let provider = openAICompatibleProvider else {
            return
        }

        do {
            if let secretID = provider.apiKeySecretID {
                try await secretStore.deleteSecret(id: secretID)
            }

            let wasActive = settings.activeProviderID == provider.id
            settings.providers.removeAll { $0.id == provider.id }
            if !settings.providers.contains(where: { $0.id == ProviderConfiguration.defaultOllamaID }) {
                settings.providers.insert(ProviderConfiguration.defaultOllama(baseURL: settings.ollamaBaseURL), at: 0)
            }

            if wasActive {
                settings.activeProviderID = ProviderConfiguration.defaultOllamaID
                settings.selectedModelID = nil
                settings.selectedModelIDs = []
                settings.embeddingModelID = nil
                models = []
                providerStatus = .unknown
            }

            try await settingsStore.save(settings)
            await recordAuditEvent(
                action: .providerSettingsUpdated,
                outcome: .succeeded,
                summary: "Removed OpenAI-compatible provider settings",
                metadata: [
                    "providerKind": ProviderKind.openAICompatible.rawValue,
                    "providerName": provider.name,
                    "baseURL": provider.baseURL,
                    "wasActive": String(wasActive)
                ]
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func createThread() {
        var thread = ChatThread(providerID: settings.activeProviderID, modelIDs: selectedModelIDs)
        thread.title = "New Chat"
        threads.insert(thread, at: 0)
        sortThreads()
        selectedThreadID = thread.id
        focusedChatMessageID = nil
        chatTranscriptSearchText = ""
        selectedChannelID = nil
        isShowingEvaluationDashboard = false
        isShowingAnalyticsDashboard = false
        isShowingPlayground = false
        isShowingFiles = false
        isShowingCalendar = false
        isShowingImageGeneration = false
        isShowingAudio = false
        isShowingCodeInterpreter = false
        isShowingTerminalSessions = false
        Task {
            try? await storage.save(thread)
        }
    }

    func createFolder(named name: String) async {
        guard requireFoldersFeatureEnabled() else {
            return
        }

        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            return
        }

        var folder = ChatFolder(name: trimmedName)
        folder.updatedAt = Date()

        do {
            try await folderStorage.save(folder)
            folders.append(folder)
            sortFolders()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func deleteFolder(_ folderID: UUID) async {
        guard requireFoldersFeatureEnabled() else {
            return
        }

        do {
            try await folderStorage.deleteFolder(id: folderID)
            folders.removeAll { $0.id == folderID }
            for index in threads.indices where threads[index].folderID == folderID {
                threads[index].folderID = nil
                threads[index].updatedAt = Date()
                try await storage.save(threads[index])
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func createPrompt(
        title: String,
        content: String,
        command: String? = nil,
        tags: [String] = [],
        allowedUserIDs: [String] = [],
        allowedGroupIDs: [String] = []
    ) async {
        guard requirePromptsFeatureEnabled() else {
            return
        }
        guard requirePromptWritePermission() else {
            return
        }
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedContent = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty, !trimmedContent.isEmpty else {
            return
        }

        let prompt = SavedPrompt(
            title: trimmedTitle,
            content: trimmedContent,
            command: command,
            tags: tags,
            allowedUserIDs: allowedUserIDs,
            allowedGroupIDs: allowedGroupIDs
        )

        do {
            try await promptStorage.save(prompt)
            prompts.append(prompt)
            sortPrompts()
            await recordAuditEvent(
                action: .promptCreated,
                outcome: .succeeded,
                summary: "Created prompt \(prompt.title)",
                metadata: promptAuditMetadata(for: prompt)
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func updatePrompt(
        _ promptID: UUID,
        title: String,
        content: String,
        command: String? = nil,
        tags: [String] = [],
        allowedUserIDs: [String]? = nil,
        allowedGroupIDs: [String]? = nil
    ) async {
        guard requirePromptsFeatureEnabled() else {
            return
        }
        guard requirePromptWritePermission() else {
            return
        }
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedContent = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty, !trimmedContent.isEmpty,
              let index = prompts.firstIndex(where: { $0.id == promptID }) else {
            return
        }
        let originalPrompt = prompts[index]
        let versionSnapshot = SavedPromptVersion(prompt: originalPrompt)

        prompts[index].versions.append(versionSnapshot)
        prompts[index].title = trimmedTitle
        prompts[index].content = trimmedContent
        prompts[index].command = SavedPrompt.normalizedCommand(command)
        prompts[index].tags = SavedPrompt.normalizedTags(tags)
        if let allowedUserIDs {
            prompts[index].allowedUserIDs = SavedPrompt.normalizedAccessIDs(allowedUserIDs)
        }
        if let allowedGroupIDs {
            prompts[index].allowedGroupIDs = SavedPrompt.normalizedAccessIDs(allowedGroupIDs)
        }
        prompts[index].updatedAt = Date()

        do {
            try await promptStorage.save(prompts[index])
            let updatedPrompt = prompts[index]
            sortPrompts()
            var metadata = promptAuditMetadata(for: updatedPrompt)
            metadata["fromTitle"] = originalPrompt.title
            await recordAuditEvent(
                action: .promptUpdated,
                outcome: .succeeded,
                summary: "Updated prompt \(updatedPrompt.title)",
                metadata: metadata
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func deletePrompt(_ promptID: UUID) async {
        guard requirePromptsFeatureEnabled() else {
            return
        }
        guard requirePromptWritePermission() else {
            return
        }
        let deletedPrompt = prompts.first { $0.id == promptID }
        do {
            try await promptStorage.deletePrompt(id: promptID)
            prompts.removeAll { $0.id == promptID }
            if let deletedPrompt {
                await recordAuditEvent(
                    action: .promptDeleted,
                    outcome: .succeeded,
                    summary: "Deleted prompt \(deletedPrompt.title)",
                    metadata: promptAuditMetadata(for: deletedPrompt)
                )
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func promptVariables(for promptID: UUID) -> [PromptVariable] {
        guard let prompt = prompts.first(where: { $0.id == promptID }) else {
            return []
        }
        return promptVariableResolver.variables(in: prompt.content)
    }

    func insertPrompt(_ promptID: UUID, variableValues: [String: String] = [:]) {
        guard requirePromptsFeatureEnabled() else {
            return
        }
        guard let prompt = prompts.first(where: { $0.id == promptID }) else {
            return
        }

        let resolvedContent: String
        do {
            resolvedContent = try promptVariableResolver.resolve(prompt.content, values: variableValues)
        } catch {
            errorMessage = error.localizedDescription
            return
        }

        let trimmedDraft = draftPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedDraft.isEmpty {
            draftPrompt = resolvedContent
        } else {
            draftPrompt = "\(trimmedDraft)\n\n\(resolvedContent)"
        }
    }

    func prompt(matchingCommand rawCommand: String) -> SavedPrompt? {
        guard isFeatureEnabled(.prompts) else {
            return nil
        }
        guard let command = SavedPrompt.normalizedCommand(rawCommand) else {
            return nil
        }
        return prompts.first { $0.command == command }
    }

    func exportPromptsJSONData() throws -> Data {
        try promptExportService.jsonData(for: prompts)
    }

    func exportPromptsOpenWebUIJSONData() throws -> Data {
        try promptExportService.openWebUIJSONData(for: prompts)
    }

    func exportPromptsJSONDataForUserAction() async throws -> Data {
        let exportedPrompts = prompts
        let data = try promptExportService.jsonData(for: exportedPrompts)
        await recordAuditEvent(
            action: .promptsExported,
            outcome: .succeeded,
            summary: "Exported prompt library",
            metadata: promptTransferAuditMetadata(prefix: "exported", prompts: exportedPrompts)
        )
        return data
    }

    func exportPromptsOpenWebUIJSONDataForUserAction() async throws -> Data {
        let exportedPrompts = prompts
        let data = try promptExportService.openWebUIJSONData(for: exportedPrompts)
        var metadata = promptTransferAuditMetadata(prefix: "exported", prompts: exportedPrompts)
        metadata["format"] = "open-webui"
        await recordAuditEvent(
            action: .promptsExported,
            outcome: .succeeded,
            summary: "Exported Open WebUI prompt records",
            metadata: metadata
        )
        return data
    }

    func exportPromptJSONData(_ promptID: UUID) throws -> Data? {
        guard let prompt = prompts.first(where: { $0.id == promptID }) else {
            return nil
        }
        return try promptExportService.jsonData(for: [prompt])
    }

    func sharePrompt(_ promptID: UUID) {
        guard requirePromptsFeatureEnabled() else {
            return
        }
        guard let prompt = prompts.first(where: { $0.id == promptID }) else {
            return
        }

        do {
            let data = try promptExportService.jsonData(for: [prompt])
            guard let json = String(data: data, encoding: .utf8) else {
                errorMessage = "The selected prompt could not be encoded for sharing."
                return
            }
            shareService.share(text: json, title: prompt.title)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func exportPromptsJSONWithSavePanel() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "open-webui-native-prompts.json"
        panel.canCreateDirectories = true
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else {
                return
            }
            Task { @MainActor in
                do {
                    let data = try await self?.exportPromptsJSONDataForUserAction()
                    try data?.write(to: url, options: [.atomic])
                } catch {
                    self?.errorMessage = error.localizedDescription
                }
            }
        }
    }

    func exportPromptsOpenWebUIJSONWithSavePanel() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "open-webui-prompts.json"
        panel.canCreateDirectories = true
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else {
                return
            }
            Task { @MainActor in
                do {
                    let data = try await self?.exportPromptsOpenWebUIJSONDataForUserAction()
                    try data?.write(to: url, options: [.atomic])
                } catch {
                    self?.errorMessage = error.localizedDescription
                }
            }
        }
    }

    func importPromptsJSONData(_ data: Data) async throws {
        guard requirePromptsFeatureEnabled() else {
            return
        }
        guard requirePromptWritePermission() else {
            return
        }
        let importedPrompts = try promptExportService.prompts(fromJSONData: data)
        try await importPrompts(importedPrompts)
    }

    func importPromptsJSONDataForUserAction(_ data: Data) async throws {
        guard requirePromptsFeatureEnabled() else {
            return
        }
        guard requirePromptWritePermission() else {
            return
        }
        let importedPrompts = try promptExportService.prompts(fromJSONData: data)
        try await importPrompts(importedPrompts)
        var metadata = promptTransferAuditMetadata(prefix: "imported", prompts: importedPrompts)
        metadata["totalPromptCount"] = String(prompts.count)
        await recordAuditEvent(
            action: .promptsImported,
            outcome: .succeeded,
            summary: "Imported prompt library",
            metadata: metadata
        )
    }

    private func importPrompts(_ importedPrompts: [SavedPrompt]) async throws {
        for prompt in importedPrompts {
            try await promptStorage.save(prompt)
            prompts.removeAll { $0.id == prompt.id }
            prompts.append(prompt)
        }
        sortPrompts()
    }

    private func promptTransferAuditMetadata(prefix: String, prompts: [SavedPrompt]) -> [String: String] {
        [
            "\(prefix)PromptCount": String(prompts.count),
            "\(prefix)CommandPromptCount": String(prompts.filter { $0.command != nil }.count),
            "\(prefix)TaggedPromptCount": String(prompts.filter { !$0.tags.isEmpty }.count)
        ]
    }

    func importPromptsJSON(from url: URL) async {
        guard requirePromptsFeatureEnabled() else {
            return
        }
        guard requirePromptWritePermission() else {
            return
        }

        let didStartAccessing = url.startAccessingSecurityScopedResource()
        defer {
            if didStartAccessing {
                url.stopAccessingSecurityScopedResource()
            }
        }

        do {
            let data = try Data(contentsOf: url)
            try await importPromptsJSONDataForUserAction(data)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func importPromptsJSONWithOpenPanel() {
        guard requirePromptsFeatureEnabled() else {
            return
        }
        guard requirePromptWritePermission() else {
            return
        }

        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.begin { [weak self] response in
            guard response == .OK else {
                return
            }
            let urls = panel.urls
            Task { @MainActor in
                for url in urls {
                    await self?.importPromptsJSON(from: url)
                }
            }
        }
    }

    func createTool(name: String, content: String, description: String?, valvesJSON: String? = nil) async {
        guard requireToolsFeatureEnabled() else {
            return
        }
        guard requireToolWritePermission() else {
            return
        }
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedContent = content.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedDescription = description?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty, !trimmedContent.isEmpty else {
            return
        }
        let valves: JSONValue?
        do {
            valves = try await validatedToolValves(
                from: valvesJSON,
                name: trimmedName,
                content: trimmedContent
            )
        } catch {
            errorMessage = error.localizedDescription
            return
        }
        errorMessage = nil

        let tool = AppTool(
            name: trimmedName,
            content: trimmedContent,
            description: trimmedDescription?.isEmpty == false ? trimmedDescription : nil,
            valves: valves
        )

        do {
            try await toolStorage.save(tool)
            tools.append(tool)
            sortTools()
            await recordAuditEvent(
                action: .toolCreated,
                outcome: .succeeded,
                summary: "Created tool \(tool.name)",
                metadata: toolAuditMetadata(for: tool)
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func updateTool(_ toolID: String, name: String, content: String, description: String?, valvesJSON: String? = nil) async {
        guard requireToolsFeatureEnabled() else {
            return
        }
        guard requireToolWritePermission() else {
            return
        }
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedContent = content.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedDescription = description?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty, !trimmedContent.isEmpty,
              let index = tools.firstIndex(where: { $0.id == toolID }) else {
            return
        }
        let valves: JSONValue?
        if let valvesJSON {
            do {
                valves = try await validatedToolValves(
                    from: valvesJSON,
                    name: trimmedName,
                    content: trimmedContent
                )
            } catch {
                errorMessage = error.localizedDescription
                return
            }
        } else {
            valves = tools[index].valves
        }
        errorMessage = nil
        let originalTool = tools[index]

        tools[index].name = trimmedName
        tools[index].content = trimmedContent
        tools[index].description = trimmedDescription?.isEmpty == false ? trimmedDescription : nil
        tools[index].valves = valves
        tools[index].updatedAt = Date()

        do {
            try await toolStorage.save(tools[index])
            let updatedTool = tools[index]
            sortTools()
            var metadata = toolAuditMetadata(for: updatedTool)
            metadata["fromName"] = originalTool.name
            await recordAuditEvent(
                action: .toolUpdated,
                outcome: .succeeded,
                summary: "Updated tool \(updatedTool.name)",
                metadata: metadata
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func deleteTool(_ toolID: String) async {
        guard requireToolsFeatureEnabled() else {
            return
        }
        guard requireToolWritePermission() else {
            return
        }
        let deletedTool = tools.first { $0.id == toolID }
        do {
            try await toolStorage.deleteTool(id: toolID)
            tools.removeAll { $0.id == toolID }
            if let deletedTool {
                await recordAuditEvent(
                    action: .toolDeleted,
                    outcome: .succeeded,
                    summary: "Deleted tool \(deletedTool.name)",
                    metadata: toolAuditMetadata(for: deletedTool)
                )
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func toolValvesTemplateJSON(name: String, content: String) async -> String? {
        await toolValvesSchemaDraft(name: name, content: content)?.templateJSON
    }

    func toolValvesSchemaDraft(name: String, content: String) async -> ValvesSchemaDraft? {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedContent = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedContent.isEmpty else {
            return nil
        }
        guard let schema = await toolValvesSchema(
            name: trimmedName.isEmpty ? "Draft tool" : trimmedName,
            content: trimmedContent
        ) else {
            errorMessage = "Tool does not define a Valves schema."
            return nil
        }
        do {
            errorMessage = nil
            return ValvesSchemaDraft(
                templateJSON: try toolArgumentTemplateService.jsonTemplate(forSchema: schema),
                fields: toolArgumentTemplateService.formFields(forSchema: schema)
            )
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    func exportToolsJSONData() throws -> Data {
        try toolExportService.jsonData(for: tools)
    }

    func exportToolsOpenWebUIJSONData() throws -> Data {
        try toolExportService.openWebUIJSONData(for: tools, userID: currentUserID)
    }

    func exportToolJSONData(_ toolID: String) throws -> Data? {
        guard let tool = tools.first(where: { $0.id == toolID }) else {
            return nil
        }
        return try toolExportService.jsonData(for: [tool])
    }

    func shareTool(_ toolID: String) {
        guard requireToolsFeatureEnabled() else {
            return
        }
        guard let tool = tools.first(where: { $0.id == toolID }) else {
            return
        }

        do {
            let data = try toolExportService.jsonData(for: [tool])
            guard let json = String(data: data, encoding: .utf8) else {
                errorMessage = "The selected tool could not be encoded for sharing."
                return
            }
            shareService.share(text: json, title: tool.name)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func exportToolsJSONWithSavePanel() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "open-webui-native-tools.json"
        panel.canCreateDirectories = true
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else {
                return
            }
            Task { @MainActor in
                do {
                    let data = try self?.exportToolsJSONData()
                    try data?.write(to: url, options: [.atomic])
                } catch {
                    self?.errorMessage = error.localizedDescription
                }
            }
        }
    }

    func exportToolsOpenWebUIJSONWithSavePanel() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "open-webui-tools.json"
        panel.canCreateDirectories = true
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else {
                return
            }
            Task { @MainActor in
                do {
                    let data = try self?.exportToolsOpenWebUIJSONData()
                    try data?.write(to: url, options: [.atomic])
                } catch {
                    self?.errorMessage = error.localizedDescription
                }
            }
        }
    }

    func importToolsJSONData(_ data: Data) async throws {
        guard requireToolsFeatureEnabled() else {
            return
        }
        guard requireToolWritePermission() else {
            return
        }
        let importedTools = try toolExportService.tools(fromJSONData: data)
        for tool in importedTools {
            try await toolStorage.save(tool)
            tools.removeAll { $0.id == tool.id }
            tools.append(tool)
        }
        sortTools()
    }

    func importToolsJSON(from url: URL) async {
        guard requireToolsFeatureEnabled() else {
            return
        }
        let didStartAccessing = url.startAccessingSecurityScopedResource()
        defer {
            if didStartAccessing {
                url.stopAccessingSecurityScopedResource()
            }
        }

        do {
            let data = try Data(contentsOf: url)
            try await importToolsJSONData(data)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func importToolsJSONWithOpenPanel() {
        guard requireToolsFeatureEnabled() else {
            return
        }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.begin { [weak self] response in
            guard response == .OK else {
                return
            }
            let urls = panel.urls
            Task { @MainActor in
                for url in urls {
                    await self?.importToolsJSON(from: url)
                }
            }
        }
    }

    func runTool(_ toolID: String, functionName: String? = nil, argumentsBody: String = "{}") async {
        guard let tool = tools.first(where: { $0.id == toolID }) else {
            toolExecutionError = "Tool not found."
            errorMessage = toolExecutionError
            return
        }
        guard requireToolsFeatureEnabled() else {
            toolExecutionError = toolsDisabledMessage
            return
        }
        guard requireToolExecutionPermission() else {
            return
        }

        let trimmedBody = argumentsBody.trimmingCharacters(in: .whitespacesAndNewlines)
        let payload = trimmedBody.isEmpty ? "{}" : trimmedBody
        guard let data = payload.data(using: .utf8),
              let arguments = try? JSONDecoder().decode(JSONValue.self, from: data),
              arguments.objectValue != nil else {
            toolExecutionError = "Tool arguments must be a JSON object."
            errorMessage = toolExecutionError
            return
        }

        let resolvedFunctionName = functionName?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfEmpty ?? defaultFunctionName(for: tool)
        guard let resolvedFunctionName else {
            toolExecutionError = "Select a tool function to run."
            errorMessage = toolExecutionError
            return
        }

        isRunningTool = true
        toolExecutionError = nil
        errorMessage = nil
        defer {
            isRunningTool = false
        }

        let run = await toolExecutor.invoke(
            LocalToolInvocationRequest(
                tool: tool,
                functionName: resolvedFunctionName,
                arguments: arguments,
                argumentsBody: payload,
                timeoutSeconds: min(max(codeExecutionTimeoutSeconds, 0.1), max(settings.codeExecution.maxTimeoutSeconds, 0.1))
            )
        )

        do {
            try await toolRunStorage.save(run)
            toolRuns.removeAll { $0.id == run.id }
            toolRuns.append(run)
            sortToolRuns()
            selectedToolRunID = run.id
            toolExecutionError = run.status == .succeeded
                ? nil
                : run.errorMessage ?? "Tool run failed."
            await recordAuditEvent(
                action: .toolInvoked,
                outcome: run.status == .succeeded ? .succeeded : .failed,
                summary: "\(run.toolName) tool \(run.functionName) \(run.status.rawValue)",
                metadata: [
                    "toolID": run.toolID,
                    "toolName": run.toolName,
                    "functionName": run.functionName,
                    "status": run.status.rawValue,
                    "runID": run.id.uuidString
                ]
            )
        } catch {
            toolExecutionError = error.localizedDescription
            errorMessage = error.localizedDescription
        }
    }

    func createToolServer(
        name: String,
        kind: AppToolServerKind,
        command: String,
        argumentsText: String,
        baseURL: String,
        environmentText: String,
        isEnabled: Bool
    ) async {
        guard requireToolServerWritePermission() else {
            return
        }
        guard let server = makeToolServer(
            id: UUID().uuidString,
            name: name,
            kind: kind,
            command: command,
            argumentsText: argumentsText,
            baseURL: baseURL,
            environmentText: environmentText,
            isEnabled: isEnabled,
            createdAt: Date(),
            updatedAt: Date()
        ) else {
            return
        }

        do {
            try await toolServerStorage.save(server)
            toolServers.append(server)
            toolServerStatuses[server.id] = .unknown
            toolServerDiscoveryStatuses[server.id] = .unknown
            toolServerTools[server.id] = []
            sortToolServers()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func updateToolServer(
        _ serverID: String,
        name: String,
        kind: AppToolServerKind,
        command: String,
        argumentsText: String,
        baseURL: String,
        environmentText: String,
        isEnabled: Bool
    ) async {
        guard requireToolServerWritePermission() else {
            return
        }
        guard let index = toolServers.firstIndex(where: { $0.id == serverID }),
              let server = makeToolServer(
                id: serverID,
                name: name,
                kind: kind,
                command: command,
                argumentsText: argumentsText,
                baseURL: baseURL,
                environmentText: environmentText,
                isEnabled: isEnabled,
                createdAt: toolServers[index].createdAt,
                updatedAt: Date()
              ) else {
            return
        }

        do {
            try await toolServerStorage.save(server)
            toolServers[index] = server
            toolServerStatuses[serverID] = .unknown
            toolServerDiscoveryStatuses[serverID] = .unknown
            toolServerTools[serverID] = []
            sortToolServers()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func deleteToolServer(_ serverID: String) async {
        guard requireToolServerWritePermission() else {
            return
        }
        do {
            try await toolServerStorage.deleteServer(id: serverID)
            toolServers.removeAll { $0.id == serverID }
            toolServerStatuses[serverID] = nil
            toolServerDiscoveryStatuses[serverID] = nil
            toolServerTools[serverID] = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func checkToolServer(_ serverID: String) async {
        guard let server = toolServers.first(where: { $0.id == serverID }) else {
            toolServerStatuses[serverID] = .unavailable("Tool server not found.")
            return
        }

        guard requireDirectToolServersFeatureEnabled() else {
            toolServerStatuses[serverID] = .unavailable(directToolServersDisabledMessage)
            return
        }

        toolServerStatuses[serverID] = .checking
        let result = await toolServerChecker.check(server)
        guard toolServers.contains(where: { $0.id == serverID }) else {
            return
        }
        toolServerStatuses[serverID] = result.status
    }

    func discoverToolServerTools(_ serverID: String) async {
        guard let server = toolServers.first(where: { $0.id == serverID }) else {
            toolServerDiscoveryError = "Tool server not found."
            errorMessage = toolServerDiscoveryError
            toolServerDiscoveryStatuses[serverID] = .unavailable("Tool server not found.")
            return
        }

        guard requireDirectToolServersFeatureEnabled() else {
            toolServerDiscoveryError = directToolServersDisabledMessage
            toolServerDiscoveryStatuses[serverID] = .unavailable(directToolServersDisabledMessage)
            return
        }

        guard server.isEnabled else {
            toolServerDiscoveryError = "Tool server is disabled."
            errorMessage = toolServerDiscoveryError
            toolServerDiscoveryStatuses[serverID] = .unavailable("Tool server is disabled.")
            return
        }

        isDiscoveringToolServerTools = true
        toolServerDiscoveryError = nil
        errorMessage = nil
        toolServerDiscoveryStatuses[serverID] = .checking
        defer {
            isDiscoveringToolServerTools = false
        }

        let result = await toolServerDiscoverer.discoverTools(for: server)
        guard toolServers.contains(where: { $0.id == serverID }) else {
            return
        }

        toolServerTools[serverID] = result.tools
        toolServerDiscoveryStatuses[serverID] = result.status
        if case .unavailable(let message) = result.status {
            toolServerDiscoveryError = message
            errorMessage = message
        }
    }

    func invokeToolServer(_ serverID: String, requestBody: String? = nil) async {
        guard let server = toolServers.first(where: { $0.id == serverID }) else {
            toolServerInvocationError = "Tool server not found."
            errorMessage = toolServerInvocationError
            return
        }

        guard requireDirectToolServersFeatureEnabled() else {
            toolServerInvocationError = directToolServersDisabledMessage
            return
        }

        guard requireToolServerExecutionPermission() else {
            return
        }

        guard server.isEnabled else {
            toolServerInvocationError = "Tool server is disabled."
            errorMessage = toolServerInvocationError
            return
        }

        let trimmedBody = (requestBody ?? toolServerInvocationRequestBody)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let payload = trimmedBody.isEmpty ? "{}" : trimmedBody
        isInvokingToolServer = true
        toolServerInvocationError = nil
        errorMessage = nil
        defer {
            isInvokingToolServer = false
        }

        let run = await toolServerInvoker.invoke(
            ToolServerInvocationRequest(server: server, requestBody: payload)
        )

        do {
            try await toolServerRunStorage.save(run)
            toolServerRuns.removeAll { $0.id == run.id }
            toolServerRuns.append(run)
            sortToolServerRuns()
            selectedToolServerRunID = run.id
            toolServerInvocationError = run.status == .failed
                ? run.errorMessage ?? "Tool server invocation failed."
                : nil
            await recordAuditEvent(
                action: .toolServerInvoked,
                outcome: run.status == .succeeded ? .succeeded : .failed,
                summary: "\(run.serverName) tool-server invocation \(run.status.rawValue)",
                metadata: [
                    "serverID": run.serverID,
                    "serverKind": run.serverKind.rawValue,
                    "status": run.status.rawValue,
                    "runID": run.id.uuidString
                ]
            )
        } catch {
            toolServerInvocationError = error.localizedDescription
            errorMessage = error.localizedDescription
        }
    }

    func callToolServerTool(_ serverID: String, toolName: String, argumentsBody: String = "{}") async {
        guard let server = toolServers.first(where: { $0.id == serverID }) else {
            toolServerInvocationError = "Tool server not found."
            errorMessage = toolServerInvocationError
            return
        }

        guard requireDirectToolServersFeatureEnabled() else {
            toolServerInvocationError = directToolServersDisabledMessage
            return
        }

        guard requireToolServerExecutionPermission() else {
            return
        }

        guard server.isEnabled else {
            toolServerInvocationError = "Tool server is disabled."
            errorMessage = toolServerInvocationError
            return
        }

        let trimmedBody = argumentsBody.trimmingCharacters(in: .whitespacesAndNewlines)
        let payload = trimmedBody.isEmpty ? "{}" : trimmedBody
        guard let data = payload.data(using: .utf8),
              let arguments = try? JSONDecoder().decode(JSONValue.self, from: data),
              arguments.objectValue != nil else {
            toolServerInvocationError = "Tool arguments must be a JSON object."
            errorMessage = toolServerInvocationError
            return
        }

        if let tool = toolServerTools[serverID]?.first(where: { $0.name == toolName }),
           let validationError = toolArgumentTemplateService.validationError(for: arguments, tool: tool) {
            toolServerInvocationError = validationError
            errorMessage = validationError
            return
        }

        isInvokingToolServer = true
        toolServerInvocationError = nil
        errorMessage = nil
        defer {
            isInvokingToolServer = false
        }

        let run = await toolServerToolCaller.callTool(
            ToolServerToolCallRequest(server: server, toolName: toolName, arguments: arguments)
        )

        do {
            try await toolServerRunStorage.save(run)
            toolServerRuns.removeAll { $0.id == run.id }
            toolServerRuns.append(run)
            sortToolServerRuns()
            selectedToolServerRunID = run.id
            toolServerInvocationError = run.status == .failed
                ? run.errorMessage ?? "Tool call failed."
                : nil
            await recordAuditEvent(
                action: .toolServerInvoked,
                outcome: run.status == .succeeded ? .succeeded : .failed,
                summary: "\(run.serverName) tool \(toolName) call \(run.status.rawValue)",
                metadata: [
                    "serverID": run.serverID,
                    "serverKind": run.serverKind.rawValue,
                    "status": run.status.rawValue,
                    "runID": run.id.uuidString,
                    "toolName": toolName
                ]
            )
        } catch {
            toolServerInvocationError = error.localizedDescription
            errorMessage = error.localizedDescription
        }
    }

    func deleteToolServerRun(_ runID: UUID) async {
        guard requireDirectToolServersFeatureEnabled() else {
            return
        }

        guard requireToolServerWritePermission() else {
            return
        }

        let deletedRun = toolServerRuns.first { $0.id == runID }

        do {
            try await toolServerRunStorage.deleteRun(id: runID)
            toolServerRuns.removeAll { $0.id == runID }
            if selectedToolServerRunID == runID {
                selectedToolServerRunID = nil
            }
            errorMessage = nil
            await recordAuditEvent(
                action: .toolServerRunDeleted,
                outcome: .succeeded,
                summary: "Deleted tool-server run",
                metadata: [
                    "runID": runID.uuidString,
                    "serverID": deletedRun?.serverID ?? "",
                    "serverKind": deletedRun?.serverKind.rawValue ?? "",
                    "status": deletedRun?.status.rawValue ?? ""
                ]
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func exportToolServersJSONData() throws -> Data {
        try toolServerExportService.jsonData(for: toolServers)
    }

    func exportToolServersJSONWithSavePanel() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "open-webui-native-tool-servers.json"
        panel.canCreateDirectories = true
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else {
                return
            }
            Task { @MainActor in
                do {
                    let data = try self?.exportToolServersJSONData()
                    try data?.write(to: url, options: [.atomic])
                } catch {
                    self?.errorMessage = error.localizedDescription
                }
            }
        }
    }

    func importToolServersJSONData(_ data: Data) async throws {
        guard requireToolServerWritePermission() else {
            return
        }
        let importedServers = try toolServerExportService.servers(fromJSONData: data)
        for server in importedServers {
            try await toolServerStorage.save(server)
            toolServers.removeAll { $0.id == server.id }
            toolServers.append(server)
            toolServerStatuses[server.id] = .unknown
            toolServerDiscoveryStatuses[server.id] = .unknown
            toolServerTools[server.id] = []
        }
        sortToolServers()
    }

    func importToolServersJSON(from url: URL) async {
        let didStartAccessing = url.startAccessingSecurityScopedResource()
        defer {
            if didStartAccessing {
                url.stopAccessingSecurityScopedResource()
            }
        }

        do {
            let data = try Data(contentsOf: url)
            try await importToolServersJSONData(data)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func importToolServersJSONWithOpenPanel() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.begin { [weak self] response in
            guard response == .OK else {
                return
            }
            let urls = panel.urls
            Task { @MainActor in
                for url in urls {
                    await self?.importToolServersJSON(from: url)
                }
            }
        }
    }

    func runFunction(_ functionID: String, methodName: String? = nil, inputBody: String = "{}") async {
        guard let function = functions.first(where: { $0.id == functionID }) else {
            functionExecutionError = "Function not found."
            errorMessage = functionExecutionError
            return
        }
        guard requireFunctionsFeatureEnabled() else {
            functionExecutionError = functionsDisabledMessage
            return
        }
        guard requireFunctionExecutionPermission() else {
            return
        }

        let trimmedBody = inputBody.trimmingCharacters(in: .whitespacesAndNewlines)
        let payload = trimmedBody.isEmpty ? "{}" : trimmedBody
        guard let data = payload.data(using: .utf8),
              let input = try? JSONDecoder().decode(JSONValue.self, from: data),
              input.objectValue != nil else {
            functionExecutionError = "Function input must be a JSON object."
            errorMessage = functionExecutionError
            return
        }

        let resolvedMethodName = methodName?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfEmpty ?? defaultMethodName(for: function)
        guard !resolvedMethodName.isEmpty else {
            functionExecutionError = "Select a function method to run."
            errorMessage = functionExecutionError
            return
        }

        isRunningFunction = true
        functionExecutionError = nil
        errorMessage = nil
        defer {
            isRunningFunction = false
        }

        let run = await functionExecutor.invoke(
            LocalFunctionInvocationRequest(
                function: function,
                methodName: resolvedMethodName,
                input: input,
                inputBody: payload,
                timeoutSeconds: min(max(codeExecutionTimeoutSeconds, 0.1), max(settings.codeExecution.maxTimeoutSeconds, 0.1))
            )
        )

        do {
            try await persistFunctionRun(run)
            functionExecutionError = run.status == .succeeded
                ? nil
                : run.errorMessage ?? "Function run failed."
        } catch {
            functionExecutionError = error.localizedDescription
            errorMessage = error.localizedDescription
        }
    }

    func runActionFunction(_ functionID: String, messageID: UUID) async {
        guard requireFunctionsFeatureEnabled() else {
            functionExecutionError = functionsDisabledMessage
            return
        }
        guard let function = activeActionFunctions.first(where: { $0.id == functionID }) else {
            functionExecutionError = "Active action function not found."
            errorMessage = functionExecutionError
            return
        }
        guard requireFunctionExecutionPermission() else {
            return
        }
        guard let threadIndex = threadIndex(containing: messageID),
              let message = threads[threadIndex].messages.first(where: { $0.id == messageID }) else {
            functionExecutionError = "Message not found."
            errorMessage = functionExecutionError
            return
        }
        guard message.role == .assistant else {
            functionExecutionError = "Action functions can only run on assistant messages."
            errorMessage = functionExecutionError
            return
        }
        guard !message.isStreaming else {
            functionExecutionError = "Wait for the assistant response to finish before running actions."
            errorMessage = functionExecutionError
            return
        }

        isRunningFunction = true
        functionExecutionError = nil
        errorMessage = nil
        defer {
            isRunningFunction = false
        }

        let thread = threads[threadIndex]
        let input = actionInvocationInput(thread: thread, message: message)
        let run = await functionExecutor.invoke(
            LocalFunctionInvocationRequest(
                function: function,
                methodName: "action",
                input: input,
                inputBody: jsonBodyString(for: input),
                timeoutSeconds: min(max(codeExecutionTimeoutSeconds, 0.1), max(settings.codeExecution.maxTimeoutSeconds, 0.1))
            )
        )

        do {
            try await persistFunctionRun(run)
            functionExecutionError = run.status == .succeeded
                ? nil
                : run.errorMessage ?? "Function action failed."
            if functionExecutionError != nil {
                errorMessage = functionExecutionError
            }
        } catch {
            functionExecutionError = error.localizedDescription
            errorMessage = error.localizedDescription
        }
    }

    func createFunction(
        name: String,
        kind: AppFunctionKind,
        content: String,
        description: String?,
        valvesJSON: String? = nil
    ) async {
        guard requireFunctionsFeatureEnabled() else {
            return
        }
        guard requireFunctionWritePermission() else {
            return
        }
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedContent = content.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedDescription = description?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty, !trimmedContent.isEmpty else {
            return
        }
        let valves: JSONValue?
        do {
            valves = try await validatedFunctionValves(
                from: valvesJSON,
                name: trimmedName,
                kind: kind,
                content: trimmedContent
            )
        } catch {
            errorMessage = error.localizedDescription
            return
        }
        errorMessage = nil

        let function = AppFunction(
            name: trimmedName,
            kind: kind,
            content: trimmedContent,
            description: trimmedDescription?.isEmpty == false ? trimmedDescription : nil,
            valves: valves
        )

        do {
            try await functionStorage.save(function)
            functions.append(function)
            sortFunctions()
            refreshNativeFunctionModels()
            await recordAuditEvent(
                action: .functionCreated,
                outcome: .succeeded,
                summary: "Created function \(function.name)",
                metadata: functionAuditMetadata(for: function)
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func updateFunction(
        _ functionID: String,
        name: String,
        kind: AppFunctionKind,
        content: String,
        description: String?,
        isActive: Bool,
        isGlobal: Bool,
        valvesJSON: String? = nil
    ) async {
        guard requireFunctionsFeatureEnabled() else {
            return
        }
        guard requireFunctionWritePermission() else {
            return
        }
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedContent = content.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedDescription = description?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty, !trimmedContent.isEmpty,
              let index = functions.firstIndex(where: { $0.id == functionID }) else {
            return
        }
        let valves: JSONValue?
        if let valvesJSON {
            do {
                valves = try await validatedFunctionValves(
                    from: valvesJSON,
                    name: trimmedName,
                    kind: kind,
                    content: trimmedContent
                )
            } catch {
                errorMessage = error.localizedDescription
                return
            }
        } else {
            valves = functions[index].valves
        }
        errorMessage = nil
        let originalFunction = functions[index]

        functions[index].name = trimmedName
        functions[index].kind = kind
        functions[index].content = trimmedContent
        functions[index].description = trimmedDescription?.isEmpty == false ? trimmedDescription : nil
        functions[index].valves = valves
        functions[index].isActive = isActive
        functions[index].isGlobal = isGlobal
        functions[index].updatedAt = Date()

        do {
            try await functionStorage.save(functions[index])
            let updatedFunction = functions[index]
            sortFunctions()
            refreshNativeFunctionModels()
            var metadata = functionAuditMetadata(for: updatedFunction)
            metadata["fromName"] = originalFunction.name
            await recordAuditEvent(
                action: .functionUpdated,
                outcome: .succeeded,
                summary: "Updated function \(updatedFunction.name)",
                metadata: metadata
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func functionValvesTemplateJSON(name: String, kind: AppFunctionKind, content: String) async -> String? {
        await functionValvesSchemaDraft(name: name, kind: kind, content: content)?.templateJSON
    }

    func functionValvesSchemaDraft(name: String, kind: AppFunctionKind, content: String) async -> ValvesSchemaDraft? {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedContent = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedContent.isEmpty else {
            return nil
        }
        guard let schema = await functionValvesSchema(
            name: trimmedName.isEmpty ? "Draft function" : trimmedName,
            kind: kind,
            content: trimmedContent
        ) else {
            errorMessage = "Function does not define a Valves schema."
            return nil
        }
        do {
            errorMessage = nil
            return ValvesSchemaDraft(
                templateJSON: try toolArgumentTemplateService.jsonTemplate(forSchema: schema),
                fields: toolArgumentTemplateService.formFields(forSchema: schema)
            )
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    func deleteFunction(_ functionID: String) async {
        guard requireFunctionsFeatureEnabled() else {
            return
        }
        guard requireFunctionWritePermission() else {
            return
        }
        let deletedFunction = functions.first { $0.id == functionID }
        do {
            try await functionStorage.deleteFunction(id: functionID)
            functions.removeAll { $0.id == functionID }
            refreshNativeFunctionModels()
            if let deletedFunction {
                await recordAuditEvent(
                    action: .functionDeleted,
                    outcome: .succeeded,
                    summary: "Deleted function \(deletedFunction.name)",
                    metadata: functionAuditMetadata(for: deletedFunction)
                )
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func exportFunctionsJSONData() throws -> Data {
        try functionExportService.jsonData(for: functions)
    }

    func exportFunctionsOpenWebUIJSONData() throws -> Data {
        try functionExportService.openWebUIJSONData(for: functions, userID: currentUserID)
    }

    func exportFunctionJSONData(_ functionID: String) throws -> Data? {
        guard let function = functions.first(where: { $0.id == functionID }) else {
            return nil
        }
        return try functionExportService.jsonData(for: [function])
    }

    func shareFunction(_ functionID: String) {
        guard requireFunctionsFeatureEnabled() else {
            return
        }
        guard let function = functions.first(where: { $0.id == functionID }) else {
            return
        }

        do {
            let data = try functionExportService.jsonData(for: [function])
            guard let json = String(data: data, encoding: .utf8) else {
                errorMessage = "The selected function could not be encoded for sharing."
                return
            }
            shareService.share(text: json, title: function.name)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func exportFunctionsJSONWithSavePanel() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "open-webui-native-functions.json"
        panel.canCreateDirectories = true
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else {
                return
            }
            Task { @MainActor in
                do {
                    let data = try self?.exportFunctionsJSONData()
                    try data?.write(to: url, options: [.atomic])
                } catch {
                    self?.errorMessage = error.localizedDescription
                }
            }
        }
    }

    func exportFunctionsOpenWebUIJSONWithSavePanel() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "open-webui-functions.json"
        panel.canCreateDirectories = true
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else {
                return
            }
            Task { @MainActor in
                do {
                    let data = try self?.exportFunctionsOpenWebUIJSONData()
                    try data?.write(to: url, options: [.atomic])
                } catch {
                    self?.errorMessage = error.localizedDescription
                }
            }
        }
    }

    func importFunctionsJSONData(_ data: Data) async throws {
        guard requireFunctionsFeatureEnabled() else {
            return
        }
        guard requireFunctionWritePermission() else {
            return
        }
        let importedFunctions = try functionExportService.functions(fromJSONData: data)
        for function in importedFunctions {
            try await functionStorage.save(function)
            functions.removeAll { $0.id == function.id }
            functions.append(function)
        }
        sortFunctions()
        refreshNativeFunctionModels()
    }

    func importFunctionsJSON(from url: URL) async {
        guard requireFunctionsFeatureEnabled() else {
            return
        }
        let didStartAccessing = url.startAccessingSecurityScopedResource()
        defer {
            if didStartAccessing {
                url.stopAccessingSecurityScopedResource()
            }
        }

        do {
            let data = try Data(contentsOf: url)
            try await importFunctionsJSONData(data)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func importFunctionsJSONWithOpenPanel() {
        guard requireFunctionsFeatureEnabled() else {
            return
        }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.begin { [weak self] response in
            guard response == .OK else {
                return
            }
            let urls = panel.urls
            Task { @MainActor in
                for url in urls {
                    await self?.importFunctionsJSON(from: url)
                }
            }
        }
    }

    func createSkill(
        name: String,
        content: String,
        description: String?,
        tags: [String],
        allowedUserIDs: [String] = [],
        allowedGroupIDs: [String] = []
    ) async {
        guard requireSkillsFeatureEnabled() else {
            return
        }
        guard requireSkillWritePermission() else {
            return
        }
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedContent = content.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedDescription = description?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty, !trimmedContent.isEmpty else {
            return
        }

        let skill = AppSkill(
            name: trimmedName,
            content: trimmedContent,
            description: trimmedDescription?.isEmpty == false ? trimmedDescription : nil,
            tags: AppSkill.normalizedTags(tags),
            allowedUserIDs: AppSkill.normalizedAccessIDs(allowedUserIDs),
            allowedGroupIDs: AppSkill.normalizedAccessIDs(allowedGroupIDs)
        )

        do {
            try await skillStorage.save(skill)
            skills.append(skill)
            sortSkills()
            await recordAuditEvent(
                action: .skillCreated,
                outcome: .succeeded,
                summary: "Created skill \(skill.name)",
                metadata: skillAuditMetadata(for: skill)
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func updateSkill(
        _ skillID: String,
        name: String,
        content: String,
        description: String?,
        tags: [String],
        isActive: Bool,
        allowedUserIDs: [String]? = nil,
        allowedGroupIDs: [String]? = nil
    ) async {
        guard requireSkillsFeatureEnabled() else {
            return
        }
        guard requireSkillWritePermission() else {
            return
        }
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedContent = content.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedDescription = description?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty, !trimmedContent.isEmpty,
              let index = skills.firstIndex(where: { $0.id == skillID }) else {
            return
        }
        let originalSkill = skills[index]

        skills[index].name = trimmedName
        skills[index].content = trimmedContent
        skills[index].description = trimmedDescription?.isEmpty == false ? trimmedDescription : nil
        skills[index].tags = AppSkill.normalizedTags(tags)
        skills[index].isActive = isActive
        if let allowedUserIDs {
            skills[index].allowedUserIDs = AppSkill.normalizedAccessIDs(allowedUserIDs)
        }
        if let allowedGroupIDs {
            skills[index].allowedGroupIDs = AppSkill.normalizedAccessIDs(allowedGroupIDs)
        }
        skills[index].updatedAt = Date()

        do {
            try await skillStorage.save(skills[index])
            let updatedSkill = skills[index]
            sortSkills()
            var metadata = skillAuditMetadata(for: updatedSkill)
            metadata["fromName"] = originalSkill.name
            await recordAuditEvent(
                action: .skillUpdated,
                outcome: .succeeded,
                summary: "Updated skill \(updatedSkill.name)",
                metadata: metadata
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func deleteSkill(_ skillID: String) async {
        guard requireSkillsFeatureEnabled() else {
            return
        }
        guard requireSkillWritePermission() else {
            return
        }
        let deletedSkill = skills.first { $0.id == skillID }
        do {
            try await skillStorage.deleteSkill(id: skillID)
            skills.removeAll { $0.id == skillID }
            if let deletedSkill {
                await recordAuditEvent(
                    action: .skillDeleted,
                    outcome: .succeeded,
                    summary: "Deleted skill \(deletedSkill.name)",
                    metadata: skillAuditMetadata(for: deletedSkill)
                )
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func exportSkillsJSONData() throws -> Data {
        try skillExportService.jsonData(for: skills)
    }

    func exportSkillsOpenWebUIJSONData() throws -> Data {
        try skillExportService.openWebUIJSONData(for: skills, userID: currentUserID)
    }

    func exportSkillJSONData(_ skillID: String) throws -> Data? {
        guard let skill = skills.first(where: { $0.id == skillID }) else {
            return nil
        }
        return try skillExportService.jsonData(for: [skill])
    }

    func shareSkill(_ skillID: String) {
        guard requireSkillsFeatureEnabled() else {
            return
        }
        guard let skill = skills.first(where: { $0.id == skillID }) else {
            return
        }

        do {
            let data = try skillExportService.jsonData(for: [skill])
            guard let json = String(data: data, encoding: .utf8) else {
                errorMessage = "The selected skill could not be encoded for sharing."
                return
            }
            shareService.share(text: json, title: skill.name)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func exportSkillsJSONWithSavePanel() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "open-webui-native-skills.json"
        panel.canCreateDirectories = true
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else {
                return
            }
            Task { @MainActor in
                do {
                    let data = try self?.exportSkillsJSONData()
                    try data?.write(to: url, options: [.atomic])
                } catch {
                    self?.errorMessage = error.localizedDescription
                }
            }
        }
    }

    func exportSkillsOpenWebUIJSONWithSavePanel() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "open-webui-skills.json"
        panel.canCreateDirectories = true
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else {
                return
            }
            Task { @MainActor in
                do {
                    let data = try self?.exportSkillsOpenWebUIJSONData()
                    try data?.write(to: url, options: [.atomic])
                } catch {
                    self?.errorMessage = error.localizedDescription
                }
            }
        }
    }

    func importSkillsJSONData(_ data: Data) async throws {
        guard requireSkillsFeatureEnabled() else {
            return
        }
        guard requireSkillWritePermission() else {
            return
        }
        let importedSkills = try skillExportService.skills(fromJSONData: data)
        for skill in importedSkills {
            try await skillStorage.save(skill)
            skills.removeAll { $0.id == skill.id }
            skills.append(skill)
        }
        sortSkills()
    }

    func importSkillsJSON(from url: URL) async {
        guard requireSkillsFeatureEnabled() else {
            return
        }
        guard requireSkillWritePermission() else {
            return
        }

        let didStartAccessing = url.startAccessingSecurityScopedResource()
        defer {
            if didStartAccessing {
                url.stopAccessingSecurityScopedResource()
            }
        }

        do {
            let data = try Data(contentsOf: url)
            try await importSkillsJSONData(data)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func importSkillsJSONWithOpenPanel() {
        guard requireSkillsFeatureEnabled() else {
            return
        }
        guard requireSkillWritePermission() else {
            return
        }

        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.begin { [weak self] response in
            guard response == .OK else {
                return
            }
            let urls = panel.urls
            Task { @MainActor in
                for url in urls {
                    await self?.importSkillsJSON(from: url)
                }
            }
        }
    }

    func createFeedback(
        messageID: UUID,
        rating: MessageRating,
        reason: String?,
        comment: String?
    ) async {
        guard let threadIndex = threadIndex(containing: messageID),
              let messageIndex = threads[threadIndex].messages.firstIndex(where: { $0.id == messageID }) else {
            return
        }

        let thread = threads[threadIndex]
        let message = thread.messages[messageIndex]
        let trimmedReason = reason?.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedComment = comment?.trimmingCharacters(in: .whitespacesAndNewlines)
        let feedback = AppFeedback(
            data: AppFeedbackData(
                rating: rating,
                modelID: message.modelID,
                siblingModelIDs: siblingModelIDs(for: message, in: thread),
                reason: trimmedReason?.isEmpty == false ? trimmedReason : nil,
                comment: trimmedComment?.isEmpty == false ? trimmedComment : nil
            ),
            meta: AppFeedbackMeta(
                arena: thread.modelIDs.count > 1,
                chatID: thread.id.uuidString,
                messageID: message.id.uuidString,
                tags: thread.tags
            ),
            snapshot: AppFeedbackSnapshot(
                chat: AppFeedbackChatSnapshot(
                    title: thread.title,
                    messageCount: thread.messages.count
                )
            )
        )

        do {
            try await feedbackStorage.save(feedback)
            feedbacks.append(feedback)
            sortFeedbacks()
            threads[threadIndex].messages[messageIndex].rating = rating
            threads[threadIndex].messages[messageIndex].updatedAt = Date()
            threads[threadIndex].updatedAt = Date()
            await persistThread(at: threadIndex)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func deleteFeedback(_ feedbackID: String) async {
        let deletedFeedback = feedbacks.first { $0.id == feedbackID }
        do {
            try await feedbackStorage.deleteFeedback(id: feedbackID)
            feedbacks.removeAll { $0.id == feedbackID }
            if let deletedFeedback {
                await recordAuditEvent(
                    action: .feedbackDeleted,
                    outcome: .succeeded,
                    summary: "Deleted feedback for \(deletedFeedback.data.modelID ?? "unknown model")",
                    metadata: [
                        "feedbackID": deletedFeedback.id,
                        "modelID": deletedFeedback.data.modelID ?? "",
                        "rating": deletedFeedback.data.rating?.rawValue ?? "unrated",
                        "moderationStatus": deletedFeedback.moderationStatus.rawValue
                    ]
                )
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func updateFeedbackModerationStatus(_ feedbackID: String, status: AppFeedbackModerationStatus) async {
        guard let index = feedbacks.firstIndex(where: { $0.id == feedbackID }) else {
            return
        }
        let previousStatus = feedbacks[index].moderationStatus
        feedbacks[index].moderationStatus = status
        feedbacks[index].updatedAt = Date()
        let updatedFeedback = feedbacks[index]
        do {
            try await feedbackStorage.save(updatedFeedback)
            sortFeedbacks()
            await recordAuditEvent(
                action: .feedbackModerationUpdated,
                outcome: .succeeded,
                summary: "Marked feedback \(status.label.lowercased())",
                metadata: [
                    "feedbackID": updatedFeedback.id,
                    "modelID": updatedFeedback.data.modelID ?? "",
                    "fromStatus": previousStatus.rawValue,
                    "toStatus": status.rawValue
                ]
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func exportFeedbackJSONData() throws -> Data {
        try feedbackExportService.jsonData(for: feedbacks)
    }

    func exportFeedbackOpenWebUIJSONData() throws -> Data {
        try feedbackExportService.openWebUIJSONData(for: feedbacks)
    }

    func exportFeedbackJSONDataForUserAction() async throws -> Data {
        let exportedFeedbacks = feedbacks
        let data = try feedbackExportService.jsonData(for: exportedFeedbacks)
        await recordAuditEvent(
            action: .feedbackExported,
            outcome: .succeeded,
            summary: "Exported feedback records",
            metadata: feedbackTransferAuditMetadata(prefix: "exported", feedbacks: exportedFeedbacks)
        )
        return data
    }

    func exportFeedbackOpenWebUIJSONDataForUserAction() async throws -> Data {
        let exportedFeedbacks = feedbacks
        let data = try feedbackExportService.openWebUIJSONData(for: exportedFeedbacks)
        await recordAuditEvent(
            action: .feedbackExported,
            outcome: .succeeded,
            summary: "Exported feedback records",
            metadata: feedbackTransferAuditMetadata(prefix: "exported", feedbacks: exportedFeedbacks)
                .merging(["format": "open-webui"], uniquingKeysWith: { _, new in new })
        )
        return data
    }

    func exportFeedbackJSONWithSavePanel() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "open-webui-native-feedback.json"
        panel.canCreateDirectories = true
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else {
                return
            }
            Task { @MainActor in
                do {
                    let data = try await self?.exportFeedbackJSONDataForUserAction()
                    try data?.write(to: url, options: [.atomic])
                } catch {
                    self?.errorMessage = error.localizedDescription
                }
            }
        }
    }

    func exportFeedbackOpenWebUIJSONWithSavePanel() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "open-webui-feedback.json"
        panel.canCreateDirectories = true
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else {
                return
            }
            Task { @MainActor in
                do {
                    let data = try await self?.exportFeedbackOpenWebUIJSONDataForUserAction()
                    try data?.write(to: url, options: [.atomic])
                } catch {
                    self?.errorMessage = error.localizedDescription
                }
            }
        }
    }

    func importFeedbackJSONData(_ data: Data) async throws {
        let importedFeedbacks = try feedbackExportService.feedbacks(fromJSONData: data)
        try await importFeedbacks(importedFeedbacks)
    }

    func importFeedbackJSONDataForUserAction(_ data: Data) async throws {
        let importedFeedbacks = try feedbackExportService.feedbacks(fromJSONData: data)
        try await importFeedbacks(importedFeedbacks)
        var metadata = feedbackTransferAuditMetadata(prefix: "imported", feedbacks: importedFeedbacks)
        metadata["totalFeedbackCount"] = String(feedbacks.count)
        await recordAuditEvent(
            action: .feedbackImported,
            outcome: .succeeded,
            summary: "Imported feedback records",
            metadata: metadata
        )
    }

    private func importFeedbacks(_ importedFeedbacks: [AppFeedback]) async throws {
        for feedback in importedFeedbacks {
            try await feedbackStorage.save(feedback)
            feedbacks.removeAll { $0.id == feedback.id }
            feedbacks.append(feedback)
        }
        sortFeedbacks()
    }

    private func feedbackTransferAuditMetadata(prefix: String, feedbacks: [AppFeedback]) -> [String: String] {
        [
            "\(prefix)FeedbackCount": String(feedbacks.count),
            "\(prefix)PositiveCount": String(feedbacks.filter { $0.data.rating == .positive }.count),
            "\(prefix)NegativeCount": String(feedbacks.filter { $0.data.rating == .negative }.count),
            "\(prefix)PendingCount": String(feedbacks.filter { $0.moderationStatus == .pending }.count),
            "\(prefix)ReviewedCount": String(feedbacks.filter { $0.moderationStatus == .reviewed }.count),
            "\(prefix)DismissedCount": String(feedbacks.filter { $0.moderationStatus == .dismissed }.count)
        ]
    }

    func importFeedbackJSON(from url: URL) async {
        let didStartAccessing = url.startAccessingSecurityScopedResource()
        defer {
            if didStartAccessing {
                url.stopAccessingSecurityScopedResource()
            }
        }

        do {
            let data = try Data(contentsOf: url)
            try await importFeedbackJSONDataForUserAction(data)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func importFeedbackJSONWithOpenPanel() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.begin { [weak self] response in
            guard response == .OK else {
                return
            }
            let urls = panel.urls
            Task { @MainActor in
                for url in urls {
                    await self?.importFeedbackJSON(from: url)
                }
            }
        }
    }

    func createAdminUser(name: String, email: String, role: AdminUserRole) async {
        guard requireAdminDirectoryWritePermission() else {
            return
        }

        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmedName.isEmpty, !normalizedEmail.isEmpty else {
            return
        }

        let user = AdminUser(name: trimmedName, email: normalizedEmail, role: role)
        adminUsers.removeAll { $0.email == normalizedEmail }
        adminUsers.append(user)
        sortAdminDirectory()
        if await persistAdminDirectory() {
            await recordAuditEvent(
                action: .adminUserCreated,
                outcome: .succeeded,
                summary: "Created admin user \(user.name)",
                metadata: adminUserAuditMetadata(for: user)
            )
        }
    }

    func updateAdminUser(_ userID: String, name: String, email: String, role: AdminUserRole) async {
        guard requireAdminDirectoryWritePermission() else {
            return
        }

        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmedName.isEmpty,
              !normalizedEmail.isEmpty,
              let index = adminUsers.firstIndex(where: { $0.id == userID }) else {
            return
        }
        let originalUser = adminUsers[index]

        adminUsers[index].name = trimmedName
        adminUsers[index].email = normalizedEmail
        adminUsers[index].role = role
        adminUsers[index].updatedAt = Date()
        sortAdminDirectory()
        if await persistAdminDirectory(),
           let updatedUser = adminUsers.first(where: { $0.id == userID }) {
            var metadata = adminUserAuditMetadata(for: updatedUser)
            metadata["fromName"] = originalUser.name
            metadata["fromEmail"] = originalUser.email
            metadata["fromRole"] = originalUser.role.rawValue
            await recordAuditEvent(
                action: .adminUserUpdated,
                outcome: .succeeded,
                summary: "Updated admin user \(updatedUser.name)",
                metadata: metadata
            )
        }
    }

    func deleteAdminUser(_ userID: String) async {
        guard requireAdminDirectoryWritePermission() else {
            return
        }

        guard let deletedUser = adminUsers.first(where: { $0.id == userID }) else {
            return
        }
        let removedFromGroupCount = adminGroups.filter { $0.memberIDs.contains(userID) }.count
        adminUsers.removeAll { $0.id == userID }
        for index in adminGroups.indices {
            adminGroups[index].memberIDs.removeAll { $0 == userID }
        }
        sortAdminDirectory()
        if await persistAdminDirectory() {
            var metadata = adminUserAuditMetadata(for: deletedUser)
            metadata["removedFromGroupCount"] = String(removedFromGroupCount)
            await recordAuditEvent(
                action: .adminUserDeleted,
                outcome: .succeeded,
                summary: "Deleted admin user \(deletedUser.name)",
                metadata: metadata
            )
        }
    }

    func createAdminGroup(name: String, description: String, permissions: [String]) async {
        guard requireAdminDirectoryWritePermission() else {
            return
        }

        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedDescription = description.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            return
        }

        let group = AdminGroup(
            name: trimmedName,
            description: trimmedDescription,
            permissions: AdminGroup.normalizedPermissions(permissions)
        )
        adminGroups.removeAll { $0.name.localizedCaseInsensitiveCompare(trimmedName) == .orderedSame }
        adminGroups.append(group)
        sortAdminDirectory()
        if await persistAdminDirectory() {
            await recordAuditEvent(
                action: .adminGroupCreated,
                outcome: .succeeded,
                summary: "Created admin group \(group.name)",
                metadata: adminGroupAuditMetadata(for: group)
            )
        }
    }

    func updateAdminGroup(
        _ groupID: String,
        name: String,
        description: String,
        permissions: [String],
        memberIDs: [String]
    ) async {
        guard requireAdminDirectoryWritePermission() else {
            return
        }

        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedDescription = description.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty,
              let index = adminGroups.firstIndex(where: { $0.id == groupID }) else {
            return
        }
        let originalGroup = adminGroups[index]

        adminGroups[index].name = trimmedName
        adminGroups[index].description = trimmedDescription
        adminGroups[index].permissions = AdminGroup.normalizedPermissions(permissions)
        adminGroups[index].memberIDs = AdminGroup.normalizedMemberIDs(
            memberIDs,
            validUserIDs: Set(adminUsers.map(\.id))
        )
        adminGroups[index].updatedAt = Date()
        sortAdminDirectory()
        if await persistAdminDirectory(),
           let updatedGroup = adminGroups.first(where: { $0.id == groupID }) {
            var metadata = adminGroupAuditMetadata(for: updatedGroup)
            metadata["fromName"] = originalGroup.name
            metadata["fromMemberCount"] = String(originalGroup.memberIDs.count)
            await recordAuditEvent(
                action: .adminGroupUpdated,
                outcome: .succeeded,
                summary: "Updated admin group \(updatedGroup.name)",
                metadata: metadata
            )
        }
    }

    func setAdminGroupMembers(_ groupID: String, memberIDs: [String]) async {
        guard requireAdminDirectoryWritePermission() else {
            return
        }

        guard let index = adminGroups.firstIndex(where: { $0.id == groupID }) else {
            return
        }
        let originalMemberCount = adminGroups[index].memberIDs.count

        adminGroups[index].memberIDs = AdminGroup.normalizedMemberIDs(
            memberIDs,
            validUserIDs: Set(adminUsers.map(\.id))
        )
        adminGroups[index].updatedAt = Date()
        sortAdminDirectory()
        if await persistAdminDirectory(),
           let updatedGroup = adminGroups.first(where: { $0.id == groupID }) {
            var metadata = adminGroupAuditMetadata(for: updatedGroup)
            metadata["fromMemberCount"] = String(originalMemberCount)
            await recordAuditEvent(
                action: .adminGroupMembersUpdated,
                outcome: .succeeded,
                summary: "Updated members for admin group \(updatedGroup.name)",
                metadata: metadata
            )
        }
    }

    func deleteAdminGroup(_ groupID: String) async {
        guard requireAdminDirectoryWritePermission() else {
            return
        }

        guard let deletedGroup = adminGroups.first(where: { $0.id == groupID }) else {
            return
        }
        adminGroups.removeAll { $0.id == groupID }
        if await persistAdminDirectory() {
            await recordAuditEvent(
                action: .adminGroupDeleted,
                outcome: .succeeded,
                summary: "Deleted admin group \(deletedGroup.name)",
                metadata: adminGroupAuditMetadata(for: deletedGroup)
            )
        }
    }

    func userHasPermission(_ userID: String, permission: String) -> Bool {
        let trimmedPermission = permission.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPermission.isEmpty,
              let user = adminUsers.first(where: { $0.id == userID }) else {
            return false
        }

        switch user.role {
        case .admin:
            return true
        case .pending:
            return false
        case .user:
            return adminGroups.contains { group in
                group.memberIDs.contains(userID) && group.permissions.contains(trimmedPermission)
            }
        }
    }

    func currentUserHasPermission(_ permission: String) -> Bool {
        guard !adminUsers.isEmpty else {
            return true
        }
        guard adminUsers.contains(where: { $0.id == currentUserID }) else {
            return true
        }

        return userHasPermission(currentUserID, permission: permission)
    }

    var currentUserCanManageSkills: Bool {
        currentUserHasPermission("skills.write")
    }

    var currentUserCanManagePrompts: Bool {
        currentUserHasPermission("prompts.write")
    }

    var currentUserCanManageNotes: Bool {
        currentUserHasPermission("notes.write")
    }

    var currentUserCanManageTools: Bool {
        currentUserHasPermission("tools.write")
    }

    var currentUserCanInvokeTools: Bool {
        currentUserHasPermission("tools.execute")
    }

    var currentUserCanManageFunctions: Bool {
        currentUserHasPermission("functions.write")
    }

    var currentUserCanInvokeFunctions: Bool {
        currentUserHasPermission("functions.execute")
    }

    var currentUserCanManageKnowledge: Bool {
        currentUserHasPermission("knowledge.write")
    }

    var currentUserCanManageChannels: Bool {
        currentUserHasPermission("channels.write")
    }

    var currentUserCanManageAutomations: Bool {
        currentUserHasPermission("automations.write")
    }

    var currentUserCanManageCalendar: Bool {
        currentUserHasPermission("calendar.write")
    }

    var currentUserCanUsePlayground: Bool {
        currentUserHasPermission("playground.execute")
    }

    var currentUserCanManagePlaygroundHistory: Bool {
        currentUserHasPermission("playground.write")
    }

    var currentUserCanGenerateImages: Bool {
        currentUserHasPermission("image_generation.execute")
    }

    var currentUserCanManageGeneratedImages: Bool {
        currentUserHasPermission("image_generation.write")
    }

    var currentUserCanTranscribeAudio: Bool {
        currentUserHasPermission("audio.transcribe")
    }

    var currentUserCanSynthesizeSpeech: Bool {
        currentUserHasPermission("audio.synthesize")
    }

    var currentUserCanManageAudioHistory: Bool {
        currentUserHasPermission("audio.write")
    }

    var currentUserCanUseWebSearch: Bool {
        currentUserHasPermission("web_search.execute")
    }

    var currentUserCanRunCode: Bool {
        currentUserHasPermission("code.execute")
    }

    var currentUserCanUseTerminal: Bool {
        currentUserHasPermission("terminal.execute")
    }

    var currentUserCanManageTerminalSessions: Bool {
        currentUserHasPermission("terminal.write")
    }

    var currentUserCanCreateTerminalSessions: Bool {
        currentUserCanUseTerminal || currentUserCanManageTerminalSessions
    }

    var currentUserCanManageAdminDirectory: Bool {
        currentUserHasPermission("settings.write")
    }

    var selectedTerminalSession: AppTerminalSession? {
        guard let selectedTerminalSessionID else {
            return terminalSessions.first
        }
        return terminalSessions.first { $0.id == selectedTerminalSessionID }
    }

    func exportAdminDirectoryJSONData() throws -> Data {
        try adminDirectoryExportService.jsonData(
            for: AdminDirectorySnapshot(users: adminUsers, groups: adminGroups)
        )
    }

    func exportAdminDirectoryJSONDataForUserAction() async throws -> Data {
        guard requireAdminDirectoryWritePermission() else {
            throw AppStoreMessageError(message: errorMessage ?? "You do not have permission to manage admin directory.")
        }

        let data = try exportAdminDirectoryJSONData()
        await recordAuditEvent(
            action: .adminDirectoryExported,
            outcome: .succeeded,
            summary: "Exported admin directory",
            metadata: [
                "exportedUserCount": String(adminUsers.count),
                "exportedGroupCount": String(adminGroups.count)
            ]
        )
        return data
    }

    func exportAdminDirectoryJSONWithSavePanel() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "open-webui-native-admin-directory.json"
        panel.canCreateDirectories = true
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else {
                return
            }
            Task { @MainActor in
                do {
                    let data = try await self?.exportAdminDirectoryJSONDataForUserAction()
                    try data?.write(to: url, options: [.atomic])
                } catch {
                    self?.errorMessage = error.localizedDescription
                }
            }
        }
    }

    func importAdminDirectoryJSONData(_ data: Data) async throws {
        guard requireAdminDirectoryWritePermission() else {
            throw AppStoreMessageError(message: errorMessage ?? "You do not have permission to manage admin directory.")
        }

        let snapshot = try adminDirectoryExportService.snapshot(fromJSONData: data)
        for user in snapshot.users {
            adminUsers.removeAll { existingUser in
                existingUser.id == user.id || existingUser.email == user.email
            }
            adminUsers.append(user)
        }

        let validUserIDs = Set(adminUsers.map(\.id))
        for group in snapshot.groups {
            var normalizedGroup = group
            normalizedGroup.memberIDs = AdminGroup.normalizedMemberIDs(
                group.memberIDs,
                validUserIDs: validUserIDs
            )
            adminGroups.removeAll { existingGroup in
                existingGroup.id == normalizedGroup.id
                    || existingGroup.name.localizedCaseInsensitiveCompare(normalizedGroup.name) == .orderedSame
            }
            adminGroups.append(normalizedGroup)
        }

        sortAdminDirectory()
        await persistAdminDirectory()
        await recordAuditEvent(
            action: .adminDirectoryImported,
            outcome: .succeeded,
            summary: "Imported admin directory",
            metadata: [
                "importedUserCount": String(snapshot.users.count),
                "importedGroupCount": String(snapshot.groups.count),
                "totalUserCount": String(adminUsers.count),
                "totalGroupCount": String(adminGroups.count)
            ]
        )
    }

    func importAdminDirectoryJSON(from url: URL) async {
        let didStartAccessing = url.startAccessingSecurityScopedResource()
        defer {
            if didStartAccessing {
                url.stopAccessingSecurityScopedResource()
            }
        }

        do {
            let data = try Data(contentsOf: url)
            try await importAdminDirectoryJSONData(data)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func importAdminDirectoryJSONWithOpenPanel() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.begin { [weak self] response in
            guard response == .OK else {
                return
            }
            let urls = panel.urls
            Task { @MainActor in
                for url in urls {
                    await self?.importAdminDirectoryJSON(from: url)
                }
            }
        }
    }

    func createChannel(name: String, description: String?) async {
        guard requireChannelsFeatureEnabled() else {
            return
        }
        guard requireChannelWritePermission() else {
            return
        }

        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedDescription = description?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            return
        }

        let channel = AppChannel(
            name: trimmedName,
            description: trimmedDescription?.isEmpty == false ? trimmedDescription : nil
        )

        do {
            try await channelStorage.save(channel)
            channels.append(channel)
            sortChannels()
            await recordAuditEvent(
                action: .channelCreated,
                outcome: .succeeded,
                summary: "Created channel \(channel.name)",
                metadata: [
                    "channelID": channel.id.uuidString,
                    "name": channel.name,
                    "hasDescription": String(channel.description?.isEmpty == false)
                ]
            )
            await selectChannel(channel.id)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func updateChannel(_ channelID: UUID, name: String, description: String?) async {
        guard requireChannelsFeatureEnabled() else {
            return
        }
        guard requireChannelWritePermission() else {
            return
        }

        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedDescription = description?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty,
              let index = channels.firstIndex(where: { $0.id == channelID }) else {
            return
        }

        let previousName = channels[index].name
        channels[index].name = trimmedName
        channels[index].description = trimmedDescription?.isEmpty == false ? trimmedDescription : nil
        channels[index].updatedAt = Date()
        let updatedChannel = channels[index]

        do {
            try await channelStorage.save(updatedChannel)
            sortChannels()
            await recordAuditEvent(
                action: .channelUpdated,
                outcome: .succeeded,
                summary: "Updated channel \(updatedChannel.name)",
                metadata: [
                    "channelID": updatedChannel.id.uuidString,
                    "name": updatedChannel.name,
                    "previousName": previousName,
                    "hasDescription": String(updatedChannel.description?.isEmpty == false)
                ]
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func postChannelMessage(_ channelID: UUID, content: String) async {
        guard requireChannelsFeatureEnabled() else {
            return
        }
        guard requireChannelWritePermission() else {
            return
        }

        let trimmedContent = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedContent.isEmpty,
              let index = channels.firstIndex(where: { $0.id == channelID }) else {
            return
        }

        channels[index].messages.append(ChannelMessage(content: trimmedContent))
        channels[index].unreadCount += 1
        channels[index].updatedAt = Date()

        do {
            try await channelStorage.save(channels[index])
            sortChannels()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func postChannelReply(_ channelID: UUID, to messageID: UUID, content: String) async {
        guard requireChannelsFeatureEnabled() else {
            return
        }
        guard requireChannelWritePermission() else {
            return
        }

        let trimmedContent = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedContent.isEmpty,
              let channelIndex = channels.firstIndex(where: { $0.id == channelID }),
              let messageIndex = channels[channelIndex].messages.firstIndex(where: { $0.id == messageID }) else {
            return
        }

        channels[channelIndex].messages[messageIndex].replies.append(ChannelReply(content: trimmedContent))
        channels[channelIndex].unreadCount += 1
        channels[channelIndex].updatedAt = Date()

        do {
            try await channelStorage.save(channels[channelIndex])
            sortChannels()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func selectChannel(_ channelID: UUID) async {
        guard requireChannelsFeatureEnabled() else {
            return
        }
        guard let index = channels.firstIndex(where: { $0.id == channelID }) else {
            return
        }

        selectedChannelID = channelID
        selectedThreadID = nil
        clearSelectedKnowledgeDocument()
        isShowingEvaluationDashboard = false
        isShowingAnalyticsDashboard = false
        isShowingPlayground = false
        isShowingFiles = false
        isShowingCalendar = false
        isShowingImageGeneration = false
        isShowingAudio = false
        isShowingCodeInterpreter = false
        isShowingTerminalSessions = false

        guard channels[index].unreadCount > 0 else {
            return
        }

        channels[index].unreadCount = 0
        do {
            try await channelStorage.save(channels[index])
            sortChannels()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func deleteChannel(_ channelID: UUID) async {
        guard requireChannelsFeatureEnabled() else {
            return
        }
        guard requireChannelWritePermission() else {
            return
        }

        guard let channel = channels.first(where: { $0.id == channelID }) else {
            return
        }

        do {
            try await channelStorage.deleteChannel(id: channelID)
            channels.removeAll { $0.id == channelID }
            if selectedChannelID == channelID {
                selectedChannelID = nil
            }
            await recordAuditEvent(
                action: .channelDeleted,
                outcome: .succeeded,
                summary: "Deleted channel \(channel.name)",
                metadata: [
                    "channelID": channel.id.uuidString,
                    "name": channel.name,
                    "messageCount": String(channel.messages.count),
                    "memberCount": String(channel.members.count)
                ]
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func addChannelMember(
        _ channelID: UUID,
        userID: String,
        displayName: String,
        role: ChannelMemberRole
    ) async {
        guard requireChannelsFeatureEnabled() else {
            return
        }
        guard requireChannelWritePermission() else {
            return
        }

        let normalizedUserID = userID.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedDisplayName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedUserID.isEmpty,
              !trimmedDisplayName.isEmpty,
              let channelIndex = channels.firstIndex(where: { $0.id == channelID }) else {
            return
        }

        let member = ChannelMember(
            userID: normalizedUserID,
            displayName: trimmedDisplayName,
            role: role
        )
        channels[channelIndex].members.removeAll { $0.userID == normalizedUserID }
        channels[channelIndex].members.append(member)
        channels[channelIndex].updatedAt = Date()
        sortChannelMembers(at: channelIndex)
        let channel = channels[channelIndex]
        guard await persistChannel(at: channelIndex) else {
            return
        }
        await recordAuditEvent(
            action: .channelMemberAdded,
            outcome: .succeeded,
            summary: "Added channel member to \(channel.name)",
            metadata: channelMemberAuditMetadata(channel: channel, member: member)
        )
    }

    func updateChannelMember(
        _ memberID: String,
        in channelID: UUID,
        role: ChannelMemberRole,
        status: ChannelMemberStatus,
        isMuted: Bool,
        isPinned: Bool
    ) async {
        guard requireChannelsFeatureEnabled() else {
            return
        }
        guard requireChannelWritePermission() else {
            return
        }

        guard let channelIndex = channels.firstIndex(where: { $0.id == channelID }),
              let memberIndex = channels[channelIndex].members.firstIndex(where: { $0.id == memberID }) else {
            return
        }

        let previousMember = channels[channelIndex].members[memberIndex]
        channels[channelIndex].members[memberIndex].role = role
        channels[channelIndex].members[memberIndex].status = status
        channels[channelIndex].members[memberIndex].isMuted = isMuted
        channels[channelIndex].members[memberIndex].isPinned = isPinned
        channels[channelIndex].members[memberIndex].updatedAt = Date()
        channels[channelIndex].updatedAt = Date()
        sortChannelMembers(at: channelIndex)
        let channel = channels[channelIndex]
        guard await persistChannel(at: channelIndex),
              let updatedMember = channel.members.first(where: { $0.id == memberID }) else {
            return
        }
        var metadata = channelMemberAuditMetadata(channel: channel, member: updatedMember)
        metadata["previousRole"] = previousMember.role.rawValue
        metadata["previousStatus"] = previousMember.status.rawValue
        metadata["previousIsMuted"] = String(previousMember.isMuted)
        metadata["previousIsPinned"] = String(previousMember.isPinned)
        await recordAuditEvent(
            action: .channelMemberUpdated,
            outcome: .succeeded,
            summary: "Updated channel member in \(channel.name)",
            metadata: metadata
        )
    }

    func removeChannelMember(_ memberID: String, from channelID: UUID) async {
        guard requireChannelsFeatureEnabled() else {
            return
        }
        guard requireChannelWritePermission() else {
            return
        }

        guard let channelIndex = channels.firstIndex(where: { $0.id == channelID }),
              let member = channels[channelIndex].members.first(where: { $0.id == memberID }) else {
            return
        }

        channels[channelIndex].members.removeAll { $0.id == memberID }
        channels[channelIndex].updatedAt = Date()
        let channel = channels[channelIndex]
        guard await persistChannel(at: channelIndex) else {
            return
        }
        await recordAuditEvent(
            action: .channelMemberRemoved,
            outcome: .succeeded,
            summary: "Removed channel member from \(channel.name)",
            metadata: channelMemberAuditMetadata(channel: channel, member: member)
        )
    }

    func exportChannelsJSONData() throws -> Data {
        try channelExportService.jsonData(for: channels)
    }

    func exportChannelsOpenWebUIJSONData() throws -> Data {
        try channelExportService.openWebUIJSONData(for: channels, userID: currentUserID)
    }

    func exportChannelsJSONWithSavePanel() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "open-webui-native-channels.json"
        panel.canCreateDirectories = true
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else {
                return
            }
            Task { @MainActor in
                do {
                    let data = try self?.exportChannelsJSONData()
                    try data?.write(to: url, options: [.atomic])
                } catch {
                    self?.errorMessage = error.localizedDescription
                }
            }
        }
    }

    func exportChannelsOpenWebUIJSONWithSavePanel() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "open-webui-channels.json"
        panel.canCreateDirectories = true
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else {
                return
            }
            Task { @MainActor in
                do {
                    let data = try self?.exportChannelsOpenWebUIJSONData()
                    try data?.write(to: url, options: [.atomic])
                } catch {
                    self?.errorMessage = error.localizedDescription
                }
            }
        }
    }

    func importChannelsJSONData(_ data: Data) async throws {
        guard requireChannelsFeatureEnabled() else {
            return
        }
        guard requireChannelWritePermission() else {
            return
        }

        let importedChannels = try channelExportService.channels(fromJSONData: data)
        for channel in importedChannels {
            try await channelStorage.save(channel)
            channels.removeAll { $0.id == channel.id }
            channels.append(channel)
        }
        sortChannels()
    }

    func importChannelsJSON(from url: URL) async {
        guard requireChannelsFeatureEnabled() else {
            return
        }
        guard requireChannelWritePermission() else {
            return
        }

        let didStartAccessing = url.startAccessingSecurityScopedResource()
        defer {
            if didStartAccessing {
                url.stopAccessingSecurityScopedResource()
            }
        }

        do {
            let data = try Data(contentsOf: url)
            try await importChannelsJSONData(data)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func importChannelsJSONWithOpenPanel() {
        guard requireChannelWritePermission() else {
            return
        }

        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.begin { [weak self] response in
            guard response == .OK else {
                return
            }
            let urls = panel.urls
            Task { @MainActor in
                for url in urls {
                    await self?.importChannelsJSON(from: url)
                }
            }
        }
    }

    func createAutomation(
        name: String,
        prompt: String,
        modelID: String,
        rrule: String,
        isActive: Bool
    ) async {
        guard requireAutomationsFeatureEnabled() else {
            return
        }
        guard requireAutomationWritePermission() else {
            return
        }

        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedModelID = modelID.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedRRule = rrule.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty, !trimmedPrompt.isEmpty, !trimmedModelID.isEmpty, !trimmedRRule.isEmpty else {
            return
        }

        let now = Date()
        let schedulePreview = automationScheduleService.preview(
            for: trimmedRRule,
            createdAt: now,
            after: now
        )
        guard schedulePreview.isValid else {
            errorMessage = schedulePreview.message
            return
        }

        var automation = AppAutomation(
            name: trimmedName,
            prompt: trimmedPrompt,
            modelID: trimmedModelID,
            rrule: trimmedRRule,
            isActive: isActive,
            createdAt: now,
            updatedAt: now
        )
        if isActive {
            automation.nextRunAt = schedulePreview.nextRunAt
        }

        do {
            try await automationStorage.save(automation)
            automations.append(automation)
            sortAutomations()
            await recordAuditEvent(
                action: .automationCreated,
                outcome: .succeeded,
                summary: "Created automation",
                metadata: automationAuditMetadata(for: automation)
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func updateAutomation(
        _ automationID: String,
        name: String,
        prompt: String,
        modelID: String,
        rrule: String,
        isActive: Bool
    ) async {
        guard requireAutomationsFeatureEnabled() else {
            return
        }
        guard requireAutomationWritePermission() else {
            return
        }

        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedModelID = modelID.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedRRule = rrule.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty, !trimmedPrompt.isEmpty, !trimmedModelID.isEmpty, !trimmedRRule.isEmpty,
              let index = automations.firstIndex(where: { $0.id == automationID }) else {
            return
        }

        let previousAutomation = automations[index]
        let now = Date()
        let schedulePreview = automationScheduleService.preview(
            for: trimmedRRule,
            createdAt: automations[index].createdAt,
            lastRunAt: automations[index].lastRunAt,
            after: now
        )
        guard schedulePreview.isValid else {
            errorMessage = schedulePreview.message
            return
        }

        automations[index].name = trimmedName
        automations[index].prompt = trimmedPrompt
        automations[index].modelID = trimmedModelID
        automations[index].rrule = trimmedRRule
        automations[index].isActive = isActive
        automations[index].updatedAt = now
        automations[index].nextRunAt = isActive
            ? schedulePreview.nextRunAt
            : nil

        do {
            try await automationStorage.save(automations[index])
            let updatedAutomation = automations[index]
            sortAutomations()
            var metadata = automationAuditMetadata(for: updatedAutomation)
            metadata["previousModelID"] = previousAutomation.modelID
            metadata["previousRRule"] = previousAutomation.rrule
            metadata["previousIsActive"] = String(previousAutomation.isActive)
            await recordAuditEvent(
                action: .automationUpdated,
                outcome: .succeeded,
                summary: "Updated automation",
                metadata: metadata
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func toggleAutomation(_ automationID: String) async {
        guard requireAutomationsFeatureEnabled() else {
            return
        }
        guard requireAutomationWritePermission() else {
            return
        }

        guard let index = automations.firstIndex(where: { $0.id == automationID }) else {
            return
        }

        let previousIsActive = automations[index].isActive
        automations[index].isActive.toggle()
        let now = Date()
        automations[index].updatedAt = now
        automations[index].nextRunAt = automations[index].isActive
            ? automationScheduleService.nextRunDate(for: automations[index], after: now)
            : nil

        do {
            try await automationStorage.save(automations[index])
            let updatedAutomation = automations[index]
            sortAutomations()
            var metadata = automationAuditMetadata(for: updatedAutomation)
            metadata["previousIsActive"] = String(previousIsActive)
            await recordAuditEvent(
                action: .automationStatusUpdated,
                outcome: .succeeded,
                summary: "Updated automation status",
                metadata: metadata
            )
        } catch {
            automations[index].isActive.toggle()
            errorMessage = error.localizedDescription
        }
    }

    func deleteAutomation(_ automationID: String) async {
        guard requireAutomationsFeatureEnabled() else {
            return
        }
        guard requireAutomationWritePermission() else {
            return
        }

        do {
            guard let automation = automations.first(where: { $0.id == automationID }) else {
                return
            }
            try await automationStorage.deleteAutomation(id: automationID)
            for run in automationRuns where run.automationID == automationID {
                try await automationRunStorage.deleteRun(id: run.id)
            }
            automations.removeAll { $0.id == automationID }
            automationRuns.removeAll { $0.automationID == automationID }
            await recordAuditEvent(
                action: .automationDeleted,
                outcome: .succeeded,
                summary: "Deleted automation",
                metadata: automationAuditMetadata(for: automation)
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func runAutomationNow(_ automationID: String) async {
        guard requireAutomationsFeatureEnabled() else {
            return
        }
        guard requireAutomationWritePermission() else {
            return
        }

        guard let index = automations.firstIndex(where: { $0.id == automationID }) else {
            return
        }

        let automation = automations[index]
        let startedAt = Date()
        var output = ""
        do {
            let provider = try makeActiveProvider()
            guard canChat else {
                throw ProviderError.unsupportedChat(activeProvider.name)
            }
            let messages = [ProviderChatMessage(role: ChatRole.user.rawValue, content: automation.prompt)]
            for try await chunk in provider.streamChat(model: automation.modelID, messages: messages) {
                output += chunk
            }
            let completedAt = Date()
            let run = AppAutomationRun(
                automationID: automation.id,
                automationName: automation.name,
                modelID: automation.modelID,
                prompt: automation.prompt,
                output: output,
                status: .succeeded,
                startedAt: startedAt,
                completedAt: completedAt
            )
            automations[index].lastRunAt = completedAt
            automations[index].nextRunAt = automationScheduleService.nextRunDate(for: automations[index], after: completedAt)
            automations[index].updatedAt = completedAt
            try await automationStorage.save(automations[index])
            try await automationRunStorage.save(run)
            automationRuns.append(run)
            sortAutomations()
            sortAutomationRuns()
            await recordAuditEvent(
                action: .automationRun,
                outcome: .succeeded,
                summary: "\(automation.name) automation succeeded",
                metadata: [
                    "automationID": automation.id,
                    "modelID": automation.modelID,
                    "status": run.status.rawValue,
                    "runID": run.id
                ]
            )
        } catch {
            let completedAt = Date()
            let run = AppAutomationRun(
                automationID: automation.id,
                automationName: automation.name,
                modelID: automation.modelID,
                prompt: automation.prompt,
                output: output,
                status: .failed,
                errorMessage: error.localizedDescription,
                startedAt: startedAt,
                completedAt: completedAt
            )
            do {
                try await automationRunStorage.save(run)
                automationRuns.append(run)
                sortAutomationRuns()
                await recordAuditEvent(
                    action: .automationRun,
                    outcome: .failed,
                    summary: "\(automation.name) automation failed",
                    metadata: [
                        "automationID": automation.id,
                        "modelID": automation.modelID,
                        "status": run.status.rawValue,
                        "runID": run.id,
                        "error": run.errorMessage ?? error.localizedDescription
                    ]
                )
            } catch {
                errorMessage = error.localizedDescription
                return
            }
            errorMessage = error.localizedDescription
        }
    }

    func runDueAutomations(at now: Date = Date()) async {
        guard requireAutomationsFeatureEnabled() else {
            return
        }
        guard requireAutomationWritePermission() else {
            return
        }

        let dueAutomations = automationScheduleService.dueAutomations(automations, at: now)
        for automation in dueAutomations {
            await runAutomationNow(automation.id)
        }
    }

    func startAutomationScheduler(intervalNanoseconds: UInt64 = 60_000_000_000) {
        guard isFeatureEnabled(.automations), automationSchedulerTask == nil else {
            return
        }

        isAutomationSchedulerRunning = true
        automationSchedulerTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.runDueAutomations()
                do {
                    try await Task.sleep(nanoseconds: intervalNanoseconds)
                } catch {
                    break
                }
            }
            await MainActor.run {
                self?.automationSchedulerTask = nil
                self?.isAutomationSchedulerRunning = false
            }
        }
    }

    func stopAutomationScheduler() {
        automationSchedulerTask?.cancel()
        automationSchedulerTask = nil
        isAutomationSchedulerRunning = false
    }

    func exportAutomationsJSONData() throws -> Data {
        try automationExportService.jsonData(for: automations)
    }

    func exportAutomationsOpenWebUIJSONData() throws -> Data {
        try automationExportService.openWebUIJSONData(for: automations)
    }

    func exportAutomationJSONData(_ automationID: String) throws -> Data? {
        guard let automation = automations.first(where: { $0.id == automationID }) else {
            return nil
        }
        return try automationExportService.jsonData(for: [automation])
    }

    func shareAutomation(_ automationID: String) {
        guard requireAutomationsFeatureEnabled() else {
            return
        }
        guard let automation = automations.first(where: { $0.id == automationID }) else {
            return
        }

        do {
            let data = try automationExportService.jsonData(for: [automation])
            guard let json = String(data: data, encoding: .utf8) else {
                errorMessage = "The selected automation could not be encoded for sharing."
                return
            }
            shareService.share(text: json, title: automation.name)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func exportAutomationsJSONWithSavePanel() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "open-webui-native-automations.json"
        panel.canCreateDirectories = true
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else {
                return
            }
            Task { @MainActor in
                do {
                    let data = try self?.exportAutomationsJSONData()
                    try data?.write(to: url, options: [.atomic])
                } catch {
                    self?.errorMessage = error.localizedDescription
                }
            }
        }
    }

    func exportAutomationsOpenWebUIJSONWithSavePanel() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "open-webui-automations.json"
        panel.canCreateDirectories = true
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else {
                return
            }
            Task { @MainActor in
                do {
                    let data = try self?.exportAutomationsOpenWebUIJSONData()
                    try data?.write(to: url, options: [.atomic])
                } catch {
                    self?.errorMessage = error.localizedDescription
                }
            }
        }
    }

    func importAutomationsJSONData(_ data: Data) async throws {
        guard requireAutomationsFeatureEnabled() else {
            return
        }
        guard requireAutomationWritePermission() else {
            return
        }

        let importedAutomations = try automationExportService.automations(fromJSONData: data)
        for automation in importedAutomations {
            try await automationStorage.save(automation)
            automations.removeAll { $0.id == automation.id }
            automations.append(automation)
        }
        sortAutomations()
    }

    func importAutomationsJSON(from url: URL) async {
        guard requireAutomationsFeatureEnabled() else {
            return
        }
        guard requireAutomationWritePermission() else {
            return
        }

        let didStartAccessing = url.startAccessingSecurityScopedResource()
        defer {
            if didStartAccessing {
                url.stopAccessingSecurityScopedResource()
            }
        }

        do {
            let data = try Data(contentsOf: url)
            try await importAutomationsJSONData(data)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func importAutomationsJSONWithOpenPanel() {
        guard requireAutomationsFeatureEnabled() else {
            return
        }
        guard requireAutomationWritePermission() else {
            return
        }

        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.begin { [weak self] response in
            guard response == .OK else {
                return
            }
            let urls = panel.urls
            Task { @MainActor in
                for url in urls {
                    await self?.importAutomationsJSON(from: url)
                }
            }
        }
    }

    func createCalendar(
        name: String,
        color: String?,
        allowedUserIDs: [String] = [],
        allowedGroupIDs: [String] = []
    ) async {
        guard requireCalendarFeatureEnabled() else {
            return
        }
        guard requireCalendarWritePermission() else {
            return
        }

        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedColor = color?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            return
        }

        let calendar = AppCalendar(
            name: trimmedName,
            color: trimmedColor?.isEmpty == false ? trimmedColor : nil,
            isDefault: calendars.isEmpty,
            allowedUserIDs: allowedUserIDs,
            allowedGroupIDs: allowedGroupIDs
        )
        calendars.append(calendar)
        selectedCalendarID = calendar.id
        await persistCalendarSnapshot()
    }

    func deleteCalendar(_ calendarID: String) async {
        guard requireCalendarFeatureEnabled() else {
            return
        }
        guard requireCalendarWritePermission() else {
            return
        }

        guard calendars.count > 1,
              let calendar = calendars.first(where: { $0.id == calendarID }),
              !calendar.isSystem else {
            return
        }
        calendars.removeAll { $0.id == calendarID }
        calendarEvents.removeAll { $0.calendarID == calendarID }
        if selectedCalendarID == calendarID {
            selectedCalendarID = calendars.first(where: \.isDefault)?.id ?? calendars.first?.id
        }
        await persistCalendarSnapshot()
    }

    func createCalendarEvent(
        calendarID: String,
        title: String,
        description: String?,
        startAt: Date,
        endAt: Date?,
        allDay: Bool,
        location: String?,
        reminderMinutesBefore: Int? = nil,
        rrule: String? = nil
    ) async {
        guard requireCalendarFeatureEnabled() else {
            return
        }
        guard requireCalendarWritePermission() else {
            return
        }

        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty,
              let calendar = calendars.first(where: { $0.id == calendarID }),
              currentUserCanAccessCalendar(calendar) else {
            return
        }

        let event = AppCalendarEvent(
            calendarID: calendarID,
            title: trimmedTitle,
            description: description?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            startAt: startAt,
            endAt: endAt,
            allDay: allDay,
            rrule: rrule?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            location: location?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            reminderMinutesBefore: normalizedReminderMinutesBefore(reminderMinutesBefore)
        )
        calendarEvents.append(event)
        guard await persistCalendarSnapshot() else {
            return
        }
        await recordAuditEvent(
            action: .calendarEventCreated,
            outcome: .succeeded,
            summary: "Created calendar event in \(calendar.name)",
            metadata: calendarEventAuditMetadata(for: event)
        )
    }

    func updateCalendarEvent(
        _ eventID: String,
        calendarID: String,
        title: String,
        description: String?,
        startAt: Date,
        endAt: Date?,
        allDay: Bool,
        location: String?,
        isCancelled: Bool,
        reminderMinutesBefore: Int? = nil,
        rrule: String? = nil
    ) async {
        guard requireCalendarFeatureEnabled() else {
            return
        }
        guard requireCalendarWritePermission() else {
            return
        }

        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty,
              let calendar = calendars.first(where: { $0.id == calendarID }),
              currentUserCanAccessCalendar(calendar),
              let index = calendarEvents.firstIndex(where: { $0.id == eventID }) else {
            return
        }

        let previousEvent = calendarEvents[index]
        calendarEvents[index].calendarID = calendarID
        calendarEvents[index].title = trimmedTitle
        calendarEvents[index].description = description?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        calendarEvents[index].startAt = startAt
        calendarEvents[index].endAt = endAt
        calendarEvents[index].allDay = allDay
        calendarEvents[index].rrule = rrule?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        calendarEvents[index].location = location?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        calendarEvents[index].reminderMinutesBefore = normalizedReminderMinutesBefore(reminderMinutesBefore)
        calendarEvents[index].isCancelled = isCancelled
        calendarEvents[index].updatedAt = Date()
        let updatedEvent = calendarEvents[index]
        guard await persistCalendarSnapshot() else {
            return
        }
        var metadata = calendarEventAuditMetadata(for: updatedEvent)
        metadata["previousCalendarID"] = previousEvent.calendarID
        metadata["previousAllDay"] = String(previousEvent.allDay)
        metadata["previousIsCancelled"] = String(previousEvent.isCancelled)
        metadata["previousHasReminder"] = String(previousEvent.reminderMinutesBefore != nil)
        metadata["previousHasRecurrence"] = String(previousEvent.rrule != nil)
        await recordAuditEvent(
            action: .calendarEventUpdated,
            outcome: .succeeded,
            summary: "Updated calendar event in \(calendar.name)",
            metadata: metadata
        )
    }

    func deleteCalendarEvent(_ eventID: String) async {
        guard requireCalendarFeatureEnabled() else {
            return
        }
        guard requireCalendarWritePermission() else {
            return
        }

        guard let event = calendarEvents.first(where: { $0.id == eventID }) else {
            return
        }
        calendarEvents.removeAll { $0.id == eventID }
        guard await persistCalendarSnapshot() else {
            return
        }
        await recordAuditEvent(
            action: .calendarEventDeleted,
            outcome: .succeeded,
            summary: "Deleted calendar event from \(calendarName(for: event.calendarID))",
            metadata: calendarEventAuditMetadata(for: event)
        )
    }

    func addCalendarEventAttendee(eventID: String, userID: String, status: String = "pending") async {
        guard requireCalendarFeatureEnabled() else {
            return
        }
        guard requireCalendarWritePermission() else {
            return
        }

        guard let eventIndex = calendarEvents.firstIndex(where: { $0.id == eventID }) else {
            return
        }
        let trimmedUserID = userID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedUserID.isEmpty else {
            return
        }
        let normalizedUserID = trimmedUserID.lowercased()
        let trimmedStatus = normalizedCalendarAttendeeStatus(status)
        let previousAttendee = calendarEvents[eventIndex].attendees.first { $0.userID.lowercased() == normalizedUserID }
        var updatedAttendee: AppCalendarEventAttendee?

        if let attendeeIndex = calendarEvents[eventIndex].attendees.firstIndex(where: { $0.userID.lowercased() == normalizedUserID }) {
            calendarEvents[eventIndex].attendees[attendeeIndex].userID = trimmedUserID
            calendarEvents[eventIndex].attendees[attendeeIndex].status = trimmedStatus
            calendarEvents[eventIndex].attendees[attendeeIndex].updatedAt = Date()
            updatedAttendee = calendarEvents[eventIndex].attendees[attendeeIndex]
        } else {
            let attendee = AppCalendarEventAttendee(
                eventID: eventID,
                userID: trimmedUserID,
                status: trimmedStatus
            )
            calendarEvents[eventIndex].attendees.append(attendee)
            updatedAttendee = attendee
        }
        calendarEvents[eventIndex].updatedAt = Date()
        let event = calendarEvents[eventIndex]
        guard await persistCalendarSnapshot(),
              let attendee = updatedAttendee else {
            return
        }
        var metadata = calendarAttendeeAuditMetadata(event: event, attendee: attendee)
        if let previousAttendee {
            metadata["previousStatus"] = previousAttendee.status
        }
        await recordAuditEvent(
            action: previousAttendee == nil ? .calendarAttendeeAdded : .calendarAttendeeUpdated,
            outcome: .succeeded,
            summary: previousAttendee == nil ? "Added calendar event attendee" : "Updated calendar event attendee",
            metadata: metadata
        )
    }

    func updateCalendarEventAttendee(eventID: String, attendeeID: String, status: String) async {
        guard requireCalendarFeatureEnabled() else {
            return
        }
        guard requireCalendarWritePermission() else {
            return
        }

        guard let eventIndex = calendarEvents.firstIndex(where: { $0.id == eventID }),
              let attendeeIndex = calendarEvents[eventIndex].attendees.firstIndex(where: { $0.id == attendeeID }) else {
            return
        }

        let previousAttendee = calendarEvents[eventIndex].attendees[attendeeIndex]
        calendarEvents[eventIndex].attendees[attendeeIndex].status = normalizedCalendarAttendeeStatus(status)
        calendarEvents[eventIndex].attendees[attendeeIndex].updatedAt = Date()
        calendarEvents[eventIndex].updatedAt = Date()
        let event = calendarEvents[eventIndex]
        let attendee = calendarEvents[eventIndex].attendees[attendeeIndex]
        guard await persistCalendarSnapshot() else {
            return
        }
        var metadata = calendarAttendeeAuditMetadata(event: event, attendee: attendee)
        metadata["previousStatus"] = previousAttendee.status
        await recordAuditEvent(
            action: .calendarAttendeeUpdated,
            outcome: .succeeded,
            summary: "Updated calendar event attendee",
            metadata: metadata
        )
    }

    func removeCalendarEventAttendee(eventID: String, attendeeID: String) async {
        guard requireCalendarFeatureEnabled() else {
            return
        }
        guard requireCalendarWritePermission() else {
            return
        }

        guard let eventIndex = calendarEvents.firstIndex(where: { $0.id == eventID }) else {
            return
        }

        guard let attendee = calendarEvents[eventIndex].attendees.first(where: { $0.id == attendeeID }) else {
            return
        }
        calendarEvents[eventIndex].attendees.removeAll { $0.id == attendeeID }
        calendarEvents[eventIndex].updatedAt = Date()
        let event = calendarEvents[eventIndex]
        guard await persistCalendarSnapshot() else {
            return
        }
        await recordAuditEvent(
            action: .calendarAttendeeRemoved,
            outcome: .succeeded,
            summary: "Removed calendar event attendee",
            metadata: calendarAttendeeAuditMetadata(event: event, attendee: attendee)
        )
    }

    func calendarEvents(in range: ClosedRange<Date>, calendarIDs: Set<String>? = nil) -> [AppCalendarEvent] {
        CalendarRecurrenceService().occurrences(
            of: calendarSourceEvents(),
            in: range,
            calendarIDs: calendarIDs
        )
    }

    func filteredCalendarEvents(in range: ClosedRange<Date>, calendarIDs: Set<String>? = nil) -> [AppCalendarEvent] {
        let query = parsedCalendarSearchQuery()
        return calendarEvents(in: range, calendarIDs: calendarIDs)
            .filter { calendarEventMatchesSearch($0, query: query) }
    }

    func calendarRemindersDue(in range: ClosedRange<Date>) -> [AppCalendarReminder] {
        let reminderEvents = calendarSourceEvents()
            .filter { !$0.isCancelled && $0.reminderMinutesBefore != nil }
        let maxLeadMinutes = reminderEvents.compactMap(\.reminderMinutesBefore).max() ?? 0
        let maxLeadSeconds = TimeInterval(maxLeadMinutes * 60)
        let occurrenceRange = range.lowerBound.addingTimeInterval(maxLeadSeconds)...range.upperBound.addingTimeInterval(maxLeadSeconds)

        return CalendarRecurrenceService().occurrences(of: reminderEvents, in: occurrenceRange)
            .compactMap { event in
                guard let minutes = event.reminderMinutesBefore, !event.isCancelled else {
                    return nil
                }
                let reminderAt = event.startAt.addingTimeInterval(-TimeInterval(minutes * 60))
                guard range.contains(reminderAt) else {
                    return nil
                }
                return AppCalendarReminder(event: event, reminderAt: reminderAt)
            }
            .sorted { lhs, rhs in
                if lhs.reminderAt != rhs.reminderAt {
                    return lhs.reminderAt < rhs.reminderAt
                }
                return lhs.event.startAt < rhs.event.startAt
            }
    }

    func deliverDueCalendarReminders(in range: ClosedRange<Date>) async {
        guard requireCalendarFeatureEnabled() else {
            return
        }

        let dueReminders = calendarRemindersDue(in: range)
        let notificationRequests = calendarReminderNotificationService
            .requests(for: dueReminders, calendars: visibleCalendars)
            .filter { !deliveredCalendarReminderIDs.contains($0.id) }

        guard !notificationRequests.isEmpty else {
            return
        }

        do {
            try await calendarReminderDeliverer.deliver(notificationRequests)
            deliveredCalendarReminderIDs.formUnion(notificationRequests.map(\.id))
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func startCalendarReminderScheduler(
        intervalNanoseconds: UInt64 = 60_000_000_000,
        lookAheadSeconds: TimeInterval = 60
    ) {
        guard isFeatureEnabled(.calendar) else {
            return
        }
        guard calendarReminderSchedulerTask == nil else {
            return
        }

        isCalendarReminderSchedulerRunning = true
        calendarReminderSchedulerTask = Task { [weak self] in
            while !Task.isCancelled {
                let now = Date()
                await self?.deliverDueCalendarReminders(
                    in: now...now.addingTimeInterval(lookAheadSeconds)
                )
                do {
                    try await Task.sleep(nanoseconds: intervalNanoseconds)
                } catch {
                    break
                }
            }
            await MainActor.run {
                self?.calendarReminderSchedulerTask = nil
                self?.isCalendarReminderSchedulerRunning = false
            }
        }
    }

    func stopCalendarReminderScheduler() {
        calendarReminderSchedulerTask?.cancel()
        calendarReminderSchedulerTask = nil
        isCalendarReminderSchedulerRunning = false
    }

    func selectCalendarDashboard() {
        selectedThreadID = nil
        selectedChannelID = nil
        clearSelectedKnowledgeDocument()
        isShowingEvaluationDashboard = false
        isShowingAnalyticsDashboard = false
        isShowingPlayground = false
        isShowingFiles = false
        isShowingCalendar = true
        isShowingImageGeneration = false
        isShowingAudio = false
        isShowingCodeInterpreter = false
        isShowingTerminalSessions = false
    }

    func exportCalendarJSONData() throws -> Data {
        try calendarExportService.jsonData(for: CalendarSnapshot(calendars: calendars, events: calendarEvents))
    }

    func exportCalendarOpenWebUIJSONData() throws -> Data {
        try calendarExportService.openWebUIJSONData(for: CalendarSnapshot(calendars: calendars, events: calendarEvents))
    }

    func exportCalendarEventJSONData(_ eventID: String) throws -> Data? {
        guard let event = calendarEvents.first(where: { $0.id == eventID }),
              let calendar = calendars.first(where: { $0.id == event.calendarID }) else {
            return nil
        }

        return try calendarExportService.jsonData(for: CalendarSnapshot(calendars: [calendar], events: [event]))
    }

    func shareCalendarEvent(_ eventID: String) {
        guard requireCalendarFeatureEnabled() else {
            return
        }
        guard let event = calendarEvents.first(where: { $0.id == eventID }),
              let calendar = calendars.first(where: { $0.id == event.calendarID }) else {
            return
        }

        do {
            let data = try calendarExportService.jsonData(for: CalendarSnapshot(calendars: [calendar], events: [event]))
            guard let json = String(data: data, encoding: .utf8) else {
                errorMessage = "The selected calendar event could not be encoded for sharing."
                return
            }
            shareService.share(text: json, title: event.title)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func exportCalendarJSONWithSavePanel() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "open-webui-native-calendar.json"
        panel.canCreateDirectories = true
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else {
                return
            }
            Task { @MainActor in
                do {
                    let data = try self?.exportCalendarJSONData()
                    try data?.write(to: url, options: [.atomic])
                } catch {
                    self?.errorMessage = error.localizedDescription
                }
            }
        }
    }

    func exportCalendarOpenWebUIJSONWithSavePanel() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "open-webui-calendar.json"
        panel.canCreateDirectories = true
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else {
                return
            }
            Task { @MainActor in
                do {
                    let data = try self?.exportCalendarOpenWebUIJSONData()
                    try data?.write(to: url, options: [.atomic])
                } catch {
                    self?.errorMessage = error.localizedDescription
                }
            }
        }
    }

    func importCalendarJSONData(_ data: Data) async throws {
        guard requireCalendarFeatureEnabled() else {
            return
        }
        guard requireCalendarWritePermission() else {
            return
        }

        let importedSnapshot = try calendarExportService.snapshot(fromJSONData: data)
        for calendar in importedSnapshot.calendars {
            calendars.removeAll { $0.id == calendar.id }
            calendars.append(calendar)
        }
        for event in importedSnapshot.events {
            calendarEvents.removeAll { $0.id == event.id }
            calendarEvents.append(event)
        }
        if selectedCalendarID == nil || !calendars.contains(where: { $0.id == selectedCalendarID }) {
            selectedCalendarID = calendars.first(where: \.isDefault)?.id ?? calendars.first?.id
        }
        await persistCalendarSnapshot()
    }

    func importCalendarJSON(from url: URL) async {
        guard requireCalendarFeatureEnabled() else {
            return
        }
        guard requireCalendarWritePermission() else {
            return
        }

        let didStartAccessing = url.startAccessingSecurityScopedResource()
        defer {
            if didStartAccessing {
                url.stopAccessingSecurityScopedResource()
            }
        }

        do {
            let data = try Data(contentsOf: url)
            try await importCalendarJSONData(data)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func importCalendarJSONWithOpenPanel() {
        guard requireCalendarFeatureEnabled() else {
            return
        }
        guard requireCalendarWritePermission() else {
            return
        }

        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.begin { [weak self] response in
            guard response == .OK else {
                return
            }
            let urls = panel.urls
            Task { @MainActor in
                for url in urls {
                    await self?.importCalendarJSON(from: url)
                }
            }
        }
    }

    func createNote(title: String, content: String) async {
        guard requireNotesFeatureEnabled() else {
            return
        }
        guard requireNoteWritePermission() else {
            return
        }

        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedContent = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty, !trimmedContent.isEmpty else {
            return
        }

        let note = AppNote(title: trimmedTitle, content: trimmedContent)

        do {
            try await noteStorage.save(note)
            notes.append(note)
            sortNotes()
            await recordAuditEvent(
                action: .noteCreated,
                outcome: .succeeded,
                summary: "Created note",
                metadata: noteAuditMetadata(for: note)
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func updateNote(_ noteID: UUID, title: String, content: String) async {
        guard requireNotesFeatureEnabled() else {
            return
        }
        guard requireNoteWritePermission() else {
            return
        }

        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedContent = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty, !trimmedContent.isEmpty,
              let index = notes.firstIndex(where: { $0.id == noteID }) else {
            return
        }

        notes[index].title = trimmedTitle
        notes[index].content = trimmedContent
        notes[index].updatedAt = Date()

        do {
            try await noteStorage.save(notes[index])
            let updatedNote = notes[index]
            sortNotes()
            await recordAuditEvent(
                action: .noteUpdated,
                outcome: .succeeded,
                summary: "Updated note",
                metadata: noteAuditMetadata(for: updatedNote)
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func toggleNotePinned(_ noteID: UUID) async {
        guard requireNotesFeatureEnabled() else {
            return
        }
        guard requireNoteWritePermission() else {
            return
        }

        guard let index = notes.firstIndex(where: { $0.id == noteID }) else {
            return
        }

        let previousIsPinned = notes[index].isPinned
        notes[index].isPinned.toggle()

        do {
            try await noteStorage.save(notes[index])
            let updatedNote = notes[index]
            sortNotes()
            var metadata = noteAuditMetadata(for: updatedNote)
            metadata["previousIsPinned"] = String(previousIsPinned)
            await recordAuditEvent(
                action: .notePinUpdated,
                outcome: .succeeded,
                summary: "Updated note pin state",
                metadata: metadata
            )
        } catch {
            notes[index].isPinned.toggle()
            errorMessage = error.localizedDescription
        }
    }

    func deleteNote(_ noteID: UUID) async {
        guard requireNotesFeatureEnabled() else {
            return
        }
        guard requireNoteWritePermission() else {
            return
        }

        do {
            guard let note = notes.first(where: { $0.id == noteID }) else {
                return
            }
            try await noteStorage.deleteNote(id: noteID)
            notes.removeAll { $0.id == noteID }
            await recordAuditEvent(
                action: .noteDeleted,
                outcome: .succeeded,
                summary: "Deleted note",
                metadata: noteAuditMetadata(for: note)
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func noteLink(for noteID: UUID) -> URL? {
        notes.first { $0.id == noteID }?.deepLinkURL
    }

    @discardableResult
    func resolveNoteLink(_ url: URL) -> AppNote? {
        guard let noteID = AppNote.noteID(fromDeepLink: url),
              let note = notes.first(where: { $0.id == noteID }) else {
            return nil
        }
        focusedNoteID = note.id
        noteSearchText = note.title
        return note
    }

    func copyNoteLink(_ noteID: UUID) {
        guard let url = noteLink(for: noteID) else {
            return
        }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(url.absoluteString, forType: .string)
        focusedNoteID = noteID
    }

    func shareNote(_ noteID: UUID) {
        guard requireNotesFeatureEnabled() else {
            return
        }
        guard let note = notes.first(where: { $0.id == noteID }) else {
            return
        }
        shareService.share(text: "# \(note.title)\n\n\(note.content)", title: note.title)
    }

    func exportNotesJSONData() throws -> Data {
        try noteExportService.jsonData(for: notes)
    }

    func exportNotesOpenWebUIJSONData() throws -> Data {
        try noteExportService.openWebUIJSONData(for: notes)
    }

    func exportNotesJSONWithSavePanel() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "open-webui-native-notes.json"
        panel.canCreateDirectories = true
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else {
                return
            }
            Task { @MainActor in
                do {
                    let data = try self?.exportNotesJSONData()
                    try data?.write(to: url, options: [.atomic])
                } catch {
                    self?.errorMessage = error.localizedDescription
                }
            }
        }
    }

    func exportNotesOpenWebUIJSONWithSavePanel() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "open-webui-notes.json"
        panel.canCreateDirectories = true
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else {
                return
            }
            Task { @MainActor in
                do {
                    let data = try self?.exportNotesOpenWebUIJSONData()
                    try data?.write(to: url, options: [.atomic])
                } catch {
                    self?.errorMessage = error.localizedDescription
                }
            }
        }
    }

    func importNotesJSONData(_ data: Data) async throws {
        guard requireNotesFeatureEnabled() else {
            return
        }
        guard requireNoteWritePermission() else {
            return
        }

        let importedNotes = try noteExportService.notes(fromJSONData: data)
        for note in importedNotes {
            try await noteStorage.save(note)
            notes.removeAll { $0.id == note.id }
            notes.append(note)
        }
        sortNotes()
    }

    func importNotesJSON(from url: URL) async {
        guard requireNotesFeatureEnabled() else {
            return
        }
        guard requireNoteWritePermission() else {
            return
        }

        let didStartAccessing = url.startAccessingSecurityScopedResource()
        defer {
            if didStartAccessing {
                url.stopAccessingSecurityScopedResource()
            }
        }

        do {
            let data = try Data(contentsOf: url)
            try await importNotesJSONData(data)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func importNotesJSONWithOpenPanel() {
        guard requireNotesFeatureEnabled() else {
            return
        }
        guard requireNoteWritePermission() else {
            return
        }

        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.begin { [weak self] response in
            guard response == .OK else {
                return
            }
            let urls = panel.urls
            Task { @MainActor in
                for url in urls {
                    await self?.importNotesJSON(from: url)
                }
            }
        }
    }

    func assignThread(_ threadID: UUID, toFolder folderID: UUID?) async {
        guard requireFoldersFeatureEnabled() else {
            return
        }

        guard let index = threads.firstIndex(where: { $0.id == threadID }) else {
            return
        }
        threads[index].folderID = folderID
        threads[index].updatedAt = Date()

        do {
            try await storage.save(threads[index])
            sortThreads()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func toggleThreadPinned(_ threadID: UUID) async {
        guard let index = threads.firstIndex(where: { $0.id == threadID }) else {
            return
        }

        threads[index].isPinned.toggle()

        do {
            try await storage.save(threads[index])
            sortThreads()
        } catch {
            threads[index].isPinned.toggle()
            errorMessage = error.localizedDescription
        }
    }

    func addTag(_ rawTag: String, to threadID: UUID) async {
        guard let tag = normalizedTag(rawTag),
              let index = threads.firstIndex(where: { $0.id == threadID }) else {
            return
        }

        if !threads[index].tags.contains(tag) {
            threads[index].tags.append(tag)
            threads[index].tags.sort()
            threads[index].updatedAt = Date()
            await persistThread(at: index)
        }
    }

    func removeTag(_ rawTag: String, from threadID: UUID) async {
        guard let tag = normalizedTag(rawTag),
              let index = threads.firstIndex(where: { $0.id == threadID }) else {
            return
        }

        threads[index].tags.removeAll { $0 == tag }
        threads[index].updatedAt = Date()
        await persistThread(at: index)
    }

    func filteredThreads(folderID: UUID? = nil) -> [ChatThread] {
        let query = parsedSidebarSearchQuery()
        let scoped = threads.filter { thread in
            if let isArchived = query.isArchived, thread.isArchived != isArchived {
                return false
            }
            if let isPinned = query.isPinned, thread.isPinned != isPinned {
                return false
            }
            guard threadMatchesSearchOperators(thread, query: query) else {
                return false
            }
            guard !thread.isArchived else {
                return false
            }
            if let folderID {
                return thread.folderID == folderID
            }
            return thread.folderID == nil
        }

        guard !query.text.isEmpty else {
            return scoped
        }

        return scoped.filter { thread in
            searchableText(for: thread).contains(query.text)
        }
    }

    func filteredArchivedThreads() -> [ChatThread] {
        let query = parsedSidebarSearchQuery()
        let archived = threads
            .filter { thread in
                if let isArchived = query.isArchived, thread.isArchived != isArchived {
                    return false
                }
                if let isPinned = query.isPinned, thread.isPinned != isPinned {
                    return false
                }
                guard threadMatchesSearchOperators(thread, query: query) else {
                    return false
                }
                return thread.isArchived
            }
            .sorted { $0.updatedAt > $1.updatedAt }
        guard !query.text.isEmpty else {
            return archived
        }

        return archived.filter { thread in
            searchableText(for: thread).contains(query.text)
        }
    }

    func chatLink(for threadID: UUID) -> URL? {
        threads.first { $0.id == threadID }?.deepLinkURL
    }

    func messageLink(for messageID: UUID) -> URL? {
        guard let thread = threads.first(where: { thread in
            thread.messages.contains { $0.id == messageID }
        }) else {
            return nil
        }
        return thread.deepLinkURL(forMessageID: messageID)
    }

    @discardableResult
    func resolveChatLink(_ url: URL) -> ChatThread? {
        guard let target = ChatThread.deepLinkTarget(fromDeepLink: url),
              let thread = threads.first(where: { $0.id == target.threadID }) else {
            return nil
        }
        if let messageID = target.messageID,
           !thread.messages.contains(where: { $0.id == messageID }) {
            return nil
        }
        selectedThreadID = thread.id
        focusedChatMessageID = target.messageID
        chatTranscriptSearchText = ""
        selectedChannelID = nil
        clearSelectedKnowledgeDocument()
        isShowingEvaluationDashboard = false
        isShowingAnalyticsDashboard = false
        isShowingPlayground = false
        isShowingFiles = false
        isShowingCalendar = false
        isShowingImageGeneration = false
        isShowingAudio = false
        isShowingCodeInterpreter = false
        isShowingTerminalSessions = false
        return thread
    }

    @discardableResult
    func handleAppURL(_ url: URL) -> Bool {
        if resolveChatLink(url) != nil {
            return true
        }
        if resolveNoteLink(url) != nil {
            return true
        }
        return false
    }

    func copyChatLink(_ threadID: UUID) {
        guard let url = chatLink(for: threadID) else {
            return
        }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(url.absoluteString, forType: .string)
    }

    func copyMessageLink(_ messageID: UUID) {
        guard let url = messageLink(for: messageID) else {
            return
        }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(url.absoluteString, forType: .string)
    }

    func copySelectedThreadLink() {
        guard let selectedThreadID else {
            return
        }
        copyChatLink(selectedThreadID)
    }

    func selectChatSearchResult(_ result: ChatSearchResult) {
        selectedThreadID = result.threadID
        focusedChatMessageID = result.messageID
        chatTranscriptSearchText = ""
        selectedChannelID = nil
        clearSelectedKnowledgeDocument()
        isShowingEvaluationDashboard = false
        isShowingAnalyticsDashboard = false
        isShowingPlayground = false
        isShowingFiles = false
        isShowingCalendar = false
        isShowingImageGeneration = false
        isShowingAudio = false
        isShowingCodeInterpreter = false
        isShowingTerminalSessions = false
    }

    func toggleThreadArchived(_ threadID: UUID) async {
        guard let index = threads.firstIndex(where: { $0.id == threadID }) else {
            return
        }

        threads[index].isArchived.toggle()

        do {
            try await storage.save(threads[index])
            sortThreads()
            if selectedThreadID == threadID,
               threads.first(where: { $0.id == threadID })?.isArchived == true {
                selectedThreadID = firstVisibleThreadID()
            }
        } catch {
            threads[index].isArchived.toggle()
            errorMessage = error.localizedDescription
        }
    }

    func unarchiveAllArchivedThreads() async {
        let archivedIndices = threads.indices.filter { threads[$0].isArchived }
        guard !archivedIndices.isEmpty else {
            return
        }

        do {
            for index in archivedIndices {
                threads[index].isArchived = false
                try await storage.save(threads[index])
            }
            sortThreads()
            if selectedThreadID == nil {
                selectedThreadID = firstVisibleThreadID()
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func archiveAllThreads() async {
        let unarchivedIndices = threads.indices.filter { !threads[$0].isArchived }
        guard !unarchivedIndices.isEmpty else {
            return
        }

        do {
            for index in unarchivedIndices {
                threads[index].isArchived = true
                try await storage.save(threads[index])
            }
            sortThreads()
            if firstVisibleThreadID() == nil {
                selectedThreadID = nil
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func exportArchivedThreadsJSONData() throws -> Data {
        let archivedThreads = threads
            .filter(\.isArchived)
            .sorted { $0.updatedAt > $1.updatedAt }
        return try JSONEncoder.openWebUIEncoder.encode(archivedThreads)
    }

    func exportAllThreadsJSONData() throws -> Data {
        let allThreads = threads.sorted { $0.updatedAt > $1.updatedAt }
        return try JSONEncoder.openWebUIEncoder.encode(allThreads)
    }

    func exportAllThreadsOpenWebUIJSONData() throws -> Data {
        let allThreads = threads.sorted { $0.updatedAt > $1.updatedAt }
        return try exportService.openWebUIJSONData(for: allThreads)
    }

    func exportAllThreadsJSONWithSavePanel() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.canCreateDirectories = true
        let timestamp = Int(Date().timeIntervalSince1970 * 1000)
        panel.nameFieldStringValue = "chat-export-\(timestamp).json"
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else {
                return
            }
            Task { @MainActor in
                do {
                    let data = try self?.exportAllThreadsJSONData()
                    try data?.write(to: url, options: [.atomic])
                } catch {
                    self?.errorMessage = error.localizedDescription
                }
            }
        }
    }

    func exportAllThreadsOpenWebUIJSONWithSavePanel() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.canCreateDirectories = true
        let timestamp = Int(Date().timeIntervalSince1970 * 1000)
        panel.nameFieldStringValue = "chat-export-open-webui-\(timestamp).json"
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else {
                return
            }
            Task { @MainActor in
                do {
                    let data = try self?.exportAllThreadsOpenWebUIJSONData()
                    try data?.write(to: url, options: [.atomic])
                } catch {
                    self?.errorMessage = error.localizedDescription
                }
            }
        }
    }

    func exportArchivedThreadsJSONWithSavePanel() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = "archived-chats.json"
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else {
                return
            }
            Task { @MainActor in
                do {
                    let data = try self?.exportArchivedThreadsJSONData()
                    try data?.write(to: url, options: [.atomic])
                } catch {
                    self?.errorMessage = error.localizedDescription
                }
            }
        }
    }

    func cloneThread(_ threadID: UUID) async {
        guard let sourceThread = threads.first(where: { $0.id == threadID }) else {
            return
        }

        let now = Date()
        let clonedThread = ChatThread(
            title: "Clone of \(sourceThread.title)",
            createdAt: now,
            updatedAt: now,
            folderID: sourceThread.folderID,
            providerID: sourceThread.providerID,
            modelIDs: sourceThread.modelIDs,
            tags: sourceThread.tags,
            isPinned: sourceThread.isPinned,
            isArchived: false,
            messages: sourceThread.messages.map(clonedMessage(from:))
        )

        do {
            try await storage.save(clonedThread)
            threads.append(clonedThread)
            sortThreads()
            selectedThreadID = clonedThread.id
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func filteredNotes() -> [AppNote] {
        let query = noteSearchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else {
            return notes
        }

        return notes.filter { note in
            searchableText(for: note).contains(query)
        }
    }

    func filteredFiles() -> [AppFile] {
        let rawQuery = fileSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let query = rawQuery.lowercased()
        guard !query.isEmpty else {
            return files
        }

        if isWildcardFileSearch(rawQuery) {
            return files.filter { file in
                fileName(file.fileName, matchesWildcardPattern: rawQuery)
            }
        }

        return files.filter { file in
            [
                file.fileName,
                file.contentType,
                file.textContent
            ]
            .joined(separator: " ")
            .lowercased()
            .contains(query)
        }
    }

    private func isWildcardFileSearch(_ query: String) -> Bool {
        query.contains("*") || query.contains("?")
    }

    private func fileName(_ fileName: String, matchesWildcardPattern pattern: String) -> Bool {
        let regexPattern = "^" + pattern.reduce(into: "") { result, character in
            switch character {
            case "*":
                result += ".*"
            case "?":
                result += "."
            default:
                result += NSRegularExpression.escapedPattern(for: String(character))
            }
        } + "$"

        return fileName.range(
            of: regexPattern,
            options: [.regularExpression, .caseInsensitive]
        ) != nil
    }

    func filteredSkills() -> [AppSkill] {
        let query = parsedSkillSearchQuery()
        guard query.isActive != nil || !query.tags.isEmpty || !query.textTerms.isEmpty else {
            return skills
        }

        return skills.filter { skill in
            skillMatchesSearch(skill, query: query)
        }
    }

    func filteredChannels() -> [AppChannel] {
        let query = channelSearchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else {
            return channels
        }

        return channels.filter { channel in
            searchableText(for: channel).contains(query)
        }
    }

    func filteredAutomations() -> [AppAutomation] {
        let query = automationSearchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else {
            return automations
        }

        let terms = query.split(separator: " ").map(String.init)
        return automations.filter { automation in
            terms.allSatisfy { term in
                if let model = term.removingPrefix("model:") {
                    return automation.modelID.lowercased().contains(model)
                }
                if let status = term.removingPrefix("status:") {
                    switch status {
                    case "active", "enabled":
                        return automation.isActive
                    case "paused", "disabled":
                        return !automation.isActive
                    default:
                        return false
                    }
                }
                return searchableText(for: automation).contains(term)
            }
        }
    }

    func automationRuns(for automationID: String, limit: Int = 3) -> [AppAutomationRun] {
        Array(
            automationRuns
                .filter { $0.automationID == automationID }
                .sorted { $0.startedAt > $1.startedAt }
                .prefix(limit)
        )
    }

    func deleteSelectedThread() async {
        guard let selectedThreadID else {
            return
        }
        do {
            try await storage.deleteThread(id: selectedThreadID)
            threads.removeAll { $0.id == selectedThreadID }
            self.selectedThreadID = firstVisibleThreadID()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func deleteAllThreads() async {
        guard !threads.isEmpty else {
            return
        }

        do {
            for thread in threads {
                try await storage.deleteThread(id: thread.id)
            }
            threads.removeAll()
            selectedThreadID = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func renameThread(_ threadID: UUID, title: String) async {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty,
              let index = threads.firstIndex(where: { $0.id == threadID }) else {
            return
        }

        threads[index].title = trimmedTitle
        threads[index].updatedAt = Date()
        await persistThread(at: index)
    }

    func editMessage(id: UUID, content: String) async {
        guard let threadIndex = threadIndex(containing: id),
              let messageIndex = threads[threadIndex].messages.firstIndex(where: { $0.id == id }) else {
            return
        }
        let oldContent = threads[threadIndex].messages[messageIndex].content
        threads[threadIndex].messages[messageIndex].content = content
        threads[threadIndex].messages[messageIndex].updatedAt = Date()
        if threads[threadIndex].messages[messageIndex].originalContent == nil {
            threads[threadIndex].messages[messageIndex].originalContent = oldContent
        }
        threads[threadIndex].updatedAt = Date()
        await persistThread(at: threadIndex)
    }

    func rateMessage(id: UUID, rating: MessageRating?) async {
        guard let threadIndex = threadIndex(containing: id),
              let messageIndex = threads[threadIndex].messages.firstIndex(where: { $0.id == id }) else {
            return
        }
        threads[threadIndex].messages[messageIndex].rating = rating
        threads[threadIndex].messages[messageIndex].updatedAt = Date()
        threads[threadIndex].updatedAt = Date()
        await persistThread(at: threadIndex)
    }

    func copyMessageToPasteboard(id: UUID) {
        guard let message = selectedThread?.messages.first(where: { $0.id == id }) else {
            return
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(message.content, forType: .string)
    }

    func exportSelectedThreadAsMarkdownToPasteboard() {
        guard let selectedThread else {
            return
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(exportService.markdown(for: selectedThread), forType: .string)
    }

    func shareSelectedThreadAsMarkdown() {
        guard let selectedThread else {
            return
        }
        shareService.share(text: exportService.markdown(for: selectedThread), title: selectedThread.title)
    }

    func exportSelectedThreadJSONData() throws -> Data? {
        guard let selectedThread else {
            return nil
        }
        return try exportService.jsonData(for: selectedThread)
    }

    func exportSelectedThreadOpenWebUIJSONData() throws -> Data? {
        guard let selectedThread else {
            return nil
        }
        return try exportService.openWebUIJSONData(for: selectedThread)
    }

    func exportSelectedThreadJSONWithSavePanel() {
        guard let selectedThread else {
            return
        }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = "\(selectedThread.title).json"
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else {
                return
            }
            Task { @MainActor in
                do {
                    let data = try self?.exportService.jsonData(for: selectedThread)
                    try data?.write(to: url, options: [.atomic])
                } catch {
                    self?.errorMessage = error.localizedDescription
                }
            }
        }
    }

    func exportSelectedThreadOpenWebUIJSONWithSavePanel() {
        guard let selectedThread else {
            return
        }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = "\(selectedThread.title)-open-webui.json"
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else {
                return
            }
            Task { @MainActor in
                do {
                    let data = try self?.exportService.openWebUIJSONData(for: selectedThread)
                    try data?.write(to: url, options: [.atomic])
                } catch {
                    self?.errorMessage = error.localizedDescription
                }
            }
        }
    }

    func importChatThreadJSON(from url: URL) async {
        let didStartAccessing = url.startAccessingSecurityScopedResource()
        defer {
            if didStartAccessing {
                url.stopAccessingSecurityScopedResource()
            }
        }

        do {
            let data = try Data(contentsOf: url)
            var importedThread = try exportService.thread(fromJSONData: data)
            importedThread.updatedAt = Date()
            try await storage.save(importedThread)
            threads.removeAll { $0.id == importedThread.id }
            threads.insert(importedThread, at: 0)
            sortThreads()
            selectedThreadID = importedThread.id
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func importChatThreadsJSON(from url: URL) async {
        let didStartAccessing = url.startAccessingSecurityScopedResource()
        defer {
            if didStartAccessing {
                url.stopAccessingSecurityScopedResource()
            }
        }

        do {
            let data = try Data(contentsOf: url)
            let importedThreads = try exportService.threads(fromJSONData: data)
                .map(freshImportedThread(from:))
            for thread in importedThreads {
                try await storage.save(thread)
            }
            threads.append(contentsOf: importedThreads)
            sortThreads()
            selectedThreadID = importedThreads
                .filter { !$0.isArchived }
                .sorted { $0.updatedAt > $1.updatedAt }
                .first?.id ?? firstVisibleThreadID()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func importChatThreadJSONWithOpenPanel() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.begin { [weak self] response in
            guard response == .OK else {
                return
            }
            let urls = panel.urls
            Task { @MainActor in
                for url in urls {
                    await self?.importChatThreadJSON(from: url)
                }
            }
        }
    }

    func importChatThreadsJSONWithOpenPanel() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.begin { [weak self] response in
            guard response == .OK else {
                return
            }
            let urls = panel.urls
            Task { @MainActor in
                for url in urls {
                    await self?.importChatThreadsJSON(from: url)
                }
            }
        }
    }

    func regenerateResponse(messageID: UUID) async {
        guard let originalThreadIndex = threadIndex(containing: messageID),
              let messageIndex = threads[originalThreadIndex].messages.firstIndex(where: { $0.id == messageID }),
              threads[originalThreadIndex].messages[messageIndex].role == .assistant else {
            return
        }

        let modelID = threads[originalThreadIndex].messages[messageIndex].modelID
            ?? selectedModelID
            ?? threads[originalThreadIndex].modelIDs.first
        guard let modelID else {
            errorMessage = ProviderError.noModelSelected.localizedDescription
            return
        }

        guard canChat else {
            errorMessage = ProviderError.unsupportedChat(activeProvider.name).localizedDescription
            return
        }

        threads[originalThreadIndex].messages[messageIndex].content = ""
        threads[originalThreadIndex].messages[messageIndex].error = nil
        threads[originalThreadIndex].messages[messageIndex].isStreaming = true
        threads[originalThreadIndex].messages[messageIndex].generationMetrics = ChatGenerationMetrics()
        threads[originalThreadIndex].messages[messageIndex].tokenUsage = nil
        threads[originalThreadIndex].messages[messageIndex].updatedAt = Date()
        threads[originalThreadIndex].updatedAt = Date()
        await persistThread(at: originalThreadIndex)

        do {
            let provider = try makeActiveProvider()
            let providerMessages = providerMessages(
                for: threads[originalThreadIndex],
                throughMessageID: messageID,
                excludingMessageID: messageID
            )

            for try await event in provider.streamChatEvents(model: modelID, messages: providerMessages) {
                guard let currentThreadIndex = self.threadIndex(containing: messageID),
                      let currentMessageIndex = threads[currentThreadIndex].messages.firstIndex(where: { $0.id == messageID }) else {
                    continue
                }
                switch event {
                case .content(let chunk):
                    threads[currentThreadIndex].messages[currentMessageIndex].content += chunk
                case .tokenUsage(let tokenUsage):
                    threads[currentThreadIndex].messages[currentMessageIndex].tokenUsage = tokenUsage
                }
                threads[currentThreadIndex].updatedAt = Date()
            }

            finishAssistantMessage(id: messageID, error: nil)
        } catch {
            finishAssistantMessage(id: messageID, error: error.localizedDescription)
            errorMessage = error.localizedDescription
        }

        if let currentThreadIndex = threadIndex(containing: messageID) {
            await persistThread(at: currentThreadIndex)
        }
    }

    func sendDraftPrompt() async {
        let trimmedPrompt = draftPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        if let savedPrompt = prompt(matchingCommand: trimmedPrompt) {
            let variables = promptVariableResolver.variables(in: savedPrompt.content)
            guard variables.isEmpty else {
                errorMessage = "Prompt command \(savedPrompt.command ?? trimmedPrompt) requires variable values. Insert it from the prompt library."
                return
            }

            draftPrompt = ""
            insertPrompt(savedPrompt.id)
            return
        }
        draftPrompt = ""
        await send(trimmedPrompt)
    }

    func importAttachment(from url: URL) async throws {
        let didStartAccessing = url.startAccessingSecurityScopedResource()
        defer {
            if didStartAccessing {
                url.stopAccessingSecurityScopedResource()
            }
        }

        let document = try readImportedDocument(from: url, requiresExtractedText: true)
        let file = AppFile(
            fileName: document.fileName,
            contentType: document.contentType,
            byteCount: document.byteCount,
            textContent: document.text,
            originalData: document.originalData
        )
        try await saveFile(file)
        pendingAttachments.append(file.chatAttachment)
    }

    func importFileToLibrary(from url: URL) async throws {
        guard requireFilesFeatureEnabled() else {
            return
        }

        let didStartAccessing = url.startAccessingSecurityScopedResource()
        defer {
            if didStartAccessing {
                url.stopAccessingSecurityScopedResource()
            }
        }

        let document = try readImportedDocument(from: url, requiresExtractedText: false)
        let file = AppFile(
            fileName: document.fileName,
            contentType: document.contentType,
            byteCount: document.byteCount,
            textContent: document.text,
            originalData: document.originalData
        )
        try await saveFile(file)
    }

    func attachFileToChatContext(_ fileID: UUID) {
        guard requireFilesFeatureEnabled() else {
            return
        }
        guard let file = files.first(where: { $0.id == fileID }) else {
            errorMessage = "The selected file could not be found."
            return
        }
        guard !file.textContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            errorMessage = "This saved file has no extracted text to attach to chat."
            return
        }

        pendingAttachments.append(file.chatAttachment)
    }

    func deleteFile(_ fileID: UUID) async {
        guard requireFilesFeatureEnabled() else {
            return
        }

        do {
            try await fileStorage.deleteFile(id: fileID)
            files.removeAll { $0.id == fileID }
            pendingAttachments.removeAll { $0.id == fileID }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func deleteAllFiles() async {
        guard requireFilesFeatureEnabled() else {
            return
        }

        do {
            let persistedFiles = try await fileStorage.loadFiles()
            let fileIDs = Set((files + persistedFiles).map(\.id))
            guard !fileIDs.isEmpty else {
                return
            }

            try await fileStorage.replaceFiles([])
            files.removeAll { fileIDs.contains($0.id) }
            pendingAttachments.removeAll { fileIDs.contains($0.id) }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func renameFile(_ fileID: UUID, fileName: String) async {
        guard requireFilesFeatureEnabled() else {
            return
        }

        let trimmedName = fileName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            errorMessage = "File name cannot be empty."
            return
        }
        guard let index = files.firstIndex(where: { $0.id == fileID }) else {
            errorMessage = "The selected file could not be found."
            return
        }

        var file = files[index]
        file.fileName = trimmedName
        file.updatedAt = Date()

        do {
            try await saveFile(file)
            for attachmentIndex in pendingAttachments.indices where pendingAttachments[attachmentIndex].id == fileID {
                pendingAttachments[attachmentIndex] = file.chatAttachment
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func updateFileContent(_ fileID: UUID, textContent: String) async {
        guard requireFilesFeatureEnabled() else {
            return
        }

        guard let index = files.firstIndex(where: { $0.id == fileID }) else {
            errorMessage = "The selected file could not be found."
            return
        }

        var file = files[index]
        file.textContent = textContent
        file.byteCount = Data(textContent.utf8).count
        file.updatedAt = Date()

        do {
            try await saveFile(file)
            for attachmentIndex in pendingAttachments.indices where pendingAttachments[attachmentIndex].id == fileID {
                pendingAttachments[attachmentIndex] = file.chatAttachment
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func shareFile(_ fileID: UUID) {
        guard requireFilesFeatureEnabled() else {
            return
        }
        guard let file = files.first(where: { $0.id == fileID }) else {
            errorMessage = "The selected file could not be found."
            return
        }
        guard !file.textContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            shareOriginalFile(file)
            return
        }

        shareService.share(text: file.textContent, title: file.fileName)
    }

    func copyFileText(_ fileID: UUID) {
        guard requireFilesFeatureEnabled() else {
            return
        }
        guard let file = files.first(where: { $0.id == fileID }) else {
            errorMessage = "The selected file could not be found."
            return
        }

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(file.textContent, forType: .string)
    }

    func exportFileTextData(_ fileID: UUID) throws -> Data {
        guard let file = files.first(where: { $0.id == fileID }) else {
            throw AppStoreMessageError(message: "The selected file could not be found.")
        }

        return Data(file.textContent.utf8)
    }

    private func shareOriginalFile(_ file: AppFile) {
        guard let originalData = file.originalData else {
            errorMessage = "Original file data is not available for this saved file."
            return
        }

        do {
            let url = try temporaryShareURL(for: file)
            try originalData.write(to: url, options: [.atomic])
            shareService.share(fileURL: url, title: file.fileName)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func exportOriginalFileData(_ fileID: UUID) throws -> Data {
        guard let file = files.first(where: { $0.id == fileID }) else {
            throw AppStoreMessageError(message: "The selected file could not be found.")
        }
        guard let originalData = file.originalData else {
            throw AppStoreMessageError(message: "Original file data is not available for this saved file.")
        }

        return originalData
    }

    func exportFilesJSONData() throws -> Data {
        try fileExportService.jsonData(for: files)
    }

    func exportFilesOpenWebUIJSONData() throws -> Data {
        try fileExportService.openWebUIJSONData(for: files, userID: currentUserID)
    }

    func importFilesJSONData(_ data: Data) async throws {
        guard requireFilesFeatureEnabled() else {
            return
        }
        let importedFiles = try fileExportService.files(fromJSONData: data)
        for file in importedFiles {
            try await saveFile(file)
            for attachmentIndex in pendingAttachments.indices where pendingAttachments[attachmentIndex].id == file.id {
                pendingAttachments[attachmentIndex] = file.chatAttachment
            }
        }
    }

    func exportOriginalFileWithSavePanel(_ fileID: UUID) {
        guard let file = files.first(where: { $0.id == fileID }) else {
            errorMessage = "The selected file could not be found."
            return
        }
        guard file.originalData != nil else {
            errorMessage = "Original file data is not available for this saved file."
            return
        }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [fileUTType(for: file)]
        panel.nameFieldStringValue = file.fileName
        panel.canCreateDirectories = true
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else {
                return
            }
            Task { @MainActor in
                do {
                    let data = try self?.exportOriginalFileData(fileID)
                    try data?.write(to: url, options: [.atomic])
                } catch {
                    self?.errorMessage = error.localizedDescription
                }
            }
        }
    }

    func exportFileTextWithSavePanel(_ fileID: UUID) {
        guard let file = files.first(where: { $0.id == fileID }) else {
            errorMessage = "The selected file could not be found."
            return
        }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText, .text, .sourceCode, UTType(filenameExtension: "md") ?? .plainText]
        panel.nameFieldStringValue = file.fileName
        panel.canCreateDirectories = true
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else {
                return
            }
            Task { @MainActor in
                do {
                    let data = try self?.exportFileTextData(fileID)
                    try data?.write(to: url, options: [.atomic])
                } catch {
                    self?.errorMessage = error.localizedDescription
                }
            }
        }
    }

    func exportFilesJSONWithSavePanel() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "open-webui-native-files.json"
        panel.canCreateDirectories = true
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else {
                return
            }
            Task { @MainActor in
                do {
                    let data = try self?.exportFilesJSONData()
                    try data?.write(to: url, options: [.atomic])
                } catch {
                    self?.errorMessage = error.localizedDescription
                }
            }
        }
    }

    func exportFilesOpenWebUIJSONWithSavePanel() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "open-webui-files.json"
        panel.canCreateDirectories = true
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else {
                return
            }
            Task { @MainActor in
                do {
                    let data = try self?.exportFilesOpenWebUIJSONData()
                    try data?.write(to: url, options: [.atomic])
                } catch {
                    self?.errorMessage = error.localizedDescription
                }
            }
        }
    }

    func importFilesJSON(from url: URL) async {
        guard requireFilesFeatureEnabled() else {
            return
        }

        let didStartAccessing = url.startAccessingSecurityScopedResource()
        defer {
            if didStartAccessing {
                url.stopAccessingSecurityScopedResource()
            }
        }

        do {
            let data = try Data(contentsOf: url)
            try await importFilesJSONData(data)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func importFilesJSONWithOpenPanel() {
        guard requireFilesFeatureEnabled() else {
            return
        }

        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else {
                return
            }
            Task { @MainActor in
                await self?.importFilesJSON(from: url)
            }
        }
    }

    private func saveFile(_ file: AppFile) async throws {
        try await fileStorage.save(file)
        files.removeAll { $0.id == file.id }
        files.append(file)
        sortFiles()
    }

    func attachNoteToChatContext(_ noteID: UUID) {
        guard requireNotesFeatureEnabled() else {
            return
        }
        guard let note = notes.first(where: { $0.id == noteID }) else {
            errorMessage = "The selected note could not be found."
            return
        }

        pendingAttachments.append(
            ChatAttachment(
                fileName: noteAttachmentFileName(for: note.title),
                contentType: "text/markdown",
                byteCount: Data(note.content.utf8).count,
                textContent: note.content
            )
        )
    }

    func removePendingAttachment(id: UUID) {
        pendingAttachments.removeAll { $0.id == id }
    }

    func loadKnowledgeCollections() async {
        do {
            try await refreshKnowledgeState()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func createKnowledgeCollection(
        named name: String,
        allowedUserIDs: [String] = [],
        allowedGroupIDs: [String] = []
    ) async {
        guard requireKnowledgeFeatureEnabled() else {
            return
        }
        guard requireKnowledgeWritePermission() else {
            return
        }

        do {
            _ = try await knowledgeService.createCollection(
                named: name,
                allowedUserIDs: allowedUserIDs,
                allowedGroupIDs: allowedGroupIDs
            )
            try await refreshKnowledgeState()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func updateKnowledgeCollection(
        _ collectionID: UUID,
        name: String,
        allowedUserIDs: [String]? = nil,
        allowedGroupIDs: [String]? = nil
    ) async {
        guard requireKnowledgeFeatureEnabled() else {
            return
        }
        guard requireKnowledgeWritePermission() else {
            return
        }

        do {
            _ = try await knowledgeService.updateCollection(
                id: collectionID,
                name: name,
                allowedUserIDs: allowedUserIDs,
                allowedGroupIDs: allowedGroupIDs
            )
            if selectedKnowledgeDocumentDetail?.collection.id == collectionID,
               let documentID = selectedKnowledgeDocumentDetail?.document.id {
                let detail = try await knowledgeService.loadDocumentDetail(id: documentID)
                selectedKnowledgeDocumentDetail = currentUserCanAccessKnowledgeCollection(detail.collection) ? detail : nil
                if selectedKnowledgeDocumentDetail == nil {
                    selectedKnowledgeChunkID = nil
                }
            }
            try await refreshKnowledgeState()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func importKnowledgeDocument(from url: URL, toCollectionID collectionID: UUID) async {
        guard requireKnowledgeFeatureEnabled() else {
            return
        }
        guard requireKnowledgeWritePermission() else {
            return
        }
        guard canCreateEmbeddings else {
            errorMessage = ProviderError.unsupportedEmbeddings(activeProvider.name).localizedDescription
            return
        }
        guard let embeddingModel = selectedEmbeddingModelID else {
            errorMessage = ProviderError.noModelSelected.localizedDescription
            return
        }

        do {
            let document = try readImportedDocument(from: url, requiresExtractedText: true)
            let provider = try makeActiveProvider()
            try await knowledgeService.importTextDocument(
                collectionID: collectionID,
                fileName: document.fileName,
                contentType: document.contentType,
                text: document.text,
                embeddingModel: embeddingModel,
                provider: provider,
                sourceKind: document.sourceKind
            )
            try await refreshKnowledgeState()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func importNoteToKnowledge(_ noteID: UUID, toCollectionID collectionID: UUID) async {
        guard requireNotesFeatureEnabled() else {
            return
        }
        guard requireKnowledgeFeatureEnabled() else {
            return
        }
        guard requireKnowledgeWritePermission() else {
            return
        }
        guard canCreateEmbeddings else {
            errorMessage = ProviderError.unsupportedEmbeddings(activeProvider.name).localizedDescription
            return
        }
        guard let embeddingModel = selectedEmbeddingModelID else {
            errorMessage = ProviderError.noModelSelected.localizedDescription
            return
        }
        guard let note = notes.first(where: { $0.id == noteID }) else {
            errorMessage = "The selected note could not be found."
            return
        }

        do {
            let provider = try makeActiveProvider()
            try await knowledgeService.importTextDocument(
                collectionID: collectionID,
                fileName: noteAttachmentFileName(for: note.title),
                contentType: "text/markdown",
                text: note.content,
                embeddingModel: embeddingModel,
                provider: provider,
                sourceKind: .nativeNote
            )
            try await refreshKnowledgeState()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func reindexKnowledgeDocument(from url: URL, toCollectionID collectionID: UUID) async {
        guard requireKnowledgeFeatureEnabled() else {
            return
        }
        guard requireKnowledgeWritePermission() else {
            return
        }
        guard canCreateEmbeddings else {
            errorMessage = ProviderError.unsupportedEmbeddings(activeProvider.name).localizedDescription
            return
        }
        guard let embeddingModel = selectedEmbeddingModelID else {
            errorMessage = ProviderError.noModelSelected.localizedDescription
            return
        }

        do {
            let document = try readImportedDocument(from: url, requiresExtractedText: true)
            let provider = try makeActiveProvider()
            try await knowledgeService.reindexTextDocument(
                collectionID: collectionID,
                fileName: document.fileName,
                contentType: document.contentType,
                text: document.text,
                embeddingModel: embeddingModel,
                provider: provider,
                sourceKind: document.sourceKind
            )
            try await refreshKnowledgeState()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func exportKnowledgeJSONData() async throws -> Data {
        try await knowledgeService.exportKnowledgeJSONData()
    }

    func exportKnowledgeCollectionJSONData(_ collectionID: UUID) async throws -> Data {
        try await knowledgeService.exportCollectionJSONData(id: collectionID)
    }

    func shareKnowledgeCollection(_ collectionID: UUID) async {
        guard requireKnowledgeFeatureEnabled() else {
            return
        }
        do {
            guard let collection = knowledgeCollections.first(where: { $0.id == collectionID }) else {
                throw KnowledgeError.collectionNotFound
            }
            let data = try await exportKnowledgeCollectionJSONData(collectionID)
            guard let json = String(data: data, encoding: .utf8) else {
                errorMessage = "The selected knowledge collection could not be encoded for sharing."
                return
            }
            shareService.share(text: json, title: collection.name)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func exportKnowledgeJSONWithSavePanel() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "open-webui-native-knowledge.json"
        panel.canCreateDirectories = true
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else {
                return
            }
            Task { @MainActor in
                do {
                    let data = try await self?.exportKnowledgeJSONData()
                    try data?.write(to: url, options: [.atomic])
                } catch {
                    self?.errorMessage = error.localizedDescription
                }
            }
        }
    }

    func importKnowledgeJSONData(_ data: Data) async throws {
        guard requireKnowledgeFeatureEnabled() else {
            return
        }
        guard requireKnowledgeWritePermission() else {
            return
        }
        try await knowledgeService.importKnowledgeJSONData(data)
        try await refreshKnowledgeState()
    }

    func importKnowledgeJSON(from url: URL) async {
        guard requireKnowledgeFeatureEnabled() else {
            return
        }
        guard requireKnowledgeWritePermission() else {
            return
        }

        let didStartAccessing = url.startAccessingSecurityScopedResource()
        defer {
            if didStartAccessing {
                url.stopAccessingSecurityScopedResource()
            }
        }

        do {
            let data = try Data(contentsOf: url)
            try await importKnowledgeJSONData(data)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func importKnowledgeJSONWithOpenPanel() {
        guard requireKnowledgeFeatureEnabled() else {
            return
        }
        guard requireKnowledgeWritePermission() else {
            return
        }

        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.begin { [weak self] response in
            guard response == .OK else {
                return
            }
            let urls = panel.urls
            Task { @MainActor in
                for url in urls {
                    await self?.importKnowledgeJSON(from: url)
                }
            }
        }
    }

    func deleteKnowledgeCollection(_ collectionID: UUID) async {
        guard requireKnowledgeFeatureEnabled() else {
            return
        }
        guard requireKnowledgeWritePermission() else {
            return
        }

        do {
            try await knowledgeService.deleteCollection(id: collectionID)
            try await refreshKnowledgeState()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func deleteKnowledgeDocument(_ documentID: UUID) async {
        guard requireKnowledgeFeatureEnabled() else {
            return
        }
        guard requireKnowledgeWritePermission() else {
            return
        }

        do {
            try await knowledgeService.deleteDocument(id: documentID)
            if selectedKnowledgeDocumentDetail?.document.id == documentID {
                selectedKnowledgeDocumentDetail = nil
                selectedKnowledgeChunkID = nil
            }
            try await refreshKnowledgeState()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func updateKnowledgeDocument(_ documentID: UUID, fileName: String) async {
        guard requireKnowledgeFeatureEnabled() else {
            return
        }
        guard requireKnowledgeWritePermission() else {
            return
        }

        do {
            _ = try await knowledgeService.updateDocument(id: documentID, fileName: fileName)
            if selectedKnowledgeDocumentDetail?.document.id == documentID {
                selectedKnowledgeDocumentDetail = try await knowledgeService.loadDocumentDetail(id: documentID)
            }
            try await refreshKnowledgeState()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func selectKnowledgeDocument(_ documentID: UUID) async {
        guard requireKnowledgeFeatureEnabled() else {
            return
        }
        do {
            let detail = try await knowledgeService.loadDocumentDetail(id: documentID)
            guard currentUserCanAccessKnowledgeCollection(detail.collection) else {
                selectedKnowledgeDocumentDetail = nil
                selectedKnowledgeChunkID = nil
                errorMessage = "You do not have access to this knowledge collection."
                return
            }
            selectedKnowledgeDocumentDetail = detail
            selectedKnowledgeChunkID = nil
            selectedThreadID = nil
            selectedChannelID = nil
            isShowingEvaluationDashboard = false
            isShowingAnalyticsDashboard = false
            isShowingPlayground = false
            isShowingFiles = false
            isShowingCalendar = false
            isShowingImageGeneration = false
            isShowingAudio = false
            isShowingCodeInterpreter = false
            isShowingTerminalSessions = false
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func clearSelectedKnowledgeDocument() {
        selectedKnowledgeDocumentDetail = nil
        selectedKnowledgeChunkID = nil
    }

    func selectEvaluationDashboard() {
        selectedThreadID = nil
        selectedChannelID = nil
        clearSelectedKnowledgeDocument()
        isShowingEvaluationDashboard = true
        isShowingAnalyticsDashboard = false
        isShowingPlayground = false
        isShowingFiles = false
        isShowingCalendar = false
        isShowingImageGeneration = false
        isShowingAudio = false
        isShowingCodeInterpreter = false
        isShowingTerminalSessions = false
    }

    func selectAnalyticsDashboard() {
        selectedThreadID = nil
        selectedChannelID = nil
        clearSelectedKnowledgeDocument()
        isShowingEvaluationDashboard = false
        isShowingAnalyticsDashboard = true
        isShowingPlayground = false
        isShowingFiles = false
        isShowingCalendar = false
        isShowingImageGeneration = false
        isShowingAudio = false
        isShowingCodeInterpreter = false
        isShowingTerminalSessions = false
    }

    func openAnalyticsModelChat(threadID: UUID) {
        selectedThreadID = threadID
        focusedChatMessageID = nil
        chatTranscriptSearchText = ""
        selectedChannelID = nil
        clearSelectedKnowledgeDocument()
        isShowingEvaluationDashboard = false
        isShowingAnalyticsDashboard = false
        isShowingPlayground = false
        isShowingFiles = false
        isShowingCalendar = false
        isShowingImageGeneration = false
        isShowingAudio = false
        isShowingCodeInterpreter = false
        isShowingTerminalSessions = false
    }

    func selectPlayground() {
        selectedThreadID = nil
        selectedChannelID = nil
        clearSelectedKnowledgeDocument()
        isShowingEvaluationDashboard = false
        isShowingAnalyticsDashboard = false
        isShowingPlayground = true
        isShowingFiles = false
        isShowingCalendar = false
        isShowingImageGeneration = false
        isShowingAudio = false
        isShowingCodeInterpreter = false
        isShowingTerminalSessions = false
    }

    func selectFiles() {
        selectedThreadID = nil
        selectedChannelID = nil
        clearSelectedKnowledgeDocument()
        isShowingEvaluationDashboard = false
        isShowingAnalyticsDashboard = false
        isShowingPlayground = false
        isShowingFiles = true
        isShowingCalendar = false
        isShowingImageGeneration = false
        isShowingAudio = false
        isShowingCodeInterpreter = false
        isShowingTerminalSessions = false
    }

    func selectImageGeneration() {
        selectedThreadID = nil
        selectedChannelID = nil
        clearSelectedKnowledgeDocument()
        isShowingEvaluationDashboard = false
        isShowingAnalyticsDashboard = false
        isShowingPlayground = false
        isShowingFiles = false
        isShowingCalendar = false
        isShowingImageGeneration = true
        isShowingAudio = false
        isShowingCodeInterpreter = false
        isShowingTerminalSessions = false
    }

    func selectAudio() {
        selectedThreadID = nil
        selectedChannelID = nil
        clearSelectedKnowledgeDocument()
        isShowingEvaluationDashboard = false
        isShowingAnalyticsDashboard = false
        isShowingPlayground = false
        isShowingFiles = false
        isShowingCalendar = false
        isShowingImageGeneration = false
        isShowingAudio = true
        isShowingCodeInterpreter = false
        isShowingTerminalSessions = false
    }

    func setPendingAudioFile(data: Data, fileName: String, contentType: String) {
        pendingAudioData = data
        pendingAudioFileName = fileName
        pendingAudioContentType = contentType
        audioTranscriptText = ""
        audioError = nil
    }

    func importAudioFile(from url: URL) async {
        guard requireAudioFeatureEnabled() else {
            return
        }

        do {
            let data = try Data(contentsOf: url)
            let contentType = UTType(filenameExtension: url.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
            setPendingAudioFile(data: data, fileName: url.lastPathComponent, contentType: contentType)
            errorMessage = nil
        } catch {
            audioError = error.localizedDescription
            errorMessage = error.localizedDescription
        }
    }

    func importAudioFileWithOpenPanel() {
        guard requireAudioFeatureEnabled() else {
            return
        }

        let panel = NSOpenPanel()
        panel.allowedContentTypes = [
            .audio,
            UTType(filenameExtension: "mp3") ?? .audio,
            UTType(filenameExtension: "m4a") ?? .audio,
            UTType(filenameExtension: "wav") ?? .audio,
            UTType(filenameExtension: "webm") ?? .audio
        ]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else {
                return
            }
            Task { @MainActor in
                await self?.importAudioFile(from: url)
            }
        }
    }

    func startAudioRecording() async {
        guard requireAudioFeatureEnabled() else {
            return
        }

        guard requireAudioTranscriptionPermission() else {
            return
        }

        guard !isRecordingAudio else {
            return
        }

        let permissionStatus = await resolvedAudioRecordingPermissionStatus()
        guard permissionStatus.canRecord else {
            audioError = permissionStatus.denialMessage
            errorMessage = audioError
            return
        }

        do {
            audioError = nil
            errorMessage = nil
            try await audioRecorder.startRecording()
            isRecordingAudio = true
        } catch {
            isRecordingAudio = false
            audioError = error.localizedDescription
            errorMessage = error.localizedDescription
        }
    }

    func stopAudioRecording() async {
        guard isRecordingAudio else {
            return
        }

        do {
            let recording = try await audioRecorder.stopRecording()
            setPendingAudioFile(
                data: recording.data,
                fileName: recording.fileName,
                contentType: recording.contentType
            )
            audioError = nil
            errorMessage = nil
        } catch {
            audioError = error.localizedDescription
            errorMessage = error.localizedDescription
        }

        isRecordingAudio = false
    }

    func refreshAudioRecordingPermissionStatus() {
        audioRecordingPermissionStatus = audioRecorder.recordingPermissionStatus()
    }

    private func resolvedAudioRecordingPermissionStatus() async -> AudioRecordingPermissionStatus {
        let currentStatus = audioRecorder.recordingPermissionStatus()
        audioRecordingPermissionStatus = currentStatus
        guard currentStatus == .notDetermined else {
            return currentStatus
        }

        let requestedStatus = await audioRecorder.requestRecordingPermission()
        audioRecordingPermissionStatus = requestedStatus
        return requestedStatus
    }

    func transcribeAudio() async {
        guard requireAudioFeatureEnabled() else {
            return
        }

        guard requireAudioTranscriptionPermission() else {
            return
        }

        guard canTranscribeAudio else {
            audioError = ProviderError.unsupportedAudioTranscription(activeProvider.name).localizedDescription
            errorMessage = audioError
            return
        }
        guard let audioData = pendingAudioData,
              let fileName = pendingAudioFileName,
              let contentType = pendingAudioContentType else {
            audioError = "Choose an audio file before transcribing."
            errorMessage = audioError
            return
        }

        let modelID = audioTranscriptionModelID.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            ?? "gpt-4o-mini-transcribe"
        isTranscribingAudio = true
        audioError = nil
        errorMessage = nil

        do {
            let provider = try makeActiveProvider()
            let result = try await provider.transcribeAudio(
                request: AudioTranscriptionRequest(
                    model: modelID,
                    audioData: audioData,
                    fileName: fileName,
                    contentType: contentType,
                    prompt: audioTranscriptionPrompt.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
                    language: audioTranscriptionLanguage.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
                )
            )
            audioTranscriptText = result.text
            let item = AppAudioHistoryItem(
                kind: .transcription,
                title: fileName,
                text: result.text,
                modelID: modelID,
                sourceFileName: fileName,
                sourceContentType: contentType
            )
            try await saveAudioHistoryItem(item)
        } catch {
            audioError = error.localizedDescription
            errorMessage = error.localizedDescription
        }

        isTranscribingAudio = false
    }

    func synthesizeSpeech() async {
        guard requireAudioFeatureEnabled() else {
            return
        }

        guard requireSpeechSynthesisPermission() else {
            return
        }

        guard canSynthesizeSpeech else {
            audioError = ProviderError.unsupportedSpeechSynthesis(activeProvider.name).localizedDescription
            errorMessage = audioError
            return
        }
        let input = audioSpeechInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty else {
            audioError = ProviderError.emptyPrompt.localizedDescription
            errorMessage = audioError
            return
        }

        let modelID = audioSpeechModelID.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            ?? "gpt-4o-mini-tts"
        let outputFormat = audioSpeechFormat.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? "mp3"
        isSynthesizingSpeech = true
        audioError = nil
        errorMessage = nil

        do {
            let provider = try makeActiveProvider()
            let result = try await provider.synthesizeSpeech(
                request: SpeechSynthesisRequest(
                    model: modelID,
                    input: input,
                    voice: audioSpeechVoice.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? "coral",
                    instructions: audioSpeechInstructions.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
                    responseFormat: outputFormat
                )
            )
            synthesizedSpeechData = result.audioData
            synthesizedSpeechFileName = "open-webui-native-speech.\(result.outputFormat)"
            let item = AppAudioHistoryItem(
                kind: .speech,
                title: synthesizedSpeechFileName ?? "open-webui-native-speech.\(result.outputFormat)",
                text: input,
                modelID: modelID,
                voice: audioSpeechVoice.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? "coral",
                instructions: audioSpeechInstructions.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
                outputFormat: result.outputFormat,
                audioData: result.audioData
            )
            try await saveAudioHistoryItem(item)
        } catch {
            audioError = error.localizedDescription
            errorMessage = error.localizedDescription
        }

        isSynthesizingSpeech = false
    }

    func runVoiceMode(synthesizeResponse: Bool = true) async {
        guard requireVoiceModeFeatureEnabled() else {
            return
        }
        guard requireAudioFeatureEnabled() else {
            return
        }
        guard requireAudioTranscriptionPermission() else {
            return
        }
        if synthesizeResponse {
            guard requireSpeechSynthesisPermission() else {
                return
            }
        }
        guard canTranscribeAudio else {
            audioError = ProviderError.unsupportedAudioTranscription(activeProvider.name).localizedDescription
            errorMessage = audioError
            return
        }
        guard canChat else {
            audioError = ProviderError.unsupportedChat(activeProvider.name).localizedDescription
            errorMessage = audioError
            return
        }
        if synthesizeResponse {
            guard canSynthesizeSpeech else {
                audioError = ProviderError.unsupportedSpeechSynthesis(activeProvider.name).localizedDescription
                errorMessage = audioError
                return
            }
        }
        guard pendingAudioData != nil,
              pendingAudioFileName != nil,
              pendingAudioContentType != nil else {
            audioError = "Choose an audio file before starting voice mode."
            errorMessage = audioError
            return
        }

        isRunningVoiceMode = true
        audioError = nil
        errorMessage = nil
        defer {
            isRunningVoiceMode = false
        }

        await transcribeAudio()
        let prompt = audioTranscriptText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard audioError == nil, !prompt.isEmpty else {
            if audioError == nil {
                audioError = "Voice mode transcription returned no text."
                errorMessage = audioError
            }
            return
        }

        await send(prompt)
        guard errorMessage == nil else {
            audioError = errorMessage
            return
        }

        guard synthesizeResponse else {
            return
        }

        guard let assistantText = latestAssistantResponseText() else {
            audioError = "Voice mode could not find an assistant response to synthesize."
            errorMessage = audioError
            return
        }

        audioSpeechInput = assistantText
        await synthesizeSpeech()
    }

    private func saveAudioHistoryItem(_ item: AppAudioHistoryItem) async throws {
        try await audioHistoryStorage.save(item)
        audioHistory.removeAll { $0.id == item.id }
        audioHistory.append(item)
        sortAudioHistory()
        selectedAudioHistoryItemID = item.id
    }

    func exportAudioHistoryJSONData() throws -> Data {
        try audioHistoryExportService.jsonData(for: audioHistory)
    }

    func exportAudioHistoryJSONDataForUserAction() async throws -> Data {
        guard requireAudioFeatureEnabled() else {
            throw AppStoreMessageError(message: audioError ?? "Audio is disabled.")
        }
        guard requireAudioHistoryWritePermission() else {
            throw AppStoreMessageError(message: audioError ?? "You do not have permission to manage audio history.")
        }

        let exportedItems = audioHistory
        let data = try audioHistoryExportService.jsonData(for: exportedItems)
        await recordAuditEvent(
            action: .audioHistoryExported,
            outcome: .succeeded,
            summary: "Exported audio history",
            metadata: audioHistoryTransferAuditMetadata(prefix: "exported", items: exportedItems)
        )
        return data
    }

    func exportAudioHistoryJSONWithSavePanel() {
        guard currentUserCanManageAudioHistory else {
            audioError = "You do not have permission to manage audio history."
            errorMessage = audioError
            return
        }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "open-webui-native-audio-history.json"
        panel.canCreateDirectories = true
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else {
                return
            }
            Task { @MainActor in
                do {
                    let data = try await self?.exportAudioHistoryJSONDataForUserAction()
                    try data?.write(to: url, options: [.atomic])
                } catch {
                    self?.audioError = error.localizedDescription
                    self?.errorMessage = error.localizedDescription
                }
            }
        }
    }

    func importAudioHistoryJSONData(_ data: Data) async throws {
        guard requireAudioFeatureEnabled() else {
            return
        }
        guard requireAudioHistoryWritePermission() else {
            return
        }

        let importedItems = try audioHistoryExportService.items(fromJSONData: data)
        try await replaceAudioHistory(with: importedItems)
    }

    func importAudioHistoryJSONDataForUserAction(_ data: Data) async throws {
        guard requireAudioFeatureEnabled() else {
            return
        }
        guard requireAudioHistoryWritePermission() else {
            return
        }

        let importedItems = try audioHistoryExportService.items(fromJSONData: data)
        try await replaceAudioHistory(with: importedItems)
        var metadata = audioHistoryTransferAuditMetadata(prefix: "imported", items: importedItems)
        metadata["totalAudioHistoryItemCount"] = String(audioHistory.count)
        await recordAuditEvent(
            action: .audioHistoryImported,
            outcome: .succeeded,
            summary: "Imported audio history",
            metadata: metadata
        )
    }

    private func replaceAudioHistory(with items: [AppAudioHistoryItem]) async throws {
        audioHistory = items
        sortAudioHistory()
        try await audioHistoryStorage.replaceHistory(audioHistory)
        if let selectedAudioHistoryItemID,
           !audioHistory.contains(where: { $0.id == selectedAudioHistoryItemID }) {
            self.selectedAudioHistoryItemID = nil
        }
        if let audioPlaybackItemID,
           !audioHistory.contains(where: { $0.id == audioPlaybackItemID }) {
            stopAudioPlayback()
        }
    }

    private func audioHistoryTransferAuditMetadata(prefix: String, items: [AppAudioHistoryItem]) -> [String: String] {
        [
            "\(prefix)AudioHistoryItemCount": String(items.count),
            "\(prefix)TranscriptionCount": String(items.filter { $0.kind == .transcription }.count),
            "\(prefix)SpeechCount": String(items.filter { $0.kind == .speech }.count)
        ]
    }

    func importAudioHistoryJSON(from url: URL) async {
        guard requireAudioFeatureEnabled() else {
            return
        }
        guard requireAudioHistoryWritePermission() else {
            return
        }

        do {
            let data = try Data(contentsOf: url)
            try await importAudioHistoryJSONDataForUserAction(data)
            audioError = nil
            errorMessage = nil
        } catch {
            audioError = error.localizedDescription
            errorMessage = error.localizedDescription
        }
    }

    func importAudioHistoryJSONWithOpenPanel() {
        guard requireAudioFeatureEnabled() else {
            return
        }
        guard requireAudioHistoryWritePermission() else {
            return
        }

        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else {
                return
            }
            Task { @MainActor in
                await self?.importAudioHistoryJSON(from: url)
            }
        }
    }

    func loadAudioHistoryItem(_ itemID: UUID) {
        guard requireAudioFeatureEnabled() else {
            return
        }
        guard let item = audioHistory.first(where: { $0.id == itemID }) else {
            return
        }

        selectedAudioHistoryItemID = item.id
        switch item.kind {
        case .transcription:
            audioTranscriptText = item.text
            audioTranscriptionModelID = item.modelID
            pendingAudioFileName = item.sourceFileName
            pendingAudioContentType = item.sourceContentType
            pendingAudioData = nil
        case .speech:
            audioSpeechInput = item.text
            audioSpeechModelID = item.modelID
            audioSpeechVoice = item.voice ?? audioSpeechVoice
            audioSpeechInstructions = item.instructions ?? ""
            audioSpeechFormat = item.outputFormat ?? audioSpeechFormat
            synthesizedSpeechData = item.audioData
            synthesizedSpeechFileName = item.title
        }
        audioError = nil
    }

    private func latestAssistantResponseText() -> String? {
        selectedThread?.messages
            .reversed()
            .first { $0.role == .assistant && !$0.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }?
            .content
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func playSynthesizedSpeech() {
        guard requireAudioFeatureEnabled() else {
            return
        }
        guard let synthesizedSpeechData else {
            audioError = "No synthesized speech is available to play."
            errorMessage = audioError
            return
        }

        playAudio(
            data: synthesizedSpeechData,
            fileName: synthesizedSpeechFileName ?? "open-webui-native-speech.\(audioSpeechFormat)",
            itemID: selectedAudioHistoryItemID
        )
    }

    func playAudioHistoryItem(_ itemID: UUID) {
        guard requireAudioFeatureEnabled() else {
            return
        }
        guard let item = audioHistory.first(where: { $0.id == itemID }) else {
            return
        }
        guard item.kind == .speech, let audioData = item.audioData else {
            audioError = "Only speech history items with audio can be played."
            errorMessage = audioError
            return
        }

        loadAudioHistoryItem(itemID)
        playAudio(data: audioData, fileName: item.title, itemID: item.id)
    }

    func pauseAudioPlayback() {
        guard audioPlaybackState == .playing else {
            return
        }

        audioPlayer.pause()
        audioPlaybackState = .paused
    }

    func stopAudioPlayback() {
        audioPlayer.stop()
        audioPlaybackState = .stopped
        audioPlaybackTitle = nil
        audioPlaybackItemID = nil
    }

    private func playAudio(data: Data, fileName: String, itemID: UUID?) {
        do {
            try audioPlayer.play(data: data, fileName: fileName)
            audioPlaybackState = .playing
            audioPlaybackTitle = fileName
            audioPlaybackItemID = itemID
            audioError = nil
            errorMessage = nil
        } catch {
            audioPlaybackState = .stopped
            audioPlaybackTitle = nil
            audioPlaybackItemID = nil
            audioError = error.localizedDescription
            errorMessage = error.localizedDescription
        }
    }

    func deleteAudioHistoryItem(_ itemID: UUID) async {
        guard requireAudioFeatureEnabled() else {
            return
        }
        guard requireAudioHistoryWritePermission() else {
            return
        }

        do {
            try await audioHistoryStorage.deleteHistoryItem(id: itemID)
            audioHistory.removeAll { $0.id == itemID }
            if selectedAudioHistoryItemID == itemID {
                selectedAudioHistoryItemID = nil
            }
            if audioPlaybackItemID == itemID {
                stopAudioPlayback()
            }
        } catch {
            audioError = error.localizedDescription
            errorMessage = error.localizedDescription
        }
    }

    func saveSynthesizedSpeechWithSavePanel() {
        guard let synthesizedSpeechData else {
            return
        }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = synthesizedSpeechFileName ?? "open-webui-native-speech.\(audioSpeechFormat)"
        panel.canCreateDirectories = true
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else {
                return
            }
            do {
                try synthesizedSpeechData.write(to: url, options: [.atomic])
            } catch {
                self?.errorMessage = error.localizedDescription
            }
        }
    }

    func selectCodeInterpreter() {
        selectedThreadID = nil
        selectedChannelID = nil
        clearSelectedKnowledgeDocument()
        isShowingEvaluationDashboard = false
        isShowingAnalyticsDashboard = false
        isShowingPlayground = false
        isShowingFiles = false
        isShowingCalendar = false
        isShowingImageGeneration = false
        isShowingAudio = false
        isShowingCodeInterpreter = true
        isShowingTerminalSessions = false
    }

    func selectTerminalSessions() {
        selectedThreadID = nil
        selectedChannelID = nil
        clearSelectedKnowledgeDocument()
        isShowingEvaluationDashboard = false
        isShowingAnalyticsDashboard = false
        isShowingPlayground = false
        isShowingFiles = false
        isShowingCalendar = false
        isShowingImageGeneration = false
        isShowingAudio = false
        isShowingCodeInterpreter = false
        isShowingTerminalSessions = true
    }

    func runCodeExecution() async {
        guard requireCodeInterpreterFeatureEnabled() else {
            return
        }

        guard requireCodeExecutionPermission() else {
            return
        }
        let code = codeExecutionInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !code.isEmpty else {
            codeExecutionError = "Enter code to run."
            errorMessage = codeExecutionError
            return
        }

        let requestedRun = CodeExecutionRequest(
            language: codeExecutionLanguage,
            code: code,
            workingDirectoryPath: codeExecutionWorkingDirectory.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            timeoutSeconds: codeExecutionTimeoutSeconds
        )

        let policyDecision = CodeExecutionPolicy(settings: settings.codeExecution).evaluate(requestedRun)
        let allowedRun: CodeExecutionRequest
        switch policyDecision {
        case let .allowed(timeoutSeconds, workingDirectoryPath, maxCapturedOutputBytes):
            allowedRun = CodeExecutionRequest(
                language: requestedRun.language,
                code: requestedRun.code,
                workingDirectoryPath: workingDirectoryPath,
                timeoutSeconds: timeoutSeconds,
                maxCapturedOutputBytes: maxCapturedOutputBytes
            )
        case let .blocked(reason):
            codeExecutionError = reason
            errorMessage = reason
            return
        }

        isRunningCodeExecution = true
        codeExecutionError = nil
        errorMessage = nil
        defer {
            isRunningCodeExecution = false
        }

        let run = await codeExecutor.execute(allowedRun)

        do {
            try await codeExecutionStorage.save(run)
            codeExecutionRuns.removeAll { $0.id == run.id }
            codeExecutionRuns.append(run)
            sortCodeExecutionRuns()
            selectedCodeExecutionRunID = run.id
            codeExecutionError = codeExecutionErrorMessage(for: run)
            await recordAuditEvent(
                action: .codeExecutionRun,
                outcome: run.status == .succeeded ? .succeeded : .failed,
                summary: "\(run.language.label) code execution \(run.status.rawValue)",
                metadata: [
                    "language": run.language.rawValue,
                    "status": run.status.rawValue,
                    "runID": run.id.uuidString
                ]
            )
        } catch {
            codeExecutionError = error.localizedDescription
            errorMessage = error.localizedDescription
        }
    }

    func loadCodeExecutionRun(_ runID: UUID) {
        guard let run = codeExecutionRuns.first(where: { $0.id == runID }) else {
            return
        }

        selectedCodeExecutionRunID = run.id
        codeExecutionLanguage = run.language
        codeExecutionInput = run.code
        codeExecutionWorkingDirectory = run.workingDirectoryPath ?? ""
        codeExecutionError = codeExecutionErrorMessage(for: run)
    }

    func createTerminalSession(title: String, workingDirectoryPath: String? = nil) async -> AppTerminalSession? {
        guard requireTerminalSessionsFeatureEnabled() else {
            return nil
        }

        guard requireTerminalSessionCreationPermission() else {
            return nil
        }

        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedWorkingDirectory = workingDirectoryPath?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfEmpty
        let now = Date()
        let session = AppTerminalSession(
            title: trimmedTitle.isEmpty ? "Terminal" : trimmedTitle,
            workingDirectoryPath: trimmedWorkingDirectory,
            createdAt: now,
            updatedAt: now
        )

        do {
            try await terminalStorage.saveSession(session)
            terminalSessions.removeAll { $0.id == session.id }
            terminalSessions.append(session)
            sortTerminalSessions()
            selectedTerminalSessionID = session.id
            terminalError = nil
            await recordAuditEvent(
                action: .terminalSessionCreated,
                outcome: .succeeded,
                summary: "Created terminal session",
                metadata: [
                    "sessionID": session.id.uuidString,
                    "workingDirectory": session.workingDirectoryPath ?? ""
                ]
            )
            return session
        } catch {
            terminalError = error.localizedDescription
            errorMessage = error.localizedDescription
            return nil
        }
    }

    func updateTerminalSession(_ sessionID: UUID, title: String, workingDirectoryPath: String? = nil) async {
        guard requireTerminalSessionsFeatureEnabled() else {
            return
        }

        guard requireTerminalManagementPermission() else {
            return
        }

        guard let index = terminalSessions.firstIndex(where: { $0.id == sessionID }) else {
            terminalError = "Terminal session not found."
            errorMessage = terminalError
            return
        }

        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedWorkingDirectory = workingDirectoryPath?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfEmpty
        terminalSessions[index].title = trimmedTitle.isEmpty ? "Terminal" : trimmedTitle
        terminalSessions[index].workingDirectoryPath = trimmedWorkingDirectory
        terminalSessions[index].updatedAt = Date()

        do {
            try await terminalStorage.saveSession(terminalSessions[index])
            sortTerminalSessions()
            selectedTerminalSessionID = sessionID
            terminalError = nil
            await recordAuditEvent(
                action: .terminalSessionUpdated,
                outcome: .succeeded,
                summary: "Updated terminal session",
                metadata: [
                    "sessionID": sessionID.uuidString,
                    "workingDirectory": trimmedWorkingDirectory ?? ""
                ]
            )
        } catch {
            terminalError = error.localizedDescription
            errorMessage = error.localizedDescription
        }
    }

    func prepareTerminalCommandForRerun(_ commandID: UUID) {
        guard requireTerminalSessionsFeatureEnabled() else {
            return
        }

        guard requireTerminalExecutionPermission() else {
            return
        }

        guard let command = terminalCommands.first(where: { $0.id == commandID }) else {
            terminalError = "Terminal command not found."
            errorMessage = terminalError
            return
        }

        guard terminalSessions.contains(where: { $0.id == command.sessionID }) else {
            terminalError = "Terminal session not found."
            errorMessage = terminalError
            return
        }

        selectedTerminalSessionID = command.sessionID
        terminalCommandInput = command.command
        terminalError = nil
        errorMessage = nil
    }

    func runTerminalCommand() async {
        guard requireTerminalSessionsFeatureEnabled() else {
            return
        }

        guard requireTerminalExecutionPermission() else {
            return
        }

        let command = terminalCommandInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !command.isEmpty else {
            terminalError = "Enter a terminal command."
            errorMessage = terminalError
            return
        }

        let session: AppTerminalSession?
        if let selectedTerminalSession {
            session = selectedTerminalSession
        } else {
            session = await createTerminalSession(title: "Terminal")
        }
        guard let session else {
            return
        }

        let requestedRun = CodeExecutionRequest(
            language: .shell,
            code: command,
            workingDirectoryPath: session.workingDirectoryPath,
            timeoutSeconds: terminalTimeoutSeconds
        )
        let policyDecision = CodeExecutionPolicy(settings: settings.codeExecution).evaluate(requestedRun)
        let allowedRun: CodeExecutionRequest
        switch policyDecision {
        case let .allowed(timeoutSeconds, workingDirectoryPath, maxCapturedOutputBytes):
            allowedRun = CodeExecutionRequest(
                language: .shell,
                code: command,
                workingDirectoryPath: workingDirectoryPath,
                timeoutSeconds: timeoutSeconds,
                maxCapturedOutputBytes: maxCapturedOutputBytes
            )
        case let .blocked(reason):
            terminalError = reason
            errorMessage = reason
            return
        }

        isRunningTerminalCommand = true
        terminalError = nil
        errorMessage = nil
        defer {
            isRunningTerminalCommand = false
        }

        let run = await codeExecutor.execute(allowedRun)
        let terminalCommand = AppTerminalCommand(
            id: run.id,
            sessionID: session.id,
            command: command,
            workingDirectoryPath: run.workingDirectoryPath,
            stdout: run.stdout,
            stderr: run.stderr,
            status: run.status,
            exitCode: run.exitCode,
            startedAt: run.startedAt,
            completedAt: run.completedAt
        )

        do {
            try await terminalStorage.saveCommand(terminalCommand)
            terminalCommands.removeAll { $0.id == terminalCommand.id }
            terminalCommands.append(terminalCommand)
            if let sessionIndex = terminalSessions.firstIndex(where: { $0.id == session.id }) {
                terminalSessions[sessionIndex].updatedAt = terminalCommand.startedAt
                try await terminalStorage.saveSession(terminalSessions[sessionIndex])
            }
            sortTerminalSessions()
            sortTerminalCommands()
            selectedTerminalSessionID = session.id
            terminalCommandInput = ""
            terminalError = terminalCommandErrorMessage(for: terminalCommand)
            await recordAuditEvent(
                action: .terminalCommandRun,
                outcome: terminalCommand.status == .succeeded ? .succeeded : .failed,
                summary: "Terminal command \(terminalCommand.status.rawValue)",
                metadata: [
                    "sessionID": session.id.uuidString,
                    "commandID": terminalCommand.id.uuidString,
                    "status": terminalCommand.status.rawValue
                ]
            )
        } catch {
            terminalError = error.localizedDescription
            errorMessage = error.localizedDescription
        }
    }

    func deleteTerminalCommand(_ commandID: UUID) async {
        guard requireTerminalSessionsFeatureEnabled() else {
            return
        }

        guard requireTerminalManagementPermission() else {
            return
        }

        let deletedCommand = terminalCommands.first { $0.id == commandID }

        do {
            try await terminalStorage.deleteCommand(id: commandID)
            terminalCommands.removeAll { $0.id == commandID }
            terminalError = nil
            await recordAuditEvent(
                action: .terminalCommandDeleted,
                outcome: .succeeded,
                summary: "Deleted terminal command",
                metadata: [
                    "sessionID": deletedCommand?.sessionID.uuidString ?? "",
                    "commandID": commandID.uuidString
                ]
            )
        } catch {
            terminalError = error.localizedDescription
            errorMessage = error.localizedDescription
        }
    }

    func deleteTerminalSession(_ sessionID: UUID) async {
        guard requireTerminalSessionsFeatureEnabled() else {
            return
        }

        guard requireTerminalManagementPermission() else {
            return
        }

        let deletedCommandCount = terminalCommands.filter { $0.sessionID == sessionID }.count

        do {
            try await terminalStorage.deleteSession(id: sessionID)
            terminalSessions.removeAll { $0.id == sessionID }
            terminalCommands.removeAll { $0.sessionID == sessionID }
            if selectedTerminalSessionID == sessionID {
                selectedTerminalSessionID = terminalSessions.first?.id
            }
            terminalError = nil
            await recordAuditEvent(
                action: .terminalSessionDeleted,
                outcome: .succeeded,
                summary: "Deleted terminal session",
                metadata: [
                    "sessionID": sessionID.uuidString,
                    "deletedCommandCount": String(deletedCommandCount)
                ]
            )
        } catch {
            terminalError = error.localizedDescription
            errorMessage = error.localizedDescription
        }
    }

    func deleteCodeExecutionRun(_ runID: UUID) async {
        guard requireCodeInterpreterFeatureEnabled() else {
            return
        }

        guard requireCodeExecutionPermission() else {
            return
        }

        let deletedRun = codeExecutionRuns.first { $0.id == runID }

        do {
            try await codeExecutionStorage.deleteRun(id: runID)
            codeExecutionRuns.removeAll { $0.id == runID }
            if selectedCodeExecutionRunID == runID {
                selectedCodeExecutionRunID = nil
            }
            codeExecutionError = nil
            errorMessage = nil
            await recordAuditEvent(
                action: .codeExecutionRunDeleted,
                outcome: .succeeded,
                summary: "Deleted code execution run",
                metadata: [
                    "runID": runID.uuidString,
                    "language": deletedRun?.language.rawValue ?? "",
                    "status": deletedRun?.status.rawValue ?? ""
                ]
            )
        } catch {
            codeExecutionError = error.localizedDescription
            errorMessage = error.localizedDescription
        }
    }

    func exportGeneratedImagesJSONData() throws -> Data {
        try generatedImageExportService.jsonData(for: generatedImages)
    }

    func exportGeneratedImagesOpenWebUIJSONData() throws -> Data {
        try generatedImageExportService.openWebUIJSONData(for: generatedImages)
    }

    func exportGeneratedImagesJSONDataForUserAction() async throws -> Data {
        guard requireImageGenerationFeatureEnabled() else {
            throw AppStoreMessageError(message: imageGenerationError ?? "Image Generation is disabled.")
        }
        guard requireGeneratedImageWritePermission() else {
            throw AppStoreMessageError(message: errorMessage ?? "You do not have permission to manage generated images.")
        }

        let exportedImages = generatedImages
        let data = try generatedImageExportService.jsonData(for: exportedImages)
        await recordAuditEvent(
            action: .generatedImagesExported,
            outcome: .succeeded,
            summary: "Exported generated images",
            metadata: generatedImageTransferAuditMetadata(prefix: "exported", images: exportedImages)
        )
        return data
    }

    func exportGeneratedImagesOpenWebUIJSONDataForUserAction() async throws -> Data {
        guard requireImageGenerationFeatureEnabled() else {
            throw AppStoreMessageError(message: imageGenerationError ?? "Image Generation is disabled.")
        }
        guard requireGeneratedImageWritePermission() else {
            throw AppStoreMessageError(message: errorMessage ?? "You do not have permission to manage generated images.")
        }

        let exportedImages = generatedImages
        let data = try generatedImageExportService.openWebUIJSONData(for: exportedImages)
        await recordAuditEvent(
            action: .generatedImagesExported,
            outcome: .succeeded,
            summary: "Exported Open WebUI generated image records",
            metadata: generatedImageTransferAuditMetadata(prefix: "exported", images: exportedImages)
        )
        return data
    }

    func exportGeneratedImagesJSONWithSavePanel() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "open-webui-native-generated-images.json"
        panel.canCreateDirectories = true
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else {
                return
            }
            Task { @MainActor in
                do {
                    let data = try await self?.exportGeneratedImagesJSONDataForUserAction()
                    try data?.write(to: url, options: [.atomic])
                } catch {
                    self?.errorMessage = error.localizedDescription
                }
            }
        }
    }

    func exportGeneratedImagesOpenWebUIJSONWithSavePanel() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "open-webui-generated-images.json"
        panel.canCreateDirectories = true
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else {
                return
            }
            Task { @MainActor in
                do {
                    let data = try await self?.exportGeneratedImagesOpenWebUIJSONDataForUserAction()
                    try data?.write(to: url, options: [.atomic])
                } catch {
                    self?.errorMessage = error.localizedDescription
                }
            }
        }
    }

    func importGeneratedImagesJSONData(_ data: Data) async throws {
        guard requireImageGenerationFeatureEnabled() else {
            return
        }
        guard requireGeneratedImageWritePermission() else {
            return
        }

        let importedImages = try generatedImageExportService.images(fromJSONData: data)
        try await replaceGeneratedImages(with: importedImages)
    }

    func importGeneratedImagesJSONDataForUserAction(_ data: Data) async throws {
        guard requireImageGenerationFeatureEnabled() else {
            return
        }
        guard requireGeneratedImageWritePermission() else {
            return
        }

        let importedImages = try generatedImageExportService.images(fromJSONData: data)
        try await replaceGeneratedImages(with: importedImages)
        var metadata = generatedImageTransferAuditMetadata(prefix: "imported", images: importedImages)
        metadata["totalGeneratedImageCount"] = String(generatedImages.count)
        await recordAuditEvent(
            action: .generatedImagesImported,
            outcome: .succeeded,
            summary: "Imported generated images",
            metadata: metadata
        )
    }

    private func replaceGeneratedImages(with images: [AppGeneratedImage]) async throws {
        generatedImages = images
        sortGeneratedImages()
        try await generatedImageStorage.replaceImages(generatedImages)
    }

    private func generatedImageTransferAuditMetadata(prefix: String, images: [AppGeneratedImage]) -> [String: String] {
        [
            "\(prefix)GeneratedImageCount": String(images.count),
            "\(prefix)OriginalImageCount": String(images.filter { $0.sourceOperation == nil }.count),
            "\(prefix)EditedImageCount": String(images.filter { $0.sourceOperation == "edit" }.count),
            "\(prefix)VariationImageCount": String(images.filter { $0.sourceOperation == "variation" }.count)
        ]
    }

    func importGeneratedImagesJSON(from url: URL) async {
        guard requireImageGenerationFeatureEnabled() else {
            return
        }
        guard requireGeneratedImageWritePermission() else {
            return
        }

        do {
            let data = try Data(contentsOf: url)
            try await importGeneratedImagesJSONDataForUserAction(data)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func importGeneratedImagesJSONWithOpenPanel() {
        guard requireImageGenerationFeatureEnabled() else {
            return
        }
        guard requireGeneratedImageWritePermission() else {
            return
        }

        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else {
                return
            }
            Task { @MainActor in
                await self?.importGeneratedImagesJSON(from: url)
            }
        }
    }

    func selectImageForEditing(_ imageID: UUID) {
        selectedImageForEditingID = imageID
        imageEditPrompt = ""
        clearImageEditMask()
        imageGenerationError = nil
    }

    func setImageEditMask(data: Data, fileName: String, contentType: String) {
        imageEditMaskData = data
        imageEditMaskFileName = fileName
        imageEditMaskContentType = contentType
        imageGenerationError = nil
    }

    func clearImageEditMask() {
        imageEditMaskData = nil
        imageEditMaskFileName = nil
        imageEditMaskContentType = nil
    }

    func importImageEditMask(from url: URL) async {
        let didAccess = url.startAccessingSecurityScopedResource()
        defer {
            if didAccess {
                url.stopAccessingSecurityScopedResource()
            }
        }

        do {
            let data = try Data(contentsOf: url)
            let contentType = UTType(filenameExtension: url.pathExtension)?.preferredMIMEType ?? "image/png"
            setImageEditMask(data: data, fileName: url.lastPathComponent, contentType: contentType)
            errorMessage = nil
        } catch {
            imageGenerationError = error.localizedDescription
            errorMessage = error.localizedDescription
        }
    }

    func generateImage() async {
        guard requireImageGenerationFeatureEnabled() else {
            return
        }
        guard requireImageGenerationPermission() else {
            return
        }

        guard canGenerateImages else {
            imageGenerationError = ProviderError.unsupportedImageGeneration(activeProvider.name).localizedDescription
            errorMessage = imageGenerationError
            return
        }
        let prompt = imageGenerationPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty else {
            imageGenerationError = ProviderError.emptyPrompt.localizedDescription
            errorMessage = imageGenerationError
            return
        }
        let modelID = imageGenerationModelID ?? settings.selectedModelID ?? models.first?.id
        guard let modelID else {
            imageGenerationError = ProviderError.noModelSelected.localizedDescription
            errorMessage = imageGenerationError
            return
        }

        isGeneratingImage = true
        imageGenerationError = nil
        errorMessage = nil

        do {
            let provider = try makeActiveProvider()
            let result = try await provider.generateImages(
                request: ImageGenerationRequest(
                    model: modelID,
                    prompt: prompt,
                    size: imageGenerationSize,
                    quality: imageGenerationQuality.nilIfEmpty,
                    count: imageGenerationCount
                )
            )
            let records = result.images.map { image in
                AppGeneratedImage(
                    prompt: prompt,
                    modelID: modelID,
                    providerID: settings.activeProviderID,
                    imageData: image.data,
                    revisedPrompt: image.revisedPrompt,
                    outputFormat: result.outputFormat,
                    size: result.size ?? imageGenerationSize,
                    quality: result.quality ?? imageGenerationQuality.nilIfEmpty
                )
            }
            for record in records {
                try await generatedImageStorage.save(record)
            }
            generatedImages.insert(contentsOf: records, at: 0)
            sortGeneratedImages()
        } catch {
            imageGenerationError = error.localizedDescription
            errorMessage = error.localizedDescription
        }

        isGeneratingImage = false
    }

    func editGeneratedImage(_ imageID: UUID) async {
        guard requireImageGenerationFeatureEnabled() else {
            return
        }
        guard requireImageGenerationPermission() else {
            return
        }

        guard canEditImages else {
            imageGenerationError = ProviderError.unsupportedImageEditing(activeProvider.name).localizedDescription
            errorMessage = imageGenerationError
            return
        }
        let prompt = imageEditPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty else {
            imageGenerationError = ProviderError.emptyPrompt.localizedDescription
            errorMessage = imageGenerationError
            return
        }
        guard let source = generatedImages.first(where: { $0.id == imageID }) else {
            imageGenerationError = "Choose a generated image before editing."
            errorMessage = imageGenerationError
            return
        }
        let modelID = imageGenerationModelID ?? source.modelID
        isEditingImage = true
        selectedImageForEditingID = imageID
        imageGenerationError = nil
        errorMessage = nil

        do {
            let provider = try makeActiveProvider()
            let format = source.outputFormat?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? "png"
            let result = try await provider.editImage(
                request: ImageEditRequest(
                    model: modelID,
                    prompt: prompt,
                    imageData: source.imageData,
                    imageFileName: "source.\(fileExtension(forImageFormat: format))",
                    imageContentType: contentType(forImageFormat: format),
                    maskData: imageEditMaskData,
                    maskFileName: imageEditMaskFileName,
                    maskContentType: imageEditMaskContentType,
                    size: source.size ?? imageGenerationSize,
                    quality: source.quality ?? imageGenerationQuality.nilIfEmpty,
                    count: 1
                )
            )
            let records = result.images.map { image in
                AppGeneratedImage(
                    prompt: prompt,
                    modelID: modelID,
                    providerID: settings.activeProviderID,
                    imageData: image.data,
                    revisedPrompt: image.revisedPrompt,
                    outputFormat: result.outputFormat ?? source.outputFormat,
                    size: result.size ?? source.size ?? imageGenerationSize,
                    quality: result.quality ?? source.quality ?? imageGenerationQuality.nilIfEmpty,
                    sourceImageID: source.id,
                    sourceOperation: "edit"
                )
            }
            for record in records {
                try await generatedImageStorage.save(record)
            }
            generatedImages.insert(contentsOf: records, at: 0)
            sortGeneratedImages()
            clearImageEditMask()
        } catch {
            imageGenerationError = error.localizedDescription
            errorMessage = error.localizedDescription
        }

        isEditingImage = false
    }

    func varyGeneratedImage(_ imageID: UUID) async {
        guard requireImageGenerationFeatureEnabled() else {
            return
        }
        guard requireImageGenerationPermission() else {
            return
        }

        guard canVaryImages else {
            imageGenerationError = ProviderError.unsupportedImageVariation(activeProvider.name).localizedDescription
            errorMessage = imageGenerationError
            return
        }
        guard let source = generatedImages.first(where: { $0.id == imageID }) else {
            imageGenerationError = "Choose a generated image before creating a variation."
            errorMessage = imageGenerationError
            return
        }
        let modelID = imageGenerationModelID?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? source.modelID
        guard modelID == "dall-e-2" else {
            imageGenerationError = "Image variations currently require the dall-e-2 model."
            errorMessage = imageGenerationError
            return
        }
        if let outputFormat = source.outputFormat?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
           !outputFormat.isEmpty,
           outputFormat != "png" {
            imageGenerationError = "Image variations require a PNG source image."
            errorMessage = imageGenerationError
            return
        }
        if let sourceSize = source.size, !Self.isSquareImageSize(sourceSize) {
            imageGenerationError = "Image variations require a square source image."
            errorMessage = imageGenerationError
            return
        }

        isVaryingImage = true
        imageGenerationError = nil
        errorMessage = nil

        do {
            let provider = try makeActiveProvider()
            let result = try await provider.varyImage(
                request: ImageVariationRequest(
                    model: modelID,
                    imageData: source.imageData,
                    imageFileName: "source.png",
                    imageContentType: "image/png",
                    size: imageGenerationSize,
                    count: imageGenerationCount
                )
            )
            let records = result.images.map { image in
                AppGeneratedImage(
                    prompt: source.prompt,
                    modelID: modelID,
                    providerID: settings.activeProviderID,
                    imageData: image.data,
                    revisedPrompt: image.revisedPrompt,
                    outputFormat: result.outputFormat ?? "png",
                    size: result.size ?? imageGenerationSize,
                    quality: result.quality,
                    sourceImageID: source.id,
                    sourceOperation: "variation"
                )
            }
            for record in records {
                try await generatedImageStorage.save(record)
            }
            generatedImages.insert(contentsOf: records, at: 0)
            sortGeneratedImages()
        } catch {
            imageGenerationError = error.localizedDescription
            errorMessage = error.localizedDescription
        }

        isVaryingImage = false
    }

    func runPlayground() async {
        let prompt = playgroundPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty else {
            playgroundError = ProviderError.emptyPrompt.localizedDescription
            errorMessage = playgroundError
            return
        }
        guard requirePlaygroundFeatureEnabled() else {
            return
        }

        if playgroundMode == .notes {
            await savePlaygroundNote()
            return
        }

        guard requirePlaygroundExecutionPermission() else {
            return
        }

        switch playgroundMode {
        case .chat:
            await runChatPlayground(prompt: prompt)
        case .completions:
            await runCompletionPlayground(prompt: prompt)
        case .notes:
            await savePlaygroundNote()
        case .images:
            await runImagePlayground(prompt: prompt)
        }
    }

    private func runChatPlayground(prompt: String) async {
        guard canChat else {
            playgroundError = ProviderError.unsupportedChat(activeProvider.name).localizedDescription
            errorMessage = playgroundError
            return
        }

        let modelID = playgroundModelID?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            ?? selectedModelID
            ?? selectedModelIDs.first
        guard let modelID else {
            playgroundError = ProviderError.noModelSelected.localizedDescription
            errorMessage = playgroundError
            return
        }

        let systemPrompt = playgroundSystemPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        var providerMessages: [ProviderChatMessage] = []
        if !systemPrompt.isEmpty {
            providerMessages.append(ProviderChatMessage(role: ChatRole.system.rawValue, content: systemPrompt))
        }
        providerMessages.append(ProviderChatMessage(role: ChatRole.user.rawValue, content: prompt))

        playgroundOutput = ""
        playgroundError = nil
        errorMessage = nil
        playgroundImageOutputs = []
        isRunningPlayground = true
        defer {
            isRunningPlayground = false
        }

        playgroundComparisonOutput = ""
        playgroundComparisonError = nil

        do {
            let provider = try makeActiveProvider()
            await streamPlaygroundResponse(
                provider: provider,
                modelID: modelID,
                messages: providerMessages,
                assignError: { self.playgroundError = $0 },
                appendChunk: { self.playgroundOutput += $0 }
            )

            if isPlaygroundComparisonEnabled,
               let comparisonModelID = playgroundComparisonModelID(forPrimaryModelID: modelID) {
                await streamPlaygroundResponse(
                    provider: provider,
                    modelID: comparisonModelID,
                    messages: providerMessages,
                    assignError: { self.playgroundComparisonError = $0 },
                    appendChunk: { self.playgroundComparisonOutput += $0 }
                )
            }
        } catch {
            let message = error.localizedDescription
            playgroundError = message
            if isPlaygroundComparisonEnabled {
                playgroundComparisonError = message
            }
            errorMessage = message
        }
    }

    private func streamPlaygroundResponse(
        provider: any ChatProvider,
        modelID: String,
        messages: [ProviderChatMessage],
        assignError: (String) -> Void,
        appendChunk: (String) -> Void
    ) async {
        do {
            for try await chunk in provider.streamChat(
                model: modelID,
                messages: messages,
                options: playgroundChatOptions
            ) {
                appendChunk(chunk)
            }
        } catch {
            let message = error.localizedDescription
            assignError(message)
            errorMessage = message
        }
    }

    private func runCompletionPlayground(prompt: String) async {
        guard canComplete else {
            playgroundError = ProviderError.unsupportedCompletions(activeProvider.name).localizedDescription
            errorMessage = playgroundError
            return
        }

        let modelID = playgroundModelID?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            ?? selectedModelID
            ?? selectedModelIDs.first
        guard let modelID else {
            playgroundError = ProviderError.noModelSelected.localizedDescription
            errorMessage = playgroundError
            return
        }

        playgroundOutput = ""
        playgroundError = nil
        playgroundComparisonOutput = ""
        playgroundComparisonError = nil
        playgroundImageOutputs = []
        errorMessage = nil
        isRunningPlayground = true
        defer {
            isRunningPlayground = false
        }

        do {
            let provider = try makeActiveProvider()
            for try await chunk in provider.streamCompletion(
                model: modelID,
                prompt: prompt,
                options: playgroundChatOptions
            ) {
                playgroundOutput += chunk
            }
        } catch {
            let message = error.localizedDescription
            playgroundError = message
            errorMessage = message
        }
    }

    func savePlaygroundNote() async {
        guard requireNoteWritePermission() else {
            playgroundError = errorMessage
            return
        }

        let content = playgroundPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty else {
            playgroundError = ProviderError.emptyPrompt.localizedDescription
            errorMessage = playgroundError
            return
        }

        let title = playgroundNoteTitle.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            ?? playgroundHistoryTitle(for: content)

        playgroundError = nil
        playgroundComparisonError = nil
        playgroundComparisonOutput = ""
        playgroundImageOutputs = []
        errorMessage = nil

        do {
            if let noteID = selectedPlaygroundNoteID,
               let index = notes.firstIndex(where: { $0.id == noteID }) {
                notes[index].title = title
                notes[index].content = content
                notes[index].updatedAt = Date()
                try await noteStorage.save(notes[index])
                sortNotes()
                playgroundNoteTitle = title
                playgroundOutput = "Updated note: \(title)"
            } else {
                let note = AppNote(title: title, content: content)
                try await noteStorage.save(note)
                notes.append(note)
                sortNotes()
                selectedPlaygroundNoteID = note.id
                playgroundNoteTitle = title
                playgroundOutput = "Saved note: \(title)"
            }
        } catch {
            let message = error.localizedDescription
            playgroundError = message
            errorMessage = message
        }
    }

    private func playgroundComparisonModelID(forPrimaryModelID primaryModelID: String) -> String? {
        playgroundComparisonModelID?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            ?? models.first { $0.id != primaryModelID }?.id
    }

    var playgroundChatOptions: ProviderChatOptions {
        ProviderChatOptions(
            temperature: min(max(playgroundTemperature, 0), 2),
            topP: min(max(playgroundTopP, 0), 1),
            maxTokens: max(playgroundMaxTokens, 1)
        )
    }

    func currentPlaygroundTranscript(now: Date = Date()) throws -> PlaygroundTranscript {
        let prompt = playgroundPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let output = playgroundOutput.trimmingCharacters(in: .whitespacesAndNewlines)
        let modelID = currentPlaygroundModelID()
        guard !prompt.isEmpty else {
            throw ProviderError.emptyPrompt
        }
        guard !output.isEmpty else {
            throw ProviderError.emptyPrompt
        }
        guard let modelID else {
            throw ProviderError.noModelSelected
        }

        return PlaygroundTranscript(
            mode: playgroundMode,
            modelID: modelID,
            comparisonModelID: isPlaygroundComparisonEnabled
                ? playgroundComparisonModelID(forPrimaryModelID: modelID)
                : nil,
            isComparisonEnabled: isPlaygroundComparisonEnabled,
            systemPrompt: playgroundSystemPrompt.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            prompt: prompt,
            output: output,
            comparisonOutput: isPlaygroundComparisonEnabled
                ? playgroundComparisonOutput.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
                : nil,
            options: playgroundChatOptions,
            imageOutputs: playgroundMode == .images ? playgroundImageOutputs : [],
            imageSize: playgroundMode == .images ? playgroundImageSize : nil,
            imageQuality: playgroundMode == .images ? playgroundImageQuality.nilIfEmpty : nil,
            imageCount: playgroundMode == .images ? playgroundImageCount : nil,
            createdAt: now
        )
    }

    func saveCurrentPlaygroundRun(now: Date = Date()) async {
        guard requirePlaygroundHistoryWritePermission() else {
            return
        }

        let prompt = playgroundPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let output = playgroundOutput.trimmingCharacters(in: .whitespacesAndNewlines)
        let modelID = currentPlaygroundModelID()
        guard !prompt.isEmpty else {
            errorMessage = ProviderError.emptyPrompt.localizedDescription
            return
        }
        guard !output.isEmpty else {
            errorMessage = ProviderError.emptyPrompt.localizedDescription
            return
        }
        guard let modelID else {
            errorMessage = ProviderError.noModelSelected.localizedDescription
            return
        }

        let item = PlaygroundHistoryItem(
            title: playgroundHistoryTitle(for: prompt),
            mode: playgroundMode,
            modelID: modelID,
            comparisonModelID: isPlaygroundComparisonEnabled
                ? playgroundComparisonModelID(forPrimaryModelID: modelID)
                : nil,
            isComparisonEnabled: isPlaygroundComparisonEnabled,
            systemPrompt: playgroundSystemPrompt.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            prompt: prompt,
            output: output,
            comparisonOutput: isPlaygroundComparisonEnabled
                ? playgroundComparisonOutput.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
                : nil,
            options: playgroundChatOptions,
            imageOutputs: playgroundMode == .images ? playgroundImageOutputs : [],
            imageSize: playgroundMode == .images ? playgroundImageSize : nil,
            imageQuality: playgroundMode == .images ? playgroundImageQuality.nilIfEmpty : nil,
            imageCount: playgroundMode == .images ? playgroundImageCount : nil,
            createdAt: now,
            updatedAt: now
        )

        do {
            try await playgroundHistoryStorage.save(item)
            playgroundHistory.removeAll { $0.id == item.id }
            playgroundHistory.append(item)
            sortPlaygroundHistory()
            selectedPlaygroundHistoryID = item.id
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func loadPlaygroundHistoryItem(_ itemID: UUID) {
        guard let item = playgroundHistory.first(where: { $0.id == itemID }) else {
            return
        }

        selectedPlaygroundHistoryID = item.id
        playgroundMode = item.mode
        playgroundModelID = item.mode == .chat || item.mode == .completions ? item.modelID : playgroundModelID
        playgroundImageModelID = item.mode == .images ? item.modelID : playgroundImageModelID
        selectedPlaygroundNoteID = nil
        playgroundNoteTitle = item.mode == .notes ? item.title : playgroundNoteTitle
        playgroundComparisonModelID = item.comparisonModelID
        isPlaygroundComparisonEnabled = item.isComparisonEnabled
        playgroundSystemPrompt = item.systemPrompt ?? ""
        playgroundPrompt = item.prompt
        playgroundOutput = item.output
        playgroundComparisonOutput = item.comparisonOutput ?? ""
        playgroundImageOutputs = item.imageOutputs
        playgroundImageSize = item.imageSize ?? "1024x1024"
        playgroundImageQuality = item.imageQuality ?? "high"
        playgroundImageCount = item.imageCount ?? 1
        playgroundError = nil
        playgroundComparisonError = nil
        playgroundTemperature = item.options.temperature ?? 0.7
        playgroundTopP = item.options.topP ?? 0.9
        playgroundMaxTokens = item.options.maxTokens ?? 512
    }

    private func currentPlaygroundModelID() -> String? {
        switch playgroundMode {
        case .chat, .completions:
            return playgroundModelID?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
                ?? selectedModelID
                ?? selectedModelIDs.first
        case .notes:
            return "notes"
        case .images:
            return playgroundImageModelID?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
                ?? imageGenerationModelID?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
                ?? selectedModelID
                ?? selectedModelIDs.first
                ?? models.first?.id
        }
    }

    func deletePlaygroundHistoryItem(_ itemID: UUID) async {
        guard requirePlaygroundHistoryWritePermission() else {
            return
        }

        do {
            try await playgroundHistoryStorage.deleteHistoryItem(id: itemID)
            playgroundHistory.removeAll { $0.id == itemID }
            if selectedPlaygroundHistoryID == itemID {
                selectedPlaygroundHistoryID = nil
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func sortPlaygroundHistory() {
        playgroundHistory.sort { $0.updatedAt > $1.updatedAt }
    }

    private func playgroundHistoryTitle(for prompt: String) -> String {
        let firstLine = prompt
            .split(whereSeparator: \.isNewline)
            .first
            .map(String.init)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let title = firstLine?.nilIfEmpty ?? "Playground Run"
        if title.count <= 60 {
            return title
        }
        return String(title.prefix(60))
    }

    func exportPlaygroundJSONData() throws -> Data {
        try playgroundExportService.jsonData(for: currentPlaygroundTranscript())
    }

    func exportPlaygroundTextData() throws -> Data {
        let text = try playgroundExportService.text(for: currentPlaygroundTranscript())
        return Data(text.utf8)
    }

    func shareCurrentPlaygroundRun() {
        do {
            let transcript = try currentPlaygroundTranscript()
            try sharePlaygroundTranscript(transcript, title: playgroundHistoryTitle(for: transcript.prompt))
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func sharePlaygroundHistoryItem(_ itemID: UUID) {
        guard let item = playgroundHistory.first(where: { $0.id == itemID }) else {
            return
        }

        do {
            try sharePlaygroundTranscript(playgroundTranscript(for: item), title: item.title)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func sharePlaygroundTranscript(_ transcript: PlaygroundTranscript, title: String) throws {
        let data = try playgroundExportService.jsonData(for: transcript)
        guard let json = String(data: data, encoding: .utf8) else {
            errorMessage = "The selected playground run could not be encoded for sharing."
            return
        }
        shareService.share(text: json, title: title)
    }

    private func playgroundTranscript(for item: PlaygroundHistoryItem) -> PlaygroundTranscript {
        PlaygroundTranscript(
            mode: item.mode,
            modelID: item.modelID,
            comparisonModelID: item.comparisonModelID,
            isComparisonEnabled: item.isComparisonEnabled,
            systemPrompt: item.systemPrompt,
            prompt: item.prompt,
            output: item.output,
            comparisonOutput: item.comparisonOutput,
            options: item.options,
            imageOutputs: item.imageOutputs,
            imageSize: item.imageSize,
            imageQuality: item.imageQuality,
            imageCount: item.imageCount,
            createdAt: item.createdAt
        )
    }

    func exportPlaygroundJSONWithSavePanel() {
        exportPlaygroundWithSavePanel(
            allowedContentTypes: [.json],
            defaultFileName: "playground-chat.json",
            dataProvider: exportPlaygroundJSONData
        )
    }

    func exportPlaygroundTextWithSavePanel() {
        exportPlaygroundWithSavePanel(
            allowedContentTypes: [.plainText],
            defaultFileName: "playground-chat.txt",
            dataProvider: exportPlaygroundTextData
        )
    }

    private func exportPlaygroundWithSavePanel(
        allowedContentTypes: [UTType],
        defaultFileName: String,
        dataProvider: @escaping () throws -> Data
    ) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = allowedContentTypes
        panel.nameFieldStringValue = defaultFileName
        panel.canCreateDirectories = true
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else {
                return
            }
            Task { @MainActor in
                do {
                    try dataProvider().write(to: url, options: [.atomic])
                } catch {
                    self?.errorMessage = error.localizedDescription
                }
            }
        }
    }

    private func runImagePlayground(prompt: String) async {
        guard canGenerateImages else {
            playgroundError = ProviderError.unsupportedImageGeneration(activeProvider.name).localizedDescription
            errorMessage = playgroundError
            return
        }

        let modelID = playgroundImageModelID?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            ?? imageGenerationModelID?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            ?? selectedModelID
            ?? selectedModelIDs.first
            ?? models.first?.id
        guard let modelID else {
            playgroundError = ProviderError.noModelSelected.localizedDescription
            errorMessage = playgroundError
            return
        }

        playgroundOutput = ""
        playgroundError = nil
        playgroundComparisonOutput = ""
        playgroundComparisonError = nil
        playgroundImageOutputs = []
        errorMessage = nil
        isRunningPlayground = true
        defer {
            isRunningPlayground = false
        }

        do {
            let provider = try makeActiveProvider()
            let result = try await provider.generateImages(
                request: ImageGenerationRequest(
                    model: modelID,
                    prompt: prompt,
                    size: playgroundImageSize,
                    quality: playgroundImageQuality.nilIfEmpty,
                    count: playgroundImageCount
                )
            )
            playgroundImageOutputs = result.images.map { image in
                PlaygroundImageOutput(
                    imageData: image.data,
                    revisedPrompt: image.revisedPrompt,
                    outputFormat: result.outputFormat,
                    size: result.size ?? playgroundImageSize,
                    quality: result.quality ?? playgroundImageQuality.nilIfEmpty
                )
            }
            let count = playgroundImageOutputs.count
            playgroundOutput = "Generated \(count) \(count == 1 ? "image" : "images")."
        } catch {
            let message = error.localizedDescription
            playgroundError = message
            errorMessage = message
        }
    }

    func exportAnalyticsJSONData() throws -> Data {
        try analyticsExportService.jsonData(
            for: analyticsSummary,
            webSearchNetworkSummary: webSearchNetworkHistorySummary
        )
    }

    func exportAnalyticsJSONDataForUserAction() async throws -> Data {
        let summary = analyticsSummary
        let networkSummary = webSearchNetworkHistorySummary
        await recordAuditEvent(
            action: .analyticsExported,
            outcome: .succeeded,
            summary: "Exported analytics report",
            metadata: analyticsExportAuditMetadata(
                for: summary,
                webSearchNetworkSummary: networkSummary
            )
        )
        return try analyticsExportService.jsonData(
            for: summary,
            webSearchNetworkSummary: networkSummary
        )
    }

    func exportAuditLogJSONData() throws -> Data {
        try auditLogExportService.jsonData(for: auditEvents)
    }

    func exportAuditLogJSONDataForUserAction() async throws -> Data {
        await recordAuditEvent(
            action: .auditLogExported,
            outcome: .succeeded,
            summary: "Exported audit log",
            metadata: [
                "exportedAuditEventCount": String(auditEvents.count + 1),
                "includedExportEvent": "true"
            ]
        )
        return try exportAuditLogJSONData()
    }

    func deleteAuditEvent(_ eventID: UUID) async {
        let deletedEvent = auditEvents.first { $0.id == eventID }
        do {
            try await auditLogStorage.deleteEvent(id: eventID)
            auditEvents.removeAll { $0.id == eventID }
            var metadata = ["deletedEventID": eventID.uuidString]
            if let deletedEvent {
                metadata["deletedAction"] = deletedEvent.action.rawValue
                metadata["deletedOutcome"] = deletedEvent.outcome.rawValue
            }
            await recordAuditEvent(
                action: .auditEventDeleted,
                outcome: .succeeded,
                summary: "Deleted audit event",
                metadata: metadata
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func exportAnalyticsJSONWithSavePanel() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "open-webui-native-analytics.json"
        panel.canCreateDirectories = true
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else {
                return
            }
            Task { @MainActor in
                do {
                    let data = try await self?.exportAnalyticsJSONDataForUserAction()
                    try data?.write(to: url, options: [.atomic])
                } catch {
                    self?.errorMessage = error.localizedDescription
                }
            }
        }
    }

    func exportAuditLogJSONWithSavePanel() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "open-webui-native-audit-log.json"
        panel.canCreateDirectories = true
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else {
                return
            }
            Task { @MainActor in
                do {
                    let data = try await self?.exportAuditLogJSONDataForUserAction()
                    try data?.write(to: url, options: [.atomic])
                } catch {
                    self?.errorMessage = error.localizedDescription
                }
            }
        }
    }

    private func analyticsExportAuditMetadata(
        for summary: AnalyticsSummary,
        webSearchNetworkSummary: WebSearchNetworkHistorySummary = .empty
    ) -> [String: String] {
        var metadata = [
            "exportedChatCount": String(summary.totalChats),
            "exportedMessageCount": String(summary.totalMessages),
            "exportedModelCount": String(summary.totalModels),
            "exportedFeedbackCount": String(summary.feedbackRecords),
            "exportedKnowledgeCollectionCount": String(summary.knowledgeCollections),
            "exportedKnowledgeDocumentCount": String(summary.knowledgeDocuments),
            "exportedChannelCount": String(summary.channels),
            "exportedNoteCount": String(summary.notes),
            "exportedAutomationCount": String(summary.automations),
            "exportedCalendarCount": String(summary.calendars),
            "exportedCalendarEventCount": String(summary.calendarEvents)
        ]
        metadata["exportedWebSearchRunCount"] = String(webSearchNetworkSummary.totalRuns)
        metadata["exportedWebSearchHostCount"] = String(webSearchNetworkSummary.uniqueHostCount)
        metadata["exportedWebSearchAPIKeyRunCount"] = String(webSearchNetworkSummary.apiKeyRuns)
        metadata["exportedWebSearchFailedRunCount"] = String(webSearchNetworkSummary.failedRuns)
        metadata["exportedWebSearchBlockedRunCount"] = String(webSearchNetworkSummary.blockedRuns)
        return metadata
    }

    private func recordAuditEvent(
        action: AppAuditAction,
        outcome: AppAuditOutcome,
        summary: String,
        metadata: [String: String] = [:]
    ) async {
        let event = AppAuditEvent(
            action: action,
            outcome: outcome,
            summary: summary,
            metadata: metadata
        )
        do {
            try await auditLogStorage.save(event)
            auditEvents.removeAll { $0.id == event.id }
            auditEvents.append(event)
            sortAuditEvents()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func promptAuditMetadata(for prompt: SavedPrompt) -> [String: String] {
        var metadata = [
            "promptID": prompt.id.uuidString,
            "title": prompt.title
        ]
        if let command = prompt.command {
            metadata["command"] = command
        }
        if !prompt.tags.isEmpty {
            metadata["tags"] = prompt.tags.joined(separator: ", ")
        }
        return metadata
    }

    private func noteAuditMetadata(for note: AppNote) -> [String: String] {
        [
            "noteID": note.id.uuidString,
            "isPinned": String(note.isPinned)
        ]
    }

    private func automationAuditMetadata(for automation: AppAutomation) -> [String: String] {
        [
            "automationID": automation.id,
            "modelID": automation.modelID,
            "rrule": automation.rrule,
            "isActive": String(automation.isActive)
        ]
    }

    private func toolAuditMetadata(for tool: AppTool) -> [String: String] {
        var metadata = [
            "toolID": tool.id,
            "name": tool.name
        ]
        if let description = tool.description {
            metadata["description"] = description
        }
        return metadata
    }

    private func defaultFunctionName(for tool: AppTool) -> String? {
        for spec in tool.specs {
            guard let nameValue = spec.objectValue?["name"] else {
                continue
            }
            if case .string(let name) = nameValue {
                let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmedName.isEmpty {
                    return trimmedName
                }
            }
        }
        return "run"
    }

    private func skillAuditMetadata(for skill: AppSkill) -> [String: String] {
        var metadata = [
            "skillID": skill.id,
            "name": skill.name,
            "isActive": String(skill.isActive)
        ]
        if let description = skill.description {
            metadata["description"] = description
        }
        if !skill.tags.isEmpty {
            metadata["tags"] = skill.tags.joined(separator: ", ")
        }
        if !skill.allowedUserIDs.isEmpty {
            metadata["allowedUserIDs"] = skill.allowedUserIDs.joined(separator: ", ")
        }
        if !skill.allowedGroupIDs.isEmpty {
            metadata["allowedGroupIDs"] = skill.allowedGroupIDs.joined(separator: ", ")
        }
        return metadata
    }

    private func functionAuditMetadata(for function: AppFunction) -> [String: String] {
        var metadata = [
            "functionID": function.id,
            "name": function.name,
            "kind": function.kind.rawValue,
            "isActive": String(function.isActive),
            "isGlobal": String(function.isGlobal)
        ]
        if let description = function.description {
            metadata["description"] = description
        }
        return metadata
    }

    private func adminUserAuditMetadata(for user: AdminUser) -> [String: String] {
        [
            "userID": user.id,
            "name": user.name,
            "email": user.email,
            "role": user.role.rawValue
        ]
    }

    private func adminGroupAuditMetadata(for group: AdminGroup) -> [String: String] {
        var metadata = [
            "groupID": group.id,
            "name": group.name,
            "memberCount": String(group.memberIDs.count)
        ]
        if !group.description.isEmpty {
            metadata["description"] = group.description
        }
        if !group.permissions.isEmpty {
            metadata["permissions"] = group.permissions.joined(separator: ", ")
        }
        return metadata
    }

    func openCitationSource(_ citation: ChatCitation) async {
        guard requireKnowledgeFeatureEnabled() else {
            return
        }
        guard let documentID = citation.documentID else {
            errorMessage = "This citation is not linked to an indexed source document."
            return
        }
        do {
            let detail = try await knowledgeService.loadDocumentDetail(id: documentID)
            guard currentUserCanAccessKnowledgeCollection(detail.collection) else {
                selectedKnowledgeDocumentDetail = nil
                selectedKnowledgeChunkID = nil
                errorMessage = "You do not have access to this knowledge collection."
                return
            }
            selectedKnowledgeDocumentDetail = detail
            selectedKnowledgeChunkID = citation.chunkID
            selectedThreadID = nil
            selectedChannelID = nil
            isShowingEvaluationDashboard = false
            isShowingAnalyticsDashboard = false
            isShowingPlayground = false
            isShowingFiles = false
            isShowingCalendar = false
            isShowingImageGeneration = false
            isShowingAudio = false
            isShowingCodeInterpreter = false
            isShowingTerminalSessions = false
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func cancelCurrentSend() {
        guard isSending, let activeSendID else {
            return
        }
        cancelledSendIDs.insert(activeSendID)
        for task in activeAssistantBranchTasks.values {
            task.cancel()
        }
        isCancellingSend = true
    }

    func cancelAssistantBranch(messageID: UUID) {
        guard let threadIndex = currentThreadIndex(),
              let messageIndex = threads[threadIndex].messages.firstIndex(where: { $0.id == messageID }),
              threads[threadIndex].messages[messageIndex].role == .assistant,
              threads[threadIndex].messages[messageIndex].isStreaming else {
            return
        }
        cancelledAssistantBranchIDs.insert(messageID)
        activeAssistantBranchTasks[messageID]?.cancel()
        finishAssistantMessage(id: messageID, error: nil)
    }

    func send(_ prompt: String) async {
        guard !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            errorMessage = ProviderError.emptyPrompt.localizedDescription
            return
        }
        guard canChat else {
            errorMessage = ProviderError.unsupportedChat(activeProvider.name).localizedDescription
            return
        }
        let modelIDs = selectedModelIDs
        guard let primaryModelID = modelIDs.first else {
            errorMessage = ProviderError.noModelSelected.localizedDescription
            return
        }

        if selectedThreadID == nil {
            createThread()
        }

        guard let index = currentThreadIndex() else {
            return
        }

        isSending = true
        isCancellingSend = false
        errorMessage = nil
        let sendID = UUID()
        activeSendID = sendID
        cancelledSendIDs.remove(sendID)
        var assistantMessageID: UUID?

        do {
            let provider = try makeActiveProvider()
            let webCitations = try await webSearchCitations(for: prompt)
            let citations = try await knowledgeCitations(
                for: prompt,
                provider: provider,
                embeddingModel: selectedEmbeddingModelID ?? primaryModelID
            )
            let attachments = pendingAttachments
            let userMessage = ChatMessage(role: .user, content: prompt, attachments: attachments, citations: webCitations + citations)
            let assistantMessages = modelIDs.map { modelID in
                ChatMessage(
                    role: .assistant,
                    content: "",
                    modelID: modelID,
                    isStreaming: true,
                    generationMetrics: ChatGenerationMetrics()
                )
            }
            assistantMessageID = assistantMessages.first?.id
            pendingAttachments = []
            isWebSearchEnabledForNextPrompt = false
            webSearchError = nil

            threads[index].messages.append(userMessage)
            threads[index].messages.append(contentsOf: assistantMessages)
            threads[index].providerID = settings.activeProviderID
            threads[index].modelIDs = modelIDs
            threads[index].title = title(for: prompt)
            threads[index].updatedAt = Date()
            await persistCurrentThread()

            var branchTasks: [(messageID: UUID, task: Task<Void, Never>)] = []
            for assistantMessage in assistantMessages {
                let task = Task { [weak self] in
                    guard let self else {
                        return
                    }
                    await self.streamAssistantBranch(
                        assistantMessage: assistantMessage,
                        provider: provider,
                        fallbackModelID: primaryModelID,
                        sendID: sendID
                    )
                }
                activeAssistantBranchTasks[assistantMessage.id] = task
                branchTasks.append((assistantMessage.id, task))
            }

            for branchTask in branchTasks {
                await branchTask.task.value
                activeAssistantBranchTasks[branchTask.messageID] = nil
            }
            if let index = currentThreadIndex() {
                orderAssistantBranches(assistantMessages.map(\.id), in: index)
            }
        } catch {
            if let assistantMessageID {
                finishAssistantMessage(id: assistantMessageID, error: error.localizedDescription)
            }
            if isWebSearchEnabledForNextPrompt {
                webSearchError = error.localizedDescription
            }
            errorMessage = error.localizedDescription
        }

        isSending = false
        isCancellingSend = false
        if activeSendID == sendID {
            activeSendID = nil
        }
        cancelledSendIDs.remove(sendID)
        await persistCurrentThread()
    }

    private func streamAssistantBranch(
        assistantMessage: ChatMessage,
        provider: any ChatProvider,
        fallbackModelID: String,
        sendID: UUID
    ) async {
        guard let threadIndex = currentThreadIndex() else {
            return
        }

        do {
            var providerMessages = providerMessages(
                for: threads[threadIndex],
                throughMessageID: assistantMessage.id,
                excludingMessageID: assistantMessage.id
            )
            providerMessages = try await applyActiveFilterFunctions(methodName: "inlet", to: providerMessages)

            var wasCancelled = false
            let modelID = assistantMessage.modelID ?? fallbackModelID
            if let pipeFunction = pipeFunction(for: modelID) {
                try await runPipeFunction(
                    pipeFunction,
                    modelID: modelID,
                    providerMessages: providerMessages,
                    assistantMessageID: assistantMessage.id
                )
            } else {
                for try await event in provider.streamChatEvents(
                    model: modelID,
                    messages: providerMessages
                ) {
                    if Task.isCancelled || isSendCancelled(sendID) || isAssistantBranchCancelled(assistantMessage.id) {
                        wasCancelled = true
                        break
                    }
                    guard let threadIndex = currentThreadIndex(),
                          let messageIndex = threads[threadIndex].messages.firstIndex(where: { $0.id == assistantMessage.id }) else {
                        continue
                    }
                    switch event {
                    case .content(let chunk):
                        threads[threadIndex].messages[messageIndex].content += chunk
                    case .tokenUsage(let tokenUsage):
                        threads[threadIndex].messages[messageIndex].tokenUsage = tokenUsage
                    }
                    threads[threadIndex].updatedAt = Date()
                }
            }

            if !wasCancelled {
                try await applyActiveOutletFilters(to: assistantMessage.id)
            }
            finishAssistantMessage(id: assistantMessage.id, error: nil)
        } catch is CancellationError {
            finishAssistantMessage(id: assistantMessage.id, error: nil)
        } catch {
            finishAssistantMessage(id: assistantMessage.id, error: error.localizedDescription)
        }
        cancelledAssistantBranchIDs.remove(assistantMessage.id)
    }

    private func isSendCancelled(_ sendID: UUID) -> Bool {
        cancelledSendIDs.contains(sendID)
    }

    private func isAssistantBranchCancelled(_ messageID: UUID) -> Bool {
        cancelledAssistantBranchIDs.contains(messageID)
    }

    private func finishAssistantMessage(id: UUID, error: String?) {
        guard let threadIndex = currentThreadIndex(),
              let messageIndex = threads[threadIndex].messages.firstIndex(where: { $0.id == id }) else {
            return
        }
        threads[threadIndex].messages[messageIndex].isStreaming = false
        threads[threadIndex].messages[messageIndex].error = error
        if let generationMetrics = threads[threadIndex].messages[messageIndex].generationMetrics,
           generationMetrics.completedAt == nil {
            threads[threadIndex].messages[messageIndex].generationMetrics = generationMetrics.completed()
        }
        threads[threadIndex].updatedAt = Date()
    }

    private func orderAssistantBranches(_ messageIDs: [UUID], in threadIndex: Array<ChatThread>.Index) {
        let order = Dictionary(uniqueKeysWithValues: messageIDs.enumerated().map { ($0.element, $0.offset) })
        let branchMessages = threads[threadIndex].messages
            .filter { message in
                order[message.id] != nil
            }
            .sorted { lhs, rhs in
                (order[lhs.id] ?? Int.max) < (order[rhs.id] ?? Int.max)
            }
        var branchIterator = branchMessages.makeIterator()
        threads[threadIndex].messages = threads[threadIndex].messages.map { message in
            guard order[message.id] != nil, let nextBranch = branchIterator.next() else {
                return message
            }
            return nextBranch
        }
    }

    private func persistCurrentThread() async {
        guard let thread = selectedThread else {
            return
        }
        do {
            try await storage.save(thread)
            sortThreads()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func persistThread(at index: Array<ChatThread>.Index) async {
        do {
            try await storage.save(threads[index])
            sortThreads()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func currentThreadIndex() -> Array<ChatThread>.Index? {
        guard let selectedThreadID else {
            return nil
        }
        return threads.firstIndex { $0.id == selectedThreadID }
    }

    private func threadIndex(containing messageID: UUID) -> Array<ChatThread>.Index? {
        threads.firstIndex { thread in
            thread.messages.contains { $0.id == messageID }
        }
    }

    private func providerMessages(
        for thread: ChatThread,
        throughMessageID: UUID? = nil,
        excludingMessageID: UUID? = nil
    ) -> [ProviderChatMessage] {
        var messages = thread.messages
        if let throughMessageID,
           let endIndex = messages.firstIndex(where: { $0.id == throughMessageID }) {
            messages = Array(messages.prefix(upTo: endIndex))
        }
        if let excludingMessageID {
            messages.removeAll { $0.id == excludingMessageID }
        }

        var providerMessages = messages
            .filter { !$0.isStreaming && $0.error == nil }
            .map { message in
                ProviderChatMessage(role: message.role.rawValue, content: providerContent(for: message))
            }

        if let activeSkillContext = activeSkillProviderContext() {
            providerMessages.insert(
                ProviderChatMessage(role: ChatRole.system.rawValue, content: activeSkillContext),
                at: 0
            )
        }

        return providerMessages
    }

    private func applyActiveOutletFilters(to assistantMessageID: UUID) async throws {
        guard let outletMessages = providerMessagesIncludingAssistant(assistantMessageID: assistantMessageID) else {
            return
        }
        let filteredMessages = try await applyActiveFilterFunctions(methodName: "outlet", to: outletMessages)
        guard let filteredAssistant = filteredMessages.reversed().first(where: { $0.role == ChatRole.assistant.rawValue }),
              let threadIndex = currentThreadIndex(),
              let messageIndex = threads[threadIndex].messages.firstIndex(where: { $0.id == assistantMessageID }) else {
            return
        }
        threads[threadIndex].messages[messageIndex].content = filteredAssistant.content
        threads[threadIndex].updatedAt = Date()
    }

    private func providerMessagesIncludingAssistant(assistantMessageID: UUID) -> [ProviderChatMessage]? {
        guard let threadIndex = currentThreadIndex(),
              let assistantIndex = threads[threadIndex].messages.firstIndex(where: { $0.id == assistantMessageID }) else {
            return nil
        }

        var messages = providerMessages(
            for: threads[threadIndex],
            throughMessageID: assistantMessageID,
            excludingMessageID: nil
        )
        let assistantMessage = threads[threadIndex].messages[assistantIndex]
        messages.append(ProviderChatMessage(role: ChatRole.assistant.rawValue, content: providerContent(for: assistantMessage)))
        return messages
    }

    private func runPipeFunction(
        _ function: AppFunction,
        modelID: String,
        providerMessages: [ProviderChatMessage],
        assistantMessageID: UUID
    ) async throws {
        let input = pipeInvocationInput(modelID: modelID, messages: providerMessages)
        let run = await functionExecutor.invoke(
            LocalFunctionInvocationRequest(
                function: function,
                methodName: "pipe",
                input: input,
                inputBody: jsonBodyString(for: input),
                timeoutSeconds: min(max(codeExecutionTimeoutSeconds, 0.1), max(settings.codeExecution.maxTimeoutSeconds, 0.1))
            )
        )
        try await persistFunctionRun(run)
        guard run.status == .succeeded else {
            throw FunctionFilterExecutionError(run: run)
        }
        appendAssistantContent(run.output, to: assistantMessageID)
    }

    private func appendAssistantContent(_ content: String, to assistantMessageID: UUID) {
        guard let threadIndex = currentThreadIndex(),
              let messageIndex = threads[threadIndex].messages.firstIndex(where: { $0.id == assistantMessageID }) else {
            return
        }
        threads[threadIndex].messages[messageIndex].content += content
        threads[threadIndex].updatedAt = Date()
    }

    private func applyActiveFilterFunctions(
        methodName: String,
        to providerMessages: [ProviderChatMessage]
    ) async throws -> [ProviderChatMessage] {
        var filteredMessages = providerMessages
        let filters = activeFilterFunctions(defining: methodName)
        guard !filters.isEmpty else {
            return filteredMessages
        }

        for function in filters {
            let input = filterInvocationInput(for: filteredMessages)
            let run = await functionExecutor.invoke(
                LocalFunctionInvocationRequest(
                    function: function,
                    methodName: methodName,
                    input: input,
                    inputBody: jsonBodyString(for: input),
                    timeoutSeconds: min(max(codeExecutionTimeoutSeconds, 0.1), max(settings.codeExecution.maxTimeoutSeconds, 0.1))
                )
            )
            try await persistFunctionRun(run)
            guard run.status == .succeeded else {
                throw FunctionFilterExecutionError(run: run)
            }
            filteredMessages = try filteredProviderMessages(from: run.output, fallback: filteredMessages)
        }

        return filteredMessages
    }

    private func activeFilterFunctions(defining methodName: String) -> [AppFunction] {
        functions
            .filter { $0.kind == .filter && $0.isActive && function($0, defines: methodName) }
            .sorted { lhs, rhs in
                if lhs.isGlobal != rhs.isGlobal {
                    return lhs.isGlobal && !rhs.isGlobal
                }
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
    }

    private func function(_ function: AppFunction, defines methodName: String) -> Bool {
        let escapedMethod = NSRegularExpression.escapedPattern(for: methodName)
        let pattern = #"(?m)^\s*(async\s+)?def\s+\#(escapedMethod)\s*\("#
        return function.content.range(of: pattern, options: .regularExpression) != nil
    }

    private func filterInvocationInput(for messages: [ProviderChatMessage]) -> JSONValue {
        .object([
            "body": .object([
                "messages": .array(messages.map { message in
                    .object([
                        "role": .string(message.role),
                        "content": .string(message.content)
                    ])
                })
            ])
        ])
    }

    private func pipeInvocationInput(modelID: String, messages: [ProviderChatMessage]) -> JSONValue {
        .object([
            "body": .object([
                "model": .string(modelID),
                "messages": .array(messages.map { message in
                    .object([
                        "role": .string(message.role),
                        "content": .string(message.content)
                    ])
                })
            ])
        ])
    }

    private func actionInvocationInput(thread: ChatThread, message: ChatMessage) -> JSONValue {
        .object([
            "body": .object([
                "message": chatMessageJSON(message),
                "thread": chatThreadSummaryJSON(thread),
                "messages": .array(thread.messages.map(chatMessageJSON)
                )
            ])
        ])
    }

    private func chatThreadSummaryJSON(_ thread: ChatThread) -> JSONValue {
        .object([
            "id": .string(thread.id.uuidString),
            "title": .string(thread.title),
            "user_id": .string(thread.userID),
            "model_ids": .array(thread.modelIDs.map { .string($0) }),
            "tags": .array(thread.tags.map { .string($0) }),
            "created_at": .string(Self.iso8601String(from: thread.createdAt)),
            "updated_at": .string(Self.iso8601String(from: thread.updatedAt))
        ])
    }

    private func chatMessageJSON(_ message: ChatMessage) -> JSONValue {
        var object: [String: JSONValue] = [
            "id": .string(message.id.uuidString),
            "role": .string(message.role.rawValue),
            "content": .string(message.content),
            "created_at": .string(Self.iso8601String(from: message.createdAt)),
            "is_streaming": .bool(message.isStreaming),
            "attachments": .array(message.attachments.map(chatAttachmentJSON)),
            "citations": .array(message.citations.map(chatCitationJSON))
        ]
        if let modelID = message.modelID {
            object["model"] = .string(modelID)
        }
        if let updatedAt = message.updatedAt {
            object["updated_at"] = .string(Self.iso8601String(from: updatedAt))
        }
        if let rating = message.rating {
            object["rating"] = .string(rating.rawValue)
        }
        if let error = message.error {
            object["error"] = .string(error)
        }
        return .object(object)
    }

    private func chatAttachmentJSON(_ attachment: ChatAttachment) -> JSONValue {
        var object: [String: JSONValue] = [
            "id": .string(attachment.id.uuidString),
            "file_name": .string(attachment.fileName),
            "content_type": .string(attachment.contentType),
            "byte_count": .number(Double(attachment.byteCount)),
            "created_at": .string(Self.iso8601String(from: attachment.createdAt))
        ]
        if let textContent = attachment.textContent {
            object["text_content"] = .string(textContent)
        }
        return .object(object)
    }

    private func chatCitationJSON(_ citation: ChatCitation) -> JSONValue {
        var object: [String: JSONValue] = [
            "id": .string(citation.id.uuidString),
            "collection_name": .string(citation.collectionName),
            "collection_slug": .string(citation.collectionSlug),
            "source_name": .string(citation.sourceName),
            "text": .string(citation.text),
            "score": .number(citation.score)
        ]
        if let collectionID = citation.collectionID {
            object["collection_id"] = .string(collectionID.uuidString)
        }
        if let documentID = citation.documentID {
            object["document_id"] = .string(documentID.uuidString)
        }
        if let chunkID = citation.chunkID {
            object["chunk_id"] = .string(chunkID.uuidString)
        }
        return .object(object)
    }

    private func filteredProviderMessages(
        from output: String,
        fallback: [ProviderChatMessage]
    ) throws -> [ProviderChatMessage] {
        let trimmedOutput = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedOutput.isEmpty,
              let data = trimmedOutput.data(using: .utf8) else {
            return fallback
        }

        let value = try JSONDecoder.openWebUIDecoder.decode(JSONValue.self, from: data)
        guard let object = value.objectValue else {
            throw FunctionFilterOutputError(message: "Function filter output must be a JSON object.")
        }
        guard let messagesValue = object["messages"] else {
            return fallback
        }
        guard case .array(let messageValues) = messagesValue else {
            throw FunctionFilterOutputError(message: "Function filter messages must be a JSON array.")
        }

        return try messageValues.map { value in
            guard let messageObject = value.objectValue,
                  case .string(let role)? = messageObject["role"],
                  case .string(let content)? = messageObject["content"] else {
                throw FunctionFilterOutputError(message: "Function filter messages must include string role and content.")
            }
            return ProviderChatMessage(role: role, content: content)
        }
    }

    private func persistFunctionRun(_ run: AppFunctionRun) async throws {
        try await functionRunStorage.save(run)
        functionRuns.removeAll { $0.id == run.id }
        functionRuns.append(run)
        sortFunctionRuns()
        selectedFunctionRunID = run.id
        await recordAuditEvent(
            action: .functionInvoked,
            outcome: run.status == .succeeded ? .succeeded : .failed,
            summary: "\(run.functionName) function \(run.methodName) \(run.status.rawValue)",
            metadata: [
                "functionID": run.functionID,
                "functionName": run.functionName,
                "functionKind": run.functionKind.rawValue,
                "methodName": run.methodName,
                "status": run.status.rawValue,
                "runID": run.id.uuidString
            ]
        )
    }

    private func jsonBodyString(for value: JSONValue) -> String {
        guard let data = try? JSONEncoder.openWebUIEncoder.encode(value),
              let body = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return body
    }

    private func functionValves(from valvesJSON: String?) throws -> JSONValue? {
        guard let valvesJSON else {
            return nil
        }
        let trimmedValves = valvesJSON.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedValves.isEmpty else {
            return nil
        }
        guard let data = trimmedValves.data(using: .utf8),
              let value = try? JSONDecoder.openWebUIDecoder.decode(JSONValue.self, from: data),
              value.objectValue != nil else {
            throw FunctionValvesValidationError()
        }
        return value
    }

    private func toolValves(from valvesJSON: String?) throws -> JSONValue? {
        guard let valvesJSON else {
            return nil
        }
        let trimmedValves = valvesJSON.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedValves.isEmpty else {
            return nil
        }
        guard let data = trimmedValves.data(using: .utf8),
              let value = try? JSONDecoder.openWebUIDecoder.decode(JSONValue.self, from: data),
              value.objectValue != nil else {
            throw ToolValvesValidationError()
        }
        return value
    }

    private func validatedToolValves(
        from valvesJSON: String?,
        name: String,
        content: String
    ) async throws -> JSONValue? {
        guard let valves = try toolValves(from: valvesJSON) else {
            return nil
        }
        guard let schema = await toolValvesSchema(name: name, content: content),
              let validationError = toolArgumentTemplateService.validationError(
                for: valves,
                schema: schema,
                valueLabel: "Tool valve",
                missingLabel: "Missing required tool valve"
              ) else {
            return valves
        }
        throw ToolValvesSchemaValidationError(message: validationError)
    }

    private func toolValvesSchema(name: String, content: String) async -> JSONValue? {
        guard requireToolsFeatureEnabled() else {
            return nil
        }

        let tool = AppTool(
            name: name,
            content: content
        )
        let run = await toolExecutor.invoke(
            LocalToolInvocationRequest(
                tool: tool,
                functionName: "__native_valves_schema",
                arguments: .object([:]),
                argumentsBody: "{}",
                timeoutSeconds: min(max(codeExecutionTimeoutSeconds, 0.1), max(settings.codeExecution.maxTimeoutSeconds, 0.1))
            )
        )
        guard run.status == .succeeded,
              let data = run.output.trimmingCharacters(in: .whitespacesAndNewlines).data(using: .utf8),
              let schema = try? JSONDecoder.openWebUIDecoder.decode(JSONValue.self, from: data),
              case .string("object")? = schema.objectValue?["type"] else {
            return nil
        }
        return schema
    }

    private func validatedFunctionValves(
        from valvesJSON: String?,
        name: String,
        kind: AppFunctionKind,
        content: String
    ) async throws -> JSONValue? {
        guard let valves = try functionValves(from: valvesJSON) else {
            return nil
        }
        guard let schema = await functionValvesSchema(name: name, kind: kind, content: content),
              let validationError = toolArgumentTemplateService.validationError(
                for: valves,
                schema: schema,
                valueLabel: "Function valve",
                missingLabel: "Missing required function valve"
              ) else {
            return valves
        }
        throw FunctionValvesSchemaValidationError(message: validationError)
    }

    private func functionValvesSchema(name: String, kind: AppFunctionKind, content: String) async -> JSONValue? {
        guard requireFunctionsFeatureEnabled() else {
            return nil
        }

        let function = AppFunction(
            name: name,
            kind: kind,
            content: content
        )
        let run = await functionExecutor.invoke(
            LocalFunctionInvocationRequest(
                function: function,
                methodName: "__native_valves_schema",
                input: .object([:]),
                inputBody: "{}",
                timeoutSeconds: min(max(codeExecutionTimeoutSeconds, 0.1), max(settings.codeExecution.maxTimeoutSeconds, 0.1))
            )
        )
        guard run.status == .succeeded,
              let data = run.output.trimmingCharacters(in: .whitespacesAndNewlines).data(using: .utf8),
              let schema = try? JSONDecoder.openWebUIDecoder.decode(JSONValue.self, from: data),
              case .string("object")? = schema.objectValue?["type"] else {
            return nil
        }
        return schema
    }

    private static func iso8601String(from date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }

    private func activeSkillProviderContext() -> String? {
        guard isFeatureEnabled(.skills) else {
            return nil
        }

        let activeSkills = skills
            .filter { $0.isActive }
            .filter { currentUserCanAccessSkill($0) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

        guard !activeSkills.isEmpty else {
            return nil
        }

        let skillBlocks = activeSkills.map { skill in
            var lines = ["- \(skill.name)"]
            if let description = skill.description, !description.isEmpty {
                lines.append("  Description: \(description)")
            }
            if !skill.tags.isEmpty {
                lines.append("  Tags: \(skill.tags.joined(separator: ", "))")
            }
            lines.append("  Instructions: \(skill.content)")
            return lines.joined(separator: "\n")
        }

        return """
        Active Open WebUI skills:
        \(skillBlocks.joined(separator: "\n\n"))
        """
    }

    private func currentUserCanAccessSkill(_ skill: AppSkill) -> Bool {
        guard !skill.allowedUserIDs.isEmpty || !skill.allowedGroupIDs.isEmpty else {
            return true
        }
        guard !adminUsers.isEmpty else {
            return true
        }
        guard let user = adminUsers.first(where: { $0.id == currentUserID }) else {
            return true
        }
        if user.role == .admin {
            return true
        }
        if skill.allowedUserIDs.contains(currentUserID) {
            return true
        }
        return adminGroups.contains { group in
            group.memberIDs.contains(currentUserID) && skill.allowedGroupIDs.contains(group.id)
        }
    }

    private func currentUserCanAccessKnowledgeCollection(_ collection: KnowledgeCollection) -> Bool {
        guard !collection.allowedUserIDs.isEmpty || !collection.allowedGroupIDs.isEmpty else {
            return true
        }
        guard !adminUsers.isEmpty else {
            return true
        }
        guard let user = adminUsers.first(where: { $0.id == currentUserID }) else {
            return true
        }
        if user.role == .admin {
            return true
        }
        if collection.allowedUserIDs.contains(currentUserID) {
            return true
        }
        return adminGroups.contains { group in
            group.memberIDs.contains(currentUserID) && collection.allowedGroupIDs.contains(group.id)
        }
    }

    private func currentUserCanAccessCalendar(_ calendar: AppCalendar) -> Bool {
        guard !calendar.allowedUserIDs.isEmpty || !calendar.allowedGroupIDs.isEmpty else {
            return true
        }
        guard !adminUsers.isEmpty else {
            return true
        }
        guard let user = adminUsers.first(where: { $0.id == currentUserID }) else {
            return true
        }
        if user.role == .admin {
            return true
        }
        if calendar.allowedUserIDs.contains(currentUserID) {
            return true
        }
        return adminGroups.contains { group in
            group.memberIDs.contains(currentUserID) && calendar.allowedGroupIDs.contains(group.id)
        }
    }

    private func requireSkillWritePermission() -> Bool {
        guard currentUserCanManageSkills else {
            errorMessage = "You do not have permission to manage skills."
            return false
        }

        return true
    }

    private var skillsDisabledMessage: String {
        "\(AppFeatureToggle.skills.label) is disabled."
    }

    private func requireSkillsFeatureEnabled() -> Bool {
        guard isFeatureEnabled(.skills) else {
            errorMessage = skillsDisabledMessage
            return false
        }

        return true
    }

    private func requirePromptWritePermission() -> Bool {
        guard currentUserCanManagePrompts else {
            errorMessage = "You do not have permission to manage prompts."
            return false
        }

        return true
    }

    private var promptsDisabledMessage: String {
        "\(AppFeatureToggle.prompts.label) is disabled."
    }

    private func requirePromptsFeatureEnabled() -> Bool {
        guard isFeatureEnabled(.prompts) else {
            errorMessage = promptsDisabledMessage
            return false
        }

        return true
    }

    private var filesDisabledMessage: String {
        "\(AppFeatureToggle.files.label) is disabled."
    }

    private func requireFilesFeatureEnabled() -> Bool {
        guard isFeatureEnabled(.files) else {
            errorMessage = filesDisabledMessage
            return false
        }

        return true
    }

    private var foldersDisabledMessage: String {
        "\(AppFeatureToggle.folders.label) is disabled."
    }

    private func requireFoldersFeatureEnabled() -> Bool {
        guard isFeatureEnabled(.folders) else {
            errorMessage = foldersDisabledMessage
            return false
        }

        return true
    }

    private var notesDisabledMessage: String {
        "\(AppFeatureToggle.notes.label) is disabled."
    }

    private func requireNotesFeatureEnabled() -> Bool {
        guard isFeatureEnabled(.notes) else {
            errorMessage = notesDisabledMessage
            return false
        }

        return true
    }

    private func requireNoteWritePermission() -> Bool {
        guard currentUserCanManageNotes else {
            errorMessage = "You do not have permission to manage notes."
            return false
        }

        return true
    }

    private func requireToolWritePermission() -> Bool {
        guard currentUserCanManageTools else {
            errorMessage = "You do not have permission to manage tools."
            return false
        }

        return true
    }

    private var toolsDisabledMessage: String {
        "\(AppFeatureToggle.tools.label) is disabled."
    }

    private func requireToolsFeatureEnabled() -> Bool {
        guard isFeatureEnabled(.tools) else {
            errorMessage = toolsDisabledMessage
            return false
        }

        return true
    }

    private func requireToolExecutionPermission() -> Bool {
        guard currentUserCanInvokeTools else {
            toolExecutionError = "You do not have permission to run tools."
            errorMessage = toolExecutionError
            return false
        }

        return true
    }

    private func requireToolServerWritePermission() -> Bool {
        guard currentUserCanManageTools else {
            errorMessage = "You do not have permission to manage tool servers."
            return false
        }

        return true
    }

    private var directToolServersDisabledMessage: String {
        "\(AppFeatureToggle.directToolServers.label) is disabled."
    }

    private func requireDirectToolServersFeatureEnabled() -> Bool {
        guard isFeatureEnabled(.directToolServers) else {
            errorMessage = directToolServersDisabledMessage
            return false
        }

        return true
    }

    private func requireToolServerExecutionPermission() -> Bool {
        guard currentUserCanInvokeTools else {
            toolServerInvocationError = "You do not have permission to run tool servers."
            errorMessage = toolServerInvocationError
            return false
        }

        return true
    }

    private func requireFunctionWritePermission() -> Bool {
        guard currentUserCanManageFunctions else {
            errorMessage = "You do not have permission to manage functions."
            return false
        }

        return true
    }

    private var functionsDisabledMessage: String {
        "\(AppFeatureToggle.functions.label) is disabled."
    }

    private func requireFunctionsFeatureEnabled() -> Bool {
        guard isFeatureEnabled(.functions) else {
            errorMessage = functionsDisabledMessage
            return false
        }

        return true
    }

    private func requireFunctionExecutionPermission() -> Bool {
        guard currentUserCanInvokeFunctions else {
            functionExecutionError = "You do not have permission to run functions."
            errorMessage = functionExecutionError
            return false
        }

        return true
    }

    private var knowledgeDisabledMessage: String {
        "\(AppFeatureToggle.knowledge.label) is disabled."
    }

    private func requireKnowledgeFeatureEnabled() -> Bool {
        guard isFeatureEnabled(.knowledge) else {
            errorMessage = knowledgeDisabledMessage
            return false
        }

        return true
    }

    private func requireKnowledgeWritePermission() -> Bool {
        guard currentUserCanManageKnowledge else {
            errorMessage = "You do not have permission to manage knowledge."
            return false
        }

        return true
    }

    private func requireChannelWritePermission() -> Bool {
        guard currentUserCanManageChannels else {
            errorMessage = "You do not have permission to manage channels."
            return false
        }

        return true
    }

    private var channelsDisabledMessage: String {
        "\(AppFeatureToggle.channels.label) is disabled."
    }

    private func requireChannelsFeatureEnabled() -> Bool {
        guard isFeatureEnabled(.channels) else {
            errorMessage = channelsDisabledMessage
            return false
        }

        return true
    }

    private var automationsDisabledMessage: String {
        "\(AppFeatureToggle.automations.label) is disabled."
    }

    private func requireAutomationsFeatureEnabled() -> Bool {
        guard isFeatureEnabled(.automations) else {
            errorMessage = automationsDisabledMessage
            return false
        }

        return true
    }

    private func requireAutomationWritePermission() -> Bool {
        guard currentUserCanManageAutomations else {
            errorMessage = "You do not have permission to manage automations."
            return false
        }

        return true
    }

    private var calendarDisabledMessage: String {
        "\(AppFeatureToggle.calendar.label) is disabled."
    }

    private func requireCalendarFeatureEnabled() -> Bool {
        guard isFeatureEnabled(.calendar) else {
            errorMessage = calendarDisabledMessage
            return false
        }

        return true
    }

    private func requireCalendarWritePermission() -> Bool {
        guard currentUserCanManageCalendar else {
            errorMessage = "You do not have permission to manage calendar."
            return false
        }

        return true
    }

    private func requireAdminDirectoryWritePermission() -> Bool {
        guard currentUserCanManageAdminDirectory else {
            errorMessage = "You do not have permission to manage admin directory."
            return false
        }

        return true
    }

    private func requirePlaygroundExecutionPermission() -> Bool {
        guard currentUserCanUsePlayground else {
            playgroundError = "You do not have permission to use playground."
            errorMessage = playgroundError
            return false
        }

        return true
    }

    private func requirePlaygroundFeatureEnabled() -> Bool {
        guard isFeatureEnabled(.playground) else {
            playgroundOutput = ""
            playgroundComparisonOutput = ""
            playgroundComparisonError = nil
            playgroundImageOutputs = []
            playgroundError = "\(AppFeatureToggle.playground.label) is disabled."
            errorMessage = playgroundError
            isRunningPlayground = false
            return false
        }

        return true
    }

    private func requirePlaygroundHistoryWritePermission() -> Bool {
        guard currentUserCanManagePlaygroundHistory else {
            errorMessage = "You do not have permission to manage playground history."
            return false
        }

        return true
    }

    private func requireImageGenerationFeatureEnabled() -> Bool {
        guard isFeatureEnabled(.imageGeneration) else {
            imageGenerationError = "\(AppFeatureToggle.imageGeneration.label) is disabled."
            errorMessage = imageGenerationError
            return false
        }

        return true
    }

    private func requireImageGenerationPermission() -> Bool {
        guard currentUserCanGenerateImages else {
            imageGenerationError = "You do not have permission to generate images."
            errorMessage = imageGenerationError
            return false
        }

        return true
    }

    private func requireGeneratedImageWritePermission() -> Bool {
        guard currentUserCanManageGeneratedImages else {
            errorMessage = "You do not have permission to manage generated images."
            return false
        }

        return true
    }

    private func requireAudioFeatureEnabled() -> Bool {
        guard isFeatureEnabled(.audio) else {
            audioError = "\(AppFeatureToggle.audio.label) is disabled."
            errorMessage = audioError
            return false
        }

        return true
    }

    private func requireVoiceModeFeatureEnabled() -> Bool {
        guard isFeatureEnabled(.voiceMode) else {
            audioError = "\(AppFeatureToggle.voiceMode.label) is disabled."
            errorMessage = audioError
            isRunningVoiceMode = false
            return false
        }

        return true
    }

    private func requireAudioTranscriptionPermission() -> Bool {
        guard currentUserCanTranscribeAudio else {
            audioError = "You do not have permission to transcribe audio."
            errorMessage = audioError
            return false
        }

        return true
    }

    private func requireSpeechSynthesisPermission() -> Bool {
        guard currentUserCanSynthesizeSpeech else {
            audioError = "You do not have permission to synthesize speech."
            errorMessage = audioError
            return false
        }

        return true
    }

    private func requireAudioHistoryWritePermission() -> Bool {
        guard currentUserCanManageAudioHistory else {
            audioError = "You do not have permission to manage audio history."
            errorMessage = audioError
            return false
        }

        return true
    }

    private func requireCodeInterpreterFeatureEnabled() -> Bool {
        guard isFeatureEnabled(.codeInterpreter) else {
            codeExecutionError = "\(AppFeatureToggle.codeInterpreter.label) is disabled."
            errorMessage = codeExecutionError
            return false
        }

        return true
    }

    private func requireCodeExecutionPermission() -> Bool {
        guard currentUserCanRunCode else {
            codeExecutionError = "You do not have permission to run code."
            errorMessage = codeExecutionError
            return false
        }

        return true
    }

    private func requireTerminalSessionsFeatureEnabled() -> Bool {
        guard isFeatureEnabled(.terminalSessions) else {
            terminalError = "\(AppFeatureToggle.terminalSessions.label) is disabled."
            errorMessage = terminalError
            return false
        }

        return true
    }

    private func requireTerminalExecutionPermission() -> Bool {
        guard currentUserCanUseTerminal else {
            terminalError = "You do not have permission to use terminal sessions."
            errorMessage = terminalError
            return false
        }

        return true
    }

    private func requireTerminalManagementPermission() -> Bool {
        guard currentUserCanManageTerminalSessions else {
            terminalError = "You do not have permission to manage terminal sessions."
            errorMessage = terminalError
            return false
        }

        return true
    }

    private func requireTerminalSessionCreationPermission() -> Bool {
        guard currentUserCanCreateTerminalSessions else {
            terminalError = "You do not have permission to create terminal sessions."
            errorMessage = terminalError
            return false
        }

        return true
    }

    private func makeActiveProvider() throws -> any ChatProvider {
        if let providerOverride {
            return providerOverride
        }
        return try ProviderFactory(secretStore: secretStore).makeProvider(for: settings.activeProvider)
    }

    private func makeOllamaModelManager() throws -> any OllamaModelManaging {
        guard canManageOllamaModels else {
            throw ProviderError.unsupportedModelManagement(activeProvider.name)
        }
        if let manager = providerOverride as? any OllamaModelManaging {
            return manager
        }
        guard let baseURL = URL(string: activeProvider.baseURL), baseURL.scheme != nil else {
            throw ProviderError.invalidBaseURL(activeProvider.baseURL)
        }
        return OllamaClient(baseURL: baseURL, configuration: activeProvider)
    }

    private func refreshKnowledgeState() async throws {
        let collections = try await knowledgeService.loadCollections()
            .filter { currentUserCanAccessKnowledgeCollection($0) }
        var documentsByCollection: [UUID: [KnowledgeDocument]] = [:]
        for collection in collections {
            documentsByCollection[collection.id] = try await knowledgeService.loadDocuments(collectionID: collection.id)
        }
        knowledgeCollections = collections
        knowledgeDocuments = documentsByCollection
    }

    private func readImportedDocument(from url: URL, requiresExtractedText: Bool) throws -> ImportedTextDocument {
        let didStartAccessing = url.startAccessingSecurityScopedResource()
        defer {
            if didStartAccessing {
                url.stopAccessingSecurityScopedResource()
            }
        }

        let data = try Data(contentsOf: url)
        let contentType = UTType(filenameExtension: url.pathExtension)?.preferredMIMEType ?? "text/plain"
        let sourceKind = knowledgeSourceKind(for: url, contentType: contentType)
        let text: String?
        if UTType(filenameExtension: url.pathExtension) == .pdf || contentType == "application/pdf" {
            text = extractPDFText(from: data)
        } else {
            text = String(data: data, encoding: .utf8)
        }

        if requiresExtractedText, text?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false {
            throw ProviderError.unsupportedAttachment(url.lastPathComponent)
        }

        return ImportedTextDocument(
            fileName: url.lastPathComponent,
            contentType: contentType,
            text: text ?? "",
            originalData: data,
            byteCount: data.count,
            sourceKind: sourceKind
        )
    }

    private func knowledgeSourceKind(for url: URL, contentType: String) -> KnowledgeDocumentSourceKind {
        let pathExtension = url.pathExtension.lowercased()
        let lowercasedContentType = contentType.lowercased()

        if lowercasedContentType == "application/pdf" || pathExtension == "pdf" {
            return .pdf
        }
        if lowercasedContentType == "text/markdown" || ["md", "markdown"].contains(pathExtension) {
            return .markdown
        }
        if lowercasedContentType.hasPrefix("text/") {
            return .plainText
        }
        return .unknown
    }

    private func fileUTType(for file: AppFile) -> UTType {
        let extensionType = UTType(filenameExtension: URL(fileURLWithPath: file.fileName).pathExtension)
        let mimeType = UTType(mimeType: file.contentType)
        return extensionType ?? mimeType ?? .data
    }

    private func temporaryShareURL(for file: AppFile) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("OpenWebUINativeSharedFiles", isDirectory: true)
            .appendingPathComponent(file.id.uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent(file.fileName)
    }

    private func extractPDFText(from data: Data) -> String? {
        guard let document = PDFDocument(data: data) else {
            return nil
        }

        let pageText = (0..<document.pageCount).compactMap { pageIndex in
            document.page(at: pageIndex)?.string
        }
        let text = pageText.joined(separator: "\n")
        return text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : text
    }

    private func updateProvider(_ provider: ProviderConfiguration) {
        if let index = settings.providers.firstIndex(where: { $0.id == provider.id }) {
            settings.providers[index] = provider
        } else {
            settings.providers.append(provider)
        }
    }

    private func makeToolServer(
        id: String,
        name: String,
        kind: AppToolServerKind,
        command: String,
        argumentsText: String,
        baseURL: String,
        environmentText: String,
        isEnabled: Bool,
        createdAt: Date,
        updatedAt: Date
    ) -> AppToolServer? {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            return nil
        }

        switch kind {
        case .stdio:
            let trimmedCommand = command.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedCommand.isEmpty else {
                return nil
            }
            return AppToolServer(
                id: id,
                name: trimmedName,
                kind: .stdio,
                command: trimmedCommand,
                arguments: parseToolServerArguments(argumentsText),
                environment: parseToolServerEnvironment(environmentText),
                isEnabled: isEnabled,
                createdAt: createdAt,
                updatedAt: updatedAt
            )
        case .http:
            let trimmedBaseURL = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedBaseURL.isEmpty else {
                return nil
            }
            return AppToolServer(
                id: id,
                name: trimmedName,
                kind: .http,
                baseURL: trimmedBaseURL,
                isEnabled: isEnabled,
                createdAt: createdAt,
                updatedAt: updatedAt
            )
        }
    }

    private func parseToolServerArguments(_ text: String) -> [String] {
        text.split { character in
            character == "," || character.isNewline
        }
        .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
    }

    private func parseToolServerEnvironment(_ text: String) -> [String: String] {
        var environment: [String: String] = [:]
        for line in text.split(whereSeparator: \.isNewline) {
            let parts = line.split(separator: "=", maxSplits: 1).map(String.init)
            guard parts.count == 2 else {
                continue
            }
            let key = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
            let value = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
            if !key.isEmpty, !value.isEmpty {
                environment[key] = value
            }
        }
        return environment
    }

    private func replaceWorkspace(with backup: WorkspaceBackup) async throws {
        try await deletePersistedWorkspaceRecords()

        settings = backup.settings
        threads = backup.threads
        folders = backup.folders
        files = backup.files
        prompts = backup.prompts
        notes = backup.notes
        tools = backup.tools
        toolRuns = backup.toolRuns
        functions = backup.functions
        functionRuns = backup.functionRuns
        skills = backup.skills
        feedbacks = backup.feedbacks
        adminUsers = backup.adminDirectory.users
        adminGroups = backup.adminDirectory.groups
        channels = backup.channels
        automations = backup.automations
        automationRuns = backup.automationRuns
        calendars = backup.calendar.calendars
        calendarEvents = backup.calendar.events
        playgroundHistory = backup.playgroundHistory
        generatedImages = backup.generatedImages
        codeExecutionRuns = backup.codeExecutionRuns
        terminalSessions = backup.terminalSessions
        terminalCommands = backup.terminalCommands
        audioHistory = backup.audioHistory
        auditEvents = backup.auditEvents
        toolServers = backup.toolServers
        toolServerRuns = backup.toolServerRuns
        resetToolServerStatuses()
        resetToolServerDiscoveryState()

        try await settingsStore.save(settings)
        for thread in threads {
            try await storage.save(thread)
        }
        for folder in folders {
            try await folderStorage.save(folder)
        }
        for file in files {
            try await fileStorage.save(file)
        }
        for prompt in prompts {
            try await promptStorage.save(prompt)
        }
        for note in notes {
            try await noteStorage.save(note)
        }
        for tool in tools {
            try await toolStorage.save(tool)
        }
        for run in toolRuns {
            try await toolRunStorage.save(run)
        }
        for server in toolServers {
            try await toolServerStorage.save(server)
        }
        for run in toolServerRuns {
            try await toolServerRunStorage.save(run)
        }
        for function in functions {
            try await functionStorage.save(function)
        }
        for run in functionRuns {
            try await functionRunStorage.save(run)
        }
        for skill in skills {
            try await skillStorage.save(skill)
        }
        for feedback in feedbacks {
            try await feedbackStorage.save(feedback)
        }
        try await adminDirectoryStorage.saveSnapshot(backup.adminDirectory)
        for channel in channels {
            try await channelStorage.save(channel)
        }
        for automation in automations {
            try await automationStorage.save(automation)
        }
        for run in automationRuns {
            try await automationRunStorage.save(run)
        }
        try await calendarStorage.saveSnapshot(backup.calendar)
        for item in playgroundHistory {
            try await playgroundHistoryStorage.save(item)
        }
        for image in generatedImages {
            try await generatedImageStorage.save(image)
        }
        for run in codeExecutionRuns {
            try await codeExecutionStorage.save(run)
        }
        for session in terminalSessions {
            try await terminalStorage.saveSession(session)
        }
        for command in terminalCommands {
            try await terminalStorage.saveCommand(command)
        }
        for item in audioHistory {
            try await audioHistoryStorage.save(item)
        }
        for event in auditEvents {
            try await auditLogStorage.save(event)
        }
        try await knowledgeService.replaceSnapshot(backup.knowledge)

        sortWorkspaceAfterRestore()
        try await refreshKnowledgeState()
        selectedThreadID = firstVisibleThreadID()
        selectedCalendarID = calendars.first(where: \.isDefault)?.id ?? calendars.first?.id
        selectedChannelID = nil
        selectedPlaygroundHistoryID = nil
        selectedAudioHistoryItemID = nil
        selectedTerminalSessionID = nil
        clearSelectedKnowledgeDocument()
        isShowingEvaluationDashboard = false
        isShowingAnalyticsDashboard = false
        isShowingPlayground = false
        isShowingFiles = false
        isShowingCalendar = false
        isShowingImageGeneration = false
        isShowingAudio = false
        isShowingCodeInterpreter = false
        isShowingTerminalSessions = false
        models = []
        providerStatus = .unknown
        errorMessage = nil
    }

    private func workspaceBackupAuditMetadata(prefix: String, backup: WorkspaceBackup) -> [String: String] {
        [
            "\(prefix)ThreadCount": String(backup.threads.count),
            "\(prefix)FolderCount": String(backup.folders.count),
            "\(prefix)FileCount": String(backup.files.count),
            "\(prefix)PromptCount": String(backup.prompts.count),
            "\(prefix)NoteCount": String(backup.notes.count),
            "\(prefix)KnowledgeCollectionCount": String(backup.knowledge.collections.count),
            "\(prefix)KnowledgeDocumentCount": String(backup.knowledge.documents.count),
            "\(prefix)ToolCount": String(backup.tools.count),
            "\(prefix)ToolServerCount": String(backup.toolServers.count),
            "\(prefix)FunctionCount": String(backup.functions.count),
            "\(prefix)SkillCount": String(backup.skills.count),
            "\(prefix)FeedbackCount": String(backup.feedbacks.count),
            "\(prefix)AdminUserCount": String(backup.adminDirectory.users.count),
            "\(prefix)AdminGroupCount": String(backup.adminDirectory.groups.count),
            "\(prefix)ChannelCount": String(backup.channels.count),
            "\(prefix)AutomationCount": String(backup.automations.count),
            "\(prefix)CalendarCount": String(backup.calendar.calendars.count),
            "\(prefix)CalendarEventCount": String(backup.calendar.events.count),
            "\(prefix)PlaygroundRunCount": String(backup.playgroundHistory.count),
            "\(prefix)GeneratedImageCount": String(backup.generatedImages.count),
            "\(prefix)CodeExecutionRunCount": String(backup.codeExecutionRuns.count),
            "\(prefix)TerminalSessionCount": String(backup.terminalSessions.count),
            "\(prefix)TerminalCommandCount": String(backup.terminalCommands.count),
            "\(prefix)AudioHistoryCount": String(backup.audioHistory.count),
            "\(prefix)AuditEventCount": String(backup.auditEvents.count),
            "excludedSecrets": String(backup.excludesSecrets)
        ]
    }

    private func deletePersistedWorkspaceRecords() async throws {
        for thread in try await storage.loadThreads() {
            try await storage.deleteThread(id: thread.id)
        }
        for folder in try await folderStorage.loadFolders() {
            try await folderStorage.deleteFolder(id: folder.id)
        }
        for file in try await fileStorage.loadFiles() {
            try await fileStorage.deleteFile(id: file.id)
        }
        for prompt in try await promptStorage.loadPrompts() {
            try await promptStorage.deletePrompt(id: prompt.id)
        }
        for note in try await noteStorage.loadNotes() {
            try await noteStorage.deleteNote(id: note.id)
        }
        for tool in try await toolStorage.loadTools() {
            try await toolStorage.deleteTool(id: tool.id)
        }
        for run in try await toolRunStorage.loadRuns() {
            try await toolRunStorage.deleteRun(id: run.id)
        }
        for server in try await toolServerStorage.loadServers() {
            try await toolServerStorage.deleteServer(id: server.id)
        }
        for run in try await toolServerRunStorage.loadRuns() {
            try await toolServerRunStorage.deleteRun(id: run.id)
        }
        for function in try await functionStorage.loadFunctions() {
            try await functionStorage.deleteFunction(id: function.id)
        }
        for run in try await functionRunStorage.loadRuns() {
            try await functionRunStorage.deleteRun(id: run.id)
        }
        for skill in try await skillStorage.loadSkills() {
            try await skillStorage.deleteSkill(id: skill.id)
        }
        for feedback in try await feedbackStorage.loadFeedbacks() {
            try await feedbackStorage.deleteFeedback(id: feedback.id)
        }
        for channel in try await channelStorage.loadChannels() {
            try await channelStorage.deleteChannel(id: channel.id)
        }
        for automation in try await automationStorage.loadAutomations() {
            try await automationStorage.deleteAutomation(id: automation.id)
        }
        for run in try await automationRunStorage.loadRuns() {
            try await automationRunStorage.deleteRun(id: run.id)
        }
        for item in try await playgroundHistoryStorage.loadHistory() {
            try await playgroundHistoryStorage.deleteHistoryItem(id: item.id)
        }
        for image in try await generatedImageStorage.loadImages() {
            try await generatedImageStorage.deleteImage(id: image.id)
        }
        for run in try await codeExecutionStorage.loadRuns() {
            try await codeExecutionStorage.deleteRun(id: run.id)
        }
        for session in try await terminalStorage.loadSessions() {
            try await terminalStorage.deleteSession(id: session.id)
        }
        for command in try await terminalStorage.loadCommands() {
            try await terminalStorage.deleteCommand(id: command.id)
        }
        for item in try await audioHistoryStorage.loadHistory() {
            try await audioHistoryStorage.deleteHistoryItem(id: item.id)
        }
        for event in try await auditLogStorage.loadEvents() {
            try await auditLogStorage.deleteEvent(id: event.id)
        }
    }

    private func sortWorkspaceAfterRestore() {
        sortFolders()
        sortFiles()
        sortPrompts()
        sortNotes()
        sortTools()
        sortToolRuns()
        sortToolServers()
        sortToolServerRuns()
        sortFunctions()
        sortFunctionRuns()
        sortSkills()
        sortFeedbacks()
        sortAdminDirectory()
        sortChannels()
        sortAutomations()
        sortAutomationRuns()
        sortGeneratedImages()
        sortCodeExecutionRuns()
        sortTerminalSessions()
        sortTerminalCommands()
        sortAudioHistory()
        sortAuditEvents()
        sortCalendars()
        sortCalendarEvents()
        sortPlaygroundHistory()
        sortThreads()
    }

    private func sortFolders() {
        folders.sort {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    private func sortPrompts() {
        prompts.sort { $0.updatedAt > $1.updatedAt }
    }

    private func sortGeneratedImages() {
        generatedImages.sort { $0.createdAt > $1.createdAt }
    }

    private func sortToolServers() {
        toolServers.sort { $0.updatedAt > $1.updatedAt }
    }

    private func sortToolRuns() {
        toolRuns.sort { $0.startedAt > $1.startedAt }
    }

    private func sortToolServerRuns() {
        toolServerRuns.sort { $0.startedAt > $1.startedAt }
    }

    private func sortFunctionRuns() {
        functionRuns.sort { $0.startedAt > $1.startedAt }
    }

    private func refreshNativeFunctionModels() {
        let providerModels = models.filter { $0.provider != .localFunction }
        models = providerModels.filter { model in
            !activePipeFunctions().contains { function in
                model.id == function.id || model.id.hasPrefix("\(function.id).")
            }
        } + activePipeFunctions()
            .filter { !function($0, defines: "pipes") }
            .map { singlePipeModel(for: $0) }
    }

    private func modelsIncludingActivePipeFunctions(_ providerModels: [ProviderModel]) async -> [ProviderModel] {
        var pipeModels: [ProviderModel] = []
        for function in activePipeFunctions() {
            if self.function(function, defines: "pipes") {
                pipeModels.append(contentsOf: await manifoldPipeModels(for: function))
            } else {
                pipeModels.append(singlePipeModel(for: function))
            }
        }
        let pipeIDs = Set(pipeModels.map(\.id))
        return providerModels.filter { !pipeIDs.contains($0.id) } + pipeModels
    }

    private func singlePipeModel(for function: AppFunction) -> ProviderModel {
        ProviderModel(
            id: function.id,
            name: function.name,
            provider: .localFunction,
            providerID: nil,
            details: "Native pipe function"
        )
    }

    private func manifoldPipeModels(for function: AppFunction) async -> [ProviderModel] {
        let run = await functionExecutor.invoke(
            LocalFunctionInvocationRequest(
                function: function,
                methodName: "pipes",
                input: .object([:]),
                inputBody: "{}",
                timeoutSeconds: min(max(codeExecutionTimeoutSeconds, 0.1), max(settings.codeExecution.maxTimeoutSeconds, 0.1))
            )
        )
        guard run.status == .succeeded else {
            return []
        }
        return manifoldPipeDefinitions(from: run.output).map { definition in
            ProviderModel(
                id: "\(function.id).\(definition.id)",
                name: "\(function.name) \(definition.name)",
                provider: .localFunction,
                providerID: nil,
                details: "Native manifold pipe function"
            )
        }
    }

    private func manifoldPipeDefinitions(from output: String) -> [(id: String, name: String)] {
        let trimmedOutput = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedOutput.isEmpty,
              let data = trimmedOutput.data(using: .utf8),
              let value = try? JSONDecoder.openWebUIDecoder.decode(JSONValue.self, from: data),
              case .array(let items) = value else {
            return []
        }
        return items.compactMap { item in
            guard let object = item.objectValue,
                  case .string(let id)? = object["id"],
                  case .string(let name)? = object["name"] else {
                return nil
            }
            let trimmedID = id.trimmingCharacters(in: .whitespacesAndNewlines)
            let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedID.isEmpty, !trimmedName.isEmpty else {
                return nil
            }
            return (trimmedID, trimmedName)
        }
    }

    private func activePipeFunctions() -> [AppFunction] {
        guard isFeatureEnabled(.functions) else {
            return []
        }

        return functions
            .filter { $0.kind == .pipe && $0.isActive && function($0, defines: "pipe") }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private func pipeFunction(for modelID: String) -> AppFunction? {
        activePipeFunctions().first { function in
            modelID == function.id || modelID.hasPrefix("\(function.id).")
        }
    }

    private func defaultMethodName(for function: AppFunction) -> String {
        switch function.kind {
        case .filter:
            return "inlet"
        case .action:
            return "action"
        case .pipe:
            return "pipe"
        }
    }

    private func resetToolServerStatuses() {
        toolServerStatuses = Dictionary(
            uniqueKeysWithValues: toolServers.map { server in
                (server.id, ToolServerConnectionStatus.unknown)
            }
        )
    }

    private func resetToolServerDiscoveryState() {
        toolServerDiscoveryStatuses = Dictionary(
            uniqueKeysWithValues: toolServers.map { server in
                (server.id, ToolServerConnectionStatus.unknown)
            }
        )
        toolServerTools = Dictionary(
            uniqueKeysWithValues: toolServers.map { server in
                (server.id, [AppToolServerTool]())
            }
        )
    }

    private func sortAudioHistory() {
        audioHistory.sort { $0.createdAt > $1.createdAt }
    }

    private func updateAudioModelDefaults(from fetchedModels: [ProviderModel]) {
        let transcriptionModels = fetchedModels.filter {
            $0.capabilityMetadata.supportsAudioTranscription
        }
        if !transcriptionModels.isEmpty,
           !transcriptionModels.contains(where: { $0.id == audioTranscriptionModelID }) {
            audioTranscriptionModelID = transcriptionModels[0].id
        }

        let speechModels = fetchedModels.filter {
            $0.capabilityMetadata.supportsSpeechSynthesis
        }
        if !speechModels.isEmpty,
           !speechModels.contains(where: { $0.id == audioSpeechModelID }) {
            audioSpeechModelID = speechModels[0].id
        }
    }

    private func sortAuditEvents() {
        auditEvents.sort { $0.createdAt > $1.createdAt }
    }

    private func contentType(forImageFormat format: String) -> String {
        switch format.lowercased() {
        case "jpeg", "jpg":
            return "image/jpeg"
        case "webp":
            return "image/webp"
        default:
            return "image/png"
        }
    }

    private func fileExtension(forImageFormat format: String) -> String {
        switch format.lowercased() {
        case "jpeg":
            return "jpg"
        case "jpg", "webp":
            return format.lowercased()
        default:
            return "png"
        }
    }

    private static func isSquareImageSize(_ size: String) -> Bool {
        let parts = size
            .lowercased()
            .split(separator: "x")
            .compactMap { Int($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
        guard parts.count == 2 else {
            return false
        }
        return parts[0] == parts[1]
    }

    private func sortNotes() {
        notes.sort { lhs, rhs in
            if lhs.isPinned != rhs.isPinned {
                return lhs.isPinned && !rhs.isPinned
            }
            return lhs.updatedAt > rhs.updatedAt
        }
    }

    private func sortFiles() {
        files.sort { $0.updatedAt > $1.updatedAt }
    }

    private func sortTools() {
        tools.sort { $0.updatedAt > $1.updatedAt }
    }

    private func sortFunctions() {
        functions.sort { $0.updatedAt > $1.updatedAt }
    }

    private func sortSkills() {
        skills.sort { $0.updatedAt > $1.updatedAt }
    }

    private func sortFeedbacks() {
        feedbacks.sort { $0.updatedAt > $1.updatedAt }
    }

    private func sortChannels() {
        channels.sort { $0.updatedAt > $1.updatedAt }
    }

    private func sortAutomations() {
        automations.sort { $0.updatedAt > $1.updatedAt }
    }

    private func sortAutomationRuns() {
        automationRuns.sort { $0.startedAt > $1.startedAt }
    }

    private func sortCodeExecutionRuns() {
        codeExecutionRuns.sort { $0.startedAt > $1.startedAt }
    }

    private func sortTerminalSessions() {
        terminalSessions.sort { $0.updatedAt > $1.updatedAt }
    }

    private func sortTerminalCommands() {
        terminalCommands.sort { $0.startedAt > $1.startedAt }
    }

    private func sortCalendars() {
        calendars = sortedCalendars(calendars)
    }

    private func sortCalendarEvents() {
        calendarEvents.sort { $0.startAt < $1.startAt }
    }

    private func sortedCalendars(_ calendars: [AppCalendar]) -> [AppCalendar] {
        calendars.sorted { lhs, rhs in
            if lhs.isDefault != rhs.isDefault {
                return lhs.isDefault && !rhs.isDefault
            }
            if lhs.isSystem != rhs.isSystem {
                return !lhs.isSystem && rhs.isSystem
            }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    private func normalizedReminderMinutesBefore(_ value: Int?) -> Int? {
        guard let value, value >= 0 else {
            return nil
        }
        return value
    }

    private func calendarSourceEvents() -> [AppCalendarEvent] {
        let visibleCalendarIDs = Set(visibleCalendars.map(\.id))
        return calendarEvents.filter { visibleCalendarIDs.contains($0.calendarID) } + scheduledTaskCalendarEvents()
    }

    private func filteredCalendarSourceEvents() -> [AppCalendarEvent] {
        let query = parsedCalendarSearchQuery()
        return calendarSourceEvents()
            .filter { calendarEventMatchesSearch($0, query: query) }
    }

    private func scheduledTaskCalendarEvents() -> [AppCalendarEvent] {
        guard isFeatureEnabled(.automations) else {
            return []
        }

        return automations.compactMap { automation -> AppCalendarEvent? in
            guard automation.isActive else {
                return nil
            }
            let startAt = automation.nextRunAt
                ?? automationScheduleService.nextRunDate(for: automation, after: Date())
            guard let startAt else {
                return nil
            }

            return AppCalendarEvent(
                id: "automation-\(automation.id)",
                calendarID: AppCalendar.scheduledTasksCalendarID,
                userID: automation.userID,
                title: automation.name,
                description: automation.prompt,
                startAt: startAt,
                endAt: nil,
                allDay: false,
                rrule: automation.rrule,
                color: "#8b5cf6",
                meta: .object([
                    "automation_id": .string(automation.id),
                    "model_id": .string(automation.modelID)
                ]),
                createdAt: automation.createdAt,
                updatedAt: automation.updatedAt
            )
        }
    }

    private func parsedCalendarSearchQuery() -> CalendarSearchQuery {
        var query = CalendarSearchQuery()
        let words = calendarSearchText
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)

        for word in words {
            if let calendar = word.removingPrefix("calendar:") {
                let normalized = normalizedSearchOperatorValue(calendar)
                if !normalized.isEmpty {
                    query.calendarTerms.insert(normalized)
                }
            } else if let status = word.removingPrefix("status:") {
                query.status = normalizedSearchOperatorValue(status)
            } else {
                query.textTerms.append(word)
            }
        }

        return query
    }

    private func calendarEventMatchesSearch(_ event: AppCalendarEvent, query: CalendarSearchQuery) -> Bool {
        if let status = query.status {
            switch status {
            case "cancelled", "canceled":
                guard event.isCancelled else {
                    return false
                }
            case "active", "scheduled", "confirmed":
                guard !event.isCancelled else {
                    return false
                }
            default:
                return false
            }
        }

        if !query.calendarTerms.isEmpty {
            let calendarTokens = calendarSearchTokens(for: event)
            guard query.calendarTerms.allSatisfy({ term in
                calendarTokens.contains { token in
                    token.contains(term)
                }
            }) else {
                return false
            }
        }

        let text = searchableText(for: event)
        return query.textTerms.allSatisfy { term in
            text.contains(term)
        }
    }

    private func calendarSearchTokens(for event: AppCalendarEvent) -> [String] {
        var tokens = [
            normalizedSearchOperatorValue(event.calendarID)
        ]
        if let calendar = visibleCalendars.first(where: { $0.id == event.calendarID }) {
            tokens.append(normalizedSearchOperatorValue(calendar.name))
        }
        return tokens
    }

    private func normalizedCalendarAttendeeStatus(_ status: String) -> String {
        let trimmed = status.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return trimmed.isEmpty ? "pending" : trimmed
    }

    @discardableResult
    private func persistCalendarSnapshot() async -> Bool {
        sortCalendars()
        sortCalendarEvents()
        do {
            try await calendarStorage.saveSnapshot(CalendarSnapshot(calendars: calendars, events: calendarEvents))
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    private func calendarEventAuditMetadata(for event: AppCalendarEvent) -> [String: String] {
        [
            "eventID": event.id,
            "calendarID": event.calendarID,
            "calendarName": calendarName(for: event.calendarID),
            "allDay": String(event.allDay),
            "isCancelled": String(event.isCancelled),
            "hasReminder": String(event.reminderMinutesBefore != nil),
            "hasRecurrence": String(event.rrule != nil)
        ]
    }

    private func calendarAttendeeAuditMetadata(event: AppCalendarEvent, attendee: AppCalendarEventAttendee) -> [String: String] {
        [
            "eventID": event.id,
            "calendarID": event.calendarID,
            "calendarName": calendarName(for: event.calendarID),
            "attendeeID": attendee.id,
            "userID": attendee.userID,
            "status": attendee.status
        ]
    }

    private func calendarName(for calendarID: String) -> String {
        calendars.first { $0.id == calendarID }?.name ?? calendarID
    }

    private func sortChannelMembers(at index: Array<AppChannel>.Index) {
        channels[index].members.sort { lhs, rhs in
            if lhs.isPinned != rhs.isPinned {
                return lhs.isPinned && !rhs.isPinned
            }
            if lhs.role != rhs.role {
                return channelMemberRoleRank(lhs.role) < channelMemberRoleRank(rhs.role)
            }
            return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
        }
    }

    @discardableResult
    private func persistChannel(at index: Array<AppChannel>.Index) async -> Bool {
        do {
            try await channelStorage.save(channels[index])
            sortChannels()
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    private func channelMemberAuditMetadata(channel: AppChannel, member: ChannelMember) -> [String: String] {
        [
            "channelID": channel.id.uuidString,
            "channelName": channel.name,
            "memberID": member.id,
            "userID": member.userID,
            "role": member.role.rawValue,
            "status": member.status.rawValue,
            "isMuted": String(member.isMuted),
            "isPinned": String(member.isPinned)
        ]
    }

    private func channelMemberRoleRank(_ role: ChannelMemberRole) -> Int {
        switch role {
        case .owner:
            return 0
        case .admin:
            return 1
        case .member:
            return 2
        }
    }

    private func sortAdminDirectory() {
        adminUsers.sort { lhs, rhs in
            if lhs.updatedAt != rhs.updatedAt {
                return lhs.updatedAt > rhs.updatedAt
            }
            return lhs.email.localizedCaseInsensitiveCompare(rhs.email) == .orderedAscending
        }
        adminGroups.sort { lhs, rhs in
            if lhs.updatedAt != rhs.updatedAt {
                return lhs.updatedAt > rhs.updatedAt
            }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    @discardableResult
    private func persistAdminDirectory() async -> Bool {
        do {
            try await adminDirectoryStorage.saveSnapshot(
                AdminDirectorySnapshot(users: adminUsers, groups: adminGroups)
            )
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    private func sortThreads() {
        threads.sort { lhs, rhs in
            if lhs.isPinned != rhs.isPinned {
                return lhs.isPinned && !rhs.isPinned
            }
            return lhs.updatedAt > rhs.updatedAt
        }
        refreshChatTranscriptSearchResults()
    }

    private func refreshChatTranscriptSearchResults() {
        let searchableThreads = threads.filter { !$0.isArchived }
        chatTranscriptSearchResults = chatSearchService.search(chatTranscriptSearchText, in: searchableThreads)
    }

    private func codeExecutionErrorMessage(for run: AppCodeExecutionRun) -> String? {
        switch run.status {
        case .succeeded:
            return nil
        case .failed:
            if let exitCode = run.exitCode {
                return "Run exited with code \(exitCode)."
            }
            return run.stderr.nilIfEmpty ?? "Run failed."
        case .timedOut:
            return "Run timed out."
        }
    }

    private func terminalCommandErrorMessage(for command: AppTerminalCommand) -> String? {
        switch command.status {
        case .succeeded:
            return nil
        case .failed:
            if let exitCode = command.exitCode {
                return "Terminal command exited with code \(exitCode)."
            }
            return command.stderr.nilIfEmpty ?? "Terminal command failed."
        case .timedOut:
            return "Terminal command timed out."
        }
    }

    private func firstVisibleThreadID() -> UUID? {
        threads.first { !$0.isArchived }?.id
    }

    private func siblingModelIDs(for message: ChatMessage, in thread: ChatThread) -> [String] {
        guard let modelID = message.modelID else {
            return []
        }
        return thread.modelIDs.filter { $0 != modelID }
    }

    private func clonedMessage(from message: ChatMessage) -> ChatMessage {
        ChatMessage(
            role: message.role,
            content: message.content,
            modelID: message.modelID,
            createdAt: message.createdAt,
            updatedAt: message.updatedAt,
            isStreaming: false,
            error: message.error,
            rating: message.rating,
            originalContent: message.originalContent,
            attachments: message.attachments,
            citations: message.citations
        )
    }

    private func freshImportedThread(from thread: ChatThread) -> ChatThread {
        ChatThread(
            title: thread.title,
            createdAt: thread.createdAt,
            updatedAt: thread.updatedAt,
            folderID: thread.folderID,
            providerID: thread.providerID,
            modelIDs: thread.modelIDs,
            tags: thread.tags,
            isPinned: thread.isPinned,
            isArchived: thread.isArchived,
            messages: thread.messages.map(clonedMessage(from:))
        )
    }

    private func parsedSidebarSearchQuery() -> ChatSearchQuery {
        var query = ChatSearchQuery()
        let words = sidebarSearchText
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)

        var textWords: [String] = []
        for word in words {
            if word == "pinned:true" {
                query.isPinned = true
            } else if word == "pinned:false" {
                query.isPinned = false
            } else if word == "archived:true" {
                query.isArchived = true
            } else if word == "archived:false" {
                query.isArchived = false
            } else if word.starts(with: "tag:") {
                let tag = String(word.dropFirst("tag:".count))
                    .trimmingCharacters(in: CharacterSet(charactersIn: "#"))
                if !tag.isEmpty {
                    query.tags.insert(tag)
                }
            } else if word.starts(with: "folder:") {
                let folderSlug = normalizedSearchOperatorValue(String(word.dropFirst("folder:".count)))
                if !folderSlug.isEmpty {
                    query.folderSlugs.insert(folderSlug)
                }
            } else if word.starts(with: "pinned:") || word.starts(with: "archived:") {
                continue
            } else {
                textWords.append(word)
            }
        }

        query.text = textWords.joined(separator: " ")
        return query
    }

    private func parsedSkillSearchQuery() -> SkillSearchQuery {
        var query = SkillSearchQuery()
        let words = skillSearchText
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)

        for word in words {
            if let tag = word.removingPrefix("tag:") {
                let normalizedTag = tag.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
                if !normalizedTag.isEmpty {
                    query.tags.insert(normalizedTag)
                }
            } else if let active = word.removingPrefix("active:") {
                switch active {
                case "true", "yes", "enabled":
                    query.isActive = true
                case "false", "no", "disabled":
                    query.isActive = false
                default:
                    continue
                }
            } else if word.starts(with: "tag:") || word.starts(with: "active:") {
                continue
            } else {
                query.textTerms.append(word)
            }
        }

        return query
    }

    private func skillMatchesSearch(_ skill: AppSkill, query: SkillSearchQuery) -> Bool {
        if let isActive = query.isActive, skill.isActive != isActive {
            return false
        }

        if !query.tags.isEmpty {
            let skillTags = Set(skill.tags.map { normalizedSearchOperatorValue($0) })
            guard query.tags.allSatisfy({ skillTags.contains(normalizedSearchOperatorValue($0)) }) else {
                return false
            }
        }

        let text = searchableText(for: skill)
        return query.textTerms.allSatisfy { text.contains($0) }
    }

    private func threadMatchesSearchOperators(_ thread: ChatThread, query: ChatSearchQuery) -> Bool {
        if !query.tags.isEmpty,
           !query.tags.allSatisfy({ thread.tags.contains($0) }) {
            return false
        }

        if !query.folderSlugs.isEmpty {
            guard let folderID = thread.folderID,
                  let folder = folders.first(where: { $0.id == folderID }),
                  query.folderSlugs.contains(normalizedSearchOperatorValue(folder.name)) else {
                return false
            }
        }

        return true
    }

    private func normalizedSearchOperatorValue(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: " ", with: "_")
            .lowercased()
    }

    private func normalizedTag(_ rawTag: String) -> String? {
        let trimmed = rawTag.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "#"))
            .lowercased()
        let collapsed = trimmed
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: "-")
        return collapsed.isEmpty ? nil : collapsed
    }

    private func searchableText(for thread: ChatThread) -> String {
        [
            thread.title,
            thread.modelIDs.joined(separator: " "),
            thread.tags.joined(separator: " "),
            thread.messages.map { message in
                ([message.content] + message.attachments.flatMap { attachment in
                    [attachment.fileName, attachment.textContent ?? ""]
                } + message.citations.flatMap { citation in
                    [citation.collectionName, citation.sourceName, citation.text]
                })
                .joined(separator: " ")
            }
            .joined(separator: " ")
        ]
        .joined(separator: " ")
        .lowercased()
    }

    private func searchableText(for note: AppNote) -> String {
        [note.title, note.content]
            .joined(separator: " ")
            .lowercased()
    }

    private func searchableText(for skill: AppSkill) -> String {
        [
            skill.name,
            skill.description ?? "",
            skill.tags.joined(separator: " "),
            skill.content,
            skill.isActive ? "active enabled" : "inactive disabled"
        ]
        .joined(separator: " ")
        .lowercased()
    }

    private func searchableText(for channel: AppChannel) -> String {
        [
            channel.name,
            channel.description ?? "",
            channel.messages.map(\.content).joined(separator: " ")
        ]
        .joined(separator: " ")
        .lowercased()
    }

    private func searchableText(for automation: AppAutomation) -> String {
        [
            automation.name,
            automation.prompt,
            automation.modelID,
            automation.rrule,
            automation.isActive ? "active enabled" : "paused disabled"
        ]
        .joined(separator: " ")
        .lowercased()
    }

    private func searchableText(for event: AppCalendarEvent) -> String {
        let calendarName = visibleCalendars.first { $0.id == event.calendarID }?.name ?? ""
        return [
            event.title,
            event.description ?? "",
            event.location ?? "",
            event.rrule ?? "",
            calendarName,
            event.isCancelled ? "cancelled canceled" : "active scheduled confirmed"
        ]
        .joined(separator: " ")
        .lowercased()
    }

    private func providerContent(for message: ChatMessage) -> String {
        let attachmentContext = message.attachments.compactMap { attachment -> String? in
            guard let textContent = attachment.textContent, !textContent.isEmpty else {
                return nil
            }
            return """
            Attachment: \(attachment.fileName)
            \(textContent)
            """
        }

        let knowledgeContext = message.citations.map { citation in
            if citation.collectionSlug == "web" {
                return """
                Web search context
                Source: \(citation.sourceName)
                \(citation.text)
                """
            }
            return """
            Knowledge context from #\(citation.collectionSlug)
            Source: \(citation.sourceName)
            \(citation.text)
            """
        }

        guard !attachmentContext.isEmpty || !knowledgeContext.isEmpty else {
            return message.content
        }

        let contextSections = (attachmentContext + knowledgeContext).joined(separator: "\n\n")
        return """
        \(message.content)

        Attached context:
        \(contextSections)
        """
    }

    private func noteAttachmentFileName(for title: String) -> String {
        let cleanedTitle = title
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .map { character in
                character == "/" || character == ":" ? "-" : character
            }
        let fileTitle = String(cleanedTitle).isEmpty ? "Note" : String(cleanedTitle)
        return fileTitle.hasSuffix(".md") ? fileTitle : "\(fileTitle).md"
    }

    private func knowledgeCitations(
        for prompt: String,
        provider: any ChatProvider,
        embeddingModel: String
    ) async throws -> [ChatCitation] {
        let mentions = collectionMentions(in: prompt)
        guard !mentions.isEmpty else {
            return []
        }
        guard isFeatureEnabled(.knowledge) else {
            let message = knowledgeDisabledMessage
            errorMessage = message
            throw NSError(
                domain: "OpenWebUINative.Knowledge",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: message]
            )
        }
        guard canCreateEmbeddings else {
            throw ProviderError.unsupportedEmbeddings(activeProvider.name)
        }

        var citations: [ChatCitation] = []
        for mention in mentions {
            guard let collection = try await knowledgeService.collection(matchingMention: mention) else {
                continue
            }
            guard currentUserCanAccessKnowledgeCollection(collection) else {
                continue
            }
            let results = try await knowledgeService.retrieve(
                collectionID: collection.id,
                query: prompt,
                embeddingModel: embeddingModel,
                provider: provider,
                limit: 3
            )
            citations.append(contentsOf: results.map { result in
                ChatCitation(
                    collectionName: result.collection.name,
                    collectionSlug: result.collection.slug,
                    collectionID: result.collection.id,
                    documentID: result.document?.id ?? result.chunk.documentID,
                    chunkID: result.chunk.id,
                    sourceName: result.document?.fileName ?? result.chunk.sourceName,
                    text: result.chunk.text,
                    score: result.score
                )
            })
        }
        return citations
    }

    private func webSearchCitations(for prompt: String) async throws -> [ChatCitation] {
        guard isWebSearchEnabledForNextPrompt else {
            return []
        }
        let webSearchSettings = settings.webSearch
        guard isFeatureEnabled(.webSearch) else {
            recentWebSearchResults = []
            let telemetry = WebSearchTelemetry(
                query: prompt,
                engine: webSearchSettings.engine,
                resultCount: 0,
                status: .failed,
                wasPageContentLoadingEnabled: webSearchSettings.isPageContentLoadingEnabled,
                pageContentResultCount: 0,
                errorMessage: "\(AppFeatureToggle.webSearch.label) is disabled.",
                completedAt: Date(),
                contactedHosts: [],
                usedAPIKey: false
            )
            recentWebSearchTelemetry = telemetry
            await recordWebSearchAuditEvent(for: telemetry, outcome: .blocked)
            throw NSError(domain: "OpenWebUINative.WebSearch", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "\(AppFeatureToggle.webSearch.label) is disabled."
            ])
        }
        recentWebSearchResults = []
        recentWebSearchTelemetry = nil
        guard currentUserCanUseWebSearch else {
            let telemetry = WebSearchTelemetry(
                query: prompt,
                engine: webSearchSettings.engine,
                resultCount: 0,
                status: .failed,
                wasPageContentLoadingEnabled: webSearchSettings.isPageContentLoadingEnabled,
                pageContentResultCount: 0,
                errorMessage: "You do not have permission to use web search.",
                completedAt: Date(),
                contactedHosts: [],
                usedAPIKey: false
            )
            recentWebSearchTelemetry = telemetry
            await recordWebSearchAuditEvent(for: telemetry, outcome: .blocked)
            throw NSError(domain: "OpenWebUINative.WebSearch", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "You do not have permission to use web search."
            ])
        }
        let results: [WebSearchResult]
        do {
            results = try await webSearchService.search(query: prompt, settings: webSearchSettings)
        } catch {
            let missingAPIKey = (error as? WebSearchServiceError)?.isMissingAPIKey ?? false
            let telemetry = WebSearchTelemetry(
                query: prompt,
                engine: webSearchSettings.engine,
                resultCount: 0,
                status: .failed,
                wasPageContentLoadingEnabled: webSearchSettings.isPageContentLoadingEnabled,
                pageContentResultCount: 0,
                errorMessage: error.localizedDescription,
                completedAt: Date(),
                contactedHosts: missingAPIKey ? [] : webSearchNetworkHosts(for: webSearchSettings),
                usedAPIKey: missingAPIKey ? false : webSearchUsesAPIKey(webSearchSettings)
            )
            recentWebSearchTelemetry = telemetry
            await recordWebSearchAuditEvent(for: telemetry, outcome: .failed)
            throw error
        }
        recentWebSearchResults = results
        let telemetry = WebSearchTelemetry(
            query: prompt,
            engine: webSearchSettings.engine,
            resultCount: results.count,
            status: .succeeded,
            wasPageContentLoadingEnabled: webSearchSettings.isPageContentLoadingEnabled,
            pageContentResultCount: results.filter { ($0.pageContent?.nilIfEmpty) != nil }.count,
            errorMessage: nil,
            completedAt: Date(),
            contactedHosts: webSearchNetworkHosts(for: webSearchSettings, results: results),
            usedAPIKey: webSearchUsesAPIKey(webSearchSettings)
        )
        recentWebSearchTelemetry = telemetry
        await recordWebSearchAuditEvent(for: telemetry, outcome: .succeeded)
        return results.map { result in
            ChatCitation(
                collectionName: "Web Search",
                collectionSlug: "web",
                sourceName: result.title,
                text: """
                URL: \(result.url.absoluteString)
                \(result.pageContent?.nilIfEmpty ?? result.snippet)
                """,
                score: 1
            )
        }
    }

    private func recordWebSearchAuditEvent(for telemetry: WebSearchTelemetry, outcome: AppAuditOutcome) async {
        await recordAuditEvent(
            action: .webSearchRun,
            outcome: outcome,
            summary: webSearchAuditSummary(for: outcome),
            metadata: webSearchAuditMetadata(for: telemetry)
        )
    }

    private func webSearchAuditSummary(for outcome: AppAuditOutcome) -> String {
        switch outcome {
        case .succeeded:
            return "Web search completed"
        case .failed:
            return "Web search failed"
        case .blocked:
            return "Web search blocked"
        }
    }

    private func webSearchAuditMetadata(for telemetry: WebSearchTelemetry) -> [String: String] {
        [
            "engine": telemetry.engine.rawValue,
            "status": telemetry.status.rawValue,
            "resultCount": String(telemetry.resultCount),
            "pageContentResultCount": String(telemetry.pageContentResultCount),
            "pageContentLoadingEnabled": String(telemetry.wasPageContentLoadingEnabled),
            "contactedHosts": telemetry.contactedHosts.isEmpty ? "none" : telemetry.contactedHosts.joined(separator: ", "),
            "usedAPIKey": String(telemetry.usedAPIKey)
        ]
    }

    private func webSearchNetworkHosts(for settings: WebSearchSettings, results: [WebSearchResult] = []) -> [String] {
        var hosts: [String] = []
        if let searchHost = webSearchPrimaryHost(for: settings) {
            hosts.append(searchHost)
        }
        if settings.isPageContentLoadingEnabled {
            hosts.append(contentsOf: results.compactMap { $0.url.host })
        }
        return normalizedHosts(hosts)
    }

    private func webSearchPrimaryHost(for settings: WebSearchSettings) -> String? {
        switch settings.engine {
        case .duckDuckGoHTML:
            return "html.duckduckgo.com"
        case .searxng:
            return URL(string: settings.searxngBaseURL)?.host
        case .brave:
            return "api.search.brave.com"
        case .tavily:
            return "api.tavily.com"
        }
    }

    private func webSearchUsesAPIKey(_ settings: WebSearchSettings) -> Bool {
        switch settings.engine {
        case .brave:
            return settings.braveAPIKeySecretID?.nilIfEmpty != nil
        case .tavily:
            return settings.tavilyAPIKeySecretID?.nilIfEmpty != nil
        case .duckDuckGoHTML, .searxng:
            return false
        }
    }

    private func normalizedHosts(_ hosts: [String]) -> [String] {
        var seen: Set<String> = []
        var result: [String] = []
        for host in hosts {
            let normalized = host.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !normalized.isEmpty, !seen.contains(normalized) else {
                continue
            }
            seen.insert(normalized)
            result.append(normalized)
        }
        return result
    }

    private func collectionMentions(in prompt: String) -> [String] {
        let pattern = #"#([A-Za-z0-9][A-Za-z0-9_-]*)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return []
        }
        let range = NSRange(prompt.startIndex..<prompt.endIndex, in: prompt)
        let matches = regex.matches(in: prompt, range: range)
        return Array(Set(matches.compactMap { match in
            guard let range = Range(match.range(at: 1), in: prompt) else {
                return nil
            }
            return String(prompt[range])
        }))
    }

    private static func isValidProviderBaseURL(_ value: String) -> Bool {
        guard let components = URLComponents(string: value),
              let scheme = components.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              components.host?.isEmpty == false else {
            return false
        }
        return true
    }

    private func title(for prompt: String) -> String {
        let singleLine = prompt.replacingOccurrences(of: "\n", with: " ")
        if singleLine.count <= 42 {
            return singleLine
        }
        return String(singleLine.prefix(42)) + "..."
    }
}

private struct FunctionFilterExecutionError: LocalizedError {
    var run: AppFunctionRun

    var errorDescription: String? {
        run.errorMessage ?? "\(run.functionName) function \(run.methodName) failed."
    }
}

private struct FunctionFilterOutputError: LocalizedError {
    var message: String

    var errorDescription: String? {
        message
    }
}

private struct AppStoreMessageError: LocalizedError {
    var message: String

    var errorDescription: String? {
        message
    }
}

private struct FunctionValvesValidationError: LocalizedError {
    var errorDescription: String? {
        "Function valves must be a JSON object."
    }
}

private struct ToolValvesValidationError: LocalizedError {
    var errorDescription: String? {
        "Tool valves must be a JSON object."
    }
}

private struct ToolValvesSchemaValidationError: LocalizedError {
    var message: String

    var errorDescription: String? {
        message
    }
}

private struct FunctionValvesSchemaValidationError: LocalizedError {
    var message: String

    var errorDescription: String? {
        message
    }
}

private struct ImportedTextDocument {
    var fileName: String
    var contentType: String
    var text: String
    var originalData: Data
    var byteCount: Int
    var sourceKind: KnowledgeDocumentSourceKind
}

private extension String {
    func removingPrefix(_ prefix: String) -> String? {
        hasPrefix(prefix) ? String(dropFirst(prefix.count)) : nil
    }

    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}

private func normalizedExecutableName(_ name: String) -> String {
    let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
        return ""
    }
    return URL(fileURLWithPath: trimmed).lastPathComponent
}
