import SwiftUI
import UniformTypeIdentifiers

struct ImageGenerationSidebarView: View {
    @ObservedObject var store: AppStore

    var body: some View {
        Button {
            store.selectImageGeneration()
        } label: {
            Label("Image Generation", systemImage: "photo")
        }
        .buttonStyle(.plain)
        .disabled(!store.currentUserCanGenerateImages && !store.currentUserCanManageGeneratedImages)
    }
}

struct ImageGenerationView: View {
    @ObservedObject var store: AppStore

    private let sizes = ["1024x1024", "1024x1536", "1536x1024"]
    private let qualities = ["low", "medium", "high"]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.horizontal, 20)
                .padding(.vertical, 14)

            Divider()

            HSplitView {
                controls
                    .frame(minWidth: 320, idealWidth: 380, maxWidth: 460)

                gallery
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Image Generation")
                    .font(.title2.weight(.semibold))
                Text(imageGenerationStatusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                store.importGeneratedImagesJSONWithOpenPanel()
            } label: {
                Label("Import", systemImage: "square.and.arrow.down")
            }
            .disabled(!store.currentUserCanManageGeneratedImages)

            Menu {
                Button("Native JSON") {
                    store.exportGeneratedImagesJSONWithSavePanel()
                }

                Button("Open WebUI JSON") {
                    store.exportGeneratedImagesOpenWebUIJSONWithSavePanel()
                }
            } label: {
                Label("Export", systemImage: "square.and.arrow.up")
            }
            .disabled(store.generatedImages.isEmpty)

            Button {
                Task {
                    await store.generateImage()
                }
            } label: {
                Label(store.isGeneratingImage ? "Generating" : "Generate", systemImage: "sparkles")
            }
            .disabled(!store.currentUserCanGenerateImages || !store.canGenerateImages || store.isGeneratingImage || store.imageGenerationPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Model")
                    .font(.headline)
                if !store.canGenerateImages {
                    Label("\(store.activeProvider.name) does not support native image generation.", systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Picker("Model", selection: imageModelBinding) {
                    ForEach(store.models) { model in
                        Text(model.name).tag(Optional(model.id))
                    }
                }
                .labelsHidden()
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Prompt")
                    .font(.headline)
                TextEditor(text: $store.imageGenerationPrompt)
                    .font(.body.monospaced())
                    .frame(minHeight: 180)
                    .overlay {
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.secondary.opacity(0.2))
                    }
            }

            Picker("Size", selection: $store.imageGenerationSize) {
                ForEach(sizes, id: \.self) { size in
                    Text(size).tag(size)
                }
            }

            Picker("Quality", selection: $store.imageGenerationQuality) {
                ForEach(qualities, id: \.self) { quality in
                    Text(quality.capitalized).tag(quality)
                }
            }

            Stepper("Images: \(store.imageGenerationCount)", value: $store.imageGenerationCount, in: 1...4)

            HStack {
                Button {
                    Task {
                        await store.generateImage()
                    }
                } label: {
                    Label("Generate", systemImage: "sparkles")
                }
                .disabled(!store.currentUserCanGenerateImages || !store.canGenerateImages || store.isGeneratingImage || store.imageGenerationPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                Button {
                    store.imageGenerationPrompt = ""
                    store.imageGenerationError = nil
                } label: {
                    Label("Clear", systemImage: "xmark.circle")
                }
                .disabled(store.imageGenerationPrompt.isEmpty && store.imageGenerationError == nil)

                Spacer()
            }

            if let error = store.imageGenerationError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            Spacer()
        }
        .padding(16)
    }

    private var gallery: some View {
        ScrollView {
            if store.generatedImages.isEmpty {
                ContentUnavailableView(
                    "No Images",
                    systemImage: "photo.on.rectangle.angled",
                    description: Text("Generate an image from the active provider to see it here.")
                )
                .frame(maxWidth: .infinity, minHeight: 360)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 240), spacing: 14)], spacing: 14) {
                    ForEach(store.generatedImages) { image in
                        GeneratedImageCard(store: store, image: image)
                    }
                }
                .padding(20)
            }
        }
    }

    private var imageModelBinding: Binding<String?> {
        Binding(
            get: { store.imageGenerationModelID ?? store.settings.selectedModelID ?? store.models.first?.id },
            set: { store.imageGenerationModelID = $0 }
        )
    }

    private var imageGenerationStatusText: String {
        if store.canGenerateImages {
            return "\(store.generatedImages.count) generated images"
        }
        return "\(store.activeProvider.name) image generation unavailable"
    }
}

