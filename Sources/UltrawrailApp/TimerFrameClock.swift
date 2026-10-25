import Foundation
import UltrawrailCore

@MainActor
final class TimerFrameClock: FrameClock {
    private var timer: Timer?

    func start(_ tick: @escaping () -> Void) {
        stop()
        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { _ in
            MainActor.assumeIsolated { tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }
}
