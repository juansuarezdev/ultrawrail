import AppKit
import ApplicationServices
import LayoutEngine
import LinkrCore

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
        var adopted: Bool
    }

    private var entries: [WindowID: Entry] = [:]
    private var observers: [pid_t: AXObserver] = [:]
    private var nextID = 1
    private let ownPID = ProcessInfo.processInfo.processIdentifier

    // MARK: WindowService

    func start() {
        // Window elements inherit the system-wide timeout, so a hung app cannot block the main thread for long.
        AXUIElementSetMessagingTimeout(AXUIElementCreateSystemWide(), 0.3)
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

    func setFrame(_ rect: CGRect, for id: WindowID, moveOnly: Bool) -> Bool {
        guard let entry = entries[id] else { return false }
        var origin = rect.origin
        var size = rect.size
        guard let position = AXValueCreate(.cgPoint, &origin),
              let dimensions = AXValueCreate(.cgSize, &size) else { return false }
        // Intermediate animation frames only move the window; skip the size AX call.
        var sizeResult = AXError.success
        if !moveOnly {
            sizeResult = AXUIElementSetAttributeValue(entry.element, kAXSizeAttribute as CFString, dimensions)
        }
        let positionResult = AXUIElementSetAttributeValue(entry.element, kAXPositionAttribute as CFString, position)
        return sizeResult == .success && positionResult == .success
    }

    func focus(_ id: WindowID) {
        guard let entry = entries[id] else { return }
        AXUIElementPerformAction(entry.element, kAXRaiseAction as CFString)
        let appElement = AXUIElementCreateApplication(entry.pid)
        AXUIElementSetAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, entry.element)
        AXUIElementSetAttributeValue(appElement, kAXFrontmostAttribute as CFString, kCFBooleanTrue)
        AXUIElementSetAttributeValue(entry.element, kAXMainAttribute as CFString, kCFBooleanTrue)
        NSRunningApplication(processIdentifier: entry.pid)?.activate()
    }

    // Temporary: replaced by the real implementation in Task 3.
    func describe(_ id: WindowID) -> WindowDescription? { nil }

    func isAlive(_ id: WindowID) -> Bool {
        guard let entry = entries[id] else { return false }
        var value: CFTypeRef?
        // Only a destroyed element means dead; a hung app (.cannotComplete) keeps its windows.
        return AXUIElementCopyAttributeValue(entry.element, kAXRoleAttribute as CFString, &value) != .invalidUIElement
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
        AXObserverAddNotification(observer, appElement, kAXApplicationActivatedNotification as CFString, refcon)
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
        guard AXUIElementGetPid(element, &pid) == .success else { return }
        switch notification {
        case kAXWindowCreatedNotification:
            _ = register(element, pid: pid, emit: true)
        case kAXFocusedWindowChangedNotification:
            windowFocused(element, pid: pid)
        case kAXApplicationActivatedNotification:
            if let focused: AXUIElement = attribute(element, kAXFocusedWindowAttribute) {
                windowFocused(focused, pid: pid)
            }
        case kAXUIElementDestroyedNotification:
            if let id = id(of: element) {
                entries[id] = nil
                onEvent?(.closed(id))
            }
        case kAXWindowMiniaturizedNotification:
            // Keep the entry: the window comes back on deminiaturize.
            if let id = id(of: element) { onEvent?(.closed(id)) }
        case kAXWindowDeminiaturizedNotification:
            if let id = id(of: element), let info = info(for: id) { onEvent?(.opened(info)) }
        default:
            break
        }
    }

    private func windowFocused(_ element: AXUIElement, pid: pid_t) {
        guard let id = id(of: element) else {
            let id = register(element, pid: pid, emit: true)
            onEvent?(.focused(id))
            return
        }
        // Manageability is only checked at registration; retry for windows that were not ready then.
        if var entry = entries[id], !entry.adopted, isManageable(entry.element) {
            entry.adopted = true
            entries[id] = entry
            if let info = info(for: id) { onEvent?(.opened(info)) }
        }
        onEvent?(.focused(id))
    }

    private func register(_ element: AXUIElement, pid: pid_t, emit: Bool) -> WindowID {
        if let existing = id(of: element) { return existing }
        let id = WindowID(nextID)
        nextID += 1
        entries[id] = Entry(element: element, pid: pid, adopted: isManageable(element))
        if let observer = observers[pid] {
            let refcon = Unmanaged.passUnretained(self).toOpaque()
            AXObserverAddNotification(observer, element, kAXUIElementDestroyedNotification as CFString, refcon)
            AXObserverAddNotification(observer, element, kAXWindowMiniaturizedNotification as CFString, refcon)
            AXObserverAddNotification(observer, element, kAXWindowDeminiaturizedNotification as CFString, refcon)
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
