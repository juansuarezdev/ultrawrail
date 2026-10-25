public enum MotionSpeed: String, CaseIterable, Sendable {
    case fast
    case normal
    case off

    public var duration: Double {
        switch self {
        case .fast: 0.12
        case .normal: 0.18
        case .off: 0
        }
    }
}

public struct MotionSettings: Equatable, Sendable {
    public var speed: MotionSpeed
    public var respectReduceMotion: Bool

    public init(speed: MotionSpeed = .off, respectReduceMotion: Bool = true) {
        self.speed = speed
        self.respectReduceMotion = respectReduceMotion
    }

    /// Duration for real windows; 0 means no animation.
    public func duration(reduceMotion: Bool) -> Double {
        if speed == .off || (respectReduceMotion && reduceMotion) { return 0 }
        return speed.duration
    }

    /// The menu preview is cheap to draw, so it animates even with speed off.
    public func previewDuration(reduceMotion: Bool) -> Double {
        if respectReduceMotion && reduceMotion { return 0 }
        return speed == .off ? MotionSpeed.normal.duration : speed.duration
    }
}
