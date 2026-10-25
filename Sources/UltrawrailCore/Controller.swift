import CoreGraphics
import Foundation
import LayoutEngine

public struct WorkspaceSnapshot: Equatable, Sendable {
    public let workspace: Workspace
    public let viewport: CGRect
    public let config: LayoutConfig
    public let page: Int
    public let pageCount: Int
    public let zone: Int
    public let zoneCount: Int

    public init(workspace: Workspace, viewport: CGRect, config: LayoutConfig, page: Int = 0, pageCount: Int = 1,
                zone: Int = 0, zoneCount: Int = 1) {
        self.workspace = workspace
        self.viewport = viewport
        self.config = config
        self.page = page
        self.pageCount = pageCount
        self.zone = zone
        self.zoneCount = zoneCount
    }
}

/// A vertical slice of the display with its own pages.
struct Zone: Equatable {
    var pages: [Workspace] = [Workspace()]
    var currentPage = 0
}

@MainActor
public final class Controller {
    public static let maxPages = 9
    public static let maxZones = 3
    private(set) var zones: [Zone] = [Zone()]
    public private(set) var focusedZone = 0
    /// Number of zones the display is split into (1...3). Shrinking moves the windows of the
    /// removed zones to the last remaining zone's current page.
    public var zoneCount: Int {
        get { zones.count }
        set {
            let count = min(max(newValue, 1), Self.maxZones)
            guard count != zones.count else { return }
            resizeZones(to: count)
            needsClamp = true
            relayout(force: true)
        }
    }
    /// The focused zone's pages.
    public private(set) var pages: [Workspace] {
        get { zones[focusedZone].pages }
        set { zones[focusedZone].pages = newValue }
    }
    public private(set) var currentPage: Int {
        get { zones[focusedZone].currentPage }
        set { zones[focusedZone].currentPage = newValue }
    }
    /// The focused zone's current strip.
    public private(set) var workspace: Workspace {
        get { zones[focusedZone].pages[zones[focusedZone].currentPage] }
        set { zones[focusedZone].pages[zones[focusedZone].currentPage] = newValue }
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
    private var allPageWindows: [WindowID] { zones.flatMap { $0.pages.flatMap(\.allWindows) } }

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
        set {
            for zone in zones.indices {
                for page in zones[zone].pages.indices { zones[zone].pages[page].newColumnWidth = newValue }
            }
        }
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
        workspace.apply(template, assignment: assignment, viewport: focusedViewport(), config: config)
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
        case .focusZoneLeft:
            focusZone(focusedZone - 1)
            return
        case .focusZoneRight:
            focusZone(focusedZone + 1)
            return
        case .moveWindowToZoneLeft:
            if let id = workspace.focusedWindow { moveFocusedWindow(id, toZone: focusedZone - 1) }
            return
        case .moveWindowToZoneRight:
            if let id = workspace.focusedWindow { moveFocusedWindow(id, toZone: focusedZone + 1) }
            return
        default:
            break
        }
        workspace.perform(command, viewport: focusedViewport(), config: config)
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
            var switchedZone = false
            if !workspace.contains(id), let (zone, page) = locate(id) {
                if page != zones[zone].currentPage {
                    if now() < suppressFocusEchoUntil { return }
                    zones[zone].pages[page].focus(window: id)
                    focusedZone = zone
                    switchPage(to: page)
                    return
                }
                focusedZone = zone
                switchedZone = true
            }
            guard workspace.contains(id) else { return }
            if !switchedZone, animator?.isAnimating == true, id == workspace.focusedWindow { return }
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
        let full = windows.usableFrame()
        for id in allPageWindows where !windows.isAlive(id) { forget(id) }
        var changed: [WindowID: CGRect] = [:]
        var animated: [WindowID: CGRect] = [:]
        for zone in zones.indices {
            let viewport = zoneViewport(zone, in: full)
            let page = zones[zone].currentPage
            Layout.reveal(&zones[zone].pages[page], viewport: viewport, config: config)
            if needsClamp {
                Layout.removeOverscroll(&zones[zone].pages[page], viewport: viewport, config: config)
            }
            let targets = Layout.frames(zones[zone].pages[page], viewport: viewport, config: config)
            let zoneChanged = targets.filter { lastApplied[$0.key] != $0.value }
            changed.merge(zoneChanged) { $1 }
            animated.merge(animatedSubset(of: zoneChanged, in: zones[zone].pages[page], viewport: viewport)) { $1 }
        }
        needsClamp = false

