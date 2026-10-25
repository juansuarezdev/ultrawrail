# Panerail MVP Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Gestor de ventanas de scroll horizontal para macOS en Swift nativo: columnas de ventanas sobre una tira que se desplaza con el foco, controlada por atajos globales.

**Architecture:** `LayoutEngine` es una librería pura (modelo `Workspace` y cálculo de rects). `PanerailCore` contiene los protocolos `WindowService`/`HotkeyService` y el `Controller` que los une, testeable con dobles. `PanerailApp` es el ejecutable con las implementaciones reales (Accessibility, Carbon hotkeys, barra de menús).

**Tech Stack:** Swift 6.4 toolchain, SwiftPM, XCTest, AppKit, ApplicationServices (AXUIElement), Carbon (RegisterEventHotKey), ServiceManagement.

## Global Constraints

- Nombre del proyecto `Panerail`, bundle id `dev.panerail.app`. No usar nombres de otros productos en código ni textos.
- macOS 13+ (`.macOS(.v13)`), Apple silicon.
- Solo permiso de Accessibility. Los atajos usan Carbon `RegisterEventHotKey` (no requiere permisos).
- Movimiento instantáneo: sin animación ni `Animator`.
- Las ventanas fuera de la vista se aparcan dejando 1 px visible en el borde del área útil.
- MVP gestiona solo la pantalla principal (`NSScreen.screens[0]`). Sin Spaces independientes, sin columnas fijadas, sin restauración de sesión.
- Anchos preestablecidos: 0.25, 0.33, 0.5, 0.66, 0.75; ancho por defecto 0.5; ancho completo 1.0.
- Huecos por defecto: `gap` 8, `outerGap` 8.
- Una escritura AX por ventana y por cambio (se compara con el último rect aplicado).
- Un solo hilo: todo el estado vive en `@MainActor`.
- Modo de lenguaje Swift: `LayoutEngine` y `PanerailCore` en Swift 6; `PanerailApp` y `PanerailCoreTests` en modo Swift 5 (callbacks C de AX/Carbon).
- Commits en inglés, estilo `feat:`/`test:`/`docs:`/`chore:`. Sin trailers de autoría ni mención a IA.

## Estructura de archivos

```
Package.swift
.gitignore
Sources/
  LayoutEngine/
    Types.swift            WindowID, LayoutConfig, Command, WidthPreset, Column
    Workspace.swift        modelo y operaciones puras (add/remove/focus/apply)
    Workspace+Perform.swift  apply + reveal/center en un paso
    Layout.swift           scroll (reveal/center) y cálculo de rects
  PanerailCore/
    Protocols.swift        WindowInfo, WindowEvent, WindowService, HotkeyService
    Controller.swift       une servicios y modelo
  PanerailApp/
    main.swift             punto de entrada
    AppDelegate.swift      barra de menús, permisos, login item
    AXWindowService.swift  Accessibility
    CarbonHotkeyService.swift
Tests/
  LayoutEngineTests/WorkspaceTests.swift, LayoutTests.swift
  PanerailCoreTests/ControllerTests.swift
Resources/Info.plist
scripts/bundle.sh
docs/smoke-test.md
```

---

### Task 1: Paquete y modelo base del Workspace

**Files:**
- Create: `Package.swift`, `.gitignore`
- Create: `Sources/LayoutEngine/Types.swift`, `Sources/LayoutEngine/Workspace.swift`
- Test: `Tests/LayoutEngineTests/WorkspaceTests.swift`

**Interfaces:**
- Produces: `WindowID(Int)` (también literal entero), `LayoutConfig(gap:outerGap:)`, `Command`, `WidthPreset.all/defaultWidth`, `Column(windows:width:restoreWidth:)`, `Workspace` con `columns`, `focusedColumn`, `focusedRow`, `scrollOffset`, `focusedWindow`, `allWindows`, `contains(_:)`, `addWindow(_:)`, `removeWindow(_:)`, `focus(window:)`.

- [ ] **Step 1: Crear el paquete**

`Package.swift`:

```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Panerail",
    platforms: [.macOS(.v13)],
    targets: [
        .target(name: "LayoutEngine"),
        .testTarget(name: "LayoutEngineTests", dependencies: ["LayoutEngine"]),
    ]
)
```

`.gitignore`:

```
.build/
build/
.DS_Store
*.xcodeproj
```

- [ ] **Step 2: Escribir los tests que fallan**

`Tests/LayoutEngineTests/WorkspaceTests.swift`:

```swift
import XCTest
@testable import LayoutEngine

final class WorkspaceTests: XCTestCase {
    func makeWorkspace(_ count: Int) -> Workspace {
        var ws = Workspace()
        for i in 1...count { ws.addWindow(WindowID(i)) }
        return ws
    }

    func testAddToEmptyCreatesFocusedColumnWithDefaultWidth() {
        let ws = makeWorkspace(1)
        XCTAssertEqual(ws.columns.count, 1)
        XCTAssertEqual(ws.focusedWindow, 1)
        XCTAssertEqual(ws.columns[0].width, 0.5)
    }

    func testAddAppendsRightAndFocusesNewWindow() {
        let ws = makeWorkspace(3)
        XCTAssertEqual(ws.allWindows, [1, 2, 3])
        XCTAssertEqual(ws.focusedWindow, 3)
    }

    func testAddInsertsRightOfFocusedColumn() {
        var ws = makeWorkspace(3)
        ws.focus(window: 2)
        ws.addWindow(4)
        XCTAssertEqual(ws.allWindows, [1, 2, 4, 3])
        XCTAssertEqual(ws.focusedWindow, 4)
    }

    func testAddIgnoresDuplicates() {
        var ws = makeWorkspace(2)
        ws.addWindow(1)
        XCTAssertEqual(ws.allWindows, [1, 2])
    }

    func testRemoveFocusedLastClampsFocusToPrevious() {
        var ws = makeWorkspace(3)
        ws.removeWindow(3)
        XCTAssertEqual(ws.focusedWindow, 2)
    }

    func testRemoveFocusedMiddleFocusesColumnOnTheRight() {
        var ws = makeWorkspace(3)
        ws.focus(window: 2)
        ws.removeWindow(2)
        XCTAssertEqual(ws.allWindows, [1, 3])
        XCTAssertEqual(ws.focusedWindow, 3)
    }

    func testRemoveColumnLeftOfFocusKeepsFocusedWindow() {
        var ws = makeWorkspace(3)
        ws.removeWindow(1)
        XCTAssertEqual(ws.focusedWindow, 3)
    }

    func testRemoveLastWindowResetsWorkspace() {
        var ws = makeWorkspace(1)
        ws.scrollOffset = 42
        ws.removeWindow(1)
        XCTAssertNil(ws.focusedWindow)
        XCTAssertEqual(ws.scrollOffset, 0)
        XCTAssertTrue(ws.columns.isEmpty)
    }

    func testRemoveUnknownWindowIsNoOp() {
        var ws = makeWorkspace(2)
        ws.removeWindow(99)
        XCTAssertEqual(ws.allWindows, [1, 2])
    }
}
```

- [ ] **Step 3: Ejecutar y ver que falla**

Run: `swift test --filter WorkspaceTests`
Expected: error de compilación `cannot find 'Workspace' in scope`.

- [ ] **Step 4: Implementar**

`Sources/LayoutEngine/Types.swift`:

