import Foundation

struct PromptVariable: Equatable, Sendable {
    var name: String
}

enum PromptVariableResolutionError: Error, Equatable, LocalizedError, Sendable {
    case missingValues([String])

    var errorDescription: String? {
        switch self {
        case let .missingValues(names):
            return "Missing prompt variable values: \(names.joined(separator: ", "))"
        }
    }
}

struct PromptVariableResolver: Sendable {
    func variables(in content: String) -> [PromptVariable] {
        placeholderMatches(in: content).reduce(into: []) { variables, match in
            guard !variables.contains(where: { $0.name == match.name }) else {
                return
            }
            variables.append(PromptVariable(name: match.name))
        }
    }

    func resolve(_ content: String, values: [String: String]) throws -> String {
        let matches = placeholderMatches(in: content)
        let missing = variables(in: content)
            .map(\.name)
            .filter { name in
                values[name]?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false
            }
        guard missing.isEmpty else {
            throw PromptVariableResolutionError.missingValues(missing)
        }

        var resolved = content
        for match in matches.reversed() {
            let value = values[match.name]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            resolved.replaceSubrange(match.range, with: value)
        }
        return resolved
    }

    private func placeholderMatches(in content: String) -> [PromptVariableMatch] {
        let pattern = #"\{\{\s*([A-Za-z][A-Za-z0-9_-]*)\s*\}\}"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return []
        }

        let nsRange = NSRange(content.startIndex..<content.endIndex, in: content)
        return regex.matches(in: content, range: nsRange).compactMap { match in
            guard let placeholderRange = Range(match.range(at: 0), in: content),
                  let nameRange = Range(match.range(at: 1), in: content) else {
                return nil
            }
            return PromptVariableMatch(name: String(content[nameRange]), range: placeholderRange)
        }
    }
}

private struct PromptVariableMatch {
    var name: String
    var range: Range<String.Index>
}
