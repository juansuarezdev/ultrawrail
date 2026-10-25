import Foundation

/// Copies settings saved under the app's former bundle identifier, once.
enum LegacyDefaultsMigration {
    static let legacyDomain = "dev.linkr.app"
    private static let doneKey = "legacyDefaultsMigrated"

    static func run(defaults: UserDefaults = .standard) {
        guard !defaults.bool(forKey: doneKey) else { return }
        defaults.set(true, forKey: doneKey)
        guard let legacy = defaults.persistentDomain(forName: legacyDomain) else { return }
        for (key, value) in legacy where defaults.object(forKey: key) == nil {
            defaults.set(value, forKey: key)
        }
    }
}
