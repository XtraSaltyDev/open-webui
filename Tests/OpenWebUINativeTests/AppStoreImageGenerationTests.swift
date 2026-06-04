import Foundation
import XCTest
@testable import OpenWebUINative

final class AppStoreImageGenerationTests: XCTestCase {
    @MainActor
    func testSelectImageGenerationClearsOtherDetailSelections() async throws {
        let fixture = try ImageGenerationFixture(provider: FakeImageGenerationProvider())
        let store = fixture.makeStore()
        store.selectedThreadID = UUID()
        store.selectedChannelID = UUID()
        store.isShowingEvaluationDashboard = true
        store.isShowingAnalyticsDashboard = true
        store.isShowingPlayground = true
        store.isShowingCalendar = true

        store.selectImageGeneration()

        XCTAssertNil(store.selectedThreadID)
        XCTAssertNil(store.selectedChannelID)
        XCTAssertFalse(store.isShowingEvaluationDashboard)
        XCTAssertFalse(store.isShowingAnalyticsDashboard)
        XCTAssertFalse(store.isShowingPlayground)
        XCTAssertFalse(store.isShowingCalendar)
        XCTAssertTrue(store.isShowingImageGeneration)
    }

    @MainActor
    func testGenerateImageStoresProviderResultAndRequestMetadata() async throws {
        let imageData = Data("image-bytes".utf8)
        let provider = FakeImageGenerationProvider(
            result: ImageGenerationResult(
                images: [GeneratedImage(data: imageData, revisedPrompt: "A refined native icon")],
                outputFormat: "png",
                size: "1024x1024",
                quality: "high"
            )
        )
        let fixture = try ImageGenerationFixture(provider: provider)
        let store = fixture.makeStore()
        store.models = [
            ProviderModel(id: "gpt-image-1", name: "gpt-image-1", provider: .openAICompatible, providerID: provider.configuration.id)
        ]
        store.imageGenerationModelID = "gpt-image-1"
        store.imageGenerationPrompt = "Native app icon"
        store.imageGenerationSize = "1024x1024"
        store.imageGenerationQuality = "high"
        store.imageGenerationCount = 1

        await store.generateImage()

        let captured = await provider.capturedRequest
        XCTAssertEqual(captured?.model, "gpt-image-1")
        XCTAssertEqual(captured?.prompt, "Native app icon")
        XCTAssertEqual(captured?.size, "1024x1024")
        XCTAssertEqual(captured?.quality, "high")
        XCTAssertEqual(captured?.count, 1)
        XCTAssertEqual(store.generatedImages.count, 1)
        XCTAssertEqual(store.generatedImages.first?.imageData, imageData)
        XCTAssertEqual(store.generatedImages.first?.prompt, "Native app icon")
        XCTAssertEqual(store.generatedImages.first?.revisedPrompt, "A refined native icon")
        XCTAssertEqual(store.generatedImages.first?.outputFormat, "png")
        XCTAssertFalse(store.isGeneratingImage)
        XCTAssertNil(store.imageGenerationError)
    }

    @MainActor
    func testLoadReadsGeneratedImagesFromStorage() async throws {
        let fixture = try ImageGenerationFixture(provider: FakeImageGenerationProvider())
        let image = AppGeneratedImage(
            prompt: "Persisted image",
            modelID: "gpt-image-1",
            imageData: Data("persisted".utf8),
            outputFormat: "png",
            size: "1024x1024",
            quality: "high",
            createdAt: Date(timeIntervalSince1970: 300)
        )
        try await fixture.generatedImageStorage.save(image)

        let store = fixture.makeStore()
        await store.load()

        XCTAssertEqual(store.generatedImages, [image])
    }

    @MainActor
    func testGenerateImagePersistsGeneratedRecordsForReload() async throws {
        let imageData = Data("image-bytes".utf8)
        let provider = FakeImageGenerationProvider(
            result: ImageGenerationResult(
                images: [GeneratedImage(data: imageData, revisedPrompt: "A refined native icon")],
                outputFormat: "png",
                size: "1024x1024",
                quality: "high"
            )
        )
        let fixture = try ImageGenerationFixture(provider: provider)
        let store = fixture.makeStore()
        store.models = [
            ProviderModel(id: "gpt-image-1", name: "gpt-image-1", provider: .openAICompatible, providerID: provider.configuration.id)
        ]
        store.imageGenerationModelID = "gpt-image-1"
        store.imageGenerationPrompt = "Native app icon"

        await store.generateImage()

        let reloadedStore = fixture.makeStore()
        await reloadedStore.load()

        XCTAssertEqual(reloadedStore.generatedImages.count, 1)
        XCTAssertEqual(reloadedStore.generatedImages.first?.imageData, imageData)
        XCTAssertEqual(reloadedStore.generatedImages.first?.prompt, "Native app icon")
        XCTAssertEqual(reloadedStore.generatedImages.first?.revisedPrompt, "A refined native icon")
    }

