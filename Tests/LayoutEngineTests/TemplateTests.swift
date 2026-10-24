import XCTest
import CoreGraphics
@testable import LayoutEngine

final class TemplateTests: XCTestCase {
    func workspace(_ count: Int) -> Workspace {
        var ws = Workspace()
        for id in 1...count { ws.addWindow(WindowID(id)) }
        return ws
    }

    func testBuiltInTemplates() {
        XCTAssertEqual(Template.all.map(\.id), ["halves", "main-side", "half-stack"])
        XCTAssertEqual(Template.all.map(\.slotCount), [2, 2, 3])
        XCTAssertEqual(Template.all[1].columns.map(\.width), [0.66, 0.33])
    }

    func testDefaultAssignmentFillsSlotsInOrderAndLeavesRestOut() {
        let t = Template.all[2]
        XCTAssertEqual(t.defaultAssignment(for: [1, 2, 3, 4]), [1, 2, 3])
        XCTAssertEqual(t.defaultAssignment(for: [1]), [1, nil, nil])
    }

    func testSlotColumnMapsSlotsToColumns() {
        let t = Template.all[2]
        XCTAssertEqual([0, 1, 2].map(t.slotColumn(of:)), [0, 1, 1])
    }

    func testApplyBuildsColumnsWithWidthsAndStacks() {
        var ws = workspace(3)
        ws.apply(Template.all[2], assignment: [3, 1, 2])
        XCTAssertEqual(ws.columns.map(\.windows), [[3], [1, 2]])
        XCTAssertEqual(ws.columns.map(\.width), [0.5, 0.5])
    }

    func testUnassignedWindowsBecomeExtraDefaultWidthColumns() {
        var ws = workspace(4)
        ws.apply(Template.all[0], assignment: [2, 1])
        XCTAssertEqual(ws.columns.map(\.windows), [[2], [1], [3], [4]])
        XCTAssertEqual(ws.columns[2].width, WidthPreset.defaultWidth)
    }

    func testEmptyColumnIsDroppedAndHolesAreSkipped() {
        var ws = workspace(2)
        ws.apply(Template.all[2], assignment: [nil, 1, nil])
        XCTAssertEqual(ws.columns.map(\.windows), [[1], [2]])
        XCTAssertEqual(ws.columns[0].width, 0.5)
    }

    func testDuplicateAndUnknownIdsAreIgnored() {
        var ws = workspace(2)
        ws.apply(Template.all[0], assignment: [1, 1])
        XCTAssertEqual(ws.columns.map(\.windows), [[1], [2]])
        ws.apply(Template.all[0], assignment: [9, 2])
        XCTAssertEqual(Set(ws.allWindows), [1, 2])
        XCTAssertEqual(ws.allWindows.count, 2)
    }

    func testFocusedWindowIsKeptAndScrollReset() {
        var ws = workspace(3)
        ws.focus(window: 2)
        ws.scrollOffset = 300
        ws.apply(Template.all[0], assignment: [3, 2])
        XCTAssertEqual(ws.focusedWindow, 2)
        XCTAssertEqual(ws.scrollOffset, 0)
    }

    func testApplyWithViewportRevealsFocusedColumn() {
        var ws = workspace(4)
        ws.focus(window: 4)
        let viewport = CGRect(x: 0, y: 0, width: 1000, height: 800)
        ws.apply(Template.all[0], assignment: [1, 2],
                 viewport: viewport, config: LayoutConfig(gap: 10, outerGap: 10))
        XCTAssertEqual(ws.focusedWindow, 4)
        let frames = Layout.frames(ws, viewport: viewport, config: LayoutConfig(gap: 10, outerGap: 10))
        XCTAssertTrue(viewport.contains(frames[4]!.insetBy(dx: 1, dy: 1)))
    }
}
