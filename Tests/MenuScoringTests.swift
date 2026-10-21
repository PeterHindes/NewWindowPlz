import XCTest
@testable import NewWindowPlz

final class MenuScoringTests: XCTestCase {
    private func candidate(
        _ title: String,
        key: String = "",
        modifiers: UInt32 = 0,
        enabled: Bool = true,
        children: Bool = false,
        path: [String] = ["File"]
    ) -> MenuCandidate {
        MenuCandidate(
            title: title,
            keyEquivalent: key,
            commandModifiers: modifiers,
            enabled: enabled,
            hasChildren: children,
            path: path
        )
    }

    func testNewWindowBeatsOtherNewItems() {
        let best = NewWindowMenuScoring.best(in: [
            candidate("New Tab", key: "t"),
            candidate("New"),
            candidate("New Window", key: "n")
        ])
        XCTAssertEqual(best?.title, "New Window")
    }

    func testFinderTitleIsRecognized() {
        let best = NewWindowMenuScoring.best(in: [
            candidate("New Finder Window", key: "n")
        ])
        XCTAssertEqual(best?.title, "New Finder Window")
    }

    func testDisabledItemIsIgnored() {
        XCTAssertNil(NewWindowMenuScoring.best(in: [
            candidate("New Window", key: "n", enabled: false)
        ]))
    }

    func testSubmenuParentIsIgnored() {
        XCTAssertNil(NewWindowMenuScoring.best(in: [
            candidate("New Window", key: "n", children: true)
        ]))
    }

    func testTabAndFolderAreNotMistakenForWindows() {
        XCTAssertNil(NewWindowMenuScoring.best(in: [
            candidate("New Tab", key: "t"),
            candidate("New Folder", key: "n")
        ]))
    }

    func testPlainNewIsAccepted() {
        let best = NewWindowMenuScoring.best(in: [candidate("New", key: "n")])
        XCTAssertEqual(best?.title, "New")
    }

    func testUnrelatedItemIsIgnored() {
        XCTAssertNil(NewWindowMenuScoring.best(in: [
            candidate("Open…", key: "o")
        ]))
    }

    func testNoCandidate() {
        XCTAssertNil(NewWindowMenuScoring.best(in: []))
    }

    func testNormalization() {
        XCTAssertEqual(RunningApplicationResolver.normalize("Visual Studio Code.app"), "visualstudiocode")
        XCTAssertEqual(RunningApplicationResolver.normalize("Finder"), "finder")
    }
}
