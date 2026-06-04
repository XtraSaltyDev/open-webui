import Foundation

struct PlaygroundTranscript: Codable, Equatable, Sendable {
    var mode: PlaygroundMode
    var modelID: String
    var comparisonModelID: String?
    var isComparisonEnabled: Bool
    var systemPrompt: String?
    var prompt: String
    var output: String
    var comparisonOutput: String?
    var options: ProviderChatOptions?
    var imageOutputs: [PlaygroundImageOutput]
    var imageSize: String?
    var imageQuality: String?
    var imageCount: Int?
    var createdAt: Date

    init(
        mode: PlaygroundMode = .chat,
        modelID: String,
        comparisonModelID: String? = nil,
        isComparisonEnabled: Bool = false,
        systemPrompt: String? = nil,
        prompt: String,
        output: String,
        comparisonOutput: String? = nil,
        options: ProviderChatOptions? = nil,
        imageOutputs: [PlaygroundImageOutput] = [],
        imageSize: String? = nil,
        imageQuality: String? = nil,
        imageCount: Int? = nil,
        createdAt: Date = Date()
    ) {
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
    }
}

struct PlaygroundExportBundle: Codable, Equatable, Sendable {
    var version: Int
    var transcript: PlaygroundTranscript

    init(version: Int = 1, transcript: PlaygroundTranscript) {
        self.version = version
        self.transcript = transcript
    }
}

struct PlaygroundExportService: Sendable {
    func jsonData(for transcript: PlaygroundTranscript) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(PlaygroundExportBundle(transcript: transcript))
    }

    func text(for transcript: PlaygroundTranscript) -> String {
        var sections: [String] = []
        if transcript.mode == .images {
            sections.append("### MODE\nImages")
        }
        if let systemPrompt = transcript.systemPrompt?.trimmingCharacters(in: .whitespacesAndNewlines),
           !systemPrompt.isEmpty {
            sections.append("### SYSTEM\n\(systemPrompt)")
        }
        sections.append("### USER\n\(transcript.prompt)")
        if transcript.isComparisonEnabled,
           let comparisonOutput = transcript.comparisonOutput?.trimmingCharacters(in: .whitespacesAndNewlines),
           !comparisonOutput.isEmpty {
            sections.append("### ASSISTANT (\(transcript.modelID))\n\(transcript.output)")
            let comparisonTitle = transcript.comparisonModelID ?? "Comparison"
            sections.append("### ASSISTANT (\(comparisonTitle))\n\(comparisonOutput)")
        } else {
            sections.append("### ASSISTANT\n\(transcript.output)")
        }
        return sections.joined(separator: "\n\n")
    }
}
