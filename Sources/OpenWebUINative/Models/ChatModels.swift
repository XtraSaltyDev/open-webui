import Foundation

enum ProviderKind: String, Codable, Equatable, Sendable {
    case ollama
    case openAICompatible
    case localFunction
}

struct ProviderConfiguration: Identifiable, Codable, Equatable, Sendable {
    var id: UUID
    var name: String
    var kind: ProviderKind
    var baseURL: String
    var apiKeySecretID: String?
    var isEnabled: Bool

    init(
        id: UUID = UUID(),
        name: String,
        kind: ProviderKind,
        baseURL: String,
        apiKeySecretID: String? = nil,
        isEnabled: Bool = true
    ) {
        self.id = id
        self.name = name
        self.kind = kind
        self.baseURL = baseURL
        self.apiKeySecretID = apiKeySecretID
        self.isEnabled = isEnabled
    }

    static let defaultOllamaID = UUID(uuidString: "00000000-0000-0000-0000-000000000114")!

    static func defaultOllama(baseURL: String = "http://localhost:11434") -> ProviderConfiguration {
        ProviderConfiguration(
            id: defaultOllamaID,
            name: "Ollama",
            kind: .ollama,
            baseURL: baseURL
        )
    }
}

struct ProviderCapabilities: Equatable, Sendable {
    var supportsChat: Bool
    var supportsCompletions: Bool
    var supportsEmbeddings: Bool
    var supportsModelManagement: Bool
    var supportsImageGeneration: Bool
    var supportsImageEditing: Bool
    var supportsImageVariation: Bool
    var supportsAudioTranscription: Bool
    var supportsSpeechSynthesis: Bool

    static let ollama = ProviderCapabilities(
        supportsChat: true,
        supportsCompletions: true,
        supportsEmbeddings: false,
        supportsModelManagement: true,
        supportsImageGeneration: false,
        supportsImageEditing: false,
        supportsImageVariation: false,
        supportsAudioTranscription: false,
        supportsSpeechSynthesis: false
    )

    static let openAICompatible = ProviderCapabilities(
        supportsChat: true,
        supportsCompletions: true,
        supportsEmbeddings: true,
        supportsModelManagement: false,
        supportsImageGeneration: true,
        supportsImageEditing: true,
        supportsImageVariation: true,
        supportsAudioTranscription: true,
        supportsSpeechSynthesis: true
    )

    static let localFunction = ProviderCapabilities(
        supportsChat: true,
        supportsCompletions: false,
        supportsEmbeddings: false,
        supportsModelManagement: false,
        supportsImageGeneration: false,
        supportsImageEditing: false,
        supportsImageVariation: false,
        supportsAudioTranscription: false,
        supportsSpeechSynthesis: false
    )
}

extension ProviderConfiguration {
    var capabilities: ProviderCapabilities {
        switch kind {
        case .ollama:
            return .ollama
        case .openAICompatible:
            return .openAICompatible
        case .localFunction:
            return .localFunction
        }
    }
}

struct ProviderModel: Identifiable, Codable, Equatable, Sendable {
    var id: String
    var name: String
    var provider: ProviderKind
    var providerID: UUID?
    var details: String?
}

struct ChatFolder: Identifiable, Codable, Equatable, Sendable {
    var id: UUID
    var name: String
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

struct SavedPrompt: Identifiable, Codable, Equatable, Sendable {
    var id: UUID
    var title: String
    var content: String
    var command: String?
    var tags: [String]
    var allowedUserIDs: [String]
    var allowedGroupIDs: [String]
    var versions: [SavedPromptVersion]
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        title: String,
        content: String,
        command: String? = nil,
        tags: [String] = [],
        allowedUserIDs: [String] = [],
        allowedGroupIDs: [String] = [],
        versions: [SavedPromptVersion] = [],
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.content = content
        self.command = SavedPrompt.normalizedCommand(command)
        self.tags = SavedPrompt.normalizedTags(tags)
        self.allowedUserIDs = SavedPrompt.normalizedAccessIDs(allowedUserIDs)
        self.allowedGroupIDs = SavedPrompt.normalizedAccessIDs(allowedGroupIDs)
        self.versions = versions
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case content
        case command
        case tags
        case allowedUserIDs
        case allowedGroupIDs
        case versions
        case createdAt
        case updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let legacyContainer = try? decoder.container(keyedBy: LegacyCodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        content = try container.decode(String.self, forKey: .content)
        command = SavedPrompt.normalizedCommand(try container.decodeIfPresent(String.self, forKey: .command))
        tags = SavedPrompt.normalizedTags(try container.decodeIfPresent([String].self, forKey: .tags) ?? [])
        allowedUserIDs = SavedPrompt.normalizedAccessIDs(
            try container.decodeIfPresent([String].self, forKey: .allowedUserIDs) ?? []
        )
        allowedGroupIDs = SavedPrompt.normalizedAccessIDs(
            try container.decodeIfPresent([String].self, forKey: .allowedGroupIDs) ?? []
        )
        versions = try container.decodeIfPresent([SavedPromptVersion].self, forKey: .versions)
            ?? legacyContainer?.decodeIfPresent([SavedPromptVersion].self, forKey: .versionHistory)
            ?? []
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
    }

    private enum LegacyCodingKeys: String, CodingKey {
        case versionHistory = "version_history"
    }

    static func normalizedCommand(_ rawCommand: String?) -> String? {
        guard let rawCommand else {
            return nil
        }
        let trimmed = rawCommand.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }
        let withoutSlash = trimmed.hasPrefix("/") ? String(trimmed.dropFirst()) : trimmed
        let cleaned = withoutSlash
            .lowercased()
            .split { !$0.isLetter && !$0.isNumber && $0 != "-" && $0 != "_" }
            .joined(separator: "-")
        return cleaned.isEmpty ? nil : "/\(cleaned)"
    }

