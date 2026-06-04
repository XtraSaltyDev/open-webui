import Foundation
import XCTest
@testable import OpenWebUINative

@MainActor
final class AppStorePlaygroundTests: XCTestCase {
    func testRunPlaygroundStreamsPromptSystemMessageAndSelectedModel() async throws {
        let provider = FakePlaygroundProvider(chunks: ["Native", " answer"])
        let fixture = try PlaygroundFixture(provider: provider)
        let store = fixture.makeStore()
        await store.load()
        store.playgroundSystemPrompt = "Be concise."
        store.playgroundPrompt = "Explain SwiftUI."
        store.playgroundModelID = "model-b"

        await store.runPlayground()

        XCTAssertEqual(store.playgroundOutput, "Native answer")
        XCTAssertFalse(store.isRunningPlayground)
        XCTAssertNil(store.playgroundError)

        let captured = await provider.capturedRequest
        XCTAssertEqual(captured?.model, "model-b")
        XCTAssertEqual(captured?.messages, [
            ProviderChatMessage(role: "system", content: "Be concise."),
            ProviderChatMessage(role: "user", content: "Explain SwiftUI.")
        ])
    }

    func testRunPlaygroundFallsBackToSelectedModelWhenNoPlaygroundModelIsSet() async throws {
        let provider = FakePlaygroundProvider(chunks: ["Fallback"])
        let fixture = try PlaygroundFixture(provider: provider)
        let store = fixture.makeStore()
        await store.load()
        store.playgroundModelID = nil
        store.playgroundPrompt = "Use the default model."

        await store.runPlayground()

        XCTAssertEqual(store.playgroundOutput, "Fallback")
        let captured = await provider.capturedRequest
        XCTAssertEqual(captured?.model, "model-a")
    }

    func testRunPlaygroundPassesGenerationOptionsToProvider() async throws {
        let provider = FakePlaygroundProvider(chunks: ["Tuned"])
        let fixture = try PlaygroundFixture(provider: provider)
        let store = fixture.makeStore()
        await store.load()
        store.playgroundPrompt = "Tune this response."
        store.playgroundTemperature = 0.2
        store.playgroundTopP = 0.7
        store.playgroundMaxTokens = 128

        await store.runPlayground()

        let captured = await provider.capturedRequest
        XCTAssertEqual(captured?.options, ProviderChatOptions(temperature: 0.2, topP: 0.7, maxTokens: 128))
    }

    func testRunPlaygroundComparisonStreamsSamePromptToSecondModel() async throws {
        let provider = FakePlaygroundProvider(chunksByModel: [
            "model-a": ["Primary"],
            "model-b": ["Comparison"]
        ])
        let fixture = try PlaygroundFixture(provider: provider)
        let store = fixture.makeStore()
        await store.load()
        store.playgroundPrompt = "Compare these answers."
        store.playgroundModelID = "model-a"
        store.isPlaygroundComparisonEnabled = true
        store.playgroundComparisonModelID = "model-b"
        store.playgroundTemperature = 0.2
        store.playgroundTopP = 0.7
        store.playgroundMaxTokens = 128

        await store.runPlayground()

        XCTAssertEqual(store.playgroundOutput, "Primary")
        XCTAssertEqual(store.playgroundComparisonOutput, "Comparison")
        XCTAssertNil(store.playgroundError)
        XCTAssertNil(store.playgroundComparisonError)
        XCTAssertTrue(store.threads.isEmpty)

        let captured = await provider.capturedRequests
        XCTAssertEqual(captured.map(\.model), ["model-a", "model-b"])
        XCTAssertEqual(captured.map(\.messages), [
            [ProviderChatMessage(role: "user", content: "Compare these answers.")],
            [ProviderChatMessage(role: "user", content: "Compare these answers.")]
        ])
        XCTAssertEqual(captured.map(\.options), [
            ProviderChatOptions(temperature: 0.2, topP: 0.7, maxTokens: 128),
            ProviderChatOptions(temperature: 0.2, topP: 0.7, maxTokens: 128)
        ])
    }

    func testRunCompletionPlaygroundStreamsRawPromptWithoutChatMessages() async throws {
        let provider = FakePlaygroundProvider(completionChunks: ["Raw", " completion"])
        let fixture = try PlaygroundFixture(provider: provider)
        let store = fixture.makeStore()
        await store.load()
        store.playgroundMode = .completions
        store.playgroundPrompt = "Complete this sentence"
        store.playgroundModelID = "model-b"
        store.playgroundTemperature = 0.2
        store.playgroundTopP = 0.7
        store.playgroundMaxTokens = 64

        await store.runPlayground()

        XCTAssertEqual(store.playgroundOutput, "Raw completion")
        XCTAssertFalse(store.isRunningPlayground)
        XCTAssertNil(store.playgroundError)
        XCTAssertTrue(store.threads.isEmpty)
        let captured = await provider.capturedCompletionRequest
        XCTAssertEqual(captured, PlaygroundCompletionRequest(
            model: "model-b",
            prompt: "Complete this sentence",
            options: ProviderChatOptions(temperature: 0.2, topP: 0.7, maxTokens: 64)
        ))
        let chatRequests = await provider.capturedRequests
        XCTAssertTrue(chatRequests.isEmpty)
    }

