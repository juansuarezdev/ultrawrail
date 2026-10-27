import XCTest
import CoreGraphics
import LayoutEngine
@testable import UltrawrailCore

@MainActor
final class FakeWindows: WindowService {
    var onEvent: ((WindowEvent) -> Void)?
    var existing: [WindowInfo] = []
    var alive: Set<WindowID> = []
    var failing: Set<WindowID> = []
    var frame = CGRect(x: 0, y: 0, width: 1000, height: 800)
    private(set) var setFrameCalls: [(id: WindowID, rect: CGRect, moveOnly: Bool)] = []
    private(set) var focusCalls: [WindowID] = []

    func add(_ id: Int, manageable: Bool = true) {
        existing.append(WindowInfo(id: WindowID(id), isManageable: manageable))
        alive.insert(WindowID(id))
    }

    func start() {}
    func allWindows() -> [WindowInfo] { existing }
    func usableFrame() -> CGRect { frame }
    func setFrame(_ rect: CGRect, for id: WindowID, moveOnly: Bool) -> Bool {
        setFrameCalls.append((id, rect, moveOnly))
        onSetFrame?()
        return !failing.contains(id)
    }
    var echoFocus = false
    var onSetFrame: (() -> Void)?
    func focus(_ id: WindowID) {
        focusCalls.append(id)
        if echoFocus { onEvent?(.focused(id)) }
    }
    func isAlive(_ id: WindowID) -> Bool { alive.contains(id) }
    var descriptions: [WindowID: WindowDescription] = [:]
    func describe(_ id: WindowID) -> WindowDescription? { descriptions[id] }
    func writes(_ id: Int) -> Int {
        setFrameCalls.filter { $0.id == WindowID(id) }.count
    }
    func lastRect(_ id: Int) -> CGRect? {
        setFrameCalls.last { $0.id == WindowID(id) }?.rect
    }
}

@MainActor
final class FakeHotkeys: HotkeyService {
    var onCommand: ((Command) -> Void)?
    func register(_ shortcuts: [ResolvedShortcut]) -> [String] { [] }
}

@MainActor
final class ControllerTests: XCTestCase {
    let config = LayoutConfig(gap: 10, outerGap: 10)

    func makeController(_ ids: [Int], unmanageable: [Int] = []) -> (Controller, FakeWindows) {
        let windows = FakeWindows()
        for id in ids { windows.add(id, manageable: !unmanageable.contains(id)) }
        let controller = Controller(windows: windows, hotkeys: FakeHotkeys(), config: config)
        controller.start()
        return (controller, windows)
    }

    func testStartLaysOutExistingWindows() {
        let (_, windows) = makeController([1, 2, 3])
        XCTAssertEqual(windows.lastRect(1), CGRect(x: -484, y: 10, width: 485, height: 780))
        XCTAssertEqual(windows.lastRect(2), CGRect(x: 10, y: 10, width: 485, height: 780))
        XCTAssertEqual(windows.lastRect(3), CGRect(x: 505, y: 10, width: 485, height: 780))
    }

    func testFocusLeftCommandMovesStripAndFocusesWindow() {
        let (controller, windows) = makeController([1, 2, 3])
        controller.handle(.focusLeft)
        controller.handle(.focusLeft)
        XCTAssertEqual(windows.focusCalls.last, 1)
        XCTAssertEqual(windows.lastRect(1), CGRect(x: 10, y: 10, width: 485, height: 780))
        XCTAssertEqual(windows.lastRect(3), CGRect(x: 999, y: 10, width: 485, height: 780))
    }

    func testUnmanageableWindowsAreIgnored() {
        let (controller, windows) = makeController([1, 2], unmanageable: [2])
        XCTAssertEqual(controller.workspace.allWindows, [1])
        XCTAssertNil(windows.lastRect(2))
    }

    func testUnchangedLayoutIsNotRewritten() {
        let (controller, windows) = makeController([1, 2, 3, 4])
        let before1 = windows.writes(1), before2 = windows.writes(2)
        let before3 = windows.writes(3), before4 = windows.writes(4)
        controller.handle(.focused(2))
        // Focusing 2 scrolls the strip from 990 to 495: 2, 3 and 4 move once, parked 1 does not change.
        XCTAssertEqual(windows.writes(1), before1)
        XCTAssertEqual(windows.writes(2) - before2, 1)
        XCTAssertEqual(windows.writes(3) - before3, 1)
        XCTAssertEqual(windows.writes(4) - before4, 1)
    }

    func testFocusedEventRewritesThatWindowSoManualMovesSnapBack() {
        let (controller, windows) = makeController([1, 2, 3])
        let before = windows.writes(2)
        controller.handle(.focused(2))
        XCTAssertEqual(windows.writes(2), before + 1)
    }

    func testOpenedUnmanageableWindowIsIgnored() {
        let (controller, windows) = makeController([1, 2])
        let before = windows.setFrameCalls.count
        windows.alive.insert(9)
        controller.handle(.opened(WindowInfo(id: 9, isManageable: false)))
        XCTAssertEqual(controller.workspace.allWindows, [1, 2])
        XCTAssertEqual(windows.setFrameCalls.count, before)
    }