```swift
public struct WindowID: Hashable, Sendable, ExpressibleByIntegerLiteral {
    public let rawValue: Int
    public init(_ rawValue: Int) { self.rawValue = rawValue }
    public init(integerLiteral value: Int) { self.rawValue = value }
}

public struct LayoutConfig: Equatable, Sendable {
    public var gap: Double
    public var outerGap: Double
    public init(gap: Double = 8, outerGap: Double = 8) {
        self.gap = gap
        self.outerGap = outerGap
    }
}

public enum Command: Equatable, Sendable {
    case focusLeft, focusRight, focusUp, focusDown
    case cycleWidth, toggleFullWidth, centerColumn
    case stackLeft, unstack
}

public enum WidthPreset {
    public static let all: [Double] = [0.25, 0.33, 0.5, 0.66, 0.75]
    public static let defaultWidth: Double = 0.5
}

public struct Column: Equatable, Sendable {
    public var windows: [WindowID]
    public var width: Double
    public var restoreWidth: Double?

    public init(windows: [WindowID], width: Double = WidthPreset.defaultWidth, restoreWidth: Double? = nil) {
        self.windows = windows
        self.width = width
        self.restoreWidth = restoreWidth
    }
}
```

`Sources/LayoutEngine/Workspace.swift`:

```swift
/// Invariant: every column has at least one window; focusedColumn/focusedRow
/// always point at an existing window while the workspace is non-empty.
public struct Workspace: Equatable, Sendable {
    public private(set) var columns: [Column] = []
    public private(set) var focusedColumn = 0
    public private(set) var focusedRow = 0
    public var scrollOffset: Double = 0

    public init() {}

    public var focusedWindow: WindowID? {
        guard columns.indices.contains(focusedColumn) else { return nil }
        return columns[focusedColumn].windows[focusedRow]
    }

    public var allWindows: [WindowID] { columns.flatMap(\.windows) }

    public func contains(_ id: WindowID) -> Bool { allWindows.contains(id) }

    public mutating func addWindow(_ id: WindowID) {
        guard !contains(id) else { return }
        let index = columns.isEmpty ? 0 : focusedColumn + 1
        columns.insert(Column(windows: [id]), at: index)
        focusedColumn = index
        focusedRow = 0
    }

    public mutating func removeWindow(_ id: WindowID) {
        guard let c = columns.firstIndex(where: { $0.windows.contains(id) }),
              let r = columns[c].windows.firstIndex(of: id) else { return }
        columns[c].windows.remove(at: r)
        if columns[c].windows.isEmpty {
            columns.remove(at: c)
            if c < focusedColumn { focusedColumn -= 1 }
        } else if c == focusedColumn, r < focusedRow {
            focusedRow -= 1
        }
        if columns.isEmpty {
            focusedColumn = 0
            focusedRow = 0
            scrollOffset = 0
            return
        }
        focusedColumn = min(focusedColumn, columns.count - 1)
        focusedRow = min(focusedRow, columns[focusedColumn].windows.count - 1)
    }

    public mutating func focus(window id: WindowID) {
        guard let c = columns.firstIndex(where: { $0.windows.contains(id) }),
              let r = columns[c].windows.firstIndex(of: id) else { return }
        focusedColumn = c
        focusedRow = r
    }
}
```

- [ ] **Step 5: Ejecutar y ver que pasa**

Run: `swift test --filter WorkspaceTests`
Expected: `Executed 9 tests, with 0 failures`.

- [ ] **Step 6: Commit**

```bash
git add Package.swift .gitignore Sources Tests
git commit -m "feat: add layout engine package with workspace model"
```

---

### Task 2: Comandos de foco horizontal y anchos

**Files:**
- Modify: `Sources/LayoutEngine/Workspace.swift` (añadir `apply` al final del struct)
- Test: `Tests/LayoutEngineTests/WorkspaceTests.swift` (añadir tests dentro de la clase)

**Interfaces:**
- Consumes: Task 1 (`Workspace`, `Column`, `Command`, `WidthPreset`).
- Produces: `Workspace.apply(_ command: Command)` (mutating, público). Esta tarea implementa `focusLeft`, `focusRight`, `cycleWidth`, `toggleFullWidth`.

- [ ] **Step 1: Añadir los tests que fallan**

Dentro de `WorkspaceTests`:

```swift
    func testFocusLeftAndRightClampAtEdges() {
        var ws = makeWorkspace(3)
        ws.apply(.focusRight)
        XCTAssertEqual(ws.focusedWindow, 3)
        ws.apply(.focusLeft)
        ws.apply(.focusLeft)
        XCTAssertEqual(ws.focusedWindow, 1)
        ws.apply(.focusLeft)
        XCTAssertEqual(ws.focusedWindow, 1)
    }

    func testCycleWidthWalksPresetsAndWraps() {
        var ws = makeWorkspace(1)
        var seen: [Double] = []
        for _ in 0..<5 {
            ws.apply(.cycleWidth)
            seen.append(ws.columns[0].width)
        }
        XCTAssertEqual(seen, [0.66, 0.75, 0.25, 0.33, 0.5])
    }

    func testToggleFullWidthRestoresPreviousWidth() {
        var ws = makeWorkspace(1)
        ws.apply(.cycleWidth)
        ws.apply(.toggleFullWidth)
        XCTAssertEqual(ws.columns[0].width, 1.0)
        ws.apply(.toggleFullWidth)
        XCTAssertEqual(ws.columns[0].width, 0.66)
    }

    func testApplyOnEmptyWorkspaceIsNoOp() {
        var ws = Workspace()
        ws.apply(.focusRight)
        ws.apply(.cycleWidth)
        XCTAssertTrue(ws.columns.isEmpty)
    }
```

- [ ] **Step 2: Ejecutar y ver que falla**

Run: `swift test --filter WorkspaceTests`
Expected: error de compilación `value of type 'Workspace' has no member 'apply'`.

- [ ] **Step 3: Implementar**

Añadir dentro de `Workspace` en `Workspace.swift`, antes del `}` final:

```swift
    /// Pure model mutation. `centerColumn` is a no-op here: centering needs the
    /// viewport and is handled by `perform(_:viewport:config:)`.
    public mutating func apply(_ command: Command) {
        guard !columns.isEmpty else { return }
        switch command {
        case .focusLeft:
            focusedColumn = max(0, focusedColumn - 1)
            focusedRow = min(focusedRow, columns[focusedColumn].windows.count - 1)
        case .focusRight:
            focusedColumn = min(columns.count - 1, focusedColumn + 1)
            focusedRow = min(focusedRow, columns[focusedColumn].windows.count - 1)
        case .cycleWidth:
            let current = columns[focusedColumn].width
            columns[focusedColumn].width = WidthPreset.all.first { $0 > current + 0.001 } ?? WidthPreset.all[0]
            columns[focusedColumn].restoreWidth = nil
        case .toggleFullWidth:
            if columns[focusedColumn].width >= 1.0 {
                columns[focusedColumn].width = columns[focusedColumn].restoreWidth ?? WidthPreset.defaultWidth
                columns[focusedColumn].restoreWidth = nil
            } else {
                columns[focusedColumn].restoreWidth = columns[focusedColumn].width
                columns[focusedColumn].width = 1.0
            }
        case .focusUp, .focusDown, .centerColumn, .stackLeft, .unstack:
            break
        }
    }
```

- [ ] **Step 4: Ejecutar y ver que pasa**

Run: `swift test --filter WorkspaceTests`
Expected: `Executed 13 tests, with 0 failures`.

- [ ] **Step 5: Commit**

```bash
git add Sources Tests
git commit -m "feat: add horizontal focus and width commands"
```

---

### Task 3: Pilas (stack, unstack, foco vertical)

**Files:**
- Modify: `Sources/LayoutEngine/Workspace.swift` (sustituir el `case` vacío de `apply`, añadir dos métodos privados)
- Test: `Tests/LayoutEngineTests/WorkspaceTests.swift`

**Interfaces:**
- Consumes: Task 2 `apply`.
- Produces: comportamiento de `.focusUp`, `.focusDown`, `.stackLeft`, `.unstack` en `apply`.

- [ ] **Step 1: Añadir los tests que fallan**

Dentro de `WorkspaceTests`:

```swift
    func testStackLeftMovesFocusedWindowIntoLeftColumn() {
        var ws = makeWorkspace(3)
        ws.apply(.stackLeft)
        XCTAssertEqual(ws.columns.map(\.windows), [[1], [2, 3]])
        XCTAssertEqual(ws.focusedWindow, 3)
        XCTAssertEqual(ws.focusedRow, 1)
    }

    func testStackLeftRemovingEmptiedColumnKeepsFocus() {
        var ws = makeWorkspace(2)
        ws.apply(.stackLeft)
        XCTAssertEqual(ws.columns.map(\.windows), [[1, 2]])
        XCTAssertEqual(ws.focusedColumn, 0)
        XCTAssertEqual(ws.focusedWindow, 2)
    }

    func testStackLeftOnFirstColumnIsNoOp() {
        var ws = makeWorkspace(2)
        ws.apply(.focusLeft)
        ws.apply(.stackLeft)
        XCTAssertEqual(ws.columns.map(\.windows), [[1], [2]])
    }

    func testUnstackExpelsFocusedWindowToNewColumnOnTheRight() {
        var ws = makeWorkspace(3)
        ws.apply(.stackLeft)
        ws.apply(.unstack)
        XCTAssertEqual(ws.columns.map(\.windows), [[1], [2], [3]])
        XCTAssertEqual(ws.focusedWindow, 3)
        XCTAssertEqual(ws.focusedColumn, 2)
    }

    func testUnstackSingleWindowIsNoOp() {
        var ws = makeWorkspace(2)
        ws.apply(.unstack)
        XCTAssertEqual(ws.columns.map(\.windows), [[1], [2]])
    }

    func testFocusUpAndDownMoveWithinStack() {
        var ws = makeWorkspace(2)
        ws.apply(.stackLeft)
        ws.apply(.focusUp)
        XCTAssertEqual(ws.focusedWindow, 1)
        ws.apply(.focusUp)
        XCTAssertEqual(ws.focusedWindow, 1)
        ws.apply(.focusDown)
        XCTAssertEqual(ws.focusedWindow, 2)
        ws.apply(.focusDown)
        XCTAssertEqual(ws.focusedWindow, 2)
    }
```

- [ ] **Step 2: Ejecutar y ver que falla**

Run: `swift test --filter WorkspaceTests`
Expected: FAIL en los 6 tests nuevos (los comandos aún no hacen nada).

- [ ] **Step 3: Implementar**

En `apply`, sustituir la línea `case .focusUp, .focusDown, .centerColumn, .stackLeft, .unstack: break` por:

```swift
        case .focusUp:
            focusedRow = max(0, focusedRow - 1)
        case .focusDown:
            focusedRow = min(columns[focusedColumn].windows.count - 1, focusedRow + 1)
        case .stackLeft:
            stackLeft()
        case .unstack:
            unstack()
        case .centerColumn:
            break
```

Y añadir al final del struct:

```swift
    private mutating func stackLeft() {
        guard focusedColumn > 0, let id = focusedWindow else { return }
        columns[focusedColumn].windows.remove(at: focusedRow)
        if columns[focusedColumn].windows.isEmpty { columns.remove(at: focusedColumn) }
        focusedColumn -= 1
        columns[focusedColumn].windows.append(id)
        focusedRow = columns[focusedColumn].windows.count - 1
    }

    private mutating func unstack() {
        guard columns[focusedColumn].windows.count > 1, let id = focusedWindow else { return }
        columns[focusedColumn].windows.remove(at: focusedRow)
        columns.insert(Column(windows: [id]), at: focusedColumn + 1)
        focusedColumn += 1
        focusedRow = 0
    }
```

- [ ] **Step 4: Ejecutar y ver que pasa**

Run: `swift test --filter WorkspaceTests`
Expected: `Executed 19 tests, with 0 failures`.

- [ ] **Step 5: Commit**

```bash
git add Sources Tests
git commit -m "feat: add window stacking and vertical focus"
```

---

### Task 4: Cálculo de layout, scroll y aparcado

**Files:**
- Create: `Sources/LayoutEngine/Layout.swift`, `Sources/LayoutEngine/Workspace+Perform.swift`
- Test: `Tests/LayoutEngineTests/LayoutTests.swift`

**Interfaces:**
- Consumes: Tasks 1-3.
- Produces:
  - `Layout.frames(_ ws: Workspace, viewport: CGRect, config: LayoutConfig) -> [WindowID: CGRect]`
  - `Layout.reveal(_ ws: inout Workspace, viewport: CGRect, config: LayoutConfig)`
  - `Layout.center(_ ws: inout Workspace, viewport: CGRect, config: LayoutConfig)`
  - `Workspace.perform(_ command: Command, viewport: CGRect, config: LayoutConfig)` (mutating)

- [ ] **Step 1: Escribir los tests que fallan**

`Tests/LayoutEngineTests/LayoutTests.swift`:

```swift
import XCTest
import CoreGraphics
@testable import LayoutEngine

final class LayoutTests: XCTestCase {
    let viewport = CGRect(x: 0, y: 0, width: 1000, height: 800)
    let config = LayoutConfig(gap: 10, outerGap: 10)

    func makeWorkspace(_ count: Int) -> Workspace {
        var ws = Workspace()
        for i in 1...count { ws.addWindow(WindowID(i)) }
        return ws
    }

    func testSingleWindowGetsHalfOfUsableWidthMinusOuterGaps() {
        let frames = Layout.frames(makeWorkspace(1), viewport: viewport, config: config)
        XCTAssertEqual(frames[1], CGRect(x: 10, y: 10, width: 490, height: 780))
    }

    func testViewportOriginIsRespected() {
        let shifted = CGRect(x: 100, y: 50, width: 1000, height: 800)
        let frames = Layout.frames(makeWorkspace(1), viewport: shifted, config: config)
        XCTAssertEqual(frames[1], CGRect(x: 110, y: 60, width: 490, height: 780))
    }

    func testRevealScrollsMinimumAmountToTheRight() {
        var ws = makeWorkspace(2)
        Layout.reveal(&ws, viewport: viewport, config: config)
        XCTAssertEqual(ws.scrollOffset, 10)
        let frames = Layout.frames(ws, viewport: viewport, config: config)
        XCTAssertEqual(frames[1], CGRect(x: 0, y: 10, width: 490, height: 780))
        XCTAssertEqual(frames[2], CGRect(x: 500, y: 10, width: 490, height: 780))
    }

    func testWindowsFullyLeftOfViewportAreParkedWithOnePixelVisible() {
        var ws = makeWorkspace(3)
        Layout.reveal(&ws, viewport: viewport, config: config)
        let frames = Layout.frames(ws, viewport: viewport, config: config)
        XCTAssertEqual(frames[1], CGRect(x: -489, y: 10, width: 490, height: 780))
        XCTAssertEqual(frames[2], CGRect(x: 0, y: 10, width: 490, height: 780))
        XCTAssertEqual(frames[3], CGRect(x: 500, y: 10, width: 490, height: 780))
    }

    func testRevealScrollsBackLeftAndParksRightWindows() {
        var ws = makeWorkspace(3)
        Layout.reveal(&ws, viewport: viewport, config: config)
        ws.focus(window: 1)
        Layout.reveal(&ws, viewport: viewport, config: config)
        XCTAssertEqual(ws.scrollOffset, 0)
        let frames = Layout.frames(ws, viewport: viewport, config: config)
        XCTAssertEqual(frames[1], CGRect(x: 10, y: 10, width: 490, height: 780))
        XCTAssertEqual(frames[3], CGRect(x: 999, y: 10, width: 490, height: 780))
    }

    func testStackedWindowsSplitHeightEvenly() {
        var ws = makeWorkspace(2)
        ws.apply(.stackLeft)
        let frames = Layout.frames(ws, viewport: viewport, config: config)
        XCTAssertEqual(frames[1], CGRect(x: 10, y: 10, width: 490, height: 385))
        XCTAssertEqual(frames[2], CGRect(x: 10, y: 405, width: 490, height: 385))
    }

    func testCenterPutsFocusedColumnInTheMiddle() {
        var ws = makeWorkspace(1)
        Layout.center(&ws, viewport: viewport, config: config)
        let frames = Layout.frames(ws, viewport: viewport, config: config)
        XCTAssertEqual(frames[1], CGRect(x: 255, y: 10, width: 490, height: 780))
    }

    func testPerformFocusLeftRevealsTheNewFocus() {
        var ws = makeWorkspace(3)
        ws.perform(.focusLeft, viewport: viewport, config: config)
        XCTAssertEqual(ws.focusedWindow, 2)
        XCTAssertEqual(ws.scrollOffset, 10)
    }

    func testPerformCenterColumnCenters() {
        var ws = makeWorkspace(1)
        ws.perform(.centerColumn, viewport: viewport, config: config)
        XCTAssertEqual(ws.scrollOffset, -245)
    }
}
```

