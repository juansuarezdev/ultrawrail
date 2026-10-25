/// Editing rules for a template's columns: always 1 to 5 columns, 1 to 3 slots each, and widths
/// (3 decimals, at least `minWidth`) that sum to exactly 1.
public struct TemplateDraft: Equatable, Sendable {
    public static let minWidth = 0.15
    public static let maxColumns = 5
    public static let maxSlots = 3
    public static let snaps: [Double] = [0.25, 0.33, 0.5, 0.66, 0.75]
    public static let snapTolerance = 0.035

    public private(set) var columns: [TemplateColumn]

    public init(columns: [TemplateColumn]) {
        let kept = columns.isEmpty ? [TemplateColumn(width: 1, slots: 1)] : Array(columns.prefix(Self.maxColumns))
        self.columns = Self.normalized(kept.map {
            TemplateColumn(width: max($0.width, Self.minWidth), slots: min(max($0.slots, 1), Self.maxSlots))
        })
    }

    private static func round3(_ value: Double) -> Double { (value * 1000).rounded() / 1000 }

    /// Scales widths to sum to 1; the last column absorbs the rounding.
    private static func normalized(_ cols: [TemplateColumn]) -> [TemplateColumn] {
        let total = cols.reduce(0) { $0 + $1.width }
        var result = cols.map { TemplateColumn(width: round3($0.width / total), slots: $0.slots) }
        let others = result.dropLast().reduce(0) { $0 + $1.width }
        result[result.count - 1] = TemplateColumn(width: round3(1 - others), slots: result[result.count - 1].slots)
        return result
    }

    /// Splits the widest column in two equal halves; no-op if that would leave a half below `minWidth`.
    public mutating func addColumn() {
        guard columns.count < Self.maxColumns else { return }
        var widest = 0
        for (index, column) in columns.enumerated() where column.width > columns[widest].width { widest = index }
        guard columns[widest].width >= 2 * Self.minWidth else { return }
        let half = Self.round3(columns[widest].width / 2)
        let rest = Self.round3(columns[widest].width - half)
        columns[widest] = TemplateColumn(width: half, slots: columns[widest].slots)
        columns.insert(TemplateColumn(width: rest, slots: 1), at: widest + 1)
    }

    /// Removes a column and gives its width to a neighbour.
    public mutating func removeColumn(at index: Int) {
        guard columns.count > 1, columns.indices.contains(index) else { return }
        let neighbour = index > 0 ? index - 1 : index + 1
        columns[neighbour] = TemplateColumn(width: Self.round3(columns[neighbour].width + columns[index].width),
                                            slots: columns[neighbour].slots)
        columns.remove(at: index)
    }

    public mutating func setSlots(_ count: Int, at index: Int) {
        guard columns.indices.contains(index) else { return }
        columns[index] = TemplateColumn(width: columns[index].width, slots: min(max(count, 1), Self.maxSlots))
    }

    /// Moves the divider after column `index` to `position` (a fraction of the screen from its left edge).
    public mutating func moveDivider(_ index: Int, to position: Double) {
        guard columns.indices.contains(index), columns.indices.contains(index + 1) else { return }
        let pair = columns[index].width + columns[index + 1].width
        guard pair >= 2 * Self.minWidth else { return }
        let left = columns[..<index].reduce(0) { $0 + $1.width }
        var width = position - left
        for snap in Self.snaps where abs(width - snap) < Self.snapTolerance { width = snap }
        for snap in Self.snaps where abs((pair - width) - snap) < Self.snapTolerance { width = pair - snap }
        width = min(max(width, Self.minWidth), pair - Self.minWidth)
        let first = Self.round3(width)
        columns[index] = TemplateColumn(width: first, slots: columns[index].slots)
        columns[index + 1] = TemplateColumn(width: Self.round3(pair - first), slots: columns[index + 1].slots)
    }
}
