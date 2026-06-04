import Foundation

struct AppGeneratedImage: Identifiable, Codable, Equatable, Sendable {
    var id: UUID
    var prompt: String
    var modelID: String
    var providerID: UUID?
    var imageData: Data
    var revisedPrompt: String?
    var outputFormat: String?
    var size: String?
    var quality: String?
    var sourceImageID: UUID?
    var sourceOperation: String?
    var createdAt: Date

    init(
        id: UUID = UUID(),
        prompt: String,
        modelID: String,
        providerID: UUID? = nil,
        imageData: Data,
        revisedPrompt: String? = nil,
        outputFormat: String? = nil,
        size: String? = nil,
        quality: String? = nil,
        sourceImageID: UUID? = nil,
        sourceOperation: String? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.prompt = prompt
        self.modelID = modelID
        self.providerID = providerID
        self.imageData = imageData
        self.revisedPrompt = revisedPrompt
        self.outputFormat = outputFormat
        self.size = size
        self.quality = quality
        self.sourceImageID = sourceImageID
        self.sourceOperation = sourceOperation
        self.createdAt = createdAt
    }
}
