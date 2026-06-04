import Foundation
import XCTest
@testable import OpenWebUINative

final class AppSettingsTests: XCTestCase {
    func testDecodingOldMVPSettingsAddsDefaultOllamaProvider() throws {
        let data = """
        {
          "ollamaBaseURL": "http://localhost:11434",
          "selectedModelID": "llama3.2:latest"
        }
        """.data(using: .utf8)!

        let settings = try JSONDecoder().decode(AppSettings.self, from: data)

        XCTAssertEqual(settings.providers.count, 1)
        XCTAssertEqual(settings.providers.first?.kind, .ollama)
        XCTAssertEqual(settings.providers.first?.baseURL, "http://localhost:11434")
        XCTAssertEqual(settings.activeProviderID, ProviderConfiguration.defaultOllamaID)
        XCTAssertEqual(settings.selectedModelID, "llama3.2:latest")
        XCTAssertEqual(settings.selectedModelIDs, ["llama3.2:latest"])
    }

    func testDecodingSettingsUsesSelectedModelIDsWhenPresent() throws {
        let data = """
        {
          "ollamaBaseURL": "http://localhost:11434",
          "selectedModelID": "llama3.2:latest",
          "selectedModelIDs": ["llama3.2:latest", "mistral:latest"]
        }
        """.data(using: .utf8)!

        let settings = try JSONDecoder().decode(AppSettings.self, from: data)

        XCTAssertEqual(settings.selectedModelID, "llama3.2:latest")
        XCTAssertEqual(settings.selectedModelIDs, ["llama3.2:latest", "mistral:latest"])
    }

    func testDecodingSettingsWithStaleActiveProviderIDFallsBackToAvailableProvider() throws {
        let data = """
        {
          "ollamaBaseURL": "http://localhost:11434",
          "providers": [
            {
              "id": "00000000-0000-0000-0000-000000000114",
              "name": "Ollama",
              "kind": "ollama",
              "baseURL": "http://localhost:11434",
              "isEnabled": true
            }
          ],
          "activeProviderID": "11111111-1111-1111-1111-111111111111"
        }
        """.data(using: .utf8)!

        let settings = try JSONDecoder().decode(AppSettings.self, from: data)

        XCTAssertEqual(settings.activeProviderID, ProviderConfiguration.defaultOllamaID)
        XCTAssertEqual(settings.activeProvider.id, ProviderConfiguration.defaultOllamaID)
    }

    func testDecodingSettingsWithEmptyProviderListRestoresDefaultOllamaProvider() throws {
        let data = """
        {
          "ollamaBaseURL": "http://localhost:11434",
          "providers": [],
          "activeProviderID": "11111111-1111-1111-1111-111111111111"
        }
        """.data(using: .utf8)!

        let settings = try JSONDecoder().decode(AppSettings.self, from: data)

        XCTAssertEqual(settings.providers.map(\.id), [ProviderConfiguration.defaultOllamaID])
        XCTAssertEqual(settings.providers.first?.kind, .ollama)
        XCTAssertEqual(settings.providers.first?.baseURL, "http://localhost:11434")
        XCTAssertEqual(settings.activeProviderID, ProviderConfiguration.defaultOllamaID)
    }

    func testDecodingSettingsPreservesEmbeddingModelID() throws {
        let data = """
        {
          "ollamaBaseURL": "http://localhost:11434",
          "selectedModelID": "llama3.2:latest",
          "embeddingModelID": "nomic-embed-text:latest"
        }
        """.data(using: .utf8)!

        let settings = try JSONDecoder().decode(AppSettings.self, from: data)

        XCTAssertEqual(settings.embeddingModelID, "nomic-embed-text:latest")
    }

