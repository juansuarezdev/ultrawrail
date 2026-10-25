# Ultrawrail Ultrawide Pack Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task.

**Goal:** Make the strip behave well on ultrawide monitors: keep the focused column centered, cap column width in pixels, and center the whole group when it is narrower than the screen.

**Architecture:** Three new `LayoutConfig` fields (all default to current behavior) consumed by the pure `Layout` functions; app side adds persistence in `LayoutSettingsStore`, fields in `SettingsModel`, and controls in the Diseño tab. Ultrawide templates already exist (template editor, Task 1).

## Global Constraints

- Defaults must reproduce today's behavior exactly: `focusMode = .minimal`, `maxColumnWidth = 0` (off), `centerStrip = false`. Every existing test stays green unmodified.
- `LayoutConfig` init keeps the existing `init(gap:outerGap:)` call form working (new params have defaults, appended after `outerGap`).
- Pure logic lives in `Sources/LayoutEngine/Layout.swift` with XCTest tests in `Tests/LayoutEngineTests/LayoutTests.swift` (or a new `UltrawideLayoutTests.swift`).
- UserDefaults keys: `focusMode` ("minimal"|"centered"), `maxColumnWidth` (Double px, 0 = off, clamp 0...5000), `centerStrip` (Bool).
- UI copy in Spanish. Commits plain, no AI attribution. `swift build` 0 warnings. Filtered tests: `swift test --filter LayoutEngineTests.ClassName`.

---

### Task 1: Layout engine

**Files:** Modify `Sources/LayoutEngine/Types.swift`, `Sources/LayoutEngine/Layout.swift`; Test `Tests/LayoutEngineTests/UltrawideLayoutTests.swift`.

**Produces:**
```swift
public enum FocusMode: String, Sendable { case minimal, centered }
// LayoutConfig gains: focusMode: FocusMode = .minimal, maxColumnWidth: Double = 0, centerStrip: Bool = false
// init(gap: Double = 8, outerGap: Double = 8, focusMode: FocusMode = .minimal, maxColumnWidth: Double = 0, centerStrip: Bool = false)
```

Behavior:
- `columnWidth`: after the current formula, if `config.maxColumnWidth > 0` return `min(value, config.maxColumnWidth)`.
- `reveal`: when `focusMode == .centered`, call `center` then clamp the scroll to `0...max(0, stripWidth - viewport.width)`; when `.minimal` keep current code unchanged.
- `stripRects`: when `config.centerStrip` and `stripWidth < viewport.width`, add `(viewport.width - stripWidth) / 2` to every x (frames/preview inherit it since they derive from `stripRects`). `scrollOffset` is still subtracted in `frames`, and is 0 in that case after `removeOverscroll`.

Tests (write first, see them fail, then implement):
1. maxColumnWidth 800 with viewport 3440 wide, gap/outer 8, a 0.5 column: width = 800; with 0.25 column (≈ 849) also 800; maxColumnWidth 0 keeps 1708... compute with the formula, do not hard-code unless verified.
2. Narrow column below the cap is unchanged (cap 5000).
3. centered mode: 5 columns of 0.25 on 1000pt viewport, focus column 2 → its center equals viewport center (scrollOffset such that left + width/2 - scroll == 500) ; focus column 0 → scrollOffset 0 (clamped); focus last → scrollOffset == stripWidth - viewport.width.
4. minimal mode regression: same setup yields same scrollOffset as before the change (use values captured from a LayoutConfig() default run).
5. centerStrip: two 0.25 columns on 1000pt viewport, outer 8, gap 8 → group x range symmetric: leftmost.minX - viewport.minX == viewport.maxX - rightmost.maxX (within 0.5). With `centerStrip = false` leftmost.minX == outerGap.
6. centerStrip with strip wider than viewport behaves as without it.

Run `swift test --filter LayoutEngineTests.UltrawideLayoutTests`, then full `swift test`. Commit: `feat: ultrawide layout options (centered focus, max width, centered group)`.

### Task 2: Settings, persistence, docs

**Files:** Modify `Sources/UltrawrailApp/LayoutSettingsStore.swift`, `SettingsModel.swift`, `SettingsView.swift` (Diseño tab), `AppDelegate.swift` if the config mapping lives there; `docs/smoke-test.md`.

Requirements:
- `LayoutSettings` gains `focusMode: FocusMode = .minimal`, `maxColumnWidth: Double = 0`, `centerStrip: Bool = false`; store reads/writes the keys from Global Constraints with the clamp.
- `SettingsModel` gets `@Published focusMode`, `maxColumnWidth`, `centerStrip` with `didSet { commit() }` (mirror the existing `gap` pattern: slider uses a local draft committed on end of editing); `layoutConfig` includes them; "Restaurar valores" resets them.
- Diseño tab: Picker "Seguimiento del foco" (Mínimo / Centrado), Toggle "Centrar el grupo si cabe en pantalla", Stepper or slider "Ancho máximo de columna: N px" (0 = sin límite, step 100, 0...5000; label shows "sin límite" at 0). A short caption under the section: "Pensado para monitores ultrawide."
- Changing any of them relayouts live (the existing `config` didSet path).
- Smoke test section "Ultrawide" in `docs/smoke-test.md` before "Limitaciones conocidas": (1) Centrado mantiene la columna con foco en el centro salvo en los extremos; (2) Ancho máximo recorta columnas a N px; (3) Centrar el grupo coloca 2 columnas de 25 % en el centro de la pantalla; (4) Restaurar valores lo desactiva todo; (5) persisten al reiniciar.
- Add a `SettingsModel`/store test only if an existing test target already covers the app layer; otherwise rely on Task 1 tests.

Run full `swift test`, `swift build`. Commit: `feat: ultrawide settings in Diseño tab`.
