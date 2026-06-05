import Foundation
@testable import OpenWebUINative

@MainActor
extension AppStore {
    func enableLocalExecutionForTests(sandboxRootPath: String = "/tmp") {
        settings.localExecution = LocalExecutionSettings(
            isEnabled: true,
            hasAcceptedRiskWarning: true,
            sandboxRootPath: sandboxRootPath
        )
        settings.codeExecution.allowedWorkingDirectoryRoots = [sandboxRootPath]
    }
}

extension LocalExecutionSettings {
    static func enabledForTests(sandboxRootPath: String = "/tmp") -> LocalExecutionSettings {
        LocalExecutionSettings(
            isEnabled: true,
            hasAcceptedRiskWarning: true,
            sandboxRootPath: sandboxRootPath
        )
    }
}
