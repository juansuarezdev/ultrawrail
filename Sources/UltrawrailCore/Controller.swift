import CoreGraphics
import Foundation
import LayoutEngine

public struct WorkspaceSnapshot: Equatable, Sendable {
    public let workspace: Workspace
    public let viewport: CGRect
    public let config: LayoutConfig
    public let page: Int
    public let pageCount: Int

    public init(workspace: Workspace, viewport: CGRect, config: LayoutConfig, page: Int = 0, pageCount: Int = 1) {
        self.workspace = workspace
        self.viewport = viewport
        self.config = config
        self.page = page
        self.pageCount = pageCount
    }
}

@MainActor
public final class Controller {
    public static let maxPages = 9
    public private(set) var pages: [Workspace] = [Workspace()]
    public private(set) var currentPage = 0
    /// The current page's strip.
    public private(set) var workspace: Workspace {
        get { pages[currentPage] }
        set { pages[currentPage] = newValue }
    }
    public private(set) var failedHotkeys: [String] = []
    public var motion = MotionSettings()
    public var onChange: ((WorkspaceSnapshot) -> Void)?
    public var placement: PlacementMode = .automatic {
        didSet { if placement == .automatic, oldValue == .manual { adoptAllPending() } }
    }
    public var pendingCount: Int { pending.count }
    public var onShowTemplates: (() -> Void)?
    public var managedWindows: [WindowID] { workspace.allWindows }
    private var allPageWindows: [WindowID] { pages.flatMap(\.allWindows) }

    private let windows: WindowService
    private let hotkeys: HotkeyService
    public var config: LayoutConfig {
        didSet {
            if config != oldValue {
                needsClamp = true
                relayout(force: true)
            }
        }
    }
    public var newColumnWidth: Double {
        get { workspace.newColumnWidth }
        set { for index in pages.indices { pages[index].newColumnWidth = newValue } }
    }
    private let animator: Animator?
    private let reduceMotion: () -> Bool
    private let now: @MainActor () -> TimeInterval
    private let echoSuppression: TimeInterval
    private var suppressFocusEchoUntil: TimeInterval = 0
    private var needsClamp = false
    private var lastApplied: [WindowID: CGRect] = [:]
    private var animationTargets: [WindowID: CGRect] = [:]
    private var failures: [WindowID: Int] = [:]
    private var pending: [WindowID: WindowInfo] = [:]
    private var pendingFocus: WindowID?
    private var lastSnapshot: WorkspaceSnapshot?
    private static let maxFailures = 3
    private static let maxAnimated = 4