    @MainActor
    func testExportAndImportGeneratedImagesJSONRoundTripsLibrary() async throws {
        let sourceFixture = try ImageGenerationFixture(provider: FakeImageGenerationProvider())
        let sourceStore = sourceFixture.makeStore()
        let image = AppGeneratedImage(
            prompt: "Exported image",
            modelID: "gpt-image-1",
            providerID: UUID(),
            imageData: Data("exported".utf8),
            revisedPrompt: "Exported revised",
            outputFormat: "png",
            size: "1024x1024",
            quality: "high",
            createdAt: Date(timeIntervalSince1970: 400)
        )
        sourceStore.generatedImages = [image]

        let data = try sourceStore.exportGeneratedImagesJSONData()

        let importFixture = try ImageGenerationFixture(provider: FakeImageGenerationProvider())
        let importStore = importFixture.makeStore()
        try await importStore.importGeneratedImagesJSONData(data)

        let persistedImages = try await importFixture.generatedImageStorage.loadImages()
        XCTAssertEqual(importStore.generatedImages, [image])
        XCTAssertEqual(persistedImages, [image])
    }

    @MainActor
    func testExportGeneratedImagesOpenWebUIJSONDataBuildsRawImageResponseRecords() async throws {
        let sourceFixture = try ImageGenerationFixture(provider: FakeImageGenerationProvider())
        let sourceStore = sourceFixture.makeStore()
        let sourceID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
        let imageID = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
        let image = AppGeneratedImage(
            id: imageID,
            prompt: "Native image export",
            modelID: "gpt-image-1",
            providerID: UUID(uuidString: "33333333-3333-3333-3333-333333333333"),
            imageData: Data("raw-image-bytes".utf8),
            revisedPrompt: "Native image export, refined",
            outputFormat: "png",
            size: "1024x1024",
            quality: "high",
            sourceImageID: sourceID,
            sourceOperation: "edit",
            createdAt: Date(timeIntervalSince1970: 500)
        )
        sourceStore.generatedImages = [image]

        let data = try sourceStore.exportGeneratedImagesOpenWebUIJSONData()
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let records = try XCTUnwrap(root["data"] as? [[String: Any]])
        let record: [String: Any] = try XCTUnwrap(records.first)

        XCTAssertNil(root["format"])
        XCTAssertEqual(root["created"] as? Int, 500)
        XCTAssertEqual(record["id"] as? String, imageID.uuidString)
        XCTAssertEqual(record["b64_json"] as? String, Data("raw-image-bytes".utf8).base64EncodedString())
        XCTAssertEqual(record["revised_prompt"] as? String, "Native image export, refined")
        XCTAssertEqual(record["prompt"] as? String, "Native image export")
        XCTAssertEqual(record["model"] as? String, "gpt-image-1")
        XCTAssertEqual(record["size"] as? String, "1024x1024")
        XCTAssertEqual(record["quality"] as? String, "high")
        XCTAssertEqual(record["output_format"] as? String, "png")
        XCTAssertEqual(record["created_at"] as? Int, 500)
        XCTAssertEqual(record["source_image_id"] as? String, sourceID.uuidString)
        XCTAssertEqual(record["source_operation"] as? String, "edit")

        let importFixture = try ImageGenerationFixture(provider: FakeImageGenerationProvider())
        let importStore = importFixture.makeStore()
        try await importStore.importGeneratedImagesJSONData(data)
        XCTAssertEqual(importStore.generatedImages, [image])
    }

    @MainActor
    func testExportGeneratedImagesJSONForUserActionCreatesAuditEventWithoutImageContent() async throws {
        let sourceFixture = try ImageGenerationFixture(provider: FakeImageGenerationProvider())
        let sourceStore = sourceFixture.makeStore()
        let original = AppGeneratedImage(
            prompt: "Sensitive generated prompt",
            modelID: "gpt-image-1",
            imageData: Data("sensitive-image-bytes".utf8),
            revisedPrompt: "Sensitive revised prompt",
            outputFormat: "png",
            sourceOperation: nil,
            createdAt: Date(timeIntervalSince1970: 700)
        )
        let edited = AppGeneratedImage(
            prompt: "Sensitive edit prompt",
            modelID: "gpt-image-1",
            imageData: Data("edited-sensitive-image-bytes".utf8),
            sourceImageID: original.id,
            sourceOperation: "edit",
            createdAt: Date(timeIntervalSince1970: 800)
        )
        sourceStore.generatedImages = [edited, original]

        let data = try await sourceStore.exportGeneratedImagesJSONDataForUserAction()

        let importFixture = try ImageGenerationFixture(provider: FakeImageGenerationProvider())
        let importStore = importFixture.makeStore()
        try await importStore.importGeneratedImagesJSONData(data)
        XCTAssertEqual(importStore.generatedImages.count, 2)
        XCTAssertEqual(importStore.generatedImages.first?.prompt, "Sensitive edit prompt")
        let event = try XCTUnwrap(sourceStore.auditEvents.first(where: { $0.action == .generatedImagesExported }))
        XCTAssertEqual(event.outcome, .succeeded)
        XCTAssertEqual(event.summary, "Exported generated images")
        XCTAssertEqual(event.metadata["exportedGeneratedImageCount"], "2")
        XCTAssertEqual(event.metadata["exportedOriginalImageCount"], "1")
        XCTAssertEqual(event.metadata["exportedEditedImageCount"], "1")
        XCTAssertEqual(event.metadata["exportedVariationImageCount"], "0")
        XCTAssertNil(event.metadata["prompt"])
        XCTAssertNil(event.metadata["revisedPrompt"])
        XCTAssertNil(event.metadata["imageData"])
        XCTAssertFalse(event.metadata.values.contains("Sensitive generated prompt"))
        XCTAssertFalse(event.metadata.values.contains("Sensitive revised prompt"))
        XCTAssertFalse(event.metadata.values.contains("Sensitive edit prompt"))
        XCTAssertFalse(event.metadata.values.contains(Data("sensitive-image-bytes".utf8).base64EncodedString()))
    }

