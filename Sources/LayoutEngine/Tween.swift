import CoreGraphics

public enum Easing {
    public static func easeOut(_ t: Double) -> Double {
        let clamped = min(max(t, 0), 1)
        let inverse = 1 - clamped
        return 1 - inverse * inverse * inverse * inverse
    }
}

public struct Tween: Equatable, Sendable {
    public let from: [WindowID: CGRect]
    public let to: [WindowID: CGRect]
    public let duration: Double

    public init(from: [WindowID: CGRect], to: [WindowID: CGRect], duration: Double) {
        self.from = from
        self.to = to
        self.duration = duration
    }

    public var isEmpty: Bool { to.isEmpty }

    public func isFinished(at elapsed: Double) -> Bool { elapsed >= duration }

    public func frames(at elapsed: Double) -> [WindowID: CGRect] {
        let progress = duration <= 0 ? 1 : Easing.easeOut(elapsed / duration)
        guard progress < 1 else { return to }
        var result: [WindowID: CGRect] = [:]
        for (id, target) in to {
            guard let start = from[id] else {
                result[id] = target
                continue
            }
            result[id] = CGRect(
                x: start.minX + (target.minX - start.minX) * progress,
                y: start.minY + (target.minY - start.minY) * progress,
                width: start.width + (target.width - start.width) * progress,
                height: start.height + (target.height - start.height) * progress
            )
        }
        return result
    }

    public func removing(_ id: WindowID) -> Tween {
        Tween(
            from: from.filter { $0.key != id },
            to: to.filter { $0.key != id },
            duration: duration
        )
    }
}
