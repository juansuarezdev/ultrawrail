# Linkr: animación y previsualización, plan de implementación

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Animar el desplazamiento horizontal de las ventanas reales y mostrar en el menú de la barra de menús una previsualización animada de la tira.

**Architecture:** `LayoutEngine` gana piezas puras (`Tween`, `Easing`, `Layout.stripRects`, `StripPreview`). `LinkrCore` gana `Animator`, `FrameClock` y `MotionSettings`, que el `Controller` usa para repartir cada layout entre escrituras inmediatas y animadas, y publica un `onChange` con instantáneas. `LinkrApp` añade un reloj real, el guardado de ajustes, la vista `StripPreviewView` y el menú.

**Tech Stack:** Swift 6.4 toolchain, SwiftPM, XCTest, AppKit, Core Graphics.

Spec: `docs/superpowers/specs/2026-10-24-linkr-animation-preview-design.md`. Continúa el MVP (`2026-10-24-linkr-mvp.md`), ya implementado.

## Global Constraints

- Rama de trabajo: `feat/animation-preview` (ya creada).
- Modo de lenguaje Swift: `LayoutEngine` y `LinkrCore` en Swift 6; `LinkrApp` y `LinkrCoreTests` en modo Swift 5. No tocar `Package.swift`.
- Animación solo del desplazamiento horizontal: una ventana se anima solo si su tamaño no cambia y solo varía su `x`. Las demás saltan.
- Duraciones: Rápida 0.12 s, Normal 0.18 s, Desactivada 0. Curva `easeOut`.
- Máximo 4 ventanas animadas a la vez (las más cercanas a la columna enfocada). Las aparcadas fuera de la vista (en origen y destino) saltan.
- Si las escrituras de un tick tardan más de 0.033 s, se salta al destino.
- Una escritura fallida durante la animación cancela solo esa ventana, escribe su destino y cuenta un único fallo (máximo 3, como en el MVP).
- Preview: ancho máximo 256 px dentro de un menú de ~280 px; solo visual, sin clics.
- Ajustes en `UserDefaults`: `motionSpeed` (`fast`/`normal`/`off`) y `respectReduceMotion` (por defecto `true`).
- Comentarios y estilo como el código existente: pocos comentarios, solo para lo no evidente.
- Commits en inglés, estilo `feat:`/`test:`/`docs:`/`chore:`. Sin trailers de autoría ni mención a IA.

## Desviaciones respecto a la spec

- La velocidad por defecto en `LinkrCore` (`MotionSettings()`) es `.off`, para que los tests existentes no cambien. En la app, el guardado de ajustes usa `.normal` como valor por defecto desde el principio, en vez de esperar al último paso.
- `StripPreview` (geometría normalizada del preview) vive en `LayoutEngine`, para probarla sin AppKit.

## Estructura de archivos

```
Sources/LayoutEngine/
  Tween.swift              Easing, Tween
  Layout.swift             (modifica) stripRects, stripWidth; frames reutiliza stripRects
  StripPreview.swift       geometría normalizada del preview + interpolación
Sources/LinkrCore/
  MotionSettings.swift     MotionSpeed, MotionSettings
  Animator.swift           FrameClock, Animator
  Controller.swift         (modifica) animación, onChange, WorkspaceSnapshot
Sources/LinkrApp/
  TimerFrameClock.swift    FrameClock real (Timer 60 Hz)
  MotionSettingsStore.swift UserDefaults
  StripPreviewView.swift   vista del menú
  AppDelegate.swift        (modifica) menú, preview, ajustes
  AXWindowService.swift    (modifica) no reescribir el tamaño si no cambia
Tests/LayoutEngineTests/TweenTests.swift, LayoutTests.swift (modifica), StripPreviewTests.swift
Tests/LinkrCoreTests/AnimatorTests.swift, ControllerAnimationTests.swift, ControllerTests.swift (modifica FakeWindows)
docs/smoke-test.md, docs/superpowers/specs/2026-10-24-linkr-animation-preview-design.md (modifica)
```

---

### Task 1: Easing y Tween

**Files:**
- Create: `Sources/LayoutEngine/Tween.swift`
- Test: `Tests/LayoutEngineTests/TweenTests.swift`

**Interfaces:**
- Produces:
  - `Easing.easeOut(_ t: Double) -> Double`
  - `struct Tween: Equatable, Sendable` con `init(from: [WindowID: CGRect], to: [WindowID: CGRect], duration: Double)`, `from`, `to`, `duration`, `isEmpty`, `isFinished(at elapsed: Double) -> Bool`, `frames(at elapsed: Double) -> [WindowID: CGRect]`, `removing(_ id: WindowID) -> Tween`.

- [ ] **Step 1: Escribir los tests que fallan**

`Tests/LayoutEngineTests/TweenTests.swift`:

```swift
import XCTest
import CoreGraphics
@testable import LayoutEngine

final class TweenTests: XCTestCase {
    let start = CGRect(x: 0, y: 10, width: 490, height: 780)
    let end = CGRect(x: 100, y: 10, width: 490, height: 780)

    func testEaseOutEndpointsClampAndIncrease() {
        XCTAssertEqual(Easing.easeOut(0), 0)
        XCTAssertEqual(Easing.easeOut(1), 1)
        XCTAssertEqual(Easing.easeOut(-1), 0)
        XCTAssertEqual(Easing.easeOut(2), 1)
        var previous = 0.0
        for step in 1...10 {
            let value = Easing.easeOut(Double(step) / 10)
            XCTAssertGreaterThan(value, previous)
            previous = value
        }
        XCTAssertGreaterThan(Easing.easeOut(0.5), 0.5)
    }

    func testFramesInterpolateAndLandExactlyOnTarget() {
        let tween = Tween(from: [1: start], to: [1: end], duration: 0.2)
        XCTAssertEqual(tween.frames(at: 0)[1], start)
        XCTAssertEqual(tween.frames(at: 0.1)[1]!.minX, 87.5, accuracy: 0.0001)
        XCTAssertEqual(tween.frames(at: 0.2)[1], end)
        XCTAssertEqual(tween.frames(at: 5)[1], end)
        XCTAssertFalse(tween.isFinished(at: 0.19))
        XCTAssertTrue(tween.isFinished(at: 0.2))
    }

    func testZeroDurationIsFinishedAndReturnsTarget() {
        let tween = Tween(from: [1: start], to: [1: end], duration: 0)
        XCTAssertTrue(tween.isFinished(at: 0))
        XCTAssertEqual(tween.frames(at: 0)[1], end)
    }

    func testWindowWithoutOriginJumpsToTarget() {
        let tween = Tween(from: [:], to: [1: end], duration: 0.2)
        XCTAssertEqual(tween.frames(at: 0)[1], end)
    }

    func testRemovingDropsOnlyThatWindow() {
        let tween = Tween(from: [1: start, 2: start], to: [1: end, 2: end], duration: 0.2)
        let reduced = tween.removing(1)
        XCTAssertEqual(Set(reduced.to.keys), [2])
        XCTAssertFalse(reduced.isEmpty)
        XCTAssertTrue(reduced.removing(2).isEmpty)
    }
}
```

- [ ] **Step 2: Ejecutar y ver que falla**

Run: `swift test --filter TweenTests`
Expected: error de compilación `cannot find 'Easing' in scope`.

- [ ] **Step 3: Implementar**

`Sources/LayoutEngine/Tween.swift`:

```swift
import CoreGraphics

public enum Easing {
    public static func easeOut(_ t: Double) -> Double {
        let clamped = min(max(t, 0), 1)
        return 1 - (1 - clamped) * (1 - clamped) * (1 - clamped)
    }
}

public struct Tween: Equatable, Sendable {
    public let from: [WindowID: CGRect]
    public let to: [WindowID: CGRect]
    public let duration: Double

    public init(from: [WindowID: CGRect], to: [WindowID: CGRect], duration: Double) {
        self.from = from
        self.to = to
        self.duration = duration
    }

    public var isEmpty: Bool { to.isEmpty }

    public func isFinished(at elapsed: Double) -> Bool { elapsed >= duration }

    public func frames(at elapsed: Double) -> [WindowID: CGRect] {
        let progress = duration <= 0 ? 1 : Easing.easeOut(elapsed / duration)
        guard progress < 1 else { return to }
        var result: [WindowID: CGRect] = [:]
        for (id, target) in to {
            guard let start = from[id] else {
                result[id] = target
                continue
            }
            result[id] = CGRect(
                x: start.minX + (target.minX - start.minX) * progress,
                y: start.minY + (target.minY - start.minY) * progress,
                width: start.width + (target.width - start.width) * progress,
                height: start.height + (target.height - start.height) * progress
            )
        }
        return result
    }

    public func removing(_ id: WindowID) -> Tween {
        Tween(
            from: from.filter { $0.key != id },
            to: to.filter { $0.key != id },
            duration: duration
        )
    }
}
```

- [ ] **Step 4: Ejecutar y ver que pasa**

Run: `swift test --filter TweenTests`
Expected: `Executed 5 tests, with 0 failures`.

- [ ] **Step 5: Commit**

```bash
git add Sources/LayoutEngine/Tween.swift Tests/LayoutEngineTests/TweenTests.swift
git commit -m "feat: add easing and tween"
```

---

### Task 2: Geometría de la tira y del preview

**Files:**
- Modify: `Sources/LayoutEngine/Layout.swift` (añadir `stripWidth` y `stripRects`; `frames` pasa a usar `stripRects`)
- Create: `Sources/LayoutEngine/StripPreview.swift`
- Test: `Tests/LayoutEngineTests/LayoutTests.swift` (añadir tests), `Tests/LayoutEngineTests/StripPreviewTests.swift`

**Interfaces:**
- Consumes: `Workspace`, `Layout`, `LayoutConfig`, `WindowID`.
- Produces:
  - `Layout.stripWidth(_ ws: Workspace, viewport: CGRect, config: LayoutConfig) -> Double` (público)
  - `Layout.stripRects(_ ws: Workspace, viewport: CGRect, config: LayoutConfig) -> [WindowID: CGRect]` (público; x en coordenadas de tira, y relativa al viewport)
  - `struct StripPreview: Equatable, Sendable` con `Item { id, rect (normalizado), isFocused, isVisible }`, `items`, `frameX`, `frameWidth`, `init(items:frameX:frameWidth:)`, `init(workspace:viewport:config:)`, `interpolated(to:progress:) -> StripPreview`.

- [ ] **Step 1: Añadir los tests que fallan**

Dentro de `LayoutTests` (`Tests/LayoutEngineTests/LayoutTests.swift`):

```swift
    func testStripRectsUseStripCoordinatesAndViewportRelativeY() {
        let rects = Layout.stripRects(makeWorkspace(3), viewport: viewport, config: config)
        XCTAssertEqual(rects[1], CGRect(x: 10, y: 10, width: 490, height: 780))
        XCTAssertEqual(rects[2], CGRect(x: 510, y: 10, width: 490, height: 780))
        XCTAssertEqual(rects[3], CGRect(x: 1010, y: 10, width: 490, height: 780))
    }

    func testStripWidthCoversAllColumnsPlusOuterGap() {
        XCTAssertEqual(Layout.stripWidth(makeWorkspace(3), viewport: viewport, config: config), 1510)
        XCTAssertEqual(Layout.stripWidth(Workspace(), viewport: viewport, config: config), 0)
    }
```

`Tests/LayoutEngineTests/StripPreviewTests.swift`:

```swift
import XCTest
import CoreGraphics
@testable import LayoutEngine

final class StripPreviewTests: XCTestCase {
    let viewport = CGRect(x: 0, y: 0, width: 1000, height: 800)
    let config = LayoutConfig(gap: 10, outerGap: 10)

    func makeWorkspace(_ count: Int) -> Workspace {
        var ws = Workspace()
        for i in 1...count { ws.addWindow(WindowID(i)) }
        return ws
    }

    func testPreviewNormalizesToStripWidthAndMarksFocusAndVisibility() {
        var ws = makeWorkspace(3)
        Layout.reveal(&ws, viewport: viewport, config: config)
        let preview = StripPreview(workspace: ws, viewport: viewport, config: config)
        XCTAssertEqual(preview.frameX, 510.0 / 1510.0, accuracy: 1e-9)
        XCTAssertEqual(preview.frameWidth, 1000.0 / 1510.0, accuracy: 1e-9)
        XCTAssertEqual(preview.items.map(\.id), [1, 2, 3])
        XCTAssertEqual(preview.items[2].rect.minX, 1010.0 / 1510.0, accuracy: 1e-9)
        XCTAssertEqual(preview.items[2].rect.minY, 10.0 / 800.0, accuracy: 1e-9)
        XCTAssertEqual(preview.items[2].rect.height, 780.0 / 800.0, accuracy: 1e-9)
        XCTAssertEqual(preview.items.map(\.isFocused), [false, false, true])
        XCTAssertEqual(preview.items.map(\.isVisible), [false, true, true])
    }

    func testStripShorterThanViewportScalesToViewportWidth() {
        let preview = StripPreview(workspace: makeWorkspace(1), viewport: viewport, config: config)
        XCTAssertEqual(preview.frameX, 0, accuracy: 1e-9)
        XCTAssertEqual(preview.frameWidth, 1, accuracy: 1e-9)
        XCTAssertEqual(preview.items[0].rect.width, 490.0 / 1000.0, accuracy: 1e-9)
    }

    func testInterpolationBlendsMatchingItemsAndKeepsNewOnesAtTarget() {
        let from = StripPreview(
            items: [.init(id: 1, rect: CGRect(x: 0, y: 0, width: 0.2, height: 1), isFocused: false, isVisible: true)],
            frameX: 0,
            frameWidth: 0.5
        )
        let to = StripPreview(
            items: [
                .init(id: 1, rect: CGRect(x: 0.4, y: 0, width: 0.2, height: 1), isFocused: true, isVisible: true),
                .init(id: 2, rect: CGRect(x: 0.7, y: 0, width: 0.2, height: 1), isFocused: false, isVisible: false),
            ],
            frameX: 0.5,
            frameWidth: 0.5
        )
        let half = from.interpolated(to: to, progress: 0.5)
        XCTAssertEqual(half.items[0].rect.minX, 0.2, accuracy: 1e-9)
        XCTAssertTrue(half.items[0].isFocused)
        XCTAssertEqual(half.items[1].rect.minX, 0.7, accuracy: 1e-9)
        XCTAssertEqual(half.frameX, 0.25, accuracy: 1e-9)
        XCTAssertEqual(from.interpolated(to: to, progress: 1), to)
    }
}
```

- [ ] **Step 2: Ejecutar y ver que falla**

Run: `swift test --filter "LayoutTests|StripPreviewTests"`
Expected: error de compilación `type 'Layout' has no member 'stripRects'` y `cannot find 'StripPreview' in scope`.

- [ ] **Step 3: Implementar `stripRects`/`stripWidth` y reutilizarlos en `frames`**

En `Sources/LayoutEngine/Layout.swift`, sustituir el método `frames` completo (el último del enum) por:

```swift
    /// Total width of the strip including the outer gap on both ends.
    public static func stripWidth(_ ws: Workspace, viewport: CGRect, config: LayoutConfig) -> Double {
        guard !ws.columns.isEmpty else { return 0 }
        return stripX(of: ws.columns.count, in: ws, viewport: viewport, config: config) - config.gap + config.outerGap
    }

    /// Rect of every window in strip coordinates: x from the strip origin,
    /// y relative to the viewport's top edge. Nothing is parked here.
    public static func stripRects(_ ws: Workspace, viewport: CGRect, config: LayoutConfig) -> [WindowID: CGRect] {
        var result: [WindowID: CGRect] = [:]
        for (index, column) in ws.columns.enumerated() {
            let width = columnWidth(column, viewport: viewport, config: config)
            let x = stripX(of: index, in: ws, viewport: viewport, config: config)
            let count = Double(column.windows.count)
            let height = max((viewport.height - 2 * config.outerGap - (count - 1) * config.gap) / count, 1)
            for (row, id) in column.windows.enumerated() {
                let y = config.outerGap + Double(row) * (height + config.gap)
                result[id] = CGRect(x: x, y: y, width: width, height: height)
            }
        }
        return result
    }

    /// Rect of every window in screen coordinates. Columns fully outside the
    /// viewport are parked with 1 px still inside it.
    public static func frames(_ ws: Workspace, viewport: CGRect, config: LayoutConfig) -> [WindowID: CGRect] {
        let rects = stripRects(ws, viewport: viewport, config: config)
        var result: [WindowID: CGRect] = [:]
        for column in ws.columns {
            guard let first = column.windows.first, let base = rects[first] else { continue }
            var x = viewport.minX + base.minX - ws.scrollOffset
            if x + base.width <= viewport.minX {
                x = viewport.minX - base.width + 1
            } else if x >= viewport.maxX {
                x = viewport.maxX - 1
            }
            for id in column.windows {
                guard let rect = rects[id] else { continue }
                result[id] = CGRect(x: x, y: viewport.minY + rect.minY, width: rect.width, height: rect.height)
            }
        }
        return result
    }
```

También en `Layout.swift`, cambiar la línea de `removeOverscroll` que calcula `stripWidth` para reutilizar el nuevo método. Sustituir:

```swift
        let stripWidth = stripX(of: ws.columns.count, in: ws, viewport: viewport, config: config) - config.gap + config.outerGap
        ws.scrollOffset = max(0, min(ws.scrollOffset, stripWidth - viewport.width))
```

por:

```swift
        let width = stripWidth(ws, viewport: viewport, config: config)
        ws.scrollOffset = max(0, min(ws.scrollOffset, width - viewport.width))
```

- [ ] **Step 4: Implementar `StripPreview`**

`Sources/LayoutEngine/StripPreview.swift`:

```swift
import CoreGraphics

/// Normalized geometry of the strip for the menu preview: x and width are
/// fractions of the strip width, y and height fractions of the viewport height.
public struct StripPreview: Equatable, Sendable {
    public struct Item: Equatable, Sendable {
        public var id: WindowID
        public var rect: CGRect
        public var isFocused: Bool
        public var isVisible: Bool

        public init(id: WindowID, rect: CGRect, isFocused: Bool, isVisible: Bool) {
            self.id = id
            self.rect = rect
            self.isFocused = isFocused
            self.isVisible = isVisible
        }
    }

    public var items: [Item]
    public var frameX: Double
    public var frameWidth: Double

    public init(items: [Item], frameX: Double, frameWidth: Double) {
        self.items = items
        self.frameX = frameX
        self.frameWidth = frameWidth
    }

    public init(workspace ws: Workspace, viewport: CGRect, config: LayoutConfig) {
        let total = max(Layout.stripWidth(ws, viewport: viewport, config: config), viewport.width, 1)
        let height = max(viewport.height, 1)
        let left = ws.scrollOffset
        let right = left + viewport.width
        let focused = ws.focusedWindow
        let rects = Layout.stripRects(ws, viewport: viewport, config: config)
        self.items = rects.sorted { $0.key.rawValue < $1.key.rawValue }.map { id, rect in
            Item(
                id: id,
                rect: CGRect(x: rect.minX / total, y: rect.minY / height, width: rect.width / total, height: rect.height / height),
                isFocused: id == focused,
                isVisible: rect.maxX > left && rect.minX < right
            )
        }
        self.frameX = left / total
        self.frameWidth = viewport.width / total
    }

    /// Blends `self` toward `target`; windows missing from `self` appear at their target.
    public func interpolated(to target: StripPreview, progress p: Double) -> StripPreview {
        guard p < 1 else { return target }
        let previous = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0.rect) })
        let blended = target.items.map { item -> Item in
            guard let start = previous[item.id] else { return item }
            var copy = item
            copy.rect = CGRect(
                x: start.minX + (item.rect.minX - start.minX) * p,
                y: start.minY + (item.rect.minY - start.minY) * p,
                width: start.width + (item.rect.width - start.width) * p,
                height: start.height + (item.rect.height - start.height) * p
            )
            return copy
        }
        return StripPreview(
            items: blended,
            frameX: frameX + (target.frameX - frameX) * p,
            frameWidth: frameWidth + (target.frameWidth - frameWidth) * p
        )
    }
}
```

- [ ] **Step 5: Ejecutar toda la suite**

Run: `swift test`
Expected: todos pasan, incluidos los tests anteriores de `frames` y `removeOverscroll` (la refactorización no cambia su comportamiento). `Executed 52 tests, with 0 failures`.

- [ ] **Step 6: Commit**

```bash
git add Sources/LayoutEngine Tests/LayoutEngineTests
git commit -m "feat: add strip geometry and menu preview model"
```

---

### Task 3: MotionSettings y Animator

**Files:**
- Create: `Sources/LinkrCore/MotionSettings.swift`, `Sources/LinkrCore/Animator.swift`
- Test: `Tests/LinkrCoreTests/AnimatorTests.swift`

**Interfaces:**
- Consumes: `Tween`, `WindowID` (Task 1).
- Produces:
  - `enum MotionSpeed: String, CaseIterable, Sendable { fast, normal, off }` con `duration: Double`.
  - `struct MotionSettings: Equatable, Sendable { speed; respectReduceMotion }` con `init(speed: MotionSpeed = .off, respectReduceMotion: Bool = true)`, `duration(reduceMotion:) -> Double`, `previewDuration(reduceMotion:) -> Double`.
  - `@MainActor protocol FrameClock: AnyObject { func start(_ tick: @escaping () -> Void); func stop() }`
  - `@MainActor final class Animator` con `init(clock:now:slowFrameLimit:)`, `onFrame: (([WindowID: CGRect], Bool) -> Void)?`, `isAnimating`, `start(_ tween: Tween)`, `cancel()`, `remove(_ id: WindowID)`.

- [ ] **Step 1: Escribir los tests que fallan**

`Tests/LinkrCoreTests/AnimatorTests.swift`:

```swift
import XCTest
import CoreGraphics
import LayoutEngine
@testable import LinkrCore

@MainActor
final class ManualClock: FrameClock {
    var time = 0.0
    private(set) var isRunning = false
    private var tick: (() -> Void)?

    func start(_ tick: @escaping () -> Void) {
        self.tick = tick
        isRunning = true
    }

    func stop() {
        tick = nil
        isRunning = false
    }

    func fire(advancingBy dt: Double) {
        time += dt
        tick?()
    }
}

@MainActor
final class AnimatorTests: XCTestCase {
    let start = CGRect(x: 0, y: 10, width: 490, height: 780)
    let end = CGRect(x: 100, y: 10, width: 490, height: 780)

    func makeAnimator() -> (Animator, ManualClock) {
        let clock = ManualClock()
        return (Animator(clock: clock, now: { clock.time }), clock)
    }

    func testEmitsIntermediateThenExactFinalFrameAndStops() {
        let (animator, clock) = makeAnimator()
        var emitted: [(frames: [WindowID: CGRect], finished: Bool)] = []
        animator.onFrame = { emitted.append(($0, $1)) }
        animator.start(Tween(from: [1: start], to: [1: end], duration: 0.2))
        XCTAssertTrue(animator.isAnimating)

        clock.fire(advancingBy: 0.1)
        XCTAssertFalse(emitted[0].finished)
        XCTAssertGreaterThan(emitted[0].frames[1]!.minX, 0)
        XCTAssertLessThan(emitted[0].frames[1]!.minX, 100)

        clock.fire(advancingBy: 0.2)
        XCTAssertTrue(emitted[1].finished)
        XCTAssertEqual(emitted[1].frames[1], end)
        XCTAssertFalse(animator.isAnimating)
        XCTAssertFalse(clock.isRunning)
    }

    func testSlowFrameSnapsToTargetInTheSameTick() {
        let (animator, clock) = makeAnimator()
        var emitted: [(frames: [WindowID: CGRect], finished: Bool)] = []
        animator.onFrame = { frames, finished in
            emitted.append((frames, finished))
            clock.time += 0.05
        }
        animator.start(Tween(from: [1: start], to: [1: end], duration: 0.2))
        clock.fire(advancingBy: 0.01)
        XCTAssertEqual(emitted.count, 2)
        XCTAssertTrue(emitted[1].finished)
        XCTAssertEqual(emitted[1].frames[1], end)
        XCTAssertFalse(animator.isAnimating)
    }

    func testCancelStopsTheClock() {
        let (animator, clock) = makeAnimator()
        animator.start(Tween(from: [1: start], to: [1: end], duration: 0.2))
        animator.cancel()
        XCTAssertFalse(animator.isAnimating)
        XCTAssertFalse(clock.isRunning)
    }

    func testRemovingLastWindowStopsAnimation() {
        let (animator, clock) = makeAnimator()
        animator.start(Tween(from: [1: start, 2: start], to: [1: end, 2: end], duration: 0.2))
        animator.remove(1)
        XCTAssertTrue(animator.isAnimating)
        animator.remove(2)
        XCTAssertFalse(animator.isAnimating)
        XCTAssertFalse(clock.isRunning)
    }

    func testRestartInsideFrameCallbackIsNotClobbered() {
        let (animator, clock) = makeAnimator()
        var calls = 0
        animator.onFrame = { _, _ in
            calls += 1
            if calls == 1 {
                animator.cancel()
                animator.start(Tween(from: [2: self.start], to: [2: self.end], duration: 0.2))
            }
        }
        animator.start(Tween(from: [1: start], to: [1: end], duration: 0.2))
        clock.fire(advancingBy: 0.05)
        XCTAssertTrue(animator.isAnimating)
        XCTAssertTrue(clock.isRunning)
    }

    func testMotionSettingsDurations() {
        XCTAssertEqual(MotionSettings(speed: .normal).duration(reduceMotion: false), 0.18)
        XCTAssertEqual(MotionSettings(speed: .fast).duration(reduceMotion: false), 0.12)
        XCTAssertEqual(MotionSettings(speed: .off).duration(reduceMotion: false), 0)
        XCTAssertEqual(MotionSettings(speed: .normal).duration(reduceMotion: true), 0)
        XCTAssertEqual(MotionSettings(speed: .normal, respectReduceMotion: false).duration(reduceMotion: true), 0.18)
    }

    func testPreviewAnimatesEvenWhenWindowAnimationIsOff() {
        XCTAssertEqual(MotionSettings(speed: .off).previewDuration(reduceMotion: false), 0.18)
        XCTAssertEqual(MotionSettings(speed: .fast).previewDuration(reduceMotion: false), 0.12)
        XCTAssertEqual(MotionSettings(speed: .off).previewDuration(reduceMotion: true), 0)
        XCTAssertEqual(MotionSettings(speed: .off, respectReduceMotion: false).previewDuration(reduceMotion: true), 0.18)
    }
}
```

- [ ] **Step 2: Ejecutar y ver que falla**

Run: `swift test --filter AnimatorTests`
Expected: error de compilación `cannot find type 'FrameClock' in scope`.

- [ ] **Step 3: Implementar**

`Sources/LinkrCore/MotionSettings.swift`:

```swift
public enum MotionSpeed: String, CaseIterable, Sendable {
    case fast
    case normal
    case off

    public var duration: Double {
        switch self {
        case .fast: 0.12
        case .normal: 0.18
        case .off: 0
        }
    }
}

public struct MotionSettings: Equatable, Sendable {
    public var speed: MotionSpeed
    public var respectReduceMotion: Bool

    public init(speed: MotionSpeed = .off, respectReduceMotion: Bool = true) {
        self.speed = speed
        self.respectReduceMotion = respectReduceMotion
    }

    /// Duration for real windows; 0 means no animation.
    public func duration(reduceMotion: Bool) -> Double {
        if speed == .off || (respectReduceMotion && reduceMotion) { return 0 }
        return speed.duration
    }

    /// The menu preview is cheap to draw, so it animates even with speed off.
    public func previewDuration(reduceMotion: Bool) -> Double {
        if respectReduceMotion && reduceMotion { return 0 }
        return speed == .off ? MotionSpeed.normal.duration : speed.duration
    }
}
```

`Sources/LinkrCore/Animator.swift`:

```swift
import CoreGraphics
import LayoutEngine

@MainActor
public protocol FrameClock: AnyObject {
    func start(_ tick: @escaping () -> Void)
    func stop()
}

/// Drives a `Tween`. Each tick hands the interpolated rects to `onFrame`; if
/// writing them takes longer than `slowFrameLimit`, it snaps to the target.
@MainActor
public final class Animator {
    public var onFrame: (([WindowID: CGRect], Bool) -> Void)?

    private let clock: FrameClock
    private let now: () -> Double
    private let slowFrameLimit: Double
    private var tween: Tween?
    private var startTime = 0.0
    private var generation = 0

    public init(clock: FrameClock, now: @escaping () -> Double, slowFrameLimit: Double = 0.033) {
        self.clock = clock
        self.now = now
        self.slowFrameLimit = slowFrameLimit
    }

    public var isAnimating: Bool { tween != nil }

    public func start(_ tween: Tween) {
        generation += 1
        self.tween = tween
        startTime = now()
        clock.start { [weak self] in self?.tick() }
    }

    public func cancel() {
        generation += 1
        tween = nil
        clock.stop()
    }

    public func remove(_ id: WindowID) {
        guard let current = tween else { return }
        let reduced = current.removing(id)
        if reduced.isEmpty {
            cancel()
        } else {
            tween = reduced
        }
    }

    private func tick() {
        guard let tween else {
            clock.stop()
            return
        }
        let elapsed = now() - startTime
        let finished = tween.isFinished(at: elapsed)
        let frames = tween.frames(at: elapsed)
        let generationBefore = generation
        let began = now()
        onFrame?(frames, finished)
        // onFrame may have cancelled or restarted the animation.
        guard generation == generationBefore else { return }
        if finished {
            cancel()
            return
        }
        if now() - began > slowFrameLimit {
            onFrame?(tween.frames(at: tween.duration), true)
            if generation == generationBefore { cancel() }
        }
    }
}
```

- [ ] **Step 4: Ejecutar y ver que pasa**

Run: `swift test --filter AnimatorTests`
Expected: `Executed 7 tests, with 0 failures`.

- [ ] **Step 5: Commit**

```bash
git add Sources/LinkrCore Tests/LinkrCoreTests/AnimatorTests.swift
git commit -m "feat: add animator and motion settings"
```

---

### Task 4: Integrar la animación en el Controller y publicar cambios

**Files:**
- Modify: `Sources/LinkrCore/Controller.swift`
- Modify: `Tests/LinkrCoreTests/ControllerTests.swift` (solo `FakeWindows`: añadir el gancho `onSetFrame`)
- Test: `Tests/LinkrCoreTests/ControllerAnimationTests.swift`

**Interfaces:**
- Consumes: `Animator`, `MotionSettings`, `Tween` (Tasks 1 y 3), `Layout`.
- Produces:
  - `struct WorkspaceSnapshot: Equatable, Sendable { workspace: Workspace; viewport: CGRect; config: LayoutConfig }` (público, con `init`).
  - `Controller.init(windows:hotkeys:config:animator:reduceMotion:)` con `animator: Animator? = nil` y `reduceMotion: @escaping () -> Bool = { false }`.
  - `Controller.motion: MotionSettings` (público, variable; por defecto `MotionSettings()`, es decir `.off`).
  - `Controller.onChange: ((WorkspaceSnapshot) -> Void)?`.

