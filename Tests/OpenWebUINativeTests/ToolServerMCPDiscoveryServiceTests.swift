import Foundation
import XCTest
@testable import OpenWebUINative

final class ToolServerMCPDiscoveryServiceTests: XCTestCase {
    func testDiscoverHTTPServerInitializesAndListsTools() async {
        let recorder = RequestRecorder()
        let server = AppToolServer(
            id: "gateway",
            name: "Gateway",
            kind: .http,
            baseURL: "http://localhost:4444/mcp"
        )
        let service = ToolServerMCPDiscoveryService { request in
            await recorder.record(request)
            let body = request.httpBody.flatMap { String(data: $0, encoding: .utf8) } ?? ""
            let payload: String
            if body.contains(#""method":"initialize""#) {
                payload = """
                {
                  "jsonrpc": "2.0",
                  "id": 1,
                  "result": {
                    "protocolVersion": "2025-06-18",
                    "capabilities": { "tools": { "listChanged": true } },
                    "serverInfo": { "name": "gateway", "version": "1.0.0" }
                  }
                }
                """
            } else if body.contains(#""method":"notifications/initialized""#) {
                return (Data(), HTTPURLResponse(url: request.url!, statusCode: 202, httpVersion: nil, headerFields: nil)!)
            } else {
                payload = """
                {
                  "jsonrpc": "2.0",
                  "id": 2,
                  "result": {
                    "tools": [
                      {
                        "name": "search_docs",
                        "title": "Search Docs",
                        "description": "Search indexed documents.",
                        "inputSchema": {
                          "type": "object",
                          "properties": {
                            "query": { "type": "string" }
                          },
                          "required": ["query"]
                        }
                      },
                      {
                        "name": "summarize",
                        "description": "Summarize a document.",
                        "inputSchema": { "type": "object" }
                      }
                    ]
                  }
                }
                """
            }

            return (
                Data(payload.utf8),
                HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            )
        }

        let result = await service.discoverTools(for: server)
        let requests = await recorder.requests
        let requestBodies = requests.map { request in
            request.httpBody.flatMap { String(data: $0, encoding: .utf8) } ?? ""
        }

        XCTAssertEqual(result.status, .available("Discovered 2 tools."))
        XCTAssertEqual(result.tools.map(\.name), ["search_docs", "summarize"])
        XCTAssertEqual(result.tools.first?.title, "Search Docs")
        XCTAssertEqual(result.tools.first?.description, "Search indexed documents.")
        XCTAssertEqual(result.tools.first?.inputSchema.objectValue?["type"], .string("object"))
        XCTAssertEqual(requests.map(\.httpMethod), ["POST", "POST", "POST"])
        XCTAssertEqual(requests.first?.url?.absoluteString, "http://localhost:4444/mcp")
        XCTAssertEqual(requests.first?.value(forHTTPHeaderField: "Accept"), "application/json, text/event-stream")
        XCTAssertTrue(requestBodies[0].contains(#""method":"initialize""#))
        XCTAssertTrue(requestBodies[1].contains(#""method":"notifications/initialized""#))
        XCTAssertTrue(requestBodies[2].contains(#""method":"tools/list""#))
    }

    func testDiscoverHTTPServerReportsJSONRPCErrors() async {
        let server = AppToolServer(
            id: "gateway",
            name: "Gateway",
            kind: .http,
            baseURL: "http://localhost:4444/mcp"
        )
        let service = ToolServerMCPDiscoveryService { request in
            let body = request.httpBody.flatMap { String(data: $0, encoding: .utf8) } ?? ""
            if body.contains(#""method":"tools/list""#) {
                let payload = """
                {
                  "jsonrpc": "2.0",
                  "id": 2,
                  "error": { "code": -32000, "message": "Tools unavailable" }
                }
                """
                return (Data(payload.utf8), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
            }
            let payload = #"{"jsonrpc":"2.0","id":1,"result":{}}"#
            return (Data(payload.utf8), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }

        let result = await service.discoverTools(for: server)

        XCTAssertEqual(result.status, .unavailable("Tools unavailable"))
        XCTAssertTrue(result.tools.isEmpty)
    }

    func testCallHTTPToolInitializesAndSendsToolsCall() async {
        let recorder = RequestRecorder()
        let server = AppToolServer(
            id: "gateway",
            name: "Gateway",
            kind: .http,
            baseURL: "http://localhost:4444/mcp"
        )
        let service = ToolServerMCPDiscoveryService { request in
            await recorder.record(request)
            let body = request.httpBody.flatMap { String(data: $0, encoding: .utf8) } ?? ""
            let payload: String
            let responseHeaders: [String: String]?
            if body.contains(#""method":"initialize""#) {
                payload = #"{"jsonrpc":"2.0","id":1,"result":{}}"#
                responseHeaders = ["Mcp-Session-Id": "session-123"]
            } else if body.contains(#""method":"notifications/initialized""#) {
                return (Data(), HTTPURLResponse(url: request.url!, statusCode: 202, httpVersion: nil, headerFields: nil)!)
            } else {
                payload = """
                {
                  "jsonrpc": "2.0",
                  "id": 2,
                  "result": {
                    "content": [
                      { "type": "text", "text": "Found two documents." }
                    ],
                    "structuredContent": { "count": 2 }
                  }
                }
                """
                responseHeaders = nil
            }

            return (
                Data(payload.utf8),
                HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: responseHeaders)!
            )
        }

        let run = await service.callTool(
            ToolServerToolCallRequest(
                server: server,
                toolName: "search_docs",
                arguments: .object(["query": .string("SwiftUI")])
            )
        )
        let requests = await recorder.requests
        let requestBodies = requests.map { request in
            request.httpBody.flatMap { String(data: $0, encoding: .utf8) } ?? ""
        }

        XCTAssertEqual(run.status, .succeeded)
        XCTAssertEqual(run.serverID, "gateway")
        XCTAssertEqual(run.requestBody, #"{"query":"SwiftUI"}"#)
        XCTAssertTrue(run.responseBody.contains("Found two documents."))
        XCTAssertTrue(run.responseBody.contains(#""count":2"#))
        XCTAssertEqual(requests.map(\.httpMethod), ["POST", "POST", "POST"])
        XCTAssertNil(requests[0].value(forHTTPHeaderField: "Mcp-Session-Id"))
        XCTAssertEqual(requests[1].value(forHTTPHeaderField: "Mcp-Session-Id"), "session-123")
        XCTAssertEqual(requests[2].value(forHTTPHeaderField: "Mcp-Session-Id"), "session-123")
        XCTAssertTrue(requestBodies[0].contains(#""method":"initialize""#))
        XCTAssertTrue(requestBodies[1].contains(#""method":"notifications/initialized""#))
        XCTAssertTrue(requestBodies[2].contains(#""method":"tools/call""#))
        XCTAssertTrue(requestBodies[2].contains(#""name":"search_docs""#))
        XCTAssertTrue(requestBodies[2].contains(#""arguments":{"query":"SwiftUI"}"#))
    }

    func testCallStdioToolInitializesAndSendsToolsCall() async throws {
        let scriptURL = try makeStdioMCPFixtureScript()
        let server = AppToolServer(
            id: "stdio",
            name: "Stdio MCP",
            kind: .stdio,
            command: "/usr/bin/python3",
            arguments: [scriptURL.path],
            environment: ["NATIVE_MCP_FIXTURE": "1"]
        )
        let service = ToolServerMCPDiscoveryService { _ in
            XCTFail("Stdio tool calls should not call the HTTP loader.")
            return (Data(), URLResponse())
        }

        let run = await service.callTool(
            ToolServerToolCallRequest(
                server: server,
                toolName: "local_search",
                arguments: .object(["query": .string("SwiftUI")])
            )
        )

        XCTAssertEqual(run.status, .succeeded)
        XCTAssertEqual(run.serverID, "stdio")
        XCTAssertEqual(run.serverKind, .stdio)
        XCTAssertNil(run.statusCode)
        XCTAssertEqual(run.requestBody, #"{"query":"SwiftUI"}"#)
        XCTAssertNil(run.errorMessage)
        XCTAssertTrue(run.responseBody.contains("Local result for SwiftUI"))
        XCTAssertTrue(run.responseBody.contains(#""count":1"#))
    }

    func testDiscoverRejectsInvalidURL() async {
        let server = AppToolServer(
            id: "bad",
            name: "Bad Gateway",
            kind: .http,
            baseURL: "not a url"
        )
        let service = ToolServerMCPDiscoveryService { _ in
            XCTFail("Invalid URLs should not call the network loader.")
            return (Data(), URLResponse())
        }

        let result = await service.discoverTools(for: server)

        XCTAssertEqual(result.status, .unavailable("Invalid URL."))
        XCTAssertTrue(result.tools.isEmpty)
    }

    func testDiscoverStdioServerInitializesAndListsTools() async throws {
        let scriptURL = try makeStdioMCPFixtureScript()
        let server = AppToolServer(
            id: "stdio",
            name: "Stdio MCP",
            kind: .stdio,
            command: "/usr/bin/python3",
            arguments: [scriptURL.path],
            environment: ["NATIVE_MCP_FIXTURE": "1"]
        )
        let service = ToolServerMCPDiscoveryService { _ in
            XCTFail("Stdio discovery should not call the HTTP loader.")
            return (Data(), URLResponse())
        }

        let result = await service.discoverTools(for: server)

        XCTAssertEqual(result.status, .available("Discovered 1 tools."))
        XCTAssertEqual(result.tools.map(\.name), ["local_search"])
        XCTAssertEqual(result.tools.first?.title, "Local Search")
        XCTAssertEqual(result.tools.first?.description, "Search local files.")
        XCTAssertEqual(result.tools.first?.inputSchema.objectValue?["type"], .string("object"))
    }

    private func makeStdioMCPFixtureScript() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let scriptURL = directory.appendingPathComponent("stdio_mcp_fixture.py")
        let script = #"""
        import json
        import os
        import sys

        assert os.environ.get("NATIVE_MCP_FIXTURE") == "1"

        for line in sys.stdin:
            message = json.loads(line)
            method = message.get("method")
            if method == "initialize":
                print(json.dumps({
                    "jsonrpc": "2.0",
                    "id": message["id"],
                    "result": {
                        "protocolVersion": "2025-06-18",
                        "capabilities": {"tools": {"listChanged": False}},
                        "serverInfo": {"name": "fixture", "version": "1.0.0"}
                    }
                }), flush=True)
            elif method == "notifications/initialized":
                print("initialized", file=sys.stderr, flush=True)
            elif method == "tools/list":
                print(json.dumps({
                    "jsonrpc": "2.0",
                    "id": message["id"],
                    "result": {
                        "tools": [
                            {
                                "name": "local_search",
                                "title": "Local Search",
                                "description": "Search local files.",
                                "inputSchema": {
                                    "type": "object",
                                    "properties": {
                                        "query": {"type": "string"}
                                    },
                                    "required": ["query"]
                                }
                            }
                        ]
                    }
                }), flush=True)
            elif method == "tools/call":
                query = message.get("params", {}).get("arguments", {}).get("query", "")
                print(json.dumps({
                    "jsonrpc": "2.0",
                    "id": message["id"],
                    "result": {
                        "content": [
                            {"type": "text", "text": "Local result for " + query}
                        ],
                        "structuredContent": {"count": 1}
                    }
                }), flush=True)
        """#
        try script.write(to: scriptURL, atomically: true, encoding: .utf8)
        return scriptURL
    }
}

private actor RequestRecorder {
    private(set) var requests: [URLRequest] = []

    func record(_ request: URLRequest) {
        requests.append(request)
    }
}
