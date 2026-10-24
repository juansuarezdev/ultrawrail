import AppKit
import LayoutEngine
import QuartzCore

@MainActor
final class StripPreviewView: NSView {
    /// Seconds; 0 jumps straight to the new state.
    var animationDuration: Double = 0.18

    private var shown = StripPreview(items: [], frameX: 0, frameWidth: 1)
    private var from = StripPreview(items: [], frameX: 0, frameWidth: 1)
    private var target = StripPreview(items: [], frameX: 0, frameWidth: 1)
    private var startTime = 0.0
    private var timer: Timer?
    private var isLive = false

    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
    }

    required init?(coder: NSCoder) {
        fatalError("not used")
    }

    func menuDidOpen() {
        isLive = true
    }

    func menuDidClose() {
        isLive = false
        stopTimer()
        shown = target
        needsDisplay = true
    }

    func show(_ preview: StripPreview) {
        target = preview
        guard isLive, animationDuration > 0 else {
            stopTimer()
            shown = preview
            needsDisplay = true
            return
        }
        from = shown
        startTime = CACurrentMediaTime()
        guard timer == nil else { return }
        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.step() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func step() {
        let t = (CACurrentMediaTime() - startTime) / animationDuration
        if t >= 1 {
            shown = target
            stopTimer()
        } else {
            shown = from.interpolated(to: target, progress: Easing.easeOut(t))
        }
        needsDisplay = true
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    override func draw(_ dirtyRect: NSRect) {
        let inset: CGFloat = 12
        let strip = NSRect(x: inset, y: 8, width: bounds.width - 2 * inset, height: 52)
        let bar = NSRect(x: inset, y: 70, width: bounds.width - 2 * inset, height: 5)

        for item in shown.items {
            let rect = NSRect(
                x: strip.minX + item.rect.minX * strip.width,
                y: strip.minY + item.rect.minY * strip.height,
                width: item.rect.width * strip.width,
                height: item.rect.height * strip.height
            ).insetBy(dx: 1, dy: 1)
            let path = NSBezierPath(roundedRect: rect, xRadius: 3, yRadius: 3)
            let base: NSColor = item.isFocused ? .controlAccentColor : .secondaryLabelColor
            base.withAlphaComponent(item.isVisible ? 0.9 : 0.35).setFill()
            path.fill()
            if item.isFocused {
                NSColor.labelColor.setStroke()
                path.lineWidth = 1.5
                path.stroke()
            }
        }

        let frameRect = NSRect(
            x: strip.minX + shown.frameX * strip.width,
            y: strip.minY - 4,
            width: shown.frameWidth * strip.width,
            height: strip.height + 8
        )
        let framePath = NSBezierPath(roundedRect: frameRect, xRadius: 5, yRadius: 5)
        NSColor.labelColor.withAlphaComponent(0.6).setStroke()
        framePath.lineWidth = 1.5
        framePath.stroke()

        NSColor.quaternaryLabelColor.setFill()
        NSBezierPath(roundedRect: bar, xRadius: 2.5, yRadius: 2.5).fill()
        let thumbWidth = min(max(shown.frameWidth, 0.02), 1) * bar.width
        let thumbX = bar.minX + min(max(shown.frameX, 0), max(1 - shown.frameWidth, 0)) * bar.width
        NSColor.secondaryLabelColor.setFill()
        NSBezierPath(
            roundedRect: NSRect(x: thumbX, y: bar.minY, width: thumbWidth, height: bar.height),
            xRadius: 2.5,
            yRadius: 2.5
        ).fill()
    }
}
