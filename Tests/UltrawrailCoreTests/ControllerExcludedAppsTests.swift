import XCTest
import CoreGraphics
import LayoutEngine
@testable import UltrawrailCore

@MainActor
final class ControllerExcludedAppsTests: XCTestCase {
    let config = LayoutConfig(gap: 10, outerGap: 10)
    let mail = "com.apple.mail"
    let term = "com.apple.Terminal"

    /// Windows 1 and 2 belong to Mail, 3 to Terminal; every window is added before `start`.
    func make(_ ids: [Int], excluded: Set<String> = []) -> (Controller, FakeWindows) {
        let windows = FakeWindows()
        for id in ids { windows.add(id); describe(id, windows) }
        let controller = Controller(windows: windows, hotkeys: FakeHotkeys(), config: config)
        controller.excludedApps = excluded
        controller.start()
        return (controller, windows)
    }

    func describe(_ id: Int, _ windows: FakeWindows) {
        windows.descriptions[WindowID(id)] =
            WindowDescription(appName: "App", pid: Int32(id), bundleID: id <= 2 ? mail : term)
    }

    func open(_ id: Int, _ windows: FakeWindows) {
        windows.add(id)
        describe(id, windows)
        windows.onEvent?(.opened(WindowInfo(id: WindowID(id), isManageable: true)))
    }

    func testExcludedAppAtStartIsNotManaged() {
        let (c, w) = make([1, 3], excluded: [mail])
        XCTAssertEqual(c.managedWindows, [WindowID(3)])
        XCTAssertEqual(w.writes(1), 0)
    }

    func testExcludedAppOpenedWindowIsNotManaged() {
        let (c, w) = make([3], excluded: [mail])
        open(1, w)
        XCTAssertEqual(c.managedWindows, [WindowID(3)])
        XCTAssertEqual(w.writes(1), 0)
    }

    func testNonExcludedAppOpenedWindowIsManaged() {
        let (c, w) = make([1], excluded: [mail])
        open(3, w)
        XCTAssertEqual(c.managedWindows, [WindowID(3)])
    }

    func testSettingExcludedAppsForgetsItsWindowsAndKeepsOthers() {
        let (c, w) = make([1, 2, 3])
        XCTAssertEqual(Set(c.managedWindows), [WindowID(1), WindowID(2), WindowID(3)])
        let writes = w.writes(1)
        c.excludedApps = [mail]
        XCTAssertEqual(c.managedWindows, [WindowID(3)])
        XCTAssertEqual(w.writes(1), writes)
        XCTAssertEqual(w.lastRect(3)?.minX, 10)
    }

    func testForgetsExcludedWindowsOnOtherPagesAndZones() {
        let (c, _) = make([1, 3])
        c.handle(.nextPage)
        XCTAssertEqual(c.pages.count, 2)
        c.excludedApps = [mail]
        XCTAssertEqual(c.pages.flatMap(\.allWindows), [WindowID(3)])
    }

    func testRemovingAppFromSetAdoptsItsWindowsAgain() {
        let (c, w) = make([1, 2, 3], excluded: [mail])
        XCTAssertEqual(c.managedWindows, [WindowID(3)])
        c.excludedApps = []
        XCTAssertEqual(Set(c.managedWindows), [WindowID(1), WindowID(2), WindowID(3)])
        XCTAssertNotNil(w.lastRect(1))
    }

    func testReallowedUnmanageableWindowIsNotAdopted() {
        let (c, w) = make([3], excluded: [mail])
        w.add(1, manageable: false)
        describe(1, w)
        c.excludedApps = []
        XCTAssertEqual(c.managedWindows, [WindowID(3)])
    }

    func testManualModeExcludedWindowNeverPending() {
        let (c, w) = make([], excluded: [mail])
        c.placement = .manual
        open(1, w)
        XCTAssertEqual(c.pendingCount, 0)
        open(3, w)
        XCTAssertEqual(c.pendingCount, 1)
        XCTAssertEqual(c.managedWindows, [])
    }

    func testManualModeExcludingDropsPendingWindow() {
        let (c, w) = make([])
        c.placement = .manual
        open(1, w)
        XCTAssertEqual(c.pendingCount, 1)
        c.excludedApps = [mail]
        XCTAssertEqual(c.pendingCount, 0)
        c.placement = .automatic
        XCTAssertEqual(c.managedWindows, [])
    }

    func testNilDescriptionOrBundleIsNotExcluded() {
        let (c, w) = make([], excluded: [mail])
        w.add(7)
        w.onEvent?(.opened(WindowInfo(id: WindowID(7), isManageable: true)))
        w.add(8)
        w.descriptions[WindowID(8)] = WindowDescription(appName: "X", pid: 8)
        w.onEvent?(.opened(WindowInfo(id: WindowID(8), isManageable: true)))
        XCTAssertEqual(Set(c.managedWindows), [WindowID(7), WindowID(8)])
    }

    func testEmptySetKeepsBehaviour() {
        let (c, w) = make([1, 2, 3])
        XCTAssertEqual(Set(c.managedWindows), [WindowID(1), WindowID(2), WindowID(3)])
        open(4, w)
        XCTAssertEqual(c.managedWindows.count, 4)
        c.excludedApps = []
        XCTAssertEqual(c.managedWindows.count, 4)
    }
}
