import XCTest
import CoreGraphics
@testable import LayoutEngine

final class RowHeightTests: XCTestCase {
    let viewport = CGRect(x: 0, y: 0, width: 1000, height: 800)
    let config = LayoutConfig(gap: 10, outerGap: 10)

    func stacked(_ count: Int) -> Workspace {
        var ws = Workspace()
        for i in 1...count { ws.addWindow(WindowID(i)) }
        for i in 2...max(count, 2) where i <= count { ws.stack(WindowID(i), onto: WindowID(1)) }
        return ws
    }

    func testEqualSplitByDefault() {
        let frames = Layout.frames(stacked(2), viewport: viewport, config: config)
        XCTAssertEqual(frames[1]?.height, 385)
        XCTAssertEqual(frames[2]?.height, 385)
    }

    func testSetHeightGivesTheWindowItsShareAndTheOtherTheRest() {
        var ws = stacked(2)
        let top = ws.columns[0].windows[0]
        ws.setHeight(of: top, to: 0.7)
        XCTAssertEqual(ws.columns[0].rowFractions[0], 0.7, accuracy: 0.0001)
        XCTAssertEqual(ws.columns[0].rowFractions[1], 0.3, accuracy: 0.0001)
        let frames = Layout.frames(ws, viewport: viewport, config: config)
        XCTAssertEqual(frames[top]!.height, 770 * 0.7, accuracy: 0.001)
        XCTAssertEqual(frames[top]!.maxY + 10, frames[ws.columns[0].windows[1]]!.minY, accuracy: 0.001)
    }

    func testOtherWindowsKeepTheirProportions() {
        var ws = stacked(3)
        let top = ws.columns[0].windows[0]
        ws.setHeight(of: top, to: 0.5)
        let fractions = ws.columns[0].rowFractions
        XCTAssertEqual(fractions[0], 0.5, accuracy: 0.0001)
        XCTAssertEqual(fractions[1], 0.25, accuracy: 0.0001)
        XCTAssertEqual(fractions[2], 0.25, accuracy: 0.0001)
    }

    func testEachWindowKeepsAtLeastTenPercent() {
        var ws = stacked(2)
        let top = ws.columns[0].windows[0]
        ws.setHeight(of: top, to: 1)
        XCTAssertEqual(ws.columns[0].rowFractions[1], 0.1, accuracy: 0.0001)
        ws.setHeight(of: top, to: 0)
        XCTAssertEqual(ws.columns[0].rowFractions[0], 0.1, accuracy: 0.0001)
    }

    func testChangingTheStackResetsToEqualSplit() {
        var ws = stacked(2)
        ws.setHeight(of: ws.columns[0].windows[0], to: 0.7)
        ws.addWindow(WindowID(9))
        ws.stack(WindowID(9), onto: WindowID(1))
        XCTAssertEqual(ws.columns[0].windows.count, 3)
        XCTAssertEqual(ws.columns[0].rowFractions, Array(repeating: 1.0 / 3, count: 3))
    }

    func testSingleWindowColumnIgnoresSetHeight() {
        var ws = Workspace()
        ws.addWindow(WindowID(1))
        ws.setHeight(of: WindowID(1), to: 0.5)
        XCTAssertEqual(ws.columns[0].rowFractions, [1])
    }
}
