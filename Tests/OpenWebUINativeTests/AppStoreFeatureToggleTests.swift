import XCTest
@testable import OpenWebUINative

final class FeatureToggleSettingsTests: XCTestCase {
    func testDecodingOldSettingsDefaultsNativeFeatureToggles() throws {
        let data = """
        {
          "ollamaBaseURL": "http://localhost:11434",
          "selectedModelID": "llama3.2:latest"
        }
        """.data(using: .utf8)!

        let settings = try JSONDecoder().decode(AppSettings.self, from: data)

        XCTAssertTrue(settings.featureToggles.isEnabled(.folders))
        XCTAssertTrue(settings.featureToggles.isEnabled(.files))
        XCTAssertTrue(settings.featureToggles.isEnabled(.notes))
        XCTAssertTrue(settings.featureToggles.isEnabled(.knowledge))
        XCTAssertTrue(settings.featureToggles.isEnabled(.adminDirectory))
        XCTAssertTrue(settings.featureToggles.isEnabled(.channels))
        XCTAssertTrue(settings.featureToggles.isEnabled(.automations))
        XCTAssertTrue(settings.featureToggles.isEnabled(.calendar))
        XCTAssertTrue(settings.featureToggles.isEnabled(.analytics))
        XCTAssertTrue(settings.featureToggles.isEnabled(.playground))
        XCTAssertTrue(settings.featureToggles.isEnabled(.imageGeneration))
        XCTAssertTrue(settings.featureToggles.isEnabled(.audio))
        XCTAssertTrue(settings.featureToggles.isEnabled(.voiceMode))
        XCTAssertTrue(settings.featureToggles.isEnabled(.webSearch))
        XCTAssertFalse(settings.featureToggles.isEnabled(.codeInterpreter))
        XCTAssertFalse(settings.featureToggles.isEnabled(.terminalSessions))
    }

    func testFeatureTogglesRoundTripThroughSettingsJSON() throws {
        var settings = AppSettings()
        settings.featureToggles.set(.notes, isEnabled: false)
        settings.featureToggles.set(.voiceMode, isEnabled: false)
        settings.featureToggles.set(.webSearch, isEnabled: true)

        let data = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(AppSettings.self, from: data)

        XCTAssertFalse(decoded.featureToggles.isEnabled(.notes))
        XCTAssertFalse(decoded.featureToggles.isEnabled(.voiceMode))
        XCTAssertTrue(decoded.featureToggles.isEnabled(.webSearch))
        XCTAssertTrue(decoded.featureToggles.isEnabled(.folders))
        XCTAssertTrue(decoded.featureToggles.isEnabled(.files))
    }
}

@MainActor
final class AppStoreFeatureToggleTests: XCTestCase {
    func testSetFeatureTogglePersistsAndReloads() async throws {
        let fixture = try FeatureToggleFixture()
        let store = fixture.makeStore()
        await store.load()

        await store.setFeatureToggle(.notes, isEnabled: false)
        await store.setFeatureToggle(.voiceMode, isEnabled: false)
        await store.setFeatureToggle(.webSearch, isEnabled: true)

        XCTAssertFalse(store.isFeatureEnabled(.notes))
        XCTAssertFalse(store.isFeatureEnabled(.voiceMode))
        XCTAssertTrue(store.isFeatureEnabled(.webSearch))

        let reloadedStore = fixture.makeStore()
        await reloadedStore.load()

        XCTAssertFalse(reloadedStore.isFeatureEnabled(.notes))
        XCTAssertFalse(reloadedStore.isFeatureEnabled(.voiceMode))
        XCTAssertTrue(reloadedStore.isFeatureEnabled(.webSearch))
    }

    func testDisablingFilesFeatureClosesFilesSurface() async throws {
        let fixture = try FeatureToggleFixture()
        let store = fixture.makeStore()
        await store.load()

        store.selectFiles()
        XCTAssertTrue(store.isShowingFiles)

        await store.setFeatureToggle(.files, isEnabled: false)

        XCTAssertFalse(store.isShowingFiles)
    }
}

private struct FeatureToggleFixture {
    let rootURL: URL
    let chatStorage: JSONStorageService
    let folderStorage: JSONFolderStorageService
    let settingsStore: SettingsStore

    init() throws {
        rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        chatStorage = JSONStorageService(rootURL: rootURL.appendingPathComponent("Chats", isDirectory: true))
        folderStorage = JSONFolderStorageService(rootURL: rootURL.appendingPathComponent("Folders", isDirectory: true))
        settingsStore = SettingsStore(settingsURL: rootURL.appendingPathComponent("settings.json"))
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
    }

    @MainActor
    func makeStore() -> AppStore {
        AppStore(
            storage: chatStorage,
            folderStorage: folderStorage,
            settingsStore: settingsStore,
            secretStore: InMemorySecretStore()
        )
    }
}
