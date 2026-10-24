import CoreGraphics

/// Normalized geometry of the strip for the menu preview: x and width are
/// fractions of the strip width, y and height fractions of the viewport height.
public struct StripPreview: Equatable, Sendable {
    public struct Item: Equatable, Sendable {
        public var id: WindowID
        public var rect: CGRect
        public var isFocused: Bool
        public var isVisible: Bool

        public init(id: WindowID, rect: CGRect, isFocused: Bool, isVisible: Bool) {
            self.id = id
            self.rect = rect
            self.isFocused = isFocused
            self.isVisible = isVisible
        }
    }

    public var items: [Item]
    public var frameX: Double
    public var frameWidth: Double

    public init(items: [Item], frameX: Double, frameWidth: Double) {
        self.items = items
        self.frameX = frameX
        self.frameWidth = frameWidth
    }

    public init(workspace ws: Workspace, viewport: CGRect, config: LayoutConfig) {
        let total = max(Layout.stripWidth(ws, viewport: viewport, config: config), viewport.width, 1)
        let height = max(viewport.height, 1)
        let left = ws.scrollOffset
        let right = left + viewport.width
        let focused = ws.focusedWindow
        let rects = Layout.stripRects(ws, viewport: viewport, config: config)
        self.items = rects.sorted { $0.key.rawValue < $1.key.rawValue }.map { id, rect in
            Item(
                id: id,
                rect: CGRect(x: rect.minX / total, y: rect.minY / height, width: rect.width / total, height: rect.height / height),
                isFocused: id == focused,
                isVisible: rect.maxX > left && rect.minX < right
            )
        }
        self.frameX = left / total
        self.frameWidth = viewport.width / total
    }

    /// Blends `self` toward `target`; windows missing from `self` appear at their target.
    public func interpolated(to target: StripPreview, progress p: Double) -> StripPreview {
        guard p < 1 else { return target }
        let previous = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0.rect) })
        let blended = target.items.map { item -> Item in
            guard let start = previous[item.id] else { return item }
            var copy = item
            copy.rect = CGRect(
                x: start.minX + (item.rect.minX - start.minX) * p,
                y: start.minY + (item.rect.minY - start.minY) * p,
                width: start.width + (item.rect.width - start.width) * p,
                height: start.height + (item.rect.height - start.height) * p
            )
            return copy
        }
        return StripPreview(
            items: blended,
            frameX: frameX + (target.frameX - frameX) * p,
            frameWidth: frameWidth + (target.frameWidth - frameWidth) * p
        )
    }
}
