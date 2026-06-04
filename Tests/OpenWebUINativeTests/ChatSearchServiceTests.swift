import XCTest
@testable import OpenWebUINative

final class ChatSearchServiceTests: XCTestCase {
    func testSearchFindsMessageContentCaseInsensitivelyAndSortsNewestMessageFirst() {
        let olderThreadID = UUID(uuidString: "00000000-0000-0000-0000-00000000C001")!
        let newerThreadID = UUID(uuidString: "00000000-0000-0000-0000-00000000C002")!
        let olderMessageID = UUID(uuidString: "00000000-0000-0000-0000-00000000A001")!
        let newerMessageID = UUID(uuidString: "00000000-0000-0000-0000-00000000A002")!
        let oldThread = ChatThread(
            id: olderThreadID,
            title: "Research",
            messages: [
                ChatMessage(
                    id: olderMessageID,
                    role: .assistant,
                    content: "The llama roadmap mentions native transcript search.",
                    createdAt: Date(timeIntervalSince1970: 20)
                )
            ]
        )
        let newThread = ChatThread(
            id: newerThreadID,
            title: "Build Notes",
            messages: [
                ChatMessage(
                    id: newerMessageID,
                    role: .user,
                    content: "Can we add TRANSCRIPT search to the native sidebar?",
                    createdAt: Date(timeIntervalSince1970: 40)
                )
            ]
        )

        let results = ChatSearchService().search("transcript", in: [oldThread, newThread])

        XCTAssertEqual(results.map(\.threadID), [newerThreadID, olderThreadID])
        XCTAssertEqual(results.map(\.messageID), [newerMessageID, olderMessageID])
        XCTAssertEqual(results.first?.threadTitle, "Build Notes")
        XCTAssertEqual(results.first?.role, .user)
        XCTAssertTrue(results.first?.snippet.localizedCaseInsensitiveContains("TRANSCRIPT search") == true)
    }

    func testSearchTrimsBlankQueriesAndSkipsThreadsWithoutMatches() {
        let matchingThread = ChatThread(
            title: "Knowledge",
            messages: [
                ChatMessage(role: .assistant, content: "Citations point back to imported notes.")
            ]
        )
        let unrelatedThread = ChatThread(
            title: "Images",
            messages: [
                ChatMessage(role: .assistant, content: "Generated image metadata lives elsewhere.")
            ]
        )

        XCTAssertTrue(ChatSearchService().search("   ", in: [matchingThread]).isEmpty)

        let results = ChatSearchService().search("citations", in: [matchingThread, unrelatedThread])

        XCTAssertEqual(results.map(\.threadTitle), ["Knowledge"])
        XCTAssertTrue(results.first?.snippet.contains("Citations point back") == true)
    }

    func testSearchIndexesThreadMetadataAttachmentsAndCitationsWithAllQueryTerms() {
        let threadID = UUID(uuidString: "00000000-0000-0000-0000-00000000C003")!
        let messageID = UUID(uuidString: "00000000-0000-0000-0000-00000000A003")!
        let thread = ChatThread(
            id: threadID,
            title: "Release Parity",
            messages: [
                ChatMessage(
                    id: messageID,
                    role: .user,
                    content: "Please summarize this source.",
                    createdAt: Date(timeIntervalSince1970: 50),
                    attachments: [
                        ChatAttachment(
                            fileName: "scan.pdf",
                            contentType: "application/pdf",
                            byteCount: 42,
                            textContent: "OCR invoice number XR-42."
                        )
                    ],
                    citations: [
                        ChatCitation(
                            collectionName: "Docs",
                            collectionSlug: "docs",
                            sourceName: "roadmap.md",
                            text: "KaTeX rendering is part of release parity.",
                            score: 0.91
                        )
                    ]
                )
            ]
        )

        let attachmentResults = ChatSearchService().search("invoice XR-42", in: [thread])
        let citationResults = ChatSearchService().search("KaTeX parity", in: [thread])

        XCTAssertEqual(attachmentResults.map(\.messageID), [messageID])
        XCTAssertEqual(citationResults.map(\.threadID), [threadID])
        XCTAssertTrue(attachmentResults.first?.snippet.contains("XR-42") == true)
        XCTAssertTrue(citationResults.first?.snippet.localizedCaseInsensitiveContains("KaTeX rendering") == true)
    }
}
