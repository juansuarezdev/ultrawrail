# Ultrawrail Template Editor Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Create, edit (drag dividers), duplicate and delete custom window-layout templates in the Settings window; custom and ultrawide templates also appear in the Ctrl+Alt+T panel.

**Architecture:** Pure `TemplateDraft` editing rules + `Codable` templates in `LayoutEngine`; `TemplateCodec`/`TemplateLibrary` in `UltrawrailCore`; `SettingsModel` persists custom templates; a SwiftUI `TemplatesTab` edits them; the AppKit panel reads the combined list. Spec: `docs/superpowers/specs/2026-10-25-ultrawrail-template-editor-design.md`.

**Tech Stack:** Swift 5 mode, SwiftPM, SwiftUI + AppKit, XCTest, macOS 13+.

## Global Constraints

- Branch `feat/template-editor`; default branch is `main` (never `master`).
- No AI attribution or `Co-Authored-By`; commits in English (`feat:`/`fix:`/`docs:`/`test:`).
- `swift build` 0 warnings; `swift test` must pass. Do not launch the app or run `scripts/bundle.sh`.
- UI strings in Spanish. Limits (exact): 1 to 5 columns, 1 to 3 slots per column, minimum column width 0.15, snaps 0.25 0.33 0.5 0.66 0.75 with tolerance 0.025, widths rounded to 3 decimals and summing exactly to 1.
- Built-in template ids (exact): existing `halves`, `main-side`, `half-stack`; new `center` (0.25/0.5/0.25, 1 slot each, name "Centro 25 · 50 · 25"), `quad` (4 × 0.25, 1 slot, "Cuatro columnas"), `dual-zones` (0.5 with 2 slots, 0.5 with 2 slots, "Dos zonas 16:9"). Custom ids start with `custom-`.
- `UserDefaults` key for custom templates: `customTemplates` (JSON `[Template]`).
- Existing: `Template`, `TemplateColumn`, `Template.all` (3 items, unchanged), `SettingsModel` (`@Published` + `commit()` + `onChange`), `SettingsView` tabs, `TemplatePanelController`, `TemplateBoardView` (cards from `Template.all`), `AppDelegate.model`.

---

### Task 1: Codable templates, ultrawide built-ins, TemplateDraft

**Files:**
- Modify: `Sources/LayoutEngine/Template.swift`
- Create: `Sources/LayoutEngine/TemplateDraft.swift`
- Test: `Tests/LayoutEngineTests/TemplateDraftTests.swift`

- [ ] **Step 1: Write the failing tests** — `Tests/LayoutEngineTests/TemplateDraftTests.swift`

```swift
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
        d.moveDivider(0, to: 0.47)
        XCTAssertEqual(d.columns.map(\.width), [0.5, 0.5])
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
```

- [ ] **Step 2: Run to verify failure** — `swift test --filter LayoutEngineTests.TemplateDraftTests` → compile errors.

- [ ] **Step 3: Implement.** In `Template.swift` change the declarations to `public struct TemplateColumn: Equatable, Sendable, Codable` and `public struct Template: Equatable, Sendable, Codable`, and add inside `Template`, after `all`:

```swift
    public static let ultrawide: [Template] = [
        Template(id: "center", name: "Centro 25 · 50 · 25",
                 columns: [TemplateColumn(width: 0.25, slots: 1), TemplateColumn(width: 0.5, slots: 1), TemplateColumn(width: 0.25, slots: 1)]),
        Template(id: "quad", name: "Cuatro columnas",
                 columns: (0..<4).map { _ in TemplateColumn(width: 0.25, slots: 1) }),
        Template(id: "dual-zones", name: "Dos zonas 16:9",
                 columns: [TemplateColumn(width: 0.5, slots: 2), TemplateColumn(width: 0.5, slots: 2)]),
    ]

    /// Every template that ships with Ultrawrail, in display order.
    public static let builtIn: [Template] = all + ultrawide
```

`Sources/LayoutEngine/TemplateDraft.swift`:

```swift
/// Editing rules for a template's columns: always 1 to 5 columns, 1 to 3 slots each, and widths
/// (3 decimals, at least `minWidth`) that sum to exactly 1.
public struct TemplateDraft: Equatable, Sendable {
    public static let minWidth = 0.15
    public static let maxColumns = 5
    public static let maxSlots = 3
    public static let snaps: [Double] = [0.25, 0.33, 0.5, 0.66, 0.75]
    public static let snapTolerance = 0.025

    public private(set) var columns: [TemplateColumn]

    public init(columns: [TemplateColumn]) {
        let kept = columns.isEmpty ? [TemplateColumn(width: 1, slots: 1)] : Array(columns.prefix(Self.maxColumns))
        self.columns = Self.normalized(kept.map {
            TemplateColumn(width: max($0.width, 0.01), slots: min(max($0.slots, 1), Self.maxSlots))
        })
    }

    private static func round3(_ value: Double) -> Double { (value * 1000).rounded() / 1000 }

    /// Scales widths to sum to 1; the last column absorbs the rounding.
    private static func normalized(_ cols: [TemplateColumn]) -> [TemplateColumn] {
        let total = cols.reduce(0) { $0 + $1.width }
        var result = cols.map { TemplateColumn(width: round3($0.width / total), slots: $0.slots) }
        let others = result.dropLast().reduce(0) { $0 + $1.width }
        result[result.count - 1] = TemplateColumn(width: round3(1 - others), slots: result[result.count - 1].slots)
        return result
    }

    /// Splits the widest column in two equal halves.
    public mutating func addColumn() {
        guard columns.count < Self.maxColumns else { return }
        var widest = 0
        for (index, column) in columns.enumerated() where column.width > columns[widest].width { widest = index }
        let half = Self.round3(columns[widest].width / 2)
        let rest = Self.round3(columns[widest].width - half)
        columns[widest] = TemplateColumn(width: half, slots: columns[widest].slots)
        columns.insert(TemplateColumn(width: rest, slots: 1), at: widest + 1)
    }

    /// Removes a column and gives its width to a neighbour.
    public mutating func removeColumn(at index: Int) {
        guard columns.count > 1, columns.indices.contains(index) else { return }
        let neighbour = index > 0 ? index - 1 : index + 1
        columns[neighbour] = TemplateColumn(width: Self.round3(columns[neighbour].width + columns[index].width),
                                            slots: columns[neighbour].slots)
        columns.remove(at: index)
    }

    public mutating func setSlots(_ count: Int, at index: Int) {
        guard columns.indices.contains(index) else { return }
        columns[index] = TemplateColumn(width: columns[index].width, slots: min(max(count, 1), Self.maxSlots))
    }

    /// Moves the divider after column `index` to `position` (a fraction of the screen from its left edge).
    public mutating func moveDivider(_ index: Int, to position: Double) {
        guard columns.indices.contains(index), columns.indices.contains(index + 1) else { return }
        let pair = columns[index].width + columns[index + 1].width
        guard pair >= 2 * Self.minWidth else { return }
        let left = columns[..<index].reduce(0) { $0 + $1.width }
        var width = position - left
        for snap in Self.snaps where abs(width - snap) < Self.snapTolerance { width = snap }
        for snap in Self.snaps where abs((pair - width) - snap) < Self.snapTolerance { width = pair - snap }
        width = min(max(width, Self.minWidth), pair - Self.minWidth)
        let first = Self.round3(width)
        columns[index] = TemplateColumn(width: first, slots: columns[index].slots)
        columns[index + 1] = TemplateColumn(width: Self.round3(pair - first), slots: columns[index + 1].slots)
    }
}
```

- [ ] **Step 4: Verify** — `swift test` green, `swift build` 0 warnings. If a test's floating-point expectation fails by rounding, fix the code, not the intent (sum must be exactly 1 within 1e-9).

- [ ] **Step 5: Commit**

```bash
git add Sources Tests
git commit -m "feat: add template editing rules and ultrawide built-in templates"
```

---

### Task 2: TemplateCodec, TemplateLibrary, model persistence, panel integration

**Files:**
- Create: `Sources/UltrawrailCore/TemplateLibrary.swift`, `Sources/UltrawrailApp/TemplateStore.swift`
- Modify: `Sources/UltrawrailApp/SettingsModel.swift`, `Sources/UltrawrailApp/AppDelegate.swift`, `Sources/UltrawrailApp/TemplatePanelController.swift`, `Sources/UltrawrailApp/TemplateBoardView.swift`
- Test: `Tests/UltrawrailCoreTests/TemplateLibraryTests.swift`

