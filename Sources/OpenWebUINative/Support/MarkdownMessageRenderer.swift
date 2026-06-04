import Foundation
import SwiftUI

enum MarkdownMessageSegment: Equatable, Sendable {
    case markdown(String)
    case math(display: Bool, content: String)
    case code(language: String?, content: String)
}

enum CodeSyntaxTokenKind: Equatable, Sendable {
    case plain
    case keyword
    case string
    case number
    case comment
}

struct CodeSyntaxSegment: Equatable, Sendable {
    var text: String
    var kind: CodeSyntaxTokenKind
}

struct RenderedCodeToken: Equatable, Sendable {
    var text: String
    var scope: String
}

enum RenderedMessageSnapshot: Equatable, Sendable {
    case markdown(String)
    case math(display: Bool, source: String, html: String)
    case code(language: String?, source: String, tokens: [RenderedCodeToken])
}

struct MathMessageRenderer: Sendable {
    func html(for source: String, display: Bool) -> String {
        let escapedSource = htmlEscaped(source)
        if display {
            return #"<div class="math math-display" data-renderer="katex">\#(escapedSource)</div>"#
        }
        return #"<span class="math math-inline" data-renderer="katex">\#(escapedSource)</span>"#
    }

    private func htmlEscaped(_ text: String) -> String {
        text.reduce(into: "") { result, character in
            switch character {
            case "&":
                result += "&amp;"
            case "<":
                result += "&lt;"
            case ">":
                result += "&gt;"
            case "\"":
                result += "&quot;"
            case "'":
                result += "&#39;"
            default:
                result.append(character)
            }
        }
    }
}

struct CodeMessageRenderer: Sendable {
    var highlighter = CodeSyntaxHighlighter()

    func tokens(for source: String, language: String?) -> [RenderedCodeToken] {
        highlighter.segments(for: source, language: language).map { segment in
            RenderedCodeToken(text: segment.text, scope: scope(for: segment.kind))
        }
    }

    private func scope(for kind: CodeSyntaxTokenKind) -> String {
        switch kind {
        case .plain:
            return "plain"
        case .keyword:
            return "keyword"
        case .string:
            return "string"
        case .number:
            return "number"
        case .comment:
            return "comment"
        }
    }
}

struct MarkdownMessageSnapshotRenderer: Sendable {
    var parser = MarkdownMessageParser()
    var mathRenderer = MathMessageRenderer()
    var codeRenderer = CodeMessageRenderer()

    func snapshots(from markdown: String) -> [RenderedMessageSnapshot] {
        parser.segments(from: markdown).map { segment in
            switch segment {
            case .markdown(let text):
                return .markdown(text)
            case .math(let display, let content):
                return .math(
                    display: display,
                    source: content,
                    html: mathRenderer.html(for: content, display: display)
                )
            case .code(let language, let content):
                return .code(
                    language: language,
                    source: content,
                    tokens: codeRenderer.tokens(for: content, language: language)
                )
            }
        }
    }
}

struct CodeSyntaxHighlighter: Sendable {
    func segments(for code: String, language: String?) -> [CodeSyntaxSegment] {
        guard let language = normalizedLanguage(language),
              let keywords = keywordsByLanguage[language] else {
            return [CodeSyntaxSegment(text: code, kind: .plain)]
        }

        var segments: [CodeSyntaxSegment] = []
        var plainBuffer = ""
        var index = code.startIndex

        func flushPlain() {
            guard !plainBuffer.isEmpty else {
                return
            }
            segments.append(CodeSyntaxSegment(text: plainBuffer, kind: .plain))
            plainBuffer = ""
        }

        while index < code.endIndex {
            if startsLineComment(at: index, in: code, language: language) {
                flushPlain()
                let commentStart = index
                index = code.index(index, offsetBy: language == "python" || language == "shell" ? 1 : 2)
                while index < code.endIndex, code[index] != "\n" {
                    index = code.index(after: index)
                }
                segments.append(CodeSyntaxSegment(text: String(code[commentStart..<index]), kind: .comment))
                continue
            }

            if code[index] == "\"" || code[index] == "'" || (language != "python" && code[index] == "`") {
                flushPlain()
                let stringStart = index
                let quote = code[index]
                index = code.index(after: index)
                while index < code.endIndex {
                    let character = code[index]
                    index = code.index(after: index)
                    if character == quote, !isEscaped(code.index(before: index), in: code) {
                        break
                    }
                }
                segments.append(CodeSyntaxSegment(text: String(code[stringStart..<index]), kind: .string))
                continue
            }

            if code[index].isNumber {
                flushPlain()
                let numberStart = index
                index = code.index(after: index)
                while index < code.endIndex, code[index].isNumber || code[index] == "." || code[index] == "_" {
                    index = code.index(after: index)
                }
                segments.append(CodeSyntaxSegment(text: String(code[numberStart..<index]), kind: .number))
                continue
            }

            if isIdentifierStart(code[index]) {
                let identifierStart = index
                index = code.index(after: index)
                while index < code.endIndex, isIdentifierBody(code[index]) {
                    index = code.index(after: index)
                }
                let identifier = String(code[identifierStart..<index])
                if keywords.contains(identifier) {
                    flushPlain()
                    segments.append(CodeSyntaxSegment(text: identifier, kind: .keyword))
                } else {
                    plainBuffer += identifier
                }
                continue
            }

            plainBuffer.append(code[index])
            index = code.index(after: index)
        }

        flushPlain()
        return segments.isEmpty ? [CodeSyntaxSegment(text: code, kind: .plain)] : segments
    }

