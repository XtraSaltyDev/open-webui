import Foundation

protocol LocalFunctionExecuting: Sendable {
    func invoke(_ request: LocalFunctionInvocationRequest) async -> AppFunctionRun
}

struct LocalFunctionExecutionService: LocalFunctionExecuting {
    private let encoder = JSONEncoder.openWebUIEncoder

    func invoke(_ request: LocalFunctionInvocationRequest) async -> AppFunctionRun {
        await Task.detached(priority: .userInitiated) {
            invokeSynchronously(request, encoder: encoder)
        }.value
    }
}

private func invokeSynchronously(_ request: LocalFunctionInvocationRequest, encoder: JSONEncoder) -> AppFunctionRun {
    let startedAt = Date()
    let process = Process()
    let stdoutPipe = Pipe()
    let stderrPipe = Pipe()
    let stdinPipe = Pipe()
    var timedOut = false

    guard let inputData = try? encoder.encode(request.input) else {
        return failedFunctionRun(
            request,
            output: "",
            stderr: "Function input could not be encoded.",
            status: .failed,
            exitCode: nil,
            startedAt: startedAt
        )
    }

    process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
    process.arguments = ["-c", pythonInvocationScript(for: request)]
    process.standardOutput = stdoutPipe
    process.standardError = stderrPipe
    process.standardInput = stdinPipe

    do {
        try process.run()
        stdinPipe.fileHandleForWriting.write(inputData)
        try? stdinPipe.fileHandleForWriting.close()
    } catch {
        return failedFunctionRun(
            request,
            output: "",
            stderr: error.localizedDescription,
            status: .failed,
            exitCode: nil,
            startedAt: startedAt
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

    let output = String(data: stdoutPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
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

    return AppFunctionRun(
        functionID: request.function.id,
        functionName: request.function.name,
        functionKind: request.function.kind,
        methodName: request.methodName,
        inputBody: request.inputBody,
        output: output,
        stderr: stderr,
        status: status,
        exitCode: exitCode,
        errorMessage: functionRunErrorMessage(status: status, stderr: stderr),
        startedAt: startedAt,
        completedAt: Date()
    )
}

private func pythonInvocationScript(for request: LocalFunctionInvocationRequest) -> String {
    """
    import asyncio
    import inspect
    import json
    import sys

    \(request.function.content)

    method_name = \(functionPythonStringLiteral(request.methodName))
    kind_name = \(functionPythonStringLiteral(request.function.kind.rawValue.capitalized))

    if method_name == "__native_valves_schema":
        valves_class = globals().get("Valves")
        if valves_class is None:
            raise AttributeError("Function does not define Valves")
        schema_factory = getattr(valves_class, "model_json_schema", None) or getattr(valves_class, "schema", None)
        if schema_factory is None:
            raise AttributeError("Valves does not define a JSON schema method")
        print(json.dumps(schema_factory()))
        sys.exit(0)

    payload = json.loads(sys.stdin.read() or "{}")

    target = globals().get(method_name)
    if target is None:
        for class_name in ("Function", kind_name):
            candidate = globals().get(class_name)
            if candidate is not None:
                target = getattr(candidate(), method_name, None)
                if target is not None:
                    break

    if target is None:
        raise AttributeError(f"Function method not found: {method_name}")

    result = target(**payload)
    if inspect.isawaitable(result):
        result = asyncio.run(result)
    if inspect.isgenerator(result):
        result = "".join(map(str, result))
    if result is None:
        print("")
    elif isinstance(result, (dict, list, bool, int, float)):
        print(json.dumps(result))
    else:
        print(str(result))
    """
}

private func failedFunctionRun(
    _ request: LocalFunctionInvocationRequest,
    output: String,
    stderr: String,
    status: CodeExecutionStatus,
    exitCode: Int32?,
    startedAt: Date
) -> AppFunctionRun {
    AppFunctionRun(
        functionID: request.function.id,
        functionName: request.function.name,
        functionKind: request.function.kind,
        methodName: request.methodName,
        inputBody: request.inputBody,
        output: output,
        stderr: stderr,
        status: status,
        exitCode: exitCode,
        errorMessage: functionRunErrorMessage(status: status, stderr: stderr),
        startedAt: startedAt,
        completedAt: Date()
    )
}

private func functionRunErrorMessage(status: CodeExecutionStatus, stderr: String) -> String? {
    switch status {
    case .succeeded:
        return nil
    case .failed:
        return stderr.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Function run failed." : stderr
    case .timedOut:
        return "Function run timed out."
    }
}

private func functionPythonStringLiteral(_ value: String) -> String {
    let data = (try? JSONEncoder().encode(value)) ?? Data("\"\(value)\"".utf8)
    return String(data: data, encoding: .utf8) ?? "\"\(value)\""
}
