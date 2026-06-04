import Foundation

struct ProviderCapabilityRow: Equatable, Identifiable, Sendable {
    var id: String { label }
    var label: String
    var isSupported: Bool

    var statusText: String {
        isSupported ? "Supported" : "Unsupported"
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
