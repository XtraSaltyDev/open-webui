import Foundation
import XCTest
@testable import OpenWebUINative

final class AppStoreAudioTests: XCTestCase {
    @MainActor
    func testSelectAudioClearsOtherDetailSelections() throws {
        let fixture = try AudioFixture(provider: FakeAudioProvider())
        let store = fixture.makeStore()
        store.selectedThreadID = UUID()
        store.selectedChannelID = UUID()
        store.isShowingEvaluationDashboard = true
        store.isShowingAnalyticsDashboard = true
        store.isShowingPlayground = true
        store.isShowingImageGeneration = true
        store.isShowingCalendar = true

        store.selectAudio()

        XCTAssertNil(store.selectedThreadID)
        XCTAssertNil(store.selectedChannelID)
        XCTAssertFalse(store.isShowingEvaluationDashboard)
        XCTAssertFalse(store.isShowingAnalyticsDashboard)
        XCTAssertFalse(store.isShowingPlayground)
        XCTAssertFalse(store.isShowingImageGeneration)
        XCTAssertFalse(store.isShowingCalendar)
        XCTAssertTrue(store.isShowingAudio)
    }

    @MainActor
    func testTranscribeAudioRoutesFileToProviderAndStoresTranscript() async throws {
        let provider = FakeAudioProvider(transcriptionText: "Native audio is working.")
        let fixture = try AudioFixture(provider: provider)
        let store = fixture.makeStore()
        await store.load()
        store.audioTranscriptionModelID = "gpt-4o-mini-transcribe"
        store.audioTranscriptionPrompt = "Product planning terms."
        store.audioTranscriptionLanguage = "en"
        store.setPendingAudioFile(
            data: Data("audio-bytes".utf8),
            fileName: "meeting.wav",
            contentType: "audio/wav"
        )

        await store.transcribeAudio()

        let captured = await provider.capturedTranscriptionRequest
        XCTAssertEqual(captured?.model, "gpt-4o-mini-transcribe")
        XCTAssertEqual(captured?.audioData, Data("audio-bytes".utf8))
        XCTAssertEqual(captured?.fileName, "meeting.wav")
        XCTAssertEqual(captured?.contentType, "audio/wav")
        XCTAssertEqual(captured?.prompt, "Product planning terms.")
        XCTAssertEqual(captured?.language, "en")
        XCTAssertEqual(store.audioTranscriptText, "Native audio is working.")
        XCTAssertFalse(store.isTranscribingAudio)
        XCTAssertNil(store.audioError)

        let item = try XCTUnwrap(store.audioHistory.first)
        XCTAssertEqual(item.kind, .transcription)
        XCTAssertEqual(item.title, "meeting.wav")
        XCTAssertEqual(item.text, "Native audio is working.")
        XCTAssertEqual(item.modelID, "gpt-4o-mini-transcribe")
        XCTAssertEqual(item.sourceFileName, "meeting.wav")

        let reloaded = try await fixture.audioHistoryStorage.loadHistory()
        XCTAssertEqual(reloaded.first?.text, "Native audio is working.")
    }

    @MainActor
    func testTranscribeAudioBlocksDisabledFeatureBeforeCallingProvider() async throws {
        let provider = FakeAudioProvider(transcriptionText: "Should not transcribe.")
        let fixture = try AudioFixture(provider: provider)
        let store = fixture.makeStore()
        await store.load()
        await store.setFeatureToggle(.audio, isEnabled: false)
        store.setPendingAudioFile(
            data: Data("audio-bytes".utf8),
            fileName: "meeting.wav",
            contentType: "audio/wav"
        )

        await store.transcribeAudio()

        XCTAssertEqual(store.audioError, "Audio is disabled.")
        XCTAssertEqual(store.errorMessage, "Audio is disabled.")
        XCTAssertTrue(store.audioTranscriptText.isEmpty)
        XCTAssertFalse(store.isTranscribingAudio)
        let captured = await provider.capturedTranscriptionRequest
        XCTAssertNil(captured)
        XCTAssertTrue(store.audioHistory.isEmpty)
        let reloaded = try await fixture.audioHistoryStorage.loadHistory()
        XCTAssertTrue(reloaded.isEmpty)
    }

    @MainActor
    func testAudioImportsBlockDisabledFeatureBeforeFileOrHistoryChanges() async throws {
        let fixture = try AudioFixture(provider: FakeAudioProvider())
        let store = fixture.makeStore()
        await store.load()
        await store.setFeatureToggle(.audio, isEnabled: false)
        let audioURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("wav")
        try Data("audio-bytes".utf8).write(to: audioURL)
        let importedItem = AppAudioHistoryItem(
            kind: .transcription,
            title: "imported.wav",
            text: "Imported transcript.",
            modelID: "gpt-4o-mini-transcribe",
            sourceFileName: "imported.wav",
            sourceContentType: "audio/wav",
            createdAt: Date(timeIntervalSince1970: 200)
        )
        let exportData = try AudioHistoryExportService().jsonData(for: [importedItem])

        await store.importAudioFile(from: audioURL)
        try await store.importAudioHistoryJSONData(exportData)
        await store.importAudioHistoryJSON(from: FileManager.default.temporaryDirectory.appendingPathComponent("missing-audio-history.json"))

        XCTAssertNil(store.pendingAudioFileName)
        XCTAssertNil(store.pendingAudioContentType)
        XCTAssertTrue(store.audioHistory.isEmpty)
        XCTAssertEqual(store.audioError, "Audio is disabled.")
        XCTAssertEqual(store.errorMessage, "Audio is disabled.")
        let reloaded = try await fixture.audioHistoryStorage.loadHistory()
        XCTAssertTrue(reloaded.isEmpty)
    }