    @MainActor
    func testExportGeneratedImagesForUserActionBlocksDisabledFeatureBeforeDataOrAuditEvent() async throws {
        let fixture = try ImageGenerationFixture(provider: FakeImageGenerationProvider())
        let store = fixture.makeStore()
        store.generatedImages = [
            AppGeneratedImage(
                prompt: "Generated prompt",
                modelID: "gpt-image-1",
                imageData: Data("generated-image".utf8),
                createdAt: Date(timeIntervalSince1970: 700)
            )
        ]
        await store.setFeatureToggle(.imageGeneration, isEnabled: false)

        do {
            _ = try await store.exportGeneratedImagesJSONDataForUserAction()
            XCTFail("Disabled Image Generation should block native generated-image export.")
        } catch {
            XCTAssertEqual(error.localizedDescription, "Image Generation is disabled.")
        }

        do {
            _ = try await store.exportGeneratedImagesOpenWebUIJSONDataForUserAction()
            XCTFail("Disabled Image Generation should block Open WebUI generated-image export.")
        } catch {
            XCTAssertEqual(error.localizedDescription, "Image Generation is disabled.")
        }

        XCTAssertEqual(store.imageGenerationError, "Image Generation is disabled.")
        XCTAssertEqual(store.errorMessage, "Image Generation is disabled.")
        XCTAssertFalse(store.auditEvents.contains { $0.action == .generatedImagesExported })
    }

    @MainActor
    func testExportGeneratedImagesForUserActionRequiresWritePermissionBeforeDataOrAuditEvent() async throws {
        let fixture = try ImageGenerationFixture(provider: FakeImageGenerationProvider())
        let store = fixture.makeStore()
        store.adminUsers = [
            AdminUser(id: "local-user", name: "Local User", email: "local@example.com", role: .user)
        ]
        store.generatedImages = [
            AppGeneratedImage(
                prompt: "Generated prompt",
                modelID: "gpt-image-1",
                imageData: Data("generated-image".utf8),
                createdAt: Date(timeIntervalSince1970: 700)
            )
        ]

        do {
            _ = try await store.exportGeneratedImagesJSONDataForUserAction()
            XCTFail("Missing image_generation.write should block native generated-image export.")
        } catch {
            XCTAssertEqual(error.localizedDescription, "You do not have permission to manage generated images.")
        }

        do {
            _ = try await store.exportGeneratedImagesOpenWebUIJSONDataForUserAction()
            XCTFail("Missing image_generation.write should block Open WebUI generated-image export.")
        } catch {
            XCTAssertEqual(error.localizedDescription, "You do not have permission to manage generated images.")
        }

        XCTAssertEqual(store.errorMessage, "You do not have permission to manage generated images.")
        XCTAssertFalse(store.auditEvents.contains { $0.action == .generatedImagesExported })
    }

    @MainActor
    func testImportGeneratedImagesJSONForUserActionCreatesAuditEventWithoutImageContent() async throws {
        let sourceFixture = try ImageGenerationFixture(provider: FakeImageGenerationProvider())
        let sourceStore = sourceFixture.makeStore()
        let source = AppGeneratedImage(
            prompt: "Imported source prompt",
            modelID: "gpt-image-1",
            imageData: Data("import-source-bytes".utf8),
            createdAt: Date(timeIntervalSince1970: 700)
        )
        let variation = AppGeneratedImage(
            prompt: "Imported variation prompt",
            modelID: "dall-e-2",
            imageData: Data("imported-variation-bytes".utf8),
            revisedPrompt: "Imported variation revised",
            sourceImageID: source.id,
            sourceOperation: "variation",
            createdAt: Date(timeIntervalSince1970: 800)
        )
        sourceStore.generatedImages = [variation, source]
        let data = try sourceStore.exportGeneratedImagesJSONData()

        let importFixture = try ImageGenerationFixture(provider: FakeImageGenerationProvider())
        let importStore = importFixture.makeStore()
        try await importStore.importGeneratedImagesJSONDataForUserAction(data)

        XCTAssertEqual(importStore.generatedImages.count, 2)
        XCTAssertEqual(importStore.generatedImages.first?.prompt, "Imported variation prompt")
        let event = try XCTUnwrap(importStore.auditEvents.first(where: { $0.action == .generatedImagesImported }))
        XCTAssertEqual(event.outcome, .succeeded)
        XCTAssertEqual(event.summary, "Imported generated images")
        XCTAssertEqual(event.metadata["importedGeneratedImageCount"], "2")
        XCTAssertEqual(event.metadata["importedOriginalImageCount"], "1")
        XCTAssertEqual(event.metadata["importedEditedImageCount"], "0")
        XCTAssertEqual(event.metadata["importedVariationImageCount"], "1")
        XCTAssertEqual(event.metadata["totalGeneratedImageCount"], "2")
        XCTAssertNil(event.metadata["prompt"])
        XCTAssertNil(event.metadata["revisedPrompt"])
        XCTAssertNil(event.metadata["imageData"])
        XCTAssertFalse(event.metadata.values.contains("Imported source prompt"))
        XCTAssertFalse(event.metadata.values.contains("Imported variation prompt"))
        XCTAssertFalse(event.metadata.values.contains("Imported variation revised"))
        XCTAssertFalse(event.metadata.values.contains(Data("imported-variation-bytes".utf8).base64EncodedString()))
    }

