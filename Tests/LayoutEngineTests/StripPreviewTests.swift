import XCTest
import CoreGraphics
@testable import LayoutEngine

final class StripPreviewTests: XCTestCase {
    let viewport = CGRect(x: 0, y: 0, width: 1000, height: 800)
    let config = LayoutConfig(gap: 10, outerGap: 10)

    func makeWorkspace(_ count: Int) -> Workspace {
        var ws = Workspace()
        for i in 1...count { ws.addWindow(WindowID(i)) }
        return ws
    }

    func testPreviewNormalizesToStripWidthAndMarksFocusAndVisibility() {
        var ws = makeWorkspace(3)
        Layout.reveal(&ws, viewport: viewport, config: config)
        let preview = StripPreview(workspace: ws, viewport: viewport, config: config)
        XCTAssertEqual(preview.frameX, 495.0 / 1495.0, accuracy: 1e-9)
        XCTAssertEqual(preview.frameWidth, 1000.0 / 1495.0, accuracy: 1e-9)
        XCTAssertEqual(preview.items.map(\.id), [1, 2, 3])
        XCTAssertEqual(preview.items[2].rect.minX, 1000.0 / 1495.0, accuracy: 1e-9)
        XCTAssertEqual(preview.items[2].rect.minY, 10.0 / 800.0, accuracy: 1e-9)
        XCTAssertEqual(preview.items[2].rect.height, 780.0 / 800.0, accuracy: 1e-9)
        XCTAssertEqual(preview.items.map(\.isFocused), [false, false, true])
        XCTAssertEqual(preview.items.map(\.isVisible), [false, true, true])
    }

    func testStripShorterThanViewportScalesToViewportWidth() {
        let preview = StripPreview(workspace: makeWorkspace(1), viewport: viewport, config: config)
        XCTAssertEqual(preview.frameX, 0, accuracy: 1e-9)
        XCTAssertEqual(preview.frameWidth, 1, accuracy: 1e-9)
        XCTAssertEqual(preview.items[0].rect.width, 485.0 / 1000.0, accuracy: 1e-9)
    }

    func testInterpolationBlendsMatchingItemsAndKeepsNewOnesAtTarget() {
        let from = StripPreview(
            items: [.init(id: 1, rect: CGRect(x: 0, y: 0, width: 0.2, height: 1), isFocused: false, isVisible: true)],
            frameX: 0,
            frameWidth: 0.5
        )
        let to = StripPreview(
            items: [
                .init(id: 1, rect: CGRect(x: 0.4, y: 0, width: 0.2, height: 1), isFocused: true, isVisible: true),
                .init(id: 2, rect: CGRect(x: 0.7, y: 0, width: 0.2, height: 1), isFocused: false, isVisible: false),
            ],
            frameX: 0.5,
            frameWidth: 0.5
        )
        let half = from.interpolated(to: to, progress: 0.5)
        XCTAssertEqual(half.items[0].rect.minX, 0.2, accuracy: 1e-9)
        XCTAssertTrue(half.items[0].isFocused)
        XCTAssertEqual(half.items[1].rect.minX, 0.7, accuracy: 1e-9)
        XCTAssertEqual(half.frameX, 0.25, accuracy: 1e-9)
        XCTAssertEqual(from.interpolated(to: to, progress: 1), to)
    }
}
