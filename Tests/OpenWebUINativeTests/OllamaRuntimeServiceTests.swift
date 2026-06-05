import Foundation
import XCTest
@testable import OpenWebUINative

final class OllamaRuntimeServiceTests: XCTestCase {
    func testStatusReturnsReachableVersionFromVersionEndpoint() async throws {
        var capturedRequest: URLRequest?
        let service = OllamaRuntimeService(
            dataLoader: { request in
                capturedRequest = request
                return (#"{"version":"0.12.6"}"#.data(using: .utf8)!, HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
            }
        )

        let status = await service.status(baseURL: "http://localhost:11434")

        XCTAssertEqual(status, .reachable(version: "0.12.6"))
        XCTAssertEqual(capturedRequest?.url?.path, "/api/version")
        XCTAssertEqual(capturedRequest?.httpMethod, "GET")
    }

    func testStatusReturnsUnreachableSafeReasonWhenConnectionFails() async {
        let service = OllamaRuntimeService(
            dataLoader: { _ in
                throw URLError(.cannotConnectToHost)
            }
        )

        let status = await service.status(baseURL: "http://localhost:11434")

        XCTAssertEqual(status, .unreachable(reason: "Ollama is not reachable at http://localhost:11434."))
    }

    func testStartOpensInstalledAppAndWaitsForReachability() async throws {
        var openedApplications: [String] = []
        var healthAttempts = 0
        let service = OllamaRuntimeService(
            dataLoader: { request in
                healthAttempts += 1
                if healthAttempts == 1 {
                    throw URLError(.cannotConnectToHost)
                }
                return (#"{"version":"0.12.6"}"#.data(using: .utf8)!, HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
            },
            fileExists: { path in
                path == "/Applications/Ollama.app"
            },
            openApplication: { url in
                openedApplications.append(url.path)
                return true
            },
            sleep: { _ in }
        )

        let status = await service.start(baseURL: "http://localhost:11434", preferredMethod: .automatic)
        let ownsRunningCLIProcess = await service.ownsRunningCLIProcess

        XCTAssertEqual(openedApplications, ["/Applications/Ollama.app"])
        XCTAssertEqual(status, .startedByApp(version: "0.12.6"))
        XCTAssertFalse(ownsRunningCLIProcess)
    }

    func testStartUsesTrustedCLIWhenAppMissingAndTracksOwnership() async throws {
        var launchedExecutables: [String] = []
        let fakeProcess = FakeOllamaRuntimeProcess()
        var healthAttempts = 0
        let service = OllamaRuntimeService(
            dataLoader: { request in
                healthAttempts += 1
                if healthAttempts == 1 {
                    throw URLError(.cannotConnectToHost)
                }
                return (#"{"version":"0.12.6"}"#.data(using: .utf8)!, HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
            },
            fileExists: { path in
                path == "/opt/homebrew/bin/ollama"
            },
            openApplication: { _ in
                XCTFail("App should not open when it is missing")
                return false
            },
            launchProcess: { executablePath, arguments in
                launchedExecutables.append("\(executablePath) \(arguments.joined(separator: " "))")
                return fakeProcess
            },
            sleep: { _ in }
        )

        let status = await service.start(baseURL: "http://localhost:11434", preferredMethod: .automatic)
        let ownsRunningCLIProcess = await service.ownsRunningCLIProcess

        XCTAssertEqual(launchedExecutables, ["/opt/homebrew/bin/ollama serve"])
        XCTAssertEqual(status, .startedByApp(version: "0.12.6"))
        XCTAssertTrue(ownsRunningCLIProcess)
    }

    func testStopOwnedProcessTerminatesOnlyAppOwnedCLIProcess() async throws {
        let fakeProcess = FakeOllamaRuntimeProcess()
        var healthAttempts = 0
        let service = OllamaRuntimeService(
            dataLoader: { request in
                healthAttempts += 1
                if healthAttempts == 1 {
                    throw URLError(.cannotConnectToHost)
                }
                return (#"{"version":"0.12.6"}"#.data(using: .utf8)!, HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
            },
            fileExists: { path in
                path == "/opt/homebrew/bin/ollama"
            },
            launchProcess: { _, _ in fakeProcess },
            sleep: { _ in }
        )

        _ = await service.start(baseURL: "http://localhost:11434", preferredMethod: .cli)
        await service.stopOwnedCLIProcess()
        let ownsRunningCLIProcess = await service.ownsRunningCLIProcess

        XCTAssertEqual(fakeProcess.terminateCount, 1)
        XCTAssertFalse(ownsRunningCLIProcess)

        await service.stopOwnedCLIProcess()
        XCTAssertEqual(fakeProcess.terminateCount, 1)
    }
}

private final class FakeOllamaRuntimeProcess: OllamaRuntimeProcessHandling {
    private(set) var terminateCount = 0
    var isRunning = true

    func terminate() {
        terminateCount += 1
        isRunning = false
    }
}
