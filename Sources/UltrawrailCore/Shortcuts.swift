import LayoutEngine

public enum KeyboardStyle: String, CaseIterable, Sendable {
    case windows
    case mac
}

/// A global key combination. `keyCode` is a Carbon virtual key code.
public struct KeyCombo: Codable, Equatable, Hashable, Sendable {
    public var keyCode: Int
    public var control: Bool
    public var option: Bool
    public var command: Bool
    public var shift: Bool

    public init(keyCode: Int, control: Bool = false, option: Bool = false, command: Bool = false, shift: Bool = false) {
        self.keyCode = keyCode
        self.control = control
        self.option = option
        self.command = command
        self.shift = shift
    }

    public func display(style: KeyboardStyle) -> String {
        let key = KeyNames.name(for: keyCode)
        switch style {
        case .windows:
            var parts: [String] = []
            if control { parts.append("Ctrl") }
            if option { parts.append("Alt") }
            if command { parts.append("Win") }
            if shift { parts.append("Shift") }
            return (parts + [key]).joined(separator: "+")
        case .mac:
            return (control ? "⌃" : "") + (option ? "⌥" : "") + (command ? "⌘" : "") + (shift ? "⇧" : "") + key
        }
    }
}

enum KeyNames {
    static func name(for keyCode: Int) -> String { table[keyCode] ?? "Tecla \(keyCode)" }

    private static let table: [Int: String] = [
        0: "A", 11: "B", 8: "C", 2: "D", 14: "E", 3: "F", 5: "G", 4: "H", 34: "I", 38: "J", 40: "K", 37: "L", 46: "M",
        45: "N", 31: "O", 35: "P", 12: "Q", 15: "R", 1: "S", 17: "T", 32: "U", 9: "V", 13: "W", 7: "X", 16: "Y", 6: "Z",
        18: "1", 19: "2", 20: "3", 21: "4", 23: "5", 22: "6", 26: "7", 28: "8", 25: "9", 29: "0",
        27: "-", 24: "=", 33: "[", 30: "]", 41: ";", 39: "'", 43: ",", 47: ".", 44: "/", 42: "\\", 50: "`",
        123: "←", 124: "→", 125: "↓", 126: "↑",
        49: "Espacio", 36: "Intro", 48: "Tab", 51: "Retroceso", 53: "Esc",
        122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6", 98: "F7", 100: "F8", 101: "F9",
        109: "F10", 103: "F11", 111: "F12",
    ]
}

/// A shortcut the user can rebind.
public struct ShortcutBinding: Equatable, Sendable {
    public let id: String
    public let title: String
    public let command: Command
    public let defaultCombo: KeyCombo

    public init(id: String, title: String, command: Command, defaultCombo: KeyCombo) {
        self.id = id
        self.title = title
        self.command = command
        self.defaultCombo = defaultCombo
    }
}

/// A binding together with the combo currently in effect.
public struct ResolvedShortcut: Equatable, Sendable {
    public let binding: ShortcutBinding
    public let combo: KeyCombo
    public var id: String { binding.id }
    public var title: String { binding.title }
    public var command: Command { binding.command }
}

public enum ShortcutIssue: Equatable, Sendable {
    case needsTwoModifiers
    case reservedBySystem
    case conflict(title: String)
}

public enum ShortcutCatalog {
    private static func combo(_ key: Int, shift: Bool = false) -> KeyCombo {
        KeyCombo(keyCode: key, control: true, option: true, shift: shift)
    }

    private static func page(_ key: Int, shift: Bool = false) -> KeyCombo {
        KeyCombo(keyCode: key, option: true, command: true, shift: shift)
    }

    private static func zone(_ key: Int, shift: Bool = false) -> KeyCombo {
        KeyCombo(keyCode: key, control: true, option: true, command: true, shift: shift)
    }

    // Carbon virtual key codes.
    private static let left = 123, right = 124, down = 125, up = 126

