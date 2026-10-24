import CoreGraphics
import LayoutEngine

@MainActor
public protocol FrameClock: AnyObject {
    func start(_ tick: @escaping () -> Void)
    func stop()
}

/// Drives a `Tween`. Each tick hands the interpolated rects to `onFrame`; if
/// writing them takes longer than `slowFrameLimit`, it snaps to the target.
@MainActor
public final class Animator {
    public var onFrame: (([WindowID: CGRect], Bool) -> Void)?

    private let clock: FrameClock
    private let now: () -> Double
    private let slowFrameLimit: Double
    private var tween: Tween?
    private var startTime = 0.0
    private var generation = 0

    public init(clock: FrameClock, now: @escaping () -> Double, slowFrameLimit: Double = 0.033) {
        self.clock = clock
        self.now = now
        self.slowFrameLimit = slowFrameLimit
    }

    public var isAnimating: Bool { tween != nil }

    public func start(_ tween: Tween) {
        generation += 1
        self.tween = tween
        startTime = now()
        clock.start { [weak self] in self?.tick() }
    }

    public func cancel() {
        generation += 1
        tween = nil
        clock.stop()
    }

    public func remove(_ id: WindowID) {
        guard let current = tween else { return }
        let reduced = current.removing(id)
        if reduced.isEmpty {
            cancel()
        } else {
            tween = reduced
        }
    }

    private func tick() {
        guard let tween else {
            clock.stop()
            return
        }
        let elapsed = now() - startTime
        let finished = tween.isFinished(at: elapsed)
        let frames = tween.frames(at: elapsed)
        let generationBefore = generation
        let began = now()
        onFrame?(frames, finished)
        // onFrame may have cancelled or restarted the animation.
        guard generation == generationBefore else { return }
        if finished {
            cancel()
            return
        }
        if now() - began > slowFrameLimit {
            onFrame?(tween.frames(at: tween.duration), true)
            if generation == generationBefore { cancel() }
        }
    }
}
