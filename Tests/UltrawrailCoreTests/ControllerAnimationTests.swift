import XCTest
import CoreGraphics
import LayoutEngine
@testable import UltrawrailCore

@MainActor
final class ControllerAnimationTests: XCTestCase {
    let config = LayoutConfig(gap: 10, outerGap: 10)
    var clock = ManualClock()

    func makeController(
        _ ids: [Int],
        speed: MotionSpeed = .normal,
        respectReduceMotion: Bool = true,
        reduceMotion: Bool = false
    ) -> (Controller, FakeWindows) {
        let windows = FakeWindows()
        for id in ids { windows.add(id) }
        let clock = ManualClock()
        self.clock = clock
        let animator = Animator(clock: clock, now: { clock.time })
        let controller = Controller(
            windows: windows,
            hotkeys: FakeHotkeys(),
            config: config,
            animator: animator,
            reduceMotion: { reduceMotion }
        )
        controller.motion = MotionSettings(speed: speed, respectReduceMotion: respectReduceMotion)
        controller.start()
        return (controller, windows)
    }

    func testFocusChangeSlidesWindowsThenLandsOnTarget() {
        let (controller, windows) = makeController([1, 2, 3])
        let before = windows.setFrameCalls.count
        controller.handle(.centerColumn)
        XCTAssertEqual(windows.setFrameCalls.count, before)

        clock.fire(advancingBy: 0.09)
        let mid = windows.lastRect(2)!
        XCTAssertGreaterThan(mid.minX, -237.5)
        XCTAssertLessThan(mid.minX, 10)

        clock.fire(advancingBy: 0.2)
        XCTAssertEqual(windows.lastRect(2), CGRect(x: -237.5, y: 10, width: 485, height: 780))
        XCTAssertEqual(windows.lastRect(3), CGRect(x: 257.5, y: 10, width: 485, height: 780))
        XCTAssertFalse(clock.isRunning)
    }

    func testSizeChangeWritesImmediately() {
        let (controller, windows) = makeController([1, 2, 3])
        controller.handle(.cycleWidth)
        XCTAssertEqual(windows.lastRect(3)!.width, 0.66 * 990 - 10, accuracy: 0.001)
    }

    func testOffWritesImmediatelyAndNeverStartsTheClock() {
        let (controller, windows) = makeController([1, 2, 3], speed: .off)
        controller.handle(.centerColumn)
        XCTAssertEqual(windows.lastRect(2), CGRect(x: -237.5, y: 10, width: 485, height: 780))
        XCTAssertFalse(clock.isRunning)
    }

    func testReduceMotionWritesImmediatelyUnlessIgnored() {
        let (reduced, reducedWindows) = makeController([1, 2, 3], reduceMotion: true)
        reduced.handle(.centerColumn)
        XCTAssertEqual(reducedWindows.lastRect(2), CGRect(x: -237.5, y: 10, width: 485, height: 780))
        XCTAssertFalse(clock.isRunning)

        let (ignored, ignoredWindows) = makeController([1, 2, 3], respectReduceMotion: false, reduceMotion: true)
        let before = ignoredWindows.setFrameCalls.count
        ignored.handle(.centerColumn)
        XCTAssertEqual(ignoredWindows.setFrameCalls.count, before)
        XCTAssertTrue(clock.isRunning)
    }

    func testOnlyWindowsTouchingTheScreenAnimateAndTheRestJump() {
        let (controller, windows) = makeController(Array(1...12), speed: .off)
        for id in 1...12 {
            controller.handle(.focused(WindowID(id)))
            for _ in 0..<3 { controller.handle(.cycleWidth) }
        }
        controller.handle(.focused(12))
        controller.motion = MotionSettings(speed: .normal)

        let baseline = windows.setFrameCalls.count
        controller.handle(.focused(1))
        let immediate = Set(windows.setFrameCalls.dropFirst(baseline).map(\.id.rawValue))
        XCTAssertEqual(immediate, [1, 5, 6, 7, 8])

        let afterJump = windows.setFrameCalls.count
        clock.fire(advancingBy: 0.09)
        let animated = Set(windows.setFrameCalls.dropFirst(afterJump).map(\.id.rawValue))
        XCTAssertEqual(animated, [2, 3, 4, 9, 10, 11, 12])
    }

    func testSlowFrameSnapsToTarget() {
        let (controller, windows) = makeController([1, 2, 3])
        controller.handle(.centerColumn)
        windows.onSetFrame = { [clock] in clock.time += 0.25 }
        clock.fire(advancingBy: 0.01)
        XCTAssertEqual(windows.lastRect(2), CGRect(x: -237.5, y: 10, width: 485, height: 780))
        XCTAssertEqual(windows.lastRect(3), CGRect(x: 257.5, y: 10, width: 485, height: 780))
        XCTAssertFalse(clock.isRunning)
    }

