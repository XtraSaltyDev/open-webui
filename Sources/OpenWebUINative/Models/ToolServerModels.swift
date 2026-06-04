import Foundation

enum AppToolServerKind: String, CaseIterable, Codable, Equatable, Sendable {
    case stdio
    case http

    var label: String {
        switch self {
        case .stdio:
            return "Stdio"
        case .http:
            return "HTTP"
        }
    }
}

struct AppToolServer: Identifiable, Codable, Equatable, Sendable {
    var id: String
    var name: String
    var kind: AppToolServerKind
    var command: String?
    var arguments: [String]
    var baseURL: String?
    var environment: [String: String]
    var isEnabled: Bool
    var createdAt: Date
    var updatedAt: Date

    init(
        id: String = UUID().uuidString,
        name: String,
        kind: AppToolServerKind,
        command: String? = nil,
        arguments: [String] = [],
        baseURL: String? = nil,
        environment: [String: String] = [:],
        isEnabled: Bool = true,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.kind = kind
        self.command = command
        self.arguments = arguments
        self.baseURL = baseURL
        self.environment = environment
        self.isEnabled = isEnabled
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

enum ToolServerConnectionStatus: Equatable, Sendable {
    case unknown
    case checking
    case available(String)
    case unavailable(String)

    var label: String {
        switch self {
        case .unknown:
            return "Unknown"
        case .checking:
            return "Checking"
        case .available:
            return "Available"
        case .unavailable:
            return "Unavailable"
        }
    }

    var detail: String? {
        switch self {
        case .unknown, .checking:
            return nil
        case .available(let message), .unavailable(let message):
            return message
        }
    }
}

struct ToolServerCheckResult: Equatable, Sendable {
    var status: ToolServerConnectionStatus
}

struct AppToolServerTool: Identifiable, Codable, Equatable, Sendable {
    var id: String { name }
    var name: String
    var title: String?
    var description: String?
    var inputSchema: JSONValue

    init(
        name: String,
        title: String? = nil,
        description: String? = nil,
        inputSchema: JSONValue = .object([:])
    ) {
        self.name = name
        self.title = title
        self.description = description
        self.inputSchema = inputSchema
    }
}

struct ToolServerToolDiscoveryResult: Equatable, Sendable {
    var status: ToolServerConnectionStatus
    var tools: [AppToolServerTool]
}

struct ToolServerToolCallRequest: Equatable, Sendable {
    var server: AppToolServer
    var toolName: String
    var arguments: JSONValue

    init(server: AppToolServer, toolName: String, arguments: JSONValue = .object([:])) {
        self.server = server
        self.toolName = toolName
        self.arguments = arguments
    }
}

enum ToolServerInvocationStatus: String, Codable, Equatable, Sendable {
    case succeeded
    case failed
}

struct ToolServerInvocationRequest: Equatable, Sendable {
    var server: AppToolServer
    var requestBody: String

    init(server: AppToolServer, requestBody: String = "{}") {
        self.server = server
        self.requestBody = requestBody
    }
}

struct AppToolServerRun: Identifiable, Codable, Equatable, Sendable {
    var id: UUID
    var serverID: String
    var serverName: String
    var serverKind: AppToolServerKind
    var requestBody: String
    var responseBody: String
    var statusCode: Int?
    var status: ToolServerInvocationStatus
    var errorMessage: String?
    var startedAt: Date
    var completedAt: Date?

    init(
        id: UUID = UUID(),
        serverID: String,
        serverName: String,
        serverKind: AppToolServerKind,
        requestBody: String,
        responseBody: String,
        statusCode: Int?,
        status: ToolServerInvocationStatus,
        errorMessage: String? = nil,
        startedAt: Date = Date(),
        completedAt: Date? = nil
    ) {
        self.id = id
        self.serverID = serverID
        self.serverName = serverName
        self.serverKind = serverKind
        self.requestBody = requestBody
        self.responseBody = responseBody
        self.statusCode = statusCode
        self.status = status
        self.errorMessage = errorMessage
        self.startedAt = startedAt
        self.completedAt = completedAt
    }

    var title: String {
        "\(serverName) \(status.rawValue)"
    }
}
