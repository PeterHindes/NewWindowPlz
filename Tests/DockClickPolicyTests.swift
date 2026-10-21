import CoreGraphics
import XCTest
@testable import NewWindowPlz

final class DockClickPolicyTests: XCTestCase {
    private let policy = DockClickPolicy()
    private let tile = DockTile(
        title: "TextEdit",
        frame: CGRect(x: 100, y: 900, width: 48, height: 48),
        isRunning: true
    )

    func testPlainClickOnRunningAppOpensNewWindow() {
        XCTAssertEqual(
            policy.decide(isEnabled: true, tile: tile, modifiers: []),
            .openNewWindow
        )
    }

    func testShiftClickPassesThrough() {
        XCTAssertEqual(
            policy.decide(isEnabled: true, tile: tile, modifiers: [.maskShift]),
            .passThrough(.modifierKey)
        )
    }

    func testEveryShortcutModifierPassesThrough() {
        let modifiers: [CGEventFlags] = [
            .maskShift, .maskControl, .maskAlternate, .maskCommand,
            [.maskShift, .maskCommand], [.maskControl, .maskAlternate]
        ]
        for modifier in modifiers {
            XCTAssertEqual(
                policy.decide(isEnabled: true, tile: tile, modifiers: modifier),
                .passThrough(.modifierKey),
                "Expected \(modifier) to use native Dock behavior"
            )
        }
    }

    func testNonAppTilePassesThrough() {
        XCTAssertEqual(
            policy.decide(isEnabled: true, tile: nil, modifiers: []),
            .passThrough(.noTile)
        )
    }

    func testStoppedAppTilePassesThrough() {
        let stopped = DockTile(
            title: "Safari",
            frame: CGRect(x: 0, y: 900, width: 48, height: 48),
            isRunning: false
        )
        XCTAssertEqual(
            policy.decide(isEnabled: true, tile: stopped, modifiers: []),
            .passThrough(.applicationNotRunning)
        )
    }

    func testDisabledPolicyPassesThrough() {
        XCTAssertEqual(
            policy.decide(isEnabled: false, tile: tile, modifiers: []),
            .passThrough(.disabled)
        )
    }
}
