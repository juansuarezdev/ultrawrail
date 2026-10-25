import Foundation

struct ExcludedAppsStore {
    private let defaults = UserDefaults.standard
    private let key = "excludedApps"

    var apps: [String] {
        get { Array(Set(defaults.stringArray(forKey: key) ?? [])).sorted() }
        nonmutating set { defaults.set(Array(Set(newValue)).sorted(), forKey: key) }
    }
}