    @MainActor
    func testRecordingAudioStoresRecordedFileForTranscription() async throws {
        let provider = FakeAudioProvider(transcriptionText: "Recorded transcript.")
        let audioRecorder = CapturingAudioRecorder(
            recording: RecordedAudio(
                data: Data("recorded-audio-bytes".utf8),
                fileName: "voice-recording.m4a",
                contentType: "audio/mp4"
            )
        )
        let fixture = try AudioFixture(provider: provider, audioRecorder: audioRecorder)
        let store = fixture.makeStore()
        await store.load()

        await store.startAudioRecording()

        XCTAssertTrue(store.isRecordingAudio)
        XCTAssertEqual(audioRecorder.startCallCount, 1)
        XCTAssertNil(store.audioError)

        await store.stopAudioRecording()

        XCTAssertFalse(store.isRecordingAudio)
        XCTAssertEqual(audioRecorder.stopCallCount, 1)
        XCTAssertEqual(store.pendingAudioFileName, "voice-recording.m4a")
        XCTAssertEqual(store.pendingAudioContentType, "audio/mp4")

        await store.transcribeAudio()

        let captured = await provider.capturedTranscriptionRequest
        XCTAssertEqual(captured?.audioData, Data("recorded-audio-bytes".utf8))
        XCTAssertEqual(captured?.fileName, "voice-recording.m4a")
        XCTAssertEqual(captured?.contentType, "audio/mp4")
        XCTAssertEqual(store.audioTranscriptText, "Recorded transcript.")
    }

    @MainActor
    func testStartAudioRecordingBlocksDisabledFeatureBeforeCallingRecorder() async throws {
        let audioRecorder = CapturingAudioRecorder()
        let fixture = try AudioFixture(provider: FakeAudioProvider(), audioRecorder: audioRecorder)
        let store = fixture.makeStore()
        await store.load()
        await store.setFeatureToggle(.audio, isEnabled: false)

        await store.startAudioRecording()

        XCTAssertFalse(store.isRecordingAudio)
        XCTAssertEqual(store.audioError, "Audio is disabled.")
        XCTAssertEqual(store.errorMessage, "Audio is disabled.")
        XCTAssertEqual(audioRecorder.startCallCount, 0)
    }

    @MainActor
    func testStartAudioRecordingRequestsUndeterminedMicrophonePermissionBeforeRecording() async throws {
        let audioRecorder = CapturingAudioRecorder(permissionStatus: .notDetermined, requestedPermissionStatus: .authorized)
        let fixture = try AudioFixture(provider: FakeAudioProvider(), audioRecorder: audioRecorder)
        let store = fixture.makeStore()
        await store.load()

        await store.startAudioRecording()

        XCTAssertEqual(audioRecorder.requestPermissionCallCount, 1)
        XCTAssertEqual(audioRecorder.startCallCount, 1)
        XCTAssertTrue(store.isRecordingAudio)
        XCTAssertEqual(store.audioRecordingPermissionStatus, .authorized)
        XCTAssertNil(store.audioError)
    }

    @MainActor
    func testStartAudioRecordingBlocksDeniedMicrophonePermissionBeforeRecording() async throws {
        let audioRecorder = CapturingAudioRecorder(permissionStatus: .denied)
        let fixture = try AudioFixture(provider: FakeAudioProvider(), audioRecorder: audioRecorder)
        let store = fixture.makeStore()
        await store.load()

        await store.startAudioRecording()

        XCTAssertEqual(audioRecorder.requestPermissionCallCount, 0)
        XCTAssertEqual(audioRecorder.startCallCount, 0)
        XCTAssertFalse(store.isRecordingAudio)
        XCTAssertEqual(store.audioRecordingPermissionStatus, .denied)
        XCTAssertEqual(store.audioError, "Microphone access is denied. Enable it in System Settings to record audio.")
        XCTAssertEqual(store.errorMessage, "Microphone access is denied. Enable it in System Settings to record audio.")
    }

    @MainActor
    func testSynthesizeSpeechRoutesTextToProviderAndStoresAudio() async throws {
        let speechData = Data("speech-bytes".utf8)
        let provider = FakeAudioProvider(speechResult: SpeechSynthesisResult(audioData: speechData, outputFormat: "mp3"))
        let fixture = try AudioFixture(provider: provider)
        let store = fixture.makeStore()
        await store.load()
        store.audioSpeechModelID = "gpt-4o-mini-tts"
        store.audioSpeechInput = "Welcome to native audio."
        store.audioSpeechVoice = "coral"
        store.audioSpeechInstructions = "Warm and concise."
        store.audioSpeechFormat = "mp3"

        await store.synthesizeSpeech()

        let captured = await provider.capturedSpeechRequest
        XCTAssertEqual(captured?.model, "gpt-4o-mini-tts")
        XCTAssertEqual(captured?.input, "Welcome to native audio.")
        XCTAssertEqual(captured?.voice, "coral")
        XCTAssertEqual(captured?.instructions, "Warm and concise.")
        XCTAssertEqual(captured?.responseFormat, "mp3")
        XCTAssertEqual(store.synthesizedSpeechData, speechData)
        XCTAssertEqual(store.synthesizedSpeechFileName, "open-webui-native-speech.mp3")
        XCTAssertFalse(store.isSynthesizingSpeech)
        XCTAssertNil(store.audioError)

        let item = try XCTUnwrap(store.audioHistory.first)
        XCTAssertEqual(item.kind, .speech)
        XCTAssertEqual(item.title, "open-webui-native-speech.mp3")
        XCTAssertEqual(item.text, "Welcome to native audio.")
        XCTAssertEqual(item.modelID, "gpt-4o-mini-tts")
        XCTAssertEqual(item.voice, "coral")
        XCTAssertEqual(item.outputFormat, "mp3")
        XCTAssertEqual(item.audioData, speechData)

        let reloadedStore = fixture.makeStore()
        await reloadedStore.load()

        XCTAssertEqual(reloadedStore.audioHistory.first?.audioData, speechData)
    }