        var dropped = false
        for (id, rect) in changed.sorted(by: { $0.key.rawValue < $1.key.rawValue }) where animated[id] == nil {
            if !write(rect, to: id) { dropped = true }
        }
        if force, !parkInactivePages(sizes: sizes, full: full) { dropped = true }
        if dropped {
            relayout()
            return
        }
        startAnimation(animated)
        emitChange(zoneViewport(focusedZone, in: full))
    }

    // MARK: Zones

    /// Zone `index` covers an equal-width vertical slice of `full`.
    private func zoneViewport(_ index: Int, in full: CGRect) -> CGRect {
        let width = full.width / CGFloat(zones.count)
        return CGRect(x: full.minX + CGFloat(index) * width, y: full.minY, width: width, height: full.height)
    }

    private func focusedViewport() -> CGRect { zoneViewport(focusedZone, in: windows.usableFrame()) }

    private func resizeZones(to count: Int) {
        if count > zones.count {
            let width = newColumnWidth
            while zones.count < count {
                var zone = Zone()
                zone.pages[0].newColumnWidth = width
                zones.append(zone)
            }
            return
        }
        let moved = zones[count...].flatMap { $0.pages.flatMap(\.allWindows) }
        zones.removeLast(zones.count - count)
        let last = count - 1
        let page = zones[last].currentPage
        for id in moved { zones[last].pages[page].addWindow(id) }
        focusedZone = min(focusedZone, last)
    }

    /// Zone and page holding `id`.
    private func locate(_ id: WindowID) -> (zone: Int, page: Int)? {
        for (zone, value) in zones.enumerated() {
            if let page = value.pages.firstIndex(where: { $0.contains(id) }) { return (zone, page) }
        }
        return nil
    }

    private func focusZone(_ target: Int) {
        guard zones.indices.contains(target), target != focusedZone else { return }
        focusedZone = target
        relayout()
        focusCurrent()
    }

    private func moveFocusedWindow(_ id: WindowID, toZone target: Int) {
        guard zones.indices.contains(target), target != focusedZone else { return }
        workspace.removeWindow(id)
        focusedZone = target
        workspace.addWindow(id)
        needsClamp = true
        relayout()
        focusWindow(id)
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
            guard zones.contains(where: { $0.pages[$0.currentPage].contains(id) }) else { continue }
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
    private func animatedSubset(of changed: [WindowID: CGRect], in strip: Workspace,
                                viewport: CGRect) -> [WindowID: CGRect] {
        guard animator != nil, motion.duration(reduceMotion: reduceMotion()) > 0 else { return [:] }
        let candidates = changed.filter { id, target in
            guard let from = lastApplied[id] else { return false }
            return from.size == target.size
                && abs(from.minY - target.minY) < 0.5
                && !(isOffscreen(from, in: viewport) && isOffscreen(target, in: viewport))
        }
        let focused = strip.focusedColumn
        let ranked = candidates.keys.sorted { lhs, rhs in
            let (left, right) = (columnDistance(lhs, in: strip, from: focused),
                                 columnDistance(rhs, in: strip, from: focused))
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

    private func columnDistance(_ id: WindowID, in strip: Workspace, from focused: Int) -> Int {
        guard let index = strip.columns.firstIndex(where: { $0.windows.contains(id) }) else { return .max }
        return abs(index - focused)
    }

    // MARK: Model

    private func emitChange(_ viewport: CGRect) {
        let snapshot = WorkspaceSnapshot(workspace: workspace, viewport: viewport, config: config,
                                     page: currentPage, pageCount: pages.count,
                                     zone: focusedZone, zoneCount: zones.count)
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

    /// Moves every inactive page's windows off the right edge of the whole display, keeping their size.
    /// Returns false when some window was dropped after repeated failures.
    private func parkInactivePages(sizes: [WindowID: CGSize], full: CGRect) -> Bool {
        var ok = true
        for (zone, value) in zones.enumerated() {
            let viewport = zoneViewport(zone, in: full)
            for (index, page) in value.pages.enumerated() where index != value.currentPage {
                for id in page.allWindows {
                    let size = sizes[id]
                    let rect = CGRect(x: full.maxX - 1, y: viewport.minY,
                                      width: size?.width ?? 200, height: size?.height ?? viewport.height)
                    if !write(rect, to: id) { ok = false }
                }
            }
        }
        return ok
    }

    /// Puts every inactive page's windows where its own layout would place them (used on quit).
    public func restoreParkedWindows() {
        let full = windows.usableFrame()
        for (zone, value) in zones.enumerated() {
            let viewport = zoneViewport(zone, in: full)
            for (index, page) in value.pages.enumerated() where index != value.currentPage {
                for (id, rect) in Layout.frames(page, viewport: viewport, config: config) {
                    _ = windows.setFrame(rect, for: id, moveOnly: false)
                }
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
        for zone in zones.indices {
            for page in zones[zone].pages.indices { zones[zone].pages[page].removeWindow(id) }
        }
        lastApplied[id] = nil
        failures[id] = nil
        needsClamp = true
    }
}
