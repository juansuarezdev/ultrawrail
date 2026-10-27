public struct WindowID: Hashable, Sendable, ExpressibleByIntegerLiteral {
    public let rawValue: Int
    public init(_ rawValue: Int) { self.rawValue = rawValue }
    public init(integerLiteral value: Int) { self.rawValue = value }
}

public enum FocusMode: String, Sendable { case minimal, centered }

public struct LayoutConfig: Equatable, Sendable {
    public var gap: Double
    public var outerGap: Double
    public var focusMode: FocusMode
    public var maxColumnWidth: Double
    public var centerStrip: Bool
    public init(gap: Double = 8, outerGap: Double = 8, focusMode: FocusMode = .minimal,
                maxColumnWidth: Double = 0, centerStrip: Bool = false) {
        self.gap = gap
        self.outerGap = outerGap
        self.focusMode = focusMode
        self.maxColumnWidth = maxColumnWidth
        self.centerStrip = centerStrip
    }
}

public enum Command: Equatable, Sendable {
    case focusLeft, focusRight, focusUp, focusDown
    case cycleWidth, toggleFullWidth, centerColumn
    case stackLeft, unstack
    case moveColumnLeft, moveColumnRight
    case showTemplates, showOverview
    case adoptWindow
    case previousPage, nextPage, moveWindowToPreviousPage, moveWindowToNextPage
    case focusZoneLeft, focusZoneRight, moveWindowToZoneLeft, moveWindowToZoneRight
}

public enum WidthPreset {
    public static let all: [Double] = [0.25, 0.33, 0.5, 0.66, 0.75]
    public static let defaultWidth: Double = 0.5
}

public struct Column: Equatable, Sendable {
    public var windows: [WindowID]
    public var width: Double
    public var restoreWidth: Double?
    /// Share of the column height of each window, top to bottom. Ignored (equal split) unless it
    /// has one positive entry per window, so adding or removing a window resets the split.
    public var heights: [Double] = []

    public init(windows: [WindowID], width: Double = WidthPreset.defaultWidth, restoreWidth: Double? = nil) {
        self.windows = windows
        self.width = width
        self.restoreWidth = restoreWidth
    }

    /// Normalized height share of each window; they add up to 1.
    public var rowFractions: [Double] {
        let count = windows.count
        guard count > 0 else { return [] }
        guard heights.count == count, heights.allSatisfy({ $0 > 0 }) else {
            return Array(repeating: 1 / Double(count), count: count)
        }
        let total = heights.reduce(0, +)
        return heights.map { $0 / total }
    }
}
