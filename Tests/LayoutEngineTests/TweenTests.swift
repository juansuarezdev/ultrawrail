import XCTest
import CoreGraphics
@testable import LayoutEngine

final class TweenTests: XCTestCase {
    let start = CGRect(x: 0, y: 10, width: 490, height: 780)
    let end = CGRect(x: 100, y: 10, width: 490, height: 780)

    func testEaseOutEndpointsClampAndIncrease() {
        XCTAssertEqual(Easing.easeOut(0), 0)
        XCTAssertEqual(Easing.easeOut(1), 1)
        XCTAssertEqual(Easing.easeOut(-1), 0)
        XCTAssertEqual(Easing.easeOut(2), 1)
        var previous = 0.0
        for step in 1...10 {
            let value = Easing.easeOut(Double(step) / 10)
            XCTAssertGreaterThan(value, previous)
            previous = value
        }
        XCTAssertGreaterThan(Easing.easeOut(0.5), 0.5)
    }

    func testFramesInterpolateAndLandExactlyOnTarget() {
        let tween = Tween(from: [1: start], to: [1: end], duration: 0.2)
        XCTAssertEqual(tween.frames(at: 0)[1], start)
        XCTAssertEqual(tween.frames(at: 0.1)[1]!.minX, 87.5, accuracy: 0.0001)
        XCTAssertEqual(tween.frames(at: 0.2)[1], end)
        XCTAssertEqual(tween.frames(at: 5)[1], end)
        XCTAssertFalse(tween.isFinished(at: 0.19))
        XCTAssertTrue(tween.isFinished(at: 0.2))
    }

    func testZeroDurationIsFinishedAndReturnsTarget() {
        let tween = Tween(from: [1: start], to: [1: end], duration: 0)
        XCTAssertTrue(tween.isFinished(at: 0))
        XCTAssertEqual(tween.frames(at: 0)[1], end)
    }

    func testWindowWithoutOriginJumpsToTarget() {
        let tween = Tween(from: [:], to: [1: end], duration: 0.2)
        XCTAssertEqual(tween.frames(at: 0)[1], end)
    }

    func testRemovingDropsOnlyThatWindow() {
        let tween = Tween(from: [1: start, 2: start], to: [1: end, 2: end], duration: 0.2)
        let reduced = tween.removing(1)
        XCTAssertEqual(Set(reduced.to.keys), [2])
        XCTAssertFalse(reduced.isEmpty)
        XCTAssertTrue(reduced.removing(2).isEmpty)
    }
}
