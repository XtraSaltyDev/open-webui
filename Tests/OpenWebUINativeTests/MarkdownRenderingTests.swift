import Foundation
import XCTest
@testable import OpenWebUINative

final class MarkdownRenderingTests: XCTestCase {
    func testParserSplitsMarkdownTextAndFencedCodeBlocks() {
        let markdown = """
        Here is **Swift**:

        ```swift
        let answer = 42
        print(answer)
        ```

        Done.
        """

        let segments = MarkdownMessageParser().segments(from: markdown)

        XCTAssertEqual(segments.count, 3)
        XCTAssertEqual(segments[0], .markdown("Here is **Swift**:"))
        XCTAssertEqual(segments[1], .code(language: "swift", content: "let answer = 42\nprint(answer)"))
        XCTAssertEqual(segments[2], .markdown("Done."))
    }

    func testParserSplitsInlineAndBlockLatexOutsideCodeFences() {
        let markdown = """
        Before $E=mc^2$ after.

        $$
        \\int_0^1 x\\,dx = \\frac{1}{2}
        $$
        """

        let segments = MarkdownMessageParser().segments(from: markdown)

        guard segments.count == 4 else {
            return XCTFail("Expected 4 markdown/math segments, got \(segments)")
        }
        XCTAssertEqual(segments[0], .markdown("Before"))
        XCTAssertEqual(String(describing: segments[1]), #"math(display: false, content: "E=mc^2")"#)
        XCTAssertEqual(segments[2], .markdown("after."))
        XCTAssertEqual(String(describing: segments[3]), #"math(display: true, content: "\\int_0^1 x\\,dx = \\frac{1}{2}")"#)
    }

    func testParserDoesNotSplitLatexInsideCodeBlocks() {
        let markdown = """
        ```text
        Keep $E=mc^2$ literal.
        ```
        """

        let segments = MarkdownMessageParser().segments(from: markdown)

        XCTAssertEqual(segments, [.code(language: "text", content: "Keep $E=mc^2$ literal.")])
    }

    func testParserDoesNotSplitLatexInsideIndentedCodeBlocks() {
        let markdown = "   ```swift\nlet template = \"$x + y$\"\n   ```"

        let segments = MarkdownMessageParser().segments(from: markdown)

        XCTAssertEqual(segments, [.code(language: "swift", content: "let template = \"$x + y$\"")])
    }

    func testParserPreservesOrderAcrossMultipleMathSegments() {
        let markdown = "Start $a$ middle $$b$$ end \\(c\\) finish."

        let segments = MarkdownMessageParser().segments(from: markdown)

        XCTAssertEqual(segments, [
            .markdown("Start"),
            .math(display: false, content: "a"),
            .markdown("middle"),
            .math(display: true, content: "b"),
            .markdown("end"),
            .math(display: false, content: "c"),
            .markdown("finish.")
        ])
    }

    func testParserTreatsEscapedDollarAsMarkdownText() {
        let markdown = #"Price is \$10 before $x+y$."#

        let segments = MarkdownMessageParser().segments(from: markdown)

        XCTAssertEqual(segments, [
            .markdown(#"Price is \$10 before"#),
            .math(display: false, content: "x+y"),
            .markdown(".")
        ])
    }

    func testParserTreatsUnclosedFenceAsMarkdown() {
        let markdown = """
        Before

        ```python
        print("oops")
        """

        let segments = MarkdownMessageParser().segments(from: markdown)

        XCTAssertEqual(segments, [.markdown(markdown)])
    }

    func testRendererConvertsMarkdownToAttributedStringAndFallsBackToPlainText() {
        let renderer = MarkdownMessageRenderer()

        let rendered = renderer.attributedString(from: "**Bold**")
        XCTAssertEqual(String(rendered.characters), "Bold")

        let fallback = renderer.attributedString(from: "[broken](<)")
        XCTAssertEqual(String(fallback.characters), "[broken](<)")
    }

    func testCodeSyntaxHighlighterClassifiesSwiftTokens() {
        let code = """
        let answer = 42
        print("done") // comment
        """

        let segments = CodeSyntaxHighlighter().segments(for: code, language: "swift")

        XCTAssertEqual(segments.map(\.kind), [
            .keyword,
            .plain,
            .number,
            .plain,
            .string,
            .plain,
            .comment
        ])
        XCTAssertEqual(segments.map(\.text).joined(), code)
    }

    func testCodeSyntaxHighlighterLeavesUnsupportedLanguagesPlain() {
        let code = "SELECT * FROM chats"

        let segments = CodeSyntaxHighlighter().segments(for: code, language: "sql")

        XCTAssertEqual(segments, [
            CodeSyntaxSegment(text: code, kind: .plain)
        ])
    }
}
