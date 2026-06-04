import Foundation

protocol LocalToolExecuting: Sendable {
    func invoke(_ request: LocalToolInvocationRequest) async -> AppToolRun
}

struct LocalToolExecutionService: LocalToolExecuting {
    private let encoder = JSONEncoder.openWebUIEncoder

    func invoke(_ request: LocalToolInvocationRequest) async -> AppToolRun {
        await Task.detached(priority: .userInitiated) {
            invokeSynchronously(request, encoder: encoder)
        }.value
    }
}

private func invokeSynchronously(_ request: LocalToolInvocationRequest, encoder: JSONEncoder) -> AppToolRun {
    let startedAt = Date()
    let process = Process()
    let stdoutPipe = Pipe()
    let stderrPipe = Pipe()
    let stdinPipe = Pipe()
    var timedOut = false

    guard let argumentsData = try? encoder.encode(request.arguments) else {
        return failedToolRun(
            request,
            output: "",
            stderr: "Tool arguments could not be encoded.",
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
        stdinPipe.fileHandleForWriting.write(argumentsData)
        try? stdinPipe.fileHandleForWriting.close()
    } catch {
        return failedToolRun(
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

    return AppToolRun(
        toolID: request.tool.id,
        toolName: request.tool.name,
        functionName: request.functionName,
        argumentsBody: request.argumentsBody,
        output: output,
        stderr: stderr,
        status: status,
        exitCode: exitCode,
        errorMessage: toolRunErrorMessage(status: status, stderr: stderr),
        startedAt: startedAt,
        completedAt: Date()
    )
}

private func pythonInvocationScript(for request: LocalToolInvocationRequest) -> String {
    """
    import json
    import sys
    from types import SimpleNamespace

    \(request.tool.content)

    function_name = \(pythonStringLiteral(request.functionName))
    if function_name == "__native_valves_schema":
        valves_class = globals().get("Valves")
        if valves_class is None:
            raise AttributeError("Tool does not define Valves")
        schema_factory = getattr(valves_class, "model_json_schema", None) or getattr(valves_class, "schema", None)
        if schema_factory is None:
            raise AttributeError("Valves does not define a JSON schema method")
        print(json.dumps(schema_factory()))
        sys.exit(0)

    valves_payload = json.loads(\(pythonStringLiteral(jsonString(for: request.tool.valves ?? .object([:]))))
    )
    valves_class = globals().get("Valves")
    if valves_class is not None:
        try:
            valves = valves_class(**valves_payload)
        except Exception:
            valves = SimpleNamespace(**valves_payload)
    else:
        valves = SimpleNamespace(**valves_payload)

    arguments = json.loads(sys.stdin.read() or "{}")
    tools = Tools()
    function = getattr(tools, function_name)
    result = function(**arguments)
    if result is None:
        print("")
    elif isinstance(result, (dict, list, bool, int, float)):
        print(json.dumps(result))
    else:
        print(str(result))
    """
}

private func jsonString(for value: JSONValue) -> String {
    guard let data = try? JSONEncoder.openWebUIEncoder.encode(value),
          let string = String(data: data, encoding: .utf8) else {
        return "{}"
    }
    return string
}

private func failedToolRun(
    _ request: LocalToolInvocationRequest,
    output: String,
    stderr: String,
    status: CodeExecutionStatus,
    exitCode: Int32?,
    startedAt: Date
) -> AppToolRun {
    AppToolRun(
        toolID: request.tool.id,
        toolName: request.tool.name,
        functionName: request.functionName,
        argumentsBody: request.argumentsBody,
        output: output,
        stderr: stderr,
        status: status,
        exitCode: exitCode,
        errorMessage: toolRunErrorMessage(status: status, stderr: stderr),
        startedAt: startedAt,
        completedAt: Date()
    )
}

private func toolRunErrorMessage(status: CodeExecutionStatus, stderr: String) -> String? {
    switch status {
    case .succeeded:
        return nil
    case .failed:
        return stderr.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Tool run failed." : stderr
    case .timedOut:
        return "Tool run timed out."
    }
}

private func pythonStringLiteral(_ value: String) -> String {
    let data = (try? JSONEncoder().encode(value)) ?? Data("\"\(value)\"".utf8)
    return String(data: data, encoding: .utf8) ?? "\"\(value)\""
}
