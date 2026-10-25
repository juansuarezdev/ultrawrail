public struct WindowID: Hashable, Sendable, ExpressibleByIntegerLiteral {
    public let rawValue: Int
    public init(_ rawValue: Int) { self.rawValue = rawValue }
    public init(integerLiteral value: Int) { self.rawValue = value }
}

public struct LayoutConfig: Equatable, Sendable {
    public var gap: Double
    public var outerGap: Double
    public init(gap: Double = 8, outerGap: Double = 8) {
        self.gap = gap
        self.outerGap = outerGap
    }
}

public enum Command: Equatable, Sendable {
    case focusLeft, focusRight, focusUp, focusDown
    case cycleWidth, toggleFullWidth, centerColumn
    case stackLeft, unstack
    case moveColumnLeft, moveColumnRight
    case showTemplates
    case adoptWindow
}

public enum WidthPreset {
    public static let all: [Double] = [0.25, 0.33, 0.5, 0.66, 0.75]
    public static let defaultWidth: Double = 0.5
}

public struct Column: Equatable, Sendable {
    public var windows: [WindowID]
    public var width: Double
    public var restoreWidth: Double?

    public init(windows: [WindowID], width: Double = WidthPreset.defaultWidth, restoreWidth: Double? = nil) {
        self.windows = windows
        self.width = width
        self.restoreWidth = restoreWidth
    }
}
