import Foundation
import UltrawrailCore

struct ShortcutStore {
    private let defaults = UserDefaults.standard
    private let key = "shortcutOverrides"

    var map: ShortcutMap {
        get {
            guard let data = defaults.data(forKey: key),
                  let overrides = try? JSONDecoder().decode([String: KeyCombo].self, from: data) else { return ShortcutMap() }
            return ShortcutMap(overrides: overrides)
        }
        nonmutating set {
            if newValue.overrides.isEmpty {
                defaults.removeObject(forKey: key)
            } else if let data = try? JSONEncoder().encode(newValue.overrides) {
                defaults.set(data, forKey: key)
            }
        }
    }
}
