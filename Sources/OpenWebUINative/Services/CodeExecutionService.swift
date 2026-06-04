import Foundation

protocol CodeExecuting: Sendable {
    func execute(_ request: CodeExecutionRequest) async -> AppCodeExecutionRun
}

struct CodeExecutionService: CodeExecuting {
    func execute(_ request: CodeExecutionRequest) async -> AppCodeExecutionRun {
        await Task.detached(priority: .userInitiated) {
            executeSynchronously(request)
        }.value
    }
}

private func executeSynchronously(_ request: CodeExecutionRequest) -> AppCodeExecutionRun {
    let startedAt = Date()
    let process = Process()
    let stdoutPipe = Pipe()
    let stderrPipe = Pipe()
    let maxCapturedOutputBytes = max(
        request.maxCapturedOutputBytes ?? CodeExecutionSettings().maxCapturedOutputBytes,
        1
    )
    let outputCapture = ProcessOutputCapture(maxCapturedOutputBytes: maxCapturedOutputBytes)
    var timedOut = false

    switch request.language {
    case .shell:
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-lc", request.code]
    case .python:
        process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        process.arguments = ["-c", request.code]
    }

    if let path = request.workingDirectoryPath?.trimmingCharacters(in: .whitespacesAndNewlines),
       !path.isEmpty {
        process.currentDirectoryURL = URL(fileURLWithPath: path, isDirectory: true).standardizedFileURL
    }

    process.standardOutput = stdoutPipe
    process.standardError = stderrPipe

    stdoutPipe.fileHandleForReading.readabilityHandler = { fileHandle in
        let data = fileHandle.availableData
        guard !data.isEmpty else {
            return
        }

        if outputCapture.append(data, to: .stdout) {
            process.terminate()
        }
    }

    stderrPipe.fileHandleForReading.readabilityHandler = { fileHandle in
        let data = fileHandle.availableData
        guard !data.isEmpty else {
            return
        }

        if outputCapture.append(data, to: .stderr) {
            process.terminate()
        }
    }

    do {
        try process.run()
    } catch {
        return AppCodeExecutionRun(
            language: request.language,
            code: request.code,
            workingDirectoryPath: request.workingDirectoryPath,
            stdout: "",
            stderr: error.localizedDescription,
            status: .failed,
            exitCode: nil,
            startedAt: startedAt,
            completedAt: Date()
        )
    }

    let timeout = max(request.timeoutSeconds, 0.1)
    let deadline = Date().addingTimeInterval(timeout)
    while process.isRunning {
        if Date() >= deadline {
            timedOut = true
            process.terminate()
            break
        }
        Thread.sleep(forTimeInterval: 0.02)
    }

    process.waitUntilExit()

    stdoutPipe.fileHandleForReading.readabilityHandler = nil
    stderrPipe.fileHandleForReading.readabilityHandler = nil

    if let remainingStdout = try? stdoutPipe.fileHandleForReading.readToEnd(),
       !remainingStdout.isEmpty {
        _ = outputCapture.append(remainingStdout, to: .stdout)
    }

    if let remainingStderr = try? stderrPipe.fileHandleForReading.readToEnd(),
       !remainingStderr.isEmpty {
        _ = outputCapture.append(remainingStderr, to: .stderr)
    }

    let capturedOutput = outputCapture.snapshot()
    let stdout = String(data: capturedOutput.stdout, encoding: .utf8) ?? ""
    var stderr = String(data: capturedOutput.stderr, encoding: .utf8) ?? ""
    if capturedOutput.isTruncated {
        let truncationMessage = "Output truncated after reaching the \(maxCapturedOutputBytes)-byte capture limit."
        stderr = stderr.isEmpty ? truncationMessage : "\(stderr)\n\(truncationMessage)"
    }
    let status: CodeExecutionStatus
    let exitCode: Int32?
    if timedOut {
        status = .timedOut
        exitCode = nil
    } else {
        exitCode = process.terminationStatus
        status = process.terminationStatus == 0 ? .succeeded : .failed
    }

    return AppCodeExecutionRun(
        language: request.language,
        code: request.code,
        workingDirectoryPath: request.workingDirectoryPath,
        stdout: stdout,
        stderr: stderr,
        status: status,
        exitCode: exitCode,
        startedAt: startedAt,
        completedAt: Date()
    )
}

private final class ProcessOutputCapture {
    enum Stream {
        case stdout
        case stderr
    }

    private let maxCapturedOutputBytes: Int
    private let lock = NSLock()
    private var stdout = Data()
    private var stderr = Data()
    private var capturedBytes = 0
    private var isTruncated = false

    init(maxCapturedOutputBytes: Int) {
        self.maxCapturedOutputBytes = max(maxCapturedOutputBytes, 1)
    }

    func append(_ data: Data, to stream: Stream) -> Bool {
        lock.lock()
        defer { lock.unlock() }

        guard !data.isEmpty else {
            return false
        }

        let remainingBytes = maxCapturedOutputBytes - capturedBytes
        guard remainingBytes > 0 else {
            isTruncated = true
            return true
        }

        let capturedChunkCount = min(remainingBytes, data.count)
        if capturedChunkCount > 0 {
            let chunk = data.prefix(capturedChunkCount)
            switch stream {
            case .stdout:
                stdout.append(chunk)
            case .stderr:
                stderr.append(chunk)
            }
            capturedBytes += capturedChunkCount
        }

        if capturedChunkCount < data.count {
            isTruncated = true
            return true
        }

        return false
    }

    func snapshot() -> (stdout: Data, stderr: Data, isTruncated: Bool) {
        lock.lock()
        defer { lock.unlock() }
        return (stdout, stderr, isTruncated)
    }
}