- [ ] **Step 1: Añadir el gancho a `FakeWindows`**

En `Tests/LinkrCoreTests/ControllerTests.swift`, dentro de `FakeWindows`, añadir la propiedad bajo `var echoFocus = false`:

```swift
    var onSetFrame: (() -> Void)?
```

y cambiar `setFrame` para que la llame:

```swift
    func setFrame(_ rect: CGRect, for id: WindowID) -> Bool {
        setFrameCalls.append((id, rect))
        onSetFrame?()
        return !failing.contains(id)
    }
```

- [ ] **Step 2: Escribir los tests que fallan**

`Tests/LinkrCoreTests/ControllerAnimationTests.swift`:

```swift
import XCTest
import CoreGraphics
import LayoutEngine
@testable import LinkrCore

@MainActor
final class ControllerAnimationTests: XCTestCase {
    let config = LayoutConfig(gap: 10, outerGap: 10)
    var clock = ManualClock()

    func makeController(
        _ ids: [Int],
        speed: MotionSpeed = .normal,
        respectReduceMotion: Bool = true,
        reduceMotion: Bool = false
    ) -> (Controller, FakeWindows) {
        let windows = FakeWindows()
        for id in ids { windows.add(id) }
        let clock = ManualClock()
        self.clock = clock
        let animator = Animator(clock: clock, now: { clock.time })
        let controller = Controller(
            windows: windows,
            hotkeys: FakeHotkeys(),
            config: config,
            animator: animator,
            reduceMotion: { reduceMotion }
        )
        controller.motion = MotionSettings(speed: speed, respectReduceMotion: respectReduceMotion)
        controller.start()
        return (controller, windows)
    }

    func testFocusChangeSlidesWindowsThenLandsOnTarget() {
        let (controller, windows) = makeController([1, 2, 3])
        let before = windows.setFrameCalls.count
        controller.handle(.focusLeft)
        XCTAssertEqual(windows.setFrameCalls.count, before)

        clock.fire(advancingBy: 0.09)
        let mid = windows.lastRect(2)!
        XCTAssertGreaterThan(mid.minX, 0)
        XCTAssertLessThan(mid.minX, 10)

        clock.fire(advancingBy: 0.2)
        XCTAssertEqual(windows.lastRect(2), CGRect(x: 10, y: 10, width: 490, height: 780))
        XCTAssertEqual(windows.lastRect(3), CGRect(x: 510, y: 10, width: 490, height: 780))
        XCTAssertFalse(clock.isRunning)
    }

    func testSizeChangeWritesImmediately() {
        let (controller, windows) = makeController([1, 2, 3])
        controller.handle(.cycleWidth)
        XCTAssertEqual(windows.lastRect(3)!.width, 0.66 * 980, accuracy: 0.001)
    }

    func testOffWritesImmediatelyAndNeverStartsTheClock() {
        let (controller, windows) = makeController([1, 2, 3], speed: .off)
        controller.handle(.focusLeft)
        XCTAssertEqual(windows.lastRect(2), CGRect(x: 10, y: 10, width: 490, height: 780))
        XCTAssertFalse(clock.isRunning)
    }

    func testReduceMotionWritesImmediatelyUnlessIgnored() {
        let (reduced, reducedWindows) = makeController([1, 2, 3], reduceMotion: true)
        reduced.handle(.focusLeft)
        XCTAssertEqual(reducedWindows.lastRect(2), CGRect(x: 10, y: 10, width: 490, height: 780))
        XCTAssertFalse(clock.isRunning)

        let (ignored, ignoredWindows) = makeController([1, 2, 3], respectReduceMotion: false, reduceMotion: true)
        let before = ignoredWindows.setFrameCalls.count
        ignored.handle(.focusLeft)
        XCTAssertEqual(ignoredWindows.setFrameCalls.count, before)
        XCTAssertTrue(clock.isRunning)
    }

    func testAtMostFourWindowsAnimateAndTheRestJump() {
        let (controller, windows) = makeController([1, 2, 3, 4, 5, 6], speed: .off)
        for id in 1...6 {
            controller.handle(.focused(WindowID(id)))
            for _ in 0..<3 { controller.handle(.cycleWidth) }
        }
        controller.handle(.focused(6))
        controller.motion = MotionSettings(speed: .normal)

        let baseline = windows.setFrameCalls.count
        controller.handle(.focused(1))
        let immediate = Set(windows.setFrameCalls.dropFirst(baseline).map(\.id.rawValue))
        XCTAssertEqual(immediate, [1, 6])

        let afterJump = windows.setFrameCalls.count
        clock.fire(advancingBy: 0.09)
        let animated = Set(windows.setFrameCalls.dropFirst(afterJump).map(\.id.rawValue))
        XCTAssertEqual(animated, [2, 3, 4, 5])
    }

    func testSlowFrameSnapsToTarget() {
        let (controller, windows) = makeController([1, 2, 3])
        controller.handle(.focusLeft)
        windows.onSetFrame = { [clock] in clock.time += 0.05 }
        clock.fire(advancingBy: 0.01)
        XCTAssertEqual(windows.lastRect(2), CGRect(x: 10, y: 10, width: 490, height: 780))
        XCTAssertEqual(windows.lastRect(3), CGRect(x: 510, y: 10, width: 490, height: 780))
        XCTAssertFalse(clock.isRunning)
    }

    func testNewLayoutDuringAnimationRetargetsFromCurrentPosition() {
        let (controller, windows) = makeController([1, 2, 3])
        controller.handle(.focusLeft)
        clock.fire(advancingBy: 0.09)
        let calls = windows.setFrameCalls.count
        controller.handle(.focusRight)
        XCTAssertEqual(windows.setFrameCalls.count, calls)
        clock.fire(advancingBy: 0.3)
        XCTAssertEqual(windows.lastRect(2), CGRect(x: 0, y: 10, width: 490, height: 780))
        XCTAssertEqual(windows.lastRect(3), CGRect(x: 500, y: 10, width: 490, height: 780))
    }

    func testFailedWriteDuringAnimationCancelsOnlyThatWindow() {
        let (controller, windows) = makeController([1, 2, 3])
        controller.handle(.focusLeft)
        windows.failing = [2]
        clock.fire(advancingBy: 0.09)
        clock.fire(advancingBy: 0.3)
        XCTAssertEqual(windows.lastRect(3), CGRect(x: 510, y: 10, width: 490, height: 780))
        XCTAssertTrue(controller.workspace.contains(2))
    }

    func testOnChangeFiresOnChangeAndNotWithoutOne() {
        let windows = FakeWindows()
        for id in [1, 2, 3] { windows.add(id) }
        let controller = Controller(windows: windows, hotkeys: FakeHotkeys(), config: config)
        var snapshots: [WorkspaceSnapshot] = []
        controller.onChange = { snapshots.append($0) }
        controller.start()
        XCTAssertEqual(snapshots.count, 1)

        controller.relayout()
        XCTAssertEqual(snapshots.count, 1)

        controller.handle(.focusLeft)
        XCTAssertEqual(snapshots.count, 2)
        XCTAssertEqual(snapshots[1].workspace.focusedWindow, 2)
    }
}
```

- [ ] **Step 3: Ejecutar y ver que falla**

Run: `swift test --filter ControllerAnimationTests`
Expected: error de compilación `extra arguments at positions ... in call` (el `Controller` aún no acepta `animator`).

- [ ] **Step 4: Implementar en el Controller**

Sustituir `Sources/LinkrCore/Controller.swift` por:

```swift
import CoreGraphics
import LayoutEngine

public struct WorkspaceSnapshot: Equatable, Sendable {
    public let workspace: Workspace
    public let viewport: CGRect
    public let config: LayoutConfig

    public init(workspace: Workspace, viewport: CGRect, config: LayoutConfig) {
        self.workspace = workspace
        self.viewport = viewport
        self.config = config
    }
}

@MainActor
public final class Controller {
    public private(set) var workspace = Workspace()
    public private(set) var failedHotkeys: [String] = []
    public var motion = MotionSettings()
    public var onChange: ((WorkspaceSnapshot) -> Void)?

    private let windows: WindowService
    private let hotkeys: HotkeyService
    private let config: LayoutConfig
    private let animator: Animator?
    private let reduceMotion: () -> Bool
    private var needsClamp = false
    private var lastApplied: [WindowID: CGRect] = [:]
    private var animationTargets: [WindowID: CGRect] = [:]
    private var failures: [WindowID: Int] = [:]
    private var lastSnapshot: WorkspaceSnapshot?
    private static let maxFailures = 3
    private static let maxAnimated = 4

    public init(
        windows: WindowService,
        hotkeys: HotkeyService,
        config: LayoutConfig = LayoutConfig(),
        animator: Animator? = nil,
        reduceMotion: @escaping () -> Bool = { false }
    ) {
        self.windows = windows
        self.hotkeys = hotkeys
        self.config = config
        self.animator = animator
        self.reduceMotion = reduceMotion
        animator?.onFrame = { [weak self] frames, finished in
            self?.applyAnimationFrame(frames, finished: finished)
        }
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
            lastApplied[id] = nil
            relayout()
        }
    }

    /// Display parameters changed or the Mac woke up: rewrite everything.
    public func screenChanged() {
        relayout(force: true)
    }

    public func relayout(force: Bool = false) {
        animator?.cancel()
        if force { lastApplied.removeAll() }
        let viewport = windows.usableFrame()
        for id in workspace.allWindows where !windows.isAlive(id) { forget(id) }
        Layout.reveal(&workspace, viewport: viewport, config: config)
        if needsClamp {
            Layout.removeOverscroll(&workspace, viewport: viewport, config: config)
            needsClamp = false
        }

        let targets = Layout.frames(workspace, viewport: viewport, config: config)
        let changed = targets.filter { lastApplied[$0.key] != $0.value }
        let animated = animatedSubset(of: changed, viewport: viewport)

        var dropped = false
        for (id, rect) in changed.sorted(by: { $0.key.rawValue < $1.key.rawValue }) where animated[id] == nil {
            if !write(rect, to: id) { dropped = true }
        }
        if dropped {
            relayout()
            return
        }
        startAnimation(animated)
        emitChange(viewport)
    }

    // MARK: Writing

    /// Returns false when the window was dropped after repeated failures.
    private func write(_ rect: CGRect, to id: WindowID) -> Bool {
        if windows.setFrame(rect, for: id) {
            lastApplied[id] = rect
            failures[id] = nil
            return true
        }
        return !registerFailure(id)
    }

    /// Returns true when the window was dropped.
    private func registerFailure(_ id: WindowID) -> Bool {
        failures[id, default: 0] += 1
        guard failures[id, default: 0] >= Self.maxFailures else { return false }
        forget(id)
        return true
    }

    private func applyAnimationFrame(_ frames: [WindowID: CGRect], finished: Bool) {
        var dropped = false
        for (id, rect) in frames.sorted(by: { $0.key.rawValue < $1.key.rawValue }) {
            guard workspace.contains(id) else { continue }
            if windows.setFrame(rect, for: id) {
                lastApplied[id] = rect
                failures[id] = nil
                continue
            }
            animator?.remove(id)
            if let target = animationTargets[id], windows.setFrame(target, for: id) {
                lastApplied[id] = target
            }
            if registerFailure(id) { dropped = true }
        }
        if dropped { relayout() }
    }

    // MARK: Animation

    /// Windows that slide: same size, same y, not parked in both positions;
    /// at most `maxAnimated`, nearest to the focused column first.
    private func animatedSubset(of changed: [WindowID: CGRect], viewport: CGRect) -> [WindowID: CGRect] {
        guard animator != nil, motion.duration(reduceMotion: reduceMotion()) > 0 else { return [:] }
        let candidates = changed.filter { id, target in
            guard let from = lastApplied[id] else { return false }
            return from.size == target.size
                && abs(from.minY - target.minY) < 0.5
                && !(isOffscreen(from, in: viewport) && isOffscreen(target, in: viewport))
        }
        let focused = workspace.focusedColumn
        let ranked = candidates.keys.sorted { lhs, rhs in
            let (left, right) = (columnDistance(lhs, from: focused), columnDistance(rhs, from: focused))
            return left != right ? left < right : lhs.rawValue < rhs.rawValue
        }
        return Dictionary(uniqueKeysWithValues: ranked.prefix(Self.maxAnimated).map { ($0, candidates[$0]!) })
    }

    private func startAnimation(_ animated: [WindowID: CGRect]) {
        guard let animator, !animated.isEmpty else { return }
        var from: [WindowID: CGRect] = [:]
        for id in animated.keys { from[id] = lastApplied[id] }
        animationTargets = animated
        let duration = motion.duration(reduceMotion: reduceMotion())
        animator.start(Tween(from: from, to: animated, duration: duration))
    }

    private func isOffscreen(_ rect: CGRect, in viewport: CGRect) -> Bool {
        rect.maxX <= viewport.minX + 1 || rect.minX >= viewport.maxX - 1
    }

    private func columnDistance(_ id: WindowID, from focused: Int) -> Int {
        guard let index = workspace.columns.firstIndex(where: { $0.windows.contains(id) }) else { return .max }
        return abs(index - focused)
    }

    // MARK: Model

    private func emitChange(_ viewport: CGRect) {
        let snapshot = WorkspaceSnapshot(workspace: workspace, viewport: viewport, config: config)
        guard snapshot != lastSnapshot else { return }
        lastSnapshot = snapshot
        onChange?(snapshot)
    }

    private func adopt(_ info: WindowInfo) {
        guard info.isManageable else { return }
        workspace.addWindow(info.id)
    }

    private func forget(_ id: WindowID) {
        workspace.removeWindow(id)
        lastApplied[id] = nil
        failures[id] = nil
        needsClamp = true
    }
}
```

- [ ] **Step 5: Ejecutar toda la suite**

Run: `swift test`
Expected: todos pasan (los tests anteriores del `Controller` no cambian porque `animator` es nil por defecto). `Executed 60 tests, with 0 failures`.

Si `testAtMostFourWindowsAnimateAndTheRestJump` falla por posiciones distintas a las calculadas (la secuencia de `cycleWidth` deja el scroll en un valor que el plan no fija), imprime los rects reales de cada ventana antes y después de `handle(.focused(1))`, comprueba a mano qué ventanas son candidatas (mismo tamaño, mismo y, no aparcadas en ambos extremos) y ajusta solo los conjuntos esperados, manteniendo la intención: con más de 4 candidatas, se animan las 4 más cercanas a la columna enfocada y el resto salta.

- [ ] **Step 6: Commit**

```bash
git add Sources/LinkrCore Tests/LinkrCoreTests
git commit -m "feat: animate window scrolling and publish workspace changes"
```

---

### Task 5: Menú con previsualización, ajustes y reloj real

**Files:**
- Create: `Sources/LinkrApp/TimerFrameClock.swift`, `Sources/LinkrApp/MotionSettingsStore.swift`, `Sources/LinkrApp/StripPreviewView.swift`
- Modify: `Sources/LinkrApp/AppDelegate.swift` (sustituir el archivo completo)
- Modify: `Sources/LinkrApp/AXWindowService.swift` (`setFrame`)

**Interfaces:**
- Consumes: `Controller` (con `animator`, `motion`, `onChange`), `Animator`, `FrameClock`, `StripPreview`, `MotionSettings`, `WorkspaceSnapshot`.
- Produces: la app con preview animada y ajustes en el menú. Sin tests unitarios (depende de AppKit); se verifica compilando y con la prueba de humo (Task 6).

- [ ] **Step 1: Reloj real**