    func testSavePlaygroundNoteCreatesNativeNoteWithoutCallingProvider() async throws {
        let provider = FakePlaygroundProvider(chunks: ["Should not run"])
        let fixture = try PlaygroundFixture(provider: provider)
        let store = fixture.makeStore()
        await store.load()
        store.playgroundMode = .notes
        store.playgroundNoteTitle = "  Release brief  "
        store.playgroundPrompt = "  Summarize what changed in the native macOS app.  "

        await store.savePlaygroundNote()

        XCTAssertEqual(store.playgroundOutput, "Saved note: Release brief")
        XCTAssertNil(store.playgroundError)
        XCTAssertEqual(store.notes.map(\.title), ["Release brief"])
        XCTAssertEqual(store.notes.first?.content, "Summarize what changed in the native macOS app.")
        let storedNotes = try await fixture.noteStorage.loadNotes()
        XCTAssertEqual(storedNotes.map(\.title), ["Release brief"])
        let chatRequests = await provider.capturedRequests
        let completionRequest = await provider.capturedCompletionRequest
        XCTAssertTrue(chatRequests.isEmpty)
        XCTAssertNil(completionRequest)
    }

    func testSavePlaygroundNoteUpdatesSelectedNativeNote() async throws {
        let fixture = try PlaygroundFixture(provider: FakePlaygroundProvider())
        let store = fixture.makeStore()
        await store.load()
        await store.createNote(title: "Draft", content: "Old body")
        let note = try XCTUnwrap(store.notes.first)
        store.playgroundMode = .notes
        store.selectedPlaygroundNoteID = note.id
        store.playgroundNoteTitle = "  Updated draft  "
        store.playgroundPrompt = "  New body  "

        await store.savePlaygroundNote()

        XCTAssertEqual(store.notes.map(\.title), ["Updated draft"])
        XCTAssertEqual(store.notes.first?.content, "New body")
        XCTAssertEqual(store.playgroundOutput, "Updated note: Updated draft")
        let storedNotes = try await fixture.noteStorage.loadNotes()
        let storedNote = try XCTUnwrap(storedNotes.first)
        XCTAssertEqual(storedNote.id, note.id)
        XCTAssertEqual(storedNote.title, "Updated draft")
        XCTAssertEqual(storedNote.content, "New body")
    }

    func testRunImagePlaygroundRoutesImageRequestAndStoresTemporaryImages() async throws {
        let imageData = Data("playground-image".utf8)
        let provider = FakePlaygroundProvider(
            imageResult: ImageGenerationResult(
                images: [GeneratedImage(data: imageData, revisedPrompt: "A revised image prompt.")],
                outputFormat: "png",
                size: "512x512",
                quality: "standard"
            )
        )
        let fixture = try PlaygroundFixture(provider: provider)
        let store = fixture.makeStore()
        await store.load()
        store.playgroundMode = .images
        store.playgroundPrompt = "Create a native macOS dashboard mockup."
        store.playgroundImageModelID = "gpt-image-1"
        store.playgroundImageSize = "512x512"
        store.playgroundImageQuality = "standard"
        store.playgroundImageCount = 1

        await store.runPlayground()

        XCTAssertEqual(store.playgroundOutput, "Generated 1 image.")
        XCTAssertNil(store.playgroundError)
        XCTAssertFalse(store.isRunningPlayground)
        XCTAssertEqual(store.playgroundImageOutputs, [
            PlaygroundImageOutput(
                imageData: imageData,
                revisedPrompt: "A revised image prompt.",
                outputFormat: "png",
                size: "512x512",
                quality: "standard"
            )
        ])
        let captured = await provider.capturedImageRequest
        XCTAssertEqual(captured, ImageGenerationRequest(
            model: "gpt-image-1",
            prompt: "Create a native macOS dashboard mockup.",
            size: "512x512",
            quality: "standard",
            count: 1
        ))
    }

