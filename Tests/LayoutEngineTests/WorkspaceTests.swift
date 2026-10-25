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

    func testFocusLeftAndRightClampAtEdges() {
        var ws = makeWorkspace(3)
        ws.apply(.focusRight)
        XCTAssertEqual(ws.focusedWindow, 3)
        ws.apply(.focusLeft)
        ws.apply(.focusLeft)
        XCTAssertEqual(ws.focusedWindow, 1)
        ws.apply(.focusLeft)
        XCTAssertEqual(ws.focusedWindow, 1)
    }

    func testCycleWidthWalksPresetsAndWraps() {
        var ws = makeWorkspace(1)
        var seen: [Double] = []
        for _ in 0..<5 {
            ws.apply(.cycleWidth)
            seen.append(ws.columns[0].width)
        }
        XCTAssertEqual(seen, [0.66, 0.75, 0.25, 0.33, 0.5])
    }

    func testToggleFullWidthRestoresPreviousWidth() {
        var ws = makeWorkspace(1)
        ws.apply(.cycleWidth)
        ws.apply(.toggleFullWidth)
        XCTAssertEqual(ws.columns[0].width, 1.0)
        ws.apply(.toggleFullWidth)
        XCTAssertEqual(ws.columns[0].width, 0.66)
    }

    func testApplyOnEmptyWorkspaceIsNoOp() {
        var ws = Workspace()
        ws.apply(.focusRight)
        ws.apply(.cycleWidth)
        XCTAssertTrue(ws.columns.isEmpty)
    }

    func testMoveColumnRightSwapsWithNeighbourAndFocusFollows() {
        var ws = makeWorkspace(3)
        ws.apply(.focusLeft)
        ws.apply(.focusLeft)
        ws.apply(.moveColumnRight)
        XCTAssertEqual(ws.columns.map(\.windows), [[2], [1], [3]])
        XCTAssertEqual(ws.focusedColumn, 1)
        XCTAssertEqual(ws.focusedWindow, 1)
    }

    func testMoveColumnLeftSwapsWithNeighbourAndFocusFollows() {
        var ws = makeWorkspace(3)
        ws.apply(.moveColumnLeft)
        XCTAssertEqual(ws.columns.map(\.windows), [[1], [3], [2]])
        XCTAssertEqual(ws.focusedColumn, 1)
        XCTAssertEqual(ws.focusedWindow, 3)
    }

    func testMoveColumnKeepsWidthsAndStacksWithTheColumn() {
        var ws = makeWorkspace(3)
        ws.apply(.stackLeft)            // [[1], [2, 3]], focus on 3
        ws.apply(.cycleWidth)
        let width = ws.columns[1].width
        ws.apply(.moveColumnLeft)
        XCTAssertEqual(ws.columns.map(\.windows), [[2, 3], [1]])
        XCTAssertEqual(ws.columns[0].width, width)
        XCTAssertEqual(ws.focusedColumn, 0)
        XCTAssertEqual(ws.focusedWindow, 3)
    }

    func testMoveColumnAtEdgeIsNoOp() {
        var ws = makeWorkspace(3)
        ws.apply(.moveColumnRight)
        XCTAssertEqual(ws.columns.map(\.windows), [[1], [2], [3]])
        ws.apply(.focusLeft)
        ws.apply(.focusLeft)
        ws.apply(.moveColumnLeft)
        XCTAssertEqual(ws.columns.map(\.windows), [[1], [2], [3]])
        XCTAssertEqual(ws.focusedColumn, 0)
    }

    func testStackLeftMovesFocusedWindowIntoLeftColumn() {
        var ws = makeWorkspace(3)
        ws.apply(.stackLeft)
        XCTAssertEqual(ws.columns.map(\.windows), [[1], [2, 3]])
        XCTAssertEqual(ws.focusedWindow, 3)
        XCTAssertEqual(ws.focusedRow, 1)
    }

    func testStackLeftRemovingEmptiedColumnKeepsFocus() {
        var ws = makeWorkspace(2)
        ws.apply(.stackLeft)
        XCTAssertEqual(ws.columns.map(\.windows), [[1, 2]])
        XCTAssertEqual(ws.focusedColumn, 0)
        XCTAssertEqual(ws.focusedWindow, 2)
    }

    func testStackLeftOnFirstColumnIsNoOp() {
        var ws = makeWorkspace(2)
        ws.apply(.focusLeft)
        ws.apply(.stackLeft)
        XCTAssertEqual(ws.columns.map(\.windows), [[1], [2]])
    }

    func testUnstackExpelsFocusedWindowToNewColumnOnTheRight() {
        var ws = makeWorkspace(3)
        ws.apply(.stackLeft)
        ws.apply(.unstack)
        XCTAssertEqual(ws.columns.map(\.windows), [[1], [2], [3]])
        XCTAssertEqual(ws.focusedWindow, 3)
        XCTAssertEqual(ws.focusedColumn, 2)
    }

    func testUnstackSingleWindowIsNoOp() {
        var ws = makeWorkspace(2)
        ws.apply(.unstack)
        XCTAssertEqual(ws.columns.map(\.windows), [[1], [2]])
    }

    func testFocusUpAndDownMoveWithinStack() {
        var ws = makeWorkspace(2)
        ws.apply(.stackLeft)
        ws.apply(.focusUp)
        XCTAssertEqual(ws.focusedWindow, 1)
        ws.apply(.focusUp)
        XCTAssertEqual(ws.focusedWindow, 1)
        ws.apply(.focusDown)
        XCTAssertEqual(ws.focusedWindow, 2)
        ws.apply(.focusDown)
        XCTAssertEqual(ws.focusedWindow, 2)
    }

    func testNewColumnWidthAppliesToAddedWindows() {
        var ws = Workspace()
        ws.newColumnWidth = 0.33
        ws.addWindow(1)
        XCTAssertEqual(ws.columns[0].width, 0.33)
    }

    func testChangingNewColumnWidthLeavesExistingColumnsAlone() {
        var ws = makeWorkspace(2)
        ws.newColumnWidth = 0.75
        XCTAssertEqual(ws.columns.map(\.width), [0.5, 0.5])
        ws.addWindow(3)
        XCTAssertEqual(ws.columns.map(\.width), [0.5, 0.5, 0.75])
    }

    func testUnstackedWindowGetsNewColumnWidth() {
        var ws = makeWorkspace(2)
        ws.apply(.stackLeft)            // [[1, 2]]
        ws.newColumnWidth = 0.25
        ws.apply(.unstack)
        XCTAssertEqual(ws.columns.map(\.windows), [[1], [2]])
        XCTAssertEqual(ws.columns[1].width, 0.25)
    }
}