    @MainActor
    func testAuditMetadataFormatterPromotesGeneratedImageTransferRows() {
        let event = AppAuditEvent(
            action: .generatedImagesImported,
            outcome: .succeeded,
            summary: "Imported generated images",
            metadata: [
                "importedGeneratedImageCount": "4",
                "importedOriginalImageCount": "2",
                "importedEditedImageCount": "1",
                "importedVariationImageCount": "1",
                "totalGeneratedImageCount": "6"
            ]
        )

        let rows = AuditEventMetadataFormatter.rows(for: event)

        XCTAssertEqual(
            rows.map(\.label),
            ["Generated Images", "Originals", "Edits", "Variations", "Total Generated Images"]
        )
        XCTAssertEqual(rows.map(\.value), ["4", "2", "1", "1", "6"])
    }

    @MainActor
    func testImportGeneratedImagesJSONReplacesPersistedStaleImages() async throws {
        let sourceFixture = try ImageGenerationFixture(provider: FakeImageGenerationProvider())
        let sourceStore = sourceFixture.makeStore()
        let restored = AppGeneratedImage(
            prompt: "Restored image",
            modelID: "gpt-image-1",
            imageData: Data("restored".utf8),
            createdAt: Date(timeIntervalSince1970: 500)
        )
        sourceStore.generatedImages = [restored]
        let data = try sourceStore.exportGeneratedImagesJSONData()

        let destinationFixture = try ImageGenerationFixture(provider: FakeImageGenerationProvider())
        let stale = AppGeneratedImage(
            prompt: "Stale image",
            modelID: "gpt-image-1",
            imageData: Data("stale".utf8),
            createdAt: Date(timeIntervalSince1970: 100)
        )
        try await destinationFixture.generatedImageStorage.save(stale)
        let destinationStore = destinationFixture.makeStore()
        await destinationStore.load()

        try await destinationStore.importGeneratedImagesJSONData(data)

        let persistedImages = try await destinationFixture.generatedImageStorage.loadImages()
        XCTAssertEqual(destinationStore.generatedImages, [restored])
        XCTAssertEqual(persistedImages, [restored])
    }

    @MainActor
    func testEditGeneratedImagePersistsEditedResultForReload() async throws {
        let sourceImageData = Data("source-image".utf8)
        let editedImageData = Data("edited-image".utf8)
        let provider = FakeImageGenerationProvider(
            editResult: ImageGenerationResult(
                images: [GeneratedImage(data: editedImageData, revisedPrompt: "A calmer toolbar")],
                outputFormat: "png",
                size: "1024x1024",
                quality: "high"
            )
        )
        let fixture = try ImageGenerationFixture(provider: provider)
        let source = AppGeneratedImage(
            prompt: "Original app mockup",
            modelID: "gpt-image-1",
            imageData: sourceImageData,
            outputFormat: "png",
            size: "1024x1024",
            quality: "high",
            createdAt: Date(timeIntervalSince1970: 100)
        )
        try await fixture.generatedImageStorage.save(source)
        let store = fixture.makeStore()
        await store.load()
        store.models = [
            ProviderModel(id: "gpt-image-1", name: "gpt-image-1", provider: .openAICompatible, providerID: provider.configuration.id)
        ]
        store.imageGenerationModelID = "gpt-image-1"
        store.imageEditPrompt = "Make the toolbar calmer"
        store.setImageEditMask(data: Data("mask-image".utf8), fileName: "toolbar-mask.png", contentType: "image/png")

        await store.editGeneratedImage(source.id)

        let captured = await provider.capturedEditRequest
        XCTAssertEqual(captured?.model, "gpt-image-1")
        XCTAssertEqual(captured?.prompt, "Make the toolbar calmer")
        XCTAssertEqual(captured?.imageData, sourceImageData)
        XCTAssertEqual(captured?.imageContentType, "image/png")
        XCTAssertEqual(captured?.maskData, Data("mask-image".utf8))
        XCTAssertEqual(captured?.maskFileName, "toolbar-mask.png")
        XCTAssertEqual(captured?.maskContentType, "image/png")
        XCTAssertEqual(captured?.size, "1024x1024")
        XCTAssertEqual(captured?.quality, "high")
        XCTAssertEqual(captured?.count, 1)
        XCTAssertEqual(store.generatedImages.count, 2)
        XCTAssertEqual(store.generatedImages.first?.imageData, editedImageData)
        XCTAssertEqual(store.generatedImages.first?.prompt, "Make the toolbar calmer")
        XCTAssertEqual(store.generatedImages.first?.revisedPrompt, "A calmer toolbar")
        XCTAssertEqual(store.generatedImages.first?.sourceImageID, source.id)
        XCTAssertNil(store.imageEditMaskData)
        XCTAssertNil(store.imageEditMaskFileName)
        XCTAssertFalse(store.isEditingImage)
        XCTAssertNil(store.imageGenerationError)

        let reloadedStore = fixture.makeStore()
        await reloadedStore.load()

        XCTAssertEqual(reloadedStore.generatedImages.count, 2)
        XCTAssertEqual(reloadedStore.generatedImages.first?.imageData, editedImageData)
        XCTAssertEqual(reloadedStore.generatedImages.first?.sourceImageID, source.id)
    }