    func testRunPlaygroundShowsProviderErrorsWithoutSavingChatThread() async throws {
        let provider = FakePlaygroundProvider(errorMessage: "Playground failed")
        let fixture = try PlaygroundFixture(provider: provider)
        let store = fixture.makeStore()
        await store.load()
        store.playgroundPrompt = "Fail clearly."

        await store.runPlayground()

        XCTAssertEqual(store.playgroundOutput, "")
        XCTAssertEqual(store.playgroundError, "Playground failed")
        XCTAssertEqual(store.errorMessage, "Playground failed")
        XCTAssertTrue(store.threads.isEmpty)
        XCTAssertFalse(store.isRunningPlayground)
    }

    func testRunPlaygroundBlocksUnsupportedChatProviderBeforeStreaming() async throws {
        let provider = UnsupportedPlaygroundChatProvider()
        let fixture = try PlaygroundFixture(provider: provider)
        let store = fixture.makeStore()
        await store.load()
        store.playgroundPrompt = "Run a temporary prompt."

        await store.runPlayground()

        XCTAssertEqual(store.playgroundOutput, "")
        XCTAssertEqual(store.playgroundError, "Ollama does not support native chat.")
        XCTAssertEqual(store.errorMessage, "Ollama does not support native chat.")
        XCTAssertFalse(store.isRunningPlayground)
        XCTAssertTrue(store.threads.isEmpty)

        let streamCallCount = await provider.streamCallCount
        XCTAssertEqual(streamCallCount, 0)
    }

    func testRunPlaygroundBlocksDisabledFeatureBeforeProviderStreaming() async throws {
        let provider = FakePlaygroundProvider(chunks: ["Should not stream"])
        let fixture = try PlaygroundFixture(provider: provider)
        let store = fixture.makeStore()
        await store.load()
        await store.setFeatureToggle(.playground, isEnabled: false)
        store.playgroundPrompt = "Run a disabled playground prompt."
        store.playgroundOutput = "Old output"
        store.playgroundComparisonOutput = "Old comparison"
        store.playgroundImageOutputs = [
            PlaygroundImageOutput(imageData: Data("old-image".utf8))
        ]

        await store.runPlayground()

        let capturedRequests = await provider.capturedRequests
        let completionRequest = await provider.capturedCompletionRequest
        let imageRequest = await provider.capturedImageRequest
        XCTAssertTrue(capturedRequests.isEmpty)
        XCTAssertNil(completionRequest)
        XCTAssertNil(imageRequest)
        XCTAssertEqual(store.playgroundOutput, "")
        XCTAssertEqual(store.playgroundComparisonOutput, "")
        XCTAssertEqual(store.playgroundImageOutputs, [])
        XCTAssertEqual(store.playgroundError, "Playground is disabled.")
        XCTAssertEqual(store.errorMessage, "Playground is disabled.")
        XCTAssertFalse(store.isRunningPlayground)
        XCTAssertTrue(store.threads.isEmpty)
    }

    func testPlaygroundPermissionsAllowExecuteSaveAndDeleteForCurrentUser() async throws {
        let provider = FakePlaygroundProvider(chunks: ["Allowed"])
        let fixture = try PlaygroundFixture(provider: provider)
        let store = fixture.makeStore()
        await store.load()
        store.adminUsers = [
            AdminUser(id: "local-user", name: "Local User", email: "local@example.com", role: .user)
        ]
        store.adminGroups = [
            AdminGroup(
                name: "Playground Users",
                description: "Can use the playground.",
                permissions: ["playground.execute", "playground.write"],
                memberIDs: ["local-user"]
            )
        ]
        store.playgroundPrompt = "Run a temporary prompt."
        store.playgroundOutput = ""

        await store.runPlayground()

        XCTAssertEqual(store.playgroundOutput, "Allowed")
        XCTAssertNil(store.playgroundError)
        let capturedRequests = await provider.capturedRequests
        XCTAssertEqual(capturedRequests.count, 1)

        await store.saveCurrentPlaygroundRun(now: Date(timeIntervalSince1970: 1_704_067_200))

        XCTAssertEqual(store.playgroundHistory.count, 1)
        let item = try XCTUnwrap(store.playgroundHistory.first)

        await store.deletePlaygroundHistoryItem(item.id)

        let remainingHistory = try await fixture.historyStorage.loadHistory()
        XCTAssertTrue(store.playgroundHistory.isEmpty)
        XCTAssertTrue(remainingHistory.isEmpty)
    }