    @MainActor
    func testSynthesizeSpeechBlocksDisabledFeatureBeforeCallingProvider() async throws {
        let speechData = Data("speech-bytes".utf8)
        let provider = FakeAudioProvider(speechResult: SpeechSynthesisResult(audioData: speechData, outputFormat: "mp3"))
        let fixture = try AudioFixture(provider: provider)
        let store = fixture.makeStore()
        await store.load()
        await store.setFeatureToggle(.audio, isEnabled: false)
        store.audioSpeechInput = "Welcome to native audio."

        await store.synthesizeSpeech()

        XCTAssertEqual(store.audioError, "Audio is disabled.")
        XCTAssertEqual(store.errorMessage, "Audio is disabled.")
        XCTAssertNil(store.synthesizedSpeechData)
        XCTAssertFalse(store.isSynthesizingSpeech)
        let captured = await provider.capturedSpeechRequest
        XCTAssertNil(captured)
        XCTAssertTrue(store.audioHistory.isEmpty)
        let reloaded = try await fixture.audioHistoryStorage.loadHistory()
        XCTAssertTrue(reloaded.isEmpty)
    }

    @MainActor
    func testRunVoiceModeTranscribesSendsChatAndSynthesizesAssistantReply() async throws {
        let speechData = Data("voice-answer".utf8)
        let provider = FakeAudioProvider(
            transcriptionText: "What shipped in the native app?",
            speechResult: SpeechSynthesisResult(audioData: speechData, outputFormat: "mp3"),
            chatChunks: ["Native ", "voice mode"]
        )
        let fixture = try AudioFixture(provider: provider)
        let store = fixture.makeStore()
        await store.load()
        store.settings.selectedModelID = "gpt-4.1"
        store.settings.selectedModelIDs = ["gpt-4.1"]
        store.audioTranscriptionModelID = "gpt-4o-mini-transcribe"
        store.audioSpeechModelID = "gpt-4o-mini-tts"
        store.audioSpeechVoice = "coral"
        store.setPendingAudioFile(
            data: Data("audio-bytes".utf8),
            fileName: "voice.wav",
            contentType: "audio/wav"
        )

        await store.runVoiceMode(synthesizeResponse: true)

        let capturedTranscription = await provider.capturedTranscriptionRequest
        XCTAssertEqual(capturedTranscription?.fileName, "voice.wav")
        XCTAssertEqual(store.audioTranscriptText, "What shipped in the native app?")

        let capturedChat = await provider.capturedChatMessages
        XCTAssertEqual(capturedChat.last?.role, ChatRole.user.rawValue)
        XCTAssertEqual(capturedChat.last?.content, "What shipped in the native app?")
        XCTAssertEqual(store.selectedThread?.messages.map(\.content), [
            "What shipped in the native app?",
            "Native voice mode"
        ])

        let capturedSpeech = await provider.capturedSpeechRequest
        XCTAssertEqual(capturedSpeech?.input, "Native voice mode")
        XCTAssertEqual(capturedSpeech?.voice, "coral")
        XCTAssertEqual(store.audioSpeechInput, "Native voice mode")
        XCTAssertEqual(store.synthesizedSpeechData, speechData)
        XCTAssertFalse(store.isRunningVoiceMode)
        XCTAssertNil(store.audioError)

        let history = try await fixture.audioHistoryStorage.loadHistory()
        XCTAssertEqual(Set(history.map(\.kind)), [.transcription, .speech])
    }

    @MainActor
    func testRunVoiceModeBlocksDisabledVoiceModeBeforeProviderCalls() async throws {
        let provider = FakeAudioProvider(
            transcriptionText: "Should not transcribe.",
            speechResult: SpeechSynthesisResult(audioData: Data("speech".utf8), outputFormat: "mp3"),
            chatChunks: ["Should not chat"]
        )
        let fixture = try AudioFixture(provider: provider)
        let store = fixture.makeStore()
        await store.load()
        await store.setFeatureToggle(.voiceMode, isEnabled: false)
        store.settings.selectedModelID = "gpt-4.1"
        store.settings.selectedModelIDs = ["gpt-4.1"]
        store.setPendingAudioFile(
            data: Data("audio-bytes".utf8),
            fileName: "voice.wav",
            contentType: "audio/wav"
        )

        await store.runVoiceMode(synthesizeResponse: true)

        XCTAssertEqual(store.audioError, "Voice Mode is disabled.")
        XCTAssertEqual(store.errorMessage, "Voice Mode is disabled.")
        XCTAssertTrue(store.audioTranscriptText.isEmpty)
        XCTAssertNil(store.selectedThread)
        XCTAssertFalse(store.isRunningVoiceMode)

        let capturedTranscription = await provider.capturedTranscriptionRequest
        let capturedChat = await provider.capturedChatMessages
        let capturedSpeech = await provider.capturedSpeechRequest
        XCTAssertNil(capturedTranscription)
        XCTAssertTrue(capturedChat.isEmpty)
        XCTAssertNil(capturedSpeech)

        let history = try await fixture.audioHistoryStorage.loadHistory()
        XCTAssertTrue(history.isEmpty)
    }

    @MainActor
    func testCanRunVoiceModeReflectsFeatureProviderPermissionAndPendingAudioState() async throws {
        let fixture = try AudioFixture(provider: FakeAudioProvider())
        let store = fixture.makeStore()
        await store.load()

        XCTAssertFalse(store.canRunVoiceMode)

        store.settings.selectedModelID = "gpt-4.1"
        store.settings.selectedModelIDs = ["gpt-4.1"]
        store.setPendingAudioFile(
            data: Data("audio-bytes".utf8),
            fileName: "voice.wav",
            contentType: "audio/wav"
        )

        XCTAssertTrue(store.canRunVoiceMode)

        store.isRunningVoiceMode = true
        XCTAssertFalse(store.canRunVoiceMode)
        store.isRunningVoiceMode = false

        store.isRecordingAudio = true
        XCTAssertFalse(store.canRunVoiceMode)
        store.isRecordingAudio = false

        await store.setFeatureToggle(.voiceMode, isEnabled: false)
        XCTAssertFalse(store.canRunVoiceMode)
    }

