import XCTest
@testable import OpenWebUINative

final class LocalToolExecutionServiceTests: XCTestCase {
    func testPythonToolInvocationCallsToolsMethodWithJSONArguments() async throws {
        let service = LocalToolExecutionService()
        let tool = AppTool(
            name: "Weather lookup",
            content: """
            class Tools:
                def get_weather(self, city, unit="f"):
                    return {"city": city, "unit": unit}
            """
        )

        let run = await service.invoke(
            LocalToolInvocationRequest(
                tool: tool,
                functionName: "get_weather",
                arguments: .object(["city": .string("Chicago"), "unit": .string("c")]),
                argumentsBody: #"{"city":"Chicago","unit":"c"}"#,
                timeoutSeconds: 2
            )
        )

        XCTAssertEqual(run.status, .succeeded)
        XCTAssertEqual(run.exitCode, 0)
        XCTAssertTrue(run.output.contains(#""city": "Chicago""#))
        XCTAssertTrue(run.output.contains(#""unit": "c""#))
        XCTAssertTrue(run.stderr.isEmpty)
        XCTAssertNil(run.errorMessage)
    }

    func testPythonToolInvocationCapturesFailures() async throws {
        let service = LocalToolExecutionService()
        let tool = AppTool(
            name: "Broken lookup",
            content: """
            class Tools:
                def get_weather(self, city):
                    raise RuntimeError("weather service unavailable")
            """
        )

        let run = await service.invoke(
            LocalToolInvocationRequest(
                tool: tool,
                functionName: "get_weather",
                arguments: .object(["city": .string("Chicago")]),
                argumentsBody: #"{"city":"Chicago"}"#,
                timeoutSeconds: 2
            )
        )

        XCTAssertEqual(run.status, .failed)
        XCTAssertNotEqual(run.exitCode, 0)
        XCTAssertTrue(run.stderr.contains("weather service unavailable"))
        XCTAssertNotNil(run.errorMessage)
    }

    func testPythonToolInvocationProvidesConfiguredValves() async throws {
        let service = LocalToolExecutionService()
        let tool = AppTool(
            name: "Configurable lookup",
            content: """
            class Tools:
                def get_secret(self):
                    return {"api_key": valves.api_key, "limit": valves.limit}
            """,
            valves: .object(["api_key": .string("secret"), "limit": .number(3)])
        )

        let run = await service.invoke(
            LocalToolInvocationRequest(
                tool: tool,
                functionName: "get_secret",
                arguments: .object([:]),
                argumentsBody: "{}",
                timeoutSeconds: 2
            )
        )

        XCTAssertEqual(run.status, .succeeded)
        XCTAssertEqual(run.exitCode, 0)
        XCTAssertTrue(run.output.contains(#""api_key": "secret""#))
        XCTAssertTrue(run.output.contains(#""limit": 3"#))
    }

    func testPythonToolInvocationCanReadValvesSchema() async throws {
        let service = LocalToolExecutionService()
        let tool = AppTool(
            name: "Configurable lookup",
            content: """
            class Valves:
                @staticmethod
                def schema():
                    return {
                        "type": "object",
                        "properties": {
                            "api_key": {"type": "string", "default": "secret"}
                        }
                    }
            class Tools:
                def get_secret(self):
                    return "ok"
            """
        )

        let run = await service.invoke(
            LocalToolInvocationRequest(
                tool: tool,
                functionName: "__native_valves_schema",
                arguments: .object([:]),
                argumentsBody: "{}",
                timeoutSeconds: 2
            )
        )

        XCTAssertEqual(run.status, .succeeded)
        XCTAssertEqual(run.exitCode, 0)
        let data = try XCTUnwrap(run.output.data(using: .utf8))
        let schema = try JSONDecoder.openWebUIDecoder.decode(JSONValue.self, from: data)
        XCTAssertEqual(schema.objectValue?["type"], .string("object"))
        XCTAssertEqual(schema.objectValue?["properties"]?.objectValue?["api_key"]?.objectValue?["default"], .string("secret"))
    }

    func testPythonToolInvocationDrainsLargeStdoutAndStderrWithoutDeadlock() async throws {
        let service = LocalToolExecutionService()
        let tool = AppTool(
            name: "Noisy lookup",
            content: """
            import sys

            class Tools:
                def noisy(self):
                    sys.stdout.write("o" * 120000)
                    sys.stderr.write("e" * 120000)
                    return "done"
            """
        )

        let run = await service.invoke(
            LocalToolInvocationRequest(
                tool: tool,
                functionName: "noisy",
                arguments: .object([:]),
                argumentsBody: "{}",
                timeoutSeconds: 3,
                maxCapturedOutputBytes: 300_000
            )
        )

        XCTAssertEqual(run.status, .succeeded)
        XCTAssertEqual(run.exitCode, 0)
        XCTAssertGreaterThanOrEqual(run.output.utf8.count, 120_000)
        XCTAssertGreaterThanOrEqual(run.stderr.utf8.count, 120_000)
        XCTAssertNil(run.errorMessage)
    }
}

final class JSONToolRunStorageServiceTests: XCTestCase {
    func testSaveAndLoadToolRunsRoundTripsNewestFirst() async throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let storage = JSONToolRunStorageService(rootURL: rootURL)
        let older = AppToolRun(
            id: UUID(uuidString: "00000000-0000-0000-0000-0000000000A1")!,
            toolID: "tool-a",
            toolName: "Tool A",
            functionName: "run",
            argumentsBody: "{}",
            output: "old",
            stderr: "",
            status: .succeeded,
            exitCode: 0,
            startedAt: Date(timeIntervalSince1970: 100),
            completedAt: Date(timeIntervalSince1970: 101)
        )
        let newer = AppToolRun(
            id: UUID(uuidString: "00000000-0000-0000-0000-0000000000B2")!,
            toolID: "tool-b",
            toolName: "Tool B",
            functionName: "lookup",
            argumentsBody: #"{"q":"new"}"#,
            output: "new",
            stderr: "",
            status: .succeeded,
            exitCode: 0,
            startedAt: Date(timeIntervalSince1970: 200),
            completedAt: Date(timeIntervalSince1970: 201)
        )

        try await storage.save(older)
        try await storage.save(newer)

        let loaded = try await storage.loadRuns()

        XCTAssertEqual(loaded.map(\.id), [newer.id, older.id])
        XCTAssertEqual(loaded.first?.toolName, "Tool B")
        XCTAssertEqual(loaded.first?.argumentsBody, #"{"q":"new"}"#)
    }
}