    public static let bindings: [ShortcutBinding] = [
        ShortcutBinding(id: "focusLeft.h", title: "Foco a la izquierda", command: .focusLeft, defaultCombo: combo(4)),
        ShortcutBinding(id: "focusLeft.arrow", title: "Foco a la izquierda", command: .focusLeft, defaultCombo: combo(left)),
        ShortcutBinding(id: "focusRight.l", title: "Foco a la derecha", command: .focusRight, defaultCombo: combo(37)),
        ShortcutBinding(id: "focusRight.arrow", title: "Foco a la derecha", command: .focusRight, defaultCombo: combo(right)),
        ShortcutBinding(id: "focusUp.k", title: "Foco arriba (pila)", command: .focusUp, defaultCombo: combo(40)),
        ShortcutBinding(id: "focusUp.arrow", title: "Foco arriba (pila)", command: .focusUp, defaultCombo: combo(up)),
        ShortcutBinding(id: "focusDown.j", title: "Foco abajo (pila)", command: .focusDown, defaultCombo: combo(38)),
        ShortcutBinding(id: "focusDown.arrow", title: "Foco abajo (pila)", command: .focusDown, defaultCombo: combo(down)),
        ShortcutBinding(id: "cycleWidth", title: "Cambiar ancho", command: .cycleWidth, defaultCombo: combo(15)),
        ShortcutBinding(id: "toggleFullWidth", title: "Columna a pantalla completa", command: .toggleFullWidth, defaultCombo: combo(3)),
        ShortcutBinding(id: "centerColumn", title: "Centrar columna", command: .centerColumn, defaultCombo: combo(8)),
        ShortcutBinding(id: "stackLeft", title: "Apilar a la izquierda", command: .stackLeft, defaultCombo: combo(33)),
        ShortcutBinding(id: "unstack", title: "Sacar de la pila", command: .unstack, defaultCombo: combo(30)),
        ShortcutBinding(id: "moveColumnLeft.h", title: "Mover columna a la izquierda", command: .moveColumnLeft, defaultCombo: combo(4, shift: true)),
        ShortcutBinding(id: "moveColumnLeft.arrow", title: "Mover columna a la izquierda", command: .moveColumnLeft, defaultCombo: combo(left, shift: true)),
        ShortcutBinding(id: "moveColumnRight.l", title: "Mover columna a la derecha", command: .moveColumnRight, defaultCombo: combo(37, shift: true)),
        ShortcutBinding(id: "moveColumnRight.arrow", title: "Mover columna a la derecha", command: .moveColumnRight, defaultCombo: combo(right, shift: true)),
        ShortcutBinding(id: "adoptWindow", title: "Añadir ventana nueva a la tira", command: .adoptWindow, defaultCombo: combo(0)),
        ShortcutBinding(id: "showTemplates", title: "Panel de plantillas", command: .showTemplates, defaultCombo: combo(17)),
        ShortcutBinding(id: "previousPage", title: "Página anterior", command: .previousPage, defaultCombo: page(left)),
        ShortcutBinding(id: "nextPage", title: "Página siguiente", command: .nextPage, defaultCombo: page(right)),
        ShortcutBinding(id: "moveWindowToPreviousPage", title: "Mover ventana a la página anterior", command: .moveWindowToPreviousPage, defaultCombo: page(left, shift: true)),
        ShortcutBinding(id: "moveWindowToNextPage", title: "Mover ventana a la página siguiente", command: .moveWindowToNextPage, defaultCombo: page(right, shift: true)),
        ShortcutBinding(id: "focusZoneLeft", title: "Zona anterior", command: .focusZoneLeft, defaultCombo: zone(left)),
        ShortcutBinding(id: "focusZoneRight", title: "Zona siguiente", command: .focusZoneRight, defaultCombo: zone(right)),
        ShortcutBinding(id: "moveWindowToZoneLeft", title: "Mover ventana a la zona anterior", command: .moveWindowToZoneLeft, defaultCombo: zone(left, shift: true)),
        ShortcutBinding(id: "moveWindowToZoneRight", title: "Mover ventana a la zona siguiente", command: .moveWindowToZoneRight, defaultCombo: zone(right, shift: true)),
    ]
}

/// The catalog plus the user's overrides.
public struct ShortcutMap: Equatable, Sendable {
    public private(set) var overrides: [String: KeyCombo]

    public init(overrides: [String: KeyCombo] = [:]) {
        let known = Set(ShortcutCatalog.bindings.map(\.id))
        self.overrides = overrides.filter { known.contains($0.key) }
    }

    public func combo(for id: String) -> KeyCombo? {
        overrides[id] ?? ShortcutCatalog.bindings.first { $0.id == id }?.defaultCombo
    }

    public var resolved: [ResolvedShortcut] {
        ShortcutCatalog.bindings.map { ResolvedShortcut(binding: $0, combo: overrides[$0.id] ?? $0.defaultCombo) }
    }

    public func isCustomized(_ id: String) -> Bool { overrides[id] != nil }

    /// Why `candidate` cannot be assigned to `id`, or nil when it can.
    public func issue(for candidate: KeyCombo, assigningTo id: String) -> ShortcutIssue? {
        let held = [candidate.control, candidate.option, candidate.command].filter { $0 }.count
        if held < 2 { return .needsTwoModifiers }
        if Self.reserved.contains(where: { $0.keyCode == candidate.keyCode && $0.control == candidate.control
            && $0.option == candidate.option && $0.command == candidate.command && !candidate.shift }) {
            return .reservedBySystem
        }
        if let other = resolved.first(where: { $0.id != id && $0.combo == candidate }) {
            return .conflict(title: other.title)
        }
        return nil
    }

    /// Assigns `candidate` to `id` if valid; returns the issue otherwise.
    @discardableResult
    public mutating func assign(_ candidate: KeyCombo, to id: String) -> ShortcutIssue? {
        if let issue = issue(for: candidate, assigningTo: id) { return issue }
        guard let binding = ShortcutCatalog.bindings.first(where: { $0.id == id }) else { return nil }
        if candidate == binding.defaultCombo { overrides[id] = nil } else { overrides[id] = candidate }
        return nil
    }

    public mutating func reset(_ id: String) { overrides[id] = nil }
    public mutating func resetAll() { overrides = [:] }

    // Force quit, lock screen, emoji picker.
    private static let reserved: [KeyCombo] = [
        KeyCombo(keyCode: 53, option: true, command: true),
        KeyCombo(keyCode: 12, control: true, command: true),
        KeyCombo(keyCode: 49, control: true, command: true),
    ]
}
