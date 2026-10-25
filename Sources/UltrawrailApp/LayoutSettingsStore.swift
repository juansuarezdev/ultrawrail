import Foundation
import LayoutEngine

struct LayoutSettings: Equatable {
    var gap: Double = 8
    var outerGap: Double = 8
    var newColumnWidth: Double = 0.5
    var focusMode: FocusMode = .minimal
    var maxColumnWidth: Double = 0
    var centerStrip: Bool = false
}

struct LayoutSettingsStore {
    private let defaults = UserDefaults.standard

    var settings: LayoutSettings {
        get {
            var value = LayoutSettings()
            if let gap = defaults.object(forKey: "gap") as? Double { value.gap = min(40, max(0, gap)) }
            if let outer = defaults.object(forKey: "outerGap") as? Double { value.outerGap = min(60, max(0, outer)) }
            if let width = defaults.object(forKey: "newColumnWidth") as? Double {
                value.newColumnWidth = WidthPreset.all.min { abs($0 - width) < abs($1 - width) } ?? value.newColumnWidth
            }
            if let raw = defaults.string(forKey: "focusMode"), let mode = FocusMode(rawValue: raw) { value.focusMode = mode }
            if let maxWidth = defaults.object(forKey: "maxColumnWidth") as? Double { value.maxColumnWidth = min(5000, max(0, maxWidth)) }
            if let center = defaults.object(forKey: "centerStrip") as? Bool { value.centerStrip = center }
            return value
        }
        nonmutating set {
            defaults.set(newValue.gap, forKey: "gap")
            defaults.set(newValue.outerGap, forKey: "outerGap")
            defaults.set(newValue.newColumnWidth, forKey: "newColumnWidth")
            defaults.set(newValue.focusMode.rawValue, forKey: "focusMode")
            defaults.set(newValue.maxColumnWidth, forKey: "maxColumnWidth")
            defaults.set(newValue.centerStrip, forKey: "centerStrip")
        }
    }
}