**Interfaces:**
- Produces: `TemplateCodec.encode/decode`, `TemplateLibrary.all(custom:)`, `SettingsModel.customTemplates/allTemplates/newTemplate()/duplicate(_:)/update(_:)/deleteTemplate(id:)`, `TemplatePanelController.init(controller:templates:)`.

- [ ] **Step 1: Write the failing tests** — `Tests/UltrawrailCoreTests/TemplateLibraryTests.swift`

```swift
import XCTest
import LayoutEngine
@testable import UltrawrailCore

final class TemplateLibraryTests: XCTestCase {
    let custom = Template(id: "custom-1", name: "Mía",
                          columns: [TemplateColumn(width: 0.25, slots: 1), TemplateColumn(width: 0.75, slots: 2)])

    func testRoundTrip() throws {
        let data = try XCTUnwrap(TemplateCodec.encode([custom]))
        XCTAssertEqual(TemplateCodec.decode(data), [custom])
    }

    func testDecodeGarbageGivesEmpty() {
        XCTAssertEqual(TemplateCodec.decode(Data("nope".utf8)), [])
    }

    func testDecodeDropsInvalidAndNormalizes() throws {
        let bad = [
            Template(id: "custom-a", name: "Sin columnas", columns: []),
            Template(id: "custom-b", name: "Ancho cero", columns: [TemplateColumn(width: 0, slots: 1)]),
            Template(id: "custom-c", name: "Suma 0.99", columns: [TemplateColumn(width: 0.66, slots: 1), TemplateColumn(width: 0.33, slots: 1)]),
        ]
        let decoded = TemplateCodec.decode(try JSONEncoder().encode(bad))
        XCTAssertEqual(decoded.map(\.id), ["custom-c"])
        XCTAssertEqual(decoded[0].columns.reduce(0) { $0 + $1.width }, 1, accuracy: 1e-9)
    }

    func testDecodeDropsDuplicateIds() throws {
        let data = try JSONEncoder().encode([custom, custom])
        XCTAssertEqual(TemplateCodec.decode(data).count, 1)
    }

    func testLibraryPutsBuiltInsFirstAndIgnoresIdCollisions() {
        let clash = Template(id: "halves", name: "Falsa", columns: [TemplateColumn(width: 1, slots: 1)])
        let all = TemplateLibrary.all(custom: [custom, clash])
        XCTAssertEqual(all.map(\.id), Template.builtIn.map(\.id) + ["custom-1"])
    }
}
```

- [ ] **Step 2: Run to verify failure** (compile errors).

- [ ] **Step 3: Implement** `Sources/UltrawrailCore/TemplateLibrary.swift`:

```swift
import Foundation
import LayoutEngine

public enum TemplateCodec {
    public static func encode(_ templates: [Template]) -> Data? {
        try? JSONEncoder().encode(templates)
    }

    /// Decodes stored templates. Anything invalid is dropped; widths are normalized to sum to 1.
    public static func decode(_ data: Data) -> [Template] {
        guard let stored = try? JSONDecoder().decode([Template].self, from: data) else { return [] }
        var seen = Set<String>()
        var result: [Template] = []
        for template in stored {
            guard !template.columns.isEmpty,
                  template.columns.allSatisfy({ $0.width > 0 && (1...TemplateDraft.maxSlots).contains($0.slots) }),
                  template.columns.count <= TemplateDraft.maxColumns,
                  seen.insert(template.id).inserted else { continue }
            let draft = TemplateDraft(columns: template.columns)
            result.append(Template(id: template.id, name: template.name, columns: draft.columns))
        }
        return result
    }
}

public enum TemplateLibrary {
    /// Built-in templates first, then the custom ones whose id does not clash with a built-in.
    public static func all(custom: [Template]) -> [Template] {
        let builtInIds = Set(Template.builtIn.map(\.id))
        return Template.builtIn + custom.filter { !builtInIds.contains($0.id) }
    }
}
```

`Sources/UltrawrailApp/TemplateStore.swift`:

```swift
import Foundation
import LayoutEngine
import UltrawrailCore

struct TemplateStore {
    private let defaults = UserDefaults.standard
    private let key = "customTemplates"

    var templates: [Template] {
        get { defaults.data(forKey: key).map(TemplateCodec.decode) ?? [] }
        nonmutating set { defaults.set(TemplateCodec.encode(newValue), forKey: key) }
    }
}
```