    func testFocusedUnknownWindowIsIgnored() {
        let (controller, windows) = makeController([1, 2])
        let before = windows.setFrameCalls.count
        controller.handle(.focused(42))
        XCTAssertEqual(controller.workspace.focusedWindow, 2)
        XCTAssertEqual(windows.setFrameCalls.count, before)
    }

    func testSynchronousFocusEchoCausesNoLoopAndNoExtraWrites() {
        let (controller, windows) = makeController([1, 2, 3])
        windows.echoFocus = true
        let before = windows.setFrameCalls.count
        controller.handle(.focusLeft)
        controller.handle(.focusLeft)
        XCTAssertEqual(windows.focusCalls, [2, 1])
        // Focusing 2 changes no frame; the echoed event rewrites 2 once (1 write).
        // Focusing 1 scrolls the strip: 1, 2 and 3 move once and the echoed event rewrites 1 once more (4 writes).
        XCTAssertEqual(windows.setFrameCalls.count - before, 5)
    }

    func testFocusedEventUpdatesModelWithoutRefocusing() {
        let (controller, windows) = makeController([1, 2, 3])
        controller.handle(.focused(1))
        XCTAssertEqual(controller.workspace.focusedWindow, 1)
        XCTAssertTrue(windows.focusCalls.isEmpty)
    }

    func testOpenedEventAddsWindowRightOfFocusAndFocusesIt() {
        let (controller, windows) = makeController([1, 2, 3])
        controller.handle(.focused(2))
        windows.alive.insert(4)
        controller.handle(.opened(WindowInfo(id: 4, isManageable: true)))
        XCTAssertEqual(controller.workspace.allWindows, [1, 2, 4, 3])
        XCTAssertEqual(controller.workspace.focusedWindow, 4)
    }

    func testClosedEventRemovesWindowAndRelayouts() {
        let (controller, windows) = makeController([1, 2, 3])
        controller.handle(.closed(2))
        XCTAssertEqual(controller.workspace.allWindows, [1, 3])
        XCTAssertEqual(windows.lastRect(1), CGRect(x: 10, y: 10, width: 485, height: 780))
        XCTAssertEqual(windows.lastRect(3), CGRect(x: 505, y: 10, width: 485, height: 780))
    }

    func testDeadWindowIsRemovedOnRelayout() {
        let (controller, windows) = makeController([1, 2, 3])
        windows.alive.remove(2)
        controller.screenChanged()
        XCTAssertEqual(controller.workspace.allWindows, [1, 3])
    }

    func testWindowFailingThreeTimesIsDropped() {
        let windows = FakeWindows()
        for id in [1, 2, 3] { windows.add(id) }
        windows.failing = [2]
        let controller = Controller(windows: windows, hotkeys: FakeHotkeys(), config: config)
        controller.start()
        XCTAssertTrue(controller.workspace.contains(2))
        controller.handle(.focused(3))
        XCTAssertTrue(controller.workspace.contains(2))
        controller.handle(.focused(3))
        XCTAssertEqual(controller.workspace.allWindows, [1, 3])
    }

    func testScreenChangedRewritesEveryWindow() {
        let (controller, windows) = makeController([1, 2, 3])
        let before = windows.setFrameCalls.count
        controller.screenChanged()
        XCTAssertEqual(windows.setFrameCalls.count, before + 3)
    }
}

@MainActor
final class ControllerCanvasTests: XCTestCase {
    func makeController(_ ids: [Int]) -> (Controller, FakeWindows) {
        let windows = FakeWindows()
        for id in ids { windows.add(id, manageable: true) }
        let controller = Controller(windows: windows, hotkeys: FakeHotkeys(), config: LayoutConfig(gap: 10, outerGap: 10))
        controller.start()
        return (controller, windows)
    }

    func testOverviewExposesColumnsAndViewport() {
        let (controller, _) = makeController([1, 2])
        let zone = controller.overview()[0]
        XCTAssertEqual(zone.pages[0].columns.map(\.windows), [[WindowID(1)], [WindowID(2)]])
        XCTAssertFalse(zone.viewport.isEmpty)
    }

    func testStackOntoSamePageMergesColumns() {
        let (controller, _) = makeController([1, 2, 3])
        controller.stack(WindowID(3), onto: WindowID(1))
        XCTAssertEqual(controller.overview()[0].pages[0].columns.map(\.windows),
                       [[WindowID(1), WindowID(3)], [WindowID(2)]])
    }

    func testStackOntoWindowOfAnotherPageMovesIt() {
        let (controller, _) = makeController([1, 2])
        controller.moveWindow(WindowID(2), toZone: 0, page: 1)
        controller.stack(WindowID(1), onto: WindowID(2))
        let pages = controller.overview()[0].pages
        XCTAssertEqual(pages.count, 2)
        XCTAssertEqual(pages.last?.columns.map(\.windows), [[WindowID(2), WindowID(1)]])
    }

    func testRevealSwitchesPageAndFocuses() {
        let (controller, windows) = makeController([1, 2])
        controller.moveWindow(WindowID(2), toZone: 0, page: 1)
        controller.reveal(WindowID(2))
        let pages = controller.overview()[0].pages
        XCTAssertTrue(pages[1].isCurrent)
        XCTAssertEqual(windows.focusCalls.last, WindowID(2))
    }
}
