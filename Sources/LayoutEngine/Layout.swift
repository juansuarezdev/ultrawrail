import CoreGraphics

public enum Layout {
    static func columnWidth(_ column: Column, viewport: CGRect, config: LayoutConfig) -> Double {
        column.width * (viewport.width - 2 * config.outerGap + config.gap) - config.gap
    }

    /// X of the column's left edge in strip coordinates (0 = strip origin).
    static func stripX(of index: Int, in ws: Workspace, viewport: CGRect, config: LayoutConfig) -> Double {
        var x = config.outerGap
        for column in ws.columns[..<index] {
            x += columnWidth(column, viewport: viewport, config: config) + config.gap
        }
        return x
    }

    /// Smallest scroll change that makes the focused column fully visible.
    public static func reveal(_ ws: inout Workspace, viewport: CGRect, config: LayoutConfig) {
        guard ws.columns.indices.contains(ws.focusedColumn) else { return }
        let left = stripX(of: ws.focusedColumn, in: ws, viewport: viewport, config: config)
        let right = left + columnWidth(ws.columns[ws.focusedColumn], viewport: viewport, config: config)
        if left - config.outerGap < ws.scrollOffset {
            ws.scrollOffset = left - config.outerGap
        } else if right + config.outerGap > ws.scrollOffset + viewport.width {
            ws.scrollOffset = right + config.outerGap - viewport.width
        }
    }

    /// Lowers scroll when the strip ends before the viewport's right edge, so
    /// no blank space is left after columns shrink or close. Never raises it.
    public static func removeOverscroll(_ ws: inout Workspace, viewport: CGRect, config: LayoutConfig) {
        guard !ws.columns.isEmpty, ws.scrollOffset > 0 else { return }
        let width = stripWidth(ws, viewport: viewport, config: config)
        ws.scrollOffset = max(0, min(ws.scrollOffset, width - viewport.width))
    }

    public static func center(_ ws: inout Workspace, viewport: CGRect, config: LayoutConfig) {
        guard ws.columns.indices.contains(ws.focusedColumn) else { return }
        let left = stripX(of: ws.focusedColumn, in: ws, viewport: viewport, config: config)
        let width = columnWidth(ws.columns[ws.focusedColumn], viewport: viewport, config: config)
        ws.scrollOffset = left + width / 2 - viewport.width / 2
    }

    /// Total width of the strip including the outer gap on both ends.
    public static func stripWidth(_ ws: Workspace, viewport: CGRect, config: LayoutConfig) -> Double {
        guard !ws.columns.isEmpty else { return 0 }
        return stripX(of: ws.columns.count, in: ws, viewport: viewport, config: config) - config.gap + config.outerGap
    }

    /// Rect of every window in strip coordinates: x from the strip origin,
    /// y relative to the viewport's top edge. Nothing is parked here.
    public static func stripRects(_ ws: Workspace, viewport: CGRect, config: LayoutConfig) -> [WindowID: CGRect] {
        var result: [WindowID: CGRect] = [:]
        for (index, column) in ws.columns.enumerated() {
            let width = columnWidth(column, viewport: viewport, config: config)
            let x = stripX(of: index, in: ws, viewport: viewport, config: config)
            let count = Double(column.windows.count)
            let height = max((viewport.height - 2 * config.outerGap - (count - 1) * config.gap) / count, 1)
            for (row, id) in column.windows.enumerated() {
                let y = config.outerGap + Double(row) * (height + config.gap)
                result[id] = CGRect(x: x, y: y, width: width, height: height)
            }
        }
        return result
    }

    /// Rect of every window in screen coordinates. Columns fully outside the
    /// viewport are parked with 1 px still inside it.
    public static func frames(_ ws: Workspace, viewport: CGRect, config: LayoutConfig) -> [WindowID: CGRect] {
        let rects = stripRects(ws, viewport: viewport, config: config)
        var result: [WindowID: CGRect] = [:]
        for column in ws.columns {
            guard let first = column.windows.first, let base = rects[first] else { continue }
            var x = viewport.minX + base.minX - ws.scrollOffset
            if x + base.width <= viewport.minX {
                x = viewport.minX - base.width + 1
            } else if x >= viewport.maxX {
                x = viewport.maxX - 1
            }
            for id in column.windows {
                guard let rect = rects[id] else { continue }
                result[id] = CGRect(x: x, y: viewport.minY + rect.minY, width: rect.width, height: rect.height)
            }
        }
        return result
    }
}
