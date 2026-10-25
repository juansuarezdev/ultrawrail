import XCTest
import CoreGraphics
import LayoutEngine
@testable import UltrawrailCore

@MainActor
final class ControllerPagesTests: XCTestCase {
    let config = LayoutConfig(gap: 10, outerGap: 10)

    func make(_ ids: [Int]) -> (Controller, FakeWindows) {
        let windows = FakeWindows()
        for id in ids { windows.add(id) }
        let controller = Controller(windows: windows, hotkeys: FakeHotkeys(), config: config)
        controller.start()
        return (controller, windows)
    }

    func open(_ id: Int, _ windows: FakeWindows) {
        windows.add(id)
        windows.onEvent?(.opened(WindowInfo(id: WindowID(id), isManageable: true)))
    }

    func testNextCreatesPageOnlyWhenCurrentHasWindows() {
        let (c, _) = make([1])
        c.handle(.nextPage)
        XCTAssertEqual(c.pages.count, 2)
        XCTAssertEqual(c.currentPage, 1)
        let (empty, _) = make([])
        empty.handle(.nextPage)
        XCTAssertEqual(empty.pages.count, 1)
        XCTAssertEqual(empty.currentPage, 0)
    }

    func testNextOnEmptyLastPageIsNoOp() {
        let (c, _) = make([1])
        c.handle(.nextPage)
        c.handle(.nextPage)
        XCTAssertEqual(c.pages.count, 2)
        XCTAssertEqual(c.currentPage, 1)
    }

    func testPreviousAtFirstPageIsNoOp() {
        let (c, w) = make([1])
        let calls = w.setFrameCalls.count
        c.handle(.previousPage)
        XCTAssertEqual(c.currentPage, 0)
        XCTAssertEqual(w.setFrameCalls.count, calls)
    }

    func testSwitchingParksAndUnparks() {
        let (c, w) = make([1])
        let before = w.lastRect(1)!
        c.handle(.nextPage)
        XCTAssertEqual(w.lastRect(1), CGRect(x: 999, y: 0, width: before.width, height: before.height))
        open(2, w)
        c.handle(.previousPage)
        XCTAssertEqual(w.lastRect(1), before)
        XCTAssertEqual(w.lastRect(2)?.minX, 999)
        XCTAssertEqual(c.managedWindows, [WindowID(1)])
    }

    func testParkedWindowKeepsItsLastSize() {
        let (c, w) = make([1, 2])
        let size = w.lastRect(2)!.size
        c.handle(.nextPage)
        XCTAssertEqual(w.lastRect(2)?.size, size)
        XCTAssertEqual(w.lastRect(2)?.minY, 0)
    }

    func testMoveWindowToNextPageFollowsIt() {
        let (c, w) = make([1, 2])
        c.handle(.moveWindowToNextPage)
        XCTAssertEqual(c.currentPage, 1)
        XCTAssertEqual(c.pages[1].allWindows, [WindowID(2)])
        XCTAssertEqual(c.pages[0].allWindows, [WindowID(1)])
        XCTAssertEqual(w.focusCalls.last, 2)
        XCTAssertEqual(w.lastRect(1)?.minX, 999)
        c.handle(.moveWindowToPreviousPage)
        XCTAssertEqual(c.currentPage, 0)
        XCTAssertEqual(Set(c.pages[0].allWindows), [WindowID(1), WindowID(2)])
        XCTAssertEqual(w.focusCalls.last, 2)
    }

    func testMoveToPreviousAtFirstPageIsNoOp() {
        let (c, _) = make([1])
        c.handle(.moveWindowToPreviousPage)
        XCTAssertEqual(c.currentPage, 0)
        XCTAssertEqual(c.pages[0].allWindows, [WindowID(1)])
    }

    func testClosedWindowOnInactivePageIsRemoved() {
        let (c, w) = make([1])
        c.handle(.nextPage)
        open(2, w)
        c.handle(.previousPage)
        w.onEvent?(.closed(WindowID(2)))
        XCTAssertTrue(c.pages[1].allWindows.isEmpty)
    }

    func testFocusedEventOnInactivePageSwitches() {
        let (c, w) = make([1])
        c.handle(.nextPage)
        open(2, w)
        c.handle(.previousPage)
        w.onEvent?(.focused(WindowID(2)))
        XCTAssertEqual(c.currentPage, 1)
        XCTAssertEqual(c.workspace.focusedWindow, WindowID(2))
        XCTAssertEqual(w.lastRect(1)?.minX, 999)
        XCTAssertNotEqual(w.lastRect(2)?.minX, 999)
    }

    func testTrailingEmptyPagesAreTrimmed() {
        let (c, w) = make([1])
        c.handle(.nextPage)
        open(2, w)
        c.handle(.nextPage)
        XCTAssertEqual(c.pages.count, 3)
        w.onEvent?(.closed(WindowID(2)))
        c.handle(.previousPage)
        XCTAssertEqual(c.pages.count, 2)
        c.handle(.previousPage)
        XCTAssertEqual(c.pages.count, 1)
    }

    func testMaxPagesCap() {
        let (c, w) = make([1])
        for id in 2...12 {
            c.handle(.nextPage)
            open(id, w)
        }
        XCTAssertEqual(c.pages.count, Controller.maxPages)
        XCTAssertEqual(c.currentPage, Controller.maxPages - 1)
    }

    func testSnapshotIncludesPage() {
        let (c, _) = make([1])
        var last: WorkspaceSnapshot?
        c.onChange = { last = $0 }
        c.handle(.nextPage)
        XCTAssertEqual(last?.page, 1)
        XCTAssertEqual(last?.pageCount, 2)
    }
}
