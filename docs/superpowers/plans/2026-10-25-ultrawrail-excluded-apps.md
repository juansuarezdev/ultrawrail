# Ultrawrail Excluded Apps Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task.

**Goal:** Let the user pick apps whose windows Ultrawrail never manages (they float untouched), from a new "Apps" tab in Settings.

**Architecture:** Exclusion is by bundle identifier. `WindowDescription` gains `bundleID: String?`; `Controller` holds `excludedApps: Set<String>` and treats a window of an excluded app like a non-manageable window (not adopted, never laid out, never parked). Changing the set live forgets windows of newly excluded apps (left where they are) and adopts the windows of newly allowed apps. The Apps tab edits the persisted list.

## Global Constraints

- Default: empty set; behavior identical to today. Every existing test stays green unmodified.
- `WindowDescription.init(appName:pid:)` keeps working (new param `bundleID: String? = nil`, appended).
- UserDefaults key `excludedApps` (array of bundle id strings, deduplicated, sorted).
- Spanish UI copy. Commits plain, no AI attribution. `swift build` 0 warnings. Filtered tests: `swift test --filter UltrawrailCoreTests.ClassName`.

---

### Task 1: Exclusion in Controller and AX service

**Files:** Modify `Sources/UltrawrailCore/Protocols.swift`, `Sources/UltrawrailCore/Controller.swift`, `Sources/UltrawrailApp/AXWindowService.swift` (fill `bundleID` in `describe` from `NSRunningApplication(processIdentifier:)?.bundleIdentifier`); Test `Tests/UltrawrailCoreTests/ControllerExcludedAppsTests.swift` (fake services as in `ControllerPagesTests.swift`; extend the fake `describe` to return a bundle id per window).

**Produces:**
```swift
public struct WindowDescription { ... public let bundleID: String?; init(appName:pid:bundleID: String? = nil) }
// Controller
public var excludedApps: Set<String> { get set }   // didSet: apply exclusion changes live, relayout(force: true)
```
Behavior:
- `adopt` (all paths: `start`, `.opened`, pending/manual adoption, rescan) skips a window whose `describe(id)?.bundleID` is in `excludedApps`. In manual placement mode an excluded window never becomes pending.
- Setting `excludedApps`: every managed window of a newly excluded app is removed from all zones/pages via the existing forget path (without touching its frame); every window from `windows.allWindows()` of a newly allowed app that is manageable and not yet managed is adopted into the focused zone's current page.
- `describe` returning nil or bundleID nil means not excluded.

Tests (first): excluded app's opened window is not managed; non-excluded still is; setting excludedApps forgets existing windows of that app and keeps others; removing the app from the set adopts its manageable windows again; manual mode: excluded window never pending; unchanged behavior with empty set.
Run filtered, full `swift test`, `swift build`. Commit: `feat: excluded apps in controller`.

### Task 2: Persistence, Apps tab, docs

**Files:** Create `Sources/UltrawrailApp/ExcludedAppsStore.swift`, `Sources/UltrawrailApp/AppsTab.swift`; Modify `SettingsModel.swift`, `SettingsView.swift`, `AppDelegate.swift`, `docs/smoke-test.md`.

Requirements:
- Store: read/write `excludedApps` (sorted unique strings) like the other `*Store` structs. `SettingsModel.excludedApps: [String]` published, committed through the existing commit path (only this store written, like `commitTemplates`); AppDelegate pushes it to `controller.excludedApps` on start and on change.
- Apps tab (4th/5th tab "Apps"): list of excluded apps showing icon + name + bundle id (resolve via `NSWorkspace.shared.urlForApplication(withBundleIdentifier:)`; fallback to the bundle id text), a "−" button per row; buttons "Añadir app…" (NSOpenPanel limited to `.app`, reads `Bundle(url:)?.bundleIdentifier`) and a menu "Añadir app en ejecución" listing `NSWorkspace.shared.runningApplications` with `activationPolicy == .regular`, excluding already listed ones and Ultrawrail itself. Empty state text: "Ninguna app excluida. Las ventanas de las apps de esta lista no se tocan."
- Default suggestions are NOT added automatically.
- Smoke test section "Apps excluidas": (1) añadir una app en ejecución la saca de la tira y sus ventanas dejan de moverse; (2) quitarla de la lista la vuelve a incorporar; (3) las ventanas nuevas de una app excluida no entran; (4) persiste al reiniciar.
Run full `swift test`, `swift build`. Commit: `feat: apps tab to exclude apps from the strip`.
