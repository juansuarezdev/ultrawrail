# Ultrawrail Templates Panel Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A floating panel (Ctrl+Alt+T) with prebuilt templates; drag window chips into template slots; Apply rebuilds the strip.

**Architecture:** Pure `Template` + `Workspace.apply(template:)` in `LayoutEngine`; pure `TemplateBoard` (panel state) and `Controller.applyTemplate` in `UltrawrailCore`; one AppKit view + panel controller in `UltrawrailApp`. Spec: `docs/superpowers/specs/2026-10-25-ultrawrail-templates-panel-design.md`.

**Tech Stack:** Swift 5 mode, SwiftPM, AppKit, XCTest, Carbon hotkeys. macOS 13+.

## Global Constraints

- Branch `feat/templates-panel`; default branch is `main` (never `master`).
- No AI attribution or `Co-Authored-By` in any commit; commits in English (`feat:`/`fix:`/`docs:`).
- `swift build` must print 0 warnings; `swift test` must pass.
- Shortcut: Ctrl+Option+T (`kVK_ANSI_T`), named `⌃⌥T` in the bindings list.
- Built-in templates (ids exact): `halves` (50|50, 1 slot each), `main-side` (66|33, 1 slot each), `half-stack` (50 with 1 slot | 50 with 2 slots).
- Unassigned windows become extra default-width columns on the right; no window is ever dropped.
- Do not launch the app (the user runs it). UI strings in Spanish, matching the existing app.
- Existing APIs: `Workspace` (`columns` is `private(set)`, so mutating code that sets `columns` must live in `Workspace.swift`), `Column(windows:width:restoreWidth:)`, `WidthPreset.defaultWidth`, `Layout.reveal/removeOverscroll`, `Controller.workspace/relayout()`, `WindowService`.

---

### Task 1: Template model and Workspace.apply(template)

**Files:**
- Create: `Sources/LayoutEngine/Template.swift`
- Modify: `Sources/LayoutEngine/Workspace.swift` (add method), `Sources/LayoutEngine/Workspace+Perform.swift` (add method)
- Test: `Tests/LayoutEngineTests/TemplateTests.swift`

**Interfaces:**
- Produces: `TemplateColumn`, `Template` (`id`, `name`, `columns`, `slotCount`, `slotColumn(of:)`, `static all`, `defaultAssignment(for:)`), `Workspace.apply(_:assignment:)`, `Workspace.apply(_:assignment:viewport:config:)`.

- [ ] **Step 1: Write the failing tests** — `Tests/LayoutEngineTests/TemplateTests.swift`

```swift
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
        let frames = Layout.frames(for: ws, viewport: viewport, config: LayoutConfig(gap: 10, outerGap: 10))
        XCTAssertTrue(viewport.contains(frames[4]!.insetBy(dx: 1, dy: 1)))
    }
}
```

If `Layout.frames` has a different signature than used in the last test, read `Sources/LayoutEngine/Layout.swift` and adapt the call only (keep the assertion's meaning: the focused window's frame lies inside the viewport).

- [ ] **Step 2: Run to verify failure**

Run: `swift test --filter TemplateTests` — Expected: compile error, `Template` not found.

- [ ] **Step 3: Implement** — `Sources/LayoutEngine/Template.swift`

