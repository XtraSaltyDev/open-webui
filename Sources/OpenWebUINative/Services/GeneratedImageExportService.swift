import Foundation

struct GeneratedImageExportService: Sendable {
    func jsonData(for images: [AppGeneratedImage], exportedAt: Date = Date()) throws -> Data {
        let bundle = GeneratedImageExportBundle(exportedAt: exportedAt, images: images)
        return try JSONEncoder.openWebUIEncoder.encode(bundle)
    }

    func openWebUIJSONData(for images: [AppGeneratedImage]) throws -> Data {
        let envelope = OpenWebUIGeneratedImageExportEnvelope(images: images)
        return try JSONEncoder.openWebUIEncoder.encode(envelope)
    }

    func images(fromJSONData data: Data) throws -> [AppGeneratedImage] {
        let decoder = JSONDecoder.openWebUIDecoder
        if let bundle = try? decoder.decode(GeneratedImageExportBundle.self, from: data) {
            return bundle.images.sorted { $0.createdAt > $1.createdAt }
        }
        if let envelope = try? decoder.decode(OpenWebUIGeneratedImageExportEnvelope.self, from: data) {
            return envelope.images.sorted { $0.createdAt > $1.createdAt }
        }
        let images = try decoder.decode([AppGeneratedImage].self, from: data)
        return images.sorted { $0.createdAt > $1.createdAt }
    }
}

private struct OpenWebUIGeneratedImageExportEnvelope: Codable {
    var created: Int
    var data: [OpenWebUIGeneratedImageExportRecord]

    init(images: [AppGeneratedImage]) {
        created = Int(images.map(\.createdAt).max()?.timeIntervalSince1970 ?? Date().timeIntervalSince1970)
        data = images.map(OpenWebUIGeneratedImageExportRecord.init(image:))
    }

    var images: [AppGeneratedImage] {
        data.compactMap(\.appGeneratedImage)
    }
}

private struct OpenWebUIGeneratedImageExportRecord: Codable {
    var id: String?
    var b64JSON: String
    var revisedPrompt: String?
    var prompt: String?
    var model: String?
    var providerID: String?
    var outputFormat: String?
    var size: String?
    var quality: String?
    var sourceImageID: String?
    var sourceOperation: String?
    var createdAt: Int?

    enum CodingKeys: String, CodingKey {
        case id
        case b64JSON = "b64_json"
        case revisedPrompt = "revised_prompt"
        case prompt
        case model
        case providerID = "provider_id"
        case outputFormat = "output_format"
        case size
        case quality
        case sourceImageID = "source_image_id"
        case sourceOperation = "source_operation"
        case createdAt = "created_at"
    }

    init(image: AppGeneratedImage) {
        id = image.id.uuidString
        b64JSON = image.imageData.base64EncodedString()
        revisedPrompt = image.revisedPrompt
        prompt = image.prompt
        model = image.modelID
        providerID = image.providerID?.uuidString
        outputFormat = image.outputFormat
        size = image.size
        quality = image.quality
        sourceImageID = image.sourceImageID?.uuidString
        sourceOperation = image.sourceOperation
        createdAt = Int(image.createdAt.timeIntervalSince1970)
    }

    var appGeneratedImage: AppGeneratedImage? {
        guard let imageData = Data(base64Encoded: b64JSON) else {
            return nil
        }
        return AppGeneratedImage(
            id: id.flatMap(UUID.init(uuidString:)) ?? UUID(),
            prompt: prompt?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? revisedPrompt?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? "Imported image",
            modelID: model?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? "unknown-image-model",
            providerID: providerID.flatMap(UUID.init(uuidString:)),
            imageData: imageData,
            revisedPrompt: revisedPrompt?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            outputFormat: outputFormat?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            size: size?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            quality: quality?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            sourceImageID: sourceImageID.flatMap(UUID.init(uuidString:)),
            sourceOperation: sourceOperation?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            createdAt: createdAt.map { Date(timeIntervalSince1970: TimeInterval($0)) } ?? Date()
        )
    }
}

private struct GeneratedImageExportBundle: Codable {
    var format: String
    var version: Int
    var exportedAt: Date
    var images: [AppGeneratedImage]

    init(
        format: String = "open-webui-native-generated-images",
        version: Int = 1,
        exportedAt: Date,
        images: [AppGeneratedImage]
    ) {
        self.format = format
        self.version = version
        self.exportedAt = exportedAt
        self.images = images
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
