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

    /// Rebuilds the strip from a template. `assignment` has one entry per slot, column by column.
    /// Windows that are not assigned (or whose entry is nil, repeated or unknown) go to extra
    /// default-width columns at the end, so no window is lost.
    public mutating func apply(_ template: Template, assignment: [WindowID?]) {
        let existing = allWindows
        let focused = focusedWindow
        var used = Set<WindowID>()
        var rebuilt: [Column] = []
        var slot = 0
        for spec in template.columns {
            var windows: [WindowID] = []
            for _ in 0..<spec.slots {
                if slot < assignment.count, let id = assignment[slot],
                   existing.contains(id), used.insert(id).inserted {
                    windows.append(id)
                }
                slot += 1
            }
            if !windows.isEmpty { rebuilt.append(Column(windows: windows, width: spec.width)) }
        }
        for id in existing where !used.contains(id) { rebuilt.append(Column(windows: [id])) }
        columns = rebuilt
        scrollOffset = 0
        focusedColumn = 0
        focusedRow = 0
        if let focused { focus(window: focused) }
    }

    /// Pure model mutation. `centerColumn` is a no-op here: centering needs the
    /// viewport and is handled by `perform(_:viewport:config:)`.
    public mutating func apply(_ command: Command) {
        guard !columns.isEmpty else { return }
        switch command {
        case .focusLeft:
            focusedColumn = max(0, focusedColumn - 1)
            focusedRow = min(focusedRow, columns[focusedColumn].windows.count - 1)
        case .focusRight:
            focusedColumn = min(columns.count - 1, focusedColumn + 1)
            focusedRow = min(focusedRow, columns[focusedColumn].windows.count - 1)
        case .cycleWidth:
            let current = columns[focusedColumn].width
            columns[focusedColumn].width = WidthPreset.all.first { $0 > current + 0.001 } ?? WidthPreset.all[0]
            columns[focusedColumn].restoreWidth = nil
        case .toggleFullWidth:
            if columns[focusedColumn].width >= 1.0 {
                columns[focusedColumn].width = columns[focusedColumn].restoreWidth ?? WidthPreset.defaultWidth
                columns[focusedColumn].restoreWidth = nil
            } else {
                columns[focusedColumn].restoreWidth = columns[focusedColumn].width
                columns[focusedColumn].width = 1.0
            }
        case .focusUp:
            focusedRow = max(0, focusedRow - 1)
        case .focusDown:
            focusedRow = min(columns[focusedColumn].windows.count - 1, focusedRow + 1)
        case .stackLeft:
            stackLeft()
        case .unstack:
            unstack()
        case .moveColumnLeft:
            moveColumn(by: -1)
        case .moveColumnRight:
            moveColumn(by: 1)
        case .centerColumn, .showTemplates, .adoptWindow:
            break
        }
    }

    private mutating func stackLeft() {
        guard focusedColumn > 0, let id = focusedWindow else { return }
        columns[focusedColumn].windows.remove(at: focusedRow)
        if columns[focusedColumn].windows.isEmpty { columns.remove(at: focusedColumn) }
        focusedColumn -= 1
        columns[focusedColumn].windows.append(id)
        focusedRow = columns[focusedColumn].windows.count - 1
    }

    private mutating func moveColumn(by delta: Int) {
        let target = focusedColumn + delta
        guard columns.indices.contains(target) else { return }
        columns.swapAt(focusedColumn, target)
        focusedColumn = target
    }

    private mutating func unstack() {
        guard columns[focusedColumn].windows.count > 1, let id = focusedWindow else { return }
        columns[focusedColumn].windows.remove(at: focusedRow)
        columns.insert(Column(windows: [id]), at: focusedColumn + 1)
        focusedColumn += 1
        focusedRow = 0
    }
}