`Sources/LinkrApp/TimerFrameClock.swift`:

```swift
import Foundation
import LinkrCore

@MainActor
final class TimerFrameClock: FrameClock {
    private var timer: Timer?

    func start(_ tick: @escaping () -> Void) {
        stop()
        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { _ in
            MainActor.assumeIsolated { tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }
}
```

- [ ] **Step 2: Guardado de ajustes**

`Sources/LinkrApp/MotionSettingsStore.swift`:

```swift
import Foundation
import LinkrCore

struct MotionSettingsStore {
    private let defaults = UserDefaults.standard
    private let speedKey = "motionSpeed"
    private let reduceKey = "respectReduceMotion"

    var settings: MotionSettings {
        get {
            let speed = defaults.string(forKey: speedKey).flatMap(MotionSpeed.init(rawValue:)) ?? .normal
            let respect = defaults.object(forKey: reduceKey) as? Bool ?? true
            return MotionSettings(speed: speed, respectReduceMotion: respect)
        }
        nonmutating set {
            defaults.set(newValue.speed.rawValue, forKey: speedKey)
            defaults.set(newValue.respectReduceMotion, forKey: reduceKey)
        }
    }
}
```

- [ ] **Step 3: Vista de la previsualización**

`Sources/LinkrApp/StripPreviewView.swift`:

```swift
import AppKit
import LayoutEngine
import QuartzCore

@MainActor
final class StripPreviewView: NSView {
    /// Seconds; 0 jumps straight to the new state.
    var animationDuration: Double = 0.18

    private var shown = StripPreview(items: [], frameX: 0, frameWidth: 1)
    private var from = StripPreview(items: [], frameX: 0, frameWidth: 1)
    private var target = StripPreview(items: [], frameX: 0, frameWidth: 1)
    private var startTime = 0.0
    private var timer: Timer?
    private var isLive = false

    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
    }

    required init?(coder: NSCoder) {
        fatalError("not used")
    }

    func menuDidOpen() {
        isLive = true
    }

    func menuDidClose() {
        isLive = false
        stopTimer()
        shown = target
        needsDisplay = true
    }

    func show(_ preview: StripPreview) {
        target = preview
        guard isLive, animationDuration > 0 else {
            stopTimer()
            shown = preview
            needsDisplay = true
            return
        }
        from = shown
        startTime = CACurrentMediaTime()
        guard timer == nil else { return }
        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.step() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func step() {
        let t = (CACurrentMediaTime() - startTime) / animationDuration
        if t >= 1 {
            shown = target
            stopTimer()
        } else {
            shown = from.interpolated(to: target, progress: Easing.easeOut(t))
        }
        needsDisplay = true
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    override func draw(_ dirtyRect: NSRect) {
        let inset: CGFloat = 12
        let strip = NSRect(x: inset, y: 8, width: bounds.width - 2 * inset, height: 52)
        let bar = NSRect(x: inset, y: 70, width: bounds.width - 2 * inset, height: 5)

        for item in shown.items {
            let rect = NSRect(
                x: strip.minX + item.rect.minX * strip.width,
                y: strip.minY + item.rect.minY * strip.height,
                width: item.rect.width * strip.width,
                height: item.rect.height * strip.height
            ).insetBy(dx: 1, dy: 1)
            let path = NSBezierPath(roundedRect: rect, xRadius: 3, yRadius: 3)
            let base: NSColor = item.isFocused ? .controlAccentColor : .secondaryLabelColor
            base.withAlphaComponent(item.isVisible ? 0.9 : 0.35).setFill()
            path.fill()
            if item.isFocused {
                NSColor.labelColor.setStroke()
                path.lineWidth = 1.5
                path.stroke()
            }
        }

        let frameRect = NSRect(
            x: strip.minX + shown.frameX * strip.width,
            y: strip.minY - 4,
            width: shown.frameWidth * strip.width,
            height: strip.height + 8
        )
        let framePath = NSBezierPath(roundedRect: frameRect, xRadius: 5, yRadius: 5)
        NSColor.labelColor.withAlphaComponent(0.6).setStroke()
        framePath.lineWidth = 1.5
        framePath.stroke()

        NSColor.quaternaryLabelColor.setFill()
        NSBezierPath(roundedRect: bar, xRadius: 2.5, yRadius: 2.5).fill()
        let thumbWidth = min(max(shown.frameWidth, 0.02), 1) * bar.width
        let thumbX = bar.minX + min(max(shown.frameX, 0), max(1 - shown.frameWidth, 0)) * bar.width
        NSColor.secondaryLabelColor.setFill()
        NSBezierPath(
            roundedRect: NSRect(x: thumbX, y: bar.minY, width: thumbWidth, height: bar.height),
            xRadius: 2.5,
            yRadius: 2.5
        ).fill()
    }
}
```

- [ ] **Step 4: AppDelegate con preview, ajustes y menú**

Sustituir `Sources/LinkrApp/AppDelegate.swift` por:

```swift
import AppKit
import ApplicationServices
import LayoutEngine
import LinkrCore
import QuartzCore
import ServiceManagement

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let previewView = StripPreviewView(frame: NSRect(x: 0, y: 0, width: 280, height: 84))
    private let settingsStore = MotionSettingsStore()
    private var controller: Controller?
    private var lastSnapshot: WorkspaceSnapshot?
    private var statusLineItem: NSMenuItem?
    private var permissionTimer: Timer?
    private var observers: [NSObjectProtocol] = []

    private var reduceMotion: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem.button?.image = NSImage(
            systemSymbolName: "rectangle.split.3x1",
            accessibilityDescription: "Linkr"
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
        // Registers Linkr in the Accessibility list so the user only has to flip the switch.
        _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)

        let alert = NSAlert()
        alert.messageText = "Linkr necesita permiso de Accesibilidad"
        alert.informativeText = "Para mover ventanas, activa Linkr en Ajustes del Sistema > Privacidad y seguridad > Accesibilidad. Linkr empezará solo cuando lo concedas."
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
        guard controller == nil else { return }
        let animator = Animator(clock: TimerFrameClock(), now: { CACurrentMediaTime() })
        let controller = Controller(
            windows: AXWindowService(),
            hotkeys: CarbonHotkeyService(),
            animator: animator,
            reduceMotion: { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
        )
        controller.motion = settingsStore.settings
        controller.onChange = { [weak self] snapshot in self?.workspaceChanged(snapshot) }
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

    private func workspaceChanged(_ snapshot: WorkspaceSnapshot) {
        lastSnapshot = snapshot
        previewView.animationDuration = settingsStore.settings.previewDuration(reduceMotion: reduceMotion)
        previewView.show(StripPreview(workspace: snapshot.workspace, viewport: snapshot.viewport, config: snapshot.config))
        statusLineItem?.title = statusText()
    }

    // MARK: Menu

    private func rebuildMenu() {
        let menu = NSMenu()
        menu.delegate = self

        if controller != nil {
            let preview = NSMenuItem()
            preview.view = previewView
            menu.addItem(preview)
        }

        let status = NSMenuItem(title: statusText(), action: nil, keyEquivalent: "")
        status.isEnabled = false
        statusLineItem = status
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
        if controller != nil {
            let settings = settingsStore.settings

            let speedItem = NSMenuItem(title: "Velocidad de animación", action: nil, keyEquivalent: "")
            let speedMenu = NSMenu()
            for (speed, title) in [(MotionSpeed.fast, "Rápida"), (.normal, "Normal"), (.off, "Desactivada")] {
                let item = NSMenuItem(title: title, action: #selector(selectSpeed(_:)), keyEquivalent: "")
                item.representedObject = speed.rawValue
                item.state = settings.speed == speed ? .on : .off
                item.target = self
                speedMenu.addItem(item)
            }
            speedItem.submenu = speedMenu
            menu.addItem(speedItem)

            let reduce = NSMenuItem(title: "Respetar Reducir movimiento del sistema", action: #selector(toggleReduceMotion), keyEquivalent: "")
            reduce.state = settings.respectReduceMotion ? .on : .off
            reduce.target = self
            menu.addItem(reduce)
        }

        let login = NSMenuItem(title: "Iniciar al arrancar", action: #selector(toggleLogin), keyEquivalent: "")
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        login.target = self
        menu.addItem(login)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Salir de Linkr", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

        for item in menu.items where item.action == #selector(openAccessibilitySettings) {
            item.target = self
        }
        statusItem.menu = menu
    }

    private func statusText() -> String {
        guard controller != nil else { return "Esperando permiso de Accesibilidad" }
        guard let workspace = lastSnapshot?.workspace else { return "Activo" }
        return "Activo · \(workspace.columns.count) columnas · \(workspace.allWindows.count) ventanas"
    }

    func menuWillOpen(_ menu: NSMenu) {
        previewView.menuDidOpen()
    }

    func menuDidClose(_ menu: NSMenu) {
        previewView.menuDidClose()
    }

    @objc private func selectSpeed(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let speed = MotionSpeed(rawValue: raw) else { return }
        var settings = settingsStore.settings
        settings.speed = speed
        apply(settings)
    }

    @objc private func toggleReduceMotion() {
        var settings = settingsStore.settings
        settings.respectReduceMotion.toggle()
        apply(settings)
    }

    private func apply(_ settings: MotionSettings) {
        settingsStore.settings = settings
        controller?.motion = settings
        rebuildMenu()
    }

    @objc private func toggleLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            NSLog("Linkr: login item change failed: \(error)")
        }
        rebuildMenu()
    }
}
```

