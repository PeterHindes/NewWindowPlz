import CoreGraphics
import XCTest
@testable import NewWindowPlz

final class DockSnapshotTests: XCTestCase {
    private var snapshot: DockSnapshot {
        DockSnapshot(
            tiles: [
                DockTile(title: "Finder", frame: CGRect(x: 100, y: 900, width: 50, height: 50), isRunning: true),
                DockTile(title: "Safari", frame: CGRect(x: 160, y: 900, width: 50, height: 50), isRunning: false)
            ],
            capturedAt: 1
        )
    }

    func testHitTestWithSlop() {
        XCTAssertEqual(snapshot.tile(at: CGPoint(x: 125, y: 925), slop: 0)?.title, "Finder")
        XCTAssertNil(snapshot.tile(at: CGPoint(x: 95, y: 925), slop: 0))
        XCTAssertEqual(snapshot.tile(at: CGPoint(x: 95, y: 925), slop: 8)?.title, "Finder")
    }

    func testMightContainTileDoesNotRequireRunning() {
        XCTAssertTrue(snapshot.mightContainTile(at: CGPoint(x: 180, y: 925), slop: 0))
    }

    func testUnionBounds() {
        XCTAssertEqual(snapshot.unionBounds, CGRect(x: 100, y: 900, width: 110, height: 50))
    }

    func testGapIsNotAHit() {
        XCTAssertNil(snapshot.tile(at: CGPoint(x: 155, y: 925), slop: 0))
    }
}
