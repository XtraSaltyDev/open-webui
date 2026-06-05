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
    let maxCapturedOutputBytes = max(
        request.maxCapturedOutputBytes ?? CodeExecutionSettings().maxCapturedOutputBytes,
        1
    )
    let executablePath: String
    let arguments: [String]
    switch request.language {
    case .shell:
        executablePath = "/bin/zsh"
        arguments = ["-lc", request.code]
    case .python:
        executablePath = "/usr/bin/python3"
        arguments = ["-c", request.code]
    }

    let result = BoundedProcessRunner().run(
        executablePath: executablePath,
        arguments: arguments,
        workingDirectoryPath: request.workingDirectoryPath,
        timeoutSeconds: request.timeoutSeconds,
        maxCapturedOutputBytes: maxCapturedOutputBytes
    )

    return AppCodeExecutionRun(
        language: request.language,
        code: request.code,
        workingDirectoryPath: request.workingDirectoryPath,
        stdout: result.stdout,
        stderr: result.stderr,
        status: result.status,
        exitCode: result.exitCode,
        startedAt: result.startedAt,
        completedAt: result.completedAt
    )
}
