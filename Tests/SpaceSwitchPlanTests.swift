import XCTest
@testable import NewWindowPlz

final class SpaceSwitchPlanTests: XCTestCase {
    func testForwardSteps() {
        XCTAssertEqual(SpaceSwitchPlan.steps(fromIndex: 1, toIndex: 4), 3)
    }

    func testBackwardSteps() {
        XCTAssertEqual(SpaceSwitchPlan.steps(fromIndex: 4, toIndex: 1), -3)
    }

    func testNoMovement() {
        XCTAssertEqual(SpaceSwitchPlan.steps(fromIndex: 2, toIndex: 2), 0)
    }
}
