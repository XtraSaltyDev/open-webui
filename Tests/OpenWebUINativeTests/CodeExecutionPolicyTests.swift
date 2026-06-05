import XCTest
@testable import OpenWebUINative

final class CodeExecutionPolicyTests: XCTestCase {
    func testPolicyAllowsEnabledLanguageInsideAllowedDirectory() {
        let policy = CodeExecutionPolicy(
            settings: CodeExecutionSettings(
                allowedLanguages: [.shell],
                allowedWorkingDirectoryRoots: ["/tmp"],
                maxTimeoutSeconds: 5
            ),
            localExecution: .enabledForTests(sandboxRootPath: "/tmp")
        )

        let decision = policy.evaluate(
            CodeExecutionRequest(
                language: .shell,
                code: "pwd",
                workingDirectoryPath: "/tmp/project",
                timeoutSeconds: 30
            )
        )

        switch decision {
        case let .allowed(timeoutSeconds, workingDirectoryPath, maxCapturedOutputBytes):
            XCTAssertEqual(timeoutSeconds, 5)
            XCTAssertEqual(workingDirectoryPath, "/tmp/project")
            XCTAssertEqual(maxCapturedOutputBytes, 1_048_576)
        case let .blocked(reason):
            XCTFail("Expected policy to allow execution, but blocked: \(reason)")
        }
    }

    func testPolicyBlocksDisabledLanguage() {
        let policy = CodeExecutionPolicy(
            settings: CodeExecutionSettings(
                allowedLanguages: [.python],
                allowedWorkingDirectoryRoots: ["/tmp"],
                maxTimeoutSeconds: 5
            ),
            localExecution: .enabledForTests(sandboxRootPath: "/tmp")
        )

        let decision = policy.evaluate(
            CodeExecutionRequest(
                language: .shell,
                code: "pwd",
                workingDirectoryPath: "/tmp",
                timeoutSeconds: 1
            )
        )

        XCTAssertEqual(decision, .blocked(reason: "Shell execution is disabled by policy."))
    }

    func testPolicyBlocksWorkingDirectoryOutsideAllowedRoots() {
        let policy = CodeExecutionPolicy(
            settings: CodeExecutionSettings(
                allowedLanguages: [.shell],
                allowedWorkingDirectoryRoots: ["/tmp/safe"],
                maxTimeoutSeconds: 5
            ),
            localExecution: .enabledForTests(sandboxRootPath: "/private")
        )

        let decision = policy.evaluate(
            CodeExecutionRequest(
                language: .shell,
                code: "pwd",
                workingDirectoryPath: "/private/project",
                timeoutSeconds: 1
            )
        )

        XCTAssertEqual(decision, .blocked(reason: "Working directory is outside the allowed code execution roots."))
    }

    func testPolicyBlocksWorkingDirectoryTraversalOutsideAllowedRoot() {
        let policy = CodeExecutionPolicy(
            settings: CodeExecutionSettings(
                allowedLanguages: [.shell],
                allowedWorkingDirectoryRoots: ["/tmp/safe"],
                maxTimeoutSeconds: 5
            ),
            localExecution: .enabledForTests(sandboxRootPath: "/tmp")
        )

        let decision = policy.evaluate(
            CodeExecutionRequest(
                language: .shell,
                code: "pwd",
                workingDirectoryPath: "/tmp/safe/../private",
                timeoutSeconds: 1
            )
        )

        XCTAssertEqual(decision, .blocked(reason: "Working directory is outside the allowed code execution roots."))
    }

    func testPolicyBlocksSiblingPathPrefixOutsideAllowedRoot() {
        let policy = CodeExecutionPolicy(
            settings: CodeExecutionSettings(
                allowedLanguages: [.shell],
                allowedWorkingDirectoryRoots: ["/tmp/safe"],
                maxTimeoutSeconds: 5
            ),
            localExecution: .enabledForTests(sandboxRootPath: "/tmp")
        )

        let decision = policy.evaluate(
            CodeExecutionRequest(
                language: .shell,
                code: "pwd",
                workingDirectoryPath: "/tmp/safe-project",
                timeoutSeconds: 1
            )
        )

        XCTAssertEqual(decision, .blocked(reason: "Working directory is outside the allowed code execution roots."))
    }

    func testPolicyBlocksDeniedShellExecutableBeforeProcessLaunch() {
        let policy = CodeExecutionPolicy(
            settings: CodeExecutionSettings(
                allowedLanguages: [.shell],
                allowedWorkingDirectoryRoots: ["/tmp"],
                deniedExecutableNames: ["rm"],
                maxTimeoutSeconds: 5
            ),
            localExecution: .enabledForTests(sandboxRootPath: "/tmp")
        )

        let decision = policy.evaluate(
            CodeExecutionRequest(
                language: .shell,
                code: "echo safe && rm -rf ./build",
                workingDirectoryPath: "/tmp",
                timeoutSeconds: 1
            )
        )

        XCTAssertEqual(decision, .blocked(reason: "Executable 'rm' is blocked by code execution policy."))
    }