- [ ] **Step 2: Ejecutar y ver que falla**

Run: `swift test --filter LayoutTests`
Expected: error de compilación `cannot find 'Layout' in scope`.

- [ ] **Step 3: Implementar**

`Sources/LayoutEngine/Layout.swift`:

```swift
import CoreGraphics

public enum Layout {
    static func columnWidth(_ column: Column, viewport: CGRect, config: LayoutConfig) -> Double {
        column.width * (viewport.width - 2 * config.outerGap)
    }

    /// X of the column's left edge in strip coordinates (0 = strip origin).
    static func stripX(of index: Int, in ws: Workspace, viewport: CGRect, config: LayoutConfig) -> Double {
        var x = config.outerGap
        for column in ws.columns[..<index] {
            x += columnWidth(column, viewport: viewport, config: config) + config.gap
        }
        return x
    }

    /// Smallest scroll change that makes the focused column fully visible.
    public static func reveal(_ ws: inout Workspace, viewport: CGRect, config: LayoutConfig) {
        guard ws.columns.indices.contains(ws.focusedColumn) else { return }
        let left = stripX(of: ws.focusedColumn, in: ws, viewport: viewport, config: config)
        let right = left + columnWidth(ws.columns[ws.focusedColumn], viewport: viewport, config: config)
        if left - config.outerGap < ws.scrollOffset {
            ws.scrollOffset = left - config.outerGap
        } else if right + config.outerGap > ws.scrollOffset + viewport.width {
            ws.scrollOffset = right + config.outerGap - viewport.width
        }
    }

    public static func center(_ ws: inout Workspace, viewport: CGRect, config: LayoutConfig) {
        guard ws.columns.indices.contains(ws.focusedColumn) else { return }
        let left = stripX(of: ws.focusedColumn, in: ws, viewport: viewport, config: config)
        let width = columnWidth(ws.columns[ws.focusedColumn], viewport: viewport, config: config)
        ws.scrollOffset = left + width / 2 - viewport.width / 2
    }

    /// Rect of every window in screen coordinates. Columns fully outside the
    /// viewport are parked with 1 px still inside it.
    public static func frames(_ ws: Workspace, viewport: CGRect, config: LayoutConfig) -> [WindowID: CGRect] {
        var result: [WindowID: CGRect] = [:]
        for (index, column) in ws.columns.enumerated() {
            let width = columnWidth(column, viewport: viewport, config: config)
            var x = viewport.minX + stripX(of: index, in: ws, viewport: viewport, config: config) - ws.scrollOffset
            if x + width <= viewport.minX {
                x = viewport.minX - width + 1
            } else if x >= viewport.maxX {
                x = viewport.maxX - 1
            }
            let count = Double(column.windows.count)
            let height = max((viewport.height - 2 * config.outerGap - (count - 1) * config.gap) / count, 1)
            for (row, id) in column.windows.enumerated() {
                let y = viewport.minY + config.outerGap + Double(row) * (height + config.gap)
                result[id] = CGRect(x: x, y: y, width: width, height: height)
            }
        }
        return result
    }
}
```

`Sources/LayoutEngine/Workspace+Perform.swift`:

```swift
import CoreGraphics

public extension Workspace {
    /// Applies a command and leaves `scrollOffset` consistent with the new focus.
    mutating func perform(_ command: Command, viewport: CGRect, config: LayoutConfig) {
        apply(command)
        if command == .centerColumn {
            Layout.center(&self, viewport: viewport, config: config)
        } else {
            Layout.reveal(&self, viewport: viewport, config: config)
        }
    }
}
```

- [ ] **Step 4: Ejecutar toda la suite**

Run: `swift test`
Expected: `Executed 28 tests, with 0 failures`.

- [ ] **Step 5: Commit**

```bash
git add Sources Tests
git commit -m "feat: add layout computation with scroll reveal and parking"
```

---

### Task 5: PanerailCore: protocolos y Controller

**Files:**
- Modify: `Package.swift`
- Create: `Sources/PanerailCore/Protocols.swift`, `Sources/PanerailCore/Controller.swift`
- Test: `Tests/PanerailCoreTests/ControllerTests.swift`
- Modify: `docs/superpowers/specs/2026-10-24-panerail-design.md` (árbol de arquitectura)

**Interfaces:**
- Consumes: `LayoutEngine` completo.
- Produces:
  - `struct WindowInfo { let id: WindowID; let isManageable: Bool }`
  - `enum WindowEvent { case opened(WindowInfo), closed(WindowID), focused(WindowID) }`
  - `@MainActor protocol WindowService: AnyObject { var onEvent: ((WindowEvent) -> Void)? { get set }; func start(); func allWindows() -> [WindowInfo]; func usableFrame() -> CGRect; func setFrame(_ rect: CGRect, for id: WindowID) -> Bool; func focus(_ id: WindowID); func isAlive(_ id: WindowID) -> Bool }`
  - `@MainActor protocol HotkeyService: AnyObject { var onCommand: ((Command) -> Void)? { get set }; func register() -> [String] }` (devuelve descripciones de atajos que no se pudieron registrar)
  - `@MainActor final class Controller` con `init(windows:hotkeys:config:)`, `start()`, `handle(_ command:)`, `handle(_ event:)`, `screenChanged()`, `relayout(force:)`, `workspace`, `failedHotkeys`.

- [ ] **Step 1: Actualizar Package.swift**

```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Panerail",
    platforms: [.macOS(.v13)],
    targets: [
        .target(name: "LayoutEngine"),
        .target(name: "PanerailCore", dependencies: ["LayoutEngine"]),
        .testTarget(name: "LayoutEngineTests", dependencies: ["LayoutEngine"]),
        .testTarget(
            name: "PanerailCoreTests",
            dependencies: ["PanerailCore", "LayoutEngine"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
```

- [ ] **Step 2: Escribir los tests que fallan**

`Tests/PanerailCoreTests/ControllerTests.swift`:

