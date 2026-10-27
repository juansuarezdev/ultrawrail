import XCTest
import CoreGraphics
import LayoutEngine
@testable import UltrawrailCore

@MainActor
final class ControllerOverviewTests: XCTestCase {
    let config = LayoutConfig(gap: 10, outerGap: 10)

    func make(_ ids: [Int], zones: Int = 1) -> (Controller, FakeWindows) {
        let windows = FakeWindows()
        for id in ids { windows.add(id) }
        let controller = Controller(windows: windows, hotkeys: FakeHotkeys(), config: config)
        controller.start()
        controller.zoneCount = zones
        return (controller, windows)
    }

    func ids(_ values: Int...) -> [WindowID] { values.map { WindowID($0) } }

    /// Zone 0: page 0 = [1, 2], page 1 = [3] (current). Zone 1: page 0 = [4].
    func populated() -> (Controller, FakeWindows) {
        let (c, w) = make([1, 2], zones: 2)
        w.add(3)
        c.handle(.nextPage)
        w.onEvent?(.opened(WindowInfo(id: WindowID(3), isManageable: true)))
        c.handle(.focusZoneRight)
        w.add(4)
        w.onEvent?(.opened(WindowInfo(id: WindowID(4), isManageable: true)))
        c.handle(.focusZoneLeft)
        return (c, w)
    }

    func testOverviewShape() {
        let (c, _) = populated()
        let overview = c.overview()
        XCTAssertEqual(overview.map(\.isFocused), [true, false])
        XCTAssertEqual(overview.map { $0.pages.map(\.windows) }, [[ids(1, 2), ids(3)], [ids(4)]])
        XCTAssertEqual(overview.map { $0.pages.map(\.isCurrent) }, [[false, true], [true]])
    }

    func testMoveBetweenPages() {
        let (c, _) = populated()
        c.moveWindow(WindowID(1), toZone: 0, page: 1)
        XCTAssertEqual(c.overview()[0].pages.map(\.windows).map(Set.init), [[WindowID(2)], [WindowID(1), WindowID(3)]])
        XCTAssertEqual(c.currentPage, 1)
        XCTAssertEqual(c.focusedZone, 0)
    }

    func testMoveToNewPage() {
        let (c, _) = populated()
        c.moveWindow(WindowID(1), toZone: 0, page: 2)
        let pages = c.overview()[0].pages
        XCTAssertEqual(pages.map(\.windows), [ids(2), ids(3), ids(1)])
        XCTAssertEqual(pages.map(\.isCurrent), [false, true, false])
    }

    func testMoveAcrossZones() {
        let (c, _) = populated()
        c.moveWindow(WindowID(1), toZone: 1, page: 0)
        XCTAssertEqual(Set(c.overview()[1].pages[0].windows), [WindowID(1), WindowID(4)])
        XCTAssertEqual(c.overview()[0].pages[0].windows, ids(2))
        XCTAssertEqual(c.focusedZone, 0)
    }

    func testInvalidTargetsAreNoOps() {
        let (c, _) = populated()
        let before = c.overview()
        c.moveWindow(WindowID(99), toZone: 0, page: 0)
        c.moveWindow(WindowID(1), toZone: 2, page: 0)
        c.moveWindow(WindowID(1), toZone: -1, page: 0)
        c.moveWindow(WindowID(1), toZone: 0, page: -1)
        c.moveWindow(WindowID(1), toZone: 0, page: 3)
        c.moveWindow(WindowID(1), toZone: 0, page: 0)
        XCTAssertEqual(c.overview(), before)
    }

    func testNewPageBeyondMaxIsNoOp() {
        let (c, _) = make(Array(1...10))
        for target in 1..<Controller.maxPages { c.moveWindow(WindowID(target + 1), toZone: 0, page: target) }
        XCTAssertEqual(c.overview()[0].pages.count, Controller.maxPages)
        c.moveWindow(WindowID(10), toZone: 0, page: Controller.maxPages)
        XCTAssertEqual(c.overview()[0].pages.count, Controller.maxPages)
        XCTAssertEqual(c.overview()[0].pages[0].windows, ids(1, 10))
    }

    func testParkedOrVisibleByTargetPage() {
        let (c, w) = populated()
        c.moveWindow(WindowID(1), toZone: 0, page: 1)
        XCTAssertLessThan(w.lastRect(1)!.minX, 1000 / 2)
        XCTAssertGreaterThanOrEqual(w.lastRect(1)!.minX, 0)
        c.moveWindow(WindowID(3), toZone: 0, page: 0)
        XCTAssertEqual(w.lastRect(3)!.minX, 999)
    }

    func testTrailingEmptyPageTrimmed() {
        let (c, _) = populated()
        c.moveWindow(WindowID(1), toZone: 0, page: 0)
        c.handle(.previousPage)
        c.moveWindow(WindowID(3), toZone: 0, page: 0)
        XCTAssertEqual(c.overview()[0].pages.count, 1)
    }

    func testFocusedWindowFollows() {
        let (c, w) = populated()
        c.moveWindow(WindowID(3), toZone: 1, page: 0)
        XCTAssertEqual(c.focusedZone, 1)
        XCTAssertEqual(w.focusCalls.last, 3)
        XCTAssertEqual(c.overview()[0].pages.map(\.windows), [ids(1, 2), []])
        c.moveWindow(WindowID(3), toZone: 0, page: 0)
        XCTAssertEqual(c.focusedZone, 0)
        XCTAssertEqual(c.currentPage, 0)
    }

    func testUnfocusedMoveKeepsFocus() {
        let (c, w) = populated()
        let calls = w.focusCalls.count
        c.moveWindow(WindowID(1), toZone: 1, page: 0)
        XCTAssertEqual(c.focusedZone, 0)
        XCTAssertEqual(c.currentPage, 1)
        XCTAssertEqual(w.focusCalls.count, calls)
    }
}
