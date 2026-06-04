import Foundation

struct AuditEventMetadataRow: Identifiable, Equatable {
    var id: String { key }
    let key: String
    let label: String
    let value: String
}

struct AuditEventMetadataPresentation: Equatable {
    let previewRows: [AuditEventMetadataRow]
    let overflowRows: [AuditEventMetadataRow]

    var overflowCount: Int {
        overflowRows.count
    }
}

enum AuditEventMetadataFormatter {
    private static let preferredKeys: [(key: String, label: String)] = [
        ("error", "Error"),
        ("status", "Status"),
        ("modelID", "Model"),
        ("runID", "Run"),
        ("feedbackID", "Feedback"),
        ("rating", "Rating"),
        ("moderationStatus", "Moderation"),
        ("fromStatus", "From"),
        ("toStatus", "To"),
        ("automationID", "Automation"),
        ("toolName", "Tool"),
        ("serverID", "Server"),
        ("language", "Language"),
        ("feature", "Feature"),
        ("enabled", "Enabled"),
        ("surface", "Surface")
    ]

    private static let feedbackPreferredKeys: [(key: String, label: String)] = [
        ("feedbackID", "Feedback"),
        ("modelID", "Model"),
        ("rating", "Rating"),
        ("moderationStatus", "Moderation"),
        ("fromStatus", "From"),
        ("toStatus", "To")
    ]

    private static let feedbackExportPreferredKeys: [(key: String, label: String)] = [
        ("exportedFeedbackCount", "Feedback"),
        ("exportedPositiveCount", "Positive"),
        ("exportedNegativeCount", "Negative"),
        ("exportedPendingCount", "Pending"),
        ("exportedReviewedCount", "Reviewed"),
        ("exportedDismissedCount", "Dismissed")
    ]

    private static let feedbackImportPreferredKeys: [(key: String, label: String)] = [
        ("importedFeedbackCount", "Feedback"),
        ("importedPositiveCount", "Positive"),
        ("importedNegativeCount", "Negative"),
        ("importedPendingCount", "Pending"),
        ("importedReviewedCount", "Reviewed"),
        ("importedDismissedCount", "Dismissed"),
        ("totalFeedbackCount", "Total Feedback")
    ]

    private static let generatedImagesExportPreferredKeys: [(key: String, label: String)] = [
        ("exportedGeneratedImageCount", "Generated Images"),
        ("exportedOriginalImageCount", "Originals"),
        ("exportedEditedImageCount", "Edits"),
        ("exportedVariationImageCount", "Variations")
    ]

    private static let generatedImagesImportPreferredKeys: [(key: String, label: String)] = [
        ("importedGeneratedImageCount", "Generated Images"),
        ("importedOriginalImageCount", "Originals"),
        ("importedEditedImageCount", "Edits"),
        ("importedVariationImageCount", "Variations"),
        ("totalGeneratedImageCount", "Total Generated Images")
    ]

    private static let webSearchPreferredKeys: [(key: String, label: String)] = [
        ("engine", "Engine"),
        ("status", "Status"),
        ("contactedHosts", "Contacted Hosts"),
        ("usedAPIKey", "Used API Key"),
        ("resultCount", "Results"),
        ("pageContentResultCount", "Page Text Results"),
        ("pageContentLoadingEnabled", "Page Text Loading")
    ]

    private static let codeExecutionPreferredKeys: [(key: String, label: String)] = [
        ("runID", "Run"),
        ("language", "Language"),
        ("status", "Status")
    ]

    private static let terminalPreferredKeys: [(key: String, label: String)] = [
        ("sessionID", "Session"),
        ("commandID", "Command"),
        ("status", "Status"),
        ("deletedCommandCount", "Deleted Commands"),
        ("workingDirectory", "Working Directory")
    ]

    private static let toolServerRunPreferredKeys: [(key: String, label: String)] = [
        ("serverID", "Server"),
        ("serverKind", "Kind"),
        ("runID", "Run"),
        ("toolName", "Tool"),
        ("status", "Status")
    ]