```swift
import XCTest
import CoreGraphics
import LayoutEngine
@testable import PanerailCore

@MainActor
final class FakeWindows: WindowService {
    var onEvent: ((WindowEvent) -> Void)?
    var existing: [WindowInfo] = []
    var alive: Set<WindowID> = []
    var failing: Set<WindowID> = []
    var frame = CGRect(x: 0, y: 0, width: 1000, height: 800)
    private(set) var setFrameCalls: [(id: WindowID, rect: CGRect)] = []
    private(set) var focusCalls: [WindowID] = []

    func add(_ id: Int, manageable: Bool = true) {
        existing.append(WindowInfo(id: WindowID(id), isManageable: manageable))
        alive.insert(WindowID(id))
    }

    func start() {}
    func allWindows() -> [WindowInfo] { existing }
    func usableFrame() -> CGRect { frame }
    func setFrame(_ rect: CGRect, for id: WindowID) -> Bool {
        setFrameCalls.append((id, rect))
        return !failing.contains(id)
    }
    func focus(_ id: WindowID) { focusCalls.append(id) }
    func isAlive(_ id: WindowID) -> Bool { alive.contains(id) }
    func lastRect(_ id: Int) -> CGRect? {
        setFrameCalls.last { $0.id == WindowID(id) }?.rect
    }
}

@MainActor
final class FakeHotkeys: HotkeyService {
    var onCommand: ((Command) -> Void)?
    func register() -> [String] { [] }
}

@MainActor
final class ControllerTests: XCTestCase {
    let config = LayoutConfig(gap: 10, outerGap: 10)

    func makeController(_ ids: [Int], unmanageable: [Int] = []) -> (Controller, FakeWindows) {
        let windows = FakeWindows()
        for id in ids { windows.add(id, manageable: !unmanageable.contains(id)) }
        let controller = Controller(windows: windows, hotkeys: FakeHotkeys(), config: config)
        controller.start()
        return (controller, windows)
    }

    func testStartLaysOutExistingWindows() {
        let (_, windows) = makeController([1, 2, 3])
        XCTAssertEqual(windows.lastRect(1), CGRect(x: -489, y: 10, width: 490, height: 780))
        XCTAssertEqual(windows.lastRect(2), CGRect(x: 0, y: 10, width: 490, height: 780))
        XCTAssertEqual(windows.lastRect(3), CGRect(x: 500, y: 10, width: 490, height: 780))
    }

    func testFocusLeftCommandMovesStripAndFocusesWindow() {
        let (controller, windows) = makeController([1, 2, 3])
        controller.handle(.focusLeft)
        XCTAssertEqual(windows.focusCalls.last, 2)
        XCTAssertEqual(windows.lastRect(2), CGRect(x: 10, y: 10, width: 490, height: 780))
    }

    func testUnmanageableWindowsAreIgnored() {
        let (controller, windows) = makeController([1, 2], unmanageable: [2])
        XCTAssertEqual(controller.workspace.allWindows, [1])
        XCTAssertNil(windows.lastRect(2))
    }

    func testUnchangedLayoutIsNotRewritten() {
        let (controller, windows) = makeController([1, 2, 3])
        let before = windows.setFrameCalls.count
        controller.handle(.focused(3))
        XCTAssertEqual(windows.setFrameCalls.count, before)
    }

    func testFocusedEventUpdatesModelWithoutRefocusing() {
        let (controller, windows) = makeController([1, 2, 3])
        controller.handle(.focused(1))
        XCTAssertEqual(controller.workspace.focusedWindow, 1)
        XCTAssertTrue(windows.focusCalls.isEmpty)
    }

    func testOpenedEventAddsWindowRightOfFocusAndFocusesIt() {
        let (controller, windows) = makeController([1, 2, 3])
        controller.handle(.focused(2))
        windows.alive.insert(4)
        controller.handle(.opened(WindowInfo(id: 4, isManageable: true)))
        XCTAssertEqual(controller.workspace.allWindows, [1, 2, 4, 3])
        XCTAssertEqual(controller.workspace.focusedWindow, 4)
    }

    func testClosedEventRemovesWindowAndRelayouts() {
        let (controller, windows) = makeController([1, 2, 3])
        controller.handle(.closed(2))
        XCTAssertEqual(controller.workspace.allWindows, [1, 3])
        XCTAssertEqual(windows.lastRect(1), CGRect(x: 0, y: 10, width: 490, height: 780))
        XCTAssertEqual(windows.lastRect(3), CGRect(x: 500, y: 10, width: 490, height: 780))
    }

    func testDeadWindowIsRemovedOnRelayout() {
        let (controller, windows) = makeController([1, 2, 3])
        windows.alive.remove(2)
        controller.screenChanged()
        XCTAssertEqual(controller.workspace.allWindows, [1, 3])
    }

    func testWindowFailingThreeTimesIsDropped() {
        let windows = FakeWindows()
        for id in [1, 2, 3] { windows.add(id) }
        windows.failing = [2]
        let controller = Controller(windows: windows, hotkeys: FakeHotkeys(), config: config)
        controller.start()
        XCTAssertTrue(controller.workspace.contains(2))
        controller.handle(.focused(3))
        XCTAssertTrue(controller.workspace.contains(2))
        controller.handle(.focused(3))
        XCTAssertEqual(controller.workspace.allWindows, [1, 3])
    }

    func testScreenChangedRewritesEveryWindow() {
        let (controller, windows) = makeController([1, 2, 3])
        let before = windows.setFrameCalls.count
        controller.screenChanged()
        XCTAssertEqual(windows.setFrameCalls.count, before + 3)
    }
}
```

- [ ] **Step 3: Ejecutar y ver que falla**

Run: `swift test --filter ControllerTests`
Expected: error de compilación (módulo `PanerailCore` sin fuentes / `cannot find 'Controller'`).

- [ ] **Step 4: Implementar**

`Sources/PanerailCore/Protocols.swift`:

```swift
import CoreGraphics
import LayoutEngine

public struct WindowInfo: Equatable, Sendable {
    public let id: WindowID
    /// False for dialogs, fixed-size, minimized or full-screen windows: they float.
    public let isManageable: Bool

    public init(id: WindowID, isManageable: Bool) {
        self.id = id
        self.isManageable = isManageable
    }
}

public enum WindowEvent: Equatable, Sendable {
    case opened(WindowInfo)
    case closed(WindowID)
    case focused(WindowID)
}

@MainActor
public protocol WindowService: AnyObject {
    var onEvent: ((WindowEvent) -> Void)? { get set }
    func start()
    func allWindows() -> [WindowInfo]
    /// Usable area of the managed display, top-left origin (Accessibility coordinates).
    func usableFrame() -> CGRect
    /// Returns false when the write failed.
    func setFrame(_ rect: CGRect, for id: WindowID) -> Bool
    func focus(_ id: WindowID)
    func isAlive(_ id: WindowID) -> Bool
}

@MainActor
public protocol HotkeyService: AnyObject {
    var onCommand: ((Command) -> Void)? { get set }
    /// Returns a description of each shortcut that could not be registered.
    func register() -> [String]
}
```

`Sources/PanerailCore/Controller.swift`:

```swift
import CoreGraphics
import LayoutEngine

@MainActor
public final class Controller {
    public private(set) var workspace = Workspace()
    public private(set) var failedHotkeys: [String] = []

    private let windows: WindowService
    private let hotkeys: HotkeyService
    private let config: LayoutConfig
    private var lastApplied: [WindowID: CGRect] = [:]
    private var failures: [WindowID: Int] = [:]
    private static let maxFailures = 3

    public init(windows: WindowService, hotkeys: HotkeyService, config: LayoutConfig = LayoutConfig()) {
        self.windows = windows
        self.hotkeys = hotkeys
        self.config = config
    }

    public func start() {
        windows.onEvent = { [weak self] event in self?.handle(event) }
        hotkeys.onCommand = { [weak self] command in self?.handle(command) }
        failedHotkeys = hotkeys.register()
        windows.start()
        for info in windows.allWindows() { adopt(info) }
        relayout()
    }

    public func handle(_ command: Command) {
        workspace.perform(command, viewport: windows.usableFrame(), config: config)
        relayout()
        if let id = workspace.focusedWindow { windows.focus(id) }
    }

    public func handle(_ event: WindowEvent) {
        switch event {
        case .opened(let info):
            adopt(info)
            relayout()
        case .closed(let id):
            forget(id)
            relayout()
        case .focused(let id):
            guard workspace.contains(id) else { return }
            workspace.focus(window: id)
            relayout()
        }
    }

    /// Display parameters changed or the Mac woke up: rewrite everything.
    public func screenChanged() {
        relayout(force: true)
    }

    public func relayout(force: Bool = false) {
        if force { lastApplied.removeAll() }
        let viewport = windows.usableFrame()
        for id in workspace.allWindows where !windows.isAlive(id) { forget(id) }
        Layout.reveal(&workspace, viewport: viewport, config: config)

        var dropped = false
        let frames = Layout.frames(workspace, viewport: viewport, config: config)
        for (id, rect) in frames.sorted(by: { $0.key.rawValue < $1.key.rawValue }) {
            guard lastApplied[id] != rect else { continue }
            if windows.setFrame(rect, for: id) {
                lastApplied[id] = rect
                failures[id] = nil
            } else {
                failures[id, default: 0] += 1
                if failures[id, default: 0] >= Self.maxFailures {
                    forget(id)
                    dropped = true
                }
            }
        }
        if dropped { relayout() }
    }

    private func adopt(_ info: WindowInfo) {
        guard info.isManageable else { return }
        workspace.addWindow(info.id)
    }

    private func forget(_ id: WindowID) {
        workspace.removeWindow(id)
        lastApplied[id] = nil
        failures[id] = nil
    }
}
```

