import Foundation
import XCTest
@testable import OpenWebUINative

final class BoundedProcessRunnerTests: XCTestCase {
    func testRunnerDrainsLargeStdoutAndStderrWithoutDeadlock() throws {
        let runner = BoundedProcessRunner()

        let result = runner.run(
            executablePath: "/usr/bin/python3",
            arguments: [
                "-c",
                "import sys; sys.stdout.write('o' * 200000); sys.stderr.write('e' * 200000)"
            ],
            timeoutSeconds: 3,
            maxCapturedOutputBytes: 500_000
        )

        XCTAssertEqual(result.status, .succeeded)
        XCTAssertEqual(result.exitCode, 0)
        XCTAssertEqual(result.stdout.utf8.count, 200_000)
        XCTAssertEqual(result.stderr.utf8.count, 200_000)
        XCTAssertFalse(result.timedOut)
        XCTAssertFalse(result.wasTruncated)
    }

    func testRunnerTimeoutTerminatesProcess() throws {
        let runner = BoundedProcessRunner()

        let result = runner.run(
            executablePath: "/usr/bin/python3",
            arguments: ["-c", "import time; time.sleep(5)"],
            timeoutSeconds: 0.1,
            maxCapturedOutputBytes: 1_024
        )

        XCTAssertEqual(result.status, .timedOut)
        XCTAssertNil(result.exitCode)
        XCTAssertTrue(result.timedOut)
        XCTAssertNotNil(result.completedAt)
    }

    func testRunnerTruncatesCapturedOutputAndRecordsTruncation() throws {
        let runner = BoundedProcessRunner()

        let result = runner.run(
            executablePath: "/usr/bin/python3",
            arguments: ["-c", "print('x' * 200)"],
            timeoutSeconds: 3,
            maxCapturedOutputBytes: 64
        )

        XCTAssertEqual(result.status, .succeeded)
        XCTAssertEqual(result.exitCode, 0)
        XCTAssertLessThanOrEqual(result.stdout.utf8.count, 64)
        XCTAssertTrue(result.stderr.contains("Output truncated after reaching the 64-byte capture limit."))
        XCTAssertTrue(result.wasTruncated)
    }

    func testRunnerUsesConfiguredWorkingDirectory() throws {
        let runner = BoundedProcessRunner()
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let result = runner.run(
            executablePath: "/bin/pwd",
            workingDirectoryPath: directory.path,
            timeoutSeconds: 3,
            maxCapturedOutputBytes: 1_024
        )

        XCTAssertEqual(result.status, .succeeded)
        let reportedDirectory = URL(
            fileURLWithPath: result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        .resolvingSymlinksInPath()
        .path
        XCTAssertEqual(reportedDirectory, directory.resolvingSymlinksInPath().path)
    }
}