    private static let promptExportPreferredKeys: [(key: String, label: String)] = [
        ("exportedPromptCount", "Prompts"),
        ("exportedCommandPromptCount", "Slash Commands"),
        ("exportedTaggedPromptCount", "Tagged Prompts")
    ]

    private static let promptImportPreferredKeys: [(key: String, label: String)] = [
        ("importedPromptCount", "Prompts"),
        ("importedCommandPromptCount", "Slash Commands"),
        ("importedTaggedPromptCount", "Tagged Prompts"),
        ("totalPromptCount", "Total Prompts")
    ]

    private static let analyticsExportPreferredKeys: [(key: String, label: String)] = [
        ("exportedChatCount", "Chats"),
        ("exportedMessageCount", "Messages"),
        ("exportedModelCount", "Models"),
        ("exportedFeedbackCount", "Feedback"),
        ("exportedKnowledgeCollectionCount", "Knowledge Collections"),
        ("exportedKnowledgeDocumentCount", "Knowledge Documents"),
        ("exportedChannelCount", "Channels"),
        ("exportedNoteCount", "Notes"),
        ("exportedAutomationCount", "Automations"),
        ("exportedCalendarCount", "Calendars"),
        ("exportedCalendarEventCount", "Calendar Events"),
        ("exportedWebSearchRunCount", "Web Search Runs"),
        ("exportedWebSearchHostCount", "Web Search Hosts"),
        ("exportedWebSearchAPIKeyRunCount", "Web Search API Key Runs"),
        ("exportedWebSearchFailedRunCount", "Web Search Failed Runs"),
        ("exportedWebSearchBlockedRunCount", "Web Search Blocked Runs")
    ]

    private static let auditLogExportPreferredKeys: [(key: String, label: String)] = [
        ("exportedAuditEventCount", "Exported Events"),
        ("includedExportEvent", "Includes Export Event")
    ]

    private static let promptPreferredKeys: [(key: String, label: String)] = [
        ("promptID", "Prompt"),
        ("title", "Title"),
        ("fromTitle", "From"),
        ("command", "Command"),
        ("tags", "Tags")
    ]

    private static let toolPreferredKeys: [(key: String, label: String)] = [
        ("toolID", "Tool"),
        ("name", "Name"),
        ("fromName", "From"),
        ("description", "Description")
    ]

    private static let skillPreferredKeys: [(key: String, label: String)] = [
        ("skillID", "Skill"),
        ("name", "Name"),
        ("fromName", "From"),
        ("description", "Description"),
        ("tags", "Tags"),
        ("isActive", "Active")
    ]

    private static let functionPreferredKeys: [(key: String, label: String)] = [
        ("functionID", "Function"),
        ("name", "Name"),
        ("fromName", "From"),
        ("kind", "Kind"),
        ("description", "Description"),
        ("isActive", "Active"),
        ("isGlobal", "Global")
    ]

    private static let adminUserPreferredKeys: [(key: String, label: String)] = [
        ("userID", "User"),
        ("name", "Name"),
        ("fromName", "From"),
        ("email", "Email"),
        ("fromEmail", "From Email"),
        ("role", "Role"),
        ("fromRole", "From Role"),
        ("removedFromGroupCount", "Removed From Groups")
    ]

    private static let adminGroupPreferredKeys: [(key: String, label: String)] = [
        ("groupID", "Group"),
        ("name", "Name"),
        ("fromName", "From"),
        ("description", "Description"),
        ("permissions", "Permissions"),
        ("memberCount", "Members"),
        ("fromMemberCount", "From Members")
    ]

    private static let adminDirectoryExportPreferredKeys: [(key: String, label: String)] = [
        ("exportedUserCount", "Exported Users"),
        ("exportedGroupCount", "Exported Groups")
    ]

    private static let adminDirectoryPreferredKeys: [(key: String, label: String)] = [
        ("importedUserCount", "Imported Users"),
        ("importedGroupCount", "Imported Groups"),
        ("totalUserCount", "Total Users"),
        ("totalGroupCount", "Total Groups")
    ]

