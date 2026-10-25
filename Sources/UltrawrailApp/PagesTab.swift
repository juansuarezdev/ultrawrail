import AppKit
import LayoutEngine
import SwiftUI
import UltrawrailCore

struct PagesTab: View {
    @ObservedObject var model: SettingsModel
    private static let maxPages = 9

    var body: some View {
        Group {
            if model.overview.allSatisfy({ $0.pages.allSatisfy { $0.windows.isEmpty } }) {
                Text("No hay ventanas gestionadas.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        ForEach(Array(model.overview.enumerated()), id: \.offset) { zone, overview in
                            zoneSection(zone, overview)
                        }
                    }
                    .padding()
                }
            }
        }
        .onAppear { model.refreshOverviewHandler?() }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
            model.refreshOverviewHandler?()
        }
    }

    private func zoneSection(_ zone: Int, _ overview: ZoneOverview) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if model.zoneCount > 1 {
                Text(overview.isFocused ? "Zona \(zone + 1) · con foco" : "Zona \(zone + 1)")
                    .font(.headline)
            }
            ScrollView(.horizontal) {
                HStack(alignment: .top, spacing: 10) {
                    ForEach(Array(overview.pages.enumerated()), id: \.offset) { page, value in
                        PageCard(model: model, zone: zone, page: page, overview: value)
                    }
                    if overview.pages.count < Self.maxPages {
                        NewPageTarget(model: model, zone: zone, page: overview.pages.count)
                    }
                }
                .padding(2)
            }
        }
    }
}

private enum WindowDrag {
    static let prefix = "ultrawrail-window:"
    static func payload(_ id: WindowID) -> String { prefix + String(id.rawValue) }
    static func id(from items: [String]) -> WindowID? {
        guard let item = items.first, item.hasPrefix(prefix), let raw = Int(item.dropFirst(prefix.count)) else { return nil }
        return WindowID(raw)
    }
}

private struct PageCard: View {
    @ObservedObject var model: SettingsModel
    let zone: Int
    let page: Int
    let overview: PageOverview
    @State private var targeted = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Página \(page + 1)").font(.subheadline.weight(.semibold))
            ForEach(overview.windows, id: \.rawValue) { id in
                WindowChipView(chip: model.windowChips[id]).draggable(WindowDrag.payload(id))
            }
            if overview.windows.isEmpty {
                Text("Vacía").font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(8)
        .frame(width: 150, height: 150, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 8).fill(targeted ? Color.accentColor.opacity(0.15) : Color.secondary.opacity(0.08)))
        .overlay(RoundedRectangle(cornerRadius: 8)
            .stroke(overview.isCurrent ? Color.accentColor : Color.secondary.opacity(0.3), lineWidth: overview.isCurrent ? 2 : 1))
        .dropDestination(for: String.self) { items, _ in
            guard let id = WindowDrag.id(from: items) else { return false }
            model.moveWindow(id, toZone: zone, page: page)
            return true
        } isTargeted: { targeted = $0 }
    }
}

private struct NewPageTarget: View {
    @ObservedObject var model: SettingsModel
    let zone: Int
    let page: Int
    @State private var targeted = false

    var body: some View {
        Text("＋ Nueva página")
            .foregroundStyle(.secondary)
            .frame(width: 150, height: 150)
            .background(RoundedRectangle(cornerRadius: 8).fill(targeted ? Color.accentColor.opacity(0.15) : Color.clear))
            .overlay(RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color.secondary.opacity(0.5), style: StrokeStyle(lineWidth: 1, dash: [5, 4])))
            .dropDestination(for: String.self) { items, _ in
                guard let id = WindowDrag.id(from: items) else { return false }
                model.moveWindow(id, toZone: zone, page: page)
                return true
            } isTargeted: { targeted = $0 }
    }
}

private struct WindowChipView: View {
    let chip: (name: String, icon: NSImage?)?

    var body: some View {
        HStack(spacing: 6) {
            if let icon = chip?.icon {
                Image(nsImage: icon).resizable().frame(width: 16, height: 16)
            } else {
                Image(systemName: "macwindow").frame(width: 16, height: 16)
            }
            Text(chip?.name ?? "Ventana").lineLimit(1).truncationMode(.tail)
            Spacer(minLength: 0)
        }
        .font(.caption)
        .contentShape(Rectangle())
    }
}
