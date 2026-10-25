/// How windows that open after launch are handled.
public enum PlacementMode: String, CaseIterable, Sendable {
    /// New windows stay where the app put them until the adopt shortcut is pressed.
    case manual
    /// New windows join the strip as soon as they open.
    case automatic
}