    private static let workspaceBackupExportPreferredKeys: [(key: String, label: String)] = [
        ("exportedThreadCount", "Threads"),
        ("exportedFolderCount", "Folders"),
        ("exportedPromptCount", "Prompts"),
        ("exportedNoteCount", "Notes"),
        ("exportedKnowledgeCollectionCount", "Knowledge Collections"),
        ("exportedKnowledgeDocumentCount", "Knowledge Documents"),
        ("exportedToolCount", "Tools"),
        ("exportedToolServerCount", "Tool Servers"),
        ("exportedFunctionCount", "Functions"),
        ("exportedSkillCount", "Skills"),
        ("exportedFeedbackCount", "Feedback"),
        ("exportedAdminUserCount", "Admin Users"),
        ("exportedAdminGroupCount", "Admin Groups"),
        ("exportedChannelCount", "Channels"),
        ("exportedAutomationCount", "Automations"),
        ("exportedCalendarCount", "Calendars"),
        ("exportedCalendarEventCount", "Calendar Events"),
        ("exportedPlaygroundRunCount", "Playground Runs"),
        ("exportedGeneratedImageCount", "Generated Images"),
        ("exportedCodeExecutionRunCount", "Code Runs"),
        ("exportedAudioHistoryCount", "Audio History"),
        ("exportedAuditEventCount", "Audit Events"),
        ("excludedSecrets", "Secrets Excluded")
    ]

    private static let workspaceBackupImportPreferredKeys: [(key: String, label: String)] = [
        ("importedThreadCount", "Threads"),
        ("importedFolderCount", "Folders"),
        ("importedPromptCount", "Prompts"),
        ("importedNoteCount", "Notes"),
        ("importedKnowledgeCollectionCount", "Knowledge Collections"),
        ("importedKnowledgeDocumentCount", "Knowledge Documents"),
        ("importedToolCount", "Tools"),
        ("importedToolServerCount", "Tool Servers"),
        ("importedFunctionCount", "Functions"),
        ("importedSkillCount", "Skills"),
        ("importedFeedbackCount", "Feedback"),
        ("importedAdminUserCount", "Admin Users"),
        ("importedAdminGroupCount", "Admin Groups"),
        ("importedChannelCount", "Channels"),
        ("importedAutomationCount", "Automations"),
        ("importedCalendarCount", "Calendars"),
        ("importedCalendarEventCount", "Calendar Events"),
        ("importedPlaygroundRunCount", "Playground Runs"),
        ("importedGeneratedImageCount", "Generated Images"),
        ("importedCodeExecutionRunCount", "Code Runs"),
        ("importedAudioHistoryCount", "Audio History"),
        ("importedAuditEventCount", "Audit Events"),
        ("excludedSecrets", "Secrets Excluded")
    ]

    static func rows(for event: AppAuditEvent) -> [AuditEventMetadataRow] {
        let orderedKeys = preferredKeys(for: event)
        let preferredRows = orderedKeys.compactMap { entry -> AuditEventMetadataRow? in
            guard let value = event.metadata[entry.key], !value.isEmpty else {
                return nil
            }
            return AuditEventMetadataRow(key: entry.key, label: entry.label, value: value)
        }
        let preferredKeySet = Set(orderedKeys.map(\.key))
        let remainingRows = event.metadata
            .filter { !preferredKeySet.contains($0.key) && !$0.value.isEmpty }
            .sorted { $0.key.localizedStandardCompare($1.key) == .orderedAscending }
            .map { key, value in
                AuditEventMetadataRow(key: key, label: titleLabel(for: key), value: value)
            }

        return preferredRows + remainingRows
    }

    static func presentation(for event: AppAuditEvent, previewLimit: Int = 4) -> AuditEventMetadataPresentation {
        let rows = rows(for: event)
        let limit = max(0, previewLimit)
        return AuditEventMetadataPresentation(
            previewRows: Array(rows.prefix(limit)),
            overflowRows: Array(rows.dropFirst(limit))
        )
    }

