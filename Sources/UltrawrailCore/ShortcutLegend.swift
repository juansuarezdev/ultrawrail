public enum KeyboardStyle: String, CaseIterable, Sendable {
    case windows
    case mac
}

public struct ShortcutLegendEntry: Equatable, Sendable {
    public let keys: [String]
    public let shift: Bool
    public let title: String
    /// Page shortcuts use Win+Alt (⌘⌥) instead of Ctrl+Alt (⌃⌥).
    public var usesCommand = false
    /// Zone shortcuts use Ctrl+Alt+Win (⌃⌥⌘); only meaningful together with `usesCommand`.
    public var withControl = false
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
        ShortcutLegendEntry(keys: ["A"], shift: false, title: "Añadir ventana nueva a la tira"),
        ShortcutLegendEntry(keys: ["T"], shift: false, title: "Panel de plantillas"),
        ShortcutLegendEntry(keys: ["←", "→"], shift: false, title: "Página anterior / siguiente", usesCommand: true),
        ShortcutLegendEntry(keys: ["←", "→"], shift: true, title: "Mover ventana a la página anterior / siguiente", usesCommand: true),
        ShortcutLegendEntry(keys: ["←", "→"], shift: false, title: "Zona anterior / siguiente", usesCommand: true, withControl: true),
        ShortcutLegendEntry(keys: ["←", "→"], shift: true, title: "Mover ventana a la zona anterior / siguiente", usesCommand: true, withControl: true),
    ]

    public static func line(for entry: ShortcutLegendEntry, style: KeyboardStyle) -> String {
        let modifiers: String
        switch style {
        case .windows:
            let base = entry.usesCommand ? (entry.withControl ? "Ctrl+Alt+Win+" : "Win+Alt+") : "Ctrl+Alt+"
            modifiers = entry.shift ? base + "Shift+" : base
        case .mac:
            let base = entry.usesCommand ? (entry.withControl ? "⌃⌥⌘" : "⌘⌥") : "⌃⌥"
            modifiers = entry.shift ? base + "⇧" : base
        }
        return "\(modifiers)\(entry.keys.joined(separator: " / "))  ·  \(entry.title)"
    }
}
