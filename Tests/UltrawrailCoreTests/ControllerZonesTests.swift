import XCTest
import CoreGraphics
import LayoutEngine
@testable import UltrawrailCore

@MainActor
final class ControllerZonesTests: XCTestCase {
    let config = LayoutConfig(gap: 10, outerGap: 10)

    var clock: Double = 0

    func make(_ ids: [Int], zones: Int = 1) -> (Controller, FakeWindows) {
        let windows = FakeWindows()
        for id in ids { windows.add(id) }
        let controller = Controller(windows: windows, hotkeys: FakeHotkeys(), config: config,
                                    now: { [unowned self] in self.clock })
        controller.start()
        controller.zoneCount = zones
        return (controller, windows)
    }

    func open(_ id: Int, _ windows: FakeWindows) {
        windows.add(id)
        windows.onEvent?(.opened(WindowInfo(id: WindowID(id), isManageable: true)))
    }

    func testZoneCountIsClamped() {
        let (c, _) = make([])
        c.zoneCount = 5
        XCTAssertEqual(c.zoneCount, 3)
        c.zoneCount = 0
        XCTAssertEqual(c.zoneCount, 1)
    }

    func testTwoZonesSplitWidthAndNewWindowsJoinFocusedZone() {
        let (c, w) = make([1], zones: 2)
        XCTAssertEqual(c.focusedZone, 0)
        let first = w.lastRect(1)!
        XCTAssertGreaterThanOrEqual(first.minX, 0)
        XCTAssertLessThanOrEqual(first.maxX, 500)
        c.handle(.focusZoneRight)
        XCTAssertEqual(c.focusedZone, 1)
        open(2, w)
        XCTAssertEqual(c.managedWindows, [WindowID(2)])
        XCTAssertEqual(c.zones[0].pages[0].allWindows, [WindowID(1)])
        let second = w.lastRect(2)!
        XCTAssertGreaterThanOrEqual(second.minX, 500)
        XCTAssertLessThanOrEqual(second.maxX, 1000)
        XCTAssertEqual(second.width, first.width)
    }

    func testFocusZoneFocusesThatZonesWindow() {
        let (c, w) = make([1], zones: 2)
        c.handle(.focusZoneRight)
        open(2, w)
        c.handle(.focusZoneLeft)
        XCTAssertEqual(c.focusedZone, 0)
        XCTAssertEqual(w.focusCalls.last, 1)
        c.handle(.focusZoneLeft)
        XCTAssertEqual(c.focusedZone, 0)
    }

    func testFocusEmptyZoneOnlyChangesZone() {
        let (c, w) = make([1], zones: 2)
        let calls = w.focusCalls.count
        c.handle(.focusZoneRight)
        XCTAssertEqual(c.focusedZone, 1)
        XCTAssertEqual(w.focusCalls.count, calls)
        c.handle(.focusZoneRight)
        XCTAssertEqual(c.focusedZone, 1)
    }

    func testMoveWindowToZoneFollowsIt() {
        let (c, w) = make([1, 2], zones: 2)
        c.handle(.moveWindowToZoneRight)
        XCTAssertEqual(c.focusedZone, 1)
        XCTAssertEqual(c.zones[1].pages[0].allWindows, [WindowID(2)])
        XCTAssertEqual(c.zones[0].pages[0].allWindows, [WindowID(1)])
        XCTAssertEqual(w.focusCalls.last, 2)
        XCTAssertGreaterThanOrEqual(w.lastRect(2)!.minX, 500)
        c.handle(.moveWindowToZoneLeft)
        XCTAssertEqual(c.focusedZone, 0)
        XCTAssertEqual(Set(c.zones[0].pages[0].allWindows), [WindowID(1), WindowID(2)])
        XCTAssertTrue(c.zones[1].pages[0].allWindows.isEmpty)
    }

    func testMoveWindowToEdgeZoneIsNoOp() {
        let (c, _) = make([1], zones: 2)
        c.handle(.moveWindowToZoneLeft)
        XCTAssertEqual(c.focusedZone, 0)
        XCTAssertEqual(c.zones[0].pages[0].allWindows, [WindowID(1)])
        c.handle(.moveWindowToZoneRight)
        c.handle(.moveWindowToZoneRight)
        XCTAssertEqual(c.focusedZone, 1)
        XCTAssertEqual(c.zones[1].pages[0].allWindows, [WindowID(1)])
    }