    public init(
        windows: WindowService,
        hotkeys: HotkeyService,
        config: LayoutConfig = LayoutConfig(),
        animator: Animator? = nil,
        reduceMotion: @escaping () -> Bool = { false },
        now: @escaping @MainActor () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
        echoSuppression: TimeInterval = 0.4
    ) {
        self.now = now
        self.echoSuppression = echoSuppression
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

    /// Focuses a window and ignores the AX echo of that focus for a short while.
    private func focusWindow(_ id: WindowID) {
        suppressFocusEchoUntil = now() + echoSuppression
        windows.focus(id)
    }

    public func describe(_ id: WindowID) -> WindowDescription? { windows.describe(id) }

    /// Gives keyboard focus back to the focused window (used when a panel closes without changes).
    public func refocus() {
        if let id = workspace.focusedWindow { focusWindow(id) }
    }

    public func applyTemplate(_ template: Template, assignment: [WindowID?]) {
        let onPage = Set(workspace.allWindows)
        guard assignment.allSatisfy({ $0.map(onPage.contains) ?? true }) else { return }
        workspace.apply(template, assignment: assignment, viewport: windows.usableFrame(), config: config)
        relayout()
        if let id = workspace.focusedWindow { focusWindow(id) }
    }

    public func handle(_ command: Command) {
        if command == .showTemplates { onShowTemplates?(); return }
        if command == .adoptWindow { adoptPending(); return }
        switch command {
        case .nextPage:
            if let target = nextPageTarget() { switchPage(to: target); focusCurrent() }
            return
        case .previousPage:
            if currentPage > 0 { switchPage(to: currentPage - 1); focusCurrent() }
            return
        case .moveWindowToNextPage:
            if let id = workspace.focusedWindow, let target = nextPageTarget() { moveFocusedWindow(id, to: target) }
            return
        case .moveWindowToPreviousPage:
            if let id = workspace.focusedWindow, currentPage > 0 { moveFocusedWindow(id, to: currentPage - 1) }
            return
        default:
            break
        }
        workspace.perform(command, viewport: windows.usableFrame(), config: config)
        relayout()
        if let id = workspace.focusedWindow { focusWindow(id) }
    }

    public func handle(_ event: WindowEvent) {
        switch event {
        case .opened(let info):
            if placement == .manual, info.isManageable, !allPageWindows.contains(info.id) {
                pending[info.id] = info
                pendingFocus = info.id
                return
            }
            adopt(info)
            relayout()
        case .closed(let id):
            if pending.removeValue(forKey: id) != nil {
                if pendingFocus == id { pendingFocus = nil }
                return
            }
            forget(id)
            relayout()
        case .focused(let id):
            if pending[id] != nil {
                pendingFocus = id
                return
            }
            if !workspace.contains(id), let index = pages.firstIndex(where: { $0.contains(id) }) {
                if now() < suppressFocusEchoUntil { return }
                pages[index].focus(window: id)
                switchPage(to: index)
                return
            }
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
        var sizes: [WindowID: CGSize] = [:]
        if force {
            for (id, rect) in lastApplied { sizes[id] = rect.size }
            lastApplied.removeAll()
        }
        let viewport = windows.usableFrame()
        for id in allPageWindows where !windows.isAlive(id) { forget(id) }
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
        if force, !parkInactivePages(sizes: sizes, viewport: viewport) { dropped = true }
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
        if windows.setFrame(rect, for: id, moveOnly: false) {
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
            if windows.setFrame(rect, for: id, moveOnly: !finished) {
                lastApplied[id] = rect
                failures[id] = nil
                continue
            }
            animator?.remove(id)
            if let target = animationTargets[id], windows.setFrame(target, for: id, moveOnly: false) {
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
        let snapshot = WorkspaceSnapshot(workspace: workspace, viewport: viewport, config: config,
                                     page: currentPage, pageCount: pages.count)
        guard snapshot != lastSnapshot else { return }
        lastSnapshot = snapshot
        onChange?(snapshot)
    }

    /// Places the pending window that was opened or focused last into the strip.
    private func adoptPending() {
        guard let id = pendingFocus ?? pending.keys.first, let info = pending[id] else { return }
        pending[id] = nil
        pendingFocus = nil
        guard windows.isAlive(id) else { return }
        adopt(info)
        relayout()
        focusWindow(id)
    }

    private func adoptAllPending() {
        let infos = pending.values.sorted { $0.id.rawValue < $1.id.rawValue }
        pending = [:]
        pendingFocus = nil
        for info in infos where windows.isAlive(info.id) { adopt(info) }
        relayout()
    }

    private func adopt(_ info: WindowInfo) {
        guard info.isManageable, !allPageWindows.contains(info.id) else { return }
        workspace.addWindow(info.id)
    }

    // MARK: Pages

    /// Index of the page `.nextPage` goes to, appending an empty one when allowed.
    private func nextPageTarget() -> Int? {
        if currentPage + 1 < pages.count { return currentPage + 1 }
        guard !workspace.allWindows.isEmpty, pages.count < Self.maxPages else { return nil }
        var page = Workspace()
        page.newColumnWidth = workspace.newColumnWidth
        pages.append(page)
        return pages.count - 1
    }

    private func switchPage(to target: Int) {
        animator?.cancel()
        currentPage = target
        suppressFocusEchoUntil = now() + echoSuppression
        while pages.count > 1, pages.count - 1 != currentPage, pages[pages.count - 1].allWindows.isEmpty {
            pages.removeLast()
        }
        relayout(force: true)
    }

    /// Moves every inactive page's windows off the right edge, keeping their size.
    /// Returns false when some window was dropped after repeated failures.
    private func parkInactivePages(sizes: [WindowID: CGSize], viewport: CGRect) -> Bool {
        var ok = true
        for (index, page) in pages.enumerated() where index != currentPage {
            for id in page.allWindows {
                let size = sizes[id]
                let rect = CGRect(x: viewport.maxX - 1, y: viewport.minY,
                                  width: size?.width ?? 200, height: size?.height ?? viewport.height)
                if !write(rect, to: id) { ok = false }
            }
        }
        return ok
    }

    /// Puts every inactive page's windows where its own layout would place them (used on quit).
    public func restoreParkedWindows() {
        let viewport = windows.usableFrame()
        for (index, page) in pages.enumerated() where index != currentPage {
            for (id, rect) in Layout.frames(page, viewport: viewport, config: config) {
                _ = windows.setFrame(rect, for: id, moveOnly: false)
            }
        }
    }

    private func moveFocusedWindow(_ id: WindowID, to target: Int) {
        pages[currentPage].removeWindow(id)
        pages[target].addWindow(id)
        needsClamp = true
        switchPage(to: target)
        focusWindow(id)
    }

    private func focusCurrent() {
        if let id = workspace.focusedWindow { focusWindow(id) }
    }

    private func forget(_ id: WindowID) {
        for index in pages.indices { pages[index].removeWindow(id) }
        lastApplied[id] = nil
        failures[id] = nil
        needsClamp = true
    }
}
