import Foundation
import LinkrCore

struct MotionSettingsStore {
    private let defaults = UserDefaults.standard
    private let speedKey = "motionSpeed"
    private let reduceKey = "respectReduceMotion"

    var settings: MotionSettings {
        get {
            let speed = defaults.string(forKey: speedKey).flatMap(MotionSpeed.init(rawValue:)) ?? .normal
            let respect = defaults.object(forKey: reduceKey) as? Bool ?? true
            return MotionSettings(speed: speed, respectReduceMotion: respect)
        }
        nonmutating set {
            defaults.set(newValue.speed.rawValue, forKey: speedKey)
            defaults.set(newValue.respectReduceMotion, forKey: reduceKey)
        }
    }
}
