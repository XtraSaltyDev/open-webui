import Foundation

struct LocalToolInvocationRequest: Equatable, Sendable {
    var tool: AppTool
    var functionName: String
    var arguments: JSONValue
    var argumentsBody: String
    var timeoutSeconds: Double

    init(
        tool: AppTool,
        functionName: String,
        arguments: JSONValue = .object([:]),
        argumentsBody: String = "{}",
        timeoutSeconds: Double = 10
    ) {
        self.tool = tool
        self.functionName = functionName
        self.arguments = arguments
        self.argumentsBody = argumentsBody
        self.timeoutSeconds = timeoutSeconds
    }
}

struct AppToolRun: Identifiable, Codable, Equatable, Sendable {
    var id: UUID
    var toolID: String
    var toolName: String
    var functionName: String
    var argumentsBody: String
    var output: String
    var stderr: String
    var status: CodeExecutionStatus
    var exitCode: Int32?
    var errorMessage: String?
    var startedAt: Date
    var completedAt: Date?

    init(
        id: UUID = UUID(),
        toolID: String,
        toolName: String,
        functionName: String,
        argumentsBody: String,
        output: String,
        stderr: String,
        status: CodeExecutionStatus,
        exitCode: Int32?,
        errorMessage: String? = nil,
        startedAt: Date = Date(),
        completedAt: Date? = nil
    ) {
        self.id = id
        self.toolID = toolID
        self.toolName = toolName
        self.functionName = functionName
        self.argumentsBody = argumentsBody
        self.output = output
        self.stderr = stderr
        self.status = status
        self.exitCode = exitCode
        self.errorMessage = errorMessage
        self.startedAt = startedAt
        self.completedAt = completedAt
    }
}