    static func normalizedTags(_ rawTags: [String]) -> [String] {
        var tags: [String] = []
        var seenKeys: Set<String> = []

        for rawTag in rawTags {
            let trimmed = rawTag.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                continue
            }

            let key = trimmed.lowercased()
            guard seenKeys.insert(key).inserted else {
                continue
            }

            tags.append(trimmed)
        }

        return tags
    }

    static func normalizedAccessIDs(_ ids: [String]) -> [String] {
        var normalized: [String] = []
        var seen: Set<String> = []

        for id in ids {
            let trimmed = id.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, seen.insert(trimmed).inserted else {
                continue
            }

            normalized.append(trimmed)
        }

        return normalized
    }
}

struct SavedPromptVersion: Codable, Equatable, Sendable {
    var title: String
    var content: String
    var command: String?
    var tags: [String]
    var allowedUserIDs: [String]
    var allowedGroupIDs: [String]
    var createdAt: Date
    var updatedAt: Date

    init(
        title: String,
        content: String,
        command: String? = nil,
        tags: [String] = [],
        allowedUserIDs: [String] = [],
        allowedGroupIDs: [String] = [],
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.title = title
        self.content = content
        self.command = SavedPrompt.normalizedCommand(command)
        self.tags = SavedPrompt.normalizedTags(tags)
        self.allowedUserIDs = SavedPrompt.normalizedAccessIDs(allowedUserIDs)
        self.allowedGroupIDs = SavedPrompt.normalizedAccessIDs(allowedGroupIDs)
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    init(prompt: SavedPrompt) {
        self.init(
            title: prompt.title,
            content: prompt.content,
            command: prompt.command,
            tags: prompt.tags,
            allowedUserIDs: prompt.allowedUserIDs,
            allowedGroupIDs: prompt.allowedGroupIDs,
            createdAt: prompt.createdAt,
            updatedAt: prompt.updatedAt
        )
    }

    enum CodingKeys: String, CodingKey {
        case title
        case content
        case command
        case tags
        case allowedUserIDs
        case allowedGroupIDs
        case createdAt
        case updatedAt
    }

    private enum SnapshotEnvelopeCodingKeys: String, CodingKey {
        case snapshot
    }

    private enum LegacyCodingKeys: String, CodingKey {
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let envelope = try? decoder.container(keyedBy: SnapshotEnvelopeCodingKeys.self)
        let sourceContainer: KeyedDecodingContainer<CodingKeys>
        if let envelope, envelope.contains(.snapshot) {
            sourceContainer = try envelope.nestedContainer(keyedBy: CodingKeys.self, forKey: .snapshot)
        } else {
            sourceContainer = container
        }
        let legacyContainer = try? decoder.container(keyedBy: LegacyCodingKeys.self)

        title = try sourceContainer.decode(String.self, forKey: .title)
        content = try sourceContainer.decode(String.self, forKey: .content)
        command = SavedPrompt.normalizedCommand(try sourceContainer.decodeIfPresent(String.self, forKey: .command))
        tags = SavedPrompt.normalizedTags(try sourceContainer.decodeIfPresent([String].self, forKey: .tags) ?? [])
        allowedUserIDs = SavedPrompt.normalizedAccessIDs(
            try sourceContainer.decodeIfPresent([String].self, forKey: .allowedUserIDs) ?? []
        )
        allowedGroupIDs = SavedPrompt.normalizedAccessIDs(
            try sourceContainer.decodeIfPresent([String].self, forKey: .allowedGroupIDs) ?? []
        )
        createdAt = Self.decodeDate(
            from: sourceContainer,
            fallback: container,
            legacy: legacyContainer,
            key: .createdAt,
            legacyKey: .createdAt
        )
        updatedAt = Self.decodeDate(
            from: sourceContainer,
            fallback: container,
            legacy: legacyContainer,
            key: .updatedAt,
            legacyKey: .updatedAt
        )
    }

    private static func decodeDate(
        from source: KeyedDecodingContainer<CodingKeys>,
        fallback: KeyedDecodingContainer<CodingKeys>,
        legacy: KeyedDecodingContainer<LegacyCodingKeys>?,
        key: CodingKeys,
        legacyKey: LegacyCodingKeys
    ) -> Date {
        if let date = try? source.decode(Date.self, forKey: key) {
            return date
        }
        if let unix = try? source.decode(Int.self, forKey: key) {
            return Date(timeIntervalSince1970: TimeInterval(unix))
        }
        if let date = try? fallback.decode(Date.self, forKey: key) {
            return date
        }
        if let unix = try? fallback.decode(Int.self, forKey: key) {
            return Date(timeIntervalSince1970: TimeInterval(unix))
        }
        if let date = try? legacy?.decode(Date.self, forKey: legacyKey) {
            return date
        }
        if let unix = try? legacy?.decode(Int.self, forKey: legacyKey) {
            return Date(timeIntervalSince1970: TimeInterval(unix))
        }
        return Date()
    }
}

enum PlaygroundMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case chat
    case completions
    case notes
    case images

    var id: String { rawValue }
}

struct PlaygroundImageOutput: Codable, Equatable, Sendable {
    var imageData: Data
    var revisedPrompt: String?
    var outputFormat: String?
    var size: String?
    var quality: String?
}