    func testPlaygroundPermissionsBlockExecuteSaveAndDeleteForCurrentUser() async throws {
        let provider = FakePlaygroundProvider(chunks: ["Denied"])
        let fixture = try PlaygroundFixture(provider: provider)
        let saved = PlaygroundHistoryItem(
            title: "Saved run",
            modelID: "model-a",
            comparisonModelID: nil,
            isComparisonEnabled: false,
            systemPrompt: nil,
            prompt: "Saved prompt",
            output: "Saved output",
            comparisonOutput: nil,
            options: ProviderChatOptions(temperature: 0.7, topP: 0.9, maxTokens: 512),
            createdAt: Date(timeIntervalSince1970: 1_704_067_200),
            updatedAt: Date(timeIntervalSince1970: 1_704_067_200)
        )
        try await fixture.historyStorage.save(saved)

        let store = fixture.makeStore()
        await store.load()
        store.adminUsers = [
            AdminUser(id: "local-user", name: "Local User", email: "local@example.com", role: .user)
        ]
        store.playgroundPrompt = "Run a temporary prompt."

        await store.runPlayground()

        XCTAssertEqual(store.playgroundOutput, "")
        XCTAssertEqual(store.playgroundError, "You do not have permission to use playground.")
        XCTAssertEqual(store.errorMessage, "You do not have permission to use playground.")
        let capturedRequests = await provider.capturedRequests
        XCTAssertEqual(capturedRequests.count, 0)

        store.playgroundOutput = "Existing output"
        await store.saveCurrentPlaygroundRun(now: Date(timeIntervalSince1970: 1_704_067_200))

        XCTAssertEqual(store.playgroundHistory.map(\.id), [saved.id])
        XCTAssertEqual(store.errorMessage, "You do not have permission to manage playground history.")

        await store.deletePlaygroundHistoryItem(saved.id)

        let remainingHistory = try await fixture.historyStorage.loadHistory()
        XCTAssertEqual(store.playgroundHistory.map(\.id), [saved.id])
        XCTAssertEqual(remainingHistory.map(\.id), [saved.id])
        XCTAssertEqual(store.errorMessage, "You do not have permission to manage playground history.")
    }

    func testSelectPlaygroundClearsOtherSelections() {
        let store = AppStore(secretStore: InMemorySecretStore())
        let threadID = UUID()
        let channelID = UUID()
        let collection = KnowledgeCollection(name: "Docs")
        let document = KnowledgeDocument(
            collectionID: collection.id,
            fileName: "guide.md",
            contentType: "text/markdown",
            byteCount: 10
        )

        store.threads = [ChatThread(id: threadID, title: "Selected")]
        store.channels = [AppChannel(id: channelID, name: "Team")]
        store.selectedThreadID = threadID
        store.selectedChannelID = channelID
        store.selectedKnowledgeDocumentDetail = KnowledgeDocumentDetail(collection: collection, document: document, chunks: [])
        store.isShowingEvaluationDashboard = true
        store.isShowingAnalyticsDashboard = true
        store.isShowingCalendar = true

        store.selectPlayground()

        XCTAssertTrue(store.isShowingPlayground)
        XCTAssertFalse(store.isShowingEvaluationDashboard)
        XCTAssertFalse(store.isShowingAnalyticsDashboard)
        XCTAssertFalse(store.isShowingCalendar)
        XCTAssertNil(store.selectedThreadID)
        XCTAssertNil(store.selectedChannelID)
        XCTAssertNil(store.selectedKnowledgeDocumentDetail)
    }

    func testPlaygroundExportTextIncludesSystemPromptUserPromptAndOutput() throws {
        let transcript = PlaygroundTranscript(
            modelID: "llama3.2:latest",
            systemPrompt: "Be concise.",
            prompt: "Explain SwiftUI.",
            output: "SwiftUI is a declarative UI framework.",
            createdAt: Date(timeIntervalSince1970: 1_704_067_200)
        )

        let text = PlaygroundExportService().text(for: transcript)

        XCTAssertEqual(
            text,
            """
            ### SYSTEM
            Be concise.

            ### USER
            Explain SwiftUI.

            ### ASSISTANT
            SwiftUI is a declarative UI framework.
            """
        )
    }

    func testPlaygroundExportJSONRoundTripsTranscriptBundle() throws {
        let transcript = PlaygroundTranscript(
            modelID: "llama3.2:latest",
            systemPrompt: nil,
            prompt: "Explain SwiftUI.",
            output: "SwiftUI is declarative.",
            createdAt: Date(timeIntervalSince1970: 1_704_067_200)
        )

        let data = try PlaygroundExportService().jsonData(for: transcript)
        let bundle = try JSONDecoder().decode(PlaygroundExportBundle.self, from: data)

        XCTAssertEqual(bundle.version, 1)
        XCTAssertEqual(bundle.transcript.modelID, "llama3.2:latest")
        XCTAssertEqual(bundle.transcript.prompt, "Explain SwiftUI.")
        XCTAssertEqual(bundle.transcript.output, "SwiftUI is declarative.")
    }