```swift
public struct TemplateColumn: Equatable, Sendable {
    public let width: Double
    public let slots: Int
    public init(width: Double, slots: Int) {
        self.width = width
        self.slots = slots
    }
}

public struct Template: Equatable, Sendable {
    public let id: String
    public let name: String
    public let columns: [TemplateColumn]

    public init(id: String, name: String, columns: [TemplateColumn]) {
        self.id = id
        self.name = name
        self.columns = columns
    }

    public var slotCount: Int { columns.reduce(0) { $0 + $1.slots } }

    /// Index of the template column that holds the given slot (slots count column by column).
    public func slotColumn(of slot: Int) -> Int {
        var remaining = slot
        for (index, column) in columns.enumerated() {
            if remaining < column.slots { return index }
            remaining -= column.slots
        }
        return max(0, columns.count - 1)
    }

    /// The first `slotCount` windows, in order, fill the slots; the rest stay unassigned.
    public func defaultAssignment(for windows: [WindowID]) -> [WindowID?] {
        (0..<slotCount).map { $0 < windows.count ? windows[$0] : nil }
    }

    public static let all: [Template] = [
        Template(id: "halves", name: "Mitades",
                 columns: [TemplateColumn(width: 0.5, slots: 1), TemplateColumn(width: 0.5, slots: 1)]),
        Template(id: "main-side", name: "Principal + lateral",
                 columns: [TemplateColumn(width: 0.66, slots: 1), TemplateColumn(width: 0.33, slots: 1)]),
        Template(id: "half-stack", name: "Mitad + dos apiladas",
                 columns: [TemplateColumn(width: 0.5, slots: 1), TemplateColumn(width: 0.5, slots: 2)]),
    ]
}
```

In `Sources/LayoutEngine/Workspace.swift`, add inside `Workspace` (it must live in this file because `columns` is `private(set)`):

```swift
    /// Rebuilds the strip from a template. `assignment` has one entry per slot, column by column.
    /// Windows that are not assigned (or whose entry is nil, repeated or unknown) go to extra
    /// default-width columns at the end, so no window is lost.
    public mutating func apply(_ template: Template, assignment: [WindowID?]) {
        let existing = allWindows
        let focused = focusedWindow
        var used = Set<WindowID>()
        var rebuilt: [Column] = []
        var slot = 0
        for spec in template.columns {
            var windows: [WindowID] = []
            for _ in 0..<spec.slots {
                if slot < assignment.count, let id = assignment[slot],
                   existing.contains(id), used.insert(id).inserted {
                    windows.append(id)
                }
                slot += 1
            }
            if !windows.isEmpty { rebuilt.append(Column(windows: windows, width: spec.width)) }
        }
        for id in existing where !used.contains(id) { rebuilt.append(Column(windows: [id])) }
        columns = rebuilt
        scrollOffset = 0
        focusedColumn = 0
        focusedRow = 0
        if let focused { focus(window: focused) }
    }
```

In `Sources/LayoutEngine/Workspace+Perform.swift`, add inside the extension:

```swift
    /// Applies a template and leaves `scrollOffset` consistent with the focused column.
    mutating func apply(_ template: Template, assignment: [WindowID?], viewport: CGRect, config: LayoutConfig) {
        apply(template, assignment: assignment)
        Layout.reveal(&self, viewport: viewport, config: config)
        Layout.removeOverscroll(&self, viewport: viewport, config: config)
    }
```

- [ ] **Step 4: Run to verify pass**

Run: `swift test --filter TemplateTests` — Expected: all pass. Then `swift build` (0 warnings).

- [ ] **Step 5: Commit**

```bash
git add Sources/LayoutEngine Tests/LayoutEngineTests
git commit -m "feat: add layout templates and apply them to the workspace"
```

---

### Task 2: TemplateBoard, Controller.applyTemplate, showTemplates command, describe

**Files:**
- Create: `Sources/UltrawrailCore/TemplateBoard.swift`
- Modify: `Sources/LayoutEngine/Types.swift` (add `showTemplates` to `Command`), `Sources/LayoutEngine/Workspace.swift` (`apply(_ command:)` switch: `case .showTemplates: break`), `Sources/UltrawrailCore/Protocols.swift` (`WindowDescription`, `describe`), `Sources/UltrawrailCore/Controller.swift` (`onShowTemplates`, `managedWindows`, `applyTemplate`, intercept in `handle(_ command:)`)
- Test: `Tests/UltrawrailCoreTests/TemplateBoardTests.swift`, `Tests/UltrawrailCoreTests/ControllerTemplateTests.swift`; update `FakeWindows` in `Tests/UltrawrailCoreTests/ControllerTests.swift` with `describe`

