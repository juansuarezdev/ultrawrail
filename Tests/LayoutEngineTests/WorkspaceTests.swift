import XCTest
@testable import LayoutEngine

final class WorkspaceTests: XCTestCase {
    func makeWorkspace(_ count: Int) -> Workspace {
        var ws = Workspace()
        for i in 1...count { ws.addWindow(WindowID(i)) }
        return ws
    }

    func testAddToEmptyCreatesFocusedColumnWithDefaultWidth() {
        let ws = makeWorkspace(1)
        XCTAssertEqual(ws.columns.count, 1)
        XCTAssertEqual(ws.focusedWindow, 1)
        XCTAssertEqual(ws.columns[0].width, 0.5)
    }

    func testAddAppendsRightAndFocusesNewWindow() {
        let ws = makeWorkspace(3)
        XCTAssertEqual(ws.allWindows, [1, 2, 3])
        XCTAssertEqual(ws.focusedWindow, 3)
    }

    func testAddInsertsRightOfFocusedColumn() {
        var ws = makeWorkspace(3)
        ws.focus(window: 2)
        ws.addWindow(4)
        XCTAssertEqual(ws.allWindows, [1, 2, 4, 3])
        XCTAssertEqual(ws.focusedWindow, 4)
    }

    func testAddIgnoresDuplicates() {
        var ws = makeWorkspace(2)
        ws.addWindow(1)
        XCTAssertEqual(ws.allWindows, [1, 2])
    }

    func testRemoveFocusedLastClampsFocusToPrevious() {
        var ws = makeWorkspace(3)
        ws.removeWindow(3)
        XCTAssertEqual(ws.focusedWindow, 2)
    }

    func testRemoveFocusedMiddleFocusesColumnOnTheRight() {
        var ws = makeWorkspace(3)
        ws.focus(window: 2)
        ws.removeWindow(2)
        XCTAssertEqual(ws.allWindows, [1, 3])
        XCTAssertEqual(ws.focusedWindow, 3)
    }

    func testRemoveColumnLeftOfFocusKeepsFocusedWindow() {
        var ws = makeWorkspace(3)
        ws.removeWindow(1)
        XCTAssertEqual(ws.focusedWindow, 3)
    }

    func testRemoveLastWindowResetsWorkspace() {
        var ws = makeWorkspace(1)
        ws.scrollOffset = 42
        ws.removeWindow(1)
        XCTAssertNil(ws.focusedWindow)
        XCTAssertEqual(ws.scrollOffset, 0)
        XCTAssertTrue(ws.columns.isEmpty)
    }

    func testRemoveUnknownWindowIsNoOp() {
        var ws = makeWorkspace(2)
        ws.removeWindow(99)
        XCTAssertEqual(ws.allWindows, [1, 2])
    }
}
