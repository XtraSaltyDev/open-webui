import Foundation
import XCTest
@testable import OpenWebUINative

final class AppDiagnosticsTests: XCTestCase {
    func testDiagnosticsSnapshotBuildsPathsProviderStateAndOmitsSecrets() {
        let providerID = UUID()
        let settings = AppSettings(
            providers: [
                ProviderConfiguration(
                    id: providerID,
                    name: "Gateway",
                    kind: .openAICompatible,
                    baseURL: "https://gateway.example/v1",
                    apiKeySecretID: "secret-provider-key"
                )
            ],
            activeProviderID: providerID,
            selectedModelID: "gpt-test",
            selectedModelIDs: ["gpt-test", "gpt-backup"],
            embeddingModelID: "text-embedding-3-small"
        )
        let paths = AppDataPaths(
            appDataRootURL: URL(fileURLWithPath: "/tmp/OpenWebUINative"),
            settingsURL: URL(fileURLWithPath: "/tmp/OpenWebUINative/settings.json"),
            chatStorageURL: URL(fileURLWithPath: "/tmp/OpenWebUINative/Chats"),
            backupRootURL: URL(fileURLWithPath: "/tmp/OpenWebUINative/Backups")
        )
        let selectedThreadID = UUID(uuidString: "00000000-0000-0000-0000-000000000123")!
        let selectedThread = ChatThread(
            id: selectedThreadID,
            title: "Debug chat",
            messages: [
                ChatMessage(role: .user, content: "secret message content"),
                ChatMessage(role: .assistant, content: "still secret", isStreaming: true)
            ]
        )

        let snapshot = AppDiagnosticsSnapshot.make(
            settings: settings,
            paths: paths,
            providerStatus: .available("Gateway connected"),
            models: [
                ProviderModel(id: "gpt-test", name: "GPT Test", provider: .openAICompatible, providerID: providerID),
                ProviderModel(id: "gpt-backup", name: "GPT Backup", provider: .openAICompatible, providerID: providerID)
            ],
            threads: [
                ChatThread(id: UUID(), title: "Other chat"),
                selectedThread
            ],
            selectedThreadID: selectedThreadID,
            activeStreamingBranchCount: 1,
            latestAutomaticBackupTimestamp: Date(timeIntervalSince1970: 100),
            recentErrorSummary: "Recovered 1 chat record."
        )

        XCTAssertEqual(snapshot.appDataRootPath, "/tmp/OpenWebUINative")
        XCTAssertEqual(snapshot.settingsFilePath, "/tmp/OpenWebUINative/settings.json")
        XCTAssertEqual(snapshot.chatStoragePath, "/tmp/OpenWebUINative/Chats")
        XCTAssertEqual(snapshot.backupPath, "/tmp/OpenWebUINative/Backups")
        XCTAssertEqual(snapshot.activeProviderName, "Gateway")
        XCTAssertEqual(snapshot.activeProviderKind, "OpenAI-compatible")
        XCTAssertEqual(snapshot.activeProviderBaseURL, "https://gateway.example/v1")
        XCTAssertEqual(snapshot.providerHealthStatus, "Gateway connected")
        XCTAssertEqual(snapshot.modelCount, 2)
        XCTAssertEqual(snapshot.selectedModelIDs, ["gpt-test", "gpt-backup"])
        XCTAssertEqual(snapshot.selectedEmbeddingModelID, "text-embedding-3-small")
        XCTAssertEqual(snapshot.chatCount, 2)
        XCTAssertEqual(snapshot.selectedThreadID, selectedThreadID)
        XCTAssertEqual(snapshot.selectedThreadTitle, "Debug chat")
        XCTAssertEqual(snapshot.selectedThreadMessageCount, 2)
        XCTAssertEqual(snapshot.activeStreamingBranchCount, 1)
        XCTAssertEqual(snapshot.currentModelSelectionSummary, "gpt-test, gpt-backup")
        XCTAssertEqual(snapshot.lastProviderErrorSummary, "Recovered 1 chat record.")
        XCTAssertFalse(snapshot.localExecutionEnabled)
        XCTAssertEqual(snapshot.latestAutomaticBackupTimestamp, Date(timeIntervalSince1970: 100))
        XCTAssertEqual(snapshot.recentErrorSummary, "Recovered 1 chat record.")

        XCTAssertFalse(snapshot.searchableText.contains("secret-provider-key"))
        XCTAssertFalse(snapshot.searchableText.contains("secret message content"))
        XCTAssertFalse(snapshot.searchableText.contains("still secret"))
    }
}