    @MainActor
    func testEditGeneratedImageSurfacesProviderError() async throws {
        let provider = FakeImageGenerationProvider(editErrorMessage: "Editing unavailable")
        let fixture = try ImageGenerationFixture(provider: provider)
        let source = AppGeneratedImage(
            prompt: "Original app mockup",
            modelID: "gpt-image-1",
            imageData: Data("source".utf8),
            createdAt: Date(timeIntervalSince1970: 100)
        )
        try await fixture.generatedImageStorage.save(source)
        let store = fixture.makeStore()
        await store.load()
        store.models = [
            ProviderModel(id: "gpt-image-1", name: "gpt-image-1", provider: .openAICompatible, providerID: provider.configuration.id)
        ]
        store.imageGenerationModelID = "gpt-image-1"
        store.imageEditPrompt = "Make it calmer"

        await store.editGeneratedImage(source.id)

        XCTAssertEqual(store.imageGenerationError, "Editing unavailable")
        XCTAssertEqual(store.errorMessage, "Editing unavailable")
        XCTAssertEqual(store.generatedImages, [source])
        XCTAssertFalse(store.isEditingImage)
    }

    @MainActor
    func testVaryGeneratedImagePersistsVariationResultForReload() async throws {
        let sourceImageData = Data("source-image".utf8)
        let variationImageData = Data("variation-image".utf8)
        let provider = FakeImageGenerationProvider(
            variationResult: ImageGenerationResult(
                images: [GeneratedImage(data: variationImageData, revisedPrompt: nil)],
                outputFormat: "png",
                size: "1024x1024",
                quality: nil
            )
        )
        let fixture = try ImageGenerationFixture(provider: provider)
        let source = AppGeneratedImage(
            prompt: "Original app mockup",
            modelID: "dall-e-2",
            imageData: sourceImageData,
            outputFormat: "png",
            size: "1024x1024",
            quality: nil,
            createdAt: Date(timeIntervalSince1970: 100)
        )
        try await fixture.generatedImageStorage.save(source)
        let store = fixture.makeStore()
        await store.load()
        store.models = [
            ProviderModel(id: "dall-e-2", name: "dall-e-2", provider: .openAICompatible, providerID: provider.configuration.id)
        ]
        store.imageGenerationModelID = "dall-e-2"
        store.imageGenerationSize = "1024x1024"
        store.imageGenerationCount = 1

        await store.varyGeneratedImage(source.id)

        let captured = await provider.capturedVariationRequest
        XCTAssertEqual(captured?.model, "dall-e-2")
        XCTAssertEqual(captured?.imageData, sourceImageData)
        XCTAssertEqual(captured?.imageFileName, "source.png")
        XCTAssertEqual(captured?.imageContentType, "image/png")
        XCTAssertEqual(captured?.size, "1024x1024")
        XCTAssertEqual(captured?.count, 1)
        XCTAssertEqual(store.generatedImages.count, 2)
        XCTAssertEqual(store.generatedImages.first?.imageData, variationImageData)
        XCTAssertEqual(store.generatedImages.first?.prompt, "Original app mockup")
        XCTAssertEqual(store.generatedImages.first?.sourceImageID, source.id)
        XCTAssertEqual(store.generatedImages.first?.sourceOperation, "variation")
        XCTAssertFalse(store.isVaryingImage)
        XCTAssertNil(store.imageGenerationError)

        let reloadedStore = fixture.makeStore()
        await reloadedStore.load()

        XCTAssertEqual(reloadedStore.generatedImages.count, 2)
        XCTAssertEqual(reloadedStore.generatedImages.first?.imageData, variationImageData)
        XCTAssertEqual(reloadedStore.generatedImages.first?.sourceOperation, "variation")
    }

    @MainActor
    func testVaryGeneratedImageBlocksNonDallE2ModelBeforeCallingProvider() async throws {
        let provider = FakeImageGenerationProvider()
        let fixture = try ImageGenerationFixture(provider: provider)
        let source = AppGeneratedImage(
            prompt: "Original app mockup",
            modelID: "gpt-image-1",
            imageData: Data("source".utf8),
            outputFormat: "png",
            size: "1024x1024",
            createdAt: Date(timeIntervalSince1970: 100)
        )
        try await fixture.generatedImageStorage.save(source)
        let store = fixture.makeStore()
        await store.load()
        store.models = [
            ProviderModel(id: "gpt-image-1", name: "gpt-image-1", provider: .openAICompatible, providerID: provider.configuration.id)
        ]
        store.imageGenerationModelID = "gpt-image-1"

        await store.varyGeneratedImage(source.id)

        XCTAssertEqual(store.imageGenerationError, "Image variations currently require the dall-e-2 model.")
        XCTAssertEqual(store.errorMessage, "Image variations currently require the dall-e-2 model.")
        XCTAssertEqual(store.generatedImages, [source])
        XCTAssertFalse(store.isVaryingImage)
        let captured = await provider.capturedVariationRequest
        XCTAssertNil(captured)
    }

    @MainActor
    func testGenerateImageSurfacesProviderError() async throws {
        let provider = FakeImageGenerationProvider(errorMessage: "Images unavailable")
        let fixture = try ImageGenerationFixture(provider: provider)
        let store = fixture.makeStore()
        store.models = [
            ProviderModel(id: "gpt-image-1", name: "gpt-image-1", provider: .openAICompatible, providerID: provider.configuration.id)
        ]
        store.imageGenerationModelID = "gpt-image-1"
        store.imageGenerationPrompt = "Native app icon"

        await store.generateImage()

        XCTAssertEqual(store.imageGenerationError, "Images unavailable")
        XCTAssertEqual(store.errorMessage, "Images unavailable")
        XCTAssertTrue(store.generatedImages.isEmpty)
        XCTAssertFalse(store.isGeneratingImage)
    }

