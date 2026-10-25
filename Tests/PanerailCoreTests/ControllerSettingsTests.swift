import XCTest
import CoreGraphics
import LayoutEngine
@testable import PanerailCore

@MainActor
final class ControllerSettingsTests: XCTestCase {
    func makeController(_ ids: [Int]) -> (Controller, FakeWindows) {
        let windows = FakeWindows()
        for id in ids { windows.add(id) }
        let controller = Controller(windows: windows, hotkeys: FakeHotkeys(), config: LayoutConfig(gap: 10, outerGap: 10))
        controller.start()
        return (controller, windows)
    }

    func testChangingConfigRelaysOutEveryWindow() {
        let (controller, windows) = makeController([1, 2])
        XCTAssertEqual(windows.lastRect(2)?.origin.y, 10)
        controller.config = LayoutConfig(gap: 20, outerGap: 20)
        XCTAssertEqual(windows.lastRect(2)?.origin.y, 20)
        XCTAssertEqual(windows.lastRect(2)?.height, 760)
        XCTAssertEqual(windows.lastRect(1)?.origin.y, 20)
    }

    func testSettingSameConfigWritesNothing() {
        let (controller, windows) = makeController([1, 2])
        let before = windows.setFrameCalls.count
        controller.config = LayoutConfig(gap: 10, outerGap: 10)
        XCTAssertEqual(windows.setFrameCalls.count, before)
    }

    func testNewColumnWidthAffectsOnlyColumnsAddedLater() {
        let (controller, windows) = makeController([1])
        controller.newColumnWidth = 0.33
        XCTAssertEqual(controller.workspace.columns.map(\.width), [0.5])
        windows.alive.insert(2)
        controller.handle(.opened(WindowInfo(id: 2, isManageable: true)))
        XCTAssertEqual(controller.workspace.columns.map(\.width), [0.5, 0.33])
    }

    func testShrinkingGapsAtStripEndLeavesNoBlankSpace() throws {
        let (controller, windows) = makeController([1, 2, 3])
        controller.handle(.focused(3))
        let tight = LayoutConfig(gap: 0, outerGap: 0)
        controller.config = tight
        let viewport = windows.frame
        let width = Layout.stripWidth(controller.workspace, viewport: viewport, config: tight)
        let expectedMaxX = viewport.minX + min(width, viewport.width) - tight.outerGap
        XCTAssertEqual(try XCTUnwrap(windows.lastRect(3)).maxX, CGFloat(expectedMaxX), accuracy: 0.5)
    }
}
