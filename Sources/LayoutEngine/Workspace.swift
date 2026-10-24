/// Invariant: every column has at least one window; focusedColumn/focusedRow
/// always point at an existing window while the workspace is non-empty.
public struct Workspace: Equatable, Sendable {
    public private(set) var columns: [Column] = []
    public private(set) var focusedColumn = 0
    public private(set) var focusedRow = 0
    public var scrollOffset: Double = 0

    public init() {}

    public var focusedWindow: WindowID? {
        guard columns.indices.contains(focusedColumn) else { return nil }
        return columns[focusedColumn].windows[focusedRow]
    }

    public var allWindows: [WindowID] { columns.flatMap(\.windows) }

    public func contains(_ id: WindowID) -> Bool { allWindows.contains(id) }

    public mutating func addWindow(_ id: WindowID) {
        guard !contains(id) else { return }
        let index = columns.isEmpty ? 0 : focusedColumn + 1
        columns.insert(Column(windows: [id]), at: index)
        focusedColumn = index
        focusedRow = 0
    }

    public mutating func removeWindow(_ id: WindowID) {
        guard let c = columns.firstIndex(where: { $0.windows.contains(id) }),
              let r = columns[c].windows.firstIndex(of: id) else { return }
        columns[c].windows.remove(at: r)
        if columns[c].windows.isEmpty {
            columns.remove(at: c)
            if c < focusedColumn { focusedColumn -= 1 }
        } else if c == focusedColumn, r < focusedRow {
            focusedRow -= 1
        }
        if columns.isEmpty {
            focusedColumn = 0
            focusedRow = 0
            scrollOffset = 0
            return
        }
        focusedColumn = min(focusedColumn, columns.count - 1)
        focusedRow = min(focusedRow, columns[focusedColumn].windows.count - 1)
    }

    public mutating func focus(window id: WindowID) {
        guard let c = columns.firstIndex(where: { $0.windows.contains(id) }),
              let r = columns[c].windows.firstIndex(of: id) else { return }
        focusedColumn = c
        focusedRow = r
    }
}