`SettingsModel.swift`: add `private let templateStore = TemplateStore()`; `@Published var customTemplates: [Template] { didSet { commit() } }` initialized in `init` from `templateStore.templates`; persist in `commit()` (`templateStore.templates = customTemplates`); and

```swift
    var allTemplates: [Template] { TemplateLibrary.all(custom: customTemplates) }

    @discardableResult
    func newTemplate() -> Template {
        let template = Template(id: "custom-" + UUID().uuidString, name: "Nueva plantilla",
                                columns: [TemplateColumn(width: 0.5, slots: 1), TemplateColumn(width: 0.5, slots: 1)])
        customTemplates.append(template)
        return template
    }

    @discardableResult
    func duplicate(_ source: Template) -> Template {
        let copy = Template(id: "custom-" + UUID().uuidString, name: "Copia de " + source.name,
                            columns: TemplateDraft(columns: source.columns).columns)
        customTemplates.append(copy)
        return copy
    }

    func update(_ template: Template) {
        guard let index = customTemplates.firstIndex(where: { $0.id == template.id }) else { return }
        customTemplates[index] = template
    }

    func deleteTemplate(id: String) {
        customTemplates.removeAll { $0.id == id }
    }
```

(import `LayoutEngine` and `UltrawrailCore` already present in that file.)

`TemplatePanelController`: change `init(controller: Controller, templates: @escaping () -> [Template])`, store it, use `templates()` for the board's default (`templates().first ?? Template.all[0]`) and pass the list to `TemplateBoardView(board:chips:templates:)`.

`TemplateBoardView`: add `private let templates: [Template]` and `private var cardScroll: CGFloat = 0` (with `didSet { needsDisplay = true }`); replace both `Template.all` uses by `templates`; `cardRect(index)` x becomes `16 + CGFloat(index) * 162 - cardScroll`; draw the cards inside a clip of the row area `NSRect(x: 0, y: 8, width: bounds.width, height: 86)` (save/restore graphics state); mouse hit-testing for cards only when `point.y < 100`; add

```swift
    override func scrollWheel(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let maxScroll = max(0, CGFloat(templates.count) * 162 + 16 - bounds.width)
        guard point.y < 100, maxScroll > 0 else { return super.scrollWheel(with: event) }
        let delta = abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY) ? event.scrollingDeltaX : event.scrollingDeltaY
        cardScroll = min(maxScroll, max(0, cardScroll - delta))
    }
```

Note `TemplateBoardView` already overrides `scrollWheel` for the window list (Task "scrollable list"): merge into ONE `scrollWheel` that routes by area (cards area y < 100 → `cardScroll`; list area → existing logic).

`AppDelegate`: create the panel with `TemplatePanelController(controller: controller, templates: { [weak self] in self?.model.allTemplates ?? Template.builtIn })`.

- [ ] **Step 4: Verify** — `swift build` (0 warnings), `swift test` all pass. Do not launch the app.

- [ ] **Step 5: Commit**

```bash
git add Sources Tests
git commit -m "feat: persist custom templates and show them in the templates panel"
```

---

### Task 3: Settings "Plantillas" tab with the drag editor

**Files:**
- Create: `Sources/UltrawrailApp/TemplatesTab.swift`
- Modify: `Sources/UltrawrailApp/SettingsView.swift` (add the tab between Diseño and Atajos), `Sources/UltrawrailApp/SettingsWindowController.swift` (window height to 560 if needed)

**Interfaces:** consumes `SettingsModel.allTemplates/customTemplates/newTemplate()/duplicate(_:)/update(_:)/deleteTemplate(id:)`, `TemplateDraft`, `Template.builtIn`.

