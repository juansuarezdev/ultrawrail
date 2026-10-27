import AppKit
import LayoutEngine
import SwiftUI
import UltrawrailCore

private final class CanvasPanelWindow: NSWindow {
    override var canBecomeKey: Bool { true }
}

/// Full-screen canvas with every zone, page and window as a zoomable map (Ctrl+Alt+O).
@MainActor
final class CanvasWindowController {
    private let controller: Controller
    private let model = CanvasModel()
    private var window: NSWindow?
    private var monitors: [Any] = []
    private var askedPermission = false

    init(controller: Controller) {
        self.controller = controller
        model.onReveal = { [weak self] id in
            self?.close()
            self?.controller.reveal(id)
        }
        model.onAssignToCurrent = { [weak self] id in
            guard let self else { return }
            let overview = self.controller.overview()
            if let zone = overview.firstIndex(where: \.isFocused),
               let page = overview[zone].pages.firstIndex(where: \.isCurrent) {
                self.apply(.page(zone: zone, page: page), to: id)
            }
        }
        model.onResize = { [weak self] id, fraction in
            self?.controller.setColumnWidth(of: id, to: fraction)
            self?.reload()
        }
        model.onResizeHeight = { [weak self] id, fraction in
            self?.controller.setWindowHeight(of: id, to: fraction)
            self?.reload()
        }
        model.onDrop = { [weak self] id, drop in self?.apply(drop, to: id) }
    }

    func toggle() {
        if window?.isVisible == true { close(); controller.refocus() } else { open() }
    }

    private func open() {
        guard !controller.managedWindows.isEmpty || !controller.unassignedWindows().isEmpty, let screen = NSScreen.main else { return }
        model.screenSize = screen.frame.size
        reload()
        model.fit()
        model.thumbnails = [:]
        model.hasCapturePermission = WindowSnapshotter.hasPermission
        if !model.hasCapturePermission, !askedPermission {
            askedPermission = true
            WindowSnapshotter.requestPermission()
        }

        let window = CanvasPanelWindow(contentRect: screen.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.level = .modalPanel
        window.isOpaque = true
        window.backgroundColor = .black
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: CanvasView(model: model))
        window.alphaValue = 0
        self.window = window
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        NSAnimationContext.runAnimationGroup { $0.duration = 0.15; window.animator().alphaValue = 1 }
        installMonitors()
        captureThumbnails()
    }

    private func close() {
        for monitor in monitors { NSEvent.removeMonitor(monitor) }
        monitors = []
        window?.orderOut(nil)
        window = nil
    }

    private func reload() {
        let overview = controller.overview()
        var chips: [WindowID: (name: String, icon: NSImage?)] = [:]
        let unassigned = controller.unassignedWindows()
        model.unassigned = unassigned
        for id in controller.managedWindows + unassigned {
            let description = controller.describe(id)
            let icon = description.flatMap { NSRunningApplication(processIdentifier: pid_t($0.pid))?.icon }
            chips[id] = (description?.appName ?? "Ventana", icon)
        }
        model.chips = chips
        model.load(overview, focused: controller.focusedWindowID)
    }

    /// One window per main-actor turn so thumbnails pop in without freezing the canvas.
    private func captureThumbnails() {
        guard model.hasCapturePermission else { return }
        let ids = controller.managedWindows + controller.unassignedWindows()
        Task { @MainActor [weak self] in
            for id in ids {
                await Task.yield()
                guard let self, self.window != nil else { return }
                if let number = self.controller.windowNumber(for: id),
                   let image = WindowSnapshotter.image(forWindowNumber: number) {
                    self.model.thumbnails[id] = image
                }
            }
        }
    }

    private func apply(_ drop: CanvasDrop, to id: WindowID) {
        switch drop {
        case .stack(let target): controller.stack(id, onto: target)
        case .page(let zone, let page):
            if controller.unassignedWindows().contains(id) {
                controller.assign(id, toZone: zone, page: page)
            } else {
                controller.moveWindow(id, toZone: zone, page: page)
            }
        }
        reload()
    }

    private func installMonitors() {
        let keys = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == 53 else { return event }
            MainActor.assumeIsolated { self?.close(); self?.controller.refocus() }
            return nil
        }
        let scroll = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            MainActor.assumeIsolated { self?.scroll(event) }
            return nil
        }
        let magnify = NSEvent.addLocalMonitorForEvents(matching: .magnify) { [weak self] event in
            MainActor.assumeIsolated { self?.magnify(event) }
            return nil
        }
        monitors = [keys, scroll, magnify].compactMap { $0 }
    }

    private func screenPoint(_ event: NSEvent) -> CGPoint {
        CGPoint(x: event.locationInWindow.x, y: model.screenSize.height - event.locationInWindow.y)
    }

    private func scroll(_ event: NSEvent) {
        if event.modifierFlags.contains(.command) || event.modifierFlags.contains(.control) {
            model.zoom(by: exp(event.scrollingDeltaY * 0.01), around: screenPoint(event))
        } else {
            model.pan(by: CGSize(width: event.scrollingDeltaX, height: event.scrollingDeltaY))
        }
    }

    private func magnify(_ event: NSEvent) {
        model.zoom(by: 1 + event.magnification, around: screenPoint(event))
    }
}
