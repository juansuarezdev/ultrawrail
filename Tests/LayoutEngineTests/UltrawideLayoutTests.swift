import XCTest
import CoreGraphics
@testable import LayoutEngine

final class UltrawideLayoutTests: XCTestCase {
    func workspace(columns: Int, width: Double, focus: Int = 0) -> Workspace {
        var ws = Workspace()
        ws.newColumnWidth = width
        for i in 1...columns { ws.addWindow(WindowID(i)) }
        ws.focus(window: WindowID(focus + 1))
        return ws
    }

    func testMaxColumnWidthCapsWideColumns() {
        let viewport = CGRect(x: 0, y: 0, width: 3440, height: 1440)
        var config = LayoutConfig(gap: 8, outerGap: 8)
        let uncapped = Layout.columnWidth(Column(windows: [1], width: 0.5), viewport: viewport, config: config)
        XCTAssertEqual(uncapped, 0.5 * (3440 - 16 + 8) - 8, accuracy: 0.001)
        config.maxColumnWidth = 800
        XCTAssertEqual(Layout.columnWidth(Column(windows: [1], width: 0.5), viewport: viewport, config: config), 800)
        let quarter = Layout.columnWidth(Column(windows: [1], width: 0.25), viewport: viewport, config: LayoutConfig(gap: 8, outerGap: 8))
        XCTAssertGreaterThan(quarter, 800)
        XCTAssertEqual(Layout.columnWidth(Column(windows: [1], width: 0.25), viewport: viewport, config: config), 800)
    }

    func testColumnBelowCapIsUnchanged() {
        let viewport = CGRect(x: 0, y: 0, width: 3440, height: 1440)
        let plain = LayoutConfig(gap: 8, outerGap: 8)
        var capped = plain
        capped.maxColumnWidth = 5000
        let column = Column(windows: [1], width: 0.25)
        XCTAssertEqual(Layout.columnWidth(column, viewport: viewport, config: capped),
                       Layout.columnWidth(column, viewport: viewport, config: plain))
    }

    func testCenteredFocusCentersMiddleColumnAndClampsEnds() {
        let viewport = CGRect(x: 0, y: 0, width: 1000, height: 800)
        let config = LayoutConfig(gap: 8, outerGap: 8, focusMode: .centered)
        var ws = workspace(columns: 5, width: 0.25, focus: 2)
        Layout.reveal(&ws, viewport: viewport, config: config)
        let rect = Layout.frames(ws, viewport: viewport, config: config)[3]!
        XCTAssertEqual(rect.midX, 500, accuracy: 0.001)

        ws.focus(window: 1)
        Layout.reveal(&ws, viewport: viewport, config: config)
        XCTAssertEqual(ws.scrollOffset, 0)

        ws.focus(window: 5)
        Layout.reveal(&ws, viewport: viewport, config: config)
        XCTAssertEqual(ws.scrollOffset, Layout.stripWidth(ws, viewport: viewport, config: config) - 1000, accuracy: 0.001)
    }

    func testMinimalModeScrollOffsetsMatchDefaultConfig() {
        let viewport = CGRect(x: 0, y: 0, width: 1000, height: 800)
        let defaults = LayoutConfig()
        let explicit = LayoutConfig(focusMode: .minimal)
        XCTAssertEqual(defaults, explicit)
        var ws = workspace(columns: 5, width: 0.25, focus: 2)
        Layout.reveal(&ws, viewport: viewport, config: defaults)
        XCTAssertEqual(ws.scrollOffset, 0)  // column 2 right edge 744+8 < 1000, already visible
        ws.focus(window: 5)
        Layout.reveal(&ws, viewport: viewport, config: defaults)
        XCTAssertEqual(ws.scrollOffset, 248, accuracy: 0.001)  // 1248 - 1000
    }

    func testCenterStripCentersNarrowGroup() {
        let viewport = CGRect(x: 0, y: 0, width: 1000, height: 800)
        var config = LayoutConfig(gap: 8, outerGap: 8)
        let ws = workspace(columns: 2, width: 0.25)
        var frames = Layout.frames(ws, viewport: viewport, config: config)
        XCTAssertEqual(frames[1]!.minX, 8)
        config.centerStrip = true
        frames = Layout.frames(ws, viewport: viewport, config: config)
        XCTAssertEqual(frames[1]!.minX - viewport.minX, viewport.maxX - frames[2]!.maxX, accuracy: 0.5)
        XCTAssertGreaterThan(frames[1]!.minX, 8)
    }

    func testCenterStripIgnoredWhenStripWiderThanViewport() {
        let viewport = CGRect(x: 0, y: 0, width: 1000, height: 800)
        var config = LayoutConfig(gap: 8, outerGap: 8)
        let ws = workspace(columns: 5, width: 0.25)
        let plain = Layout.frames(ws, viewport: viewport, config: config)
        config.centerStrip = true
        XCTAssertEqual(Layout.frames(ws, viewport: viewport, config: config), plain)
    }
}