**Interfaces:**
- Consumes: `Template`, `Workspace.apply(_:assignment:viewport:config:)` from Task 1.
- Produces: `TemplateBoard`, `WindowDescription(appName:pid:)`, `WindowService.describe(_:)`, `Controller.managedWindows`, `Controller.onShowTemplates`, `Controller.applyTemplate(_:assignment:)`, `Command.showTemplates`.

- [ ] **Step 1: Write the failing tests**

`Tests/UltrawrailCoreTests/TemplateBoardTests.swift`:

```swift
import XCTest
import LayoutEngine
@testable import UltrawrailCore

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
```

`Tests/UltrawrailCoreTests/ControllerTemplateTests.swift` (uses `FakeWindows`/`FakeHotkeys` from `ControllerTests.swift`; no animator, so writes are immediate):

```swift
import XCTest
import CoreGraphics
import LayoutEngine
@testable import UltrawrailCore

@MainActor
final class ControllerTemplateTests: XCTestCase {
    let config = LayoutConfig(gap: 10, outerGap: 10)

    func makeController(_ ids: [Int]) -> (Controller, FakeWindows) {
        let windows = FakeWindows()
        for id in ids { windows.add(id) }
        let controller = Controller(windows: windows, hotkeys: FakeHotkeys(), config: config)
        controller.start()
        return (controller, windows)
    }

    func testApplyTemplateRebuildsColumnsAndWritesFrames() {
        let (controller, windows) = makeController([1, 2, 3])
        controller.applyTemplate(Template.all[0], assignment: [3, 1])
        XCTAssertEqual(controller.workspace.columns.map(\.windows), [[3], [1], [2]])
        XCTAssertEqual(windows.lastRect(3)?.width, 490)
        XCTAssertEqual(windows.lastRect(3)?.origin.x, 10)
    }

    func testApplyTemplateKeepsFocusAndFocusesThatWindow() {
        let (controller, windows) = makeController([1, 2, 3])
        controller.applyTemplate(Template.all[0], assignment: [3, 2])
        XCTAssertEqual(controller.workspace.focusedWindow, 3)
        XCTAssertEqual(windows.focusCalls.last, 3)
    }

    func testManagedWindowsFollowColumnOrder() {
        let (controller, _) = makeController([1, 2, 3])
        controller.handle(.moveColumnLeft)
        XCTAssertEqual(controller.managedWindows, [1, 3, 2])
    }

    func testShowTemplatesCallsCallbackAndLeavesModelAlone() {
        let (controller, windows) = makeController([1, 2])
        var called = 0
        controller.onShowTemplates = { called += 1 }
        let before = windows.setFrameCalls.count
        controller.handle(.showTemplates)
        XCTAssertEqual(called, 1)
        XCTAssertEqual(controller.workspace.allWindows, [1, 2])
        XCTAssertEqual(windows.setFrameCalls.count, before)
    }
}
```

Note: the expected frame numbers assume the `FakeWindows` frame of 1000×800 and `outerGap` 10 (as in `ControllerTests`): a 0.5 column is 490 wide. In `testApplyTemplateKeepsFocus...` window 3 was focused after `start()`? `addWindow` focuses the last added, so focus is 3 before the template. Keep the assertions as written.

- [ ] **Step 2: Run to verify failure**

Run: `swift test --filter "TemplateBoardTests|ControllerTemplateTests"` — Expected: compile errors (`TemplateBoard`, `applyTemplate`, `showTemplates` missing).

- [ ] **Step 3: Implement**

`Sources/UltrawrailCore/TemplateBoard.swift`:

