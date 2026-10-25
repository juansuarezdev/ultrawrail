# Ultrawrail Zones Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task.

**Goal:** Split one ultrawide display into 1-3 side-by-side "zones" (virtual monitors); each zone has its own strip, focus and pages.

**Architecture:** Per-zone state (`pages`, `currentPage`) moves from `Controller` into a `Zone` value; `Controller` holds `zones: [Zone]` and `focusedZone`. The existing `workspace`, `pages`, `currentPage`, `managedWindows` and page commands keep working against the focused zone, so a single zone behaves exactly as today. Each zone lays out inside a vertical slice of `windows.usableFrame()` (equal widths, no extra gap: `outerGap` already pads inside each zone). Windows of other zones are laid out normally in their own slice (they are visible); only windows of inactive *pages* are parked.

## Global Constraints

- Defaults reproduce today's behavior: `zoneCount = 1`. Every existing test stays green unmodified.
- Zone count 1...3, equal widths: zone `i` of `n` covers `x = viewport.minX + i * W/n`, width `W/n`, full height.
- Notation in UI text and docs: Windows names (Win = ⌘, Alt = ⌥, Ctrl = ⌃, Shift). Symbols only in Mac keyboard style and in `CarbonHotkeyService` binding names.
- New hotkeys: Ctrl+Alt+Win+Left/Right = focus previous/next zone (modifiers `controlKey | optionKey | cmdKey`); Ctrl+Alt+Win+Shift+Left/Right = move the focused window to the previous/next zone (adds `shiftKey`).
- Spanish UI copy. Commits plain, no AI attribution. `swift build` 0 warnings. Filtered tests: `swift test --filter UltrawrailCoreTests.ClassName`.

---

### Task 1: Zones in Controller

**Files:** Modify `Sources/LayoutEngine/Types.swift` (Command), `Sources/UltrawrailCore/Controller.swift`; Test `Tests/UltrawrailCoreTests/ControllerZonesTests.swift` (same fake services as `ControllerPagesTests.swift`).

**Produces:**
```swift
// Command gains: focusZoneLeft, focusZoneRight, moveWindowToZoneLeft, moveWindowToZoneRight
// Controller:
public var zoneCount: Int { get set }            // clamped 1...3; didSet re-splits zones and relayouts (force)
public private(set) var focusedZone: Int
public var zonesInfo: (zone: Int, zoneCount: Int)  // or fields on WorkspaceSnapshot: zone: Int = 0, zoneCount: Int = 1 (appended, defaulted)
```
Behavior:
- Shrinking `zoneCount`: windows of removed zones are appended to the last remaining zone's current page (preserve order); growing adds empty zones. `focusedZone` is clamped.
- `focusZoneLeft/Right`: move `focusedZone` by one (no wrap), focus that zone's focused window if any (call `windows.focus`), otherwise just change the zone.
- `moveWindowToZoneLeft/Right`: focused window leaves the focused zone, joins the target zone's current page, focus follows it (same pattern as `moveWindowToNextPage`).
- New windows (`opened`, adopt, manual placement) join the focused zone's current page. `focused(id)` for a window in another zone switches `focusedZone` to it (inactive-page rule from pages still applies inside that zone). `closed` removes from every zone/page.
- Layout/relayout: for each zone compute its viewport slice, run the existing layout (reveal, clamp, frames) with that slice, park the zone's inactive-page windows as pages already do (relative to that zone's slice). `workspace`, `managedWindows`, `applyTemplate`, page commands, `newColumnWidth` act on the focused zone (`newColumnWidth` setter applies to all zones/pages).
- Snapshot: include `zone` and `zoneCount` (defaults 0, 1); `viewport` in the snapshot is the focused zone's slice so the menu preview shows that zone.
- `restoreParkedWindows` covers all zones.

Tests (write first): zoneCount 2 gives each zone half the usable width and windows opened land in the focused zone; focus/move commands; moving to the edge zone is a no-op; shrinking 3 to 1 merges windows; focused event in another zone switches the zone; per-zone page switching parks only that zone's inactive pages; zoneCount 1 identical to previous behavior (existing suites).

Run filtered, then full `swift test`, `swift build`. Commit: `feat: zones in controller`.

### Task 2: Hotkeys, legend, settings, menu, docs

**Files:** Modify `Sources/UltrawrailApp/CarbonHotkeyService.swift`, `Sources/UltrawrailCore/ShortcutLegend.swift` (+ test), `Sources/UltrawrailApp/{LayoutSettingsStore,SettingsModel,SettingsView,AppDelegate}.swift`, `docs/smoke-test.md`.

Requirements:
- Bindings from Global Constraints, names "⌃⌥⌘←", "⌃⌥⌘→", "⌃⌥⌘⇧←", "⌃⌥⌘⇧→" (use the existing modifier override on `Binding`).
- `ShortcutLegend`: entries "Zona anterior / siguiente" and "Mover ventana a la zona anterior / siguiente" in both styles (Windows: Ctrl+Alt+Win+←/→ and Ctrl+Alt+Win+Shift+←/→; Mac: ⌃⌥⌘←/→ and ⌃⌥⌘⇧←/→); update tests (entry count).
- Persist `zoneCount` (UserDefaults key `zoneCount`, clamp 1...3, default 1) in `LayoutSettingsStore`; `SettingsModel.zoneCount` published, "Restaurar valores" resets it to 1; AppDelegate pushes it to `controller.zoneCount` (on start and on change, like `newColumnWidth`).
- Diseño tab, ultrawide section: Picker (segmented) "Zonas de la pantalla": 1, 2, 3, with caption "Cada zona tiene su propia tira, foco y páginas."
- Menu: disabled line "Zona N de M" shown only when M > 1 (1-based), above/next to the page line.
- Smoke test section "Zonas" before "Limitaciones conocidas": (1) con 2 zonas la pantalla se divide en dos mitades; las ventanas nuevas entran en la zona con foco; (2) Ctrl+Alt+Win+→ pasa el foco a la zona siguiente; (3) con Shift mueve la ventana a esa zona; (4) cada zona cambia de página por separado con Win+Alt+←/→; (5) bajar de 3 a 1 zona junta todas las ventanas en la zona restante; (6) Ctrl+Alt+Win+flechas pueden chocar con atajos de otras apps y macOS no avisa; (7) la configuración persiste al reiniciar.
Run full `swift test`, `swift build`. Commit: `feat: zone hotkeys, legend, settings and menu`.
