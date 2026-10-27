import AppKit
import LayoutEngine
import SwiftUI

struct CanvasView: View {
    @ObservedObject var model: CanvasModel
    @State private var lastPan: CGSize = .zero

    private var zoneCount: Int { (model.pages.map(\.zone).max() ?? 0) + 1 }

    var body: some View {
        ZStack(alignment: .topLeading) {
            RadialGradient(colors: [Color(white: 0.17), Color(white: 0.04)], center: .center,
                           startRadius: 40, endRadius: 1100)
                .ignoresSafeArea()
            Color.clear
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 2, coordinateSpace: .named("canvas"))
                    .onChanged { value in
                        model.pan(by: CGSize(width: value.translation.width - lastPan.width,
                                             height: value.translation.height - lastPan.height))
                        lastPan = value.translation
                    }
                    .onEnded { _ in lastPan = .zero })
            world
            VStack(spacing: 12) {
                if !model.hasCapturePermission { permissionBanner }
                if !model.unassigned.isEmpty { UnassignedTray(model: model) }
                Spacer()
                HStack { controls; Spacer() }
            }
            .padding(20)
        }
        .overlay(alignment: .topLeading) {
            if let drag = model.trayDrag {
                TrayThumb(model: model, id: drag.id, dragging: true)
                    .position(drag.location)
                    .allowsHitTesting(false)
            }
        }
        .coordinateSpace(name: "canvas")
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var world: some View {
        ZStack(alignment: .topLeading) {
            ForEach(model.pages) { page in
                PageCardView(page: page, scale: model.scale, zoneCount: zoneCount,
                             highlighted: model.dropTarget == .page(zone: page.zone, page: page.page))
            }
            ForEach(model.pages.flatMap(\.windows)) { window in
                WindowThumbView(model: model, window: window)
            }
        }
        .scaleEffect(model.scale, anchor: .topLeading)
        .offset(model.offset)
    }

    private var controls: some View {
        HStack(spacing: 14) {
            Button { model.zoom(by: 1 / 1.25) } label: { Image(systemName: "minus") }
            Text("\(Int((model.scale * 100).rounded())) %")
                .font(.system(.callout, design: .monospaced))
                .frame(minWidth: 52)
            Button { model.zoom(by: 1.25) } label: { Image(systemName: "plus") }
            Divider().frame(height: 14)
            Button { withAnimation(.easeInOut(duration: 0.25)) { model.fit() } } label: {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
            }
            .help("Ver todo")
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white.opacity(0.85))
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Capsule().fill(.black.opacity(0.55)))
        .overlay(Capsule().stroke(.white.opacity(0.12)))
    }

    private var permissionBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle")
            Text("Sin permiso de Grabación de pantalla: se muestran tarjetas en lugar del contenido.")
            Button("Abrir ajustes") {
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!)
            }
        }
        .font(.callout)
        .foregroundStyle(.white)
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10).fill(.black.opacity(0.6)))
    }
}

private struct PageCardView: View {
    let page: CanvasPage
    let scale: CGFloat
    let zoneCount: Int
    let highlighted: Bool

    private var title: String {
        if page.isNewSlot { return "＋ Nueva página" }
        let zone = zoneCount > 1 ? "Zona \(page.zone + 1) · " : ""
        return "\(zone)Página \(page.page + 1)"
    }

    var body: some View {
        RoundedRectangle(cornerRadius: 22)
            .fill(.white.opacity(highlighted ? 0.12 : 0.04))
            .overlay(RoundedRectangle(cornerRadius: 22)
                .strokeBorder(page.isNewSlot ? .white.opacity(0.3) : (page.isCurrent ? Color.accentColor : .white.opacity(0.12)),
                              style: StrokeStyle(lineWidth: (page.isCurrent ? 3 : 1.5) / max(scale, 0.2), dash: page.isNewSlot ? [14, 10] : []))
            )
            .overlay(alignment: .topLeading) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.75))
                    .fixedSize()
                    .scaleEffect(1 / scale, anchor: .topLeading)
                    .padding(14)
            }
            .frame(width: page.rect.width, height: page.rect.height)
            .offset(x: page.rect.minX, y: page.rect.minY)
    }
}

private struct WindowThumbView: View {
    @ObservedObject var model: CanvasModel
    let window: CanvasWindow

