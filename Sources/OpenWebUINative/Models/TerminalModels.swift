import Foundation

struct AppTerminalSession: Identifiable, Codable, Equatable, Sendable {
    var id: UUID
    var title: String
    var workingDirectoryPath: String?
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        title: String,
        workingDirectoryPath: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.workingDirectoryPath = workingDirectoryPath
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

struct AppTerminalCommand: Identifiable, Codable, Equatable, Sendable {
    var id: UUID
    var sessionID: UUID
    var command: String
    var workingDirectoryPath: String?
    var stdout: String
    var stderr: String
    var status: CodeExecutionStatus
    var exitCode: Int32?
    var startedAt: Date
    var completedAt: Date?

    init(
        id: UUID = UUID(),
        sessionID: UUID,
        command: String,
        workingDirectoryPath: String? = nil,
        stdout: String,
        stderr: String = "",
        status: CodeExecutionStatus,
        exitCode: Int32?,
        startedAt: Date = Date(),
        completedAt: Date? = nil
    ) {
        self.id = id
        self.sessionID = sessionID
        self.command = command
        self.workingDirectoryPath = workingDirectoryPath
        self.stdout = stdout
        self.stderr = stderr
        self.status = status
        self.exitCode = exitCode
        self.startedAt = startedAt
        self.completedAt = completedAt
    }

    var title: String {
        let firstLine = command
            .split(whereSeparator: \.isNewline)
            .first
            .map(String.init)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let title = firstLine?.isEmpty == false ? firstLine! : "Terminal Command"
        return title.count > 60 ? String(title.prefix(60)) : title
    }
}