    func attributedString(for code: String, language: String?) -> AttributedString {
        var rendered = AttributedString()
        for segment in segments(for: code, language: language) {
            var attributedSegment = AttributedString(segment.text)
            if let color = color(for: segment.kind) {
                attributedSegment.foregroundColor = color
            }
            rendered.append(attributedSegment)
        }
        return rendered
    }

    private func normalizedLanguage(_ language: String?) -> String? {
        guard let language else {
            return nil
        }
        switch language.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "swift":
            return "swift"
        case "js", "javascript", "jsx":
            return "javascript"
        case "ts", "typescript", "tsx":
            return "typescript"
        case "py", "python":
            return "python"
        case "sh", "bash", "zsh", "shell":
            return "shell"
        default:
            return nil
        }
    }

    private func startsLineComment(at index: String.Index, in code: String, language: String) -> Bool {
        if language == "python" || language == "shell" {
            return code[index] == "#"
        }
        guard code[index] == "/" else {
            return false
        }
        let next = code.index(after: index)
        return next < code.endIndex && code[next] == "/"
    }

    private func isIdentifierStart(_ character: Character) -> Bool {
        character == "_" || character.isLetter
    }

    private func isIdentifierBody(_ character: Character) -> Bool {
        isIdentifierStart(character) || character.isNumber
    }

    private func isEscaped(_ index: String.Index, in text: String) -> Bool {
        var slashCount = 0
        var cursor = index
        while cursor > text.startIndex {
            let previous = text.index(before: cursor)
            guard text[previous] == "\\" else {
                break
            }
            slashCount += 1
            cursor = previous
        }
        return slashCount % 2 == 1
    }

    private func color(for kind: CodeSyntaxTokenKind) -> Color? {
        switch kind {
        case .plain:
            return nil
        case .keyword:
            return .purple
        case .string:
            return .green
        case .number:
            return .orange
        case .comment:
            return .secondary
        }
    }

    private var keywordsByLanguage: [String: Set<String>] {
        [
            "swift": [
                "actor", "as", "associatedtype", "async", "await", "break", "case", "catch", "class", "continue",
                "default", "defer", "do", "else", "enum", "extension", "false", "for", "func", "guard",
                "if", "import", "in", "init", "inout", "let", "nil", "private", "protocol", "public",
                "return", "self", "static", "struct", "switch", "throw", "throws", "true", "try", "var",
                "while"
            ],
            "javascript": [
                "async", "await", "break", "case", "catch", "class", "const", "continue", "default", "else",
                "export", "extends", "false", "for", "from", "function", "if", "import", "let", "new",
                "null", "return", "switch", "this", "throw", "true", "try", "undefined", "var", "while"
            ],
            "typescript": [
                "async", "await", "break", "case", "catch", "class", "const", "continue", "default", "else",
                "enum", "export", "extends", "false", "for", "from", "function", "if", "implements", "import",
                "interface", "let", "new", "null", "private", "public", "readonly", "return", "switch",
                "this", "throw", "true", "try", "type", "undefined", "var", "while"
            ],
            "python": [
                "and", "as", "async", "await", "break", "class", "continue", "def", "elif", "else",
                "except", "False", "finally", "for", "from", "if", "import", "in", "is", "lambda",
                "None", "not", "or", "pass", "raise", "return", "True", "try", "while", "with", "yield"
            ],
            "shell": [
                "case", "do", "done", "elif", "else", "esac", "export", "fi", "for", "function",
                "if", "in", "local", "then", "while"
            ]
        ]
    }
}

