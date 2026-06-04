import Foundation
import XCTest
@testable import OpenWebUINative

final class ChatGenerationMetricsTests: XCTestCase {
    func testDurationLabelFormatsCompletedGenerationDuration() {
        let metrics = ChatGenerationMetrics(
            startedAt: Date(timeIntervalSince1970: 100),
            completedAt: Date(timeIntervalSince1970: 100.25)
        )

        XCTAssertEqual(metrics.durationLabel, "0.3s")
    }

    func testDurationLabelIsNilUntilGenerationCompletes() {
        let metrics = ChatGenerationMetrics(startedAt: Date(timeIntervalSince1970: 100))

        XCTAssertNil(metrics.durationLabel)
    }
}
