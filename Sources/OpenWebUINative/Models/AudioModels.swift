import Foundation

enum AppAudioHistoryKind: String, Codable, Equatable, Sendable {
    case transcription
    case speech

    var label: String {
        switch self {
        case .transcription:
            return "Transcription"
        case .speech:
            return "Speech"
        }
    }
}

enum AppAudioPlaybackState: String, Codable, Equatable, Sendable {
    case stopped
    case playing
    case paused
}

struct AppAudioHistoryItem: Identifiable, Codable, Equatable, Sendable {
    var id: UUID
    var kind: AppAudioHistoryKind
    var title: String
    var text: String
    var modelID: String
    var sourceFileName: String?
    var sourceContentType: String?
    var voice: String?
    var instructions: String?
    var outputFormat: String?
    var audioData: Data?
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        kind: AppAudioHistoryKind,
        title: String,
        text: String,
        modelID: String,
        sourceFileName: String? = nil,
        sourceContentType: String? = nil,
        voice: String? = nil,
        instructions: String? = nil,
        outputFormat: String? = nil,
        audioData: Data? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.text = text
        self.modelID = modelID
        self.sourceFileName = sourceFileName
        self.sourceContentType = sourceContentType
        self.voice = voice
        self.instructions = instructions
        self.outputFormat = outputFormat
        self.audioData = audioData
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
