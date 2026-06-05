import Darwin
import Foundation

struct BoundedProcessResult: Equatable, Sendable {
    var stdout: String
    var stderr: String
    var status: CodeExecutionStatus
    var exitCode: Int32?
    var startedAt: Date
    var completedAt: Date?
    var timedOut: Bool
    var wasCancelled: Bool
    var wasTruncated: Bool
}

struct BoundedProcessRunner: Sendable {
    func run(
        executablePath: String,
        arguments: [String] = [],
        workingDirectoryPath: String? = nil,
        environment: [String: String]? = nil,
        stdinData: Data? = nil,
        timeoutSeconds: Double,
        maxCapturedOutputBytes: Int,
        terminationGraceSeconds: Double = 0.3,
        shouldCancel: @Sendable () -> Bool = { false }
    ) -> BoundedProcessResult {
        let startedAt = Date()
        let process = Process()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        let stdinPipe = Pipe()
        let outputCapture = BoundedProcessOutputCapture(maxCapturedOutputBytes: maxCapturedOutputBytes)

        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments
        if let workingDirectoryPath = workingDirectoryPath?.trimmingCharacters(in: .whitespacesAndNewlines),
           !workingDirectoryPath.isEmpty {
            process.currentDirectoryURL = URL(fileURLWithPath: workingDirectoryPath, isDirectory: true).standardizedFileURL
        }
        if let environment {
            process.environment = ProcessInfo.processInfo.environment.merging(environment) { _, new in
                new
            }
        }
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        if stdinData != nil {
            process.standardInput = stdinPipe
        }

        stdoutPipe.fileHandleForReading.readabilityHandler = { fileHandle in
            let data = fileHandle.availableData
            outputCapture.append(data, to: .stdout)
        }
        stderrPipe.fileHandleForReading.readabilityHandler = { fileHandle in
            let data = fileHandle.availableData
            outputCapture.append(data, to: .stderr)
        }

        do {
            try process.run()
            if let stdinData {
                stdinPipe.fileHandleForWriting.write(stdinData)
                try? stdinPipe.fileHandleForWriting.close()
            }
        } catch {
            stdoutPipe.fileHandleForReading.readabilityHandler = nil
            stderrPipe.fileHandleForReading.readabilityHandler = nil
            try? stdinPipe.fileHandleForWriting.close()
            return BoundedProcessResult(
                stdout: "",
                stderr: error.localizedDescription,
                status: .failed,
                exitCode: nil,
                startedAt: startedAt,
                completedAt: Date(),
                timedOut: false,
                wasCancelled: false,
                wasTruncated: false
            )
        }

        let timeout = max(timeoutSeconds, 0.1)
        let deadline = Date().addingTimeInterval(timeout)
        var timedOut = false
        var wasCancelled = false
        while process.isRunning {
            if shouldCancel() {
                wasCancelled = true
                terminate(process, graceSeconds: terminationGraceSeconds)
                break
            } else if Date() >= deadline {
                timedOut = true
                terminate(process, graceSeconds: terminationGraceSeconds)
                break
            }
            Thread.sleep(forTimeInterval: 0.02)
        }

        if process.isRunning {
            terminate(process, graceSeconds: terminationGraceSeconds)
        }
        process.waitUntilExit()

        stdoutPipe.fileHandleForReading.readabilityHandler = nil
        stderrPipe.fileHandleForReading.readabilityHandler = nil

        let remainingStdout = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        outputCapture.append(remainingStdout, to: .stdout)
        let remainingStderr = stderrPipe.fileHandleForReading.readDataToEndOfFile()
        outputCapture.append(remainingStderr, to: .stderr)

        let snapshot = outputCapture.snapshot()
        let stdout = String(data: snapshot.stdout, encoding: .utf8) ?? ""
        var stderr = String(data: snapshot.stderr, encoding: .utf8) ?? ""
        if snapshot.isTruncated {
            let message = "Output truncated after reaching the \(max(maxCapturedOutputBytes, 1))-byte capture limit."
            stderr = stderr.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? message
                : "\(stderr)\n\(message)"
        }

        let status: CodeExecutionStatus
        let exitCode: Int32?
        if timedOut {
            status = .timedOut
            exitCode = nil
        } else if wasCancelled {
            status = .failed
            exitCode = nil
        } else {
            exitCode = process.terminationStatus
            status = process.terminationStatus == 0 ? .succeeded : .failed
        }

        return BoundedProcessResult(
            stdout: stdout,
            stderr: stderr,
            status: status,
            exitCode: exitCode,
            startedAt: startedAt,
            completedAt: Date(),
            timedOut: timedOut,
            wasCancelled: wasCancelled,
            wasTruncated: snapshot.isTruncated
        )
    }

    private func terminate(_ process: Process, graceSeconds: Double) {
        guard process.isRunning else {
            return
        }
        process.terminate()

        let deadline = Date().addingTimeInterval(max(graceSeconds, 0))
        while process.isRunning, Date() < deadline {
            Thread.sleep(forTimeInterval: 0.02)
        }

        if process.isRunning {
            kill(process.processIdentifier, SIGKILL)
        }
    }
}

private final class BoundedProcessOutputCapture: @unchecked Sendable {
    enum Stream {
        case stdout
        case stderr
    }

    private let maxCapturedOutputBytes: Int
    private let lock = NSLock()
    private var stdout = Data()
    private var stderr = Data()
    private var capturedByteCount = 0
    private var isTruncated = false

    init(maxCapturedOutputBytes: Int) {
        self.maxCapturedOutputBytes = max(maxCapturedOutputBytes, 1)
    }

    func append(_ data: Data, to stream: Stream) {
        guard !data.isEmpty else {
            return
        }

        lock.lock()
        defer {
            lock.unlock()
        }

        let remainingByteCount = maxCapturedOutputBytes - capturedByteCount
        guard remainingByteCount > 0 else {
            isTruncated = true
            return
        }

        let capturedChunkCount = min(data.count, remainingByteCount)
        if capturedChunkCount < data.count {
            isTruncated = true
        }

        let chunk = data.prefix(capturedChunkCount)
        switch stream {
        case .stdout:
            stdout.append(chunk)
        case .stderr:
            stderr.append(chunk)
        }
        capturedByteCount += capturedChunkCount
    }

    func snapshot() -> (stdout: Data, stderr: Data, isTruncated: Bool) {
        lock.lock()
        defer {
            lock.unlock()
        }
        return (stdout, stderr, isTruncated)
    }
}