```swift
import LayoutEngine

/// Panel state: the chosen template, the open windows and which window sits in each slot.
public struct TemplateBoard: Equatable, Sendable {
    public private(set) var template: Template
    public let windows: [WindowID]
    public private(set) var assignment: [WindowID?]

    public init(template: Template, windows: [WindowID]) {
        self.template = template
        self.windows = windows
        self.assignment = template.defaultAssignment(for: windows)
    }

    public var unassigned: [WindowID] {
        windows.filter { id in !assignment.contains(id) }
    }

    public mutating func select(_ template: Template) {
        self.template = template
        assignment = template.defaultAssignment(for: windows)
    }

    /// Puts `id` in `slot`. If the slot was occupied, the occupant takes the slot `id` came
    /// from (swap) or becomes unassigned when `id` came from the list.
    public mutating func drop(_ id: WindowID, onSlot slot: Int) {
        guard windows.contains(id), assignment.indices.contains(slot) else { return }
        let source = assignment.firstIndex(of: id)
        let occupant = assignment[slot]
        if let source { assignment[source] = occupant }
        assignment[slot] = id
    }

    public mutating func unassign(_ id: WindowID) {
        if let index = assignment.firstIndex(of: id) { assignment[index] = nil }
    }
}
```

`Sources/LayoutEngine/Types.swift`: change to `case moveColumnLeft, moveColumnRight` line followed by `    case showTemplates` (new line in `Command`). In `Workspace.apply(_ command:)` change `case .centerColumn: break` into `case .centerColumn, .showTemplates: break`.

`Sources/UltrawrailCore/Protocols.swift`: add

```swift
public struct WindowDescription: Equatable, Sendable {
    public let appName: String
    public let pid: Int32
    public init(appName: String, pid: Int32) {
        self.appName = appName
        self.pid = pid
    }
}
```

and, in `WindowService`, `func describe(_ id: WindowID) -> WindowDescription?`.

`Tests/UltrawrailCoreTests/ControllerTests.swift`, in `FakeWindows`: `var descriptions: [WindowID: WindowDescription] = [:]` and `func describe(_ id: WindowID) -> WindowDescription? { descriptions[id] }`.

`Sources/UltrawrailCore/Controller.swift`: add public API

```swift
    public var onShowTemplates: (() -> Void)?
    public var managedWindows: [WindowID] { workspace.allWindows }

    public func describe(_ id: WindowID) -> WindowDescription? { windows.describe(id) }

    public func applyTemplate(_ template: Template, assignment: [WindowID?]) {
        workspace.apply(template, assignment: assignment, viewport: windows.usableFrame(), config: config)
        relayout()
        if let id = workspace.focusedWindow { windows.focus(id) }
    }
```

