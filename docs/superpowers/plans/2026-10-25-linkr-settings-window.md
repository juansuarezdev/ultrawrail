# Linkr Settings Window Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A normal-app settings window (Cmd+, / menu "Ajustes…") with General, Diseño and Atajos tabs; Dock icon only while it is open; spacing and default column width configurable live.

**Architecture:** `Controller.config` becomes mutable and `Workspace.newColumnWidth` is added (engine/core, unit-tested). In `LinkrApp`, one `SettingsModel` (ObservableObject) is the single source of truth: it persists into the existing `UserDefaults` stores and notifies `AppDelegate`, which pushes values to the `Controller` and rebuilds the menu. A SwiftUI `TabView` inside an `NSWindow` edits the model. Spec: `docs/superpowers/specs/2026-10-25-linkr-settings-window-design.md`.

**Tech Stack:** Swift 5 mode, SwiftPM, SwiftUI + AppKit, XCTest, macOS 13+.

## Global Constraints

- Branch `feat/settings-window`; default branch is `main` (never `master`).
- No AI attribution or `Co-Authored-By`; commits in English (`feat:`/`fix:`/`docs:`).
- `swift build` 0 warnings; `swift test` must pass. Do not launch the app or run `scripts/bundle.sh` (the user runs it).
- UI strings in Spanish, matching the app.
- Ranges and defaults (exact): gap 0–40 px default 8; outer gap 0–60 px default 8; new column width one of 0.25, 0.33, 0.5, 0.66, 0.75, default 0.5 (`WidthPreset.all`, `WidthPreset.defaultWidth`).
- `UserDefaults` keys (exact): existing `motionSpeed`, `respectReduceMotion`, `placementMode`, `keyboardStyle`; new `gap`, `outerGap`, `newColumnWidth`.
- Existing APIs: `MotionSettings(speed:respectReduceMotion:)`, `MotionSpeed`, `PlacementMode`, `KeyboardStyle`, `ShortcutLegend.entries/line(for:style:)`, stores `MotionSettingsStore`, `PlacementStore`, `KeyboardStyleStore` (all `nonmutating set`), `LayoutConfig(gap:outerGap:)` (Equatable), `Controller.motion/placement`.

---

### Task 1: Mutable config and newColumnWidth (engine + core)

**Files:**
- Modify: `Sources/LayoutEngine/Workspace.swift`, `Sources/LinkrCore/Controller.swift`
- Test: `Tests/LayoutEngineTests/WorkspaceTests.swift` (append), `Tests/LinkrCoreTests/ControllerSettingsTests.swift` (new)

**Interfaces:**
- Produces: `Workspace.newColumnWidth: Double`, `Controller.config` (public var), `Controller.newColumnWidth: Double` (get/set).

- [ ] **Step 1: Write the failing tests**

Append inside `WorkspaceTests` (same class as the other workspace tests; `makeWorkspace(_:)` exists there):

```swift
    func testNewColumnWidthAppliesToAddedWindows() {
        var ws = Workspace()
        ws.newColumnWidth = 0.33
        ws.addWindow(1)
        XCTAssertEqual(ws.columns[0].width, 0.33)
    }

    func testChangingNewColumnWidthLeavesExistingColumnsAlone() {
        var ws = makeWorkspace(2)
        ws.newColumnWidth = 0.75
        XCTAssertEqual(ws.columns.map(\.width), [0.5, 0.5])
        ws.addWindow(3)
        XCTAssertEqual(ws.columns.map(\.width), [0.5, 0.5, 0.75])
    }

    func testUnstackedWindowGetsNewColumnWidth() {
        var ws = makeWorkspace(2)
        ws.apply(.stackLeft)            // [[1, 2]]
        ws.newColumnWidth = 0.25
        ws.apply(.unstack)
        XCTAssertEqual(ws.columns.map(\.windows), [[1], [2]])
        XCTAssertEqual(ws.columns[1].width, 0.25)
    }
```