struct MarkdownMessageParser: Sendable {
    func segments(from markdown: String) -> [MarkdownMessageSegment] {
        let lines = markdown.components(separatedBy: .newlines)
        var segments: [MarkdownMessageSegment] = []
        var markdownBuffer: [String] = []
        var codeBuffer: [String] = []
        var codeLanguage: String?
        var isInsideFence = false

        for line in lines {
            if let fenceLine = fenceLine(in: line) {
                if isInsideFence {
                    appendMarkdownBuffer(&markdownBuffer, to: &segments)
                    segments.append(.code(language: codeLanguage, content: trimTrailingNewlines(codeBuffer.joined(separator: "\n"))))
                    codeBuffer = []
                    codeLanguage = nil
                    isInsideFence = false
                } else {
                    appendMarkdownBuffer(&markdownBuffer, to: &segments)
                    codeLanguage = language(fromFenceLine: fenceLine)
                    isInsideFence = true
                }
                continue
            }

            if isInsideFence {
                codeBuffer.append(line)
            } else {
                markdownBuffer.append(line)
            }
        }

        if isInsideFence {
            return [.markdown(markdown)]
        }

        appendMarkdownBuffer(&markdownBuffer, to: &segments)
        return segments.isEmpty ? [.markdown(markdown)] : segments
    }

    private func appendMarkdownBuffer(_ buffer: inout [String], to segments: inout [MarkdownMessageSegment]) {
        let text = trimOuterWhitespace(buffer.joined(separator: "\n"))
        if !text.isEmpty {
            appendTextSegments(text, to: &segments)
        }
        buffer = []
    }

    private func appendTextSegments(_ text: String, to segments: inout [MarkdownMessageSegment]) {
        var cursor = text.startIndex
        var markdownStart = cursor

        while cursor < text.endIndex {
            if let delimiter = mathDelimiter(at: cursor, in: text),
               let closeRange = closingRange(for: delimiter.close, in: text, from: delimiter.contentStart) {
                appendMarkdownSegment(text[markdownStart..<cursor], to: &segments)
                let content = trimOuterWhitespace(String(text[delimiter.contentStart..<closeRange.lowerBound]))
                if !content.isEmpty {
                    segments.append(.math(display: delimiter.display, content: content))
                }
                cursor = closeRange.upperBound
                markdownStart = cursor
            } else {
                cursor = text.index(after: cursor)
            }
        }

        appendMarkdownSegment(text[markdownStart..<text.endIndex], to: &segments)
    }

    private func appendMarkdownSegment(_ slice: Substring, to segments: inout [MarkdownMessageSegment]) {
        let text = trimOuterWhitespace(String(slice))
        if !text.isEmpty {
            segments.append(.markdown(text))
        }
    }

    private func mathDelimiter(
        at index: String.Index,
        in text: String
    ) -> (display: Bool, close: String, contentStart: String.Index)? {
        let character = text[index]
        if character == "$" {
            guard !isEscaped(index, in: text) else {
                return nil
            }
            let next = text.index(after: index)
            if next < text.endIndex, text[next] == "$" {
                return (true, "$$", text.index(after: next))
            }
            return (false, "$", next)
        }

        guard character == "\\" else {
            return nil
        }

        let next = text.index(after: index)
        guard next < text.endIndex else {
            return nil
        }

        if text[next] == "(" {
            return (false, "\\)", text.index(after: next))
        }
        if text[next] == "[" {
            return (true, "\\]", text.index(after: next))
        }
        return nil
    }

    private func closingRange(
        for closeDelimiter: String,
        in text: String,
        from start: String.Index
    ) -> Range<String.Index>? {
        if closeDelimiter == "$" {
            return closingSingleDollarRange(in: text, from: start)
        }
        return text.range(of: closeDelimiter, range: start..<text.endIndex)
    }

    private func closingSingleDollarRange(in text: String, from start: String.Index) -> Range<String.Index>? {
        var cursor = start
        while cursor < text.endIndex {
            if text[cursor] == "$", !isEscaped(cursor, in: text) {
                let next = text.index(after: cursor)
                if next == text.endIndex || text[next] != "$" {
                    return cursor..<next
                }
            }
            cursor = text.index(after: cursor)
        }
        return nil
    }

    private func isEscaped(_ index: String.Index, in text: String) -> Bool {
        var slashCount = 0
        var cursor = index
        while cursor > text.startIndex {
            let previous = text.index(before: cursor)
            guard text[previous] == "\\" else {
                break
            }
            slashCount += 1
            cursor = previous
        }
        return slashCount % 2 == 1
    }

    private func language(fromFenceLine line: String) -> String? {
        let language = line
            .dropFirst(3)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return language.isEmpty ? nil : language
    }

    private func fenceLine(in line: String) -> String? {
        let leadingSpaces = line.prefix { $0 == " " }.count
        guard leadingSpaces <= 3 else {
            return nil
        }

        let trimmed = line.dropFirst(leadingSpaces)
        guard trimmed.hasPrefix("```") else {
            return nil
        }

        return String(trimmed)
    }

    private func trimOuterWhitespace(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func trimTrailingNewlines(_ text: String) -> String {
        text.trimmingCharacters(in: CharacterSet.newlines)
    }
}

struct MarkdownMessageRenderer: Sendable {
    func attributedString(from markdown: String) -> AttributedString {
        do {
            return try AttributedString(
                markdown: markdown,
                options: AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
            )
        } catch {
            return AttributedString(markdown)
        }
    }
}
