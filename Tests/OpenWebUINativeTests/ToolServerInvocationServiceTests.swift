import Foundation
import XCTest
@testable import OpenWebUINative

final class ToolServerInvocationServiceTests: XCTestCase {
    func testHTTPInvocationPostsJSONPayloadAndCapturesResponse() async throws {
        let recorder = RequestRecorder()
        let server = AppToolServer(
            id: "gateway",
            name: "Gateway",
            kind: .http,
            baseURL: "http://localhost:4444/invoke"
        )
        let service = ToolServerInvocationService { request in
            await recorder.record(request)
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (Data(#"{"ok":true}"#.utf8), response)
        }

        let run = await service.invoke(
            ToolServerInvocationRequest(server: server, requestBody: #"{"ping":true}"#)
        )
        let capturedRequest = await recorder.requests.first

        XCTAssertEqual(capturedRequest?.url?.absoluteString, "http://localhost:4444/invoke")
        XCTAssertEqual(capturedRequest?.httpMethod, "POST")
        XCTAssertEqual(capturedRequest?.value(forHTTPHeaderField: "Content-Type"), "application/json")
        XCTAssertEqual(capturedRequest?.httpBody.flatMap { String(data: $0, encoding: .utf8) }, #"{"ping":true}"#)
        XCTAssertEqual(run.serverID, "gateway")
        XCTAssertEqual(run.serverName, "Gateway")
        XCTAssertEqual(run.statusCode, 200)
        XCTAssertEqual(run.responseBody, #"{"ok":true}"#)
        XCTAssertEqual(run.status, .succeeded)
        XCTAssertNil(run.errorMessage)
    }

    func testHTTPInvocationFailsForNonSuccessStatusCodes() async {
        let server = AppToolServer(
            id: "gateway",
            name: "Gateway",
            kind: .http,
            baseURL: "http://localhost:4444/invoke"
        )
        let service = ToolServerInvocationService { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 500,
                httpVersion: nil,
                headerFields: nil
            )!
            return (Data("server error".utf8), response)
        }

        let run = await service.invoke(
            ToolServerInvocationRequest(server: server, requestBody: "{}")
        )

        XCTAssertEqual(run.status, .failed)
        XCTAssertEqual(run.statusCode, 500)
        XCTAssertEqual(run.responseBody, "server error")
        XCTAssertEqual(run.errorMessage, "HTTP 500")
    }

    func testHTTPInvocationFailsForInvalidURL() async {
        let server = AppToolServer(
            id: "bad",
            name: "Bad Gateway",
            kind: .http,
            baseURL: "not a url"
        )
        let service = ToolServerInvocationService { _ in
            XCTFail("Invalid URLs should not call the network loader.")
            return (Data(), URLResponse())
        }

        let run = await service.invoke(
            ToolServerInvocationRequest(server: server, requestBody: "{}")
        )

        XCTAssertEqual(run.status, .failed)
        XCTAssertNil(run.statusCode)
        XCTAssertEqual(run.errorMessage, "Invalid URL.")
    }

    func testStdioInvocationRunsCommandWithRequestBodyOnStdin() async throws {
        let scriptURL = try makeStdioInvocationFixtureScript()
        let server = AppToolServer(
            id: "stdio",
            name: "Stdio MCP",
            kind: .stdio,
            command: "/usr/bin/python3",
            arguments: [scriptURL.path],
            environment: ["NATIVE_STDIO_FIXTURE": "1"]
        )
        let service = ToolServerInvocationService { _ in
            XCTFail("Stdio invocation should not call the HTTP loader.")
            return (Data(), URLResponse())
        }

        let run = await service.invoke(
            ToolServerInvocationRequest(server: server, requestBody: #"{"ping":true}"#)
        )

        XCTAssertEqual(run.serverID, "stdio")
        XCTAssertEqual(run.serverName, "Stdio MCP")
        XCTAssertEqual(run.serverKind, .stdio)
        XCTAssertEqual(run.requestBody, #"{"ping":true}"#)
        XCTAssertEqual(run.statusCode, 0)
        XCTAssertEqual(run.status, .succeeded)
        XCTAssertNil(run.errorMessage)
        XCTAssertEqual(run.responseBody, #"{"received":"{\"ping\":true}","env":"1"}"# + "\n")
    }

    func testStdioInvocationCapturesStderrAndExitCodeForFailures() async throws {
        let scriptURL = try makeFailingStdioInvocationFixtureScript()
        let server = AppToolServer(
            id: "stdio",
            name: "Stdio MCP",
            kind: .stdio,
            command: "/usr/bin/python3",
            arguments: [scriptURL.path]
        )
        let service = ToolServerInvocationService { _ in
            XCTFail("Stdio invocation should not call the HTTP loader.")
            return (Data(), URLResponse())
        }

        let run = await service.invoke(
            ToolServerInvocationRequest(server: server, requestBody: #"{"ping":true}"#)
        )

        XCTAssertEqual(run.statusCode, 7)
        XCTAssertEqual(run.status, .failed)
        XCTAssertEqual(run.responseBody, "partial stdout\n")
        XCTAssertEqual(run.errorMessage, "fixture failed")
    }

    func testStdioInvocationTimesOutAndTerminatesHangingProcess() async throws {
        let markerURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent("terminated.marker")
        let scriptURL = try makeHangingStdioInvocationFixtureScript(markerURL: markerURL)
        let server = AppToolServer(
            id: "stdio",
            name: "Hanging Stdio MCP",
            kind: .stdio,
            command: "/usr/bin/python3",
            arguments: [scriptURL.path],
            environment: ["NATIVE_STDIO_TERMINATION_MARKER": markerURL.path]
        )
        let service = ToolServerInvocationService(stdioTimeoutSeconds: 0.2)

        let run = await service.invoke(
            ToolServerInvocationRequest(server: server, requestBody: #"{"ping":true}"#)
        )

        XCTAssertEqual(run.status, .failed)
        XCTAssertNil(run.statusCode)
        XCTAssertEqual(run.errorMessage, "Timed out after 0.2 seconds.")
        XCTAssertEqual(try String(contentsOf: markerURL, encoding: .utf8), "terminated")
    }

    func testStdioInvocationCancelsHangingProcess() async throws {
        let markerURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent("terminated.marker")
        let scriptURL = try makeHangingStdioInvocationFixtureScript(markerURL: markerURL)
        let server = AppToolServer(
            id: "stdio",
            name: "Hanging Stdio MCP",
            kind: .stdio,
            command: "/usr/bin/python3",
            arguments: [scriptURL.path],
            environment: ["NATIVE_STDIO_TERMINATION_MARKER": markerURL.path]
        )
        let service = ToolServerInvocationService(stdioTimeoutSeconds: 5)
        let startedAt = Date()

        let task = Task {
            await service.invoke(
                ToolServerInvocationRequest(server: server, requestBody: #"{"ping":true}"#)
            )
        }

        try await Task.sleep(nanoseconds: 150_000_000)
        task.cancel()
        let run = await task.value

        XCTAssertEqual(run.status, .failed)
        XCTAssertNil(run.statusCode)
        XCTAssertEqual(run.errorMessage, "Invocation cancelled.")
        XCTAssertLessThan(Date().timeIntervalSince(startedAt), 2.0)
        XCTAssertEqual(try String(contentsOf: markerURL, encoding: .utf8), "terminated")
    }

    private func makeStdioInvocationFixtureScript() throws -> URL {
        try makeFixtureScript(named: "stdio_invocation_fixture.py", body: #"""
        import json
        import os
        import sys

        body = sys.stdin.read()
        print(json.dumps({
            "received": body,
            "env": os.environ.get("NATIVE_STDIO_FIXTURE", "")
        }, separators=(",", ":")), flush=True)
        """#)
    }

    private func makeFailingStdioInvocationFixtureScript() throws -> URL {
        try makeFixtureScript(named: "failing_stdio_invocation_fixture.py", body: #"""
        import sys

        print("partial stdout", flush=True)
        print("fixture failed", file=sys.stderr, flush=True)
        raise SystemExit(7)
        """#)
    }

    private func makeFixtureScript(named name: String, body: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let scriptURL = directory.appendingPathComponent(name)
        try Data(body.utf8).write(to: scriptURL)
        return scriptURL
    }

    private func makeHangingStdioInvocationFixtureScript(markerURL: URL) throws -> URL {
        let directory = markerURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let scriptURL = directory.appendingPathComponent("hanging_stdio_invocation_fixture.py")
        let script = #"""
        import os
        import pathlib
        import signal
        import time

        marker = pathlib.Path(os.environ["NATIVE_STDIO_TERMINATION_MARKER"])

        def handle_sigterm(signum, frame):
            marker.write_text("terminated")
            raise SystemExit(0)

        signal.signal(signal.SIGTERM, handle_sigterm)

        while True:
            time.sleep(1)
        """#
        try Data(script.utf8).write(to: scriptURL)
        return scriptURL
    }
}

private actor RequestRecorder {
    private(set) var requests: [URLRequest] = []

    func record(_ request: URLRequest) {
        requests.append(request)
    }
}
