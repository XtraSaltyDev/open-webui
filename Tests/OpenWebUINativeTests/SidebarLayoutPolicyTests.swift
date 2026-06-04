import XCTest
@testable import OpenWebUINative

final class SidebarLayoutPolicyTests: XCTestCase {
    func testSidebarActionPolicyUsesIconOnlyFixedWidthControls() {
        XCTAssertTrue(SidebarActionLayoutPolicy.usesIconOnlyLabels)
        XCTAssertGreaterThanOrEqual(SidebarActionLayoutPolicy.buttonWidth, 24)
        XCTAssertLessThanOrEqual(SidebarActionLayoutPolicy.buttonWidth, 32)
        XCTAssertLessThanOrEqual(SidebarActionLayoutPolicy.spacing, 8)
    }
}
