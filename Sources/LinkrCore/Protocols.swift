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
