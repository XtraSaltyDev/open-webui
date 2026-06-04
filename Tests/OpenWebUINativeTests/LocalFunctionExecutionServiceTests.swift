import XCTest
@testable import OpenWebUINative

final class LocalFunctionExecutionServiceTests: XCTestCase {
    func testPythonFunctionInvocationCallsFilterMethodWithJSONInput() async throws {
        let service = LocalFunctionExecutionService()
        let function = AppFunction(
            name: "Safety filter",
            kind: .filter,
            content: """
            def inlet(body):
                return {"message_count": len(body["messages"])}
            """
        )

        let run = await service.invoke(
            LocalFunctionInvocationRequest(
                function: function,
                methodName: "inlet",
                input: .object(["body": .object(["messages": .array([.object([:]), .object([:])])])]),
                inputBody: #"{"body":{"messages":[{},{}]}}"#,
                timeoutSeconds: 2
            )
        )

        XCTAssertEqual(run.status, .succeeded)
        XCTAssertEqual(run.exitCode, 0)
        XCTAssertTrue(run.output.contains(#""message_count": 2"#))
        XCTAssertTrue(run.stderr.isEmpty)
        XCTAssertNil(run.errorMessage)
    }

    func testPythonFunctionInvocationCapturesFailures() async throws {
        let service = LocalFunctionExecutionService()
        let function = AppFunction(
            name: "Broken action",
            kind: .action,
            content: """
            def action(body):
                raise RuntimeError("action unavailable")
            """
        )

        let run = await service.invoke(
            LocalFunctionInvocationRequest(
                function: function,
                methodName: "action",
                input: .object(["body": .object(["model": .string("llama3")])]),
                inputBody: #"{"body":{"model":"llama3"}}"#,
                timeoutSeconds: 2
            )
        )

        XCTAssertEqual(run.status, .failed)
        XCTAssertNotEqual(run.exitCode, 0)
        XCTAssertTrue(run.stderr.contains("action unavailable"))
        XCTAssertNotNil(run.errorMessage)
    }

    func testPythonFunctionInvocationCanReadValvesSchema() async throws {
        let service = LocalFunctionExecutionService()
        let function = AppFunction(
            name: "Configurable filter",
            kind: .filter,
            content: """
            class Valves:
                @staticmethod
                def schema():
                    return {
                        "type": "object",
                        "properties": {
                            "limit": {"type": "integer", "default": 3}
                        }
                    }
            def inlet(body):
                return body
            """
        )

        let run = await service.invoke(
            LocalFunctionInvocationRequest(
                function: function,
                methodName: "__native_valves_schema",
                input: .object([:]),
                inputBody: "{}",
                timeoutSeconds: 2
            )
        )

        XCTAssertEqual(run.status, .succeeded)
        XCTAssertEqual(run.exitCode, 0)
        let data = try XCTUnwrap(run.output.data(using: .utf8))
        let schema = try JSONDecoder.openWebUIDecoder.decode(JSONValue.self, from: data)
        XCTAssertEqual(schema.objectValue?["type"], .string("object"))
        XCTAssertEqual(schema.objectValue?["properties"]?.objectValue?["limit"]?.objectValue?["default"], .number(3))
    }
}

final class JSONFunctionRunStorageServiceTests: XCTestCase {
    func testSaveAndLoadFunctionRunsRoundTripsNewestFirst() async throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let storage = JSONFunctionRunStorageService(rootURL: rootURL)
        let older = AppFunctionRun(
            id: UUID(uuidString: "00000000-0000-0000-0000-0000000000C1")!,
            functionID: "function-a",
            functionName: "Function A",
            functionKind: .filter,
            methodName: "inlet",
            inputBody: "{}",
            output: "old",
            stderr: "",
            status: .succeeded,
            exitCode: 0,
            startedAt: Date(timeIntervalSince1970: 100),
            completedAt: Date(timeIntervalSince1970: 101)
        )
        let newer = AppFunctionRun(
            id: UUID(uuidString: "00000000-0000-0000-0000-0000000000D2")!,
            functionID: "function-b",
            functionName: "Function B",
            functionKind: .pipe,
            methodName: "pipe",
            inputBody: #"{"body":{"model":"pipe"}}"#,
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
        XCTAssertEqual(loaded.first?.functionName, "Function B")
        XCTAssertEqual(loaded.first?.inputBody, #"{"body":{"model":"pipe"}}"#)
    }
}
