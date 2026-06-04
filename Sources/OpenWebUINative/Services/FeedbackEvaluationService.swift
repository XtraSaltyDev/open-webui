import Foundation

struct ModelEvaluationTagSummary: Equatable, Sendable {
    var tag: String
    var count: Int
}

struct ModelEvaluationSummary: Identifiable, Equatable, Sendable {
    var id: String { modelID }
    var modelID: String
    var rating: Int
    var won: Int
    var lost: Int
    var count: Int
    var positiveCount: Int
    var negativeCount: Int
    var topTags: [ModelEvaluationTagSummary]
}

struct FeedbackAdminFilter: Sendable {
    static func filteredFeedbacks(_ feedbacks: [AppFeedback], query: String) -> [AppFeedback] {
        let queryTerms = query
            .lowercased()
            .split(whereSeparator: { $0.isWhitespace || $0.isNewline })
            .map(String.init)
        let sorted = feedbacks.sorted { lhs, rhs in
            if lhs.updatedAt != rhs.updatedAt {
                return lhs.updatedAt > rhs.updatedAt
            }
            return lhs.id.localizedStandardCompare(rhs.id) == .orderedAscending
        }
        guard !queryTerms.isEmpty else {
            return sorted
        }
        return sorted
            .compactMap { feedback -> (feedback: AppFeedback, score: Int)? in
                let score = searchScore(for: feedback, queryTerms: queryTerms)
                return score > 0 ? (feedback, score) : nil
            }
            .sorted { lhs, rhs in
                if lhs.score != rhs.score {
                    return lhs.score > rhs.score
                }
                if lhs.feedback.updatedAt != rhs.feedback.updatedAt {
                    return lhs.feedback.updatedAt > rhs.feedback.updatedAt
                }
                return lhs.feedback.id.localizedStandardCompare(rhs.feedback.id) == .orderedAscending
            }
            .map(\.feedback)
    }

    private static func searchScore(for feedback: AppFeedback, queryTerms: [String]) -> Int {
        let fields = searchFields(for: feedback)
        var totalScore = 0
        for term in queryTerms {
            let termScore = fields
                .map { field in field.score(for: term) }
                .max() ?? 0
            guard termScore > 0 else {
                return 0
            }
            totalScore += termScore
        }
        return totalScore
    }

    private static func searchFields(for feedback: AppFeedback) -> [SearchField] {
        var modelValues = [feedback.data.modelID].compactMap { $0 }
        modelValues += feedback.data.siblingModelIDs
        return [
            SearchField(
                values: [feedback.id, feedback.userID, feedback.type],
                exactWeight: 80,
                containsWeight: 35
            ),
            SearchField(
                values: modelValues,
                exactWeight: 100,
                containsWeight: 70
            ),
            SearchField(
                values: [
                    feedback.data.rating?.label,
                    feedback.data.rating?.rawValue,
                    feedback.moderationStatus.label,
                    feedback.moderationStatus.rawValue
                ].compactMap { $0 } + feedback.meta.tags,
                exactWeight: 90,
                containsWeight: 60
            ),
            SearchField(
                values: [feedback.meta.chatID, feedback.meta.messageID].compactMap { $0 },
                exactWeight: 70,
                containsWeight: 35
            ),
            SearchField(
                values: [feedback.data.reason, feedback.data.comment, feedback.snapshot?.chat?.title].compactMap { $0 },
                exactWeight: 55,
                containsWeight: 20
            )
        ]
    }

    private struct SearchField {
        var values: [String]
        var exactWeight: Int
        var containsWeight: Int

        func score(for term: String) -> Int {
            values
                .map { value in
                    let normalizedValue = value.lowercased()
                    if normalizedValue == term {
                        return exactWeight
                    }
                    if normalizedValue.contains(term) {
                        return containsWeight
                    }
                    return 0
                }
                .max() ?? 0
        }
    }
}

struct FeedbackEvaluationService: Sendable {
    private let startingRating = 1000.0
    private let kFactor = 32.0

