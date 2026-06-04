import XCTest
@testable import OpenWebUINative

final class ChatTranscriptLayoutPolicyTests: XCTestCase {
    func testViewportWidthUsesMinimumWhenSwiftUIProposesIntrinsicWidth() {
        XCTAssertEqual(
            ChatTranscriptLayoutPolicy.viewportWidth(for: 246, fallbackWidth: nil),
            ChatTranscriptLayoutPolicy.minimumViewportWidth
        )
    }

    func testViewportWidthHonorsKnownDetailWidth() {
        XCTAssertEqual(
            ChatTranscriptLayoutPolicy.viewportWidth(for: 246, fallbackWidth: 972),
            972
        )
    }

    func testViewportWidthHonorsCompactDetailWidth() {
        XCTAssertEqual(
            ChatTranscriptLayoutPolicy.viewportWidth(for: 540, fallbackWidth: 540),
            540
        )
    }

    func testTranscriptWidthCentersReadableLaneOnWideWindows() {
        XCTAssertEqual(ChatTranscriptLayoutPolicy.transcriptWidth(for: 1_300), ChatTranscriptLayoutPolicy.maximumTranscriptWidth)
    }

    func testTranscriptWidthKeepsMarginsOnCompactWindows() {
        XCTAssertEqual(
            ChatTranscriptLayoutPolicy.transcriptWidth(for: 700),
            700 - (ChatTranscriptLayoutPolicy.horizontalMargin * 2)
        )
    }

    func testAssistantMessageWidthNeverExceedsTranscriptWidth() {
        let compactTranscriptWidth = ChatTranscriptLayoutPolicy.transcriptWidth(for: 540)

        XCTAssertLessThanOrEqual(
            ChatTranscriptLayoutPolicy.bubbleWidthLimit(for: compactTranscriptWidth),
            compactTranscriptWidth
        )
        XCTAssertEqual(
            ChatTranscriptLayoutPolicy.bubbleWidthLimit(for: 1_000),
            ChatTranscriptLayoutPolicy.maximumAssistantWidth
        )
    }

    func testUserPillWidthIsSlimmerThanAssistantResponseWidth() {
        XCTAssertEqual(
            ChatTranscriptLayoutPolicy.bubbleWidthLimit(for: 1_000, role: .user),
            ChatTranscriptLayoutPolicy.maximumUserPillWidth
        )
        XCTAssertLessThan(
            ChatTranscriptLayoutPolicy.maximumUserPillWidth,
            ChatTranscriptLayoutPolicy.maximumAssistantWidth
        )
    }

    func testOppositeSideSpacerOnlyAppliesWhenTranscriptHasRoom() {
        XCTAssertEqual(
            ChatTranscriptLayoutPolicy.oppositeSideSpacerMinLength(for: 540),
            0
        )
        XCTAssertEqual(
            ChatTranscriptLayoutPolicy.oppositeSideSpacerMinLength(for: 920),
            ChatTranscriptLayoutPolicy.minimumInterBubbleGap
        )
    }

    func testUserChromeUsesPillWithoutHeader() {
        let style = ChatMessageChromeStyle.style(for: .user)

        XCTAssertFalse(style.showsHeader)
        XCTAssertTrue(style.showsContainer)
        XCTAssertGreaterThanOrEqual(style.cornerRadius, 18)
        XCTAssertLessThanOrEqual(style.verticalPadding, 9)
    }

    func testAssistantChromeHasNoVisibleContainer() {
        let style = ChatMessageChromeStyle.style(for: .assistant)

        XCTAssertTrue(style.showsHeader)
        XCTAssertFalse(style.showsContainer)
        XCTAssertEqual(style.horizontalPadding, 0)
        XCTAssertEqual(style.verticalPadding, 0)
    }
}
