import XCTest
import LayoutEngine
@testable import LinkrCore

final class TemplateBoardTests: XCTestCase {
    let halves = Template.all[0]
    let stack = Template.all[2]

    func testInitFillsSlotsInOrder() {
        let board = TemplateBoard(template: halves, windows: [1, 2, 3])
        XCTAssertEqual(board.assignment, [1, 2])
        XCTAssertEqual(board.unassigned, [3])
    }

    func testSelectRefillsFromWindowOrder() {
        var board = TemplateBoard(template: halves, windows: [1, 2, 3])
        board.select(stack)
        XCTAssertEqual(board.assignment, [1, 2, 3])
        XCTAssertTrue(board.unassigned.isEmpty)
    }

    func testDropOnOccupiedSlotSwapsWithSourceSlot() {
        var board = TemplateBoard(template: halves, windows: [1, 2])
        board.drop(1, onSlot: 1)
        XCTAssertEqual(board.assignment, [2, 1])
    }

    func testDropFromListOntoOccupiedSlotUnassignsOccupant() {
        var board = TemplateBoard(template: halves, windows: [1, 2, 3])
        board.drop(3, onSlot: 0)
        XCTAssertEqual(board.assignment, [3, 2])
        XCTAssertEqual(board.unassigned, [1])
    }

    func testDropOnEmptySlotMovesWindow() {
        var board = TemplateBoard(template: stack, windows: [1])
        board.drop(1, onSlot: 2)
        XCTAssertEqual(board.assignment, [nil, nil, 1])
    }

    func testUnassignEmptiesItsSlot() {
        var board = TemplateBoard(template: halves, windows: [1, 2])
        board.unassign(1)
        XCTAssertEqual(board.assignment, [nil, 2])
        XCTAssertEqual(board.unassigned, [1])
    }

    func testDropIgnoresUnknownWindowAndBadSlot() {
        var board = TemplateBoard(template: halves, windows: [1, 2])
        board.drop(9, onSlot: 0)
        board.drop(1, onSlot: 7)
        XCTAssertEqual(board.assignment, [1, 2])
    }
}
