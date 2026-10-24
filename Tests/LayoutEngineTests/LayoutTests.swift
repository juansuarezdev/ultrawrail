import XCTest
import CoreGraphics
@testable import LayoutEngine

final class LayoutTests: XCTestCase {
    let viewport = CGRect(x: 0, y: 0, width: 1000, height: 800)
    let config = LayoutConfig(gap: 10, outerGap: 10)

    func makeWorkspace(_ count: Int) -> Workspace {
        var ws = Workspace()
        for i in 1...count { ws.addWindow(WindowID(i)) }
        return ws
    }

    func testSingleWindowGetsHalfOfUsableWidthMinusOuterGaps() {
        let frames = Layout.frames(makeWorkspace(1), viewport: viewport, config: config)
        XCTAssertEqual(frames[1], CGRect(x: 10, y: 10, width: 490, height: 780))
    }

    func testViewportOriginIsRespected() {
        let shifted = CGRect(x: 100, y: 50, width: 1000, height: 800)
        let frames = Layout.frames(makeWorkspace(1), viewport: shifted, config: config)
        XCTAssertEqual(frames[1], CGRect(x: 110, y: 60, width: 490, height: 780))
    }

    func testRevealScrollsMinimumAmountToTheRight() {
        var ws = makeWorkspace(2)
        Layout.reveal(&ws, viewport: viewport, config: config)
        XCTAssertEqual(ws.scrollOffset, 10)
        let frames = Layout.frames(ws, viewport: viewport, config: config)
        XCTAssertEqual(frames[1], CGRect(x: 0, y: 10, width: 490, height: 780))
        XCTAssertEqual(frames[2], CGRect(x: 500, y: 10, width: 490, height: 780))
    }

    func testWindowsFullyLeftOfViewportAreParkedWithOnePixelVisible() {
        var ws = makeWorkspace(3)
        Layout.reveal(&ws, viewport: viewport, config: config)
        let frames = Layout.frames(ws, viewport: viewport, config: config)
        XCTAssertEqual(frames[1], CGRect(x: -489, y: 10, width: 490, height: 780))
        XCTAssertEqual(frames[2], CGRect(x: 0, y: 10, width: 490, height: 780))
        XCTAssertEqual(frames[3], CGRect(x: 500, y: 10, width: 490, height: 780))
    }

    func testRevealScrollsBackLeftAndParksRightWindows() {
        var ws = makeWorkspace(3)
        Layout.reveal(&ws, viewport: viewport, config: config)
        ws.focus(window: 1)
        Layout.reveal(&ws, viewport: viewport, config: config)
        XCTAssertEqual(ws.scrollOffset, 0)
        let frames = Layout.frames(ws, viewport: viewport, config: config)
        XCTAssertEqual(frames[1], CGRect(x: 10, y: 10, width: 490, height: 780))
        XCTAssertEqual(frames[3], CGRect(x: 999, y: 10, width: 490, height: 780))
    }

    func testStackedWindowsSplitHeightEvenly() {
        var ws = makeWorkspace(2)
        ws.apply(.stackLeft)
        let frames = Layout.frames(ws, viewport: viewport, config: config)
        XCTAssertEqual(frames[1], CGRect(x: 10, y: 10, width: 490, height: 385))
        XCTAssertEqual(frames[2], CGRect(x: 10, y: 405, width: 490, height: 385))
    }

    func testCenterPutsFocusedColumnInTheMiddle() {
        var ws = makeWorkspace(1)
        Layout.center(&ws, viewport: viewport, config: config)
        let frames = Layout.frames(ws, viewport: viewport, config: config)
        XCTAssertEqual(frames[1], CGRect(x: 255, y: 10, width: 490, height: 780))
    }

    func testPerformFocusLeftRevealsTheNewFocus() {
        var ws = makeWorkspace(3)
        ws.perform(.focusLeft, viewport: viewport, config: config)
        XCTAssertEqual(ws.focusedWindow, 2)
        XCTAssertEqual(ws.scrollOffset, 10)
    }

    func testPerformCenterColumnCenters() {
        var ws = makeWorkspace(1)
        ws.perform(.centerColumn, viewport: viewport, config: config)
        XCTAssertEqual(ws.scrollOffset, -245)
    }

    func testRemoveOverscrollLowersScrollWhenStripEndsBeforeViewportEdge() {
        var ws = makeWorkspace(2)
        ws.scrollOffset = 510
        Layout.removeOverscroll(&ws, viewport: viewport, config: config)
        XCTAssertEqual(ws.scrollOffset, 10)
    }

    func testRemoveOverscrollKeepsNegativeAndFittingScroll() {
        var ws = makeWorkspace(1)
        ws.scrollOffset = -245
        Layout.removeOverscroll(&ws, viewport: viewport, config: config)
        XCTAssertEqual(ws.scrollOffset, -245)
        ws = makeWorkspace(3)
        Layout.reveal(&ws, viewport: viewport, config: config)
        Layout.removeOverscroll(&ws, viewport: viewport, config: config)
        XCTAssertEqual(ws.scrollOffset, 510)
    }

    func testPerformShrinkingLastColumnLowersScroll() {
        var ws = makeWorkspace(3)
        ws.perform(.focusRight, viewport: viewport, config: config)
        ws.perform(.toggleFullWidth, viewport: viewport, config: config)
        XCTAssertEqual(ws.scrollOffset, 1000)
        ws.perform(.toggleFullWidth, viewport: viewport, config: config)
        XCTAssertEqual(ws.scrollOffset, 510)
    }

    func testStripRectsUseStripCoordinatesAndViewportRelativeY() {
        let rects = Layout.stripRects(makeWorkspace(3), viewport: viewport, config: config)
        XCTAssertEqual(rects[1], CGRect(x: 10, y: 10, width: 490, height: 780))
        XCTAssertEqual(rects[2], CGRect(x: 510, y: 10, width: 490, height: 780))
        XCTAssertEqual(rects[3], CGRect(x: 1010, y: 10, width: 490, height: 780))
    }

    func testStripWidthCoversAllColumnsPlusOuterGap() {
        XCTAssertEqual(Layout.stripWidth(makeWorkspace(3), viewport: viewport, config: config), 1510)
        XCTAssertEqual(Layout.stripWidth(Workspace(), viewport: viewport, config: config), 0)
    }
}
