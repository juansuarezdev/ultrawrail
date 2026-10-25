import XCTest
import CoreGraphics
import LayoutEngine
@testable import UltrawrailCore

@MainActor
final class ControllerTemplateTests: XCTestCase {
    let config = LayoutConfig(gap: 10, outerGap: 10)

    func makeController(_ ids: [Int]) -> (Controller, FakeWindows) {
        let windows = FakeWindows()
        for id in ids { windows.add(id) }
        let controller = Controller(windows: windows, hotkeys: FakeHotkeys(), config: config)
        controller.start()
        return (controller, windows)
    }

    func testApplyTemplateRebuildsColumnsAndWritesFrames() {
        let (controller, windows) = makeController([1, 2, 3])
        controller.applyTemplate(Template.all[0], assignment: [3, 1])
        XCTAssertEqual(controller.workspace.columns.map(\.windows), [[3], [1], [2]])
        XCTAssertEqual(windows.lastRect(3)?.width, 485)
        XCTAssertEqual(windows.lastRect(3)?.origin.x, 10)
    }

    func testApplyTemplateKeepsFocusAndFocusesThatWindow() {
        let (controller, windows) = makeController([1, 2, 3])
        controller.applyTemplate(Template.all[0], assignment: [3, 2])
        XCTAssertEqual(controller.workspace.focusedWindow, 3)
        XCTAssertEqual(windows.focusCalls.last, 3)
    }

    func testManagedWindowsFollowColumnOrder() {
        let (controller, _) = makeController([1, 2, 3])
        controller.handle(.moveColumnLeft)
        XCTAssertEqual(controller.managedWindows, [1, 3, 2])
    }

    func testShowTemplatesCallsCallbackAndLeavesModelAlone() {
        let (controller, windows) = makeController([1, 2])
        var called = 0
        controller.onShowTemplates = { called += 1 }
        let before = windows.setFrameCalls.count
        controller.handle(.showTemplates)
        XCTAssertEqual(called, 1)
        XCTAssertEqual(controller.workspace.allWindows, [1, 2])
        XCTAssertEqual(windows.setFrameCalls.count, before)
    }
}
