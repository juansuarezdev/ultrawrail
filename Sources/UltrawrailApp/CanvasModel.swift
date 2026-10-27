import AppKit
import CoreGraphics
import LayoutEngine
import SwiftUI
import UltrawrailCore

struct CanvasWindow: Identifiable {
    let id: WindowID
    let rect: CGRect
    let columnSize: Int
    /// Width of the zone the window lives in, to turn a dragged width into a fraction.
    let viewportWidth: CGFloat
}

struct CanvasPage: Identifiable {
    let zone: Int
    let page: Int
    let rect: CGRect
    let isCurrent: Bool
    let windows: [CanvasWindow]
    let isNewSlot: Bool
    var id: String { "\(zone).\(page)" }
}

enum CanvasDrop: Equatable {
    case stack(onto: WindowID)
    case page(zone: Int, page: Int)
}

/// World-space layout of every zone and page, plus pan, zoom and drag state.
@MainActor
final class CanvasModel: ObservableObject {
    static let headerHeight: CGFloat = 44
    private static let columnGap: CGFloat = 12
    private static let pageGap: CGFloat = 140
    private static let zoneGap: CGFloat = 220
    private static let maxPages = 9

    @Published private(set) var pages: [CanvasPage] = []
    @Published var scale: CGFloat = 0.3
    @Published var offset: CGSize = .zero
    @Published var thumbnails: [WindowID: NSImage] = [:]
    @Published var chips: [WindowID: (name: String, icon: NSImage?)] = [:]
    @Published var dragging: WindowID?
    @Published var dragDelta: CGSize = .zero
    @Published var dropTarget: CanvasDrop?
    /// A column being resized with its edge handle: a window of it and the width change in world units.
    @Published var resizing: (id: WindowID, delta: CGFloat)?
    @Published var hasCapturePermission = true
    @Published var focusedWindow: WindowID?
    @Published var unassigned: [WindowID] = []
    /// A tray window being dragged: its id and the cursor in screen space.
    @Published var trayDrag: (id: WindowID, location: CGPoint)?

    var screenSize: CGSize = CGSize(width: 1440, height: 900)
    var onReveal: ((WindowID) -> Void)?
    var onResize: ((WindowID, Double) -> Void)?
    var onAssignToCurrent: ((WindowID) -> Void)?
    var onDrop: ((WindowID, CanvasDrop) -> Void)?

    static let minScale: CGFloat = 0.08
    static let maxScale: CGFloat = 1.5

    var bounds: CGRect { pages.map(\.rect).reduce(.null) { $0.union($1) } }

    func load(_ overview: [ZoneOverview], focused: WindowID?) {
        focusedWindow = focused
        var result: [CanvasPage] = []
        var y: CGFloat = 0
        for (zone, value) in overview.enumerated() {
            let viewport = value.viewport.isEmpty ? CGRect(x: 0, y: 0, width: 1000, height: 800) : value.viewport
            var x: CGFloat = 0
            for (page, content) in value.pages.enumerated() {
                let strip = Self.strip(content.columns, viewport: viewport)
                let width = max(viewport.width, strip.width)
                let card = CGRect(x: x, y: y, width: width, height: viewport.height + Self.headerHeight)
                result.append(CanvasPage(zone: zone, page: page, rect: card, isCurrent: content.isCurrent,
                                         windows: strip.windows.map { window in
                    CanvasWindow(id: window.id, rect: window.rect.offsetBy(dx: card.minX, dy: card.minY + Self.headerHeight),
                                 columnSize: window.columnSize, viewportWidth: window.viewportWidth)
                }, isNewSlot: false))
                x += width + Self.pageGap
            }
            if value.pages.count < Self.maxPages {
                result.append(CanvasPage(zone: zone, page: value.pages.count,
                                         rect: CGRect(x: x, y: y, width: viewport.width, height: viewport.height + Self.headerHeight),
                                         isCurrent: false, windows: [], isNewSlot: true))
            }
            y += viewport.height + Self.headerHeight + Self.zoneGap
        }
        pages = result
    }

    private static func strip(_ columns: [Column], viewport: CGRect) -> (width: CGFloat, windows: [CanvasWindow]) {
        var x: CGFloat = 0
        var windows: [CanvasWindow] = []
        for column in columns {
            let width = CGFloat(column.width) * viewport.width
            let count = CGFloat(column.windows.count)
            let height = (viewport.height - columnGap * (count - 1)) / count
            for (row, id) in column.windows.enumerated() {
                windows.append(CanvasWindow(id: id, rect: CGRect(x: x, y: CGFloat(row) * (height + columnGap), width: width, height: height),
                                            columnSize: column.windows.count, viewportWidth: viewport.width))
            }
            x += width + columnGap
        }
        return (max(0, x - columnGap), windows)
    }

