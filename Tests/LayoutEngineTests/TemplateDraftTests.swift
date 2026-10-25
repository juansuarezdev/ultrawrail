import XCTest
@testable import LayoutEngine

final class TemplateDraftTests: XCTestCase {
    func draft(_ widths: [Double], slots: [Int]? = nil) -> TemplateDraft {
        TemplateDraft(columns: widths.enumerated().map { TemplateColumn(width: $1, slots: slots?[$0] ?? 1) })
    }

    func assertSumsToOne(_ d: TemplateDraft, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(d.columns.reduce(0) { $0 + $1.width }, 1, accuracy: 1e-9, file: file, line: line)
    }

    func testInitNormalizesToExactlyOne() {
        let d = draft([0.66, 0.33])
        assertSumsToOne(d)
        XCTAssertEqual(d.columns[0].width, 0.667, accuracy: 1e-9)
    }

    func testInitClampsSlotsAndColumnCount() {
        let d = TemplateDraft(columns: (0..<8).map { _ in TemplateColumn(width: 0.125, slots: 9) })
        XCTAssertEqual(d.columns.count, 5)
        XCTAssertTrue(d.columns.allSatisfy { $0.slots == 3 })
        assertSumsToOne(d)
    }

    func testEmptyInitGivesOneFullColumn() {
        let d = TemplateDraft(columns: [])
        XCTAssertEqual(d.columns, [TemplateColumn(width: 1, slots: 1)])
    }

    func testAddColumnSplitsTheWidestInHalf() {
        var d = draft([0.25, 0.75])
        d.addColumn()
        XCTAssertEqual(d.columns.map(\.width), [0.25, 0.375, 0.375])
        assertSumsToOne(d)
    }

    func testAddColumnStopsAtFive() {
        var d = draft([0.2, 0.2, 0.2, 0.2, 0.2])
        d.addColumn()
        XCTAssertEqual(d.columns.count, 5)
    }

    func testAddColumnIsNoOpWhenWidestIsTooNarrowToSplit() {
        var d = draft([0.25, 0.25, 0.25, 0.25])
        d.addColumn()
        XCTAssertEqual(d.columns.map(\.width), [0.25, 0.25, 0.25, 0.25])
    }

    func testRemoveColumnMergesIntoNeighbour() {
        var d = draft([0.25, 0.5, 0.25])
        d.removeColumn(at: 1)
        XCTAssertEqual(d.columns.map(\.width), [0.75, 0.25])
        d.removeColumn(at: 0)
        XCTAssertEqual(d.columns.map(\.width), [1])
        d.removeColumn(at: 0)
        XCTAssertEqual(d.columns.count, 1)
        assertSumsToOne(d)
    }

    func testSetSlotsClampsToOneThroughThree() {
        var d = draft([0.5, 0.5])
        d.setSlots(0, at: 0)
        d.setSlots(7, at: 1)
        XCTAssertEqual(d.columns.map(\.slots), [1, 3])
        d.setSlots(2, at: 5)
        XCTAssertEqual(d.columns.count, 2)
    }

    func testMoveDividerSnapsToPresets() {
        var d = draft([0.5, 0.5])
        d.moveDivider(0, to: 0.27)
        XCTAssertEqual(d.columns.map(\.width), [0.25, 0.75])
        d.moveDivider(0, to: 0.48)
        XCTAssertEqual(d.columns.map(\.width), [0.5, 0.5])
    }

    func testMoveDividerOutsideToleranceDoesNotSnap() {
        var d = draft([0.5, 0.5])
        d.moveDivider(0, to: 0.40)
        XCTAssertEqual(d.columns.map(\.width), [0.4, 0.6])
    }

    func testMoveDividerSnapsTheNeighbourSideToo() {
        var d = draft([0.5, 0.5])
        d.moveDivider(0, to: 0.73)      // right column would be 0.27 -> snaps to 0.25
        XCTAssertEqual(d.columns.map(\.width), [0.75, 0.25])
    }

    func testMoveDividerKeepsMinimumWidthAndTotal() {
        var d = draft([0.25, 0.5, 0.25])
        d.moveDivider(1, to: 0.99)
        XCTAssertEqual(d.columns[2].width, 0.15, accuracy: 1e-9)
        d.moveDivider(0, to: 0.0)
        XCTAssertEqual(d.columns[0].width, 0.15, accuracy: 1e-9)
        assertSumsToOne(d)
    }

    func testMoveDividerOutOfRangeIsNoOp() {
        var d = draft([0.5, 0.5])
        d.moveDivider(1, to: 0.3)
        d.moveDivider(-1, to: 0.3)
        XCTAssertEqual(d.columns.map(\.width), [0.5, 0.5])
    }

    func testBuiltInTemplatesIncludeUltrawide() {
        XCTAssertEqual(Template.all.count, 3)
        XCTAssertEqual(Template.builtIn.map(\.id), ["halves", "main-side", "half-stack", "center", "quad", "dual-zones"])
        XCTAssertEqual(Template.ultrawide.map(\.slotCount), [3, 4, 4])
    }

    func testTemplateRoundTripsThroughJSON() throws {
        let data = try JSONEncoder().encode(Template.builtIn)
        XCTAssertEqual(try JSONDecoder().decode([Template].self, from: data), Template.builtIn)
    }
}
