import LayoutEngine
import LinkrCore
import SwiftUI

struct SettingsView: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        TabView {
            GeneralTab(model: model)
                .tabItem { Label("General", systemImage: "gearshape") }
            LayoutTab(model: model)
                .tabItem { Label("Diseño", systemImage: "rectangle.split.3x1") }
            ShortcutsTab(model: model)
                .tabItem { Label("Atajos", systemImage: "keyboard") }
        }
        .frame(width: 520, height: 420)
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

    var body: some View {
        Form {
            VStack(alignment: .leading) {
                Text("Hueco entre ventanas: \(Int(model.gap)) px")
                Slider(value: $model.gap, in: 0...40, step: 1)
            }
            VStack(alignment: .leading) {
                Text("Margen exterior: \(Int(model.outerGap)) px")
                Slider(value: $model.outerGap, in: 0...60, step: 1)
            }
            Picker("Ancho de las columnas nuevas", selection: $model.newColumnWidth) {
                ForEach(WidthPreset.all, id: \.self) { width in
                    Text("\(Int((width * 100).rounded())) %").tag(width)
                }
            }
            Button("Restaurar valores") { model.restoreLayoutDefaults() }
        }
        .formStyle(.grouped)
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