- [ ] **Step 5: Ejecutar y ver que pasa**

Run: `swift test`
Expected: `Executed 38 tests, with 0 failures`.

- [ ] **Step 6: Actualizar el árbol de la spec**

En `docs/superpowers/specs/2026-10-24-panerail-design.md`, sustituir

```
  PanerailApp/         ejecutable: Accessibility, atajos, barra de menús
Tests/
  LayoutEngineTests/
  PanerailAppTests/    Controller con WindowService falso
```

por

```
  PanerailCore/        protocolos WindowService/HotkeyService y Controller
  PanerailApp/         ejecutable: Accessibility, atajos, barra de menús
Tests/
  LayoutEngineTests/
  PanerailCoreTests/   Controller con WindowService falso
```

- [ ] **Step 7: Commit**

```bash
git add Package.swift Sources Tests docs
git commit -m "feat: add controller and service protocols"
```

---

### Task 6: AXWindowService (Accessibility real)

**Files:**
- Modify: `Package.swift`
- Create: `Sources/PanerailApp/main.swift` (stub, se sustituye en Task 8), `Sources/PanerailApp/AXWindowService.swift`

**Interfaces:**
- Consumes: `WindowService`, `WindowInfo`, `WindowEvent` (Task 5).
- Produces: `final class AXWindowService: WindowService` (`@MainActor`, init sin parámetros).

No hay tests unitarios (depende del sistema). Verificación: compila; el comportamiento real se comprueba en Task 8.

- [ ] **Step 1: Añadir el target ejecutable**

En `Package.swift`, añadir dentro de `targets:` tras `PanerailCore`:

```swift
        .executableTarget(
            name: "PanerailApp",
            dependencies: ["LayoutEngine", "PanerailCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
```

`Sources/PanerailApp/main.swift` (stub temporal):

```swift
import AppKit

NSApplication.shared.run()
```

- [ ] **Step 2: Implementar el servicio**

`Sources/PanerailApp/AXWindowService.swift`:

```swift
import AppKit
import ApplicationServices
import LayoutEngine
import PanerailCore

private func axCallback(
    _ observer: AXObserver,
    _ element: AXUIElement,
    _ notification: CFString,
    _ refcon: UnsafeMutableRawPointer?
) {
    guard let refcon else { return }
    let service = Unmanaged<AXWindowService>.fromOpaque(refcon).takeUnretainedValue()
    MainActor.assumeIsolated { service.handle(element, notification as String) }
}

@MainActor
final class AXWindowService: WindowService {
    var onEvent: ((WindowEvent) -> Void)?

    private struct Entry {
        let element: AXUIElement
        let pid: pid_t
    }

    private var entries: [WindowID: Entry] = [:]
    private var observers: [pid_t: AXObserver] = [:]
    private var nextID = 1
    private let ownPID = ProcessInfo.processInfo.processIdentifier

    // MARK: WindowService

    func start() {
        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            MainActor.assumeIsolated { self?.observe(app) }
        }
        center.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            MainActor.assumeIsolated { self?.forget(pid: app.processIdentifier) }
        }
        for app in NSWorkspace.shared.runningApplications { observe(app) }
    }

    func allWindows() -> [WindowInfo] {
        entries.keys.sorted { $0.rawValue < $1.rawValue }.compactMap(info(for:))
    }

    func usableFrame() -> CGRect {
        guard let screen = NSScreen.screens.first else { return .zero }
        let visible = screen.visibleFrame
        // Cocoa: bottom-left origin. Accessibility: top-left origin.
        return CGRect(
            x: visible.minX,
            y: screen.frame.height - visible.maxY,
            width: visible.width,
            height: visible.height
        )
    }

    func setFrame(_ rect: CGRect, for id: WindowID) -> Bool {
        guard let entry = entries[id] else { return false }
        var origin = rect.origin
        var size = rect.size
        guard let position = AXValueCreate(.cgPoint, &origin),
              let dimensions = AXValueCreate(.cgSize, &size) else { return false }
        let sizeResult = AXUIElementSetAttributeValue(entry.element, kAXSizeAttribute as CFString, dimensions)
        let positionResult = AXUIElementSetAttributeValue(entry.element, kAXPositionAttribute as CFString, position)
        return sizeResult == .success && positionResult == .success
    }

    func focus(_ id: WindowID) {
        guard let entry = entries[id] else { return }
        AXUIElementPerformAction(entry.element, kAXRaiseAction as CFString)
        let appElement = AXUIElementCreateApplication(entry.pid)
        AXUIElementSetAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, entry.element)
        NSRunningApplication(processIdentifier: entry.pid)?.activate()
    }

    func isAlive(_ id: WindowID) -> Bool {
        guard let entry = entries[id] else { return false }
        var value: CFTypeRef?
        return AXUIElementCopyAttributeValue(entry.element, kAXRoleAttribute as CFString, &value) == .success
    }

    // MARK: Observation

    private func observe(_ app: NSRunningApplication) {
        let pid = app.processIdentifier
        guard app.activationPolicy == .regular, pid != ownPID, observers[pid] == nil else { return }

        let appElement = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(appElement, 0.3)

        var created: AXObserver?
        guard AXObserverCreate(pid, axCallback, &created) == .success, let observer = created else { return }
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        AXObserverAddNotification(observer, appElement, kAXWindowCreatedNotification as CFString, refcon)
        AXObserverAddNotification(observer, appElement, kAXFocusedWindowChangedNotification as CFString, refcon)
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
        observers[pid] = observer

        for window in windows(of: appElement) {
            _ = register(window, pid: pid, emit: false)
        }
    }

    private func forget(pid: pid_t) {
        if let observer = observers.removeValue(forKey: pid) {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
        }
        for (id, entry) in entries where entry.pid == pid {
            entries[id] = nil
            onEvent?(.closed(id))
        }
    }

    func handle(_ element: AXUIElement, _ notification: String) {
        var pid: pid_t = 0
        AXUIElementGetPid(element, &pid)
        switch notification {
        case kAXWindowCreatedNotification:
            _ = register(element, pid: pid, emit: true)
        case kAXFocusedWindowChangedNotification:
            if let id = id(of: element) {
                onEvent?(.focused(id))
            } else {
                let id = register(element, pid: pid, emit: true)
                onEvent?(.focused(id))
            }
        case kAXUIElementDestroyedNotification:
            if let id = id(of: element) {
                entries[id] = nil
                onEvent?(.closed(id))
            }
        default:
            break
        }
    }

    private func register(_ element: AXUIElement, pid: pid_t, emit: Bool) -> WindowID {
        if let existing = id(of: element) { return existing }
        let id = WindowID(nextID)
        nextID += 1
        entries[id] = Entry(element: element, pid: pid)
        if let observer = observers[pid] {
            let refcon = Unmanaged.passUnretained(self).toOpaque()
            AXObserverAddNotification(observer, element, kAXUIElementDestroyedNotification as CFString, refcon)
        }
        if emit, let info = info(for: id) { onEvent?(.opened(info)) }
        return id
    }

    private func id(of element: AXUIElement) -> WindowID? {
        entries.first { CFEqual($0.value.element, element) }?.key
    }

    private func info(for id: WindowID) -> WindowInfo? {
        guard let entry = entries[id] else { return nil }
        return WindowInfo(id: id, isManageable: isManageable(entry.element))
    }

    // MARK: Attributes

    private func windows(of appElement: AXUIElement) -> [AXUIElement] {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &value) == .success else { return [] }
        return value as? [AXUIElement] ?? []
    }

    private func attribute<T>(_ element: AXUIElement, _ name: String) -> T? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value as? T
    }

    private func isManageable(_ element: AXUIElement) -> Bool {
        guard attribute(element, kAXRoleAttribute) as String? == kAXWindowRole,
              attribute(element, kAXSubroleAttribute) as String? == kAXStandardWindowSubrole else { return false }
        if attribute(element, kAXMinimizedAttribute) as Bool? == true { return false }
        if attribute(element, "AXFullScreen") as Bool? == true { return false }
        var settable = DarwinBoolean(false)
        guard AXUIElementIsAttributeSettable(element, kAXSizeAttribute as CFString, &settable) == .success,
              settable.boolValue else { return false }
        return true
    }
}
```

