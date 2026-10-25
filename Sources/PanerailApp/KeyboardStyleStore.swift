import Foundation
import PanerailCore

struct KeyboardStyleStore {
    private let defaults = UserDefaults.standard
    private let key = "keyboardStyle"

    var style: KeyboardStyle {
        get { defaults.string(forKey: key).flatMap(KeyboardStyle.init(rawValue:)) ?? .windows }
        nonmutating set { defaults.set(newValue.rawValue, forKey: key) }
    }
}
