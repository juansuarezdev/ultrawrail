import AppKit
import ApplicationServices
import LayoutEngine
import UltrawrailCore
import QuartzCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let previewView = StripPreviewView(frame: NSRect(x: 0, y: 0, width: 280, height: 84))
    let model = SettingsModel()
    private var settingsWindow: SettingsWindowController?
    private var controller: Controller?
    private var templatePanel: TemplatePanelController?
    private var lastSnapshot: WorkspaceSnapshot?
    private var statusLineItem: NSMenuItem?
    private var pageLineItem: NSMenuItem?
    private var permissionTimer: Timer?
    private var observers: [NSObjectProtocol] = []

    private var reduceMotion: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }

    private func menuBarImage() -> NSImage? {
        let image = NSImage(named: "MenuBarIconTemplate")
            ?? NSImage(systemSymbolName: "rectangle.split.3x1", accessibilityDescription: nil)
        image?.size = NSSize(width: 18, height: 18)
        image?.isTemplate = true
        image?.accessibilityDescription = "Ultrawrail"
        return image
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        model.onChange = { [weak self] in self?.settingsChanged() }
        settingsWindow = SettingsWindowController(model: model)
        statusItem.button?.image = menuBarImage()
        if AXIsProcessTrusted() {
            startController()
        } else {
            requestPermission()
        }
        rebuildMenu()
        installMainMenu()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        settingsWindow?.show()
        return true
    }

    private func installMainMenu() {
        let mainMenu = NSMenu()

        let appItem = NSMenuItem()
        let appMenu = NSMenu(title: "Ultrawrail")
        let settings = NSMenuItem(title: "Ajustes…", action: #selector(openSettings), keyEquivalent: ",")
        settings.target = self
        appMenu.addItem(settings)
        appMenu.addItem(.separator())
        appMenu.addItem(NSMenuItem(title: "Ocultar Ultrawrail", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h"))
        appMenu.addItem(NSMenuItem(title: "Salir de Ultrawrail", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        appItem.submenu = appMenu
        mainMenu.addItem(appItem)

        let windowItem = NSMenuItem()
        let windowMenu = NSMenu(title: "Ventana")
        windowMenu.addItem(NSMenuItem(title: "Minimizar", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m"))
        windowMenu.addItem(NSMenuItem(title: "Cerrar", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w"))
        windowItem.submenu = windowMenu
        mainMenu.addItem(windowItem)

        NSApp.mainMenu = mainMenu
        NSApp.windowsMenu = windowMenu
    }

    private func settingsChanged() {
        controller?.motion = model.motion
        controller?.placement = model.placement
        controller?.config = model.layoutConfig
        controller?.newColumnWidth = model.newColumnWidth
        rebuildMenu()
    }

    // MARK: Permission gate

    private func requestPermission() {
        // Registers Ultrawrail in the Accessibility list so the user only has to flip the switch.
        _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)

        let alert = NSAlert()
        alert.messageText = "Ultrawrail necesita permiso de Accesibilidad"
        alert.informativeText = "Para mover ventanas, activa Ultrawrail en Ajustes del Sistema > Privacidad y seguridad > Accesibilidad. Ultrawrail empezará solo cuando lo concedas."
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
            config: model.layoutConfig,
            animator: animator,
            reduceMotion: { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
        )
        controller.motion = model.motion
        controller.placement = model.placement
        controller.newColumnWidth = model.newColumnWidth
        controller.onChange = { [weak self] snapshot in self?.workspaceChanged(snapshot) }
        templatePanel = TemplatePanelController(
            controller: controller,
            templates: { [weak self] in self?.model.allTemplates ?? Template.builtIn }
        )
        controller.onShowTemplates = { [weak self] in self?.templatePanel?.toggle() }
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
        previewView.animationDuration = model.motion.previewDuration(reduceMotion: reduceMotion)
        previewView.show(StripPreview(workspace: snapshot.workspace, viewport: snapshot.viewport, config: snapshot.config))
        statusLineItem?.title = statusText()
        updatePageLine()
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

        let pageLine = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        pageLine.isEnabled = false
        pageLineItem = pageLine
        updatePageLine()
        menu.addItem(pageLine)

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
            let settings = model.motion

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

            let placementItem = NSMenuItem(title: "Ventanas nuevas", action: nil, keyEquivalent: "")
            let placementMenu = NSMenu()
            for (mode, title) in [(PlacementMode.manual, "Manual (Ctrl+Alt+A para añadir)"), (.automatic, "Automático")] {
                let item = NSMenuItem(title: title, action: #selector(selectPlacement(_:)), keyEquivalent: "")
                item.representedObject = mode.rawValue
                item.state = model.placement == mode ? .on : .off
                item.target = self
                placementMenu.addItem(item)
            }
            placementItem.submenu = placementMenu
            menu.addItem(placementItem)

            let reduce = NSMenuItem(title: "Respetar Reducir movimiento del sistema", action: #selector(toggleReduceMotion), keyEquivalent: "")
            reduce.state = settings.respectReduceMotion ? .on : .off
            reduce.target = self
            menu.addItem(reduce)
        }

        let settingsItem = NSMenuItem(title: "Ajustes…", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        let legendItem = NSMenuItem(title: "Atajos de teclado", action: nil, keyEquivalent: "")
        let legendMenu = NSMenu()
        let style = model.keyboardStyle
        for (option, title) in [(KeyboardStyle.windows, "Teclado Windows"), (.mac, "Teclado Mac")] {
            let item = NSMenuItem(title: title, action: #selector(selectKeyboardStyle(_:)), keyEquivalent: "")
            item.representedObject = option.rawValue
            item.state = style == option ? .on : .off
            item.target = self
            legendMenu.addItem(item)
        }
        legendMenu.addItem(.separator())
        for entry in ShortcutLegend.entries {
            let line = NSMenuItem(title: ShortcutLegend.line(for: entry, style: style), action: nil, keyEquivalent: "")
            line.isEnabled = false
            legendMenu.addItem(line)
        }
        legendItem.submenu = legendMenu
        menu.addItem(legendItem)

        let login = NSMenuItem(title: "Iniciar al arrancar", action: #selector(toggleLogin), keyEquivalent: "")
        login.state = model.launchAtLogin ? .on : .off
        login.target = self
        menu.addItem(login)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Salir de Ultrawrail", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

        for item in menu.items where item.action == #selector(openAccessibilitySettings) {
            item.target = self
        }
        statusItem.menu = menu
    }

    private func updatePageLine() {
        guard let snapshot = lastSnapshot, snapshot.pageCount > 1 else {
            pageLineItem?.isHidden = true
            return
        }
        pageLineItem?.title = "Página \(snapshot.page) de \(snapshot.pageCount)"
        pageLineItem?.isHidden = false
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
        model.speed = speed
    }

    @objc private func selectPlacement(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let mode = PlacementMode(rawValue: raw) else { return }
        model.placement = mode
    }

    @objc private func selectKeyboardStyle(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let style = KeyboardStyle(rawValue: raw) else { return }
        model.keyboardStyle = style
    }

    @objc private func toggleReduceMotion() {
        model.respectReduceMotion.toggle()
    }

    @objc private func openSettings() { settingsWindow?.show() }

    @objc private func toggleLogin() {
        model.launchAtLogin.toggle()
    }
}
