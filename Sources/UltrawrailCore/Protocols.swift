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

public struct WindowDescription: Equatable, Sendable {
    public let appName: String
    public let pid: Int32
    public let bundleID: String?
    public init(appName: String, pid: Int32, bundleID: String? = nil) {
        self.appName = appName
        self.pid = pid
        self.bundleID = bundleID
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
    /// Returns false when the write failed. `moveOnly` writes the position and skips the size
    /// (intermediate animation frames); otherwise position and size are both written.
    func setFrame(_ rect: CGRect, for id: WindowID, moveOnly: Bool) -> Bool
    func focus(_ id: WindowID)
    func isAlive(_ id: WindowID) -> Bool
    func describe(_ id: WindowID) -> WindowDescription?
    /// The system window number, used to capture a thumbnail.
    func windowNumber(for id: WindowID) -> UInt32?
    func isMinimized(_ id: WindowID) -> Bool
    func restore(_ id: WindowID)
    /// Looks again for windows that were missed when their app was first observed (slow apps).
    func rescan()
}

public extension WindowService {
    /// True for windows hidden in the Dock; they can be brought back with `restore`.
    func isMinimized(_ id: WindowID) -> Bool { false }
    func restore(_ id: WindowID) {}
    func rescan() {}
    func windowNumber(for id: WindowID) -> UInt32? { nil }
}

@MainActor
public protocol HotkeyService: AnyObject {
    var onCommand: ((Command) -> Void)? { get set }
    /// Replaces every registered shortcut with `shortcuts`.
    /// Returns a description of each shortcut that could not be registered.
    func register(_ shortcuts: [ResolvedShortcut]) -> [String]
}
