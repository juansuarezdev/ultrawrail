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

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("Teclado", selection: $model.keyboardStyle) {
                Text("Windows").tag(KeyboardStyle.windows)
                Text("Mac").tag(KeyboardStyle.mac)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            List(ShortcutLegend.entries, id: \.title) { entry in
                Text(ShortcutLegend.line(for: entry, style: model.keyboardStyle))
                    .font(.system(.body, design: .monospaced))
            }
        }
        .padding()
    }
}