    @MainActor
    func testAudioModelFiltersPreferTranscriptionAndSpeechModels() async throws {
        let provider = FakeAudioProvider(models: [
            ProviderModel(id: "gpt-4.1", name: "GPT 4.1", provider: .openAICompatible),
            ProviderModel(id: "whisper-1", name: "Whisper", provider: .openAICompatible),
            ProviderModel(id: "tts-1", name: "TTS 1", provider: .openAICompatible),
            ProviderModel(id: "text-embedding-3-small", name: "Embedding", provider: .openAICompatible)
        ])
        let fixture = try AudioFixture(provider: provider)
        let store = fixture.makeStore()

        await store.refreshModels()

        XCTAssertEqual(store.audioTranscriptionModels.map(\.id), ["whisper-1"])
        XCTAssertEqual(store.audioSpeechModels.map(\.id), ["tts-1"])
        XCTAssertEqual(store.audioTranscriptionModelID, "whisper-1")
        XCTAssertEqual(store.audioSpeechModelID, "tts-1")
    }

    @MainActor
    func testAudioModelFiltersKeepExistingTextWhenNoAudioSpecificModelsAreKnown() async throws {
        let provider = FakeAudioProvider(models: [
            ProviderModel(id: "gpt-4.1", name: "GPT 4.1", provider: .openAICompatible)
        ])
        let fixture = try AudioFixture(provider: provider)
        let store = fixture.makeStore()
        store.audioTranscriptionModelID = "custom-transcribe"
        store.audioSpeechModelID = "custom-tts"

        await store.refreshModels()

        XCTAssertTrue(store.audioTranscriptionModels.isEmpty)
        XCTAssertTrue(store.audioSpeechModels.isEmpty)
        XCTAssertEqual(store.audioTranscriptionModelID, "custom-transcribe")
        XCTAssertEqual(store.audioSpeechModelID, "custom-tts")
    }

    @MainActor
    func testAudioPlaybackControlsPlayPauseAndStopSynthesizedSpeech() throws {
        let player = CapturingAudioPlayer()
        let fixture = try AudioFixture(provider: FakeAudioProvider(), audioPlayer: player)
        let store = fixture.makeStore()
        store.synthesizedSpeechData = Data("speech-bytes".utf8)
        store.synthesizedSpeechFileName = "open-webui-native-speech.mp3"

        store.playSynthesizedSpeech()

        XCTAssertEqual(player.playedAudioData, [Data("speech-bytes".utf8)])
        XCTAssertEqual(player.playedFileNames, ["open-webui-native-speech.mp3"])
        XCTAssertEqual(store.audioPlaybackState, .playing)
        XCTAssertEqual(store.audioPlaybackTitle, "open-webui-native-speech.mp3")

        store.pauseAudioPlayback()

        XCTAssertEqual(player.pauseCallCount, 1)
        XCTAssertEqual(store.audioPlaybackState, .paused)

        store.stopAudioPlayback()

        XCTAssertEqual(player.stopCallCount, 1)
        XCTAssertEqual(store.audioPlaybackState, .stopped)
        XCTAssertNil(store.audioPlaybackTitle)
    }

    @MainActor
    func testPlaySynthesizedSpeechBlocksDisabledFeatureBeforeCallingPlayer() async throws {
        let player = CapturingAudioPlayer()
        let fixture = try AudioFixture(provider: FakeAudioProvider(), audioPlayer: player)
        let store = fixture.makeStore()
        await store.setFeatureToggle(.audio, isEnabled: false)
        store.synthesizedSpeechData = Data("speech-bytes".utf8)
        store.synthesizedSpeechFileName = "open-webui-native-speech.mp3"

        store.playSynthesizedSpeech()

        XCTAssertTrue(player.playedAudioData.isEmpty)
        XCTAssertTrue(player.playedFileNames.isEmpty)
        XCTAssertEqual(store.audioPlaybackState, .stopped)
        XCTAssertNil(store.audioPlaybackTitle)
        XCTAssertEqual(store.audioError, "Audio is disabled.")
        XCTAssertEqual(store.errorMessage, "Audio is disabled.")
    }

    @MainActor
    func testAudioPlaybackLoadsSpeechHistoryItemBeforePlaying() async throws {
        let player = CapturingAudioPlayer()
        let fixture = try AudioFixture(provider: FakeAudioProvider(), audioPlayer: player)
        let speech = AppAudioHistoryItem(
            kind: .speech,
            title: "saved-speech.wav",
            text: "Saved spoken text.",
            modelID: "gpt-4o-mini-tts",
            outputFormat: "wav",
            audioData: Data("saved-speech".utf8)
        )
        try await fixture.audioHistoryStorage.save(speech)
        let store = fixture.makeStore()
        await store.load()

        store.playAudioHistoryItem(speech.id)

        XCTAssertEqual(player.playedAudioData, [Data("saved-speech".utf8)])
        XCTAssertEqual(player.playedFileNames, ["saved-speech.wav"])
        XCTAssertEqual(store.selectedAudioHistoryItemID, speech.id)
        XCTAssertEqual(store.synthesizedSpeechData, Data("saved-speech".utf8))
        XCTAssertEqual(store.audioPlaybackItemID, speech.id)
        XCTAssertEqual(store.audioPlaybackState, .playing)
    }