    func testPlaygroundExportJSONIncludesComparisonAndGenerationOptions() throws {
        let transcript = PlaygroundTranscript(
            modelID: "model-a",
            comparisonModelID: "model-b",
            isComparisonEnabled: true,
            systemPrompt: "Be concise.",
            prompt: "Compare SwiftUI and AppKit.",
            output: "SwiftUI is declarative.",
            comparisonOutput: "AppKit is imperative.",
            options: ProviderChatOptions(temperature: 0.2, topP: 0.7, maxTokens: 128),
            createdAt: Date(timeIntervalSince1970: 1_704_067_200)
        )

        let data = try PlaygroundExportService().jsonData(for: transcript)
        let bundle = try JSONDecoder().decode(PlaygroundExportBundle.self, from: data)

        XCTAssertEqual(bundle.transcript.modelID, "model-a")
        XCTAssertEqual(bundle.transcript.comparisonModelID, "model-b")
        XCTAssertTrue(bundle.transcript.isComparisonEnabled)
        XCTAssertEqual(bundle.transcript.comparisonOutput, "AppKit is imperative.")
        XCTAssertEqual(bundle.transcript.options, ProviderChatOptions(temperature: 0.2, topP: 0.7, maxTokens: 128))
    }

    func testAppStoreBuildsCurrentPlaygroundTranscriptForExport() throws {
        let store = AppStore(secretStore: InMemorySecretStore())
        store.playgroundModelID = "model-a"
        store.playgroundSystemPrompt = "  Be concise.  "
        store.playgroundPrompt = "  Explain SwiftUI.  "
        store.playgroundOutput = "  SwiftUI is declarative.  "
        store.isPlaygroundComparisonEnabled = true
        store.playgroundComparisonModelID = "model-b"
        store.playgroundComparisonOutput = "  SwiftUI builds UI from state.  "
        store.playgroundTemperature = 0.2
        store.playgroundTopP = 0.7
        store.playgroundMaxTokens = 128

        let transcript = try store.currentPlaygroundTranscript(now: Date(timeIntervalSince1970: 1_704_067_200))

        XCTAssertEqual(transcript.modelID, "model-a")
        XCTAssertEqual(transcript.comparisonModelID, "model-b")
        XCTAssertTrue(transcript.isComparisonEnabled)
        XCTAssertEqual(transcript.systemPrompt, "Be concise.")
        XCTAssertEqual(transcript.prompt, "Explain SwiftUI.")
        XCTAssertEqual(transcript.output, "SwiftUI is declarative.")
        XCTAssertEqual(transcript.comparisonOutput, "SwiftUI builds UI from state.")
        XCTAssertEqual(transcript.options, ProviderChatOptions(temperature: 0.2, topP: 0.7, maxTokens: 128))
        XCTAssertEqual(transcript.createdAt, Date(timeIntervalSince1970: 1_704_067_200))
    }

    func testShareCurrentPlaygroundRunSharesJSONTranscript() throws {
        let shareService = FakePlaygroundShareService()
        let fixture = try PlaygroundFixture(provider: FakePlaygroundProvider(), shareService: shareService)
        let store = fixture.makeStore()
        store.playgroundModelID = "model-a"
        store.playgroundSystemPrompt = "Be concise."
        store.playgroundPrompt = "Compare SwiftUI and AppKit."
        store.playgroundOutput = "SwiftUI is declarative."
        store.isPlaygroundComparisonEnabled = true
        store.playgroundComparisonModelID = "model-b"
        store.playgroundComparisonOutput = "AppKit is imperative."
        store.playgroundTemperature = 0.2
        store.playgroundTopP = 0.7
        store.playgroundMaxTokens = 128

        store.shareCurrentPlaygroundRun()

        XCTAssertEqual(shareService.sharedTitle, "Compare SwiftUI and AppKit.")
        let sharedText = try XCTUnwrap(shareService.sharedText)
        let bundle = try JSONDecoder().decode(PlaygroundExportBundle.self, from: Data(sharedText.utf8))
        XCTAssertEqual(bundle.transcript.modelID, "model-a")
        XCTAssertEqual(bundle.transcript.comparisonModelID, "model-b")
        XCTAssertEqual(bundle.transcript.prompt, "Compare SwiftUI and AppKit.")
        XCTAssertEqual(bundle.transcript.output, "SwiftUI is declarative.")
        XCTAssertEqual(bundle.transcript.comparisonOutput, "AppKit is imperative.")
        XCTAssertEqual(bundle.transcript.options, ProviderChatOptions(temperature: 0.2, topP: 0.7, maxTokens: 128))
    }

