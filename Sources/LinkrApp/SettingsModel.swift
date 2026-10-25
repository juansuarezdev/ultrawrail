import Foundation
import LayoutEngine
import LinkrCore
import ServiceManagement

/// Single source of truth for every user setting. The menu and the settings window both edit it.
@MainActor
final class SettingsModel: ObservableObject {
    private let motionStore = MotionSettingsStore()
    private let placementStore = PlacementStore()
    private let keyboardStore = KeyboardStyleStore()
    private let layoutStore = LayoutSettingsStore()
    private var loading = true

    var onChange: (() -> Void)?

    @Published var speed: MotionSpeed { didSet { commit() } }
    @Published var respectReduceMotion: Bool { didSet { commit() } }
    @Published var placement: PlacementMode { didSet { commit() } }
    @Published var keyboardStyle: KeyboardStyle { didSet { commit() } }
    @Published var gap: Double { didSet { commit() } }
    @Published var outerGap: Double { didSet { commit() } }
    @Published var newColumnWidth: Double { didSet { commit() } }
    @Published var launchAtLogin: Bool {
        didSet {
            guard !loading, launchAtLogin != oldValue else { return }
            do {
                if launchAtLogin { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            } catch {
                NSLog("Linkr: login item change failed: \(error)")
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
        launchAtLogin = SMAppService.mainApp.status == .enabled
        loading = false
    }

    var motion: MotionSettings { MotionSettings(speed: speed, respectReduceMotion: respectReduceMotion) }
    var layoutConfig: LayoutConfig { LayoutConfig(gap: gap, outerGap: outerGap) }

    func restoreLayoutDefaults() {
        let defaults = LayoutSettings()
        gap = defaults.gap
        outerGap = defaults.outerGap
        newColumnWidth = defaults.newColumnWidth
    }

    private func commit() {
        guard !loading else { return }
        motionStore.settings = motion
        placementStore.mode = placement
        keyboardStore.style = keyboardStyle
        layoutStore.settings = LayoutSettings(gap: gap, outerGap: outerGap, newColumnWidth: newColumnWidth)
        onChange?()
    }
}
