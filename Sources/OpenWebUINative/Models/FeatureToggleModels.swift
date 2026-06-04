import Foundation

enum AppFeatureToggle: String, CaseIterable, Codable, Identifiable, Equatable, Sendable {
    case folders
    case files
    case knowledge
    case prompts
    case notes
    case tools
    case skills
    case functions
    case evaluations
    case analytics
    case adminDirectory
    case webSearch
    case imageGeneration
    case audio
    case voiceMode
    case channels
    case automations
    case calendar
    case playground
    case codeInterpreter
    case terminalSessions
    case directToolServers

    var id: String { rawValue }

    var label: String {
        switch self {
        case .folders:
            return "Folders"
        case .files:
            return "Files"
        case .knowledge:
            return "Knowledge"
        case .prompts:
            return "Prompts"
        case .notes:
            return "Notes"
        case .tools:
            return "Tools"
        case .skills:
            return "Skills"
        case .functions:
            return "Functions"
        case .evaluations:
            return "Evaluations"
        case .analytics:
            return "Analytics"
        case .adminDirectory:
            return "Admin Directory"
        case .webSearch:
            return "Web Search"
        case .imageGeneration:
            return "Image Generation"
        case .audio:
            return "Audio"
        case .voiceMode:
            return "Voice Mode"
        case .channels:
            return "Channels"
        case .automations:
            return "Automations"
        case .calendar:
            return "Calendar"
        case .playground:
            return "Playground"
        case .codeInterpreter:
            return "Code Interpreter"
        case .terminalSessions:
            return "Terminal Sessions"
        case .directToolServers:
            return "Direct Tool Servers"
        }
    }

    var groupLabel: String {
        switch self {
        case .folders, .files, .knowledge, .prompts, .notes, .tools, .skills, .functions, .evaluations, .analytics, .adminDirectory, .webSearch,
             .channels, .automations, .calendar, .playground, .imageGeneration, .audio, .voiceMode, .codeInterpreter, .terminalSessions, .directToolServers:
            return "Native Surfaces"
        }
    }

    var defaultEnabled: Bool {
        switch self {
        case .folders, .files, .knowledge, .prompts, .notes, .tools, .skills, .functions, .evaluations, .analytics, .adminDirectory, .webSearch,
             .channels, .automations, .calendar, .playground, .imageGeneration, .audio, .voiceMode:
            return true
        case .codeInterpreter, .terminalSessions, .directToolServers:
            return false
        }
    }
}

struct FeatureToggleSettings: Codable, Equatable, Sendable {
    private var overrides: [String: Bool]

    init(overrides: [String: Bool] = [:]) {
        self.overrides = overrides
    }

    func isEnabled(_ feature: AppFeatureToggle) -> Bool {
        overrides[feature.rawValue] ?? feature.defaultEnabled
    }

    mutating func set(_ feature: AppFeatureToggle, isEnabled: Bool) {
        if isEnabled == feature.defaultEnabled {
            overrides.removeValue(forKey: feature.rawValue)
        } else {
            overrides[feature.rawValue] = isEnabled
        }
    }

    enum CodingKeys: String, CodingKey {
        case overrides
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        overrides = try container.decodeIfPresent([String: Bool].self, forKey: .overrides) ?? [:]
    }
}
