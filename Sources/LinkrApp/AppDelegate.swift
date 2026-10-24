import AppKit
import ApplicationServices
import LinkrCore
import ServiceManagement

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private var controller: Controller?
    private var permissionTimer: Timer?
    private var observers: [NSObjectProtocol] = []

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
        let controller = Controller(windows: AXWindowService(), hotkeys: CarbonHotkeyService())
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

    // MARK: Menu

    private func rebuildMenu() {
        let menu = NSMenu()
        let status = NSMenuItem(title: statusText(), action: nil, keyEquivalent: "")
        status.isEnabled = false
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
        let login = NSMenuItem(title: "Iniciar al arrancar", action: #selector(toggleLogin), keyEquivalent: "")
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(login)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Salir de Linkr", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

        for item in menu.items where item.action != nil && item.target == nil && item.action != #selector(NSApplication.terminate(_:)) {
            item.target = self
        }
        statusItem.menu = menu
    }

    private func statusText() -> String {
        controller == nil ? "Esperando permiso de Accesibilidad" : "Activo"
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
