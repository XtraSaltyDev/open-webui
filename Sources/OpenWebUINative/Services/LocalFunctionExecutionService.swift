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

    let result = BoundedProcessRunner().run(
        executablePath: "/usr/bin/python3",
        arguments: ["-c", pythonInvocationScript(for: request)],
        workingDirectoryPath: request.workingDirectoryPath,
        stdinData: inputData,
        timeoutSeconds: request.timeoutSeconds,
        maxCapturedOutputBytes: request.maxCapturedOutputBytes ?? CodeExecutionSettings().maxCapturedOutputBytes
    )

    return AppFunctionRun(
        functionID: request.function.id,
        functionName: request.function.name,
        functionKind: request.function.kind,
        methodName: request.methodName,
        inputBody: request.inputBody,
        output: result.stdout,
        stderr: result.stderr,
        status: result.status,
        exitCode: result.exitCode,
        errorMessage: functionRunErrorMessage(status: result.status, stderr: result.stderr),
        startedAt: result.startedAt,
        completedAt: result.completedAt
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