    func testWebSearchSettingsRoundTripThroughSettingsJSON() throws {
        var settings = AppSettings()
        settings.webSearch = WebSearchSettings(
            engine: .brave,
            resultCount: 5,
            searxngBaseURL: "http://localhost:8888",
            braveAPIKeySecretID: "web-search-brave-key",
            domainFilterList: ["developer.apple.com", "swift.org"],
            isPageContentLoadingEnabled: true,
            maxPageContentCharacters: 6_000
        )

        let data = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(AppSettings.self, from: data)

        XCTAssertEqual(decoded.webSearch.engine, .brave)
        XCTAssertEqual(decoded.webSearch.resultCount, 5)
        XCTAssertEqual(decoded.webSearch.searxngBaseURL, "http://localhost:8888")
        XCTAssertEqual(decoded.webSearch.braveAPIKeySecretID, "web-search-brave-key")
        XCTAssertEqual(decoded.webSearch.domainFilterList, ["developer.apple.com", "swift.org"])
        XCTAssertTrue(decoded.webSearch.isPageContentLoadingEnabled)
        XCTAssertEqual(decoded.webSearch.maxPageContentCharacters, 6_000)
    }

    func testDecodingWebSearchSettingsNormalizesAdminControls() throws {
        let data = """
        {
          "webSearch": {
            "engine": "searxng",
            "resultCount": 25,
            "searxngBaseURL": " http://localhost:8888 ",
            "braveAPIKeySecretID": " web-search-brave-key ",
            "domainFilterList": [" Developer.Apple.com ", "developer.apple.com", "", "SWIFT.ORG"],
            "isPageContentLoadingEnabled": true,
            "maxPageContentCharacters": 25000
          }
        }
        """.data(using: .utf8)!

        let settings = try JSONDecoder().decode(AppSettings.self, from: data)

        XCTAssertEqual(settings.webSearch.engine, .searxng)
        XCTAssertEqual(settings.webSearch.resultCount, 10)
        XCTAssertEqual(settings.webSearch.searxngBaseURL, "http://localhost:8888")
        XCTAssertEqual(settings.webSearch.braveAPIKeySecretID, "web-search-brave-key")
        XCTAssertEqual(settings.webSearch.domainFilterList, ["developer.apple.com", "swift.org"])
        XCTAssertTrue(settings.webSearch.isPageContentLoadingEnabled)
        XCTAssertEqual(settings.webSearch.maxPageContentCharacters, 12_000)
    }

    func testCodeExecutionSettingsRoundTripThroughSettingsJSON() throws {
        var settings = AppSettings()
        settings.codeExecution = CodeExecutionSettings(
            allowedLanguages: [.python],
            allowedWorkingDirectoryRoots: ["/Users/example/Projects"],
            allowedExecutableNames: ["python3", "pip3"],
            deniedExecutableNames: ["rm", "sudo"],
            maxTimeoutSeconds: 20
        )

        let data = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(AppSettings.self, from: data)

        XCTAssertEqual(decoded.codeExecution.allowedLanguages, [.python])
        XCTAssertEqual(decoded.codeExecution.allowedWorkingDirectoryRoots, ["/Users/example/Projects"])
        XCTAssertEqual(decoded.codeExecution.allowedExecutableNames, ["python3", "pip3"])
        XCTAssertEqual(decoded.codeExecution.deniedExecutableNames, ["rm", "sudo"])
        XCTAssertEqual(decoded.codeExecution.maxTimeoutSeconds, 20)
    }

    func testDecodingOlderCodeExecutionSettingsDefaultsExecutableRules() throws {
        let data = """
        {
          "codeExecution": {
            "allowedLanguages": ["shell"],
            "allowedWorkingDirectoryRoots": ["/tmp"],
            "maxTimeoutSeconds": 12
          }
        }
        """.data(using: .utf8)!

        let settings = try JSONDecoder().decode(AppSettings.self, from: data)

        XCTAssertEqual(settings.codeExecution.allowedLanguages, [.shell])
        XCTAssertEqual(settings.codeExecution.allowedWorkingDirectoryRoots, ["/tmp"])
        XCTAssertEqual(settings.codeExecution.allowedExecutableNames, [])
        XCTAssertEqual(settings.codeExecution.deniedExecutableNames, [])
        XCTAssertEqual(settings.codeExecution.maxTimeoutSeconds, 12)
    }
}