    @MainActor
    func testGenerateImageBlocksUnsupportedActiveProviderBeforeCallingProvider() async throws {
        let provider = UnsupportedImageProvider()
        let fixture = try ImageGenerationFixture(provider: provider)
        let store = fixture.makeStore()
        store.models = [
            ProviderModel(id: "llama3.2", name: "llama3.2", provider: .ollama, providerID: ProviderConfiguration.defaultOllamaID)
        ]
        store.imageGenerationModelID = "llama3.2"
        store.imageGenerationPrompt = "Native app icon"

        await store.generateImage()

        XCTAssertEqual(store.imageGenerationError, "Ollama does not support native image generation.")
        XCTAssertEqual(store.errorMessage, "Ollama does not support native image generation.")
        XCTAssertTrue(store.generatedImages.isEmpty)
        XCTAssertFalse(store.isGeneratingImage)
        let callCount = await provider.generateImageCallCount
        XCTAssertEqual(callCount, 0)
    }

    @MainActor
    func testGenerateImageBlocksDisabledFeatureBeforeCallingProvider() async throws {
        let imageData = Data("image-bytes".utf8)
        let provider = FakeImageGenerationProvider(
            result: ImageGenerationResult(
                images: [GeneratedImage(data: imageData, revisedPrompt: nil)],
                outputFormat: "png",
                size: "1024x1024",
                quality: "high"
            )
        )
        let fixture = try ImageGenerationFixture(provider: provider)
        let store = fixture.makeStore()
        store.models = [
            ProviderModel(id: "gpt-image-1", name: "gpt-image-1", provider: .openAICompatible, providerID: provider.configuration.id)
        ]
        store.imageGenerationModelID = "gpt-image-1"
        store.imageGenerationPrompt = "Native app icon"
        await store.setFeatureToggle(.imageGeneration, isEnabled: false)

        await store.generateImage()

        XCTAssertEqual(store.imageGenerationError, "Image Generation is disabled.")
        XCTAssertEqual(store.errorMessage, "Image Generation is disabled.")
        XCTAssertTrue(store.generatedImages.isEmpty)
        XCTAssertFalse(store.isGeneratingImage)
        let captured = await provider.capturedRequest
        XCTAssertNil(captured)
    }

    @MainActor
    func testEditAndVaryGeneratedImageBlockDisabledFeatureBeforeCallingProvider() async throws {
        let provider = FakeImageGenerationProvider(
            editResult: ImageGenerationResult(
                images: [GeneratedImage(data: Data("edited".utf8), revisedPrompt: nil)],
                outputFormat: "png",
                size: "1024x1024",
                quality: "high"
            ),
            variationResult: ImageGenerationResult(
                images: [GeneratedImage(data: Data("variation".utf8), revisedPrompt: nil)],
                outputFormat: "png",
                size: "1024x1024",
                quality: nil
            )
        )
        let fixture = try ImageGenerationFixture(provider: provider)
        let source = AppGeneratedImage(
            prompt: "Original app mockup",
            modelID: "dall-e-2",
            imageData: Data("source".utf8),
            outputFormat: "png",
            size: "1024x1024",
            createdAt: Date(timeIntervalSince1970: 100)
        )
        try await fixture.generatedImageStorage.save(source)
        let store = fixture.makeStore()
        await store.load()
        store.models = [
            ProviderModel(id: "dall-e-2", name: "dall-e-2", provider: .openAICompatible, providerID: provider.configuration.id)
        ]
        store.imageGenerationModelID = "dall-e-2"
        store.imageEditPrompt = "Make it calmer"
        await store.setFeatureToggle(.imageGeneration, isEnabled: false)

        await store.editGeneratedImage(source.id)
        await store.varyGeneratedImage(source.id)

        XCTAssertEqual(store.imageGenerationError, "Image Generation is disabled.")
        XCTAssertEqual(store.errorMessage, "Image Generation is disabled.")
        XCTAssertEqual(store.generatedImages, [source])
        XCTAssertFalse(store.isEditingImage)
        XCTAssertFalse(store.isVaryingImage)
        let capturedEdit = await provider.capturedEditRequest
        let capturedVariation = await provider.capturedVariationRequest
        XCTAssertNil(capturedEdit)
        XCTAssertNil(capturedVariation)
    }

    @MainActor
    func testImportGeneratedImagesJSONIsBlockedWhenImageGenerationFeatureIsDisabled() async throws {
        let fixture = try ImageGenerationFixture(provider: FakeImageGenerationProvider())
        let store = fixture.makeStore()
        await store.load()
        await store.setFeatureToggle(.imageGeneration, isEnabled: false)
        let importedImage = AppGeneratedImage(
            prompt: "Imported image",
            modelID: "gpt-image-1",
            imageData: Data("imported".utf8),
            createdAt: Date(timeIntervalSince1970: 200)
        )
        let exportData = try GeneratedImageExportService().jsonData(for: [importedImage])

        try await store.importGeneratedImagesJSONData(exportData)
        await store.importGeneratedImagesJSON(from: fixture.rootURL.appendingPathComponent("missing-generated-images.json"))

        XCTAssertTrue(store.generatedImages.isEmpty)
        XCTAssertEqual(store.imageGenerationError, "Image Generation is disabled.")
        XCTAssertEqual(store.errorMessage, "Image Generation is disabled.")
        let persistedImages = try await fixture.generatedImageStorage.loadImages()
        XCTAssertTrue(persistedImages.isEmpty)
    }