private struct GeneratedImageCard: View {
    @ObservedObject var store: AppStore
    var image: AppGeneratedImage
    @State private var isImportingMask = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let nsImage = NSImage(data: image.imageData) {
                Image(nsImage: nsImage)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity)
                    .background(Color.secondary.opacity(0.04))
                    .clipShape(RoundedRectangle(cornerRadius: 7))
            } else {
                ContentUnavailableView("Image data unavailable", systemImage: "photo")
                    .frame(minHeight: 180)
                    .background(Color.secondary.opacity(0.04))
                    .clipShape(RoundedRectangle(cornerRadius: 7))
            }

            Text(image.prompt)
                .font(.caption.weight(.medium))
                .lineLimit(2)

            if let revisedPrompt = image.revisedPrompt, revisedPrompt != image.prompt {
                Text(revisedPrompt)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            HStack {
                Text(image.modelID)
                Spacer()
                if let size = image.size {
                    Text(size)
                }
            }
            .font(.caption2)
            .foregroundStyle(.secondary)

            if image.sourceImageID != nil {
                Label(sourceOperationLabel, systemImage: sourceOperationIcon)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Divider()

            if store.selectedImageForEditingID == image.id {
                TextField("Edit prompt", text: $store.imageEditPrompt, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(2...4)

                HStack(spacing: 8) {
                    Button {
                        isImportingMask = true
                    } label: {
                        Label(store.imageEditMaskFileName == nil ? "Mask" : "Replace Mask", systemImage: "paintbrush.pointed")
                    }
                    .disabled(store.isEditingImage)

                    if let maskFileName = store.imageEditMaskFileName {
                        Label(maskFileName, systemImage: "photo.badge.checkmark")
                            .font(.caption)
                            .lineLimit(1)
                            .truncationMode(.middle)

                        Button {
                            store.clearImageEditMask()
                        } label: {
                            Label("Clear Mask", systemImage: "xmark.circle")
                        }
                        .labelStyle(.iconOnly)
                        .disabled(store.isEditingImage)
                    }

                    Spacer()
                }

                HStack {
                    Button {
                        Task {
                            await store.editGeneratedImage(image.id)
                        }
                    } label: {
                        Label(store.isEditingImage ? "Editing" : "Edit", systemImage: "wand.and.stars")
                    }
                    .disabled(!store.currentUserCanGenerateImages || !store.canEditImages || store.isEditingImage || store.imageEditPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                    Button {
                        store.selectedImageForEditingID = nil
                        store.imageEditPrompt = ""
                        store.clearImageEditMask()
                    } label: {
                        Label("Cancel", systemImage: "xmark.circle")
                    }
                    .disabled(store.isEditingImage)

                    Spacer()
                }
            } else {
                HStack {
                    Button {
                        store.selectImageForEditing(image.id)
                    } label: {
                        Label("Edit", systemImage: "wand.and.stars")
                    }
                    .disabled(!store.currentUserCanGenerateImages || !store.canEditImages || store.isEditingImage)

                    Button {
                        Task {
                            await store.varyGeneratedImage(image.id)
                        }
                    } label: {
                        Label(store.isVaryingImage ? "Varying" : "Vary", systemImage: "photo.on.rectangle.angled")
                    }
                    .disabled(!store.currentUserCanGenerateImages || !store.canVaryImages || store.isVaryingImage)

                    Spacer()
                }
            }
        }
        .fileImporter(isPresented: $isImportingMask, allowedContentTypes: [.png, .image]) { result in
            switch result {
            case let .success(url):
                Task {
                    await store.importImageEditMask(from: url)
                }
            case let .failure(error):
                store.imageGenerationError = error.localizedDescription
            }
        }
        .padding(10)
        .background(Color.secondary.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 7))
    }

    private var sourceOperationLabel: String {
        image.sourceOperation == "variation" ? "Variation" : "Edited"
    }

    private var sourceOperationIcon: String {
        image.sourceOperation == "variation" ? "photo.on.rectangle.angled" : "wand.and.stars"
    }
}
