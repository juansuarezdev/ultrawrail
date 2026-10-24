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
        previewView.setAccessibilityLabel(statusText())
    }

    // MARK: Menu

    private func rebuildMenu() {
        let menu = NSMenu()
        menu.delegate = self

        if controller != nil {
            let preview = NSMenuItem()
            previewView.setAccessibilityLabel(statusText())
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