struct PlaygroundHistoryItem: Identifiable, Codable, Equatable, Sendable {
    var id: UUID
    var title: String
    var mode: PlaygroundMode
    var modelID: String
    var comparisonModelID: String?
    var isComparisonEnabled: Bool
    var systemPrompt: String?
    var prompt: String
    var output: String
    var comparisonOutput: String?
    var options: ProviderChatOptions
    var imageOutputs: [PlaygroundImageOutput]
    var imageSize: String?
    var imageQuality: String?
    var imageCount: Int?
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        title: String,
        mode: PlaygroundMode = .chat,
        modelID: String,
        comparisonModelID: String? = nil,
        isComparisonEnabled: Bool = false,
        systemPrompt: String? = nil,
        prompt: String,
        output: String,
        comparisonOutput: String? = nil,
        options: ProviderChatOptions,
        imageOutputs: [PlaygroundImageOutput] = [],
        imageSize: String? = nil,
        imageQuality: String? = nil,
        imageCount: Int? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.mode = mode
        self.modelID = modelID
        self.comparisonModelID = comparisonModelID
        self.isComparisonEnabled = isComparisonEnabled
        self.systemPrompt = systemPrompt
        self.prompt = prompt
        self.output = output
        self.comparisonOutput = comparisonOutput
        self.options = options
        self.imageOutputs = imageOutputs
        self.imageSize = imageSize
        self.imageQuality = imageQuality
        self.imageCount = imageCount
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case mode
        case modelID
        case comparisonModelID
        case isComparisonEnabled
        case systemPrompt
        case prompt
        case output
        case comparisonOutput
        case options
        case imageOutputs
        case imageSize
        case imageQuality
        case imageCount
        case createdAt
        case updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        mode = try container.decodeIfPresent(PlaygroundMode.self, forKey: .mode) ?? .chat
        modelID = try container.decode(String.self, forKey: .modelID)
        comparisonModelID = try container.decodeIfPresent(String.self, forKey: .comparisonModelID)
        isComparisonEnabled = try container.decode(Bool.self, forKey: .isComparisonEnabled)
        systemPrompt = try container.decodeIfPresent(String.self, forKey: .systemPrompt)
        prompt = try container.decode(String.self, forKey: .prompt)
        output = try container.decode(String.self, forKey: .output)
        comparisonOutput = try container.decodeIfPresent(String.self, forKey: .comparisonOutput)
        options = try container.decode(ProviderChatOptions.self, forKey: .options)
        imageOutputs = try container.decodeIfPresent([PlaygroundImageOutput].self, forKey: .imageOutputs) ?? []
        imageSize = try container.decodeIfPresent(String.self, forKey: .imageSize)
        imageQuality = try container.decodeIfPresent(String.self, forKey: .imageQuality)
        imageCount = try container.decodeIfPresent(Int.self, forKey: .imageCount)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
    }
}

struct AppNote: Identifiable, Codable, Equatable, Sendable {
    static let deepLinkScheme = "openwebui-native"
    static let deepLinkHost = "notes"

    var id: UUID
    var title: String
    var content: String
    var createdAt: Date
    var updatedAt: Date
    var isPinned: Bool

    init(
        id: UUID = UUID(),
        title: String,
        content: String,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        isPinned: Bool = false
    ) {
        self.id = id
        self.title = title
        self.content = content
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.isPinned = isPinned
    }

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case content
        case createdAt
        case updatedAt
        case isPinned
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        content = try container.decode(String.self, forKey: .content)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        isPinned = try container.decodeIfPresent(Bool.self, forKey: .isPinned) ?? false
    }

    var deepLinkURL: URL {
        URL(string: "\(Self.deepLinkScheme)://\(Self.deepLinkHost)/\(id.uuidString)")!
    }

    static func noteID(fromDeepLink url: URL) -> UUID? {
        guard url.scheme == deepLinkScheme,
              url.host == deepLinkHost else {
            return nil
        }
        let idString = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !idString.isEmpty else {
            return nil
        }
        return UUID(uuidString: idString)
    }
}

struct AppAutomation: Identifiable, Codable, Equatable, Sendable {
    var id: String
    var userID: String
    var name: String
    var prompt: String
    var modelID: String
    var rrule: String
    var meta: JSONValue?
    var isActive: Bool
    var lastRunAt: Date?
    var nextRunAt: Date?
    var createdAt: Date
    var updatedAt: Date