    func summaries(from feedbacks: [AppFeedback]) -> [ModelEvaluationSummary] {
        var statsByModel: [String: ModelEvaluationStats] = [:]

        for feedback in feedbacks {
            guard let modelID = feedback.data.modelID, !modelID.isEmpty else {
                continue
            }

            statsByModel[modelID, default: ModelEvaluationStats()].record(
                rating: feedback.data.rating,
                tags: tags(from: feedback)
            )

            guard let rating = feedback.data.rating else {
                continue
            }

            for opponentID in feedback.data.siblingModelIDs where !opponentID.isEmpty {
                statsByModel[opponentID, default: ModelEvaluationStats()].recordOpponent()
                updateElo(
                    ratedModelID: modelID,
                    opponentID: opponentID,
                    ratedModelWon: rating == .positive,
                    statsByModel: &statsByModel
                )
            }
        }

        return statsByModel.map { modelID, stats in
            ModelEvaluationSummary(
                modelID: modelID,
                rating: Int(stats.rating.rounded()),
                won: stats.won,
                lost: stats.lost,
                count: stats.feedbackCount,
                positiveCount: stats.positiveCount,
                negativeCount: stats.negativeCount,
                topTags: stats.topTags()
            )
        }
        .sorted { lhs, rhs in
            if lhs.rating != rhs.rating {
                return lhs.rating > rhs.rating
            }
            if lhs.count != rhs.count {
                return lhs.count > rhs.count
            }
            return lhs.modelID.localizedStandardCompare(rhs.modelID) == .orderedAscending
        }
    }

    private func updateElo(
        ratedModelID: String,
        opponentID: String,
        ratedModelWon: Bool,
        statsByModel: inout [String: ModelEvaluationStats]
    ) {
        let rated = statsByModel[ratedModelID] ?? ModelEvaluationStats()
        let opponent = statsByModel[opponentID] ?? ModelEvaluationStats()
        let expectedRated = 1 / (1 + pow(10, (opponent.rating - rated.rating) / 400))
        let expectedOpponent = 1 - expectedRated
        let ratedScore = ratedModelWon ? 1.0 : 0.0
        let opponentScore = ratedModelWon ? 0.0 : 1.0

        statsByModel[ratedModelID]?.rating += kFactor * (ratedScore - expectedRated)
        statsByModel[opponentID]?.rating += kFactor * (opponentScore - expectedOpponent)

        if ratedModelWon {
            statsByModel[ratedModelID]?.won += 1
            statsByModel[opponentID]?.lost += 1
        } else {
            statsByModel[ratedModelID]?.lost += 1
            statsByModel[opponentID]?.won += 1
        }
    }

    private func tags(from feedback: AppFeedback) -> [String] {
        var tags = feedback.meta.tags
        if case .array(let values)? = feedback.data.additional["tags"] {
            tags += values.compactMap { value in
                if case .string(let tag) = value {
                    return tag
                }
                return nil
            }
        }
        return AppSkill.normalizedTags(tags)
    }
}

private struct ModelEvaluationStats {
    var rating = 1000.0
    var won = 0
    var lost = 0
    var feedbackCount = 0
    var positiveCount = 0
    var negativeCount = 0
    var tagCounts: [String: Int] = [:]

    mutating func record(rating: MessageRating?, tags: [String]) {
        feedbackCount += 1
        switch rating {
        case .positive:
            positiveCount += 1
        case .negative:
            negativeCount += 1
        case nil:
            break
        }

        for tag in tags {
            tagCounts[tag, default: 0] += 1
        }
    }

    mutating func recordOpponent() {
        feedbackCount += 1
    }

    func topTags(limit: Int = 5) -> [ModelEvaluationTagSummary] {
        tagCounts.map { tag, count in
            ModelEvaluationTagSummary(tag: tag, count: count)
        }
        .sorted { lhs, rhs in
            if lhs.count != rhs.count {
                return lhs.count > rhs.count
            }
            return lhs.tag.localizedStandardCompare(rhs.tag) == .orderedAscending
        }
        .prefix(limit)
        .map { $0 }
    }
}