    func testShrinkingMergesIntoLastRemainingZone() {
        let (c, w) = make([1], zones: 3)
        c.handle(.focusZoneRight)
        open(2, w)
        c.handle(.focusZoneRight)
        open(3, w)
        c.zoneCount = 1
        XCTAssertEqual(c.zones.count, 1)
        XCTAssertEqual(c.focusedZone, 0)
        XCTAssertEqual(c.managedWindows, [WindowID(1), WindowID(2), WindowID(3)])
        XCTAssertLessThanOrEqual(w.lastRect(3)!.maxX, 1000)
    }

    func testFocusedEventInOtherZoneSwitchesZone() {
        let (c, w) = make([1], zones: 2)
        c.handle(.focusZoneRight)
        open(2, w)
        clock += 1
        w.onEvent?(.focused(WindowID(1)))
        XCTAssertEqual(c.focusedZone, 0)
        XCTAssertEqual(c.workspace.focusedWindow, WindowID(1))
    }

    func testPageSwitchParksOnlyThatZone() {
        let (c, w) = make([1], zones: 2)
        c.handle(.focusZoneRight)
        open(2, w)
        let one = w.lastRect(1)!
        c.handle(.nextPage)
        XCTAssertEqual(c.currentPage, 1)
        XCTAssertEqual(c.zones[0].currentPage, 0)
        XCTAssertEqual(w.lastRect(2)?.minX, 999)
        XCTAssertEqual(w.lastRect(1), one)
        c.handle(.focusZoneLeft)
        XCTAssertEqual(c.currentPage, 0)
        XCTAssertEqual(c.pages.count, 1)
    }

    func testParkingIsAtDisplayEdgeForEveryZone() {
        let (c, w) = make([1], zones: 2)
        c.handle(.nextPage)
        XCTAssertEqual(w.lastRect(1)?.minX, w.usableFrame().maxX - 1)
    }

    func testSnapshotIncludesZoneAndFocusedSlice() {
        let (c, w) = make([1])
        var last: WorkspaceSnapshot?
        c.onChange = { last = $0 }
        c.zoneCount = 2
        XCTAssertEqual(last?.zone, 0)
        XCTAssertEqual(last?.zoneCount, 2)
        XCTAssertEqual(last?.viewport, CGRect(x: 0, y: 0, width: 500, height: 800))
        c.handle(.focusZoneRight)
        XCTAssertEqual(last?.zone, 1)
        XCTAssertEqual(last?.viewport, CGRect(x: 500, y: 0, width: 500, height: 800))
        _ = w
    }

    func testClosedRemovesFromEveryZone() {
        let (c, w) = make([1], zones: 2)
        c.handle(.focusZoneRight)
        open(2, w)
        c.handle(.focusZoneLeft)
        w.onEvent?(.closed(WindowID(2)))
        XCTAssertTrue(c.zones[1].pages[0].allWindows.isEmpty)
    }

    func testRestoreParkedWindowsCoversAllZones() {
        let (c, w) = make([1], zones: 2)
        c.handle(.nextPage)
        open(3, w)
        c.handle(.focusZoneRight)
        open(2, w)
        c.handle(.nextPage)
        let slice1 = CGRect(x: 500, y: 0, width: 500, height: 800)
        let expected = Layout.frames(c.zones[1].pages[0], viewport: slice1, config: config)
        c.restoreParkedWindows()
        XCTAssertEqual(w.lastRect(2), expected[WindowID(2)])
        XCTAssertNotEqual(w.lastRect(1)?.minX, w.usableFrame().maxX - 1)
    }

    func testNewColumnWidthAppliesToAllZones() {
        let (c, _) = make([1], zones: 3)
        c.newColumnWidth = 0.7
        XCTAssertTrue(c.zones.allSatisfy { $0.pages.allSatisfy { $0.newColumnWidth == 0.7 } })
        c.zoneCount = 1
        c.zoneCount = 2
        XCTAssertEqual(c.zones[1].pages[0].newColumnWidth, 0.7)
    }
}