- [ ] **Step 1: `TemplatesTab.swift`** — write a SwiftUI view with this behavior (use the prototype's layout: list left 220 pt wide, editor right):
  - `@ObservedObject var model: SettingsModel`; `@State private var selectedId: String = Template.builtIn[0].id`; `@State private var aspect: Aspect` (`enum Aspect: String, CaseIterable { case wide16x9 = "16:9", ultra21x9 = "21:9", super32x9 = "32:9"; var ratio: Double }`), initialized from `NSScreen.main` frame ratio (nearest of 16/9, 21/9, 32/9); `@State private var activeDivider: Int?` and `@State private var snapped: Double?`.
  - Left: `List(selection:)` with sections "De serie" (the 6 built-ins, ultrawide ones carry a small "UW" badge) and "Mis plantillas" (customs), each row = a mini thumbnail (reuse a `TemplateThumbnail(columns:)` view that draws proportional rounded rects) + name. A "+ Nueva plantilla" button calls `model.newTemplate()` and selects it.
  - Right editor, for the selected template `t` (look up in `model.allTemplates`; if missing select the first). `readOnly = Template.builtIn.contains { $0.id == t.id }`.
    - Header: `TextField("Nombre", text: binding)` (disabled when read-only; on change `model.update(Template(id:name:columns:))`), a note "De serie: duplica para editar" when read-only, buttons "Duplicar" (calls `model.duplicate(t)`, selects the copy) and "Borrar" (custom only; calls `model.deleteTemplate(id:)`, selects the first template).
    - Aspect picker: `Picker("Monitor", selection: $aspect).pickerStyle(.segmented)` over the three aspects.
    - Canvas: fixed width 460 pt, height `460 / aspect.ratio`, in a `ZStack` inside `GeometryReader`; background `Color(nsColor: .underPageBackgroundColor)` with a 2 pt border. For each column draw a rounded rectangle at `x = cumulativeWidth * W`, `width = column.width * W` inset by 4 pt, showing the percentage label ("50 %"), its `slots` as stacked dashed rounded rects labeled "Hueco n", a "−" button (top right; custom only and when more than 1 column; calls `draft.removeColumn(at:)`) and a bottom stepper with "−", "n hueco(s)" and "+" buttons (custom only; `draft.setSlots`). Dividers: for each boundary a `Capsule` 4×46 pt centered on the boundary with an 18 pt wide hit area, `.gesture(DragGesture(minimumDistance: 0, coordinateSpace: .named("screen")).onChanged { value in … draft.moveDivider(i, to: Double(value.location.x / W)) … }.onEnded { … })`; the cursor over it is `NSCursor.resizeLeftRight` (via `.onHover`) when editable. Name the canvas coordinate space `"screen"`. While dragging show the snap label ("Imán: 50 %") next to the canvas.
    - Every mutation builds `var draft = TemplateDraft(columns: t.columns)`, applies the operation, and calls `model.update(Template(id: t.id, name: t.name, columns: draft.columns))` (no-op for read-only).
    - Under the canvas: a ruler with tick labels at 25, 33, 50, 66, 75 and dots at the current boundaries; a button "+ Columna" (disabled when read-only or 5 columns; calls `draft.addColumn()`) and the summary text "n columnas · m huecos · suma 100 % de la pantalla".
  - Add accessibility labels to the icon-only buttons.

- [ ] **Step 2: `SettingsView.swift`** — add `TemplatesTab(model: model).tabItem { Label("Plantillas", systemImage: "square.split.2x1") }` after the Diseño tab; widen the frame to `width: 760, height: 560` and make `SettingsWindowController` use the hosting controller's size (no change if it already sizes from the SwiftUI frame).

- [ ] **Step 3: Verify** — `swift build` (0 warnings) and `swift test` (all pass). Fix compile issues with the smallest change preserving behavior; list them in the report. Do not launch the app.

- [ ] **Step 4: Commit**

```bash
git add Sources
git commit -m "feat: add templates tab with drag editor to settings"
```

---

### Task 4: Smoke test docs

**Files:** Modify `docs/smoke-test.md`.

- [ ] **Step 1:** Add a section "Editor de plantillas" before "Limitaciones conocidas":
1. Ajustes tiene la pestaña Plantillas: lista con las 6 de serie (3 con la etiqueta UW) y "Mis plantillas".
2. Las de serie son de solo lectura; "Duplicar" crea una copia editable y la selecciona.
3. Arrastrar un divisor reparte el ancho entre las dos columnas contiguas, con imán a 25, 33, 50, 66 y 75 %, y nunca baja del 15 %.
4. "+ Columna" parte la más ancha; "−" fusiona con la vecina; "− n huecos +" cambia entre 1 y 3 huecos.
5. El selector 16:9, 21:9, 32:9 cambia la proporción del lienzo; por defecto la del monitor.
6. Las plantillas propias salen en Ctrl+Alt+T tras las de serie; con muchas, las tarjetas se desplazan con la rueda.
7. Cerrar y reabrir Ultrawrail conserva las plantillas propias; "Borrar" las quita.

- [ ] **Step 2: Commit**

```bash
git add docs
git commit -m "docs: add template editor smoke steps"
```
