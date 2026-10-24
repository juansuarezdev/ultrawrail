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