- [ ] **Step 3: Compilar**

Run: `swift build`
Expected: `Build complete!`. Si algún símbolo de Accessibility cambia de firma en el SDK instalado, ajustar solo ese punto sin cambiar el comportamiento.

- [ ] **Step 4: Commit**

```bash
git add Package.swift Sources
git commit -m "feat: add Accessibility window service"
```

---

### Task 7: CarbonHotkeyService (atajos globales)

**Files:**
- Create: `Sources/PanerailApp/CarbonHotkeyService.swift`

**Interfaces:**
- Consumes: `HotkeyService` (Task 5), `Command` (Task 1).
- Produces: `final class CarbonHotkeyService: HotkeyService` (`@MainActor`, init sin parámetros).

Atajos por defecto (Ctrl+Opt):

| Tecla | Comando |
|-------|---------|
| H / ← | focusLeft |
| L / → | focusRight |
| K / ↑ | focusUp |
| J / ↓ | focusDown |
| R | cycleWidth |
| F | toggleFullWidth |
| C | centerColumn |
| [ | stackLeft |
| ] | unstack |

- [ ] **Step 1: Implementar**

`Sources/PanerailApp/CarbonHotkeyService.swift`:

```swift
import Carbon.HIToolbox
import LayoutEngine
import PanerailCore

private let hotkeySignature: OSType = 0x4C4E4B52 // 'LNKR'

private func hotkeyHandler(
    _ next: EventHandlerCallRef?,
    _ event: EventRef?,
    _ userData: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let event, let userData else { return OSStatus(eventNotHandledErr) }
    var hotkeyID = EventHotKeyID()
    let status = GetEventParameter(
        event,
        EventParamName(kEventParamDirectObject),
        EventParamType(typeEventHotKeyID),
        nil,
        MemoryLayout<EventHotKeyID>.size,
        nil,
        &hotkeyID
    )
    guard status == noErr else { return status }
    let service = Unmanaged<CarbonHotkeyService>.fromOpaque(userData).takeUnretainedValue()
    MainActor.assumeIsolated { service.fire(hotkeyID.id) }
    return noErr
}

@MainActor
final class CarbonHotkeyService: HotkeyService {
    var onCommand: ((Command) -> Void)?

    private struct Binding {
        let name: String
        let keyCode: Int
        let command: Command
    }

    private static let bindings: [Binding] = [
        Binding(name: "⌃⌥H", keyCode: kVK_ANSI_H, command: .focusLeft),
        Binding(name: "⌃⌥←", keyCode: kVK_LeftArrow, command: .focusLeft),
        Binding(name: "⌃⌥L", keyCode: kVK_ANSI_L, command: .focusRight),
        Binding(name: "⌃⌥→", keyCode: kVK_RightArrow, command: .focusRight),
        Binding(name: "⌃⌥K", keyCode: kVK_ANSI_K, command: .focusUp),
        Binding(name: "⌃⌥↑", keyCode: kVK_UpArrow, command: .focusUp),
        Binding(name: "⌃⌥J", keyCode: kVK_ANSI_J, command: .focusDown),
        Binding(name: "⌃⌥↓", keyCode: kVK_DownArrow, command: .focusDown),
        Binding(name: "⌃⌥R", keyCode: kVK_ANSI_R, command: .cycleWidth),
        Binding(name: "⌃⌥F", keyCode: kVK_ANSI_F, command: .toggleFullWidth),
        Binding(name: "⌃⌥C", keyCode: kVK_ANSI_C, command: .centerColumn),
        Binding(name: "⌃⌥[", keyCode: kVK_ANSI_LeftBracket, command: .stackLeft),
        Binding(name: "⌃⌥]", keyCode: kVK_ANSI_RightBracket, command: .unstack),
    ]

    private var refs: [EventHotKeyRef] = []
    private var handlerInstalled = false

    func register() -> [String] {
        installHandlerIfNeeded()
        var failed: [String] = []
        for (index, binding) in Self.bindings.enumerated() {
            var ref: EventHotKeyRef?
            let status = RegisterEventHotKey(
                UInt32(binding.keyCode),
                UInt32(controlKey | optionKey),
                EventHotKeyID(signature: hotkeySignature, id: UInt32(index)),
                GetApplicationEventTarget(),
                0,
                &ref
            )
            if status == noErr, let ref {
                refs.append(ref)
            } else {
                failed.append(binding.name)
            }
        }
        return failed
    }

    func fire(_ id: UInt32) {
        guard Self.bindings.indices.contains(Int(id)) else { return }
        onCommand?(Self.bindings[Int(id)].command)
    }

    private func installHandlerIfNeeded() {
        guard !handlerInstalled else { return }
        var spec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        InstallEventHandler(
            GetApplicationEventTarget(),
            hotkeyHandler,
            1,
            &spec,
            Unmanaged.passUnretained(self).toOpaque(),
            nil
        )
        handlerInstalled = true
    }
}
```

- [ ] **Step 2: Compilar**

Run: `swift build`
Expected: `Build complete!`.

- [ ] **Step 3: Commit**

```bash
git add Sources
git commit -m "feat: add global hotkeys via Carbon"
```

---

### Task 8: App de barra de menús, empaquetado y prueba de humo

**Files:**
- Modify: `Sources/PanerailApp/main.swift` (sustituye el stub)
- Create: `Sources/PanerailApp/AppDelegate.swift`, `Resources/Info.plist`, `scripts/bundle.sh`, `docs/smoke-test.md`

**Interfaces:**
- Consumes: `Controller`, `AXWindowService`, `CarbonHotkeyService`.
- Produces: `build/Panerail.app` ejecutable, con icono de barra de menús, pantalla de permiso y arranque al inicio de sesión.

- [ ] **Step 1: Punto de entrada y AppDelegate**

`Sources/PanerailApp/main.swift`:

```swift
import AppKit

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
```

`Sources/PanerailApp/AppDelegate.swift`:

