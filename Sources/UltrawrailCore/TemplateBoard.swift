import LayoutEngine

/// Panel state: the chosen template, the open windows and which window sits in each slot.
public struct TemplateBoard: Equatable, Sendable {
    public private(set) var template: Template
    public let windows: [WindowID]
    public private(set) var assignment: [WindowID?]

    public init(template: Template, windows: [WindowID]) {
        self.template = template
        self.windows = windows
        self.assignment = template.defaultAssignment(for: windows)
    }

    public var unassigned: [WindowID] {
        windows.filter { id in !assignment.contains(id) }
    }

    public mutating func select(_ template: Template) {
        self.template = template
        assignment = template.defaultAssignment(for: windows)
    }

    /// Puts `id` in `slot`. If the slot was occupied, the occupant takes the slot `id` came
    /// from (swap) or becomes unassigned when `id` came from the list.
    public mutating func drop(_ id: WindowID, onSlot slot: Int) {
        guard windows.contains(id), assignment.indices.contains(slot) else { return }
        let source = assignment.firstIndex(of: id)
        let occupant = assignment[slot]
        if let source { assignment[source] = occupant }
        assignment[slot] = id
    }

    public mutating func unassign(_ id: WindowID) {
        if let index = assignment.firstIndex(of: id) { assignment[index] = nil }
    }
}
