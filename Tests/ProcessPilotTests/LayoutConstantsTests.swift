import XCTest
@testable import ProcessPilot

final class LayoutConstantsTests: XCTestCase {
    func testDetailContentWidthIsAlwaysWithinDetailColumnWidth() {
        XCTAssertTrue(SplitLayoutConstants.isConsistent)
        XCTAssertLessThanOrEqual(
            SplitLayoutConstants.detailContentWidth,
            SplitLayoutConstants.detailColumnWidth
        )
    }
}
