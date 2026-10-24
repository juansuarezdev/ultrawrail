import XCTest
import CoreGraphics
import LayoutEngine
@testable import LinkrCore

@MainActor
final class ManualClock: FrameClock {
    var time = 0.0
    private(set) var isRunning = false
    private var tick: (() -> Void)?

    func start(_ tick: @escaping () -> Void) {
        self.tick = tick
        isRunning = true
    }

    func stop() {
        tick = nil
        isRunning = false
    }

    func fire(advancingBy dt: Double) {
        time += dt
        tick?()
    }
}

@MainActor
final class AnimatorTests: XCTestCase {
    let start = CGRect(x: 0, y: 10, width: 490, height: 780)
    let end = CGRect(x: 100, y: 10, width: 490, height: 780)

    func makeAnimator() -> (Animator, ManualClock) {
        let clock = ManualClock()
        return (Animator(clock: clock, now: { clock.time }), clock)
    }

    func testEmitsIntermediateThenExactFinalFrameAndStops() {
        let (animator, clock) = makeAnimator()
        var emitted: [(frames: [WindowID: CGRect], finished: Bool)] = []
        animator.onFrame = { emitted.append(($0, $1)) }
        animator.start(Tween(from: [1: start], to: [1: end], duration: 0.2))
        XCTAssertTrue(animator.isAnimating)

        clock.fire(advancingBy: 0.1)
        XCTAssertFalse(emitted[0].finished)
        XCTAssertGreaterThan(emitted[0].frames[1]!.minX, 0)
        XCTAssertLessThan(emitted[0].frames[1]!.minX, 100)

        clock.fire(advancingBy: 0.2)
        XCTAssertTrue(emitted[1].finished)
        XCTAssertEqual(emitted[1].frames[1], end)
        XCTAssertFalse(animator.isAnimating)
        XCTAssertFalse(clock.isRunning)
    }

    func testSlowFrameSnapsToTargetInTheSameTick() {
        let (animator, clock) = makeAnimator()
        var emitted: [(frames: [WindowID: CGRect], finished: Bool)] = []
        animator.onFrame = { frames, finished in
            emitted.append((frames, finished))
            clock.time += 0.05
        }
        animator.start(Tween(from: [1: start], to: [1: end], duration: 0.2))
        clock.fire(advancingBy: 0.01)
        XCTAssertEqual(emitted.count, 2)
        XCTAssertTrue(emitted[1].finished)
        XCTAssertEqual(emitted[1].frames[1], end)
        XCTAssertFalse(animator.isAnimating)
    }

    func testCancelStopsTheClock() {
        let (animator, clock) = makeAnimator()
        animator.start(Tween(from: [1: start], to: [1: end], duration: 0.2))
        animator.cancel()
        XCTAssertFalse(animator.isAnimating)
        XCTAssertFalse(clock.isRunning)
    }

    func testRemovingLastWindowStopsAnimation() {
        let (animator, clock) = makeAnimator()
        animator.start(Tween(from: [1: start, 2: start], to: [1: end, 2: end], duration: 0.2))
        animator.remove(1)
        XCTAssertTrue(animator.isAnimating)
        animator.remove(2)
        XCTAssertFalse(animator.isAnimating)
        XCTAssertFalse(clock.isRunning)
    }

    func testRestartInsideFinishedFrameCallbackIsNotClobbered() {
        let (animator, clock) = makeAnimator()
        var emitted: [[WindowID: CGRect]] = []
        var restarted = false
        animator.onFrame = { frames, _ in
            emitted.append(frames)
            if !restarted {
                restarted = true
                animator.cancel()
                animator.start(Tween(from: [2: self.start], to: [2: self.end], duration: 0.2))
            }
        }
        animator.start(Tween(from: [1: start], to: [1: end], duration: 0.2))
        clock.fire(advancingBy: 0.5)
        XCTAssertTrue(animator.isAnimating)
        XCTAssertTrue(clock.isRunning)

        clock.fire(advancingBy: 0.05)
        XCTAssertEqual(emitted.count, 2)
        XCTAssertEqual(Set(emitted[1].keys), [2])
    }

    func testRestartInsideSlowSnapCallbackIsNotClobbered() {
        let (animator, clock) = makeAnimator()
        var calls = 0
        var emitted: [[WindowID: CGRect]] = []
        animator.onFrame = { frames, _ in
            calls += 1
            emitted.append(frames)
            if calls == 1 {
                clock.time += 0.05
            } else if calls == 2 {
                animator.cancel()
                animator.start(Tween(from: [2: self.start], to: [2: self.end], duration: 0.2))
            }
        }
        animator.start(Tween(from: [1: start], to: [1: end], duration: 0.2))
        clock.fire(advancingBy: 0.01)
        XCTAssertEqual(calls, 2)
        XCTAssertTrue(animator.isAnimating)
        XCTAssertTrue(clock.isRunning)

        clock.fire(advancingBy: 0.05)
        XCTAssertEqual(emitted.count, 3)
        XCTAssertEqual(Set(emitted[2].keys), [2])
    }

    func testSlowFrameSnapSkipsWindowRemovedInsideCallback() {
        let (animator, clock) = makeAnimator()
        var emitted: [[WindowID: CGRect]] = []
        animator.onFrame = { frames, _ in
            emitted.append(frames)
            if emitted.count == 1 {
                animator.remove(2)
                clock.time += 0.05
            }
        }
        animator.start(Tween(from: [1: start, 2: start], to: [1: end, 2: end], duration: 0.2))
        clock.fire(advancingBy: 0.01)
        XCTAssertEqual(emitted.count, 2)
        XCTAssertEqual(Set(emitted[1].keys), [1])
        XCTAssertEqual(emitted[1][1], end)
        XCTAssertFalse(animator.isAnimating)
    }

    func testMotionSettingsDurations() {
        XCTAssertEqual(MotionSettings(speed: .normal).duration(reduceMotion: false), 0.18)
        XCTAssertEqual(MotionSettings(speed: .fast).duration(reduceMotion: false), 0.12)
        XCTAssertEqual(MotionSettings(speed: .off).duration(reduceMotion: false), 0)
        XCTAssertEqual(MotionSettings(speed: .normal).duration(reduceMotion: true), 0)
        XCTAssertEqual(MotionSettings(speed: .normal, respectReduceMotion: false).duration(reduceMotion: true), 0.18)
    }

    func testPreviewAnimatesEvenWhenWindowAnimationIsOff() {
        XCTAssertEqual(MotionSettings(speed: .off).previewDuration(reduceMotion: false), 0.18)
        XCTAssertEqual(MotionSettings(speed: .fast).previewDuration(reduceMotion: false), 0.12)
        XCTAssertEqual(MotionSettings(speed: .off).previewDuration(reduceMotion: true), 0)
        XCTAssertEqual(MotionSettings(speed: .off, respectReduceMotion: false).previewDuration(reduceMotion: true), 0.18)
    }
}
