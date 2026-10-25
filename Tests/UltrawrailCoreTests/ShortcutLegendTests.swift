import XCTest
@testable import UltrawrailCore

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
        XCTAssertEqual(titles.count, 17)
        XCTAssertTrue(titles.contains("Panel de plantillas"))
    }

    func testPageEntriesUseWinAltAndCommandOption() {
        let page = ShortcutLegend.entries.first { $0.title == "Página anterior / siguiente" }!
        XCTAssertEqual(ShortcutLegend.line(for: page, style: .windows),
                       "Win+Alt+← / →  ·  Página anterior / siguiente")
        XCTAssertEqual(ShortcutLegend.line(for: page, style: .mac),
                       "⌘⌥← / →  ·  Página anterior / siguiente")
        let move = ShortcutLegend.entries.first { $0.title == "Mover ventana a la página anterior / siguiente" }!
        XCTAssertEqual(ShortcutLegend.line(for: move, style: .windows),
                       "Win+Alt+Shift+← / →  ·  Mover ventana a la página anterior / siguiente")
        XCTAssertEqual(ShortcutLegend.line(for: move, style: .mac),
                       "⌘⌥⇧← / →  ·  Mover ventana a la página anterior / siguiente")
    }

    func testZoneEntriesUseCtrlAltWin() {
        let focus = ShortcutLegend.entries.first { $0.title == "Zona anterior / siguiente" }!
        XCTAssertEqual(ShortcutLegend.line(for: focus, style: .windows),
                       "Ctrl+Alt+Win+← / →  ·  Zona anterior / siguiente")
        XCTAssertEqual(ShortcutLegend.line(for: focus, style: .mac),
                       "⌃⌥⌘← / →  ·  Zona anterior / siguiente")
        let move = ShortcutLegend.entries.first { $0.title == "Mover ventana a la zona anterior / siguiente" }!
        XCTAssertEqual(ShortcutLegend.line(for: move, style: .windows),
                       "Ctrl+Alt+Win+Shift+← / →  ·  Mover ventana a la zona anterior / siguiente")
        XCTAssertEqual(ShortcutLegend.line(for: move, style: .mac),
                       "⌃⌥⌘⇧← / →  ·  Mover ventana a la zona anterior / siguiente")
    }
}