(Type the first test's name as `testNewColumnWidthAppliesToAddedWindows`; no special characters.)

`Tests/LinkrCoreTests/ControllerSettingsTests.swift` (uses `FakeWindows`/`FakeHotkeys` from `ControllerTests.swift`):

```swift
import XCTest
import CoreGraphics
import LayoutEngine
@testable import LinkrCore

@MainActor
final class ControllerSettingsTests: XCTestCase {
    func makeController(_ ids: [Int]) -> (Controller, FakeWindows) {
        let windows = FakeWindows()
        for id in ids { windows.add(id) }
        let controller = Controller(windows: windows, hotkeys: FakeHotkeys(), config: LayoutConfig(gap: 10, outerGap: 10))
        controller.start()
        return (controller, windows)
    }

    func testChangingConfigRelaysOutEveryWindow() {
        let (controller, windows) = makeController([1, 2])
        XCTAssertEqual(windows.lastRect(2)?.origin.y, 10)
        controller.config = LayoutConfig(gap: 20, outerGap: 20)
        XCTAssertEqual(windows.lastRect(2)?.origin.y, 20)
        XCTAssertEqual(windows.lastRect(2)?.height, 760)
        XCTAssertEqual(windows.lastRect(1)?.origin.y, 20)
    }

    func testSettingSameConfigWritesNothing() {
        let (controller, windows) = makeController([1, 2])
        let before = windows.setFrameCalls.count
        controller.config = LayoutConfig(gap: 10, outerGap: 10)
        XCTAssertEqual(windows.setFrameCalls.count, before)
    }

    func testNewColumnWidthAffectsOnlyColumnsAddedLater() {
        let (controller, windows) = makeController([1])
        controller.newColumnWidth = 0.33
        XCTAssertEqual(controller.workspace.columns.map(\.width), [0.5])
        windows.alive.insert(2)
        controller.handle(.opened(WindowInfo(id: 2, isManageable: true)))
        XCTAssertEqual(controller.workspace.columns.map(\.width), [0.5, 0.33])
    }
}
```

- [ ] **Step 2: Run to verify failure** — `swift test --filter LayoutEngineTests` and `swift test --filter LinkrCoreTests` fail to compile (`newColumnWidth`, mutable `config`).

- [ ] **Step 3: Implement**

`Workspace.swift`: add the stored property next to `scrollOffset`:

```swift
    /// Width given to columns created from now on (new windows, unstacked windows, leftovers).
    public var newColumnWidth: Double = WidthPreset.defaultWidth
```

and replace the three `Column(windows: ...)` creations that use the default width so they pass `width: newColumnWidth`: in `addWindow` (`Column(windows: [id], width: newColumnWidth)`), in `apply(template)` leftovers (`Column(windows: [id], width: newColumnWidth)`) and in `unstack` (`Column(windows: [id], width: newColumnWidth)`). Do not touch template-column creation (`width: spec.width`).

`Controller.swift`: replace `private let config: LayoutConfig` with

```swift
    public var config: LayoutConfig {
        didSet { if config != oldValue { relayout(force: true) } }
    }
    public var newColumnWidth: Double {
        get { workspace.newColumnWidth }
        set { workspace.newColumnWidth = newValue }
    }
```

`workspace` is `private(set)` but is mutated inside the class, which is allowed. `init` keeps `self.config = config` (no `didSet` fires in init).

- [ ] **Step 4: Run to verify pass** — `swift test` all green, `swift build` 0 warnings.

- [ ] **Step 5: Commit**

```bash
git add Sources Tests
git commit -m "feat: make layout config and new column width adjustable at runtime"
```

---

### Task 2: LayoutSettingsStore, SettingsModel and AppDelegate wiring

**Files:**
- Create: `Sources/LinkrApp/LayoutSettingsStore.swift`, `Sources/LinkrApp/SettingsModel.swift`
- Modify: `Sources/LinkrApp/AppDelegate.swift`

**Interfaces:**
- Consumes: Task 1 (`Controller.config`, `Controller.newColumnWidth`).
- Produces: `SettingsModel` (see code) with `onChange`; `AppDelegate.model`.

- [ ] **Step 1: `LayoutSettingsStore.swift`**

```swift
import Foundation

struct LayoutSettings: Equatable {
    var gap: Double = 8
    var outerGap: Double = 8
    var newColumnWidth: Double = 0.5
}

struct LayoutSettingsStore {
    private let defaults = UserDefaults.standard

    var settings: LayoutSettings {
        get {
            var value = LayoutSettings()
            if let gap = defaults.object(forKey: "gap") as? Double { value.gap = min(40, max(0, gap)) }
            if let outer = defaults.object(forKey: "outerGap") as? Double { value.outerGap = min(60, max(0, outer)) }
            if let width = defaults.object(forKey: "newColumnWidth") as? Double { value.newColumnWidth = width }
            return value
        }
        nonmutating set {
            defaults.set(newValue.gap, forKey: "gap")
            defaults.set(newValue.outerGap, forKey: "outerGap")
            defaults.set(newValue.newColumnWidth, forKey: "newColumnWidth")
        }
    }
}
```

- [ ] **Step 2: `SettingsModel.swift`**

```swift
import Foundation
import LayoutEngine
import LinkrCore
import ServiceManagement

/// Single source of truth for every user setting. The menu and the settings window both edit it.
@MainActor
final class SettingsModel: ObservableObject {
    private let motionStore = MotionSettingsStore()
    private let placementStore = PlacementStore()
    private let keyboardStore = KeyboardStyleStore()
    private let layoutStore = LayoutSettingsStore()
    private var loading = true

    var onChange: (() -> Void)?

    @Published var speed: MotionSpeed { didSet { commit() } }
    @Published var respectReduceMotion: Bool { didSet { commit() } }
    @Published var placement: PlacementMode { didSet { commit() } }
    @Published var keyboardStyle: KeyboardStyle { didSet { commit() } }
    @Published var gap: Double { didSet { commit() } }
    @Published var outerGap: Double { didSet { commit() } }
    @Published var newColumnWidth: Double { didSet { commit() } }
    @Published var launchAtLogin: Bool {
        didSet {
            guard !loading, launchAtLogin != oldValue else { return }
            do {
                if launchAtLogin { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            } catch {
                NSLog("Linkr: login item change failed: \(error)")
                loading = true
                launchAtLogin = oldValue
                loading = false
            }
            onChange?()
        }
    }

    init() {
        let motion = motionStore.settings
        let layout = layoutStore.settings
        speed = motion.speed
        respectReduceMotion = motion.respectReduceMotion
        placement = placementStore.mode
        keyboardStyle = keyboardStore.style
        gap = layout.gap
        outerGap = layout.outerGap
        newColumnWidth = layout.newColumnWidth
        launchAtLogin = SMAppService.mainApp.status == .enabled
        loading = false
    }

    var motion: MotionSettings { MotionSettings(speed: speed, respectReduceMotion: respectReduceMotion) }
    var layoutConfig: LayoutConfig { LayoutConfig(gap: gap, outerGap: outerGap) }

    func restoreLayoutDefaults() {
        let defaults = LayoutSettings()
        gap = defaults.gap
        outerGap = defaults.outerGap
        newColumnWidth = defaults.newColumnWidth
    }

    private func commit() {
        guard !loading else { return }
        motionStore.settings = motion
        placementStore.mode = placement
        keyboardStore.style = keyboardStyle
        layoutStore.settings = LayoutSettings(gap: gap, outerGap: outerGap, newColumnWidth: newColumnWidth)
        onChange?()
    }
}
```

Note: `restoreLayoutDefaults` sets three properties, each calling `commit()`/`onChange` (three relayouts of the same final state are cheap because `Controller.config` ignores unchanged values and writes are cached by `lastApplied`); keep it simple.

- [ ] **Step 3: AppDelegate wiring.** Read the file first. Make these changes:
  1. Add `let model = SettingsModel()` and set `model.onChange = { [weak self] in self?.settingsChanged() }` at the start of `applicationDidFinishLaunching`.
  2. Add:

```swift
    private func settingsChanged() {
        controller?.motion = model.motion
        controller?.placement = model.placement
        controller?.config = model.layoutConfig
        controller?.newColumnWidth = model.newColumnWidth
        rebuildMenu()
    }
```

  3. In `startController`, replace `controller.motion = settingsStore.settings` / `controller.placement = placementStore.mode` with `controller.motion = model.motion`, `controller.placement = model.placement`, `controller.newColumnWidth = model.newColumnWidth`, and pass `config: model.layoutConfig` in the `Controller(...)` initializer call.
  4. Make the menu read from the model (`model.motion`, `model.placement`, `model.keyboardStyle`, `model.launchAtLogin`) instead of the stores, and make the actions write to it: `selectSpeed` → `model.speed = speed`; `toggleReduceMotion` → `model.respectReduceMotion.toggle()`; `selectPlacement` → `model.placement = mode`; `selectKeyboardStyle` → `model.keyboardStyle = style`; `toggleLogin` → `model.launchAtLogin.toggle()`. Delete the now-unused `apply(_ settings:)` and the three store properties of `AppDelegate` that are no longer read (`settingsStore`, `keyboardStore`, `placementStore`); in `workspaceChanged` use `model.motion.previewDuration(reduceMotion: reduceMotion)`. Each action no longer calls `rebuildMenu()` itself (`onChange` does it).
  5. Remove the `import ServiceManagement` from `AppDelegate` only if nothing there uses it any more.

- [ ] **Step 4: Verify** — `swift build` (0 warnings), `swift test` all pass. Do not launch the app.

- [ ] **Step 5: Commit**

```bash
git add Sources
git commit -m "feat: add settings model shared by the menu and controller"
```

---

### Task 3: SwiftUI settings window and Dock behavior

**Files:**
- Create: `Sources/LinkrApp/SettingsView.swift`, `Sources/LinkrApp/SettingsWindowController.swift`
- Modify: `Sources/LinkrApp/AppDelegate.swift` (menu item + controller property)

**Interfaces:**
- Consumes: `SettingsModel` (Task 2), `ShortcutLegend`, `WidthPreset.all`.
- Produces: `SettingsWindowController.init(model:)`, `show()`.

- [ ] **Step 1: `SettingsView.swift`**

```swift
import LayoutEngine
import LinkrCore
import SwiftUI

struct SettingsView: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        TabView {
            GeneralTab(model: model)
                .tabItem { Label("General", systemImage: "gearshape") }
            LayoutTab(model: model)
                .tabItem { Label("Diseño", systemImage: "rectangle.split.3x1") }
            ShortcutsTab(model: model)
                .tabItem { Label("Atajos", systemImage: "keyboard") }
        }
        .frame(width: 520, height: 420)
    }
}

private struct GeneralTab: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        Form {
            Picker("Velocidad de animación", selection: $model.speed) {
                Text("Rápida").tag(MotionSpeed.fast)
                Text("Normal").tag(MotionSpeed.normal)
                Text("Desactivada").tag(MotionSpeed.off)
            }
            Toggle("Respetar Reducir movimiento del sistema", isOn: $model.respectReduceMotion)
            Picker("Ventanas nuevas", selection: $model.placement) {
                Text("Manual (Ctrl+Alt+A para añadir)").tag(PlacementMode.manual)
                Text("Automático").tag(PlacementMode.automatic)
            }
            Picker("Teclado", selection: $model.keyboardStyle) {
                Text("Windows").tag(KeyboardStyle.windows)
                Text("Mac").tag(KeyboardStyle.mac)
            }
            .pickerStyle(.segmented)
            Toggle("Iniciar al arrancar", isOn: $model.launchAtLogin)
        }
        .formStyle(.grouped)
    }
}

private struct LayoutTab: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        Form {
            VStack(alignment: .leading) {
                Text("Hueco entre ventanas: \(Int(model.gap)) px")
                Slider(value: $model.gap, in: 0...40, step: 1)
            }
            VStack(alignment: .leading) {
                Text("Margen exterior: \(Int(model.outerGap)) px")
                Slider(value: $model.outerGap, in: 0...60, step: 1)
            }
            Picker("Ancho de las columnas nuevas", selection: $model.newColumnWidth) {
                ForEach(WidthPreset.all, id: \.self) { width in
                    Text("\(Int((width * 100).rounded())) %").tag(width)
                }
            }
            Button("Restaurar valores") { model.restoreLayoutDefaults() }
        }
        .formStyle(.grouped)
    }
}

private struct ShortcutsTab: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("Teclado", selection: $model.keyboardStyle) {
                Text("Windows").tag(KeyboardStyle.windows)
                Text("Mac").tag(KeyboardStyle.mac)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            List(ShortcutLegend.entries, id: \.title) { entry in
                Text(ShortcutLegend.line(for: entry, style: model.keyboardStyle))
                    .font(.system(.body, design: .monospaced))
            }
        }
        .padding()
    }
}
```

`ShortcutLegend.entries` entries have unique titles, so `id: \.title` is fine. If `Picker` selection of `Double` with `WidthPreset.all` values fails to match because of floating point, the values come from the same array, so they match.

- [ ] **Step 2: `SettingsWindowController.swift`**

```swift
import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    private let model: SettingsModel
    private var window: NSWindow?

    init(model: SettingsModel) {
        self.model = model
        super.init()
    }

    func show() {
        if window == nil {
            let hosting = NSHostingController(rootView: SettingsView(model: model))
            let window = NSWindow(contentViewController: hosting)
            window.title = "Ajustes de Linkr"
            window.styleMask = [.titled, .closable, .miniaturizable]
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.center()
            self.window = window
        }
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }
}
```

- [ ] **Step 3: AppDelegate menu item.** Add `private var settingsWindow: SettingsWindowController?` and create it in `applicationDidFinishLaunching` after `model` is set: `settingsWindow = SettingsWindowController(model: model)`. In `rebuildMenu`, add just above the "Iniciar al arrancar" item (and above "Atajos de teclado" submenu): 

```swift
        let settingsItem = NSMenuItem(title: "Ajustes…", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)
```

and the action `@objc private func openSettings() { settingsWindow?.show() }`. Keep the existing menu items.

- [ ] **Step 4: Verify** — `swift build` (0 warnings), `swift test` all pass. Fix compile issues with the smallest change that preserves behavior and list them in the report. Do not launch the app.

- [ ] **Step 5: Commit**

```bash
git add Sources
git commit -m "feat: add settings window with Dock icon while open"
```

---

### Task 4: Smoke test docs

**Files:** Modify `docs/smoke-test.md`.

- [ ] **Step 1:** Add a section "Ventana de ajustes" before "Limitaciones conocidas", in the file's numbered-steps style:
1. El menú tiene "Ajustes…" (Cmd+,). Al abrirlo aparece una ventana con pestañas General, Diseño y Atajos, y Linkr aparece en el Dock y en Cmd+Tab. Al cerrarla desaparece del Dock.
2. Abrir Ajustes dos veces reutiliza la misma ventana.
3. En General, cambiar velocidad, ventanas nuevas o teclado se refleja en el menú, y al revés.
4. En Diseño, mover "Hueco entre ventanas" y "Margen exterior" recoloca las ventanas en vivo. Cambiar el ancho de las columnas nuevas solo afecta a ventanas que se añaden después.
5. "Restaurar valores" vuelve a 8 px, 8 px y 50 %.
6. Los ajustes persisten al cerrar y reabrir Linkr.

- [ ] **Step 2: Commit**

```bash
git add docs
git commit -m "docs: add settings window smoke steps"
```