    // MARK: Camera

    func fit() {
        let box = bounds
        guard !box.isNull, box.width > 0, box.height > 0 else { return }
        let target = min(screenSize.width * 0.86 / box.width, screenSize.height * 0.78 / box.height)
        scale = min(max(target, Self.minScale), 0.6)
        offset = CGSize(width: (screenSize.width - box.width * scale) / 2 - box.minX * scale,
                        height: (screenSize.height - box.height * scale) / 2 - box.minY * scale)
    }

    func zoom(by factor: CGFloat, around anchor: CGPoint? = nil) {
        let center = anchor ?? CGPoint(x: screenSize.width / 2, y: screenSize.height / 2)
        let next = min(max(scale * factor, Self.minScale), Self.maxScale)
        let k = next / scale
        offset = CGSize(width: center.x - (center.x - offset.width) * k, height: center.y - (center.y - offset.height) * k)
        scale = next
    }

    func pan(by delta: CGSize) {
        offset = CGSize(width: offset.width + delta.width, height: offset.height + delta.height)
    }

    // MARK: Dragging

    func worldPoint(fromScreen point: CGPoint) -> CGPoint {
        CGPoint(x: (point.x - offset.width) / scale, y: (point.y - offset.height) / scale)
    }

    func sameColumn(_ a: WindowID, _ b: WindowID) -> Bool {
        if a == b { return true }
        guard let page = pages.first(where: { $0.windows.contains { $0.id == a } }),
              let first = page.windows.first(where: { $0.id == a }),
              let second = page.windows.first(where: { $0.id == b }) else { return false }
        return first.rect.minX == second.rect.minX
    }

    func rect(of id: WindowID) -> CGRect? {
        pages.lazy.flatMap(\.windows).first { $0.id == id }?.rect
    }

    func target(at point: CGPoint, excluding id: WindowID) -> CanvasDrop? {
        for page in pages {
            for window in page.windows where window.id != id && window.rect.contains(point) {
                return .stack(onto: window.id)
            }
        }
        if let page = pages.first(where: { $0.rect.contains(point) }) {
            return .page(zone: page.zone, page: page.page)
        }
        return nil
    }

    func updateDrag(_ id: WindowID, translation: CGSize) {
        dragging = id
        dragDelta = CGSize(width: translation.width / scale, height: translation.height / scale)
        guard let rect = rect(of: id) else { return }
        let point = CGPoint(x: rect.midX + dragDelta.width, y: rect.midY + dragDelta.height)
        dropTarget = target(at: point, excluding: id)
    }

    func updateTrayDrag(_ id: WindowID, location: CGPoint) {
        trayDrag = (id, location)
        dropTarget = target(at: worldPoint(fromScreen: location), excluding: id)
    }

    func endTrayDrag(_ id: WindowID) {
        let target = dropTarget
        trayDrag = nil
        dropTarget = nil
        if let target { onDrop?(id, target) }
    }

    func updateResize(_ id: WindowID, translation: CGFloat) {
        resizing = (id, translation / scale)
    }

    func endResize(_ window: CanvasWindow) {
        guard let resizing, resizing.id == window.id else { return }
        self.resizing = nil
        let width = window.rect.width + resizing.delta
        onResize?(window.id, Double(width / window.viewportWidth))
    }

    func endDrag(_ id: WindowID) {
        let target = dropTarget
        dragging = nil
        dragDelta = .zero
        dropTarget = nil
        if let target { onDrop?(id, target) }
    }
}

/// Captures live thumbnails of other apps' windows. Needs the Screen Recording permission.
@MainActor
enum WindowSnapshotter {
    static var hasPermission: Bool { CGPreflightScreenCaptureAccess() }

    static func requestPermission() { _ = CGRequestScreenCaptureAccess() }

    static func image(forWindowNumber number: UInt32) -> NSImage? {
        guard let image = CGWindowListCreateImage(.null, .optionIncludingWindow, CGWindowID(number),
                                                  [.boundsIgnoreFraming, .bestResolution]),
              image.width > 1, image.height > 1 else { return nil }
        return NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
    }
}
