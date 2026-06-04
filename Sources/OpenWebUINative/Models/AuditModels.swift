import Foundation

enum AppAuditAction: String, Codable, Equatable, Sendable {
    case featureToggleUpdated
    case providerSettingsUpdated
    case analyticsExported
    case codeExecutionRun
    case codeExecutionRunDeleted
    case webSearchRun
    case terminalSessionCreated
    case terminalSessionUpdated
    case terminalSessionDeleted
    case terminalCommandRun
    case terminalCommandDeleted
    case toolServerInvoked
    case toolServerRunDeleted
    case automationRun
    case automationCreated
    case automationUpdated
    case automationStatusUpdated
    case automationDeleted
    case auditLogExported
    case auditEventDeleted
    case workspaceBackupExported
    case workspaceBackupImported
    case feedbackExported
    case feedbackImported
    case feedbackModerationUpdated
    case feedbackDeleted
    case generatedImagesExported
    case generatedImagesImported
    case audioHistoryExported
    case audioHistoryImported
    case promptsExported
    case promptsImported
    case promptCreated
    case promptUpdated
    case promptDeleted
    case toolCreated
    case toolUpdated
    case toolDeleted
    case toolInvoked
    case skillCreated
    case skillUpdated
    case skillDeleted
    case functionCreated
    case functionUpdated
    case functionDeleted
    case functionInvoked
    case adminUserCreated
    case adminUserUpdated
    case adminUserDeleted
    case adminGroupCreated
    case adminGroupUpdated
    case adminGroupMembersUpdated
    case adminGroupDeleted
    case adminDirectoryExported
    case adminDirectoryImported
    case channelCreated
    case channelUpdated
    case channelDeleted
    case channelMemberAdded
    case channelMemberUpdated
    case channelMemberRemoved
    case calendarEventCreated
    case calendarEventUpdated
    case calendarEventDeleted
    case calendarAttendeeAdded
    case calendarAttendeeUpdated
    case calendarAttendeeRemoved
    case noteCreated
    case noteUpdated
    case notePinUpdated
    case noteDeleted

    var label: String {
        switch self {
        case .featureToggleUpdated:
            return "Feature toggle updated"
        case .providerSettingsUpdated:
            return "Provider settings updated"
        case .analyticsExported:
            return "Analytics exported"
        case .codeExecutionRun:
            return "Code execution run"
        case .codeExecutionRunDeleted:
            return "Code execution run deleted"
        case .webSearchRun:
            return "Web search run"
        case .terminalSessionCreated:
            return "Terminal session created"
        case .terminalSessionUpdated:
            return "Terminal session updated"
        case .terminalSessionDeleted:
            return "Terminal session deleted"
        case .terminalCommandRun:
            return "Terminal command run"
        case .terminalCommandDeleted:
            return "Terminal command deleted"
        case .toolServerInvoked:
            return "Tool server invoked"
        case .toolServerRunDeleted:
            return "Tool server run deleted"
        case .automationRun:
            return "Automation run"
        case .automationCreated:
            return "Automation created"
        case .automationUpdated:
            return "Automation updated"
        case .automationStatusUpdated:
            return "Automation status updated"
        case .automationDeleted:
            return "Automation deleted"
        case .auditLogExported:
            return "Audit log exported"
        case .auditEventDeleted:
            return "Audit event deleted"
        case .workspaceBackupExported:
            return "Workspace backup exported"
        case .workspaceBackupImported:
            return "Workspace backup imported"
        case .feedbackExported:
            return "Feedback exported"
        case .feedbackImported:
            return "Feedback imported"
        case .feedbackModerationUpdated:
            return "Feedback moderation updated"
        case .feedbackDeleted:
            return "Feedback deleted"
        case .generatedImagesExported:
            return "Generated images exported"
        case .generatedImagesImported:
            return "Generated images imported"
        case .audioHistoryExported:
            return "Audio history exported"
        case .audioHistoryImported:
            return "Audio history imported"
        case .promptsExported:
            return "Prompts exported"
        case .promptsImported:
            return "Prompts imported"
        case .promptCreated:
            return "Prompt created"
        case .promptUpdated:
            return "Prompt updated"
        case .promptDeleted:
            return "Prompt deleted"
        case .toolCreated:
            return "Tool created"
        case .toolUpdated:
            return "Tool updated"
        case .toolDeleted:
            return "Tool deleted"
        case .toolInvoked:
            return "Tool invoked"
        case .skillCreated:
            return "Skill created"
        case .skillUpdated:
            return "Skill updated"
        case .skillDeleted:
            return "Skill deleted"
        case .functionCreated:
            return "Function created"
        case .functionUpdated:
            return "Function updated"
        case .functionDeleted:
            return "Function deleted"
        case .functionInvoked:
            return "Function invoked"
        case .adminUserCreated:
            return "Admin user created"
        case .adminUserUpdated:
            return "Admin user updated"
        case .adminUserDeleted:
            return "Admin user deleted"
        case .adminGroupCreated:
            return "Admin group created"
        case .adminGroupUpdated:
            return "Admin group updated"
        case .adminGroupMembersUpdated:
            return "Admin group members updated"
        case .adminGroupDeleted:
            return "Admin group deleted"
        case .adminDirectoryExported:
            return "Admin directory exported"
        case .adminDirectoryImported:
            return "Admin directory imported"
        case .channelCreated:
            return "Channel created"
        case .channelUpdated:
            return "Channel updated"
        case .channelDeleted:
            return "Channel deleted"
        case .channelMemberAdded:
            return "Channel member added"
        case .channelMemberUpdated:
            return "Channel member updated"
        case .channelMemberRemoved:
            return "Channel member removed"
        case .calendarEventCreated:
            return "Calendar event created"
        case .calendarEventUpdated:
            return "Calendar event updated"
        case .calendarEventDeleted:
            return "Calendar event deleted"
        case .calendarAttendeeAdded:
            return "Calendar attendee added"
        case .calendarAttendeeUpdated:
            return "Calendar attendee updated"
        case .calendarAttendeeRemoved:
            return "Calendar attendee removed"
        case .noteCreated:
            return "Note created"
        case .noteUpdated:
            return "Note updated"
        case .notePinUpdated:
            return "Note pin updated"
        case .noteDeleted:
            return "Note deleted"
        }
    }
}

enum AppAuditOutcome: String, Codable, Equatable, Sendable {
    case succeeded
    case failed
    case blocked

    var label: String {
        switch self {
        case .succeeded:
            return "Succeeded"
        case .failed:
            return "Failed"
        case .blocked:
            return "Blocked"
        }
    }
}

struct AppAuditEvent: Identifiable, Codable, Equatable, Sendable {
    var id: UUID
    var action: AppAuditAction
    var outcome: AppAuditOutcome
    var summary: String
    var metadata: [String: String]
    var createdAt: Date

    init(
        id: UUID = UUID(),
        action: AppAuditAction,
        outcome: AppAuditOutcome,
        summary: String,
        metadata: [String: String] = [:],
        createdAt: Date = Date()
    ) {
        self.id = id
        self.action = action
        self.outcome = outcome
        self.summary = summary
        self.metadata = metadata
        self.createdAt = createdAt
    }
}
