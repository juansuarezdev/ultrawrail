import Foundation
import UltrawrailCore

struct PlacementStore {
    private let defaults = UserDefaults.standard
    private let key = "placementMode"

    var mode: PlacementMode {
        get { defaults.string(forKey: key).flatMap(PlacementMode.init(rawValue:)) ?? .manual }
        nonmutating set { defaults.set(newValue.rawValue, forKey: key) }
    }
}
