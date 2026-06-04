import XCTest
@testable import OpenWebUINative

final class FeedbackEvaluationServiceTests: XCTestCase {
    func testFeedbackAdminFilterReturnsNewestFeedbackForBlankQuery() {
        let older = AppFeedback(
            id: "older",
            data: AppFeedbackData(rating: .positive, modelID: "llama3.2:latest"),
            meta: AppFeedbackMeta(),
            updatedAt: Date(timeIntervalSince1970: 100)
        )
        let newer = AppFeedback(
            id: "newer",
            data: AppFeedbackData(rating: .negative, modelID: "mistral:latest"),
            meta: AppFeedbackMeta(),
            updatedAt: Date(timeIntervalSince1970: 200)
        )

        let filtered = FeedbackAdminFilter.filteredFeedbacks([older, newer], query: "   ")

        XCTAssertEqual(filtered.map(\.id), ["newer", "older"])
    }

    func testFeedbackAdminFilterMatchesModelRatingTagsAndChatTitle() {
        let research = AppFeedback(
            id: "research",
            data: AppFeedbackData(
                rating: .positive,
                modelID: "gpt-4.1",
                reason: "accurate",
                comment: "Good citations."
            ),
            meta: AppFeedbackMeta(tags: ["research", "citations"]),
            snapshot: AppFeedbackSnapshot(chat: AppFeedbackChatSnapshot(title: "Research chat"))
        )
        let swift = AppFeedback(
            id: "swift",
            data: AppFeedbackData(
                rating: .negative,
                modelID: "llama3.2:latest",
                reason: "incomplete",
                comment: "Missed actor isolation."
            ),
            meta: AppFeedbackMeta(tags: ["swift"]),
            snapshot: AppFeedbackSnapshot(chat: AppFeedbackChatSnapshot(title: "Concurrency notes"))
        )

        XCTAssertEqual(
            FeedbackAdminFilter.filteredFeedbacks([research, swift], query: "gpt").map(\.id),
            ["research"]
        )
        XCTAssertEqual(
            FeedbackAdminFilter.filteredFeedbacks([research, swift], query: "negative").map(\.id),
            ["swift"]
        )
        XCTAssertEqual(
            FeedbackAdminFilter.filteredFeedbacks([research, swift], query: "citations").map(\.id),
            ["research"]
        )
        XCTAssertEqual(
            FeedbackAdminFilter.filteredFeedbacks([research, swift], query: "Concurrency").map(\.id),
            ["swift"]
        )
    }

    func testFeedbackAdminFilterMatchesModerationStatus() {
        let reviewed = AppFeedback(
            id: "first-feedback",
            data: AppFeedbackData(rating: .positive, modelID: "gpt-4.1"),
            meta: AppFeedbackMeta(),
            moderationStatus: .reviewed
        )
        let pending = AppFeedback(
            id: "second-feedback",
            data: AppFeedbackData(rating: .negative, modelID: "llama3.2:latest"),
            meta: AppFeedbackMeta()
        )

        XCTAssertEqual(
            FeedbackAdminFilter.filteredFeedbacks([reviewed, pending], query: "reviewed").map(\.id),
            ["first-feedback"]
        )
    }

    func testFeedbackAdminFilterRanksStrongerFieldMatchesBeforeNewerWeakMatches() {
        let newerWeakMatch = AppFeedback(
            id: "newer-weak",
            data: AppFeedbackData(
                rating: .positive,
                modelID: "gpt-4.1",
                comment: "The answer mentioned billing triage in passing."
            ),
            meta: AppFeedbackMeta(),
            updatedAt: Date(timeIntervalSince1970: 300)
        )
        let olderStrongMatch = AppFeedback(
            id: "older-strong",
            data: AppFeedbackData(rating: .negative, modelID: "llama3.2:latest"),
            meta: AppFeedbackMeta(tags: ["billing"]),
            updatedAt: Date(timeIntervalSince1970: 100)
        )

        XCTAssertEqual(
            FeedbackAdminFilter.filteredFeedbacks([newerWeakMatch, olderStrongMatch], query: "billing").map(\.id),
            ["older-strong", "newer-weak"]
        )
    }

