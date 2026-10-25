import XCTest
import CoreGraphics
import LayoutEngine
@testable import PanerailCore

@MainActor
final class ControllerPlacementTests: XCTestCase {
    let config = LayoutConfig(gap: 10, outerGap: 10)

    func makeController(_ ids: [Int], placement: PlacementMode = .manual) -> (Controller, FakeWindows) {
        let windows = FakeWindows()
        for id in ids { windows.add(id) }
        let controller = Controller(windows: windows, hotkeys: FakeHotkeys(), config: config)
        controller.placement = placement
        controller.start()
        return (controller, windows)
    }

    func open(_ id: Int, in windows: FakeWindows, controller: Controller) {
        windows.alive.insert(WindowID(id))
        controller.handle(.opened(WindowInfo(id: WindowID(id), isManageable: true)))
    }

    func testManualModeLeavesNewWindowOutOfTheStrip() {
        let (controller, windows) = makeController([1, 2])
        let before = windows.setFrameCalls.count
        open(3, in: windows, controller: controller)
        XCTAssertEqual(controller.workspace.allWindows, [1, 2])
        XCTAssertEqual(controller.pendingCount, 1)
        XCTAssertEqual(windows.setFrameCalls.count, before)
    }

    func testAdoptCommandPlacesNewWindowAndFocusesIt() {
        let (controller, windows) = makeController([1, 2])
        open(3, in: windows, controller: controller)
        controller.handle(.adoptWindow)
        XCTAssertEqual(controller.workspace.allWindows, [1, 2, 3])
        XCTAssertEqual(controller.workspace.focusedWindow, 3)
        XCTAssertEqual(controller.pendingCount, 0)
        XCTAssertEqual(windows.focusCalls.last, 3)
        XCTAssertNotNil(windows.lastRect(3))
    }

    func testAdoptWithNothingPendingChangesNothing() {
        let (controller, windows) = makeController([1, 2])
        let before = windows.setFrameCalls.count
        controller.handle(.adoptWindow)
        XCTAssertEqual(controller.workspace.allWindows, [1, 2])
        XCTAssertEqual(windows.setFrameCalls.count, before)
        XCTAssertTrue(windows.focusCalls.isEmpty)
    }

    func testFocusingAPendingWindowSelectsItForAdoption() {
        let (controller, windows) = makeController([1])
        open(4, in: windows, controller: controller)
        open(5, in: windows, controller: controller)
        controller.handle(.focused(4))
        controller.handle(.adoptWindow)
        XCTAssertEqual(controller.workspace.allWindows, [1, 4])
        XCTAssertEqual(controller.pendingCount, 1)
    }

    func testClosingAPendingWindowRemovesIt() {
        let (controller, windows) = makeController([1])
        open(4, in: windows, controller: controller)
        controller.handle(.closed(4))
        XCTAssertEqual(controller.pendingCount, 0)
        controller.handle(.adoptWindow)
        XCTAssertEqual(controller.workspace.allWindows, [1])
    }

    func testAutomaticModeAdoptsOnOpen() {
        let (controller, windows) = makeController([1], placement: .automatic)
        open(2, in: windows, controller: controller)
        XCTAssertEqual(controller.workspace.allWindows, [1, 2])
        XCTAssertEqual(controller.pendingCount, 0)
    }

    func testSwitchingToAutomaticAdoptsPendingWindows() {
        let (controller, windows) = makeController([1])
        open(2, in: windows, controller: controller)
        open(3, in: windows, controller: controller)
        controller.placement = .automatic
        XCTAssertEqual(Set(controller.workspace.allWindows), [1, 2, 3])
        XCTAssertEqual(controller.pendingCount, 0)
    }

    func testWindowsPresentAtStartAreAlwaysAdopted() {
        let (controller, _) = makeController([1, 2, 3])
        XCTAssertEqual(controller.workspace.allWindows, [1, 2, 3])
        XCTAssertEqual(controller.pendingCount, 0)
    }
}