    @MainActor
    func testLoadAudioHistoryItemRestoresTranscriptOrSpeechOutput() async throws {
        let fixture = try AudioFixture(provider: FakeAudioProvider())
        let transcription = AppAudioHistoryItem(
            kind: .transcription,
            title: "meeting.wav",
            text: "Meeting transcript.",
            modelID: "gpt-4o-mini-transcribe",
            sourceFileName: "meeting.wav",
            sourceContentType: "audio/wav"
        )
        let speech = AppAudioHistoryItem(
            kind: .speech,
            title: "open-webui-native-speech.mp3",
            text: "Spoken text.",
            modelID: "gpt-4o-mini-tts",
            voice: "coral",
            outputFormat: "mp3",
            audioData: Data("speech-bytes".utf8)
        )
        try await fixture.audioHistoryStorage.save(transcription)
        try await fixture.audioHistoryStorage.save(speech)
        let store = fixture.makeStore()
        await store.load()

        store.loadAudioHistoryItem(transcription.id)

        XCTAssertEqual(store.audioTranscriptText, "Meeting transcript.")
        XCTAssertEqual(store.pendingAudioFileName, "meeting.wav")

        store.loadAudioHistoryItem(speech.id)

        XCTAssertEqual(store.audioSpeechInput, "Spoken text.")
        XCTAssertEqual(store.synthesizedSpeechData, Data("speech-bytes".utf8))
        XCTAssertEqual(store.synthesizedSpeechFileName, "open-webui-native-speech.mp3")
    }

    @MainActor
    func testAudioHistoryActionsBlockDisabledFeatureBeforeStatePlaybackOrDeletionChanges() async throws {
        let player = CapturingAudioPlayer()
        let fixture = try AudioFixture(provider: FakeAudioProvider(), audioPlayer: player)
        let item = AppAudioHistoryItem(
            kind: .speech,
            title: "saved-speech.mp3",
            text: "Saved spoken text.",
            modelID: "gpt-4o-mini-tts",
            outputFormat: "mp3",
            audioData: Data("saved-speech".utf8)
        )
        try await fixture.audioHistoryStorage.save(item)
        let store = fixture.makeStore()
        await store.load()
        await store.setFeatureToggle(.audio, isEnabled: false)

        store.loadAudioHistoryItem(item.id)
        store.playAudioHistoryItem(item.id)
        await store.deleteAudioHistoryItem(item.id)

        XCTAssertNil(store.selectedAudioHistoryItemID)
        XCTAssertNil(store.synthesizedSpeechData)
        XCTAssertNil(store.synthesizedSpeechFileName)
        XCTAssertTrue(player.playedAudioData.isEmpty)
        XCTAssertEqual(store.audioPlaybackState, .stopped)
        XCTAssertEqual(store.audioHistory.map(\.id), [item.id])
        let reloaded = try await fixture.audioHistoryStorage.loadHistory()
        XCTAssertEqual(reloaded.map(\.id), [item.id])
        XCTAssertEqual(store.audioError, "Audio is disabled.")
        XCTAssertEqual(store.errorMessage, "Audio is disabled.")
    }

    @MainActor
    func testDeleteAudioHistoryRemovesPersistedItem() async throws {
        let fixture = try AudioFixture(provider: FakeAudioProvider())
        let item = AppAudioHistoryItem(
            kind: .transcription,
            title: "meeting.wav",
            text: "Meeting transcript.",
            modelID: "gpt-4o-mini-transcribe"
        )
        try await fixture.audioHistoryStorage.save(item)
        let store = fixture.makeStore()
        await store.load()

        await store.deleteAudioHistoryItem(item.id)

        XCTAssertTrue(store.audioHistory.isEmpty)
        let reloaded = try await fixture.audioHistoryStorage.loadHistory()
        XCTAssertTrue(reloaded.isEmpty)
    }

    @MainActor
    func testExportAndImportAudioHistoryJSONRoundTripsHistoryAndAuditsCounts() async throws {
        let sourceFixture = try AudioFixture(provider: FakeAudioProvider())
        let sourceStore = sourceFixture.makeStore()
        let transcription = AppAudioHistoryItem(
            id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
            kind: .transcription,
            title: "strategy-meeting.wav",
            text: "Sensitive transcript text.",
            modelID: "gpt-4o-mini-transcribe",
            sourceFileName: "strategy-meeting.wav",
            sourceContentType: "audio/wav",
            createdAt: Date(timeIntervalSince1970: 700),
            updatedAt: Date(timeIntervalSince1970: 710)
        )
        let speech = AppAudioHistoryItem(
            id: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
            kind: .speech,
            title: "open-webui-native-speech.mp3",
            text: "Sensitive speech text.",
            modelID: "gpt-4o-mini-tts",
            voice: "coral",
            instructions: "Speak softly.",
            outputFormat: "mp3",
            audioData: Data("sensitive-audio-bytes".utf8),
            createdAt: Date(timeIntervalSince1970: 800),
            updatedAt: Date(timeIntervalSince1970: 810)
        )
        sourceStore.audioHistory = [speech, transcription]

        let data = try await sourceStore.exportAudioHistoryJSONDataForUserAction()

        let bundle = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        XCTAssertEqual(bundle?["format"] as? String, "open-webui-native-audio-history")
        XCTAssertEqual(bundle?["version"] as? Int, 1)
        XCTAssertEqual((bundle?["items"] as? [[String: Any]])?.count, 2)
        let exportEvent = try XCTUnwrap(sourceStore.auditEvents.first(where: { $0.action == .audioHistoryExported }))
        XCTAssertEqual(exportEvent.outcome, .succeeded)
        XCTAssertEqual(exportEvent.summary, "Exported audio history")
        XCTAssertEqual(exportEvent.metadata["exportedAudioHistoryItemCount"], "2")
        XCTAssertEqual(exportEvent.metadata["exportedTranscriptionCount"], "1")
        XCTAssertEqual(exportEvent.metadata["exportedSpeechCount"], "1")
        XCTAssertNil(exportEvent.metadata["text"])
        XCTAssertNil(exportEvent.metadata["audioData"])
        XCTAssertFalse(exportEvent.metadata.values.contains("Sensitive transcript text."))
        XCTAssertFalse(exportEvent.metadata.values.contains("Sensitive speech text."))
        XCTAssertFalse(exportEvent.metadata.values.contains(Data("sensitive-audio-bytes".utf8).base64EncodedString()))

        let importFixture = try AudioFixture(provider: FakeAudioProvider())
        let importStore = importFixture.makeStore()
        try await importStore.importAudioHistoryJSONDataForUserAction(data)

        XCTAssertEqual(importStore.audioHistory, [speech, transcription])
        let reloaded = try await importFixture.audioHistoryStorage.loadHistory()
        XCTAssertEqual(reloaded, [speech, transcription])
        let importEvent = try XCTUnwrap(importStore.auditEvents.first(where: { $0.action == .audioHistoryImported }))
        XCTAssertEqual(importEvent.outcome, .succeeded)
        XCTAssertEqual(importEvent.summary, "Imported audio history")
        XCTAssertEqual(importEvent.metadata["importedAudioHistoryItemCount"], "2")
        XCTAssertEqual(importEvent.metadata["importedTranscriptionCount"], "1")
        XCTAssertEqual(importEvent.metadata["importedSpeechCount"], "1")
        XCTAssertEqual(importEvent.metadata["totalAudioHistoryItemCount"], "2")
        XCTAssertNil(importEvent.metadata["text"])
        XCTAssertNil(importEvent.metadata["audioData"])
        XCTAssertFalse(importEvent.metadata.values.contains("Sensitive transcript text."))
        XCTAssertFalse(importEvent.metadata.values.contains("Sensitive speech text."))
        XCTAssertFalse(importEvent.metadata.values.contains(Data("sensitive-audio-bytes".utf8).base64EncodedString()))
    }

