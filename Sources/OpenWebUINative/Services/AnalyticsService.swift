import Foundation

struct AnalyticsModelUsage: Identifiable, Codable, Equatable, Sendable {
    var id: String { modelID }
    var modelID: String
    var messageCount: Int
    var chatCount: Int
    var promptTokens: Int
    var completionTokens: Int
    var totalTokens: Int

    init(
        modelID: String,
        messageCount: Int,
        chatCount: Int,
        promptTokens: Int = 0,
        completionTokens: Int = 0,
        totalTokens: Int = 0
    ) {
        self.modelID = modelID
        self.messageCount = messageCount
        self.chatCount = chatCount
        self.promptTokens = promptTokens
        self.completionTokens = completionTokens
        self.totalTokens = totalTokens
    }
}

struct AnalyticsDailyModelUsage: Identifiable, Codable, Equatable, Sendable {
    var id: String { date }
    var date: String
    var models: [String: Int]
}

struct AnalyticsModelChat: Identifiable, Codable, Equatable, Sendable {
    var id: UUID { threadID }
    var threadID: UUID
    var title: String
    var messageCount: Int
    var promptTokens: Int
    var completionTokens: Int
    var totalTokens: Int
    var lastMessageAt: Date
}

struct AnalyticsSummary: Codable, Equatable, Sendable {
    var totalChats: Int
    var activeChats: Int
    var archivedChats: Int
    var pinnedChats: Int
    var totalMessages: Int
    var userMessages: Int
    var assistantMessages: Int
    var systemMessages: Int
    var totalModels: Int
    var totalPromptTokens: Int
    var totalCompletionTokens: Int
    var totalTokens: Int
    var modelUsage: [AnalyticsModelUsage]
    var dailyModelUsage: [AnalyticsDailyModelUsage]
    var feedbackRecords: Int
    var positiveFeedback: Int
    var negativeFeedback: Int
    var knowledgeCollections: Int
    var knowledgeDocuments: Int
    var channels: Int
    var channelMessages: Int
    var channelReplies: Int
    var notes: Int
    var automations: Int
    var activeAutomations: Int
    var calendars: Int
    var calendarEvents: Int

    static let empty = AnalyticsSummary(
        totalChats: 0,
        activeChats: 0,
        archivedChats: 0,
        pinnedChats: 0,
        totalMessages: 0,
        userMessages: 0,
        assistantMessages: 0,
        systemMessages: 0,
        totalModels: 0,
        totalPromptTokens: 0,
        totalCompletionTokens: 0,
        totalTokens: 0,
        modelUsage: [],
        dailyModelUsage: [],
        feedbackRecords: 0,
        positiveFeedback: 0,
        negativeFeedback: 0,
        knowledgeCollections: 0,
        knowledgeDocuments: 0,
        channels: 0,
        channelMessages: 0,
        channelReplies: 0,
        notes: 0,
        automations: 0,
        activeAutomations: 0,
        calendars: 0,
        calendarEvents: 0
    )
}

struct AnalyticsFilter: Codable, Equatable, Sendable {
    var userIDs: Set<String>
    var groupIDs: Set<String>

    init(userIDs: [String] = [], groupIDs: [String] = []) {
        self.userIDs = Set(userIDs.compactMap(Self.normalizedID(_:)))
        self.groupIDs = Set(groupIDs.compactMap(Self.normalizedID(_:)))
    }

    var isActive: Bool {
        !userIDs.isEmpty || !groupIDs.isEmpty
    }

    static let all = AnalyticsFilter()

