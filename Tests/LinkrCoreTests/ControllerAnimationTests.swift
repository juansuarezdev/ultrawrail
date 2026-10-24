import XCTest
import CoreGraphics
import LayoutEngine
@testable import LinkrCore

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
        controller.handle(.focusLeft)
        XCTAssertEqual(windows.setFrameCalls.count, before)

        clock.fire(advancingBy: 0.09)
        let mid = windows.lastRect(2)!
        XCTAssertGreaterThan(mid.minX, 0)
        XCTAssertLessThan(mid.minX, 10)

        clock.fire(advancingBy: 0.2)
        XCTAssertEqual(windows.lastRect(2), CGRect(x: 10, y: 10, width: 490, height: 780))
        XCTAssertEqual(windows.lastRect(3), CGRect(x: 510, y: 10, width: 490, height: 780))
        XCTAssertFalse(clock.isRunning)
    }

    func testSizeChangeWritesImmediately() {
        let (controller, windows) = makeController([1, 2, 3])
        controller.handle(.cycleWidth)
        XCTAssertEqual(windows.lastRect(3)!.width, 0.66 * 980, accuracy: 0.001)
    }

    func testOffWritesImmediatelyAndNeverStartsTheClock() {
        let (controller, windows) = makeController([1, 2, 3], speed: .off)
        controller.handle(.focusLeft)
        XCTAssertEqual(windows.lastRect(2), CGRect(x: 10, y: 10, width: 490, height: 780))
        XCTAssertFalse(clock.isRunning)
    }

    func testReduceMotionWritesImmediatelyUnlessIgnored() {
        let (reduced, reducedWindows) = makeController([1, 2, 3], reduceMotion: true)
        reduced.handle(.focusLeft)
        XCTAssertEqual(reducedWindows.lastRect(2), CGRect(x: 10, y: 10, width: 490, height: 780))
        XCTAssertFalse(clock.isRunning)

        let (ignored, ignoredWindows) = makeController([1, 2, 3], respectReduceMotion: false, reduceMotion: true)
        let before = ignoredWindows.setFrameCalls.count
        ignored.handle(.focusLeft)
        XCTAssertEqual(ignoredWindows.setFrameCalls.count, before)
        XCTAssertTrue(clock.isRunning)
    }

    func testAtMostFourWindowsAnimateAndTheRestJump() {
        let (controller, windows) = makeController([1, 2, 3, 4, 5, 6], speed: .off)
        for id in 1...6 {
            controller.handle(.focused(WindowID(id)))
            for _ in 0..<3 { controller.handle(.cycleWidth) }
        }
        controller.handle(.focused(6))
        controller.motion = MotionSettings(speed: .normal)

        let baseline = windows.setFrameCalls.count
        controller.handle(.focused(1))
        let immediate = Set(windows.setFrameCalls.dropFirst(baseline).map(\.id.rawValue))
        XCTAssertEqual(immediate, [1, 6])

        let afterJump = windows.setFrameCalls.count
        clock.fire(advancingBy: 0.09)
        let animated = Set(windows.setFrameCalls.dropFirst(afterJump).map(\.id.rawValue))
        XCTAssertEqual(animated, [2, 3, 4, 5])
    }

    func testSlowFrameSnapsToTarget() {
        let (controller, windows) = makeController([1, 2, 3])
        controller.handle(.focusLeft)
        windows.onSetFrame = { [clock] in clock.time += 0.05 }
        clock.fire(advancingBy: 0.01)
        XCTAssertEqual(windows.lastRect(2), CGRect(x: 10, y: 10, width: 490, height: 780))
        XCTAssertEqual(windows.lastRect(3), CGRect(x: 510, y: 10, width: 490, height: 780))
        XCTAssertFalse(clock.isRunning)
    }

    func testNewLayoutDuringAnimationRetargetsFromCurrentPosition() {
        let (controller, windows) = makeController([1, 2, 3])
        controller.handle(.focusLeft)
        clock.fire(advancingBy: 0.09)
        let calls = windows.setFrameCalls.count
        controller.handle(.focusRight)
        XCTAssertEqual(windows.setFrameCalls.count, calls)
        clock.fire(advancingBy: 0.3)
        XCTAssertEqual(windows.lastRect(2), CGRect(x: 0, y: 10, width: 490, height: 780))
        XCTAssertEqual(windows.lastRect(3), CGRect(x: 500, y: 10, width: 490, height: 780))
    }

    func testFailedWriteDuringAnimationCancelsOnlyThatWindow() {
        let (controller, windows) = makeController([1, 2, 3])
        controller.handle(.focusLeft)
        windows.failing = [2]
        clock.fire(advancingBy: 0.09)
        let writesAfterFailure = windows.writes(2)
        clock.fire(advancingBy: 0.3)
        XCTAssertEqual(windows.writes(2), writesAfterFailure)
        XCTAssertEqual(windows.lastRect(3), CGRect(x: 510, y: 10, width: 490, height: 780))
        XCTAssertTrue(controller.workspace.contains(2))
    }

    func testFocusEchoDuringAnimationDoesNotInterruptIt() {
        let (controller, windows) = makeController([1, 2, 3])
        controller.handle(.focusLeft)
        clock.fire(advancingBy: 0.09)
        let calls = windows.setFrameCalls.count
        controller.handle(.focused(2))
        XCTAssertTrue(clock.isRunning)
        XCTAssertEqual(windows.setFrameCalls.count, calls)

        clock.fire(advancingBy: 0.3)
        XCTAssertEqual(windows.lastRect(2), CGRect(x: 10, y: 10, width: 490, height: 780))
        XCTAssertEqual(windows.lastRect(3), CGRect(x: 510, y: 10, width: 490, height: 780))
    }

    func testIntermediateFramesAreMoveOnlyAndFinalFrameWritesSize() {
        let (controller, windows) = makeController([1, 2, 3])
        let baseline = windows.setFrameCalls.count
        controller.handle(.focusLeft)
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