    func testSharePlaygroundHistoryItemSharesSavedRunJSON() async throws {
        let shareService = FakePlaygroundShareService()
        let fixture = try PlaygroundFixture(provider: FakePlaygroundProvider(), shareService: shareService)
        let saved = PlaygroundHistoryItem(
            title: "Saved comparison",
            modelID: "model-a",
            comparisonModelID: "model-b",
            isComparisonEnabled: true,
            systemPrompt: "Be concise.",
            prompt: "Compare SwiftUI and AppKit.",
            output: "SwiftUI is declarative.",
            comparisonOutput: "AppKit is imperative.",
            options: ProviderChatOptions(temperature: 0.2, topP: 0.7, maxTokens: 128),
            createdAt: Date(timeIntervalSince1970: 1_704_067_200),
            updatedAt: Date(timeIntervalSince1970: 1_704_067_260)
        )
        try await fixture.historyStorage.save(saved)
        let store = fixture.makeStore()
        await store.load()

        store.sharePlaygroundHistoryItem(saved.id)

        XCTAssertEqual(shareService.sharedTitle, "Saved comparison")
        let sharedText = try XCTUnwrap(shareService.sharedText)
        let bundle = try JSONDecoder().decode(PlaygroundExportBundle.self, from: Data(sharedText.utf8))
        XCTAssertEqual(bundle.transcript.modelID, "model-a")
        XCTAssertEqual(bundle.transcript.comparisonModelID, "model-b")
        XCTAssertEqual(bundle.transcript.prompt, "Compare SwiftUI and AppKit.")
        XCTAssertEqual(bundle.transcript.comparisonOutput, "AppKit is imperative.")
        XCTAssertEqual(bundle.transcript.createdAt, Date(timeIntervalSince1970: 1_704_067_200))
    }

    func testSaveCurrentPlaygroundRunPersistsHistoryItem() async throws {
        let fixture = try PlaygroundFixture(provider: FakePlaygroundProvider())
        let store = fixture.makeStore()
        await store.load()
        store.playgroundModelID = "model-a"
        store.playgroundSystemPrompt = "Be concise."
        store.playgroundPrompt = "Explain SwiftUI."
        store.playgroundOutput = "SwiftUI is declarative."
        store.isPlaygroundComparisonEnabled = true
        store.playgroundComparisonModelID = "model-b"
        store.playgroundComparisonOutput = "SwiftUI builds UI from state."
        store.playgroundTemperature = 0.2
        store.playgroundTopP = 0.7
        store.playgroundMaxTokens = 128

        await store.saveCurrentPlaygroundRun(now: Date(timeIntervalSince1970: 1_704_067_200))

        XCTAssertEqual(store.playgroundHistory.count, 1)
        let item = try XCTUnwrap(store.playgroundHistory.first)
        XCTAssertEqual(item.title, "Explain SwiftUI.")
        XCTAssertEqual(item.modelID, "model-a")
        XCTAssertEqual(item.comparisonModelID, "model-b")
        XCTAssertEqual(item.systemPrompt, "Be concise.")
        XCTAssertEqual(item.prompt, "Explain SwiftUI.")
        XCTAssertEqual(item.output, "SwiftUI is declarative.")
        XCTAssertEqual(item.comparisonOutput, "SwiftUI builds UI from state.")
        XCTAssertEqual(item.options, ProviderChatOptions(temperature: 0.2, topP: 0.7, maxTokens: 128))

        let reloaded = try await fixture.historyStorage.loadHistory()
        XCTAssertEqual(reloaded.map(\.id), [item.id])
    }

    func testSaveAndLoadImagePlaygroundHistoryRestoresImageRunState() async throws {
        let fixture = try PlaygroundFixture(provider: FakePlaygroundProvider())
        let imageOutput = PlaygroundImageOutput(
            imageData: Data("saved-image".utf8),
            revisedPrompt: "A revised saved prompt.",
            outputFormat: "png",
            size: "1024x1024",
            quality: "high"
        )
        let store = fixture.makeStore()
        await store.load()
        store.playgroundMode = .images
        store.playgroundImageModelID = "gpt-image-1"
        store.playgroundImageSize = "1024x1024"
        store.playgroundImageQuality = "high"
        store.playgroundImageCount = 1
        store.playgroundPrompt = "Generate an app icon."
        store.playgroundOutput = "Generated 1 image."
        store.playgroundImageOutputs = [imageOutput]

        await store.saveCurrentPlaygroundRun(now: Date(timeIntervalSince1970: 1_704_067_200))

        XCTAssertEqual(store.playgroundHistory.count, 1)
        let item = try XCTUnwrap(store.playgroundHistory.first)
        XCTAssertEqual(item.mode, .images)
        XCTAssertEqual(item.imageOutputs, [imageOutput])
        XCTAssertEqual(item.imageSize, "1024x1024")
        XCTAssertEqual(item.imageQuality, "high")
        XCTAssertEqual(item.imageCount, 1)

        let reloadedStore = fixture.makeStore()
        await reloadedStore.load()
        reloadedStore.loadPlaygroundHistoryItem(item.id)

        XCTAssertEqual(reloadedStore.playgroundMode, .images)
        XCTAssertEqual(reloadedStore.playgroundPrompt, "Generate an app icon.")
        XCTAssertEqual(reloadedStore.playgroundOutput, "Generated 1 image.")
        XCTAssertEqual(reloadedStore.playgroundImageOutputs, [imageOutput])
        XCTAssertEqual(reloadedStore.playgroundImageSize, "1024x1024")
        XCTAssertEqual(reloadedStore.playgroundImageQuality, "high")
        XCTAssertEqual(reloadedStore.playgroundImageCount, 1)
    }