    private static func preferredKeys(for event: AppAuditEvent) -> [(key: String, label: String)] {
        switch event.action {
        case .analyticsExported:
            return analyticsExportPreferredKeys
        case .auditLogExported:
            return auditLogExportPreferredKeys
        case .feedbackExported:
            return feedbackExportPreferredKeys
        case .feedbackImported:
            return feedbackImportPreferredKeys
        case .generatedImagesExported:
            return generatedImagesExportPreferredKeys
        case .generatedImagesImported:
            return generatedImagesImportPreferredKeys
        case .webSearchRun:
            return webSearchPreferredKeys
        case .codeExecutionRun, .codeExecutionRunDeleted:
            return codeExecutionPreferredKeys
        case .terminalSessionCreated, .terminalSessionUpdated, .terminalSessionDeleted, .terminalCommandRun, .terminalCommandDeleted:
            return terminalPreferredKeys
        case .toolServerInvoked, .toolServerRunDeleted:
            return toolServerRunPreferredKeys
        case .promptsExported:
            return promptExportPreferredKeys
        case .promptsImported:
            return promptImportPreferredKeys
        case .feedbackModerationUpdated, .feedbackDeleted:
            return feedbackPreferredKeys
        case .promptCreated, .promptUpdated, .promptDeleted:
            return promptPreferredKeys
        case .toolCreated, .toolUpdated, .toolDeleted:
            return toolPreferredKeys
        case .skillCreated, .skillUpdated, .skillDeleted:
            return skillPreferredKeys
        case .functionCreated, .functionUpdated, .functionDeleted:
            return functionPreferredKeys
        case .adminUserCreated, .adminUserUpdated, .adminUserDeleted:
            return adminUserPreferredKeys
        case .adminGroupCreated, .adminGroupUpdated, .adminGroupMembersUpdated, .adminGroupDeleted:
            return adminGroupPreferredKeys
        case .adminDirectoryExported:
            return adminDirectoryExportPreferredKeys
        case .adminDirectoryImported:
            return adminDirectoryPreferredKeys
        case .workspaceBackupExported:
            return workspaceBackupExportPreferredKeys
        case .workspaceBackupImported:
            return workspaceBackupImportPreferredKeys
        default:
            return preferredKeys
        }
    }

    private static func titleLabel(for key: String) -> String {
        words(from: key)
            .map { word in
                if word.uppercased() == word {
                    return word
                }
                return word.prefix(1).uppercased() + word.dropFirst()
            }
            .joined(separator: " ")
    }

    private static func words(from key: String) -> [String] {
        let normalizedKey = key
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
        var words: [String] = []
        var current = ""
        let scalars = Array(normalizedKey.unicodeScalars)

        for index in scalars.indices {
            let scalar = scalars[index]
            let character = Character(scalar)
            let nextIndex = scalars.index(after: index)
            let nextScalar = nextIndex < scalars.endIndex ? scalars[nextIndex] : nil
            if CharacterSet.whitespacesAndNewlines.contains(scalar) {
                if !current.isEmpty {
                    words.append(current)
                    current = ""
                }
                continue
            }

            if !current.isEmpty,
               shouldStartNewWord(before: scalar, current: current, next: nextScalar) {
                words.append(current)
                current = String(character)
            } else {
                current.append(character)
            }
        }

        if !current.isEmpty {
            words.append(current)
        }
        return words
    }

    private static func shouldStartNewWord(before scalar: Unicode.Scalar, current: String, next: Unicode.Scalar?) -> Bool {
        guard CharacterSet.uppercaseLetters.contains(scalar),
              let previous = current.unicodeScalars.last else {
            return false
        }

        if CharacterSet.lowercaseLetters.contains(previous) {
            return true
        }

        return CharacterSet.uppercaseLetters.contains(previous)
            && next.map { CharacterSet.lowercaseLetters.contains($0) } == true
    }
}
