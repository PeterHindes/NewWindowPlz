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

    func testControlClickIsInterceptedForInversion() {
        XCTAssertEqual(
            policy.decide(isEnabled: true, tile: tile, modifiers: [.maskControl]),
            .openNewWindow
        )
    }

    func testOtherShortcutModifiersPassThrough() {
        let modifiers: [CGEventFlags] = [
            .maskAlternate, .maskCommand,
            [.maskShift, .maskControl],
            [.maskCommand, .maskControl],
            [.maskControl, .maskAlternate]
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

    func testControlInvertsEveryConfiguredAction() {
        XCTAssertEqual(DockActionResolver.resolve(configured: nil, inverted: false), .newWindow)
        XCTAssertEqual(DockActionResolver.resolve(configured: nil, inverted: true), .moveHere)
        XCTAssertEqual(DockActionResolver.resolve(configured: .moveHere, inverted: false), .moveHere)
        XCTAssertEqual(DockActionResolver.resolve(configured: .moveHere, inverted: true), .newWindow)
        XCTAssertEqual(DockActionResolver.resolve(configured: .newWindow, inverted: false), .newWindow)
        XCTAssertEqual(DockActionResolver.resolve(configured: .newWindow, inverted: true), .moveHere)
    }
}
