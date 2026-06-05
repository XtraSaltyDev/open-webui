import Foundation
import XCTest
@testable import OpenWebUINative

final class CodeExecutionServiceTests: XCTestCase {
    func testShellExecutionCapturesStdoutStderrAndExitCode() async throws {
        let service = CodeExecutionService()

        let run = await service.execute(
            CodeExecutionRequest(
                language: .shell,
                code: "printf 'hello'; >&2 printf 'warning'; exit 7",
                timeoutSeconds: 2
            )
        )

        XCTAssertEqual(run.language, .shell)
        XCTAssertEqual(run.code, "printf 'hello'; >&2 printf 'warning'; exit 7")
        XCTAssertEqual(run.stdout, "hello")
        XCTAssertEqual(run.stderr, "warning")
        XCTAssertEqual(run.exitCode, 7)
        XCTAssertEqual(run.status, .failed)
        XCTAssertNotNil(run.completedAt)
    }

    func testPythonExecutionCapturesStdout() async throws {
        let service = CodeExecutionService()

        let run = await service.execute(
            CodeExecutionRequest(
                language: .python,
                code: "print('native python')",
                timeoutSeconds: 2
            )
        )

        XCTAssertEqual(run.status, .succeeded)
        XCTAssertEqual(run.exitCode, 0)
        XCTAssertEqual(run.stdout.trimmingCharacters(in: .whitespacesAndNewlines), "native python")
        XCTAssertEqual(run.stderr, "")
        XCTAssertTrue(run.stderr.isEmpty)
    }

    func testPythonExecutionTruncatesLargeOutputAtCaptureLimit() async throws {
        let service = CodeExecutionService()

        let run = await service.execute(
            CodeExecutionRequest(
                language: .python,
                code: "print('x' * 200)",
                timeoutSeconds: 2,
                maxCapturedOutputBytes: 64
            )
        )

        XCTAssertEqual(run.status, .succeeded)
        XCTAssertLessThanOrEqual(run.stdout.utf8.count, 64)
        XCTAssertTrue(run.stderr.contains("Output truncated after reaching the 64-byte capture limit."))
    }

    func testExecutionTimeoutTerminatesLongRunningCommand() async throws {
        let service = CodeExecutionService()

        let run = await service.execute(
            CodeExecutionRequest(
                language: .shell,
                code: "sleep 2; printf late",
                timeoutSeconds: 0.1
            )
        )

        XCTAssertEqual(run.status, .timedOut)
        XCTAssertNil(run.exitCode)
        XCTAssertTrue(run.stdout.isEmpty)
        XCTAssertNotNil(run.completedAt)
    }
}

final class CodeExecutionStorageTests: XCTestCase {
    func testSaveAndLoadRunsRoundTripsNewestFirst() async throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let storage = JSONCodeExecutionStorageService(rootURL: rootURL)
        let older = AppCodeExecutionRun(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            language: .shell,
            code: "printf old",
            stdout: "old",
            status: .succeeded,
            exitCode: 0,
            startedAt: Date(timeIntervalSince1970: 100),
            completedAt: Date(timeIntervalSince1970: 101)
        )
        let newer = AppCodeExecutionRun(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
            language: .python,
            code: "print('new')",
            stdout: "new",
            status: .succeeded,
            exitCode: 0,
            startedAt: Date(timeIntervalSince1970: 200),
            completedAt: Date(timeIntervalSince1970: 201)
        )

        try await storage.save(older)
        try await storage.save(newer)

        let loaded = try await storage.loadRuns()

        XCTAssertEqual(loaded.map(\.id), [newer.id, older.id])
        XCTAssertEqual(loaded.first?.language, .python)
        XCTAssertEqual(loaded.first?.stdout, "new")
    }
}