    init(
        id: String = UUID().uuidString,
        userID: String = "local-user",
        name: String,
        prompt: String,
        modelID: String,
        rrule: String,
        meta: JSONValue? = nil,
        isActive: Bool = true,
        lastRunAt: Date? = nil,
        nextRunAt: Date? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.userID = userID
        self.name = name
        self.prompt = prompt
        self.modelID = modelID
        self.rrule = rrule
        self.meta = meta
        self.isActive = isActive
        self.lastRunAt = lastRunAt
        self.nextRunAt = nextRunAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

enum AppAutomationRunStatus: String, Codable, Equatable, Sendable {
    case succeeded
    case failed
}

struct AppAutomationRun: Identifiable, Codable, Equatable, Sendable {
    var id: String
    var automationID: String
    var automationName: String
    var modelID: String
    var prompt: String
    var output: String
    var status: AppAutomationRunStatus
    var errorMessage: String?
    var startedAt: Date
    var completedAt: Date?

    init(
        id: String = UUID().uuidString,
        automationID: String,
        automationName: String,
        modelID: String,
        prompt: String,
        output: String = "",
        status: AppAutomationRunStatus,
        errorMessage: String? = nil,
        startedAt: Date = Date(),
        completedAt: Date? = nil
    ) {
        self.id = id
        self.automationID = automationID
        self.automationName = automationName
        self.modelID = modelID
        self.prompt = prompt
        self.output = output
        self.status = status
        self.errorMessage = errorMessage
        self.startedAt = startedAt
        self.completedAt = completedAt
    }
}

struct AppTool: Identifiable, Codable, Equatable, Sendable {
    var id: String
    var name: String
    var content: String
    var description: String?
    var specs: [JSONValue]
    var manifest: JSONValue?
    var valves: JSONValue?
    var createdAt: Date
    var updatedAt: Date

    init(
        id: String = UUID().uuidString,
        name: String,
        content: String,
        description: String? = nil,
        specs: [JSONValue] = [],
        manifest: JSONValue? = nil,
        valves: JSONValue? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.content = content
        self.description = description
        self.specs = specs
        self.manifest = manifest
        self.valves = valves
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

enum AppFunctionKind: String, Codable, CaseIterable, Equatable, Sendable {
    case filter
    case action
    case pipe
}

struct AppFunction: Identifiable, Codable, Equatable, Sendable {
    var id: String
    var name: String
    var kind: AppFunctionKind
    var content: String
    var description: String?
    var manifest: JSONValue?
    var valves: JSONValue?
    var isActive: Bool
    var isGlobal: Bool
    var createdAt: Date
    var updatedAt: Date

    init(
        id: String = UUID().uuidString,
        name: String,
        kind: AppFunctionKind,
        content: String,
        description: String? = nil,
        manifest: JSONValue? = nil,
        valves: JSONValue? = nil,
        isActive: Bool = false,
        isGlobal: Bool = false,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.kind = kind
        self.content = content
        self.description = description
        self.manifest = manifest
        self.valves = valves
        self.isActive = isActive
        self.isGlobal = isGlobal
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

struct AppSkill: Identifiable, Codable, Equatable, Sendable {
    var id: String
    var name: String
    var content: String
    var description: String?
    var tags: [String]
    var allowedUserIDs: [String]
    var allowedGroupIDs: [String]
    var isActive: Bool
    var createdAt: Date
    var updatedAt: Date

    init(
        id: String = UUID().uuidString,
        name: String,
        content: String,
        description: String? = nil,
        tags: [String] = [],
        allowedUserIDs: [String] = [],
        allowedGroupIDs: [String] = [],
        isActive: Bool = true,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.content = content
        self.description = description
        self.tags = tags
        self.allowedUserIDs = AppSkill.normalizedAccessIDs(allowedUserIDs)
        self.allowedGroupIDs = AppSkill.normalizedAccessIDs(allowedGroupIDs)
        self.isActive = isActive
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case content
        case description
        case tags
        case allowedUserIDs
        case allowedGroupIDs
        case isActive
        case createdAt
        case updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try container.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString,
            name: try container.decode(String.self, forKey: .name),
            content: try container.decode(String.self, forKey: .content),
            description: try container.decodeIfPresent(String.self, forKey: .description),
            tags: try container.decodeIfPresent([String].self, forKey: .tags) ?? [],
            allowedUserIDs: try container.decodeIfPresent([String].self, forKey: .allowedUserIDs) ?? [],
            allowedGroupIDs: try container.decodeIfPresent([String].self, forKey: .allowedGroupIDs) ?? [],
            isActive: try container.decodeIfPresent(Bool.self, forKey: .isActive) ?? true,
            createdAt: try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date(),
            updatedAt: try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? Date()
        )
    }
}

struct AppFeedback: Identifiable, Codable, Equatable, Sendable {
    var id: String
    var userID: String
    var version: Int
    var type: String
    var data: AppFeedbackData
    var meta: AppFeedbackMeta
    var snapshot: AppFeedbackSnapshot?
    var moderationStatus: AppFeedbackModerationStatus
    var createdAt: Date
    var updatedAt: Date

    init(
        id: String = UUID().uuidString,
        userID: String = "local-user",
        version: Int = 0,
        type: String = "rating",
        data: AppFeedbackData,
        meta: AppFeedbackMeta,
        snapshot: AppFeedbackSnapshot? = nil,
        moderationStatus: AppFeedbackModerationStatus = .pending,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.userID = userID
        self.version = version
        self.type = type
        self.data = data
        self.meta = meta
        self.snapshot = snapshot
        self.moderationStatus = moderationStatus
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    enum CodingKeys: String, CodingKey {
        case id
        case userID
        case version
        case type
        case data
        case meta
        case snapshot
        case moderationStatus
        case createdAt
        case updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try container.decode(String.self, forKey: .id),
            userID: try container.decode(String.self, forKey: .userID),
            version: try container.decode(Int.self, forKey: .version),
            type: try container.decode(String.self, forKey: .type),
            data: try container.decode(AppFeedbackData.self, forKey: .data),
            meta: try container.decode(AppFeedbackMeta.self, forKey: .meta),
            snapshot: try container.decodeIfPresent(AppFeedbackSnapshot.self, forKey: .snapshot),
            moderationStatus: try container.decodeIfPresent(AppFeedbackModerationStatus.self, forKey: .moderationStatus) ?? .pending,
            createdAt: try container.decode(Date.self, forKey: .createdAt),
            updatedAt: try container.decode(Date.self, forKey: .updatedAt)
        )
    }
}

enum AppFeedbackModerationStatus: String, Codable, Equatable, Sendable, CaseIterable {
    case pending
    case reviewed
    case dismissed

    var label: String {
        switch self {
        case .pending:
            return "Pending"
        case .reviewed:
            return "Reviewed"
        case .dismissed:
            return "Dismissed"
        }
    }

    var systemImageName: String {
        switch self {
        case .pending:
            return "clock"
        case .reviewed:
            return "checkmark.seal"
        case .dismissed:
            return "xmark.seal"
        }
    }
}

struct AppFeedbackData: Codable, Equatable, Sendable {
    var rating: MessageRating?
    var modelID: String?
    var siblingModelIDs: [String]
    var reason: String?
    var comment: String?
    var additional: [String: JSONValue]

    init(
        rating: MessageRating? = nil,
        modelID: String? = nil,
        siblingModelIDs: [String] = [],
        reason: String? = nil,
        comment: String? = nil,
        additional: [String: JSONValue] = [:]
    ) {
        self.rating = rating
        self.modelID = modelID
        self.siblingModelIDs = siblingModelIDs
        self.reason = reason
        self.comment = comment
        self.additional = additional
    }

    enum CodingKeys: String, CodingKey, CaseIterable {
        case rating
        case modelID = "model_id"
        case siblingModelIDs = "sibling_model_ids"
        case reason
        case comment
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: DynamicCodingKey.self)
        rating = Self.decodeRating(from: container, key: "rating")
        modelID = try container.decodeIfPresent(String.self, forKey: DynamicCodingKey("model_id"))
        siblingModelIDs = try container.decodeIfPresent(
            [String].self,
            forKey: DynamicCodingKey("sibling_model_ids")
        ) ?? []
        reason = try container.decodeIfPresent(String.self, forKey: DynamicCodingKey("reason"))
        comment = try container.decodeIfPresent(String.self, forKey: DynamicCodingKey("comment"))

        let knownKeys = Set(CodingKeys.allCases.map(\.rawValue))
        additional = [:]
        for key in container.allKeys where !knownKeys.contains(key.stringValue) {
            additional[key.stringValue] = try? container.decode(JSONValue.self, forKey: key)
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: DynamicCodingKey.self)
        if let rating {
            try container.encode(rating.rawValue, forKey: DynamicCodingKey("rating"))
        }
        try container.encodeIfPresent(modelID, forKey: DynamicCodingKey("model_id"))
        if !siblingModelIDs.isEmpty {
            try container.encode(siblingModelIDs, forKey: DynamicCodingKey("sibling_model_ids"))
        }
        try container.encodeIfPresent(reason, forKey: DynamicCodingKey("reason"))
        try container.encodeIfPresent(comment, forKey: DynamicCodingKey("comment"))
        for (key, value) in additional {
            try container.encode(value, forKey: DynamicCodingKey(key))
        }
    }

    private static func decodeRating(
        from container: KeyedDecodingContainer<DynamicCodingKey>,
        key: String
    ) -> MessageRating? {
        let codingKey = DynamicCodingKey(key)
        if let value = try? container.decode(String.self, forKey: codingKey) {
            switch value.lowercased() {
            case "positive", "up", "thumbs_up", "thumbsup", "like", "good", "1", "true":
                return .positive
            case "negative", "down", "thumbs_down", "thumbsdown", "dislike", "bad", "-1", "false":
                return .negative
            default:
                return nil
            }
        }
        if let value = try? container.decode(Int.self, forKey: codingKey) {
            if value > 0 {
                return .positive
            }
            if value < 0 {
                return .negative
            }
        }
        if let value = try? container.decode(Double.self, forKey: codingKey) {
            if value > 0 {
                return .positive
            }
            if value < 0 {
                return .negative
            }
        }
        if let value = try? container.decode(Bool.self, forKey: codingKey) {
            return value ? .positive : .negative
        }
        return nil
    }
}

struct AppFeedbackMeta: Codable, Equatable, Sendable {
    var arena: Bool?
    var chatID: String?
    var messageID: String?
    var tags: [String]
    var additional: [String: JSONValue]

    init(
        arena: Bool? = nil,
        chatID: String? = nil,
        messageID: String? = nil,
        tags: [String] = [],
        additional: [String: JSONValue] = [:]
    ) {
        self.arena = arena
        self.chatID = chatID
        self.messageID = messageID
        self.tags = tags
        self.additional = additional
    }

    enum CodingKeys: String, CodingKey, CaseIterable {
        case arena
        case chatID = "chat_id"
        case messageID = "message_id"
        case tags
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: DynamicCodingKey.self)
        arena = try container.decodeIfPresent(Bool.self, forKey: DynamicCodingKey("arena"))
        chatID = try container.decodeIfPresent(String.self, forKey: DynamicCodingKey("chat_id"))
        messageID = try container.decodeIfPresent(String.self, forKey: DynamicCodingKey("message_id"))
        tags = try container.decodeIfPresent([String].self, forKey: DynamicCodingKey("tags")) ?? []

        let knownKeys = Set(CodingKeys.allCases.map(\.rawValue))
        additional = [:]
        for key in container.allKeys where !knownKeys.contains(key.stringValue) {
            additional[key.stringValue] = try? container.decode(JSONValue.self, forKey: key)
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: DynamicCodingKey.self)
        try container.encodeIfPresent(arena, forKey: DynamicCodingKey("arena"))
        try container.encodeIfPresent(chatID, forKey: DynamicCodingKey("chat_id"))
        try container.encodeIfPresent(messageID, forKey: DynamicCodingKey("message_id"))
        if !tags.isEmpty {
            try container.encode(tags, forKey: DynamicCodingKey("tags"))
        }
        for (key, value) in additional {
            try container.encode(value, forKey: DynamicCodingKey(key))
        }
    }
}

struct AppFeedbackSnapshot: Codable, Equatable, Sendable {
    var chat: AppFeedbackChatSnapshot?
    var additional: [String: JSONValue]

    init(chat: AppFeedbackChatSnapshot? = nil, additional: [String: JSONValue] = [:]) {
        self.chat = chat
        self.additional = additional
    }

    enum CodingKeys: String, CodingKey, CaseIterable {
        case chat
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: DynamicCodingKey.self)
        chat = try container.decodeIfPresent(AppFeedbackChatSnapshot.self, forKey: DynamicCodingKey("chat"))

        let knownKeys = Set(CodingKeys.allCases.map(\.rawValue))
        additional = [:]
        for key in container.allKeys where !knownKeys.contains(key.stringValue) {
            additional[key.stringValue] = try? container.decode(JSONValue.self, forKey: key)
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: DynamicCodingKey.self)
        try container.encodeIfPresent(chat, forKey: DynamicCodingKey("chat"))
        for (key, value) in additional {
            try container.encode(value, forKey: DynamicCodingKey(key))
        }
    }
}

struct AppFeedbackChatSnapshot: Codable, Equatable, Sendable {
    var title: String?
    var messageCount: Int?

    enum CodingKeys: String, CodingKey {
        case title
        case messageCount = "message_count"
    }

    init(title: String? = nil, messageCount: Int? = nil) {
        self.title = title
        self.messageCount = messageCount
    }
}

private struct DynamicCodingKey: CodingKey {
    var stringValue: String
    var intValue: Int?

    init(_ stringValue: String) {
        self.stringValue = stringValue
        self.intValue = nil
    }

    init?(stringValue: String) {
        self.init(stringValue)
    }

    init?(intValue: Int) {
        self.stringValue = String(intValue)
        self.intValue = intValue
    }
}

enum ProviderStatus: Equatable, Sendable {
    case unknown
    case checking
    case available(String)
    case unavailable(String)

    var label: String {
        switch self {
        case .unknown:
            return "Unknown"
        case .checking:
            return "Checking..."
        case .available(let message):
            return message
        case .unavailable(let message):
            return message
        }
    }
}

enum ChatRole: String, Codable, Equatable, Sendable {
    case user
    case assistant
    case system
}

enum MessageRating: String, Codable, Equatable, Sendable {
    case positive
    case negative

    var label: String {
        switch self {
        case .positive:
            return "Positive"
        case .negative:
            return "Negative"
        }
    }
}

struct ChatAttachment: Identifiable, Codable, Equatable, Sendable {
    var id: UUID
    var fileName: String
    var contentType: String
    var byteCount: Int
    var textContent: String?
    var createdAt: Date

    init(
        id: UUID = UUID(),
        fileName: String,
        contentType: String = "text/plain",
        byteCount: Int,
        textContent: String? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.fileName = fileName
        self.contentType = contentType
        self.byteCount = byteCount
        self.textContent = textContent
        self.createdAt = createdAt
    }
}

struct AppFile: Identifiable, Codable, Equatable, Sendable {
    var id: UUID
    var fileName: String
    var contentType: String
    var byteCount: Int
    var textContent: String
    var originalData: Data?
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        fileName: String,
        contentType: String = "text/plain",
        byteCount: Int,
        textContent: String,
        originalData: Data? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.fileName = fileName
        self.contentType = contentType
        self.byteCount = byteCount
        self.textContent = textContent
        self.originalData = originalData
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    var chatAttachment: ChatAttachment {
        ChatAttachment(
            id: id,
            fileName: fileName,
            contentType: contentType,
            byteCount: byteCount,
            textContent: textContent,
            createdAt: createdAt
        )
    }
}

struct ChatCitation: Identifiable, Codable, Equatable, Sendable {
    var id: UUID
    var collectionName: String
    var collectionSlug: String
    var collectionID: UUID?
    var documentID: UUID?
    var chunkID: UUID?
    var sourceName: String
    var text: String
    var score: Double

    init(
        id: UUID = UUID(),
        collectionName: String,
        collectionSlug: String,
        collectionID: UUID? = nil,
        documentID: UUID? = nil,
        chunkID: UUID? = nil,
        sourceName: String,
        text: String,
        score: Double
    ) {
        self.id = id
        self.collectionName = collectionName
        self.collectionSlug = collectionSlug
        self.collectionID = collectionID
        self.documentID = documentID
        self.chunkID = chunkID
        self.sourceName = sourceName
        self.text = text
        self.score = score
    }
}

struct ChatGenerationMetrics: Codable, Equatable, Sendable {
    var startedAt: Date
    var completedAt: Date?

    var durationSeconds: TimeInterval? {
        guard let completedAt else {
            return nil
        }
        return max(completedAt.timeIntervalSince(startedAt), 0)
    }

    var durationLabel: String? {
        guard let durationSeconds else {
            return nil
        }
        let roundedDuration = (durationSeconds * 10).rounded() / 10
        return String(format: "%.1fs", roundedDuration)
    }

    init(startedAt: Date = Date(), completedAt: Date? = nil) {
        self.startedAt = startedAt
        self.completedAt = completedAt
    }

    func completed(at date: Date = Date()) -> ChatGenerationMetrics {
        ChatGenerationMetrics(startedAt: startedAt, completedAt: date)
    }
}

struct ChatTokenUsage: Codable, Equatable, Sendable {
    var promptTokens: Int?
    var completionTokens: Int?
    var totalTokens: Int?

    init(promptTokens: Int? = nil, completionTokens: Int? = nil, totalTokens: Int? = nil) {
        self.promptTokens = promptTokens
        self.completionTokens = completionTokens
        if let totalTokens {
            self.totalTokens = totalTokens
        } else if let promptTokens, let completionTokens {
            self.totalTokens = promptTokens + completionTokens
        } else {
            self.totalTokens = nil
        }
    }
}

struct ChatMessage: Identifiable, Codable, Equatable, Sendable {
    var id: UUID
    var role: ChatRole
    var content: String
    var modelID: String?
    var createdAt: Date
    var updatedAt: Date?
    var isStreaming: Bool
    var error: String?
    var rating: MessageRating?
    var originalContent: String?
    var attachments: [ChatAttachment]
    var citations: [ChatCitation]
    var generationMetrics: ChatGenerationMetrics?
    var tokenUsage: ChatTokenUsage?

    init(
        id: UUID = UUID(),
        role: ChatRole,
        content: String,
        modelID: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date? = nil,
        isStreaming: Bool = false,
        error: String? = nil,
        rating: MessageRating? = nil,
        originalContent: String? = nil,
        attachments: [ChatAttachment] = [],
        citations: [ChatCitation] = [],
        generationMetrics: ChatGenerationMetrics? = nil,
        tokenUsage: ChatTokenUsage? = nil
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.modelID = modelID
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.isStreaming = isStreaming
        self.error = error
        self.rating = rating
        self.originalContent = originalContent
        self.attachments = attachments
        self.citations = citations
        self.generationMetrics = generationMetrics
        self.tokenUsage = tokenUsage
    }

    enum CodingKeys: String, CodingKey {
        case id
        case role
        case content
        case modelID
        case createdAt
        case updatedAt
        case isStreaming
        case error
        case rating
        case originalContent
        case attachments
        case citations
        case generationMetrics
        case tokenUsage
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try container.decode(UUID.self, forKey: .id),
            role: try container.decode(ChatRole.self, forKey: .role),
            content: try container.decode(String.self, forKey: .content),
            modelID: try container.decodeIfPresent(String.self, forKey: .modelID),
            createdAt: try container.decode(Date.self, forKey: .createdAt),
            updatedAt: try container.decodeIfPresent(Date.self, forKey: .updatedAt),
            isStreaming: try container.decodeIfPresent(Bool.self, forKey: .isStreaming) ?? false,
            error: try container.decodeIfPresent(String.self, forKey: .error),
            rating: try container.decodeIfPresent(MessageRating.self, forKey: .rating),
            originalContent: try container.decodeIfPresent(String.self, forKey: .originalContent),
            attachments: try container.decodeIfPresent([ChatAttachment].self, forKey: .attachments) ?? [],
            citations: try container.decodeIfPresent([ChatCitation].self, forKey: .citations) ?? [],
            generationMetrics: try container.decodeIfPresent(ChatGenerationMetrics.self, forKey: .generationMetrics),
            tokenUsage: try container.decodeIfPresent(ChatTokenUsage.self, forKey: .tokenUsage)
        )
    }
}

struct ChatDeepLinkTarget: Equatable, Sendable {
    var threadID: UUID
    var messageID: UUID?
}

struct ChatThread: Identifiable, Codable, Equatable, Sendable {
    static let deepLinkScheme = "openwebui-native"
    static let deepLinkHost = "chats"

