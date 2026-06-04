import SwiftUI

struct AudioSidebarView: View {
    @ObservedObject var store: AppStore

    var body: some View {
        Button {
            store.selectAudio()
        } label: {
            Label("Audio", systemImage: "waveform")
        }
        .buttonStyle(.plain)
        .disabled(!store.currentUserCanTranscribeAudio && !store.currentUserCanSynthesizeSpeech && !store.currentUserCanManageAudioHistory)
    }
}

struct AudioView: View {
    @ObservedObject var store: AppStore

    private let speechFormats = ["mp3", "wav", "opus", "flac"]
    private let commonVoices = ["alloy", "ash", "ballad", "coral", "echo", "fable", "nova", "onyx", "sage", "shimmer"]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.horizontal, 20)
                .padding(.vertical, 14)

            Divider()

            HSplitView {
                transcriptionPanel
                    .frame(minWidth: 340, idealWidth: 420, maxWidth: 520)

                speechPanel
                    .frame(minWidth: 420, maxWidth: .infinity)

                historyPanel
                    .frame(minWidth: 260, idealWidth: 300, maxWidth: 360)
            }
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Audio")
                    .font(.title2.weight(.semibold))
                Text(providerLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if let audioError = store.audioError {
                Label(audioError, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(2)
                    .multilineTextAlignment(.trailing)
            }
        }
    }

    private var transcriptionPanel: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                panelHeader("Transcription", systemImage: "waveform")

                if !store.canTranscribeAudio {
                    Label("\(store.activeProvider.name) does not support native audio transcription.", systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Button {
                            store.importAudioFileWithOpenPanel()
                        } label: {
                            Label("Import", systemImage: "square.and.arrow.down")
                        }
                        .disabled(!store.currentUserCanTranscribeAudio || store.isRecordingAudio)

                        Button {
                            Task {
                                await store.startAudioRecording()
                            }
                        } label: {
                            Label(store.isRecordingAudio ? "Recording" : "Record", systemImage: "record.circle")
                        }
                        .disabled(!canStartMicrophoneRecording)

                        Button {
                            Task {
                                await store.stopAudioRecording()
                            }
                        } label: {
                            Label("Stop", systemImage: "stop.circle")
                        }
                        .disabled(!store.isRecordingAudio)

                        Spacer()
                    }

                    Text(pendingAudioLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)

                    if let microphonePermissionLabel {
                        Label(microphonePermissionLabel, systemImage: "mic.slash")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                audioModelControl(
                    "Model",
                    selection: $store.audioTranscriptionModelID,
                    models: store.audioTranscriptionModels
                )
                labeledTextField("Language", text: $store.audioTranscriptionLanguage)

                VStack(alignment: .leading, spacing: 6) {
                    Text("Prompt")
                        .font(.headline)
                    TextEditor(text: $store.audioTranscriptionPrompt)
                        .font(.body)
                        .frame(minHeight: 90)
                        .overlay {
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.secondary.opacity(0.2))
                        }
                }

                HStack {
                    Button {
                        Task {
                            await store.transcribeAudio()
                        }
                    } label: {
                        Label(store.isTranscribingAudio ? "Transcribing" : "Transcribe", systemImage: "text.bubble")
                    }
                    .disabled(!store.currentUserCanTranscribeAudio || !store.canTranscribeAudio || store.isRecordingAudio || store.isTranscribingAudio || store.pendingAudioFileName == nil)

                    Button {
                        Task {
                            await store.runVoiceMode(synthesizeResponse: true)
                        }
                    } label: {
                        Label(store.isRunningVoiceMode ? "Voice Running" : "Voice Chat", systemImage: "mic.and.signal.meter")
                    }
                    .disabled(!store.canRunVoiceMode)

                    Button {
                        store.audioTranscriptText = ""
                        store.audioError = nil
                    } label: {
                        Label("Clear", systemImage: "xmark.circle")
                    }
                    .disabled(store.audioTranscriptText.isEmpty && store.audioError == nil)

                    Spacer()
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Transcript")
                        .font(.headline)
                    TextEditor(text: $store.audioTranscriptText)
                        .font(.body.monospaced())
                        .frame(minHeight: 220)
                        .overlay {
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.secondary.opacity(0.2))
                        }
                }

                Spacer(minLength: 0)
            }
            .padding(16)
        }
        .task {
            store.refreshAudioRecordingPermissionStatus()
        }
    }

    private var historyPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                panelHeader("History", systemImage: "clock.arrow.circlepath")

                Spacer()

                Button {
                    store.importAudioHistoryJSONWithOpenPanel()
                } label: {
                    Label("Import History", systemImage: "square.and.arrow.down")
                }
                .help("Import audio history JSON")
                .disabled(!store.currentUserCanManageAudioHistory)

                Button {
                    store.exportAudioHistoryJSONWithSavePanel()
                } label: {
                    Label("Export History", systemImage: "square.and.arrow.up")
                }
                .help("Export audio history JSON")
                .disabled(!store.currentUserCanManageAudioHistory || store.audioHistory.isEmpty)
            }
            .labelStyle(.iconOnly)

            if store.audioHistory.isEmpty {
                Text("No audio history")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            } else {
                List(selection: $store.selectedAudioHistoryItemID) {
                    ForEach(store.audioHistory) { item in
                        AudioHistoryRow(item: item)
                            .tag(item.id)
                            .contextMenu {
                                Button("Load") {
                                    store.loadAudioHistoryItem(item.id)
                                }
                                Button("Delete", role: .destructive) {
                                    Task {
                                        await store.deleteAudioHistoryItem(item.id)
                                    }
                                }
                                .disabled(!store.currentUserCanManageAudioHistory)
                            }
                    }
                }
                .onChange(of: store.selectedAudioHistoryItemID) { _, itemID in
                    if let itemID {
                        store.loadAudioHistoryItem(itemID)
                    }
                }

                HStack {
                    Button {
                        if let selectedAudioHistoryItemID = store.selectedAudioHistoryItemID {
                            store.loadAudioHistoryItem(selectedAudioHistoryItemID)
                        }
                    } label: {
                        Label("Load", systemImage: "arrow.down.doc")
                    }
                    .disabled(store.selectedAudioHistoryItemID == nil)

                    Button(role: .destructive) {
                        if let selectedAudioHistoryItemID = store.selectedAudioHistoryItemID {
                            Task {
                                await store.deleteAudioHistoryItem(selectedAudioHistoryItemID)
                            }
                        }
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                    .disabled(!store.currentUserCanManageAudioHistory || store.selectedAudioHistoryItemID == nil)

                    Button {
                        if let selectedAudioHistoryItemID = store.selectedAudioHistoryItemID {
                            store.playAudioHistoryItem(selectedAudioHistoryItemID)
                        }
                    } label: {
                        Label("Play", systemImage: "play.fill")
                    }
                    .disabled(selectedHistoryItem?.audioData == nil || store.audioPlaybackState == .playing)

                    Button {
                        store.stopAudioPlayback()
                    } label: {
                        Label("Stop", systemImage: "stop.fill")
                    }
                    .disabled(store.audioPlaybackState == .stopped)
                }
                .labelStyle(.iconOnly)
            }
        }
        .padding(16)
    }

    private var pendingAudioLabel: String {
        if store.isRecordingAudio {
            return "Recording microphone input..."
        }
        return store.pendingAudioFileName ?? "No file selected"
    }

    private var canStartMicrophoneRecording: Bool {
        store.currentUserCanTranscribeAudio
            && (store.audioRecordingPermissionStatus == .authorized || store.audioRecordingPermissionStatus == .notDetermined)
            && !store.isRecordingAudio
            && !store.isTranscribingAudio
            && !store.isRunningVoiceMode
    }

    private var microphonePermissionLabel: String? {
        switch store.audioRecordingPermissionStatus {
        case .notDetermined, .authorized:
            nil
        case .denied:
            "Microphone access denied"
        case .restricted:
            "Microphone access restricted"
        case .unknown:
            "Microphone permission unknown"
        }
    }

    private var speechPanel: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                panelHeader("Speech", systemImage: "speaker.wave.2")

                if !store.canSynthesizeSpeech {
                    Label("\(store.activeProvider.name) does not support native speech synthesis.", systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                HStack(alignment: .top, spacing: 12) {
                    audioModelControl(
                        "Model",
                        selection: $store.audioSpeechModelID,
                        models: store.audioSpeechModels
                    )

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Voice")
                            .font(.headline)
                        Picker("Voice", selection: $store.audioSpeechVoice) {
                            ForEach(commonVoices, id: \.self) { voice in
                                Text(voice).tag(voice)
                            }
                        }
                        .labelsHidden()
                    }
                    .frame(width: 150)

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Format")
                            .font(.headline)
                        Picker("Format", selection: $store.audioSpeechFormat) {
                            ForEach(speechFormats, id: \.self) { format in
                                Text(format).tag(format)
                            }
                        }
                        .labelsHidden()
                    }
                    .frame(width: 120)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Input")
                        .font(.headline)
                    TextEditor(text: $store.audioSpeechInput)
                        .font(.body)
                        .frame(minHeight: 180)
                        .overlay {
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.secondary.opacity(0.2))
                        }
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Instructions")
                        .font(.headline)
                    TextEditor(text: $store.audioSpeechInstructions)
                        .font(.body)
                        .frame(minHeight: 90)
                        .overlay {
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.secondary.opacity(0.2))
                        }
                }

                HStack {
                    Button {
                        Task {
                            await store.synthesizeSpeech()
                        }
                    } label: {
                        Label(store.isSynthesizingSpeech ? "Synthesizing" : "Synthesize", systemImage: "speaker.wave.2")
                    }
                    .disabled(!store.currentUserCanSynthesizeSpeech || !store.canSynthesizeSpeech || store.isSynthesizingSpeech || store.audioSpeechInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                    Button {
                        store.saveSynthesizedSpeechWithSavePanel()
                    } label: {
                        Label("Save", systemImage: "square.and.arrow.down")
                    }
                    .disabled(store.synthesizedSpeechData == nil)

                    Button {
                        store.playSynthesizedSpeech()
                    } label: {
                        Label("Play", systemImage: "play.fill")
                    }
                    .disabled(store.synthesizedSpeechData == nil || store.audioPlaybackState == .playing)

                    Button {
                        store.pauseAudioPlayback()
                    } label: {
                        Label("Pause", systemImage: "pause.fill")
                    }
                    .disabled(store.audioPlaybackState != .playing)

                    Button {
                        store.stopAudioPlayback()
                    } label: {
                        Label("Stop", systemImage: "stop.fill")
                    }
                    .disabled(store.audioPlaybackState == .stopped)

                    Spacer()

                    if let synthesizedSpeechData = store.synthesizedSpeechData {
                        Text(outputSummary(byteCount: synthesizedSpeechData.count))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(16)
        }
    }

	    private var providerLabel: String {
	        if let modelID = store.settings.selectedModelID {
	            return modelID
	        }
	        return "No model selected"
	    }

	    private var selectedHistoryItem: AppAudioHistoryItem? {
	        guard let selectedAudioHistoryItemID = store.selectedAudioHistoryItemID else {
	            return nil
	        }
	        return store.audioHistory.first { $0.id == selectedAudioHistoryItemID }
	    }

    private func panelHeader(_ title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .font(.title3.weight(.semibold))
    }

    private func labeledTextField(_ label: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.headline)
            TextField(label, text: text)
                .textFieldStyle(.roundedBorder)
        }
    }

    @ViewBuilder
    private func audioModelControl(
        _ label: String,
        selection: Binding<String>,
        models: [ProviderModel]
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.headline)
            if models.isEmpty {
                TextField(label, text: selection)
                    .textFieldStyle(.roundedBorder)
            } else {
                Picker(label, selection: selection) {
                    ForEach(models) { model in
                        Text(model.name).tag(model.id)
                    }
                }
                .labelsHidden()
            }
        }
    }

    private func outputSummary(byteCount: Int) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        let size = formatter.string(fromByteCount: Int64(byteCount))
        return [store.synthesizedSpeechFileName, size]
            .compactMap { $0 }
            .joined(separator: " - ")
    }
}

private struct AudioHistoryRow: View {
    var item: AppAudioHistoryItem

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(item.title, systemImage: iconName)
                .lineLimit(1)

            Text(item.kind.label)
                .font(.caption2)
                .foregroundStyle(.secondary)

            Text(item.text)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .padding(.vertical, 4)
    }

    private var iconName: String {
        switch item.kind {
        case .transcription:
            return "waveform"
        case .speech:
            return "speaker.wave.2"
        }
    }
}
