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
        process.currentDirectoryURL = URL(fileURLWithPath: path, isDirectory: true)
    }

    process.standardOutput = stdoutPipe
    process.standardError = stderrPipe

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

    let stdout = String(data: stdoutPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    let stderr = String(data: stderrPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
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