    @MainActor
    func testImageGenerationPermissionsAllowGenerateEditAndImportForCurrentUser() async throws {
        let imageData = Data("image-bytes".utf8)
        let editedImageData = Data("edited-image".utf8)
        let provider = FakeImageGenerationProvider(
            result: ImageGenerationResult(
                images: [GeneratedImage(data: imageData, revisedPrompt: "A refined native icon")],
                outputFormat: "png",
                size: "1024x1024",
                quality: "high"
            ),
            editResult: ImageGenerationResult(
                images: [GeneratedImage(data: editedImageData, revisedPrompt: "A calmer toolbar")],
                outputFormat: "png",
                size: "1024x1024",
                quality: "high"
            )
        )
        let fixture = try ImageGenerationFixture(provider: provider)
        let store = fixture.makeStore()
        await store.load()
        store.adminUsers = [
            AdminUser(id: "local-user", name: "Local User", email: "local@example.com", role: .user)
        ]
        store.adminGroups = [
            AdminGroup(
                name: "Image Makers",
                description: "Can manage generated images.",
                permissions: ["image_generation.execute", "image_generation.write"],
                memberIDs: ["local-user"]
            )
        ]
        store.models = [
            ProviderModel(id: "gpt-image-1", name: "gpt-image-1", provider: .openAICompatible, providerID: provider.configuration.id)
        ]
        store.imageGenerationModelID = "gpt-image-1"
        store.imageGenerationPrompt = "Native app icon"

        await store.generateImage()

        XCTAssertEqual(store.generatedImages.count, 1)
        XCTAssertEqual(store.generatedImages.first?.imageData, imageData)
        let capturedRequest = await provider.capturedRequest
        XCTAssertNotNil(capturedRequest)

        let sourceID = try XCTUnwrap(store.generatedImages.first?.id)
        store.imageEditPrompt = "Make it calmer"

        await store.editGeneratedImage(sourceID)

        XCTAssertEqual(store.generatedImages.count, 2)
        XCTAssertEqual(store.generatedImages.first?.imageData, editedImageData)
        let capturedEditRequest = await provider.capturedEditRequest
        XCTAssertNotNil(capturedEditRequest)

        let exported = try store.exportGeneratedImagesJSONData()
        try await store.importGeneratedImagesJSONData(exported)

        XCTAssertEqual(store.generatedImages.count, 2)
        XCTAssertNil(store.errorMessage)
    }

    @MainActor
    func testImageGenerationPermissionsBlockGenerateEditAndImportForCurrentUser() async throws {
        let imageData = Data("image-bytes".utf8)
        let provider = FakeImageGenerationProvider(
            result: ImageGenerationResult(
                images: [GeneratedImage(data: imageData, revisedPrompt: "A refined native icon")],
                outputFormat: "png",
                size: "1024x1024",
                quality: "high"
            ),
            editResult: ImageGenerationResult(
                images: [GeneratedImage(data: Data("edited".utf8), revisedPrompt: "Edited")],
                outputFormat: "png",
                size: "1024x1024",
                quality: "high"
            )
        )
        let fixture = try ImageGenerationFixture(provider: provider)
        let existingImage = AppGeneratedImage(
            prompt: "Existing image",
            modelID: "gpt-image-1",
            imageData: Data("existing".utf8),
            outputFormat: "png",
            size: "1024x1024",
            quality: "high",
            createdAt: Date(timeIntervalSince1970: 100)
        )
        try await fixture.generatedImageStorage.save(existingImage)

        let store = fixture.makeStore()
        await store.load()
        store.adminUsers = [
            AdminUser(id: "local-user", name: "Local User", email: "local@example.com", role: .user)
        ]
        store.models = [
            ProviderModel(id: "gpt-image-1", name: "gpt-image-1", provider: .openAICompatible, providerID: provider.configuration.id)
        ]
        store.imageGenerationModelID = "gpt-image-1"
        store.imageGenerationPrompt = "Native app icon"

        await store.generateImage()

        XCTAssertEqual(store.generatedImages, [existingImage])
        XCTAssertEqual(store.imageGenerationError, "You do not have permission to generate images.")
        XCTAssertEqual(store.errorMessage, "You do not have permission to generate images.")
        let capturedRequest = await provider.capturedRequest
        XCTAssertNil(capturedRequest)

        store.imageEditPrompt = "Make it calmer"
        await store.editGeneratedImage(existingImage.id)

        XCTAssertEqual(store.generatedImages, [existingImage])
        XCTAssertEqual(store.imageGenerationError, "You do not have permission to generate images.")
        XCTAssertEqual(store.errorMessage, "You do not have permission to generate images.")
        let capturedEditRequest = await provider.capturedEditRequest
        XCTAssertNil(capturedEditRequest)

        let importedImage = AppGeneratedImage(
            prompt: "Imported image",
            modelID: "gpt-image-1",
            imageData: Data("imported".utf8),
            createdAt: Date(timeIntervalSince1970: 200)
        )
        let exportData = try GeneratedImageExportService().jsonData(for: [importedImage])
        try await store.importGeneratedImagesJSONData(exportData)

        let persistedImages = try await fixture.generatedImageStorage.loadImages()
        XCTAssertEqual(store.generatedImages, [existingImage])
        XCTAssertEqual(persistedImages, [existingImage])
        XCTAssertEqual(store.errorMessage, "You do not have permission to manage generated images.")
    }
}