    @MainActor
    func testExportAudioHistoryForUserActionBlocksDisabledFeatureBeforeDataOrAuditEvent() async throws {
        let fixture = try AudioFixture(provider: FakeAudioProvider())
        let store = fixture.makeStore()
        store.audioHistory = [
            AppAudioHistoryItem(
                kind: .speech,
                title: "saved-speech.mp3",
                text: "Saved spoken text.",
                modelID: "gpt-4o-mini-tts",
                outputFormat: "mp3",
                audioData: Data("saved-speech".utf8)
            )
        ]
        await store.setFeatureToggle(.audio, isEnabled: false)

        do {
            _ = try await store.exportAudioHistoryJSONDataForUserAction()
            XCTFail("Disabled Audio should block audio-history export.")
        } catch {
            XCTAssertEqual(error.localizedDescription, "Audio is disabled.")
        }

        XCTAssertEqual(store.audioError, "Audio is disabled.")
        XCTAssertEqual(store.errorMessage, "Audio is disabled.")
        XCTAssertFalse(store.auditEvents.contains { $0.action == .audioHistoryExported })
    }

    @MainActor
    func testExportAudioHistoryForUserActionRequiresAudioWriteBeforeDataOrAuditEvent() async throws {
        let fixture = try AudioFixture(provider: FakeAudioProvider())
        let store = fixture.makeStore()
        store.adminUsers = [
            AdminUser(id: "local-user", name: "Local User", email: "local@example.com", role: .user)
        ]
        store.audioHistory = [
            AppAudioHistoryItem(
                kind: .speech,
                title: "saved-speech.mp3",
                text: "Saved spoken text.",
                modelID: "gpt-4o-mini-tts",
                outputFormat: "mp3",
                audioData: Data("saved-speech".utf8)
            )
        ]

        do {
            _ = try await store.exportAudioHistoryJSONDataForUserAction()
            XCTFail("Missing audio.write should block audio-history export.")
        } catch {
            XCTAssertEqual(error.localizedDescription, "You do not have permission to manage audio history.")
        }

        XCTAssertEqual(store.audioError, "You do not have permission to manage audio history.")
        XCTAssertEqual(store.errorMessage, "You do not have permission to manage audio history.")
        XCTAssertFalse(store.auditEvents.contains { $0.action == .audioHistoryExported })
    }

    @MainActor
    func testAudioProviderErrorsSurfaceClearly() async throws {
        let provider = FakeAudioProvider(transcriptionErrorMessage: "Transcription unavailable")
        let fixture = try AudioFixture(provider: provider)
        let store = fixture.makeStore()
        store.setPendingAudioFile(data: Data("audio".utf8), fileName: "meeting.wav", contentType: "audio/wav")

        await store.transcribeAudio()

        XCTAssertEqual(store.audioError, "Transcription unavailable")
        XCTAssertEqual(store.errorMessage, "Transcription unavailable")
        XCTAssertTrue(store.audioTranscriptText.isEmpty)
        XCTAssertFalse(store.isTranscribingAudio)
    }

    @MainActor
    func testTranscribeAudioBlocksUnsupportedActiveProviderBeforeCallingProvider() async throws {
        let provider = UnsupportedAudioProvider()
        let fixture = try AudioFixture(provider: provider)
        let store = fixture.makeStore()
        store.setPendingAudioFile(data: Data("audio".utf8), fileName: "meeting.wav", contentType: "audio/wav")

        await store.transcribeAudio()

        XCTAssertEqual(store.audioError, "Ollama does not support native audio transcription.")
        XCTAssertEqual(store.errorMessage, "Ollama does not support native audio transcription.")
        XCTAssertTrue(store.audioTranscriptText.isEmpty)
        XCTAssertFalse(store.isTranscribingAudio)
        let callCount = await provider.transcriptionCallCount
        XCTAssertEqual(callCount, 0)
    }

    @MainActor
    func testSynthesizeSpeechBlocksUnsupportedActiveProviderBeforeCallingProvider() async throws {
        let provider = UnsupportedAudioProvider()
        let fixture = try AudioFixture(provider: provider)
        let store = fixture.makeStore()
        store.audioSpeechInput = "Welcome to native audio."

        await store.synthesizeSpeech()

        XCTAssertEqual(store.audioError, "Ollama does not support native speech synthesis.")
        XCTAssertEqual(store.errorMessage, "Ollama does not support native speech synthesis.")
        XCTAssertNil(store.synthesizedSpeechData)
        XCTAssertFalse(store.isSynthesizingSpeech)
        let callCount = await provider.speechCallCount
        XCTAssertEqual(callCount, 0)
    }

