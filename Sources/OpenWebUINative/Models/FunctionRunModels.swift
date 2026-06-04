import Foundation

struct LocalFunctionInvocationRequest: Equatable, Sendable {
    var function: AppFunction
    var methodName: String
    var input: JSONValue
    var inputBody: String
    var timeoutSeconds: Double

    init(
        function: AppFunction,
        methodName: String,
        input: JSONValue = .object([:]),
        inputBody: String = "{}",
        timeoutSeconds: Double = 10
    ) {
        self.function = function
        self.methodName = methodName
        self.input = input
        self.inputBody = inputBody
        self.timeoutSeconds = timeoutSeconds
    }
}

struct AppFunctionRun: Identifiable, Codable, Equatable, Sendable {
    var id: UUID
    var functionID: String
    var functionName: String
    var functionKind: AppFunctionKind
    var methodName: String
    var inputBody: String
    var output: String
    var stderr: String
    var status: CodeExecutionStatus
    var exitCode: Int32?
    var errorMessage: String?
    var startedAt: Date
    var completedAt: Date?

    init(
        id: UUID = UUID(),
        functionID: String,
        functionName: String,
        functionKind: AppFunctionKind,
        methodName: String,
        inputBody: String,
        output: String,
        stderr: String,
        status: CodeExecutionStatus,
        exitCode: Int32?,
        errorMessage: String? = nil,
        startedAt: Date = Date(),
        completedAt: Date? = nil
    ) {
        self.id = id
        self.functionID = functionID
        self.functionName = functionName
        self.functionKind = functionKind
        self.methodName = methodName
        self.inputBody = inputBody
        self.output = output
        self.stderr = stderr
        self.status = status
        self.exitCode = exitCode
        self.errorMessage = errorMessage
        self.startedAt = startedAt
        self.completedAt = completedAt
    }
}
