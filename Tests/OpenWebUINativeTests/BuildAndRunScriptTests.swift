import Foundation
import XCTest

final class BuildAndRunScriptTests: XCTestCase {
    func testBuildAndRunScriptDefinesSmokeModeWithMacValidationSteps() throws {
        let rootURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let scriptURL = rootURL.appendingPathComponent("script/build_and_run.sh")
        let script = try String(contentsOf: scriptURL)

        XCTAssertTrue(script.contains("--smoke|smoke"))
        XCTAssertTrue(script.contains("swift test"))
        XCTAssertTrue(script.contains("swift build"))
        XCTAssertTrue(script.contains("/usr/bin/plutil -lint"))
        XCTAssertTrue(script.contains("uname -s"))
        XCTAssertTrue(script.contains("verify the packaged app binary exists"))
    }
}
