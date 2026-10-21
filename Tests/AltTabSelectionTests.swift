import XCTest
@testable import NewWindowPlz

final class AltTabSelectionTests: XCTestCase {
    func testInitialSelectionIsPreviousApp() {
        XCTAssertEqual(AltTabSelection.initialIndex(count: 4, reverse: false), 1)
    }

    func testInitialReverseSelectionIsLastApp() {
        XCTAssertEqual(AltTabSelection.initialIndex(count: 4, reverse: true), 3)
    }

    func testSingleAppSelection() {
        XCTAssertEqual(AltTabSelection.initialIndex(count: 1, reverse: false), 0)
        XCTAssertEqual(AltTabSelection.initialIndex(count: 0, reverse: false), 0)
    }

    func testAdvanceWraps() {
        XCTAssertEqual(AltTabSelection.advance(index: 3, count: 4, reverse: false), 0)
        XCTAssertEqual(AltTabSelection.advance(index: 0, count: 4, reverse: true), 3)
    }

    func testVisibleRangeCentersSelection() {
        XCTAssertEqual(AltTabSelection.visibleRange(count: 12, selectedIndex: 6), 3..<10)
        XCTAssertEqual(AltTabSelection.visibleRange(count: 12, selectedIndex: 0), 0..<7)
        XCTAssertEqual(AltTabSelection.visibleRange(count: 12, selectedIndex: 11), 5..<12)
    }

    func testVisibleRangeShortList() {
        XCTAssertEqual(AltTabSelection.visibleRange(count: 3, selectedIndex: 1), 0..<3)
    }
}