    @MainActor
    func testAudioPermissionsAllowTranscribeSynthesizeAndDeleteHistoryForCurrentUser() async throws {
        let speechData = Data("speech-bytes".utf8)
        let provider = FakeAudioProvider(
            transcriptionText: "Native audio is working.",
            speechResult: SpeechSynthesisResult(audioData: speechData, outputFormat: "mp3")
        )
        let fixture = try AudioFixture(provider: provider)
        let store = fixture.makeStore()
        await store.load()
        store.adminUsers = [
            AdminUser(id: "local-user", name: "Local User", email: "local@example.com", role: .user)
        ]
        store.adminGroups = [
            AdminGroup(
                name: "Audio Users",
                description: "Can use native audio.",
                permissions: ["audio.transcribe", "audio.synthesize", "audio.write"],
                memberIDs: ["local-user"]
            )
        ]
        store.setPendingAudioFile(data: Data("audio".utf8), fileName: "meeting.wav", contentType: "audio/wav")
        store.audioSpeechInput = "Welcome to native audio."

        await store.transcribeAudio()

        XCTAssertEqual(store.audioTranscriptText, "Native audio is working.")
        let capturedTranscriptionRequest = await provider.capturedTranscriptionRequest
        XCTAssertNotNil(capturedTranscriptionRequest)

        await store.synthesizeSpeech()

        XCTAssertEqual(store.synthesizedSpeechData, speechData)
        let capturedSpeechRequest = await provider.capturedSpeechRequest
        XCTAssertNotNil(capturedSpeechRequest)
        XCTAssertEqual(store.audioHistory.count, 2)

        let itemID = try XCTUnwrap(store.audioHistory.first?.id)
        await store.deleteAudioHistoryItem(itemID)

        XCTAssertEqual(store.audioHistory.count, 1)
        XCTAssertNil(store.audioError)
    }

    @MainActor
    func testAudioPermissionsBlockTranscribeSynthesizeAndDeleteHistoryForCurrentUser() async throws {
        let provider = FakeAudioProvider(
            transcriptionText: "Denied transcript",
            speechResult: SpeechSynthesisResult(audioData: Data("speech".utf8), outputFormat: "mp3")
        )
        let fixture = try AudioFixture(provider: provider)
        let item = AppAudioHistoryItem(
            kind: .speech,
            title: "saved-speech.mp3",
            text: "Saved spoken text.",
            modelID: "gpt-4o-mini-tts",
            outputFormat: "mp3",
            audioData: Data("saved-speech".utf8)
        )
        try await fixture.audioHistoryStorage.save(item)

        let store = fixture.makeStore()
        await store.load()
        store.adminUsers = [
            AdminUser(id: "local-user", name: "Local User", email: "local@example.com", role: .user)
        ]
        store.setPendingAudioFile(data: Data("audio".utf8), fileName: "meeting.wav", contentType: "audio/wav")
        store.audioSpeechInput = "Welcome to native audio."

        await store.transcribeAudio()

        XCTAssertEqual(store.audioTranscriptText, "")
        XCTAssertEqual(store.audioError, "You do not have permission to transcribe audio.")
        XCTAssertEqual(store.errorMessage, "You do not have permission to transcribe audio.")
        let capturedTranscriptionRequest = await provider.capturedTranscriptionRequest
        XCTAssertNil(capturedTranscriptionRequest)

        await store.synthesizeSpeech()

        XCTAssertNil(store.synthesizedSpeechData)
        XCTAssertEqual(store.audioError, "You do not have permission to synthesize speech.")
        XCTAssertEqual(store.errorMessage, "You do not have permission to synthesize speech.")
        let capturedSpeechRequest = await provider.capturedSpeechRequest
        XCTAssertNil(capturedSpeechRequest)

        await store.deleteAudioHistoryItem(item.id)

        let reloaded = try await fixture.audioHistoryStorage.loadHistory()
        XCTAssertEqual(store.audioHistory.map(\.id), [item.id])
        XCTAssertEqual(reloaded.map(\.id), [item.id])
        XCTAssertEqual(store.audioError, "You do not have permission to manage audio history.")
        XCTAssertEqual(store.errorMessage, "You do not have permission to manage audio history.")
    }
}

private struct AudioFixture {
    let chatStorage: JSONStorageService
    let settingsStore: SettingsStore
    let audioHistoryStorage: JSONAudioHistoryStorageService
    let adminStorage: JSONAdminDirectoryStorageService
    let provider: any ChatProvider
    let audioPlayer: any AudioPlaybackControlling
    let audioRecorder: any AudioRecordingControlling

    init(
        provider: any ChatProvider,
        audioPlayer: any AudioPlaybackControlling = CapturingAudioPlayer(),
        audioRecorder: any AudioRecordingControlling = CapturingAudioRecorder()
    ) throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        chatStorage = JSONStorageService(rootURL: rootURL.appendingPathComponent("Chats", isDirectory: true))
        settingsStore = SettingsStore(settingsURL: rootURL.appendingPathComponent("settings.json"))
        audioHistoryStorage = JSONAudioHistoryStorageService(
            rootURL: rootURL.appendingPathComponent("AudioHistory", isDirectory: true)
        )
        adminStorage = JSONAdminDirectoryStorageService(
            snapshotURL: rootURL.appendingPathComponent("admin-directory.json")
        )
        self.provider = provider
        self.audioPlayer = audioPlayer
        self.audioRecorder = audioRecorder
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
    }

    @MainActor
    func makeStore() -> AppStore {
        AppStore(
            storage: chatStorage,
            settingsStore: settingsStore,
            secretStore: InMemorySecretStore(),
            providerOverride: provider,
            audioHistoryStorage: audioHistoryStorage,
            audioPlayer: audioPlayer,
            audioRecorder: audioRecorder,
            adminDirectoryStorage: adminStorage
        )
    }
}

