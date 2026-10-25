import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct AppsTab: View {
    @ObservedObject var model: SettingsModel

    private var runningCandidates: [NSRunningApplication] {
        let own = Bundle.main.bundleIdentifier
        return NSWorkspace.shared.runningApplications.filter { app in
            guard app.activationPolicy == .regular, let id = app.bundleIdentifier else { return false }
            return id != own && !model.excludedApps.contains(id)
        }
        .sorted { ($0.localizedName ?? "").localizedCaseInsensitiveCompare($1.localizedName ?? "") == .orderedAscending }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if model.excludedApps.isEmpty {
                Spacer()
                Text("Ninguna app excluida. Las ventanas de las apps de esta lista no se tocan.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                Spacer()
            } else {
                List(model.excludedApps, id: \.self) { bundleID in
                    AppRow(bundleID: bundleID) { model.removeExcludedApp(bundleID) }
                }
            }
            HStack {
                Button("Añadir app…") { chooseApp() }
                Menu("Añadir app en ejecución") {
                    ForEach(runningCandidates, id: \.processIdentifier) { app in
                        Button(app.localizedName ?? app.bundleIdentifier ?? "") {
                            if let id = app.bundleIdentifier { model.addExcludedApp(id) }
                        }
                    }
                }
                .fixedSize()
            }
        }
        .padding()
    }

    private func chooseApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        guard panel.runModal() == .OK, let url = panel.url,
              let id = Bundle(url: url)?.bundleIdentifier else { return }
        model.addExcludedApp(id)
    }
}

private struct AppRow: View {
    let bundleID: String
    let onRemove: () -> Void

    private var url: URL? { NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) }

    var body: some View {
        HStack {
            if let url {
                Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable().frame(width: 24, height: 24)
                VStack(alignment: .leading) {
                    Text(url.deletingPathExtension().lastPathComponent)
                    Text(bundleID).font(.caption).foregroundStyle(.secondary)
                }
            } else {
                Text(bundleID)
            }
            Spacer()
            Button { onRemove() } label: { Image(systemName: "minus.circle") }
                .buttonStyle(.borderless)
                .help("Quitar de la lista")
        }
    }
}