    func testFeedbackAdminFilterFallsBackToNewestWhenScoresTie() {
        let older = AppFeedback(
            id: "older",
            data: AppFeedbackData(
                rating: .positive,
                modelID: "gpt-4.1",
                comment: "Needs citation review."
            ),
            meta: AppFeedbackMeta(),
            updatedAt: Date(timeIntervalSince1970: 100)
        )
        let newer = AppFeedback(
            id: "newer",
            data: AppFeedbackData(
                rating: .negative,
                modelID: "llama3.2:latest",
                comment: "Needs safety review."
            ),
            meta: AppFeedbackMeta(),
            updatedAt: Date(timeIntervalSince1970: 300)
        )

        XCTAssertEqual(
            FeedbackAdminFilter.filteredFeedbacks([older, newer], query: "needs").map(\.id),
            ["newer", "older"]
        )
    }

    func testSummariesCalculateEloWinsLossesAndTagsFromArenaFeedback() {
        let service = FeedbackEvaluationService()
        let feedbacks = [
            AppFeedback(
                data: AppFeedbackData(
                    rating: .positive,
                    modelID: "llama3.2:latest",
                    siblingModelIDs: ["mistral:latest"]
                ),
                meta: AppFeedbackMeta(tags: ["swift", "helpful"])
            ),
            AppFeedback(
                data: AppFeedbackData(
                    rating: .negative,
                    modelID: "llama3.2:latest",
                    siblingModelIDs: ["mistral:latest"]
                ),
                meta: AppFeedbackMeta(tags: ["swift", "wrong"])
            ),
            AppFeedback(
                data: AppFeedbackData(
                    rating: .positive,
                    modelID: "llama3.2:latest",
                    siblingModelIDs: ["mistral:latest"]
                ),
                meta: AppFeedbackMeta(tags: ["swift"])
            )
        ]

        let summaries = service.summaries(from: feedbacks)

        XCTAssertEqual(summaries.map(\.modelID), ["llama3.2:latest", "mistral:latest"])

        let llama = try! XCTUnwrap(summaries.first { $0.modelID == "llama3.2:latest" })
        XCTAssertEqual(llama.won, 2)
        XCTAssertEqual(llama.lost, 1)
        XCTAssertEqual(llama.count, 3)
        XCTAssertEqual(llama.positiveCount, 2)
        XCTAssertEqual(llama.negativeCount, 1)
        XCTAssertEqual(llama.topTags.map(\.tag), ["swift", "helpful", "wrong"])
        XCTAssertGreaterThan(llama.rating, 1000)

        let mistral = try! XCTUnwrap(summaries.first { $0.modelID == "mistral:latest" })
        XCTAssertEqual(mistral.won, 1)
        XCTAssertEqual(mistral.lost, 2)
        XCTAssertEqual(mistral.count, 3)
        XCTAssertLessThan(mistral.rating, 1000)
    }

    func testSummariesIncludeSingleModelFeedbackWithoutSiblings() {
        let service = FeedbackEvaluationService()
        let feedbacks = [
            AppFeedback(
                data: AppFeedbackData(
                    rating: .positive,
                    modelID: "gpt-4.1",
                    reason: "accurate",
                    comment: "Good citations."
                ),
                meta: AppFeedbackMeta(tags: ["research"])
            )
        ]

        let summaries = service.summaries(from: feedbacks)

        let summary = try! XCTUnwrap(summaries.first)
        XCTAssertEqual(summary.modelID, "gpt-4.1")
        XCTAssertEqual(summary.rating, 1000)
        XCTAssertEqual(summary.won, 0)
        XCTAssertEqual(summary.lost, 0)
        XCTAssertEqual(summary.count, 1)
        XCTAssertEqual(summary.positiveCount, 1)
        XCTAssertEqual(summary.negativeCount, 0)
        XCTAssertEqual(summary.topTags, [ModelEvaluationTagSummary(tag: "research", count: 1)])
    }

    func testSummariesIgnoreFeedbackWithoutModelID() {
        let service = FeedbackEvaluationService()
        let feedbacks = [
            AppFeedback(
                data: AppFeedbackData(rating: .positive, modelID: nil),
                meta: AppFeedbackMeta(tags: ["missing"])
            )
        ]

        XCTAssertTrue(service.summaries(from: feedbacks).isEmpty)
    }
}
