import LayoutEngine
import UltrawrailCore
import SwiftUI

struct SettingsView: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        TabView {
            GeneralTab(model: model)
                .tabItem { Label("General", systemImage: "gearshape") }
            LayoutTab(model: model)
                .tabItem { Label("Diseño", systemImage: "rectangle.split.3x1") }
            PagesTab(model: model)
                .tabItem { Label("Páginas", systemImage: "rectangle.stack") }
            TemplatesTab(model: model)
                .tabItem { Label("Plantillas", systemImage: "square.split.2x1") }
            AppsTab(model: model)
                .tabItem { Label("Apps", systemImage: "app.dashed") }
            ShortcutsTab(model: model)
                .tabItem { Label("Atajos", systemImage: "keyboard") }
        }
        .frame(width: 760, height: 560)
    }
}

private struct GeneralTab: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        Form {
            Picker("Velocidad de animación", selection: $model.speed) {
                Text("Rápida").tag(MotionSpeed.fast)
                Text("Normal").tag(MotionSpeed.normal)
                Text("Desactivada").tag(MotionSpeed.off)
            }
            Toggle("Respetar Reducir movimiento del sistema", isOn: $model.respectReduceMotion)
            Picker("Ventanas nuevas", selection: $model.placement) {
                Text("Manual (Ctrl+Alt+A para añadir)").tag(PlacementMode.manual)
                Text("Automático").tag(PlacementMode.automatic)
            }
            Picker("Teclado", selection: $model.keyboardStyle) {
                Text("Windows").tag(KeyboardStyle.windows)
                Text("Mac").tag(KeyboardStyle.mac)
            }
            .pickerStyle(.segmented)
            Toggle("Iniciar al arrancar", isOn: $model.launchAtLogin)
        }
        .formStyle(.grouped)
    }
}

private struct LayoutTab: View {
    @ObservedObject var model: SettingsModel
    @State private var gapDraft: Double
    @State private var outerGapDraft: Double
    @State private var maxWidthDraft: Double

    init(model: SettingsModel) {
        self.model = model
        _gapDraft = State(initialValue: model.gap)
        _outerGapDraft = State(initialValue: model.outerGap)
        _maxWidthDraft = State(initialValue: model.maxColumnWidth)
    }

    var body: some View {
        Form {
            VStack(alignment: .leading) {
                Text("Hueco entre ventanas: \(Int(gapDraft)) px")
                Slider(value: $gapDraft, in: 0...40, step: 1) { editing in
                    if !editing { model.gap = gapDraft }
                }
            }
            VStack(alignment: .leading) {
                Text("Margen exterior: \(Int(outerGapDraft)) px")
                Slider(value: $outerGapDraft, in: 0...60, step: 1) { editing in
                    if !editing { model.outerGap = outerGapDraft }
                }
            }
            Picker("Ancho de las columnas nuevas", selection: $model.newColumnWidth) {
                ForEach(WidthPreset.all, id: \.self) { width in
                    Text("\(Int((width * 100).rounded())) %").tag(width)
                }
            }
            Section {
                Picker("Seguimiento del foco", selection: $model.focusMode) {
                    Text("Mínimo").tag(FocusMode.minimal)
                    Text("Centrado").tag(FocusMode.centered)
                }
                Toggle("Centrar el grupo si cabe en pantalla", isOn: $model.centerStrip)
                VStack(alignment: .leading) {
                    Text(maxWidthDraft == 0 ? "Ancho máximo de columna: sin límite"
                                            : "Ancho máximo de columna: \(Int(maxWidthDraft)) px")
                    Slider(value: $maxWidthDraft, in: 0...5000, step: 100) { editing in
                        if !editing { model.maxColumnWidth = maxWidthDraft }
                    }
                }
                Picker("Zonas de la pantalla", selection: $model.zoneCount) {
                    ForEach(1...3, id: \.self) { Text("\($0)").tag($0) }
                }
                .pickerStyle(.segmented)
                Text("Cada zona tiene su propia tira, foco y páginas.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } footer: {
                Text("Pensado para monitores ultrawide.")
            }
            Button("Restaurar valores") { model.restoreLayoutDefaults() }
        }
        .formStyle(.grouped)
        .onChange(of: model.gap) { gapDraft = $0 }
        .onChange(of: model.outerGap) { outerGapDraft = $0 }
        .onChange(of: model.maxColumnWidth) { maxWidthDraft = $0 }
    }
}

private struct ShortcutsTab: View {
    @ObservedObject var model: SettingsModel
    @State private var recordingID: String?
    @State private var monitor: Any?
    @State private var message: (id: String, text: String)?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("Teclado", selection: $model.keyboardStyle) {
                Text("Windows").tag(KeyboardStyle.windows)
                Text("Mac").tag(KeyboardStyle.mac)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            List(model.shortcutMap.resolved, id: \.id) { shortcut in
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(shortcut.title)
                        Spacer()
                        Text(recordingID == shortcut.id ? "Pulsa el atajo…" : shortcut.combo.display(style: model.keyboardStyle))
                            .font(.system(.body, design: .monospaced))
                            .foregroundStyle(recordingID == shortcut.id ? Color.accentColor : .primary)
                        Button(recordingID == shortcut.id ? "Cancelar" : "Cambiar") {
                            recordingID == shortcut.id ? stopRecording() : startRecording(shortcut.id)
                        }
                        Button("Restablecer") {
                            message = nil
                            model.shortcutMap.reset(shortcut.id)
                        }
                        .disabled(!model.shortcutMap.isCustomized(shortcut.id))
                    }
                    if let message, message.id == shortcut.id {
                        Text(message.text).font(.caption).foregroundStyle(.red)
                    }
                }
            }
            HStack {
                Text("Hacen falta al menos dos de Ctrl, Alt y Win. Esc cancela la grabación.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Restablecer todos") {
                    message = nil
                    model.shortcutMap.resetAll()
                }
                .disabled(model.shortcutMap.overrides.isEmpty)
            }
        }
        .padding()
        .onDisappear { stopRecording() }
    }

    private func startRecording(_ id: String) {
        stopRecording()
        message = nil
        recordingID = id
        model.recordingChanged?(true)
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let flags = event.modifierFlags
            if event.keyCode == 53, flags.intersection([.control, .option, .command, .shift]).isEmpty {
                stopRecording()
                return nil
            }
            let combo = KeyCombo(keyCode: Int(event.keyCode), control: flags.contains(.control),
                                 option: flags.contains(.option), command: flags.contains(.command),
                                 shift: flags.contains(.shift))
            if let issue = model.shortcutMap.issue(for: combo, assigningTo: id) {
                message = (id, Self.text(for: issue))
            } else {
                model.shortcutMap.assign(combo, to: id)
                message = nil
                stopRecording()
            }
            return nil
        }
    }

    private func stopRecording() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        if recordingID != nil {
            recordingID = nil
            model.recordingChanged?(false)
        }
    }

    private static func text(for issue: ShortcutIssue) -> String {
        switch issue {
        case .needsTwoModifiers: return "Usa al menos dos modificadores entre Ctrl, Alt y Win."
        case .reservedBySystem: return "Ese atajo lo usa el sistema."
        case .conflict(let title): return "Ya lo usa «\(title)»."
        }
    }
}
