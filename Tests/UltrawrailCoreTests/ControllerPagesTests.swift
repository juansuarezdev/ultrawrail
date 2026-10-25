import XCTest
import CoreGraphics
import LayoutEngine
@testable import UltrawrailCore

@MainActor
final class ControllerPagesTests: XCTestCase {
    let config = LayoutConfig(gap: 10, outerGap: 10)

    var clock: Double = 0

    func make(_ ids: [Int]) -> (Controller, FakeWindows) {
        let windows = FakeWindows()
        for id in ids { windows.add(id) }
        let controller = Controller(windows: windows, hotkeys: FakeHotkeys(), config: config,
                                    now: { [unowned self] in self.clock })
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
        clock += 1
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

    func testParkingFailuresDropWindow() {
        let (c, w) = make([1, 2])
        w.failing = [1]
        c.handle(.nextPage)
        c.screenChanged()
        c.screenChanged()
        XCTAssertEqual(c.pages[0].allWindows, [WindowID(2)])
    }

    func testScreenChangedReparksInactivePages() {
        let (c, w) = make([1, 2])
        c.handle(.nextPage)
        open(3, w)
        let size = w.lastRect(1)!.size
        w.frame = CGRect(x: 0, y: 0, width: 1200, height: 800)
        c.screenChanged()
        XCTAssertEqual(w.lastRect(1)?.minX, 1199)
        XCTAssertEqual(w.lastRect(2)?.minX, 1199)
        XCTAssertEqual(w.lastRect(1)?.size, size)
        XCTAssertNotEqual(w.lastRect(3)?.minX, 1199)
    }

    func testFocusEchoRightAfterSwitchIsIgnoredUntilSuppressionExpires() {
        let (c, w) = make([1])
        c.handle(.nextPage)
        open(2, w)
        c.handle(.previousPage)
        w.onEvent?(.focused(WindowID(2)))
        XCTAssertEqual(c.currentPage, 0)
        clock += 0.5
        w.onEvent?(.focused(WindowID(2)))
        XCTAssertEqual(c.currentPage, 1)
    }

    func testRestoreParkedWindowsUsesOwnPageLayout() {
        let (c, w) = make([1, 2])
        c.handle(.nextPage)
        open(3, w)
        XCTAssertEqual(w.lastRect(1)?.minX, 999)
        let expected = Layout.frames(c.pages[0], viewport: w.frame, config: config)
        c.restoreParkedWindows()
        XCTAssertEqual(w.lastRect(1), expected[WindowID(1)])
        XCTAssertEqual(w.lastRect(2), expected[WindowID(2)])
        XCTAssertNotEqual(w.lastRect(1)?.minX, 999)
    }

    func testRepeatedOpenedDoesNotDuplicateAcrossPages() {
        let (c, w) = make([1])
        c.handle(.nextPage)
        open(2, w)
        c.handle(.previousPage)
        let info = WindowInfo(id: WindowID(2), isManageable: true)
        w.onEvent?(.opened(info))
        XCTAssertEqual(c.pages[0].allWindows, [WindowID(1)])
        XCTAssertEqual(c.pages[1].allWindows, [WindowID(2)])
        c.placement = .manual
        w.onEvent?(.opened(info))
        XCTAssertEqual(c.pendingCount, 0)
    }

    func testNewColumnWidthAppliesToAllPages() {
        let (c, _) = make([1])
        c.handle(.nextPage)
        c.newColumnWidth = 0.7
        XCTAssertTrue(c.pages.allSatisfy { $0.newColumnWidth == 0.7 })
    }

    func testApplyTemplateWithWindowsFromOtherPageIsNoOp() {
        let (c, w) = make([1, 2])
        c.handle(.nextPage)
        open(3, w)
        let before = c.pages
        let calls = w.setFrameCalls.count
        c.applyTemplate(Template.builtIn[0], assignment: [WindowID(1), WindowID(3)])
        XCTAssertEqual(c.pages, before)
        XCTAssertEqual(w.setFrameCalls.count, calls)
    }
}