    var id: UUID
    var title: String
    var userID: String
    var createdAt: Date
    var updatedAt: Date
    var folderID: UUID?
    var providerID: UUID?
    var modelIDs: [String]
    var tags: [String]
    var isPinned: Bool
    var isArchived: Bool
    var messages: [ChatMessage]

    init(
        id: UUID = UUID(),
        title: String = "New Chat",
        userID: String = "local-user",
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        folderID: UUID? = nil,
        providerID: UUID? = nil,
        modelIDs: [String] = [],
        tags: [String] = [],
        isPinned: Bool = false,
        isArchived: Bool = false,
        messages: [ChatMessage] = []
    ) {
        self.id = id
        self.title = title
        self.userID = userID
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.folderID = folderID
        self.providerID = providerID
        self.modelIDs = modelIDs
        self.tags = tags
        self.isPinned = isPinned
        self.isArchived = isArchived
        self.messages = messages
    }

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case userID
        case createdAt
        case updatedAt
        case folderID
        case providerID
        case modelIDs
        case tags
        case isPinned
        case isArchived
        case messages
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try container.decode(UUID.self, forKey: .id),
            title: try container.decode(String.self, forKey: .title),
            userID: try container.decodeIfPresent(String.self, forKey: .userID) ?? "local-user",
            createdAt: try container.decode(Date.self, forKey: .createdAt),
            updatedAt: try container.decode(Date.self, forKey: .updatedAt),
            folderID: try container.decodeIfPresent(UUID.self, forKey: .folderID),
            providerID: try container.decodeIfPresent(UUID.self, forKey: .providerID),
            modelIDs: try container.decodeIfPresent([String].self, forKey: .modelIDs) ?? [],
            tags: try container.decodeIfPresent([String].self, forKey: .tags) ?? [],
            isPinned: try container.decodeIfPresent(Bool.self, forKey: .isPinned) ?? false,
            isArchived: try container.decodeIfPresent(Bool.self, forKey: .isArchived) ?? false,
            messages: try container.decodeIfPresent([ChatMessage].self, forKey: .messages) ?? []
        )
    }

    var deepLinkURL: URL {
        URL(string: "\(Self.deepLinkScheme)://\(Self.deepLinkHost)/\(id.uuidString)")!
    }

    func deepLinkURL(forMessageID messageID: UUID) -> URL {
        URL(string: "\(Self.deepLinkScheme)://\(Self.deepLinkHost)/\(id.uuidString)/messages/\(messageID.uuidString)")!
    }

    static func threadID(fromDeepLink url: URL) -> UUID? {
        deepLinkTarget(fromDeepLink: url)?.threadID
    }

    static func deepLinkTarget(fromDeepLink url: URL) -> ChatDeepLinkTarget? {
        guard url.scheme == deepLinkScheme,
              url.host == deepLinkHost else {
            return nil
        }

        let components = url.pathComponents.filter { $0 != "/" }
        if components.count == 1, let threadID = UUID(uuidString: components[0]) {
            return ChatDeepLinkTarget(threadID: threadID, messageID: nil)
        }

        guard components.count == 3,
              components[1] == "messages",
              let threadID = UUID(uuidString: components[0]),
              let messageID = UUID(uuidString: components[2]) else {
            return nil
        }
        return ChatDeepLinkTarget(threadID: threadID, messageID: messageID)
    }
}