and, at the top of `handle(_ command:)`, `if command == .showTemplates { onShowTemplates?(); return }`. Place the `public var`s with the other public properties (match the file's ordering).

- [ ] **Step 4: Run to verify pass**

Run: `swift test` — Expected: all pass. `swift build` 0 warnings (the app target does not yet conform to `describe`: Task 3 adds it; to keep the build green now, add the `describe` implementation in `AXWindowService` in this task as well, see Task 3 Step 1, or temporarily return nil there and replace it in Task 3).

- [ ] **Step 5: Commit**

```bash
git add Sources Tests
git commit -m "feat: add template board state and controller template support"
```

---

### Task 3: App wiring: describe, hotkey, panel hook

**Files:**
- Modify: `Sources/UltrawrailApp/AXWindowService.swift`, `Sources/UltrawrailApp/CarbonHotkeyService.swift`, `Sources/UltrawrailApp/AppDelegate.swift`
- Create: `Sources/UltrawrailApp/TemplatePanelController.swift` (stub class only in this task, full UI in Task 4)

**Interfaces:**
- Consumes: Task 2 APIs.
- Produces: `TemplatePanelController.init(controller: Controller)` and `toggle()`, called from `onShowTemplates`.

- [ ] **Step 1: `AXWindowService.describe`** — read the file first. Add (entries hold the pid; `NSRunningApplication` gives the name):

```swift
    func describe(_ id: WindowID) -> WindowDescription? {
        guard let entry = entries[id] else { return nil }
        let name = NSRunningApplication(processIdentifier: entry.pid)?.localizedName ?? "App"
        return WindowDescription(appName: name, pid: Int32(entry.pid))
    }
```

- [ ] **Step 2: Hotkey** — in `CarbonHotkeyService.bindings` add after the move-column bindings:

```swift
        Binding(name: "⌃⌥T", keyCode: kVK_ANSI_T, command: .showTemplates),
```

- [ ] **Step 3: Panel stub** — `Sources/UltrawrailApp/TemplatePanelController.swift`:

```swift
import AppKit
import LayoutEngine
import UltrawrailCore

@MainActor
final class TemplatePanelController: NSObject {
    private let controller: Controller

    init(controller: Controller) {
        self.controller = controller
        super.init()
    }

    func toggle() {}
}
```

- [ ] **Step 4: AppDelegate** — read it. Where the `Controller` is created and before `controller.start()` (same place where `onChange` is set), create `let templates = TemplatePanelController(controller: controller)`, keep it in a stored property (for example `private var templatePanel: TemplatePanelController?`), and set `controller.onShowTemplates = { [weak self] in self?.templatePanel?.toggle() }`.

- [ ] **Step 5: Verify** — `swift build` (0 warnings), `swift test` (all pass). Do not launch the app.

- [ ] **Step 6: Commit**

```bash
git add Sources
git commit -m "feat: register templates shortcut and window descriptions"
```

---

### Task 4: Panel UI with drag and drop

**Files:**
- Modify (replace stub): `Sources/UltrawrailApp/TemplatePanelController.swift`
- Create: `Sources/UltrawrailApp/TemplateBoardView.swift`

**Interfaces:**
- Consumes: `TemplateBoard`, `Template.all`, `Controller.managedWindows/describe/applyTemplate`.
- Produces: the visible panel. Verified by build only; behavior is checked by hand (Task 5).

- [ ] **Step 1: `TemplateBoardView.swift`** — one flipped `NSView` that draws and handles everything. Layout (view is 560×330): cards row at the top (height 70, three cards, each 150×70, 12 px gap, origin x 16); slot area at left (x 16, y 100, width 330, height 190); window list at right (x 366, y 100, width 178, chips 34 high, 6 px gap); notice text under the slot area.

```swift
import AppKit
import LayoutEngine
import UltrawrailCore

let windowDragType = NSPasteboard.PasteboardType("dev.ultrawrail.window-id")

struct WindowChip {
    let id: WindowID
    let name: String
    let icon: NSImage?
}

final class TemplateBoardView: NSView {
    var board: TemplateBoard { didSet { needsDisplay = true } }
    private let chips: [WindowID: WindowChip]
    private var dragCandidate: WindowID?
    private var dragOrigin: NSPoint = .zero

    init(board: TemplateBoard, chips: [WindowID: WindowChip]) {
        self.board = board
        self.chips = chips
        super.init(frame: NSRect(x: 0, y: 0, width: 560, height: 330))
        registerForDraggedTypes([windowDragType])
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override var isFlipped: Bool { true }

    // MARK: geometry

    private func cardRect(_ index: Int) -> NSRect {
        NSRect(x: 16 + CGFloat(index) * 162, y: 16, width: 150, height: 70)
    }

    private let slotArea = NSRect(x: 16, y: 100, width: 330, height: 190)
    private let listArea = NSRect(x: 366, y: 100, width: 178, height: 190)

    /// One rect per slot, in slot order: columns split `slotArea` by their width share.
    private func slotRects() -> [NSRect] {
        let template = board.template
        let gap: CGFloat = 6
        let totalWidth = template.columns.reduce(0) { $0 + $1.width }
        let usable = slotArea.width - gap * CGFloat(template.columns.count - 1)
        var rects: [NSRect] = []
        var x = slotArea.minX
        for column in template.columns {
            let width = usable * CGFloat(column.width / totalWidth)
            let height = (slotArea.height - gap * CGFloat(column.slots - 1)) / CGFloat(column.slots)
            for row in 0..<column.slots {
                rects.append(NSRect(x: x, y: slotArea.minY + CGFloat(row) * (height + gap), width: width, height: height))
            }
            x += width + gap
        }
        return rects
    }

    private func chipRect(inList index: Int) -> NSRect {
        NSRect(x: listArea.minX, y: listArea.minY + CGFloat(index) * 40, width: listArea.width, height: 34)
    }

    private func listChips() -> [WindowID] { board.windows }

    // MARK: drawing

    override func draw(_ dirtyRect: NSRect) {
        for (index, template) in Template.all.enumerated() {
            drawCard(template, in: cardRect(index), selected: template.id == board.template.id)
        }
        for (index, rect) in slotRects().enumerated() {
            let path = NSBezierPath(roundedRect: rect, xRadius: 8, yRadius: 8)
            NSColor.quaternaryLabelColor.setFill()
            path.fill()
            NSColor.separatorColor.setStroke()
            path.lineWidth = 1
            path.stroke()
            if let id = board.assignment[index], let chip = chips[id] {
                drawChip(chip, in: rect.insetBy(dx: 6, dy: 6), highlighted: true)
            } else {
                draw(text: "Hueco \(index + 1)", in: rect, color: .tertiaryLabelColor, centered: true)
            }
        }
        for (index, id) in listChips().enumerated() {
            guard let chip = chips[id] else { continue }
            let placed = !board.unassigned.contains(id)
            drawChip(chip, in: chipRect(inList: index), highlighted: false, dimmed: placed)
        }
        let extra = board.unassigned.count
        if extra > 0 {
            let text = extra == 1 ? "1 ventana irá a una columna extra" : "\(extra) ventanas irán a columnas extra"
            draw(text: text, in: NSRect(x: 16, y: 298, width: 330, height: 20), color: .secondaryLabelColor, centered: false)
        }
    }

    private func drawCard(_ template: Template, in rect: NSRect, selected: Bool) {
        let path = NSBezierPath(roundedRect: rect, xRadius: 8, yRadius: 8)
        (selected ? NSColor.controlAccentColor.withAlphaComponent(0.15) : NSColor.quaternaryLabelColor).setFill()
        path.fill()
        (selected ? NSColor.controlAccentColor : NSColor.separatorColor).setStroke()
        path.lineWidth = selected ? 2 : 1
        path.stroke()
        let thumb = rect.insetBy(dx: 10, dy: 8)
        let preview = NSRect(x: thumb.minX, y: thumb.minY, width: thumb.width, height: 38)
        let gap: CGFloat = 3
        let total = template.columns.reduce(0) { $0 + $1.width }
        let usable = preview.width - gap * CGFloat(template.columns.count - 1)
        var x = preview.minX
        for column in template.columns {
            let width = usable * CGFloat(column.width / total)
            let height = (preview.height - gap * CGFloat(column.slots - 1)) / CGFloat(column.slots)
            for row in 0..<column.slots {
                let r = NSRect(x: x, y: preview.minY + CGFloat(row) * (height + gap), width: width, height: height)
                NSColor.secondaryLabelColor.setFill()
                NSBezierPath(roundedRect: r, xRadius: 2, yRadius: 2).fill()
            }
            x += width + gap
        }
        draw(text: template.name, in: NSRect(x: rect.minX, y: rect.maxY - 22, width: rect.width, height: 18),
             color: .labelColor, centered: true)
    }

    private func drawChip(_ chip: WindowChip, in rect: NSRect, highlighted: Bool, dimmed: Bool = false) {
        let path = NSBezierPath(roundedRect: rect, xRadius: 6, yRadius: 6)
        (highlighted ? NSColor.controlAccentColor.withAlphaComponent(0.25) : NSColor.controlBackgroundColor)
            .withAlphaComponent(dimmed ? 0.5 : 1).setFill()
        path.fill()
        NSColor.separatorColor.setStroke()
        path.lineWidth = 1
        path.stroke()
        let iconSize: CGFloat = 22
        let iconRect = NSRect(x: rect.minX + 6, y: rect.midY - iconSize / 2, width: iconSize, height: iconSize)
        chip.icon?.draw(in: iconRect, from: .zero, operation: .sourceOver, fraction: dimmed ? 0.5 : 1,
                        respectFlipped: true, hints: nil)
        draw(text: chip.name, in: NSRect(x: iconRect.maxX + 6, y: rect.minY, width: rect.width - iconSize - 18, height: rect.height),
             color: dimmed ? .tertiaryLabelColor : .labelColor, centered: false, verticallyCentered: true)
    }

    private func draw(text: String, in rect: NSRect, color: NSColor, centered: Bool, verticallyCentered: Bool = false) {
        let style = NSMutableParagraphStyle()
        style.alignment = centered ? .center : .left
        style.lineBreakMode = .byTruncatingTail
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12),
            .foregroundColor: color,
            .paragraphStyle: style,
        ]
        var target = rect
        if verticallyCentered || centered {
            let height = (text as NSString).size(withAttributes: attributes).height
            target.origin.y = rect.midY - height / 2
            target.size.height = height
        }
        (text as NSString).draw(in: target, withAttributes: attributes)
    }

    // MARK: mouse and dragging

    private func windowAt(_ point: NSPoint) -> WindowID? {
        for (index, rect) in slotRects().enumerated() where rect.contains(point) {
            if let id = board.assignment[index] { return id }
        }
        for (index, id) in listChips().enumerated() where chipRect(inList: index).contains(point) {
            return id
        }
        return nil
    }

    private func slotIndex(at point: NSPoint) -> Int? {
        slotRects().firstIndex { $0.contains(point) }
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        for (index, template) in Template.all.enumerated() where cardRect(index).contains(point) {
            board.select(template)
            return
        }
        dragCandidate = windowAt(point)
        dragOrigin = point
    }

    override func mouseDragged(with event: NSEvent) {
        guard let id = dragCandidate, let chip = chips[id] else { return }
        let point = convert(event.locationInWindow, from: nil)
        guard hypot(point.x - dragOrigin.x, point.y - dragOrigin.y) > 4 else { return }
        dragCandidate = nil
        let item = NSPasteboardItem()
        item.setString(String(id.rawValue), forType: windowDragType)
        let dragging = NSDraggingItem(pasteboardWriter: item)
        let size = NSSize(width: 150, height: 34)
        let image = NSImage(size: size, flipped: true) { rect in
            let path = NSBezierPath(roundedRect: rect, xRadius: 6, yRadius: 6)
            NSColor.controlAccentColor.withAlphaComponent(0.4).setFill()
            path.fill()
            chip.icon?.draw(in: NSRect(x: 6, y: 6, width: 22, height: 22))
            (chip.name as NSString).draw(at: NSPoint(x: 34, y: 9), withAttributes: [
                .font: NSFont.systemFont(ofSize: 12),
                .foregroundColor: NSColor.labelColor,
            ])
            return true
        }
        dragging.setDraggingFrame(NSRect(x: point.x - 75, y: point.y - 17, width: size.width, height: size.height), contents: image)
        beginDraggingSession(with: [dragging], event: event, source: self)
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation { .move }
    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation { .move }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let raw = sender.draggingPasteboard.string(forType: windowDragType),
              let value = Int(raw) else { return false }
        let id = WindowID(value)
        let point = convert(sender.draggingLocation, from: nil)
        if let slot = slotIndex(at: point) {
            board.drop(id, onSlot: slot)
        } else if listArea.contains(point) {
            board.unassign(id)
        } else {
            return false
        }
        return true
    }
}

extension TemplateBoardView: NSDraggingSource {
    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        .move
    }
}
```

- [ ] **Step 2: `TemplatePanelController.swift`** — replace the stub:

```swift
import AppKit
import LayoutEngine
import UltrawrailCore

@MainActor
final class TemplatePanelController: NSObject {
    private let controller: Controller
    private var panel: NSPanel?
    private var boardView: TemplateBoardView?

    init(controller: Controller) {
        self.controller = controller
        super.init()
    }

    func toggle() {
        if let panel, panel.isVisible {
            close()
        } else {
            open()
        }
    }

    private func open() {
        let ids = controller.managedWindows
        guard !ids.isEmpty else { return }
        var chips: [WindowID: WindowChip] = [:]
        for id in ids {
            let description = controller.describe(id)
            let icon = description.flatMap { NSRunningApplication(processIdentifier: pid_t($0.pid))?.icon }
            chips[id] = WindowChip(id: id, name: description?.appName ?? "Ventana", icon: icon)
        }
        let board = TemplateBoard(template: Template.all[0], windows: ids)
        let boardView = TemplateBoardView(board: board, chips: chips)
        self.boardView = boardView

        let content = NSView(frame: NSRect(x: 0, y: 0, width: 560, height: 380))
        boardView.frame.origin = NSPoint(x: 0, y: 50)
        content.addSubview(boardView)

        let apply = NSButton(title: "Aplicar", target: self, action: #selector(applyTapped))
        apply.keyEquivalent = "\r"
        apply.frame = NSRect(x: 456, y: 12, width: 88, height: 28)
        let cancel = NSButton(title: "Cancelar", target: self, action: #selector(cancelTapped))
        cancel.keyEquivalent = "\u{1b}"
        cancel.frame = NSRect(x: 360, y: 12, width: 88, height: 28)
        content.addSubview(apply)
        content.addSubview(cancel)

        let panel = NSPanel(contentRect: content.frame,
                            styleMask: [.titled, .closable, .utilityWindow],
                            backing: .buffered, defer: false)
        panel.title = "Plantillas"
        panel.level = .floating
        panel.isReleasedWhenClosed = false
        panel.contentView = content
        panel.center()
        self.panel = panel
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }

    private func close() {
        panel?.orderOut(nil)
        panel = nil
        boardView = nil
    }

    @objc private func applyTapped() {
        guard let board = boardView?.board else { return }
        close()
        controller.applyTemplate(board.template, assignment: board.assignment)
    }

    @objc private func cancelTapped() {
        close()
    }
}
```

`TemplateBoardView` is flipped; the 50 px bottom strip of `content` (non-flipped) holds the buttons, so `boardView` (330 high) sits at y=50 of a 380 high content view. Verify visually that the board is not clipped; if the content view is flipped by AppKit defaults adapt the two origins only.

- [ ] **Step 3: Verify** — `swift build` (0 warnings), `swift test` (all pass). Fix any compile issues with the smallest change that preserves behavior and list them in the report. Do not launch the app.

- [ ] **Step 4: Commit**

```bash
git add Sources
git commit -m "feat: add templates panel with drag and drop"
```

---

### Task 5: Smoke test docs

**Files:**
- Modify: `docs/smoke-test.md`

- [ ] **Step 1: Add a section** "Plantillas" before "Limitaciones conocidas" (match the numbered-steps style of the file), with these steps:

1. Ctrl+Alt+T abre el panel centrado con tres tarjetas (Mitades, Principal + lateral, Mitad + dos apiladas). Pulsarlo de nuevo, o Esc, lo cierra sin cambiar nada.
2. Elegir cada tarjeta redibuja los huecos y rellena las fichas por orden de columna.
3. Arrastrar una ficha de la lista a un hueco la asigna; sobre un hueco ocupado, intercambia o libera al ocupante.
4. Arrastrar una ficha desde un hueco a la lista la desasigna; con ventanas sin hueco aparece el aviso de columnas extra.
5. Aplicar (botón o Intro) reordena las ventanas con animación y mantiene el foco; el preview del menú refleja el cambio.
6. Con más ventanas que huecos, las sobrantes quedan como columnas a la derecha y ninguna desaparece.
7. El panel se ve bien en modo claro y oscuro.

- [ ] **Step 2: Add `Ctrl + Alt + T` to the shortcut list in that file** if it contains one.

- [ ] **Step 3: Commit**

```bash
git add docs
git commit -m "docs: add templates panel smoke steps"
```
