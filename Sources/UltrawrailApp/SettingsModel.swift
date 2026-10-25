import AppKit
import Foundation
import LayoutEngine
import UltrawrailCore
import ServiceManagement

/// Single source of truth for every user setting. The menu and the settings window both edit it.
@MainActor
final class SettingsModel: ObservableObject {
    private let motionStore = MotionSettingsStore()
    private let placementStore = PlacementStore()
    private let keyboardStore = KeyboardStyleStore()
    private let layoutStore = LayoutSettingsStore()
    private let templateStore = TemplateStore()
    private let excludedAppsStore = ExcludedAppsStore()
    private let shortcutStore = ShortcutStore()
    private var loading = true

    var onChange: (() -> Void)?

    /// Live pages overview and the app name/icon of each managed window, fed by the controller.
    @Published var overview: [ZoneOverview] = []
    @Published var windowChips: [WindowID: (name: String, icon: NSImage?)] = [:]
    var moveWindowHandler: ((WindowID, Int, Int) -> Void)?
    var refreshOverviewHandler: (() -> Void)?

    func moveWindow(_ id: WindowID, toZone zone: Int, page: Int) {
        moveWindowHandler?(id, zone, page)
        refreshOverviewHandler?()
    }

    @Published var speed: MotionSpeed { didSet { commit() } }
    @Published var respectReduceMotion: Bool { didSet { commit() } }
    @Published var placement: PlacementMode { didSet { commit() } }
    @Published var keyboardStyle: KeyboardStyle { didSet { commit() } }
    @Published var gap: Double { didSet { commit() } }
    @Published var outerGap: Double { didSet { commit() } }
    @Published var newColumnWidth: Double { didSet { commit() } }
    @Published var focusMode: FocusMode { didSet { commit() } }
    @Published var maxColumnWidth: Double { didSet { commit() } }
    @Published var centerStrip: Bool { didSet { commit() } }
    @Published var zoneCount: Int { didSet { commit() } }
    @Published var customTemplates: [Template] { didSet { commitTemplates() } }
    @Published var excludedApps: [String] { didSet { commitExcludedApps() } }
    @Published var shortcutMap: ShortcutMap { didSet { commitShortcuts() } }
    /// Set while a shortcut is being recorded so the global hotkeys do not swallow the keypress.
    var recordingChanged: ((Bool) -> Void)?
    @Published var launchAtLogin: Bool {
        didSet {
            guard !loading, launchAtLogin != oldValue else { return }
            do {
                if launchAtLogin { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            } catch {
                NSLog("Ultrawrail: login item change failed: \(error)")
                loading = true
                launchAtLogin = oldValue
                loading = false
            }
            onChange?()
        }
    }

    init() {
        let motion = motionStore.settings
        let layout = layoutStore.settings
        speed = motion.speed
        respectReduceMotion = motion.respectReduceMotion
        placement = placementStore.mode
        keyboardStyle = keyboardStore.style
        gap = layout.gap
        outerGap = layout.outerGap
        newColumnWidth = layout.newColumnWidth
        focusMode = layout.focusMode
        maxColumnWidth = layout.maxColumnWidth
        centerStrip = layout.centerStrip
        zoneCount = layout.zoneCount
        customTemplates = templateStore.templates
        excludedApps = excludedAppsStore.apps
        shortcutMap = shortcutStore.map
        launchAtLogin = SMAppService.mainApp.status == .enabled
        loading = false
    }

    var motion: MotionSettings { MotionSettings(speed: speed, respectReduceMotion: respectReduceMotion) }
    var layoutConfig: LayoutConfig { LayoutConfig(gap: gap, outerGap: outerGap, focusMode: focusMode,
                                                    maxColumnWidth: maxColumnWidth, centerStrip: centerStrip) }

    func restoreLayoutDefaults() {
        let defaults = LayoutSettings()
        gap = defaults.gap
        outerGap = defaults.outerGap
        newColumnWidth = defaults.newColumnWidth
        focusMode = defaults.focusMode
        maxColumnWidth = defaults.maxColumnWidth
        centerStrip = defaults.centerStrip
        zoneCount = defaults.zoneCount
    }

    private func commit() {
        guard !loading else { return }
        motionStore.settings = motion
        placementStore.mode = placement
        keyboardStore.style = keyboardStyle
        layoutStore.settings = LayoutSettings(gap: gap, outerGap: outerGap, newColumnWidth: newColumnWidth,
                                           focusMode: focusMode, maxColumnWidth: maxColumnWidth, centerStrip: centerStrip,
                                           zoneCount: zoneCount)
        onChange?()
    }

    /// Only the templates changed: skip the other stores.
    private func commitTemplates() {
        guard !loading else { return }
        templateStore.templates = customTemplates
        onChange?()
    }

    /// Only the excluded apps changed: skip the other stores.
    private func commitExcludedApps() {
        guard !loading else { return }
        excludedAppsStore.apps = excludedApps
        onChange?()
    }

    /// Only the shortcuts changed: skip the other stores.
    private func commitShortcuts() {
        guard !loading else { return }
        shortcutStore.map = shortcutMap
        onChange?()
    }

    func addExcludedApp(_ bundleID: String) {
        guard !excludedApps.contains(bundleID) else { return }
        excludedApps = (excludedApps + [bundleID]).sorted()
    }

    func removeExcludedApp(_ bundleID: String) {
        excludedApps.removeAll { $0 == bundleID }
    }

    var allTemplates: [Template] { TemplateLibrary.all(custom: customTemplates) }

    @discardableResult
    func newTemplate() -> Template {
        let template = Template(id: "custom-" + UUID().uuidString, name: "Nueva plantilla",
                                columns: [TemplateColumn(width: 0.5, slots: 1), TemplateColumn(width: 0.5, slots: 1)])
        customTemplates.append(template)
        return template
    }

    @discardableResult
    func duplicate(_ source: Template) -> Template {
        let copy = Template(id: "custom-" + UUID().uuidString, name: "Copia de " + source.name,
                            columns: TemplateDraft(columns: source.columns).columns)
        customTemplates.append(copy)
        return copy
    }

    func update(_ template: Template) {
        guard let index = customTemplates.firstIndex(where: { $0.id == template.id }) else { return }
        customTemplates[index] = template
    }

    func deleteTemplate(id: String) {
        customTemplates.removeAll { $0.id == id }
    }
}
