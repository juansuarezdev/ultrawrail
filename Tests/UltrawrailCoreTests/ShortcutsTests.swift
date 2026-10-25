import LayoutEngine
import XCTest
@testable import UltrawrailCore

final class ShortcutsTests: XCTestCase {
    func testDefaultsHaveUniqueIDsAndCombos() {
        let ids = ShortcutCatalog.bindings.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count)
        let combos = ShortcutCatalog.bindings.map(\.defaultCombo)
        XCTAssertEqual(Set(combos).count, combos.count)
    }

    func testDefaultsPassValidation() {
        let map = ShortcutMap()
        for binding in ShortcutCatalog.bindings {
            XCTAssertNil(map.issue(for: binding.defaultCombo, assigningTo: binding.id), binding.id)
        }
    }

    func testDisplayWindowsAndMac() {
        let combo = KeyCombo(keyCode: 123, control: true, option: true, command: true, shift: true)
        XCTAssertEqual(combo.display(style: .windows), "Ctrl+Alt+Win+Shift+←")
        XCTAssertEqual(combo.display(style: .mac), "⌃⌥⌘⇧←")
    }

    func testAssignOverridesAndResets() {
        var map = ShortcutMap()
        let custom = KeyCombo(keyCode: 9, control: true, option: true)
        XCTAssertNil(map.assign(custom, to: "cycleWidth"))
        XCTAssertEqual(map.combo(for: "cycleWidth"), custom)
        XCTAssertTrue(map.isCustomized("cycleWidth"))
        XCTAssertEqual(map.resolved.first { $0.id == "cycleWidth" }?.combo, custom)
        map.reset("cycleWidth")
        XCTAssertFalse(map.isCustomized("cycleWidth"))
    }

    func testAssigningTheDefaultStoresNoOverride() {
        var map = ShortcutMap()
        let original = ShortcutCatalog.bindings.first { $0.id == "cycleWidth" }!.defaultCombo
        XCTAssertNil(map.assign(original, to: "cycleWidth"))
        XCTAssertTrue(map.overrides.isEmpty)
    }

    func testRejectsFewerThanTwoModifiers() {
        let map = ShortcutMap()
        XCTAssertEqual(map.issue(for: KeyCombo(keyCode: 9, option: true), assigningTo: "cycleWidth"), .needsTwoModifiers)
        XCTAssertEqual(map.issue(for: KeyCombo(keyCode: 9, command: true, shift: true), assigningTo: "cycleWidth"), .needsTwoModifiers)
    }

    func testRejectsSystemReserved() {
        let map = ShortcutMap()
        XCTAssertEqual(map.issue(for: KeyCombo(keyCode: 53, option: true, command: true), assigningTo: "cycleWidth"), .reservedBySystem)
    }

    func testRejectsConflictWithAnotherBinding() {
        let map = ShortcutMap()
        let taken = ShortcutCatalog.bindings.first { $0.id == "centerColumn" }!.defaultCombo
        XCTAssertEqual(map.issue(for: taken, assigningTo: "cycleWidth"), .conflict(title: "Centrar columna"))
    }

    func testFreedDefaultBecomesAvailable() {
        var map = ShortcutMap()
        let centerDefault = ShortcutCatalog.bindings.first { $0.id == "centerColumn" }!.defaultCombo
        XCTAssertNil(map.assign(KeyCombo(keyCode: 9, control: true, option: true), to: "centerColumn"))
        XCTAssertNil(map.issue(for: centerDefault, assigningTo: "cycleWidth"))
    }

    func testIgnoresUnknownOverrideIDs() {
        let map = ShortcutMap(overrides: ["nope": KeyCombo(keyCode: 1, control: true, option: true)])
        XCTAssertTrue(map.overrides.isEmpty)
    }

    func testCodableRoundTrip() throws {
        let combo = KeyCombo(keyCode: 9, control: true, option: true, shift: true)
        let data = try JSONEncoder().encode(["cycleWidth": combo])
        XCTAssertEqual(try JSONDecoder().decode([String: KeyCombo].self, from: data)["cycleWidth"], combo)
    }
}
