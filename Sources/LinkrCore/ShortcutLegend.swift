public enum KeyboardStyle: String, CaseIterable, Sendable {
    case windows
    case mac
}

public struct ShortcutLegendEntry: Equatable, Sendable {
    public let keys: [String]
    public let shift: Bool
    public let title: String
}

/// Human-readable list of the global shortcuts, rendered for a Windows or a Mac keyboard.
public enum ShortcutLegend {
    public static let entries: [ShortcutLegendEntry] = [
        ShortcutLegendEntry(keys: ["H", "←"], shift: false, title: "Foco a la izquierda"),
        ShortcutLegendEntry(keys: ["L", "→"], shift: false, title: "Foco a la derecha"),
        ShortcutLegendEntry(keys: ["K", "↑"], shift: false, title: "Foco arriba (pila)"),
        ShortcutLegendEntry(keys: ["J", "↓"], shift: false, title: "Foco abajo (pila)"),
        ShortcutLegendEntry(keys: ["R"], shift: false, title: "Cambiar ancho"),
        ShortcutLegendEntry(keys: ["F"], shift: false, title: "Columna a pantalla completa"),
        ShortcutLegendEntry(keys: ["C"], shift: false, title: "Centrar columna"),
        ShortcutLegendEntry(keys: ["["], shift: false, title: "Apilar a la izquierda"),
        ShortcutLegendEntry(keys: ["]"], shift: false, title: "Sacar de la pila"),
        ShortcutLegendEntry(keys: ["H", "←"], shift: true, title: "Mover columna a la izquierda"),
        ShortcutLegendEntry(keys: ["L", "→"], shift: true, title: "Mover columna a la derecha"),
        ShortcutLegendEntry(keys: ["T"], shift: false, title: "Panel de plantillas"),
    ]

    public static func line(for entry: ShortcutLegendEntry, style: KeyboardStyle) -> String {
        let modifiers: String
        switch style {
        case .windows: modifiers = entry.shift ? "Ctrl+Alt+Shift+" : "Ctrl+Alt+"
        case .mac: modifiers = entry.shift ? "⌃⌥⇧" : "⌃⌥"
        }
        return "\(modifiers)\(entry.keys.joined(separator: " / "))  ·  \(entry.title)"
    }
}