    func testPolicyBlocksShellExecutableOutsideAllowlist() {
        let policy = CodeExecutionPolicy(
            settings: CodeExecutionSettings(
                allowedLanguages: [.shell],
                allowedWorkingDirectoryRoots: ["/tmp"],
                allowedExecutableNames: ["echo", "pwd"],
                maxTimeoutSeconds: 5
            ),
            localExecution: .enabledForTests(sandboxRootPath: "/tmp")
        )

        let decision = policy.evaluate(
            CodeExecutionRequest(
                language: .shell,
                code: "echo hello\ncurl https://example.com",
                workingDirectoryPath: "/tmp",
                timeoutSeconds: 1
            )
        )

        XCTAssertEqual(decision, .blocked(reason: "Executable 'curl' is not in the allowed code execution executables."))
    }

    func testPolicyAllowsShellExecutablesInsideAllowlist() {
        let policy = CodeExecutionPolicy(
            settings: CodeExecutionSettings(
                allowedLanguages: [.shell],
                allowedWorkingDirectoryRoots: ["/tmp"],
                allowedExecutableNames: ["echo", "pwd"],
                deniedExecutableNames: ["rm"],
                maxTimeoutSeconds: 5
            ),
            localExecution: .enabledForTests(sandboxRootPath: "/tmp")
        )

        let decision = policy.evaluate(
            CodeExecutionRequest(
                language: .shell,
                code: "pwd && echo hello",
                workingDirectoryPath: "/tmp",
                timeoutSeconds: 1
            )
        )

        switch decision {
        case let .allowed(timeoutSeconds, workingDirectoryPath, maxCapturedOutputBytes):
            XCTAssertEqual(timeoutSeconds, 1)
            XCTAssertEqual(workingDirectoryPath, "/tmp")
            XCTAssertEqual(maxCapturedOutputBytes, 1_048_576)
        case let .blocked(reason):
            XCTFail("Expected policy to allow execution, but blocked: \(reason)")
        }
    }

    func testPolicyBlocksWhenLocalExecutionIsDisabled() {
        let policy = CodeExecutionPolicy(
            settings: CodeExecutionSettings(
                allowedLanguages: [.shell],
                allowedWorkingDirectoryRoots: ["/tmp"]
            ),
            localExecution: LocalExecutionSettings(
                isEnabled: false,
                hasAcceptedRiskWarning: true,
                sandboxRootPath: "/tmp"
            )
        )

        let decision = policy.evaluate(
            CodeExecutionRequest(
                language: .shell,
                code: "pwd",
                workingDirectoryPath: "/tmp",
                timeoutSeconds: 1
            )
        )

        XCTAssertEqual(decision, .blocked(reason: LocalExecutionSettings.disabledMessage))
    }

    func testPolicyBlocksWhenRiskWarningHasNotBeenAccepted() {
        let policy = CodeExecutionPolicy(
            settings: CodeExecutionSettings(
                allowedLanguages: [.shell],
                allowedWorkingDirectoryRoots: ["/tmp"]
            ),
            localExecution: LocalExecutionSettings(
                isEnabled: true,
                hasAcceptedRiskWarning: false,
                sandboxRootPath: "/tmp"
            )
        )

        let decision = policy.evaluate(
            CodeExecutionRequest(
                language: .shell,
                code: "pwd",
                workingDirectoryPath: "/tmp",
                timeoutSeconds: 1
            )
        )

        XCTAssertEqual(decision, .blocked(reason: LocalExecutionSettings.riskWarningRequiredMessage))
    }

    func testPolicyBlocksWorkingDirectoryOutsideLocalExecutionSandbox() {
        let policy = CodeExecutionPolicy(
            settings: CodeExecutionSettings(
                allowedLanguages: [.shell],
                allowedWorkingDirectoryRoots: ["/tmp/sandbox"]
            ),
            localExecution: .enabledForTests(sandboxRootPath: "/tmp/sandbox")
        )

        let decision = policy.evaluate(
            CodeExecutionRequest(
                language: .shell,
                code: "pwd",
                workingDirectoryPath: "/tmp/outside",
                timeoutSeconds: 1
            )
        )

        XCTAssertEqual(decision, .blocked(reason: LocalExecutionSettings.outsideSandboxMessage))
    }

    func testPolicyDefaultsMissingWorkingDirectoryToSandboxRootWhenAllowed() {
        let policy = CodeExecutionPolicy(
            settings: CodeExecutionSettings(
                allowedLanguages: [.shell],
                allowedWorkingDirectoryRoots: ["/tmp/sandbox"]
            ),
            localExecution: .enabledForTests(sandboxRootPath: "/tmp/sandbox")
        )

        let decision = policy.evaluate(
            CodeExecutionRequest(
                language: .shell,
                code: "pwd",
                workingDirectoryPath: nil,
                timeoutSeconds: 1
            )
        )

        switch decision {
        case let .allowed(_, workingDirectoryPath, _):
            XCTAssertEqual(workingDirectoryPath, "/tmp/sandbox")
        case let .blocked(reason):
            XCTFail("Expected policy to allow execution, but blocked: \(reason)")
        }
    }
}
