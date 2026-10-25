import XCTest
@testable import PanerailCore

final class ShortcutLegendTests: XCTestCase {
    func testWindowsLineUsesCtrlAltNames() {
        let focusLeft = ShortcutLegend.entries[0]
        XCTAssertEqual(ShortcutLegend.line(for: focusLeft, style: .windows),
                       "Ctrl+Alt+H / ←  ·  Foco a la izquierda")
    }

    func testMacLineUsesSymbols() {
        let focusLeft = ShortcutLegend.entries[0]
        XCTAssertEqual(ShortcutLegend.line(for: focusLeft, style: .mac),
                       "⌃⌥H / ←  ·  Foco a la izquierda")
    }

    func testShiftEntriesAddShiftModifier() {
        let move = ShortcutLegend.entries.first { $0.title == "Mover columna a la izquierda" }!
        XCTAssertEqual(ShortcutLegend.line(for: move, style: .windows),
                       "Ctrl+Alt+Shift+H / ←  ·  Mover columna a la izquierda")
        XCTAssertEqual(ShortcutLegend.line(for: move, style: .mac),
                       "⌃⌥⇧H / ←  ·  Mover columna a la izquierda")
    }

    func testEveryCommandShortcutIsListed() {
        let titles = ShortcutLegend.entries.map(\.title)
        XCTAssertEqual(titles.count, 13)
        XCTAssertTrue(titles.contains("Panel de plantillas"))
    }
}