```swift
import AppKit
import ApplicationServices
import PanerailCore
import ServiceManagement

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private var controller: Controller?
    private var permissionTimer: Timer?
    private var observers: [NSObjectProtocol] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem.button?.image = NSImage(
            systemSymbolName: "rectangle.split.3x1",
            accessibilityDescription: "Panerail"
        )
        if AXIsProcessTrusted() {
            startController()
        } else {
            requestPermission()
        }
        rebuildMenu()
    }

    // MARK: Permission gate

    private func requestPermission() {
        // Registers Panerail in the Accessibility list so the user only has to flip the switch.
        _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)

        let alert = NSAlert()
        alert.messageText = "Panerail necesita permiso de Accesibilidad"
        alert.informativeText = "Para mover ventanas, activa Panerail en Ajustes del Sistema > Privacidad y seguridad > Accesibilidad. Panerail empezará solo cuando lo concedas."
        alert.addButton(withTitle: "Abrir Ajustes")
        alert.addButton(withTitle: "Más tarde")
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn { openAccessibilitySettings() }

        permissionTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard AXIsProcessTrusted() else { return }
                self?.permissionTimer?.invalidate()
                self?.permissionTimer = nil
                self?.startController()
                self?.rebuildMenu()
            }
        }
    }

    @objc private func openAccessibilitySettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }

    // MARK: Controller

    private func startController() {
        let controller = Controller(windows: AXWindowService(), hotkeys: CarbonHotkeyService())
        controller.start()
        self.controller = controller

        let screens = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak controller] _ in
            MainActor.assumeIsolated { controller?.screenChanged() }
        }
        let wake = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak controller] _ in
            MainActor.assumeIsolated { controller?.screenChanged() }
        }
        observers = [screens, wake]
    }

    // MARK: Menu

    private func rebuildMenu() {
        let menu = NSMenu()
        let status = NSMenuItem(title: statusText(), action: nil, keyEquivalent: "")
        status.isEnabled = false
        menu.addItem(status)

        if let failed = controller?.failedHotkeys, !failed.isEmpty {
            let conflict = NSMenuItem(title: "Atajos en conflicto: \(failed.joined(separator: " "))", action: nil, keyEquivalent: "")
            conflict.isEnabled = false
            menu.addItem(conflict)
        }
        if controller == nil {
            menu.addItem(NSMenuItem(title: "Abrir ajustes de Accesibilidad", action: #selector(openAccessibilitySettings), keyEquivalent: ""))
        }

        menu.addItem(.separator())
        let login = NSMenuItem(title: "Iniciar al arrancar", action: #selector(toggleLogin), keyEquivalent: "")
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(login)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Salir de Panerail", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

        for item in menu.items where item.action != nil && item.target == nil && item.action != #selector(NSApplication.terminate(_:)) {
            item.target = self
        }
        statusItem.menu = menu
    }

    private func statusText() -> String {
        controller == nil ? "Esperando permiso de Accesibilidad" : "Activo"
    }

    @objc private func toggleLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            NSLog("Panerail: login item change failed: \(error)")
        }
        rebuildMenu()
    }
}
```

- [ ] **Step 2: Info.plist y script de empaquetado**

`Resources/Info.plist`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key><string>Panerail</string>
    <key>CFBundleIdentifier</key><string>dev.panerail.app</string>
    <key>CFBundleName</key><string>Panerail</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>0.1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>13.0</string>
    <key>LSUIElement</key><true/>
    <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
```

`scripts/bundle.sh`:

```bash
#!/usr/bin/env bash
# Builds build/Panerail.app. Set SIGN_IDENTITY to a stable identity (for example an
# "Apple Development" certificate) so the Accessibility grant survives rebuilds;
# the default ad-hoc signature changes on every build.
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG="${CONFIG:-release}"
IDENTITY="${SIGN_IDENTITY:--}"
APP="build/Panerail.app"

swift build -c "$CONFIG"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp ".build/$CONFIG/PanerailApp" "$APP/Contents/MacOS/Panerail"
cp Resources/Info.plist "$APP/Contents/Info.plist"
codesign --force --sign "$IDENTITY" --identifier dev.panerail.app "$APP"

echo "Built $APP"
```

Run: `chmod +x scripts/bundle.sh`

- [ ] **Step 3: Guion de humo**

`docs/smoke-test.md`:

```markdown
# Prueba de humo manual

Cubre lo que los tests unitarios no pueden: Accessibility y atajos reales.

1. `scripts/bundle.sh` (idealmente con `SIGN_IDENTITY="Apple Development: ..."`).
2. `open build/Panerail.app`. Debe aparecer el icono en la barra de menús y el aviso de permiso.
3. Pulsa "Abrir Ajustes", activa Panerail en Accesibilidad. En ~1 s el menú pasa a "Activo".
4. Abre TextEdit y crea tres documentos con ⌘N.
   - Esperado: tres columnas del 50 % de ancho; la última visible a la derecha, la primera aparcada a la izquierda con 1 px visible.
5. ⌃⌥H / ⌃⌥L: el foco y la tira se desplazan una columna.
6. ⌃⌥R: el ancho de la columna enfocada cicla 50 → 66 → 75 → 25 → 33 → 50 %.
7. ⌃⌥F: ancho completo; otra vez, vuelve al anterior.
8. ⌃⌥C: la columna enfocada queda centrada.
9. ⌃⌥[ : la ventana enfocada se apila en la columna de su izquierda; ⌃⌥J / ⌃⌥K cambian de ventana en la pila; ⌃⌥] la saca a su propia columna.
10. Cierra una ventana: las demás se recolocan. Abre un diálogo (⌘O en TextEdit): flota y no entra en la tira.
11. Bloquea la pantalla y desbloquea: el layout se mantiene.
12. Menú: "Iniciar al arrancar" marca/desmarca; "Salir de Panerail" cierra la app.

Si algo falla, anota el paso y el comportamiento observado.
```

- [ ] **Step 4: Compilar, empaquetar y ejecutar la prueba de humo**

Run: `swift build && scripts/bundle.sh`
Expected: `Build complete!` y `Built build/Panerail.app`.

Después seguir `docs/smoke-test.md` completo. Expected: los 12 pasos se comportan como se describe. Cualquier desviación es un bug a corregir antes de dar el MVP por terminado.

- [ ] **Step 5: Ejecutar toda la suite y commit**

Run: `swift test`
Expected: `Executed 38 tests, with 0 failures`.

```bash
git add Sources Resources scripts docs
git commit -m "feat: add menu bar app, bundling script and smoke test"
```

---

## Self-review

- **Cobertura de la spec:** tira de columnas y reveal (T4); anchos, ancho completo y centrado (T2, T4); huecos (T4, `LayoutConfig`); pilas (T3); atajos Ctrl+Opt con Vim y flechas (T7); barra de menús, permiso y login item (T8); flotantes (`isManageable`, T5/T6); aparcado 1 px (T4); una escritura por cambio (T5); validación de ventanas y fallos repetidos (T5); reposo y cambio de pantallas (T5, T8); conflicto de atajos (T7, T8); pruebas del motor, del Controller y guion de humo (T1-T5, T8). Fuera del MVP, sin tarea: animación, trackpad, indicador, fijadas, reglas por app, Spaces, sesión, actualizaciones, licencias.
- **Desviaciones de la spec:** se añade el target `PanerailCore` (Controller y protocolos fuera del ejecutable para poder testearlos), corregido en la spec en Task 5. Los atajos usan Carbon en vez de `CGEventTap`, que la spec permitía y que no necesita permisos.
- **Consistencia de tipos:** `WindowID`, `Command`, `Column`, `Workspace`, `LayoutConfig`, `Layout.frames/reveal/center`, `Workspace.perform`, `WindowService`, `HotkeyService`, `Controller` usan los mismos nombres y firmas en todas las tareas.
- **Riesgos que solo la prueba de humo puede confirmar:** `AXObserverAddNotification` puede fallar en apps recién lanzadas; `isManageable` se evalúa al crear la ventana y algunas apps aún no exponen el subrole en ese instante; macOS puede reajustar ventanas parcialmente fuera de pantalla.