private final class CapturingAudioPlayer: AudioPlaybackControlling {
    private(set) var playedAudioData: [Data] = []
    private(set) var playedFileNames: [String] = []
    private(set) var pauseCallCount = 0
    private(set) var stopCallCount = 0

    func play(data: Data, fileName: String) throws {
        playedAudioData.append(data)
        playedFileNames.append(fileName)
    }

    func pause() {
        pauseCallCount += 1
    }

    func stop() {
        stopCallCount += 1
    }
}

private final class CapturingAudioRecorder: AudioRecordingControlling {
    private(set) var startCallCount = 0
    private(set) var stopCallCount = 0
    private(set) var requestPermissionCallCount = 0
    var startError: Error?
    var stopError: Error?
    var recording: RecordedAudio
    var permissionStatus: AudioRecordingPermissionStatus
    var requestedPermissionStatus: AudioRecordingPermissionStatus

    init(
        recording: RecordedAudio = RecordedAudio(
            data: Data("recorded-audio".utf8),
            fileName: "recording.m4a",
            contentType: "audio/mp4"
        ),
        permissionStatus: AudioRecordingPermissionStatus = .authorized,
        requestedPermissionStatus: AudioRecordingPermissionStatus = .authorized
    ) {
        self.recording = recording
        self.permissionStatus = permissionStatus
        self.requestedPermissionStatus = requestedPermissionStatus
    }

    func recordingPermissionStatus() -> AudioRecordingPermissionStatus {
        permissionStatus
    }

    func requestRecordingPermission() async -> AudioRecordingPermissionStatus {
        requestPermissionCallCount += 1
        permissionStatus = requestedPermissionStatus
        return requestedPermissionStatus
    }

    func startRecording() async throws {
        startCallCount += 1
        if let startError {
            throw startError
        }
    }

    func stopRecording() async throws -> RecordedAudio {
        stopCallCount += 1
        if let stopError {
            throw stopError
        }
        return recording
    }
}

private actor FakeAudioProvider: ChatProvider {
    nonisolated let configuration: ProviderConfiguration
    private let transcriptionText: String
    private let speechResult: SpeechSynthesisResult
    private let chatChunks: [String]
    private let transcriptionErrorMessage: String?
    private let speechErrorMessage: String?
    private let models: [ProviderModel]
    private(set) var capturedTranscriptionRequest: AudioTranscriptionRequest?
    private(set) var capturedSpeechRequest: SpeechSynthesisRequest?
    private(set) var capturedChatModel: String?
    private(set) var capturedChatMessages: [ProviderChatMessage] = []

    init(
        transcriptionText: String = "",
        speechResult: SpeechSynthesisResult = SpeechSynthesisResult(audioData: Data(), outputFormat: "mp3"),
        chatChunks: [String] = [],
        transcriptionErrorMessage: String? = nil,
        speechErrorMessage: String? = nil,
        models: [ProviderModel]? = nil
    ) {
        configuration = ProviderConfiguration(
            name: "Audio Provider",
            kind: .openAICompatible,
            baseURL: "https://api.example/v1",
            apiKeySecretID: "secret"
        )
        self.transcriptionText = transcriptionText
        self.speechResult = speechResult
        self.chatChunks = chatChunks
        self.transcriptionErrorMessage = transcriptionErrorMessage
        self.speechErrorMessage = speechErrorMessage
        self.models = models ?? [
            ProviderModel(id: "gpt-4o-mini-transcribe", name: "gpt-4o-mini-transcribe", provider: .openAICompatible, providerID: configuration.id),
            ProviderModel(id: "gpt-4o-mini-tts", name: "gpt-4o-mini-tts", provider: .openAICompatible, providerID: configuration.id)
        ]
    }

    func listModels() async throws -> [ProviderModel] {
        models
    }

    func healthCheck() async -> ProviderStatus {
        .available("Connected")
    }

    nonisolated func streamChat(model: String, messages: [ProviderChatMessage]) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task {
                await self.captureChat(model: model, messages: messages)
                for chunk in self.chatChunks {
                    continuation.yield(chunk)
                }
                continuation.finish()
            }
        }
    }

    private func captureChat(model: String, messages: [ProviderChatMessage]) {
        capturedChatModel = model
        capturedChatMessages = messages
    }

    func createEmbeddings(model: String, input: [String]) async throws -> [[Double]] {
        []
    }

    func transcribeAudio(request: AudioTranscriptionRequest) async throws -> AudioTranscriptionResult {
        capturedTranscriptionRequest = request
        if let transcriptionErrorMessage {
            throw NSError(domain: "FakeAudioProvider", code: 1, userInfo: [
                NSLocalizedDescriptionKey: transcriptionErrorMessage
            ])
        }
        return AudioTranscriptionResult(text: transcriptionText)
    }

    func synthesizeSpeech(request: SpeechSynthesisRequest) async throws -> SpeechSynthesisResult {
        capturedSpeechRequest = request
        if let speechErrorMessage {
            throw NSError(domain: "FakeAudioProvider", code: 2, userInfo: [
                NSLocalizedDescriptionKey: speechErrorMessage
            ])
        }
        return speechResult
    }
}

private actor UnsupportedAudioProvider: ChatProvider {
    nonisolated let configuration = ProviderConfiguration.defaultOllama()
    private(set) var transcriptionCallCount = 0
    private(set) var speechCallCount = 0

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

    func transcribeAudio(request: AudioTranscriptionRequest) async throws -> AudioTranscriptionResult {
        transcriptionCallCount += 1
        return AudioTranscriptionResult(text: "")
    }

    func synthesizeSpeech(request: SpeechSynthesisRequest) async throws -> SpeechSynthesisResult {
        speechCallCount += 1
        return SpeechSynthesisResult(audioData: Data(), outputFormat: "mp3")
    }
}
