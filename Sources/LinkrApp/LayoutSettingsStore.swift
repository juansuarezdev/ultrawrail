import Foundation

struct LayoutSettings: Equatable {
    var gap: Double = 8
    var outerGap: Double = 8
    var newColumnWidth: Double = 0.5
}

struct LayoutSettingsStore {
    private let defaults = UserDefaults.standard

    var settings: LayoutSettings {
        get {
            var value = LayoutSettings()
            if let gap = defaults.object(forKey: "gap") as? Double { value.gap = min(40, max(0, gap)) }
            if let outer = defaults.object(forKey: "outerGap") as? Double { value.outerGap = min(60, max(0, outer)) }
            if let width = defaults.object(forKey: "newColumnWidth") as? Double { value.newColumnWidth = width }
            return value
        }
        nonmutating set {
            defaults.set(newValue.gap, forKey: "gap")
            defaults.set(newValue.outerGap, forKey: "outerGap")
            defaults.set(newValue.newColumnWidth, forKey: "newColumnWidth")
        }
    }
}
