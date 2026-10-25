import Foundation

/// Copies settings saved under the app's former bundle identifiers, once.
enum LegacyDefaultsMigration {
    static let legacyDomains = ["dev.panerail.app", "dev.linkr.app"]
    private static let doneKey = "legacyDefaultsMigrated"

    static func run(defaults: UserDefaults = .standard) {
        guard !defaults.bool(forKey: doneKey) else { return }
        defaults.set(true, forKey: doneKey)
        for domain in legacyDomains {
            guard let legacy = defaults.persistentDomain(forName: domain) else { continue }
            for (key, value) in legacy where defaults.object(forKey: key) == nil {
                defaults.set(value, forKey: key)
            }
        }
    }
}
