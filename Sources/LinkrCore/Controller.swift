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
            if animator?.isAnimating == true, id == workspace.focusedWindow { return }
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