struct ProviderChatMessage: Codable, Equatable, Sendable {
    var role: String
    var content: String
}

enum WebSearchEngine: String, CaseIterable, Codable, Equatable, Sendable {
    case duckDuckGoHTML
    case searxng
    case brave
    case tavily

    var label: String {
        switch self {
        case .duckDuckGoHTML:
            return "DuckDuckGo HTML"
        case .searxng:
            return "SearXNG"
        case .brave:
            return "Brave Search"
        case .tavily:
            return "Tavily"
        }
    }
}

struct WebSearchSettings: Codable, Equatable, Sendable {
    static let resultCountRange = 1...10
    static let pageContentCharacterRange = 1...12_000

    var engine: WebSearchEngine
    var resultCount: Int
    var searxngBaseURL: String
    var braveAPIKeySecretID: String?
    var tavilyAPIKeySecretID: String?
    var domainFilterList: [String]
    var isPageContentLoadingEnabled: Bool
    var maxPageContentCharacters: Int

    init(
        engine: WebSearchEngine = .duckDuckGoHTML,
        resultCount: Int = 3,
        searxngBaseURL: String = "",
        braveAPIKeySecretID: String? = nil,
        tavilyAPIKeySecretID: String? = nil,
        domainFilterList: [String] = [],
        isPageContentLoadingEnabled: Bool = false,
        maxPageContentCharacters: Int = 4_000
    ) {
        self.engine = engine
        self.resultCount = Self.clamped(resultCount, to: Self.resultCountRange)
        self.searxngBaseURL = searxngBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedBraveSecretID = braveAPIKeySecretID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        self.braveAPIKeySecretID = trimmedBraveSecretID.isEmpty ? nil : trimmedBraveSecretID
        let trimmedTavilySecretID = tavilyAPIKeySecretID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        self.tavilyAPIKeySecretID = trimmedTavilySecretID.isEmpty ? nil : trimmedTavilySecretID
        self.domainFilterList = Self.normalizedDomainFilters(domainFilterList)
        self.isPageContentLoadingEnabled = isPageContentLoadingEnabled
        self.maxPageContentCharacters = Self.clamped(maxPageContentCharacters, to: Self.pageContentCharacterRange)
    }