    private static func normalizedID(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

struct AnalyticsService: Sendable {
    func summary(
        threads: [ChatThread],
        feedbacks: [AppFeedback],
        knowledgeCollections: [KnowledgeCollection],
        knowledgeDocuments: [UUID: [KnowledgeDocument]],
        channels: [AppChannel],
        notes: [AppNote],
        automations: [AppAutomation],
        calendars: [AppCalendar],
        calendarEvents: [AppCalendarEvent],
        adminGroups: [AdminGroup] = [],
        filter: AnalyticsFilter = .all
    ) -> AnalyticsSummary {
        let filteredThreads = Self.filteredThreads(threads, adminGroups: adminGroups, filter: filter)
        var userMessages = 0
        var assistantMessages = 0
        var systemMessages = 0
        var messageCountsByModel: [String: Int] = [:]
        var promptTokensByModel: [String: Int] = [:]
        var completionTokensByModel: [String: Int] = [:]
        var totalTokensByModel: [String: Int] = [:]
        var chatIDsByModel: [String: Set<UUID>] = [:]
        var dailyCountsByModel: [String: [String: Int]] = [:]

        for thread in filteredThreads {
            for modelID in thread.modelIDs where !modelID.isEmpty {
                chatIDsByModel[modelID, default: []].insert(thread.id)
            }

            for message in thread.messages {
                switch message.role {
                case .user:
                    userMessages += 1
                case .assistant:
                    assistantMessages += 1
                case .system:
                    systemMessages += 1
                }

                guard let modelID = message.modelID, !modelID.isEmpty else {
                    continue
                }
                messageCountsByModel[modelID, default: 0] += 1
                chatIDsByModel[modelID, default: []].insert(thread.id)
                dailyCountsByModel[Self.utcDayString(from: message.createdAt), default: [:]][modelID, default: 0] += 1
                if let tokenUsage = message.tokenUsage {
                    promptTokensByModel[modelID, default: 0] += tokenUsage.promptTokens ?? 0
                    completionTokensByModel[modelID, default: 0] += tokenUsage.completionTokens ?? 0
                    totalTokensByModel[modelID, default: 0] += tokenUsage.totalTokens ?? 0
                }
            }
        }

        let modelUsage = messageCountsByModel.map { modelID, messageCount in
            AnalyticsModelUsage(
                modelID: modelID,
                messageCount: messageCount,
                chatCount: chatIDsByModel[modelID]?.count ?? 0,
                promptTokens: promptTokensByModel[modelID] ?? 0,
                completionTokens: completionTokensByModel[modelID] ?? 0,
                totalTokens: totalTokensByModel[modelID] ?? 0
            )
        }
        .sorted { lhs, rhs in
            if lhs.messageCount != rhs.messageCount {
                return lhs.messageCount > rhs.messageCount
            }
            return lhs.modelID.localizedStandardCompare(rhs.modelID) == .orderedAscending
        }

        let dailyModelUsage = dailyCountsByModel.map { date, models in
            AnalyticsDailyModelUsage(date: date, models: models)
        }
        .sorted { lhs, rhs in
            lhs.date.localizedStandardCompare(rhs.date) == .orderedAscending
        }

        let positiveFeedback = feedbacks.filter { $0.data.rating == .positive }.count
        let negativeFeedback = feedbacks.filter { $0.data.rating == .negative }.count
        let totalPromptTokens = promptTokensByModel.values.reduce(0, +)
        let totalCompletionTokens = completionTokensByModel.values.reduce(0, +)
        let totalTokens = totalTokensByModel.values.reduce(0, +)
        let channelMessages = channels.reduce(0) { $0 + $1.messages.count }
        let channelReplies = channels.reduce(0) { total, channel in
            total + channel.messages.reduce(0) { $0 + $1.replies.count }
        }

        return AnalyticsSummary(
            totalChats: filteredThreads.count,
            activeChats: filteredThreads.filter { !$0.isArchived }.count,
            archivedChats: filteredThreads.filter(\.isArchived).count,
            pinnedChats: filteredThreads.filter(\.isPinned).count,
            totalMessages: userMessages + assistantMessages + systemMessages,
            userMessages: userMessages,
            assistantMessages: assistantMessages,
            systemMessages: systemMessages,
            totalModels: modelUsage.count,
            totalPromptTokens: totalPromptTokens,
            totalCompletionTokens: totalCompletionTokens,
            totalTokens: totalTokens,
            modelUsage: modelUsage,
            dailyModelUsage: dailyModelUsage,
            feedbackRecords: feedbacks.count,
            positiveFeedback: positiveFeedback,
            negativeFeedback: negativeFeedback,
            knowledgeCollections: knowledgeCollections.count,
            knowledgeDocuments: knowledgeDocuments.values.reduce(0) { $0 + $1.count },
            channels: channels.count,
            channelMessages: channelMessages,
            channelReplies: channelReplies,
            notes: notes.count,
            automations: automations.count,
            activeAutomations: automations.filter(\.isActive).count,
            calendars: calendars.count,
            calendarEvents: calendarEvents.count
        )
    }

    func modelChats(
        modelID: String,
        threads: [ChatThread],
        adminGroups: [AdminGroup] = [],
        filter: AnalyticsFilter = .all
    ) -> [AnalyticsModelChat] {
        Self.filteredThreads(threads, adminGroups: adminGroups, filter: filter).compactMap { thread in
            let matchingMessages = thread.messages.filter { message in
                message.modelID == modelID
            }
            guard !matchingMessages.isEmpty else {
                return nil
            }

            let promptTokens = matchingMessages.reduce(0) { total, message in
                total + (message.tokenUsage?.promptTokens ?? 0)
            }
            let completionTokens = matchingMessages.reduce(0) { total, message in
                total + (message.tokenUsage?.completionTokens ?? 0)
            }
            let totalTokens = matchingMessages.reduce(0) { total, message in
                total + (message.tokenUsage?.totalTokens ?? 0)
            }
            let lastMessageAt = matchingMessages.map(\.createdAt).max() ?? thread.updatedAt

            return AnalyticsModelChat(
                threadID: thread.id,
                title: thread.title,
                messageCount: matchingMessages.count,
                promptTokens: promptTokens,
                completionTokens: completionTokens,
                totalTokens: totalTokens,
                lastMessageAt: lastMessageAt
            )
        }
        .sorted { lhs, rhs in
            if lhs.lastMessageAt != rhs.lastMessageAt {
                return lhs.lastMessageAt > rhs.lastMessageAt
            }
            return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
        }
    }

    private static func utcDayString(from date: Date) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(
            format: "%04d-%02d-%02d",
            components.year ?? 0,
            components.month ?? 0,
            components.day ?? 0
        )
    }

    private static func filteredThreads(
        _ threads: [ChatThread],
        adminGroups: [AdminGroup],
        filter: AnalyticsFilter
    ) -> [ChatThread] {
        guard filter.isActive else {
            return threads
        }

        var allowedUserIDs = filter.userIDs
        for group in adminGroups where filter.groupIDs.contains(group.id) {
            allowedUserIDs.formUnion(group.memberIDs)
        }

        guard !allowedUserIDs.isEmpty else {
            return []
        }

        return threads.filter { allowedUserIDs.contains($0.userID) }
    }
}