    func testLoadPlaygroundHistoryItemRestoresRunState() async throws {
        let fixture = try PlaygroundFixture(provider: FakePlaygroundProvider())
        let saved = PlaygroundHistoryItem(
            title: "Saved run",
            modelID: "model-a",
            comparisonModelID: "model-b",
            isComparisonEnabled: true,
            systemPrompt: "Be concise.",
            prompt: "Explain SwiftUI.",
            output: "SwiftUI is declarative.",
            comparisonOutput: "SwiftUI builds UI from state.",
            options: ProviderChatOptions(temperature: 0.2, topP: 0.7, maxTokens: 128),
            createdAt: Date(timeIntervalSince1970: 1_704_067_200),
            updatedAt: Date(timeIntervalSince1970: 1_704_067_200)
        )
        try await fixture.historyStorage.save(saved)

        let store = fixture.makeStore()
        await store.load()

        store.loadPlaygroundHistoryItem(saved.id)

        XCTAssertEqual(store.playgroundModelID, "model-a")
        XCTAssertEqual(store.playgroundComparisonModelID, "model-b")
        XCTAssertTrue(store.isPlaygroundComparisonEnabled)
        XCTAssertEqual(store.playgroundSystemPrompt, "Be concise.")
        XCTAssertEqual(store.playgroundPrompt, "Explain SwiftUI.")
        XCTAssertEqual(store.playgroundOutput, "SwiftUI is declarative.")
        XCTAssertEqual(store.playgroundComparisonOutput, "SwiftUI builds UI from state.")
        XCTAssertEqual(store.playgroundTemperature, 0.2)
        XCTAssertEqual(store.playgroundTopP, 0.7)
        XCTAssertEqual(store.playgroundMaxTokens, 128)
    }
}

private struct PlaygroundFixture {
    let rootURL: URL
    let storage: JSONStorageService
    let settingsStore: SettingsStore
    let historyStorage: JSONPlaygroundHistoryStorageService
    let noteStorage: JSONNoteStorageService
    let provider: any ChatProvider
    let shareService: FakePlaygroundShareService?

    init(provider: any ChatProvider, shareService: FakePlaygroundShareService? = nil) throws {
        rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        storage = JSONStorageService(rootURL: rootURL.appendingPathComponent("Chats", isDirectory: true))
        settingsStore = SettingsStore(settingsURL: rootURL.appendingPathComponent("settings.json"))
        historyStorage = JSONPlaygroundHistoryStorageService(
            rootURL: rootURL.appendingPathComponent("PlaygroundHistory", isDirectory: true)
        )
        noteStorage = JSONNoteStorageService(rootURL: rootURL.appendingPathComponent("Notes", isDirectory: true))
        self.provider = provider
        self.shareService = shareService
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
    }

    @MainActor
    func makeStore() -> AppStore {
        AppStore(
            storage: storage,
            settingsStore: settingsStore,
            secretStore: InMemorySecretStore(),
            providerOverride: provider,
            shareService: shareService ?? FakePlaygroundShareService(),
            playgroundHistoryStorage: historyStorage,
            noteStorage: noteStorage
        )
    }
}

@MainActor
private final class FakePlaygroundShareService: ChatSharing {
    private(set) var sharedText: String?
    private(set) var sharedTitle: String?

    func share(text: String, title: String) {
        sharedText = text
        sharedTitle = title
    }
}