- [ ] **Step 5: No reescribir el tamaño si no cambia**

En `Sources/LinkrApp/AXWindowService.swift`, añadir junto a `private var nextID = 1`:

```swift
    private var lastWrittenSize: [WindowID: CGSize] = [:]
```

y sustituir `setFrame` por:

```swift
    func setFrame(_ rect: CGRect, for id: WindowID) -> Bool {
        guard let entry = entries[id] else { return false }
        var origin = rect.origin
        var size = rect.size
        guard let position = AXValueCreate(.cgPoint, &origin),
              let dimensions = AXValueCreate(.cgSize, &size) else { return false }
        // Animation frames only move windows; skip the second AX call when the size is unchanged.
        var sizeResult = AXError.success
        if lastWrittenSize[id] != rect.size {
            sizeResult = AXUIElementSetAttributeValue(entry.element, kAXSizeAttribute as CFString, dimensions)
            if sizeResult == .success { lastWrittenSize[id] = rect.size }
        }
        let positionResult = AXUIElementSetAttributeValue(entry.element, kAXPositionAttribute as CFString, position)
        return sizeResult == .success && positionResult == .success
    }
```

Y en los dos sitios donde se elimina una ventana de `entries` (`entries[id] = nil`, en `forget(pid:)` y en el caso `kAXUIElementDestroyedNotification` de `handle`), añadir justo después `lastWrittenSize[id] = nil`.

- [ ] **Step 6: Compilar y ejecutar las pruebas**

Run: `swift build 2>&1 | grep -E "warning|error|Build"; swift test 2>&1 | grep -E "Executed .* tests" | tail -2`
Expected: `Build complete!` sin warnings ni errores, y `Executed 60 tests, with 0 failures`.

Si el compilador rechaza algún símbolo concreto (por ejemplo, el cierre de `Timer` con `MainActor.assumeIsolated`), aplica el cambio mínimo que mantenga el comportamiento y anótalo en el informe.

- [ ] **Step 7: Commit**

```bash
git add Sources/LinkrApp
git commit -m "feat: add animated strip preview and motion settings to the menu"
```

---

### Task 6: Documentación y prueba de humo

**Files:**
- Modify: `docs/smoke-test.md`
- Modify: `docs/superpowers/specs/2026-10-24-linkr-animation-preview-design.md`

**Interfaces:** ninguna.

- [ ] **Step 1: Añadir pasos a la prueba de humo**

Al final de `docs/smoke-test.md`, antes de la sección "Limitaciones conocidas" si existe (si no, al final), añadir:

```markdown
## Animación y previsualización

1. Abre el menú de Linkr. Arriba debe verse la tira dibujada, con el marco de pantalla y la barra de posición debajo, y la línea "Activo · N columnas · M ventanas".
2. Con tres ventanas de TextEdit, pulsa ⌃⌥H / ⌃⌥L: las ventanas se deslizan en ~0,18 s en vez de saltar. No deben quedar a medio camino ni parpadear.
3. Abre el menú y, con él abierto, pulsa ⌃⌥H / ⌃⌥L: el marco y la barra de la previsualización se mueven con suavidad.
4. Cierra el menú, cambia el foco varias veces y ábrelo: la previsualización ya muestra el estado actual, sin animar.
5. Menú > "Velocidad de animación": con "Rápida" el deslizamiento es más corto; con "Desactivada" las ventanas saltan, pero la previsualización sigue animándose.
6. Activa Ajustes del Sistema > Accesibilidad > Pantalla > "Reducir movimiento": con "Respetar Reducir movimiento del sistema" marcado, todo salta. Desmárcalo y vuelve a animarse.
7. Cambia el ancho con ⌃⌥R: la ventana enfocada cambia de ancho al instante (no se anima).
8. Abre una app pesada (por ejemplo un navegador con varias pestañas) junto a TextEdit y repite el paso 2: si se ven tirones, anótalo; el salto automático por frame lento debe evitar que se quede a medias.
```

- [ ] **Step 2: Actualizar la spec**

En `docs/superpowers/specs/2026-10-24-linkr-animation-preview-design.md`, sección "Ajustes", sustituir el último punto:

```
- Durante el desarrollo, hasta el paso 4 del orden de construcción, la velocidad por defecto es "Desactivada" para no cambiar el comportamiento ya probado.
```

por:

```
- La velocidad por defecto de `MotionSettings()` en `LinkrCore` es "Desactivada", para que las pruebas del `Controller` sin animador no cambien. El guardado de ajustes de la app usa "Normal" como valor por defecto desde el principio.
```

- [ ] **Step 3: Comprobar y commit**

Run: `swift test 2>&1 | grep -E "Executed .* tests" | tail -1`
Expected: `Executed 60 tests, with 0 failures`.

```bash
git add docs
git commit -m "docs: add animation and preview smoke steps"
```

---

## Self-review

- **Cobertura de la spec:** `Tween`/`easeOut` (T1); `stripRects` y geometría del preview (T2); `Animator`, `FrameClock` y `MotionSettings` con duraciones, `previewDuration` y "reducir movimiento" (T3); reparto animado/inmediato, máximo 4 ventanas, aparcadas saltan, frame lento, retomar desde la posición actual, fallo de una ventana cancela solo esa, `onChange` sin cambio no emite (T4); reloj real, ajustes en `UserDefaults`, vista, menú con velocidad y reducir movimiento, timer en modo `.common`, apertura sin animar (T5); pruebas manuales y documentación (T6).
- **Placeholders:** ninguno; cada paso de código lleva el código. La única parte condicional es el ajuste de números de `testAtMostFourWindowsAnimate…`, con criterio explícito.
- **Consistencia de tipos:** `Tween(from:to:duration:)`, `Animator(clock:now:slowFrameLimit:)`, `Animator.onFrame`, `Controller(windows:hotkeys:config:animator:reduceMotion:)`, `MotionSettings(speed:respectReduceMotion:)`, `WorkspaceSnapshot(workspace:viewport:config:)` y `StripPreview(workspace:viewport:config:)` se usan con las mismas firmas en todas las tareas.
- **Riesgos que solo la prueba de humo confirma:** fluidez real con apps lentas (el salto por frame lento lo acota), si macOS reajusta ventanas parcialmente fuera de pantalla durante el movimiento, que el `Timer` del preview en modo `.common` anime con el menú abierto, y que el timer se detenga al cerrarlo.