    enum CodingKeys: String, CodingKey {
        case engine
        case resultCount
        case searxngBaseURL
        case braveAPIKeySecretID
        case tavilyAPIKeySecretID
        case domainFilterList
        case isPageContentLoadingEnabled
        case maxPageContentCharacters
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            engine: try container.decodeIfPresent(WebSearchEngine.self, forKey: .engine) ?? .duckDuckGoHTML,
            resultCount: try container.decodeIfPresent(Int.self, forKey: .resultCount) ?? 3,
            searxngBaseURL: try container.decodeIfPresent(String.self, forKey: .searxngBaseURL) ?? "",
            braveAPIKeySecretID: try container.decodeIfPresent(String.self, forKey: .braveAPIKeySecretID),
            tavilyAPIKeySecretID: try container.decodeIfPresent(String.self, forKey: .tavilyAPIKeySecretID),
            domainFilterList: try container.decodeIfPresent([String].self, forKey: .domainFilterList) ?? [],
            isPageContentLoadingEnabled: try container.decodeIfPresent(Bool.self, forKey: .isPageContentLoadingEnabled) ?? false,
            maxPageContentCharacters: try container.decodeIfPresent(Int.self, forKey: .maxPageContentCharacters) ?? 4_000
        )
    }

    private static func clamped(_ value: Int, to range: ClosedRange<Int>) -> Int {
        min(max(value, range.lowerBound), range.upperBound)
    }

    private static func normalizedDomainFilters(_ filters: [String]) -> [String] {
        var seen: Set<String> = []
        var result: [String] = []
        for filter in filters {
            let normalized = filter.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !normalized.isEmpty, !seen.contains(normalized) else {
                continue
            }
            seen.insert(normalized)
            result.append(normalized)
        }
        return result
    }
}