    private var isDragging: Bool { model.dragging == window.id }
    private var isDropTarget: Bool { model.dropTarget == .stack(onto: window.id) }
    private var chip: (name: String, icon: NSImage?)? { model.chips[window.id] }

    var body: some View {
        content
            .frame(width: window.rect.width, height: window.rect.height)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14)
                .strokeBorder(isDropTarget ? Color.accentColor : (model.focusedWindow == window.id ? .white.opacity(0.55) : .white.opacity(0.1)),
                              lineWidth: (isDropTarget ? 4 : 2) / max(model.scale, 0.2)))
            .overlay(alignment: .topLeading) { label }
            .shadow(color: .black.opacity(isDragging ? 0.6 : 0.35), radius: isDragging ? 40 : 18, y: 10)
            .offset(x: window.rect.minX + (isDragging ? model.dragDelta.width : 0),
                    y: window.rect.minY + (isDragging ? model.dragDelta.height : 0))
            .zIndex(isDragging ? 100 : 1)
            .onTapGesture { model.onReveal?(window.id) }
            .gesture(DragGesture(minimumDistance: 6, coordinateSpace: .named("canvas"))
                .onChanged { model.updateDrag(window.id, translation: $0.translation) }
                .onEnded { _ in model.endDrag(window.id) })
    }

    @ViewBuilder private var content: some View {
        if let image = model.thumbnails[window.id] {
            Image(nsImage: image).resizable().scaledToFill()
        } else {
            ZStack {
                Color(white: 0.13)
                if let icon = chip?.icon {
                    Image(nsImage: icon).resizable().scaledToFit().frame(width: 96, height: 96).opacity(0.8)
                }
            }
        }
    }

    private var label: some View {
        HStack(spacing: 6) {
            if let icon = chip?.icon { Image(nsImage: icon).resizable().frame(width: 16, height: 16) }
            Text(chip?.name ?? "Ventana").lineLimit(1)
            if window.columnSize > 1 {
                Text("· \(window.columnSize) ventanas").foregroundStyle(.white.opacity(0.6))
            }
        }
        .font(.system(size: 13, weight: .medium))
        .foregroundStyle(.white)
        .padding(.horizontal, 10)
        .frame(height: 24)
        .background(Capsule().fill(.black.opacity(0.7)))
        .fixedSize()
        .scaleEffect(1 / model.scale, anchor: .bottomLeading)
        .offset(y: -(24 + 6 / model.scale))
    }
}

/// Windows that are on no page, floating above the canvas so they can be dropped onto one.
private struct UnassignedTray: View {
    @ObservedObject var model: CanvasModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Sin asignar · \(model.unassigned.count)")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(0.7))
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(model.unassigned, id: \.rawValue) { id in
                        TrayThumb(model: model, id: id, dragging: false)
                            .opacity(model.trayDrag?.id == id ? 0.3 : 1)
                            .onTapGesture { model.onAssignToCurrent?(id) }
                            .gesture(DragGesture(minimumDistance: 6, coordinateSpace: .named("canvas"))
                                .onChanged { model.updateTrayDrag(id, location: $0.location) }
                                .onEnded { _ in model.endTrayDrag(id) })
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 16).fill(.black.opacity(0.55)))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(.white.opacity(0.14)))
        .frame(maxWidth: 900)
        .shadow(color: .black.opacity(0.4), radius: 20, y: 8)
    }
}

private struct TrayThumb: View {
    @ObservedObject var model: CanvasModel
    let id: WindowID
    let dragging: Bool

    private var chip: (name: String, icon: NSImage?)? { model.chips[id] }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            ZStack {
                if let image = model.thumbnails[id] {
                    Image(nsImage: image).resizable().scaledToFill()
                } else {
                    Color(white: 0.16)
                    if let icon = chip?.icon { Image(nsImage: icon).resizable().scaledToFit().frame(width: 44, height: 44).opacity(0.85) }
                }
            }
            .frame(width: 168, height: 100)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(.white.opacity(dragging ? 0.6 : 0.15), lineWidth: 1.5))
            HStack(spacing: 5) {
                if let icon = chip?.icon { Image(nsImage: icon).resizable().frame(width: 14, height: 14) }
                Text(chip?.name ?? "Ventana").lineLimit(1)
            }
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(.white.opacity(0.9))
        }
        .frame(width: 168)
        .shadow(color: .black.opacity(dragging ? 0.6 : 0), radius: 24, y: 8)
    }
}
