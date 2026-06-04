import XCTest
@testable import OpenWebUINative

final class PromptVariableResolverTests: XCTestCase {
    func testVariablesExtractsUniquePlaceholdersInOrder() {
        let resolver = PromptVariableResolver()

        let variables = resolver.variables(in: "Write about {{ topic }} for {{audience}}. Mention {{topic}} again.")

        XCTAssertEqual(variables, [
            PromptVariable(name: "topic"),
            PromptVariable(name: "audience")
        ])
    }

    func testResolveReplacesAllOccurrences() throws {
        let resolver = PromptVariableResolver()

        let resolved = try resolver.resolve(
            "Write about {{ topic }} for {{audience}}. Mention {{ topic }} again.",
            values: [
                "topic": "SwiftUI",
                "audience": "new engineers"
            ]
        )

        XCTAssertEqual(resolved, "Write about SwiftUI for new engineers. Mention SwiftUI again.")
    }

    func testResolveThrowsWhenValueIsMissing() {
        let resolver = PromptVariableResolver()

        XCTAssertThrowsError(
            try resolver.resolve(
                "Write about {{topic}} for {{audience}}.",
                values: ["topic": "SwiftUI"]
            )
        ) { error in
            XCTAssertEqual(error as? PromptVariableResolutionError, .missingValues(["audience"]))
        }
    }
}