struct AppSettings: Codable, Equatable, Sendable {
    var ollamaBaseURL: String
    var providers: [ProviderConfiguration]
    var activeProviderID: UUID
    var selectedModelID: String?
    var selectedModelIDs: [String]
    var embeddingModelID: String?
    var featureToggles: FeatureToggleSettings
    var webSearch: WebSearchSettings
    var codeExecution: CodeExecutionSettings

    init(
        ollamaBaseURL: String = "http://localhost:11434",
        providers: [ProviderConfiguration]? = nil,
        activeProviderID: UUID = ProviderConfiguration.defaultOllamaID,
        selectedModelID: String? = nil,
        selectedModelIDs: [String]? = nil,
        embeddingModelID: String? = nil,
        featureToggles: FeatureToggleSettings = FeatureToggleSettings(),
        webSearch: WebSearchSettings = WebSearchSettings(),
        codeExecution: CodeExecutionSettings = CodeExecutionSettings()
    ) {
        self.ollamaBaseURL = ollamaBaseURL
        let resolvedProviders = providers ?? [ProviderConfiguration.defaultOllama(baseURL: ollamaBaseURL)]
        self.providers = resolvedProviders
        self.activeProviderID = activeProviderID
        self.selectedModelID = selectedModelID
        self.selectedModelIDs = selectedModelIDs ?? selectedModelID.map { [$0] } ?? []
        self.embeddingModelID = embeddingModelID
        self.featureToggles = featureToggles
        self.webSearch = webSearch
        self.codeExecution = codeExecution
    }

    var activeProvider: ProviderConfiguration {
        providers.first { $0.id == activeProviderID } ?? ProviderConfiguration.defaultOllama(baseURL: ollamaBaseURL)
    }

    enum CodingKeys: String, CodingKey {
        case ollamaBaseURL
        case providers
        case activeProviderID
        case selectedModelID
        case selectedModelIDs
        case embeddingModelID
        case featureToggles
        case webSearch
        case codeExecution
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let ollamaBaseURL = try container.decodeIfPresent(String.self, forKey: .ollamaBaseURL) ?? "http://localhost:11434"
        let decodedProviders = try container.decodeIfPresent([ProviderConfiguration].self, forKey: .providers) ?? []
        let providers = decodedProviders.isEmpty
            ? [ProviderConfiguration.defaultOllama(baseURL: ollamaBaseURL)]
            : decodedProviders
        let decodedActiveProviderID = try container.decodeIfPresent(UUID.self, forKey: .activeProviderID)
        let activeProviderID = decodedActiveProviderID.flatMap { activeID in
            providers.contains { $0.id == activeID } ? activeID : nil
        } ?? providers.first?.id ?? ProviderConfiguration.defaultOllamaID

        self.init(
            ollamaBaseURL: ollamaBaseURL,
            providers: providers,
            activeProviderID: activeProviderID,
            selectedModelID: try container.decodeIfPresent(String.self, forKey: .selectedModelID),
            selectedModelIDs: try container.decodeIfPresent([String].self, forKey: .selectedModelIDs),
            embeddingModelID: try container.decodeIfPresent(String.self, forKey: .embeddingModelID),
            featureToggles: try container.decodeIfPresent(
                FeatureToggleSettings.self,
                forKey: .featureToggles
            ) ?? FeatureToggleSettings(),
            webSearch: try container.decodeIfPresent(WebSearchSettings.self, forKey: .webSearch) ?? WebSearchSettings(),
            codeExecution: try container.decodeIfPresent(CodeExecutionSettings.self, forKey: .codeExecution) ?? CodeExecutionSettings()
        )
    }
}
