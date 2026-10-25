# Ultrawrail Pages Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task.

**Goal:** Let the user keep several strips ("pages") on the same display and switch between them with Win+Alt+Left/Right; windows of inactive pages are parked off-screen.

**Architecture:** `Controller` holds `pages: [Workspace]` and `currentPage`; the existing `workspace` property becomes the current page so all current code and tests keep working. Windows of other pages are written to a parked rect at the viewport's right edge (1 px inside, the same convention columns already use). Commands are handled in `Controller` before `Workspace.perform`, like `showTemplates`.

**Tech Stack:** Swift 6 package, XCTest, Carbon hotkeys. Scope cut for this phase: no Páginas tab in Settings and no page selector in the templates panel (later phases).

## Global Constraints

- Notation in UI text and docs: Windows names (Win = ⌘, Alt = ⌥, Ctrl = ⌃). Hotkey display names in code keep the symbol style used by `CarbonHotkeyService.bindings` ("⌘⌥←").
- Max pages: 9. A single page behaves exactly as today; every existing test stays green unmodified.
- Controller public API kept: `workspace` (read), `managedWindows` = windows of the current page only.
- Spanish UI copy. Commits plain, no AI attribution. `swift build` 0 warnings. Filtered tests: `swift test --filter UltrawrailCoreTests.ClassName`.

---

### Task 1: Pages in Controller

**Files:** Modify `Sources/LayoutEngine/Types.swift` (Command), `Sources/UltrawrailCore/Controller.swift`; Test `Tests/UltrawrailCoreTests/ControllerPagesTests.swift` (reuse the fake window/hotkey services used by `ControllerTests.swift`).

**Produces:**
```swift
// Command gains: previousPage, nextPage, movePageLeft... use exactly these cases:
case previousPage, nextPage, moveWindowToPreviousPage, moveWindowToNextPage
// Controller:
public private(set) var pages: [Workspace]
public private(set) var currentPage: Int
public var workspace: Workspace { pages[currentPage] }   // read-only outside
public static let maxPages = 9
// WorkspaceSnapshot gains: page: Int = 0, pageCount: Int = 1 (appended init params with defaults)
```

Behavior:
- `.nextPage`: if `currentPage + 1 < pages.count` go there; else if current page has windows and `pages.count < maxPages` append an empty `Workspace` (copy `newColumnWidth` from the current one) and go there; else no-op. `.previousPage`: go to `currentPage - 1` if > 0, else no-op. After switching, trailing empty pages other than the current one are removed (never remove below 1 page).
- `.moveWindowToNextPage` / `.moveWindowToPreviousPage`: take the focused window, remove it from the current page, add it to the target page (creating a trailing page under the same rule as `.nextPage`; no-op if target does not exist for previous, or at max pages), then switch to the target page and focus the window.
- Switching page: all windows of non-current pages are written (never animated) to a parked rect: `CGRect(x: viewport.maxX - 1, y: viewport.minY, width: <their last size or 200>, height: <their last height or viewport.height>)`; current-page windows follow normal layout with `force` semantics (clear `lastApplied` for everything). Cancel animator first.
- New windows (`opened`) join the current page. `closed` removes the window from whichever page holds it. `focused(id)` for a window on another page switches to that page, then focuses normally. `adoptPending`/manual placement adopt into the current page.
- `managedWindows` returns current page windows only. `applyTemplate` applies to the current page only.
- `emitChange` snapshot includes `page` and `pageCount`.

Tests (write first, see them fail): next creates page 2 only when current has windows; next on empty last page is a no-op; previous at page 0 no-op; switching parks the other page's windows at `viewport.maxX - 1` and un-parks the current page's; moveWindowToNextPage moves the focused window and follows it; closed window on inactive page is removed; focused event on an inactive page's window switches page; trailing empty pages are trimmed; maxPages cap; single-page controller unchanged (existing suites).

Run filtered, then full `swift test`, `swift build`. Commit: `feat: pages in controller`.

### Task 2: Hotkeys, legend, menu, docs

**Files:** Modify `Sources/UltrawrailApp/CarbonHotkeyService.swift`, `Sources/UltrawrailCore/ShortcutLegend.swift` (+ its test), `Sources/UltrawrailApp/AppDelegate.swift` (menu), `docs/smoke-test.md`.

Requirements:
- Bindings: Win+Alt+Left → `.previousPage`, Win+Alt+Right → `.nextPage` (modifiers `cmdKey | optionKey`), Win+Alt+Shift+Left/Right → `.moveWindowToPreviousPage/NextPage` (`cmdKey | optionKey | shiftKey`). Extend `Binding` with an optional modifier override; names "⌘⌥←", "⌘⌥→", "⌘⌥⇧←", "⌘⌥⇧→". Registration failures already surface via `failedHotkeys`.
- `ShortcutLegend`: add entries "Página anterior / siguiente" and "Mover ventana a la página anterior / siguiente" in both keyboard styles (Windows style: Win+Alt+←/→ and Win+Alt+Shift+←/→; Mac style: ⌘⌥←/→ and ⌘⌥⇧←/→); update `ShortcutLegendTests`.
- Status menu: a disabled line "Página N de M" shown only when M > 1, rebuilt from the snapshot (`page`, `pageCount`).
- Smoke test section "Páginas" before "Limitaciones conocidas": (1) Win+Alt+→ en una página con ventanas crea la página 2 y esconde las ventanas de la 1; (2) Win+Alt+← vuelve y recoloca las ventanas; (3) Win+Alt+Shift+→ lleva la ventana con foco a la página siguiente y la sigue; (4) las ventanas nuevas entran en la página activa; (5) cerrar la última ventana de una página intermedia no rompe el cambio; (6) el menú muestra "Página N de M"; (7) Brave/Chrome usan Cmd+Option+←/→ para cambiar de pestaña: si el atajo no registra o choca, se indica en el menú como cualquier atajo fallido.
Run full `swift test`, `swift build`. Commit: `feat: page hotkeys, legend and menu indicator`.
