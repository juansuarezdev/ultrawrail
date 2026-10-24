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
    public init(appName: String, pid: Int32) {
        self.appName = appName
        self.pid = pid
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
}

@MainActor
public protocol HotkeyService: AnyObject {
    var onCommand: ((Command) -> Void)? { get set }
    /// Returns a description of each shortcut that could not be registered.
    func register() -> [String]
}
