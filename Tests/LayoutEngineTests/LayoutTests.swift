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
        XCTAssertEqual(frames[1], CGRect(x: 10, y: 10, width: 485, height: 780))
    }

    func testViewportOriginIsRespected() {
        let shifted = CGRect(x: 100, y: 50, width: 1000, height: 800)
        let frames = Layout.frames(makeWorkspace(1), viewport: shifted, config: config)
        XCTAssertEqual(frames[1], CGRect(x: 110, y: 60, width: 485, height: 780))
    }

    func testRevealScrollsMinimumAmountToTheRight() {
        var ws = makeWorkspace(3)
        Layout.reveal(&ws, viewport: viewport, config: config)
        XCTAssertEqual(ws.scrollOffset, 495)
        let frames = Layout.frames(ws, viewport: viewport, config: config)
        XCTAssertEqual(frames[1], CGRect(x: -484, y: 10, width: 485, height: 780))
        XCTAssertEqual(frames[2], CGRect(x: 10, y: 10, width: 485, height: 780))
        XCTAssertEqual(frames[3], CGRect(x: 505, y: 10, width: 485, height: 780))
    }

    func testWindowsFullyLeftOfViewportAreParkedWithOnePixelVisible() {
        var ws = makeWorkspace(3)
        Layout.reveal(&ws, viewport: viewport, config: config)
        let frames = Layout.frames(ws, viewport: viewport, config: config)
        XCTAssertEqual(frames[1], CGRect(x: -484, y: 10, width: 485, height: 780))
        XCTAssertEqual(frames[2], CGRect(x: 10, y: 10, width: 485, height: 780))
        XCTAssertEqual(frames[3], CGRect(x: 505, y: 10, width: 485, height: 780))
    }

    func testRevealScrollsBackLeftAndParksRightWindows() {
        var ws = makeWorkspace(3)
        Layout.reveal(&ws, viewport: viewport, config: config)
        ws.focus(window: 1)
        Layout.reveal(&ws, viewport: viewport, config: config)
        XCTAssertEqual(ws.scrollOffset, 0)
        let frames = Layout.frames(ws, viewport: viewport, config: config)
        XCTAssertEqual(frames[1], CGRect(x: 10, y: 10, width: 485, height: 780))
        XCTAssertEqual(frames[3], CGRect(x: 999, y: 10, width: 485, height: 780))
    }

    func testParkingBoundsMoveOverflowColumnsToTheirEdges() {
        let slice = CGRect(x: 500, y: 0, width: 500, height: 800)
        let display = CGRect(x: 0, y: 0, width: 1000, height: 800)
        var ws = makeWorkspace(3)
        Layout.reveal(&ws, viewport: slice, config: config)
        var frames = Layout.frames(ws, viewport: slice, config: config, parkingBounds: display)
        XCTAssertEqual(frames[1], CGRect(x: -234, y: 10, width: 235, height: 780))
        XCTAssertEqual(frames[3], CGRect(x: 755, y: 10, width: 235, height: 780))
        XCTAssertEqual(Layout.frames(ws, viewport: slice, config: config)[1]?.minX, 266)
        let left = CGRect(x: 0, y: 0, width: 500, height: 800)
        ws.focus(window: 1)
        Layout.reveal(&ws, viewport: left, config: config)
        frames = Layout.frames(ws, viewport: left, config: config, parkingBounds: display)
        XCTAssertEqual(frames[3]?.minX, 999)
        XCTAssertEqual(Layout.frames(ws, viewport: left, config: config)[3]?.minX, 499)
    }

    func testStackedWindowsSplitHeightEvenly() {
        var ws = makeWorkspace(2)
        ws.apply(.stackLeft)
        let frames = Layout.frames(ws, viewport: viewport, config: config)
        XCTAssertEqual(frames[1], CGRect(x: 10, y: 10, width: 485, height: 385))
        XCTAssertEqual(frames[2], CGRect(x: 10, y: 405, width: 485, height: 385))
    }

    func testCenterPutsFocusedColumnInTheMiddle() {
        var ws = makeWorkspace(1)
        Layout.center(&ws, viewport: viewport, config: config)
        let frames = Layout.frames(ws, viewport: viewport, config: config)
        XCTAssertEqual(frames[1], CGRect(x: 257.5, y: 10, width: 485, height: 780))
    }

    func testPerformFocusLeftRevealsTheNewFocus() {
        var ws = makeWorkspace(3)
        Layout.reveal(&ws, viewport: viewport, config: config)
        XCTAssertEqual(ws.scrollOffset, 495)
        ws.perform(.focusLeft, viewport: viewport, config: config)
        XCTAssertEqual(ws.focusedWindow, 2)
        XCTAssertEqual(ws.scrollOffset, 495)
        ws.perform(.focusLeft, viewport: viewport, config: config)
        XCTAssertEqual(ws.focusedWindow, 1)
        XCTAssertEqual(ws.scrollOffset, 0)
    }

    func testPerformCenterColumnCenters() {
        var ws = makeWorkspace(1)
        ws.perform(.centerColumn, viewport: viewport, config: config)
        XCTAssertEqual(ws.scrollOffset, -247.5)
    }

    func testRemoveOverscrollLowersScrollWhenStripEndsBeforeViewportEdge() {
        var ws = makeWorkspace(3)
        ws.scrollOffset = 700
        Layout.removeOverscroll(&ws, viewport: viewport, config: config)
        XCTAssertEqual(ws.scrollOffset, 495)
    }

    func testRemoveOverscrollKeepsNegativeAndFittingScroll() {
        var ws = makeWorkspace(1)
        ws.scrollOffset = -247.5
        Layout.removeOverscroll(&ws, viewport: viewport, config: config)
        XCTAssertEqual(ws.scrollOffset, -247.5)
        ws = makeWorkspace(3)
        Layout.reveal(&ws, viewport: viewport, config: config)
        Layout.removeOverscroll(&ws, viewport: viewport, config: config)
        XCTAssertEqual(ws.scrollOffset, 495)
    }

    func testPerformShrinkingLastColumnLowersScroll() {
        var ws = makeWorkspace(3)
        ws.perform(.focusRight, viewport: viewport, config: config)
        ws.perform(.toggleFullWidth, viewport: viewport, config: config)
        XCTAssertEqual(ws.scrollOffset, 990)
        ws.perform(.toggleFullWidth, viewport: viewport, config: config)
        XCTAssertEqual(ws.scrollOffset, 495)
    }

    func testStripRectsUseStripCoordinatesAndViewportRelativeY() {
        let rects = Layout.stripRects(makeWorkspace(3), viewport: viewport, config: config)
        XCTAssertEqual(rects[1], CGRect(x: 10, y: 10, width: 485, height: 780))
        XCTAssertEqual(rects[2], CGRect(x: 505, y: 10, width: 485, height: 780))
        XCTAssertEqual(rects[3], CGRect(x: 1000, y: 10, width: 485, height: 780))
    }

    func testStripWidthCoversAllColumnsPlusOuterGap() {
        XCTAssertEqual(Layout.stripWidth(makeWorkspace(3), viewport: viewport, config: config), 1495)
        XCTAssertEqual(Layout.stripWidth(Workspace(), viewport: viewport, config: config), 0)
    }

    func testTwoHalfColumnsFillTheViewportAndFocusChangesDoNotScroll() {
        var ws = makeWorkspace(2)
        XCTAssertEqual(Layout.stripWidth(ws, viewport: viewport, config: config), 1000)
        ws.focus(window: 1)
        Layout.reveal(&ws, viewport: viewport, config: config)
        XCTAssertEqual(ws.scrollOffset, 0)
        ws.focus(window: 2)
        Layout.reveal(&ws, viewport: viewport, config: config)
        XCTAssertEqual(ws.scrollOffset, 0)
        ws.focus(window: 1)
        Layout.reveal(&ws, viewport: viewport, config: config)
        XCTAssertEqual(ws.scrollOffset, 0)
    }

    func testFullWidthColumnEqualsUsableWidth() {
        var ws = makeWorkspace(1)
        ws.apply(.toggleFullWidth)
        let frames = Layout.frames(ws, viewport: viewport, config: config)
        XCTAssertEqual(frames[1]?.width, 980)
    }

    func testTwoThirdsAndOneThirdColumnsNeverExceedTheViewport() {
        var ws = Workspace()
        ws.newColumnWidth = 0.66
        ws.addWindow(1)
        ws.newColumnWidth = 0.33
        ws.addWindow(2)
        XCTAssertLessThanOrEqual(Layout.stripWidth(ws, viewport: viewport, config: config), 1000)
    }
}
