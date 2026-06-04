import XCTest
@testable import OpenWebUINative

final class ToolServerCheckServiceTests: XCTestCase {
    func testStdioServerIsAvailableWhenCommandCanBeResolved() async {
        let service = ToolServerCheckService(
            commandResolver: { command in command == "uvx" },
            httpStatusLoader: { _ in 200 }
        )
        let server = AppToolServer(name: "Local MCP", kind: .stdio, command: "uvx")

        let result = await service.check(server)

        XCTAssertEqual(result.status, .available("Command is available: uvx"))
    }

    func testStdioServerIsUnavailableWhenCommandCannotBeResolved() async {
        let service = ToolServerCheckService(
            commandResolver: { _ in false },
            httpStatusLoader: { _ in 200 }
        )
        let server = AppToolServer(name: "Missing MCP", kind: .stdio, command: "missing-mcp")

        let result = await service.check(server)

        XCTAssertEqual(result.status, .unavailable("Command not found: missing-mcp"))
    }

    func testHTTPServerIsAvailableForSuccessfulResponse() async {
        let service = ToolServerCheckService(
            commandResolver: { _ in false },
            httpStatusLoader: { url in
                XCTAssertEqual(url.absoluteString, "http://localhost:4444/mcp")
                return 204
            }
        )
        let server = AppToolServer(name: "Gateway", kind: .http, baseURL: "http://localhost:4444/mcp")

        let result = await service.check(server)

        XCTAssertEqual(result.status, .available("HTTP 204"))
    }

    func testHTTPServerIsUnavailableForServerErrors() async {
        let service = ToolServerCheckService(
            commandResolver: { _ in false },
            httpStatusLoader: { _ in 503 }
        )
        let server = AppToolServer(name: "Gateway", kind: .http, baseURL: "http://localhost:4444/mcp")

        let result = await service.check(server)

        XCTAssertEqual(result.status, .unavailable("HTTP 503"))
    }

    func testHTTPServerIsUnavailableForInvalidURL() async {
        let service = ToolServerCheckService(
            commandResolver: { _ in false },
            httpStatusLoader: { _ in 200 }
        )
        let server = AppToolServer(name: "Gateway", kind: .http, baseURL: "not a url")

        let result = await service.check(server)

        XCTAssertEqual(result.status, .unavailable("Invalid URL."))
    }
}
