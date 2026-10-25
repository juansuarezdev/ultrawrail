# Ultrawrail Pages Tab Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task.

**Goal:** A "Páginas" tab in Settings that shows every zone and page with its windows and lets the user move windows between pages and zones by drag and drop; plus a page switcher in the Ctrl+Alt+T templates panel.

**Architecture:** `Controller` exposes a read-only overview and a `moveWindow(_:toZone:page:)` operation (built on the existing zone/page move logic). `SettingsModel` holds a published copy of the overview, refreshed from the controller's `onChange`. The tab renders one column per page grouped by zone, with draggable window chips (icon + app name); dropping a chip on another page card moves the window. The templates panel gets "◀ Página N de M ▶" buttons that switch page and rebuild the board.

## Global Constraints

- Single zone and single page behave as today; every existing test stays green unmodified.
- Max 9 pages per zone, 3 zones (`Controller.maxPages`, `Controller.maxZones`).
- Spanish UI copy. Windows notation for shortcut text. Commits plain, no AI attribution. `swift build` 0 warnings. Do NOT launch, kill or relaunch the Ultrawrail app; verify with `swift build` / `swift test` only.
- Filtered tests: `swift test --filter UltrawrailCoreTests.ClassName`.

---

### Task 1: Controller overview and moveWindow

**Files:** Modify `Sources/UltrawrailCore/Controller.swift`; Test `Tests/UltrawrailCoreTests/ControllerOverviewTests.swift` (fakes as in `ControllerZonesTests.swift`).

**Produces:**
```swift
public struct PageOverview: Equatable, Sendable { public let windows: [WindowID]; public let isCurrent: Bool }
public struct ZoneOverview: Equatable, Sendable { public let pages: [PageOverview]; public let isFocused: Bool }
// Controller
public func overview() -> [ZoneOverview]
public func moveWindow(_ id: WindowID, toZone zone: Int, page: Int)
```
Behavior: `overview()` lists every zone and page in order; windows in column order. `moveWindow`: no-op for unknown window, zone outside `0..<zoneCount`, page `< 0`; a page index equal to the zone's page count creates a new page when `< maxPages` (otherwise no-op); any larger index is a no-op; moving to the same zone and page is a no-op. The window leaves its page, joins the target page (its width resets to the target's `newColumnWidth`, as in `moveFocusedWindow`), trailing empty pages are trimmed (never below 1 page per zone, never the current page), a forced relayout runs, and focus/current page/focused zone are NOT changed unless the moved window was the focused one (then focus follows it, same as `moveWindowToNextPage`). Reuse the existing private move helpers rather than duplicating them.
Tests (first): overview shape with 2 zones and 2 pages; move between pages; move to a new page; move across zones; invalid targets are no-ops; moved window is parked/visible according to the target page being current or not; trailing empty page trimmed after moving its only window away; focused window follows.
Run filtered, full `swift test`, `swift build`. Commit: `feat: controller overview and moveWindow`.

### Task 2: Páginas tab

**Files:** Create `Sources/UltrawrailApp/PagesTab.swift`; Modify `SettingsModel.swift` (published `overview: [ZoneOverview]`, `windowChips: [WindowID: (name: String, icon: NSImage?)]` or a lookup closure, `moveWindow` closure wired to the controller), `SettingsView.swift` (tab "Páginas", systemImage "rectangle.stack" between Diseño and Plantillas), `AppDelegate.swift` (wire: refresh overview on `controller.onChange` and when the settings window becomes key; `model.moveWindowHandler = { controller.moveWindow($0, toZone: $1, page: $2) }`), `docs/smoke-test.md`.

Requirements:
- Layout: one section per zone ("Zona N", only shown as a heading when `zoneCount > 1`), a horizontal row of page cards ("Página N", current page highlighted with an accent border, focused zone's heading marked), each card listing window chips (app icon 16 pt + app name, ellipsized). A trailing dashed "＋ Nueva página" drop target per zone (hidden at 9 pages).
- Drag and drop with SwiftUI `.draggable`/`.dropDestination` (macOS 13 compatible: use `Transferable` with a `Codable` payload of the window id raw value, or `NSItemProvider`); dropping on a page card or on "＋ Nueva página" calls `moveWindow(id, zone, page)`; the overview refreshes right after.
- Chips resolve app name/icon through `controller.describe(id)` + `NSRunningApplication(processIdentifier:)?.icon` (same as `TemplatePanelController`); fallback "Ventana".
- Empty state when there are no managed windows: "No hay ventanas gestionadas."
- Smoke test section "Pestaña Páginas": (1) muestra cada zona y página con sus ventanas; (2) arrastrar una ventana a otra página la mueve y la aparca si no es la actual; (3) soltar en "Nueva página" crea la página; (4) la página actual aparece resaltada y se actualiza al cambiar con Win+Alt+←/→; (5) con varias zonas aparece una sección por zona.
Run full `swift test`, `swift build`. Commit: `feat: pages tab in settings`.

### Task 3: Page switcher in the templates panel

**Files:** Modify `Sources/UltrawrailApp/TemplatePanelController.swift`, `Sources/UltrawrailApp/TemplateBoardView.swift` only if needed, `docs/smoke-test.md`.

Requirements: in the Ctrl+Alt+T panel add a header row with "◀", the label "Zona Z · Página N de M" (zone part only when `zoneCount > 1`) and "▶". The arrows send `.previousPage` / `.nextPage` to the controller (public `handle(_:)`), then rebuild the board from the (new) current page's `managedWindows` while keeping the panel open and the chosen template selected. Disable ◀ on page 1 and ▶ when there is no next page and the current page is empty. Applying a template still acts on the current page only. Keep the panel size sensible (grow height by the header row, not by squeezing the cards).
Smoke test lines under the existing "Panel de plantillas" section or a new "Selector de página en el panel": (1) las flechas cambian de página sin cerrar el panel; (2) el tablero muestra las ventanas de la página elegida; (3) Aplicar solo reorganiza esa página.
Run full `swift test`, `swift build`. Commit: `feat: page switcher in templates panel`.
