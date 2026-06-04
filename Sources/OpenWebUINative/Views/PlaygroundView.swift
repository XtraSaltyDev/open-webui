import SwiftUI
import AppKit

struct PlaygroundSidebarView: View {
    @ObservedObject var store: AppStore

    var body: some View {
        Button {
            store.selectPlayground()
        } label: {
            Label("Chat Playground", systemImage: "slider.horizontal.3")
        }
        .buttonStyle(.plain)
        .disabled(!store.currentUserCanUsePlayground && !store.currentUserCanManagePlaygroundHistory)
    }
}

struct PlaygroundView: View {
    @ObservedObject var store: AppStore

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.horizontal, 20)
                .padding(.vertical, 14)

            Divider()

            HSplitView {
                controls
                    .frame(minWidth: 320, idealWidth: 380, maxWidth: 460)

                output
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Playground")
                    .font(.title2.weight(.semibold))
                Text("Run temporary prompts without saving a chat thread")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                Task {
                    await store.runPlayground()
                }
            } label: {
                Label(store.isRunningPlayground ? "Running" : "Run", systemImage: "play.fill")
            }
            .disabled(!canRunPlayground)
        }
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 14) {
            Picker("Mode", selection: $store.playgroundMode) {
                ForEach(PlaygroundMode.allCases) { mode in
                    Text(playgroundModeLabel(mode)).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            if store.playgroundMode == .chat {
                chatControls
            } else if store.playgroundMode == .completions {
                completionControls
            } else if store.playgroundMode == .notes {
                noteControls
            } else {
                imageControls
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(store.playgroundMode == .notes ? "Body" : "Prompt")
                    .font(.headline)
                TextEditor(text: $store.playgroundPrompt)
                    .font(.body.monospaced())
                    .frame(minHeight: 160)
                    .overlay {
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.secondary.opacity(0.2))
                    }
            }

            HStack {
                Button {
                    Task {
                        await store.runPlayground()
                    }
                } label: {
                    if store.playgroundMode == .notes {
                        Label("Save Note", systemImage: "note.text")
                    } else {
                        Label("Run", systemImage: "play.fill")
                    }
                }
                .disabled(!canRunPlayground)

                Button {
                    store.playgroundOutput = ""
                    store.playgroundError = nil
                    store.playgroundComparisonOutput = ""
                    store.playgroundComparisonError = nil
                    store.playgroundImageOutputs = []
                } label: {
                    Label("Clear", systemImage: "xmark.circle")
                }
                .disabled(
                    store.isRunningPlayground
                        && store.playgroundOutput.isEmpty
                        && store.playgroundComparisonOutput.isEmpty
                        && store.playgroundImageOutputs.isEmpty
                )

                Button {
                    Task {
                        await store.saveCurrentPlaygroundRun()
                    }
                } label: {
                    Label("Save", systemImage: "tray.and.arrow.down")
                }
                .disabled(
                    !store.currentUserCanManagePlaygroundHistory
                        || store.playgroundPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        || store.playgroundOutput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                )

                Spacer()
            }

            historyControls

            Spacer()
        }
        .padding(16)
    }

    private var chatControls: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Model")
                    .font(.headline)
                if !store.canChat {
                    Label("\(store.activeProvider.name) does not support native chat.", systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Picker("Model", selection: playgroundModelBinding) {
                    ForEach(store.models) { model in
                        Text(model.name).tag(model.id)
                    }
                }
                .labelsHidden()
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            VStack(alignment: .leading, spacing: 6) {
                Toggle("Compare Models", isOn: $store.isPlaygroundComparisonEnabled)
                    .font(.headline)

                if store.isPlaygroundComparisonEnabled {
                    Picker("Comparison Model", selection: playgroundComparisonModelBinding) {
                        ForEach(store.models) { model in
                            Text(model.name).tag(model.id)
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            parameterControls

            VStack(alignment: .leading, spacing: 6) {
                Text("System")
                    .font(.headline)
                TextEditor(text: $store.playgroundSystemPrompt)
                    .font(.body.monospaced())
                    .frame(minHeight: 90)
                    .overlay {
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.secondary.opacity(0.2))
                    }
            }
        }
    }

    private var imageControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Image Model")
                    .font(.headline)
                if !store.canGenerateImages {
                    Label("\(store.activeProvider.name) does not support native image generation.", systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Picker("Image Model", selection: playgroundImageModelBinding) {
                    ForEach(store.models) { model in
                        Text(model.name).tag(model.id)
                    }
                }
                .labelsHidden()
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Picker("Size", selection: $store.playgroundImageSize) {
                Text("1024 x 1024").tag("1024x1024")
                Text("512 x 512").tag("512x512")
                Text("256 x 256").tag("256x256")
            }

            Picker("Quality", selection: $store.playgroundImageQuality) {
                Text("High").tag("high")
                Text("Standard").tag("standard")
            }

            Stepper("Images: \(store.playgroundImageCount)", value: $store.playgroundImageCount, in: 1...4)
        }
    }

    private var noteControls: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Note")
                    .font(.headline)
                if !store.currentUserCanManageNotes {
                    Label("You do not have permission to manage notes.", systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Picker("Note", selection: playgroundNoteBinding) {
                    Text("New Note").tag(Optional<UUID>.none)
                    ForEach(store.notes) { note in
                        Text(note.title).tag(Optional(note.id))
                    }
                }
                .labelsHidden()
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Title")
                    .font(.headline)
                TextField("Note title", text: $store.playgroundNoteTitle)
            }
        }
    }

    private var completionControls: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Model")
                    .font(.headline)
                if !store.canComplete {
                    Label("\(store.activeProvider.name) does not support native completions.", systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Picker("Model", selection: playgroundModelBinding) {
                    ForEach(store.models) { model in
                        Text(model.name).tag(model.id)
                    }
                }
                .labelsHidden()
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            parameterControls
        }
    }

    private var canRunPlayground: Bool {
        guard store.currentUserCanUsePlayground,
              !store.isRunningPlayground,
              !store.playgroundPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return false
        }
        switch store.playgroundMode {
        case .chat:
            return store.canChat
        case .completions:
            return store.canComplete
        case .notes:
            return store.currentUserCanManageNotes
        case .images:
            return store.canGenerateImages
        }
    }

    private func playgroundModeLabel(_ mode: PlaygroundMode) -> String {
        switch mode {
        case .chat:
            return "Chat"
        case .completions:
            return "Completions"
        case .notes:
            return "Notes"
        case .images:
            return "Images"
        }
    }

    private var historyControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("History")
                .font(.headline)

            if store.playgroundHistory.isEmpty {
                Text("No saved runs")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(store.playgroundHistory) { item in
                            HStack(spacing: 6) {
                                Button {
                                    store.loadPlaygroundHistoryItem(item.id)
                                } label: {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(item.title)
                                            .lineLimit(1)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                        Text("\(item.modelID) - \(item.updatedAt.formatted(date: .abbreviated, time: .shortened))")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                    }
                                }
                                .buttonStyle(.plain)

                                Button {
                                    store.sharePlaygroundHistoryItem(item.id)
                                } label: {
                                    Image(systemName: "square.and.arrow.up")
                                }
                                .buttonStyle(.borderless)
                                .help("Share saved playground run")

                                Button {
                                    Task {
                                        await store.deletePlaygroundHistoryItem(item.id)
                                    }
                                } label: {
                                    Image(systemName: "trash")
                                }
                                .buttonStyle(.borderless)
                                .help("Delete saved playground run")
                                .disabled(!store.currentUserCanManagePlaygroundHistory)
                            }
                            .padding(.vertical, 4)
                            .padding(.horizontal, 6)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(item.id == store.selectedPlaygroundHistoryID ? Color.accentColor.opacity(0.12) : Color.clear)
                            )
                        }
                    }
                }
                .frame(maxHeight: 150)
            }
        }
    }

    private var parameterControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Parameters")
                    .font(.headline)
                Spacer()
                Button {
                    store.playgroundTemperature = 0.7
                    store.playgroundTopP = 0.9
                    store.playgroundMaxTokens = 512
                } label: {
                    Label("Reset", systemImage: "arrow.counterclockwise")
                }
                .controlSize(.small)
            }

            parameterSlider(
                title: "Temperature",
                value: $store.playgroundTemperature,
                range: 0...2,
                step: 0.1
            )

            parameterSlider(
                title: "Top P",
                value: $store.playgroundTopP,
                range: 0...1,
                step: 0.05
            )

            HStack {
                Text("Max Tokens")
                Spacer()
                Stepper(value: $store.playgroundMaxTokens, in: 1...32_768, step: 64) {
                    Text("\(store.playgroundMaxTokens)")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .frame(width: 64, alignment: .trailing)
                }
            }
            .font(.callout)
        }
        .padding(.vertical, 4)
    }

    private func parameterSlider(
        title: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        step: Double
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                Spacer()
                Text(String(format: "%.2g", value.wrappedValue))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            Slider(value: value, in: range, step: step)
        }
        .font(.callout)
    }

    private var output: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center) {
                Text("Output")
                    .font(.headline)
                Spacer()
                if store.isRunningPlayground {
                    ProgressView()
                        .controlSize(.small)
                }
                Button {
                    store.shareCurrentPlaygroundRun()
                } label: {
                    Label("Share", systemImage: "square.and.arrow.up")
                }
                .help("Share playground JSON")
                .disabled(store.playgroundOutput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                Button {
                    store.exportPlaygroundJSONWithSavePanel()
                } label: {
                    Label("Export JSON", systemImage: "doc.badge.arrow.up")
                }
                .help("Export playground JSON")
                .disabled(store.playgroundOutput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                Button {
                    store.exportPlaygroundTextWithSavePanel()
                } label: {
                    Label("Export Text", systemImage: "doc.plaintext")
                }
                .help("Export playground text")
                .disabled(store.playgroundOutput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            if store.playgroundOutput.isEmpty
                && store.playgroundComparisonOutput.isEmpty
                && store.playgroundError == nil
                && store.playgroundComparisonError == nil {
                ContentUnavailableView(
                    "No Output",
                    systemImage: "slider.horizontal.3",
                    description: Text("Run a playground prompt to stream a temporary response.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if store.playgroundMode == .images {
                imageOutputPane
            } else if store.playgroundMode == .notes {
                outputPane(
                    title: store.playgroundNoteTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        ? "Note"
                        : store.playgroundNoteTitle,
                    output: store.playgroundOutput,
                    error: store.playgroundError
                )
            } else if store.isPlaygroundComparisonEnabled {
                HStack(alignment: .top, spacing: 12) {
                    outputPane(
                        title: modelName(for: store.playgroundModelID ?? store.selectedModelID),
                        output: store.playgroundOutput,
                        error: store.playgroundError
                    )

                    outputPane(
                        title: modelName(for: store.playgroundComparisonModelID),
                        output: store.playgroundComparisonOutput,
                        error: store.playgroundComparisonError
                    )
                }
            } else {
                outputPane(
                    title: modelName(for: store.playgroundModelID ?? store.selectedModelID),
                    output: store.playgroundOutput,
                    error: store.playgroundError
                )
            }
        }
        .padding(20)
    }

    private var imageOutputPane: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let error = store.playgroundError {
                Label(error, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
                    .font(.callout)
            }

            Text(modelName(for: store.playgroundImageModelID ?? store.imageGenerationModelID ?? store.selectedModelID))
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: 12)], spacing: 12) {
                    ForEach(Array(store.playgroundImageOutputs.enumerated()), id: \.offset) { _, imageOutput in
                        VStack(alignment: .leading, spacing: 6) {
                            if let image = NSImage(data: imageOutput.imageData) {
                                Image(nsImage: image)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(maxWidth: .infinity)
                                    .background(Color.secondary.opacity(0.08))
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                            } else {
                                Label("Image data unavailable", systemImage: "photo")
                                    .frame(maxWidth: .infinity, minHeight: 120)
                                    .background(Color.secondary.opacity(0.08))
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                            }

                            if let revisedPrompt = imageOutput.revisedPrompt {
                                Text(revisedPrompt)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(3)
                            }

                            HStack {
                                if let size = imageOutput.size {
                                    Text(size)
                                }
                                if let format = imageOutput.outputFormat {
                                    Text(format.uppercased())
                                }
                            }
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(12)
            }
            .background(Color.secondary.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func outputPane(title: String, output: String, error: String?) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            if let error {
                Label(error, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
                    .font(.callout)
            }

            ScrollView {
                Text(output)
                    .font(.body.monospaced())
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
            }
            .background(Color.secondary.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func modelName(for modelID: String?) -> String {
        guard let modelID else {
            return "Model"
        }
        return store.models.first { $0.id == modelID }?.name ?? modelID
    }

    private var playgroundModelBinding: Binding<String> {
        Binding(
            get: {
                store.playgroundModelID ?? store.selectedModelID ?? store.models.first?.id ?? ""
            },
            set: { modelID in
                store.playgroundModelID = modelID.isEmpty ? nil : modelID
            }
        )
    }

    private var playgroundComparisonModelBinding: Binding<String> {
        Binding(
            get: {
                store.playgroundComparisonModelID
                    ?? store.models.first { $0.id != playgroundModelBinding.wrappedValue }?.id
                    ?? ""
            },
            set: { modelID in
                store.playgroundComparisonModelID = modelID.isEmpty ? nil : modelID
            }
        )
    }

    private var playgroundImageModelBinding: Binding<String> {
        Binding(
            get: {
                store.playgroundImageModelID
                    ?? store.imageGenerationModelID
                    ?? store.selectedModelID
                    ?? store.models.first?.id
                    ?? ""
            },
            set: { modelID in
                store.playgroundImageModelID = modelID.isEmpty ? nil : modelID
            }
        )
    }

    private var playgroundNoteBinding: Binding<UUID?> {
        Binding(
            get: {
                store.selectedPlaygroundNoteID
            },
            set: { noteID in
                store.selectedPlaygroundNoteID = noteID
                guard let noteID,
                      let note = store.notes.first(where: { $0.id == noteID }) else {
                    store.playgroundNoteTitle = ""
                    return
                }
                store.playgroundNoteTitle = note.title
                store.playgroundPrompt = note.content
            }
        )
    }
}