private actor FakePlaygroundProvider: ChatProvider {
    nonisolated var configuration: ProviderConfiguration {
        ProviderConfiguration.defaultOllama()
    }

    nonisolated var capabilities: ProviderCapabilities {
        .openAICompatible
    }

    private let chunks: [String]
    private let chunksByModel: [String: [String]]
    private let completionChunks: [String]
    private let errorMessage: String?
    private let imageResult: ImageGenerationResult
    private(set) var capturedRequest: PlaygroundRequest?
    private(set) var capturedRequests: [PlaygroundRequest] = []
    private(set) var capturedCompletionRequest: PlaygroundCompletionRequest?
    private(set) var capturedImageRequest: ImageGenerationRequest?

    init(
        chunks: [String] = [],
        chunksByModel: [String: [String]] = [:],
        completionChunks: [String] = [],
        errorMessage: String? = nil,
        imageResult: ImageGenerationResult = ImageGenerationResult(images: [], outputFormat: nil, size: nil, quality: nil)
    ) {
        self.chunks = chunks
        self.chunksByModel = chunksByModel
        self.completionChunks = completionChunks
        self.errorMessage = errorMessage
        self.imageResult = imageResult
    }

    func listModels() async throws -> [ProviderModel] {
        [
            ProviderModel(id: "model-a", name: "model-a", provider: .ollama, providerID: configuration.id),
            ProviderModel(id: "model-b", name: "model-b", provider: .ollama, providerID: configuration.id)
        ]
    }

    func healthCheck() async -> ProviderStatus {
        .available("Fake connected")
    }

    nonisolated func streamChat(model: String, messages: [ProviderChatMessage]) -> AsyncThrowingStream<String, Error> {
        streamChat(model: model, messages: messages, options: nil)
    }

    nonisolated func streamChat(
        model: String,
        messages: [ProviderChatMessage],
        options: ProviderChatOptions?
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task {
                await capture(model: model, messages: messages, options: options)
                if let errorMessage {
                    continuation.finish(throwing: NSError(domain: "FakePlaygroundProvider", code: 1, userInfo: [
                        NSLocalizedDescriptionKey: errorMessage
                    ]))
                    return
                }
                for chunk in await chunks(for: model) {
                    continuation.yield(chunk)
                }
                continuation.finish()
            }
        }
    }

    func createEmbeddings(model: String, input: [String]) async throws -> [[Double]] {
        []
    }

    nonisolated func streamCompletion(
        model: String,
        prompt: String,
        options: ProviderChatOptions?
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task {
                await captureCompletion(model: model, prompt: prompt, options: options)
                if let errorMessage {
                    continuation.finish(throwing: NSError(domain: "FakePlaygroundProvider", code: 2, userInfo: [
                        NSLocalizedDescriptionKey: errorMessage
                    ]))
                    return
                }
                for chunk in await completionStreamChunks() {
                    continuation.yield(chunk)
                }
                continuation.finish()
            }
        }
    }

    func generateImages(request: ImageGenerationRequest) async throws -> ImageGenerationResult {
        capturedImageRequest = request
        if let errorMessage {
            throw NSError(domain: "FakePlaygroundProvider", code: 2, userInfo: [
                NSLocalizedDescriptionKey: errorMessage
            ])
        }
        return imageResult
    }

    private func capture(model: String, messages: [ProviderChatMessage], options: ProviderChatOptions?) {
        let request = PlaygroundRequest(model: model, messages: messages, options: options)
        capturedRequest = request
        capturedRequests.append(request)
    }

    private func captureCompletion(model: String, prompt: String, options: ProviderChatOptions?) {
        capturedCompletionRequest = PlaygroundCompletionRequest(model: model, prompt: prompt, options: options)
    }

    private func chunks(for model: String) -> [String] {
        chunksByModel[model] ?? chunks
    }

    private func completionStreamChunks() -> [String] {
        completionChunks
    }
}

private actor UnsupportedPlaygroundChatProvider: ChatProvider {
    nonisolated var configuration: ProviderConfiguration {
        ProviderConfiguration.defaultOllama()
    }

    nonisolated var capabilities: ProviderCapabilities {
        var capabilities = ProviderConfiguration.defaultOllama().capabilities
        capabilities.supportsChat = false
        return capabilities
    }

    private(set) var streamCallCount = 0

    func listModels() async throws -> [ProviderModel] {
        [
            ProviderModel(id: "model-a", name: "model-a", provider: .ollama, providerID: configuration.id)
        ]
    }

    func healthCheck() async -> ProviderStatus {
        .available("Fake connected")
    }

    nonisolated func streamChat(model: String, messages: [ProviderChatMessage]) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task {
                await recordStreamCall()
                continuation.yield("Unsupported answer")
                continuation.finish()
            }
        }
    }

    func createEmbeddings(model: String, input: [String]) async throws -> [[Double]] {
        []
    }

    private func recordStreamCall() {
        streamCallCount += 1
    }
}

private struct PlaygroundRequest: Equatable, Sendable {
    var model: String
    var messages: [ProviderChatMessage]
    var options: ProviderChatOptions?
}

private struct PlaygroundCompletionRequest: Equatable, Sendable {
    var model: String
    var prompt: String
    var options: ProviderChatOptions?
}
