public struct TemplateColumn: Equatable, Sendable {
    public let width: Double
    public let slots: Int
    public init(width: Double, slots: Int) {
        self.width = width
        self.slots = slots
    }
}

public struct Template: Equatable, Sendable {
    public let id: String
    public let name: String
    public let columns: [TemplateColumn]

    public init(id: String, name: String, columns: [TemplateColumn]) {
        self.id = id
        self.name = name
        self.columns = columns
    }

    public var slotCount: Int { columns.reduce(0) { $0 + $1.slots } }

    /// Index of the template column that holds the given slot (slots count column by column).
    public func slotColumn(of slot: Int) -> Int {
        var remaining = slot
        for (index, column) in columns.enumerated() {
            if remaining < column.slots { return index }
            remaining -= column.slots
        }
        return max(0, columns.count - 1)
    }

    /// The first `slotCount` windows, in order, fill the slots; the rest stay unassigned.
    public func defaultAssignment(for windows: [WindowID]) -> [WindowID?] {
        (0..<slotCount).map { $0 < windows.count ? windows[$0] : nil }
    }

    public static let all: [Template] = [
        Template(id: "halves", name: "Mitades",
                 columns: [TemplateColumn(width: 0.5, slots: 1), TemplateColumn(width: 0.5, slots: 1)]),
        Template(id: "main-side", name: "Principal + lateral",
                 columns: [TemplateColumn(width: 0.66, slots: 1), TemplateColumn(width: 0.33, slots: 1)]),
        Template(id: "half-stack", name: "Mitad + dos apiladas",
                 columns: [TemplateColumn(width: 0.5, slots: 1), TemplateColumn(width: 0.5, slots: 2)]),
    ]
}
