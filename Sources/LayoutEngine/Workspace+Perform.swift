import CoreGraphics

public extension Workspace {
    /// Applies a command and leaves `scrollOffset` consistent with the new focus.
    mutating func perform(_ command: Command, viewport: CGRect, config: LayoutConfig) {
        apply(command)
        if command == .centerColumn {
            Layout.center(&self, viewport: viewport, config: config)
        } else {
            Layout.reveal(&self, viewport: viewport, config: config)
        }
    }
}