private struct ImageGenerationFixture {
    let rootURL: URL
    let storage: JSONStorageService
    let generatedImageStorage: JSONGeneratedImageStorageService
    let auditStorage: JSONAuditLogStorageService
    let settingsStore: SettingsStore
    let adminStorage: JSONAdminDirectoryStorageService
    let provider: any ChatProvider

    init(provider: any ChatProvider) throws {
        rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        storage = JSONStorageService(rootURL: rootURL.appendingPathComponent("Chats", isDirectory: true))
        generatedImageStorage = JSONGeneratedImageStorageService(
            rootURL: rootURL.appendingPathComponent("GeneratedImages", isDirectory: true)
        )
        auditStorage = JSONAuditLogStorageService(rootURL: rootURL.appendingPathComponent("AuditLog", isDirectory: true))
        settingsStore = SettingsStore(settingsURL: rootURL.appendingPathComponent("settings.json"))
        adminStorage = JSONAdminDirectoryStorageService(
            snapshotURL: rootURL.appendingPathComponent("admin-directory.json")
        )
        self.provider = provider
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
    }

    @MainActor
    func makeStore() -> AppStore {
        AppStore(
            storage: storage,
            settingsStore: settingsStore,
            secretStore: InMemorySecretStore(),
            providerOverride: provider,
            generatedImageStorage: generatedImageStorage,
            auditLogStorage: auditStorage,
            adminDirectoryStorage: adminStorage
        )
    }
}

private actor FakeImageGenerationProvider: ChatProvider {
    nonisolated let configuration: ProviderConfiguration
    private let result: ImageGenerationResult
    private let editResult: ImageGenerationResult
    private let variationResult: ImageGenerationResult
    private let errorMessage: String?
    private let editErrorMessage: String?
    private let variationErrorMessage: String?
    private(set) var capturedRequest: ImageGenerationRequest?
    private(set) var capturedEditRequest: ImageEditRequest?
    private(set) var capturedVariationRequest: ImageVariationRequest?

    init(
        result: ImageGenerationResult = ImageGenerationResult(images: [], outputFormat: nil, size: nil, quality: nil),
        editResult: ImageGenerationResult = ImageGenerationResult(images: [], outputFormat: nil, size: nil, quality: nil),
        variationResult: ImageGenerationResult = ImageGenerationResult(images: [], outputFormat: nil, size: nil, quality: nil),
        errorMessage: String? = nil,
        editErrorMessage: String? = nil,
        variationErrorMessage: String? = nil
    ) {
        configuration = ProviderConfiguration(
            name: "Image Provider",
            kind: .openAICompatible,
            baseURL: "https://api.example/v1",
            apiKeySecretID: "secret"
        )
        self.result = result
        self.editResult = editResult
        self.variationResult = variationResult
        self.errorMessage = errorMessage
        self.editErrorMessage = editErrorMessage
        self.variationErrorMessage = variationErrorMessage
    }

    func listModels() async throws -> [ProviderModel] {
        [ProviderModel(id: "gpt-image-1", name: "gpt-image-1", provider: .openAICompatible, providerID: configuration.id)]
    }

    func healthCheck() async -> ProviderStatus {
        .available("Connected")
    }

    nonisolated func streamChat(model: String, messages: [ProviderChatMessage]) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish()
        }
    }

    func createEmbeddings(model: String, input: [String]) async throws -> [[Double]] {
        []
    }

    func generateImages(request: ImageGenerationRequest) async throws -> ImageGenerationResult {
        capturedRequest = request
        if let errorMessage {
            throw NSError(domain: "FakeImageGenerationProvider", code: 1, userInfo: [
                NSLocalizedDescriptionKey: errorMessage
            ])
        }
        return result
    }

    func editImage(request: ImageEditRequest) async throws -> ImageGenerationResult {
        capturedEditRequest = request
        if let editErrorMessage {
            throw NSError(domain: "FakeImageGenerationProvider", code: 2, userInfo: [
                NSLocalizedDescriptionKey: editErrorMessage
            ])
        }
        return editResult
    }

    func varyImage(request: ImageVariationRequest) async throws -> ImageGenerationResult {
        capturedVariationRequest = request
        if let variationErrorMessage {
            throw NSError(domain: "FakeImageGenerationProvider", code: 3, userInfo: [
                NSLocalizedDescriptionKey: variationErrorMessage
            ])
        }
        return variationResult
    }
}

private actor UnsupportedImageProvider: ChatProvider {
    nonisolated let configuration = ProviderConfiguration.defaultOllama()
    private(set) var generateImageCallCount = 0

    func listModels() async throws -> [ProviderModel] {
        [ProviderModel(id: "llama3.2", name: "llama3.2", provider: .ollama, providerID: configuration.id)]
    }

    func healthCheck() async -> ProviderStatus {
        .available("Connected")
    }

    nonisolated func streamChat(model: String, messages: [ProviderChatMessage]) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish()
        }
    }

    func createEmbeddings(model: String, input: [String]) async throws -> [[Double]] {
        []
    }

    func generateImages(request: ImageGenerationRequest) async throws -> ImageGenerationResult {
        generateImageCallCount += 1
        return ImageGenerationResult(images: [], outputFormat: nil, size: nil, quality: nil)
    }
}
