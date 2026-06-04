import Foundation

struct ProviderCapabilityRow: Equatable, Identifiable, Sendable {
    var id: String { label }
    var label: String
    var isSupported: Bool

    var statusText: String {
        isSupported ? "Supported" : "Unsupported"
    }
}

enum ProviderModelCapabilityStatus: String, Equatable, Sendable {
    case supported
    case unsupported
    case unknown

    var isSupported: Bool {
        self == .supported
    }
}

struct ProviderModelCapabilityMetadata: Equatable, Sendable {
    var embeddings: ProviderModelCapabilityStatus = .unknown
    var audioTranscription: ProviderModelCapabilityStatus = .unknown
    var speechSynthesis: ProviderModelCapabilityStatus = .unknown

    var supportsEmbeddings: Bool {
        embeddings.isSupported
    }

    var supportsAudioTranscription: Bool {
        audioTranscription.isSupported
    }

    var supportsSpeechSynthesis: Bool {
        speechSynthesis.isSupported
    }
}

enum ProviderCapabilitySummary {
    static func rows(for provider: ProviderConfiguration) -> [ProviderCapabilityRow] {
        rows(for: provider.capabilities)
    }

    static func rows(for capabilities: ProviderCapabilities) -> [ProviderCapabilityRow] {
        [
            ProviderCapabilityRow(label: "Chat", isSupported: capabilities.supportsChat),
            ProviderCapabilityRow(label: "Completions", isSupported: capabilities.supportsCompletions),
            ProviderCapabilityRow(label: "Embeddings", isSupported: capabilities.supportsEmbeddings),
            ProviderCapabilityRow(label: "Model management", isSupported: capabilities.supportsModelManagement),
            ProviderCapabilityRow(label: "Image generation", isSupported: capabilities.supportsImageGeneration),
            ProviderCapabilityRow(label: "Image editing", isSupported: capabilities.supportsImageEditing),
            ProviderCapabilityRow(label: "Image variations", isSupported: capabilities.supportsImageVariation),
            ProviderCapabilityRow(label: "Audio transcription", isSupported: capabilities.supportsAudioTranscription),
            ProviderCapabilityRow(label: "Speech synthesis", isSupported: capabilities.supportsSpeechSynthesis)
        ]
    }
}

extension ProviderModel {
    var capabilityMetadata: ProviderModelCapabilityMetadata {
        let searchText = capabilitySearchText
        return ProviderModelCapabilityMetadata(
            embeddings: Self.capabilityStatus(
                searchText,
                matchers: [
                    "embedding",
                    "embed",
                    "nomic-embed",
                    "bge-",
                    "e5-",
                    "gte-",
                    "jina-embeddings",
                    "sentence-transformer"
                ]
            ),
            audioTranscription: Self.capabilityStatus(
                searchText,
                matchers: [
                    "transcribe",
                    "transcription",
                    "whisper",
                    "stt"
                ]
            ),
            speechSynthesis: Self.capabilityStatus(
                searchText,
                matchers: [
                    "tts",
                    "text-to-speech",
                    "speech",
                    "voice"
                ]
            )
        )
    }

    private var capabilitySearchText: String {
        [id, name, details]
            .compactMap { $0?.lowercased() }
            .joined(separator: " ")
    }

    private static func capabilityStatus(_ searchText: String, matchers: [String]) -> ProviderModelCapabilityStatus {
        guard !searchText.isEmpty else {
            return .unknown
        }
        return matchers.contains { searchText.contains($0) } ? .supported : .unknown
    }
}
