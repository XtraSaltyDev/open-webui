import Foundation
import XCTest

final class AppBundleMetadataTests: XCTestCase {
    func testInfoPlistTemplateIncludesRequiredBundleAndPrivacyMetadata() throws {
        let plistURL = repositoryRoot()
            .appendingPathComponent("Resources/macOS/OpenWebUINative-Info.plist")
        let data = try Data(contentsOf: plistURL)
        let plist = try XCTUnwrap(
            PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any]
        )

        XCTAssertEqual(plist["CFBundleExecutable"] as? String, "OpenWebUINative")
        XCTAssertEqual(plist["CFBundleIdentifier"] as? String, "dev.xtrasalty.OpenWebUINative")
        XCTAssertEqual(plist["CFBundleName"] as? String, "OpenWebUINative")
        XCTAssertEqual(plist["CFBundlePackageType"] as? String, "APPL")
        XCTAssertEqual(plist["LSMinimumSystemVersion"] as? String, "14.0")
        XCTAssertEqual(plist["NSPrincipalClass"] as? String, "NSApplication")

        let microphoneUsage = try XCTUnwrap(plist["NSMicrophoneUsageDescription"] as? String)
        XCTAssertFalse(microphoneUsage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

        let urlTypes = try XCTUnwrap(plist["CFBundleURLTypes"] as? [[String: Any]])
        let schemes = urlTypes.flatMap { urlType in
            urlType["CFBundleURLSchemes"] as? [String] ?? []
        }
        XCTAssertTrue(schemes.contains("openwebui-native"))
    }

    func testBuildScriptSupportsSigningAndPackageValidationModes() throws {
        let scriptURL = repositoryRoot()
            .appendingPathComponent("script/build_and_run.sh")
        let script = try String(contentsOf: scriptURL, encoding: .utf8)

        XCTAssertTrue(script.contains("--sign|sign"))
        XCTAssertTrue(script.contains("--validate-package|validate-package"))
        XCTAssertTrue(script.contains("/usr/bin/codesign --force --options runtime --sign"))
        XCTAssertTrue(script.contains("/usr/bin/codesign --verify --deep --strict --verbose=2"))
    }

    private func repositoryRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