    func testNewLayoutDuringAnimationRetargetsFromCurrentPosition() {
        let (controller, windows) = makeController([1, 2, 3])
        controller.handle(.centerColumn)
        clock.fire(advancingBy: 0.09)
        let calls = windows.setFrameCalls.count
        controller.handle(.focusLeft)
        XCTAssertEqual(windows.setFrameCalls.count, calls)
        clock.fire(advancingBy: 0.3)
        XCTAssertEqual(windows.lastRect(2), CGRect(x: 10, y: 10, width: 485, height: 780))
        XCTAssertEqual(windows.lastRect(3), CGRect(x: 505, y: 10, width: 485, height: 780))
    }

    func testFailedWriteDuringAnimationCancelsOnlyThatWindow() {
        let (controller, windows) = makeController([1, 2, 3])
        controller.handle(.centerColumn)
        windows.failing = [2]
        clock.fire(advancingBy: 0.09)
        let writesAfterFailure = windows.writes(2)
        clock.fire(advancingBy: 0.3)
        XCTAssertEqual(windows.writes(2), writesAfterFailure)
        XCTAssertEqual(windows.lastRect(3), CGRect(x: 257.5, y: 10, width: 485, height: 780))
        XCTAssertTrue(controller.workspace.contains(2))
    }

    func testFocusEchoDuringAnimationDoesNotInterruptIt() {
        let (controller, windows) = makeController([1, 2, 3])
        controller.handle(.centerColumn)
        clock.fire(advancingBy: 0.09)
        let calls = windows.setFrameCalls.count
        controller.handle(.focused(3))
        XCTAssertTrue(clock.isRunning)
        XCTAssertEqual(windows.setFrameCalls.count, calls)

        clock.fire(advancingBy: 0.3)
        XCTAssertEqual(windows.lastRect(2), CGRect(x: -237.5, y: 10, width: 485, height: 780))
        XCTAssertEqual(windows.lastRect(3), CGRect(x: 257.5, y: 10, width: 485, height: 780))
    }

    func testIntermediateFramesAreMoveOnlyAndFinalFrameWritesSize() {
        let (controller, windows) = makeController([1, 2, 3])
        let baseline = windows.setFrameCalls.count
        controller.handle(.centerColumn)
        clock.fire(advancingBy: 0.09)
        let midCalls = windows.setFrameCalls.dropFirst(baseline)
        XCTAssertFalse(midCalls.isEmpty)
        XCTAssertTrue(midCalls.allSatisfy { $0.moveOnly })

        clock.fire(advancingBy: 0.3)
        let final = windows.setFrameCalls.dropFirst(baseline + midCalls.count)
        XCTAssertFalse(final.isEmpty)
        XCTAssertFalse(final.last!.moveOnly)
    }

    func testNonAnimatedWritesAreNotMoveOnly() {
        let (controller, windows) = makeController([1, 2, 3], speed: .off)
        XCTAssertTrue(windows.setFrameCalls.allSatisfy { !$0.moveOnly })
        controller.handle(.focusLeft)
        controller.handle(.cycleWidth)
        XCTAssertFalse(windows.setFrameCalls.isEmpty)
        XCTAssertTrue(windows.setFrameCalls.allSatisfy { !$0.moveOnly })
    }

    func testForcedRelayoutWritesSizeEvenAfterAnimation() {
        let (controller, windows) = makeController([1, 2, 3])
        controller.handle(.focusLeft)
        clock.fire(advancingBy: 0.3)
        let before = windows.setFrameCalls.count
        controller.relayout(force: true)
        let forced = windows.setFrameCalls.dropFirst(before)
        XCTAssertFalse(forced.isEmpty)
        XCTAssertTrue(forced.allSatisfy { !$0.moveOnly })
    }

    func testFocusOfAnotherWindowDuringAnimationStillRelayouts() {
        let (controller, _) = makeController([1, 2, 3])
        controller.handle(.focusLeft)
        XCTAssertEqual(controller.workspace.focusedWindow, 2)
        controller.handle(.focused(1))
        XCTAssertEqual(controller.workspace.focusedWindow, 1)
    }

    func testOnChangeFiresOnChangeAndNotWithoutOne() {
        let windows = FakeWindows()
        for id in [1, 2, 3] { windows.add(id) }
        let controller = Controller(windows: windows, hotkeys: FakeHotkeys(), config: config)
        var snapshots: [WorkspaceSnapshot] = []
        controller.onChange = { snapshots.append($0) }
        controller.start()
        XCTAssertEqual(snapshots.count, 1)

        controller.relayout()
        XCTAssertEqual(snapshots.count, 1)

        controller.handle(.focusLeft)
        XCTAssertEqual(snapshots.count, 2)
        XCTAssertEqual(snapshots[1].workspace.focusedWindow, 2)
    }
}
