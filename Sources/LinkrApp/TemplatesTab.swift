import AppKit
import LayoutEngine
import SwiftUI

enum Aspect: String, CaseIterable {
    case wide16x9 = "16:9", ultra21x9 = "21:9", super32x9 = "32:9"

    var ratio: Double {
        switch self {
        case .wide16x9: return 16.0 / 9.0
        case .ultra21x9: return 21.0 / 9.0
        case .super32x9: return 32.0 / 9.0
        }
    }

    static func nearest(to ratio: Double) -> Aspect {
        allCases.min { abs($0.ratio - ratio) < abs($1.ratio - ratio) } ?? .wide16x9
    }
}

/// Mini preview of a template: proportional rounded rects, one per slot.
struct TemplateThumbnail: View {
    let columns: [TemplateColumn]

    var body: some View {
        GeometryReader { proxy in
            HStack(spacing: 1) {
                ForEach(Array(columns.enumerated()), id: \.offset) { _, column in
                    VStack(spacing: 1) {
                        ForEach(0..<column.slots, id: \.self) { _ in
                            RoundedRectangle(cornerRadius: 1.5).fill(Color.accentColor.opacity(0.7))
                        }
                    }
                    .frame(width: max(1, proxy.size.width * column.width - 1))
                }
            }
        }
        .frame(width: 40, height: 22)
    }
}

struct TemplatesTab: View {
    @ObservedObject var model: SettingsModel
    @State private var selectedId: String = Template.builtIn[0].id
    @State private var aspect: Aspect = Aspect.nearest(to: Self.screenRatio())
    @State private var activeDivider: Int?
    @State private var snapped: Double?

    private static let canvasWidth: CGFloat = 460

    private static func screenRatio() -> Double {
        guard let frame = NSScreen.main?.frame, frame.height > 0 else { return 16.0 / 9.0 }
        return Double(frame.width / frame.height)
    }

    private var selected: Template {
        model.allTemplates.first { $0.id == selectedId } ?? Template.builtIn[0]
    }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            sidebar.frame(width: 220)
            Divider()
            editor(for: selected)
                .padding(16)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    // MARK: Sidebar

    private var sidebar: some View {
        VStack(spacing: 0) {
            List(selection: $selectedId) {
                Section("De serie") {
                    ForEach(Template.builtIn, id: \.id) { template in
                        row(template, badge: Template.ultrawide.contains { $0.id == template.id })
                    }
                }
                Section("Mis plantillas") {
                    ForEach(model.customTemplates, id: \.id) { row($0, badge: false) }
                }
            }
            Button {
                selectedId = model.newTemplate().id
            } label: {
                Label("Nueva plantilla", systemImage: "plus")
            }
            .padding(8)
        }
    }

    private func row(_ template: Template, badge: Bool) -> some View {
        HStack(spacing: 8) {
            TemplateThumbnail(columns: template.columns)
            Text(template.name).lineLimit(1)
            if badge {
                Text("UW")
                    .font(.system(size: 9, weight: .semibold))
                    .padding(.horizontal, 4)
                    .background(Capsule().fill(Color.secondary.opacity(0.25)))
            }
        }
        .tag(template.id)
    }

    // MARK: Editor

    private func isReadOnly(_ template: Template) -> Bool {
        Template.builtIn.contains { $0.id == template.id }
    }

    private func mutate(_ template: Template, _ change: (inout TemplateDraft) -> Void) {
        guard !isReadOnly(template) else { return }
        var draft = TemplateDraft(columns: template.columns)
        change(&draft)
        model.update(Template(id: template.id, name: template.name, columns: draft.columns))
    }

    private func editor(for t: Template) -> some View {
        let readOnly = isReadOnly(t)
        return VStack(alignment: .leading, spacing: 12) {
            header(t, readOnly: readOnly)
            Picker("Monitor", selection: $aspect) {
                ForEach(Aspect.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .frame(width: Self.canvasWidth)
            HStack(alignment: .top, spacing: 8) {
                canvas(t, readOnly: readOnly)
                if activeDivider != nil, let snapped {
                    Text("Imán: \(Int((snapped * 100).rounded())) %")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            ruler(t)
            HStack {
                Button {
                    mutate(t) { $0.addColumn() }
                } label: {
                    Label("Columna", systemImage: "plus")
                }
                .disabled(readOnly || t.columns.count >= TemplateDraft.maxColumns)
                Text("\(t.columns.count) columnas · \(t.slotCount) huecos · suma 100 % de la pantalla")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
    }

    private func header(_ t: Template, readOnly: Bool) -> some View {
        HStack {
            TextField("Nombre", text: Binding(
                get: { t.name },
                set: { model.update(Template(id: t.id, name: $0, columns: t.columns)) }
            ))
            .disabled(readOnly)
            .frame(maxWidth: 200)
            if readOnly {
                Text("De serie: duplica para editar").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button("Duplicar") { selectedId = model.duplicate(t).id }
            if !readOnly {
                Button("Borrar") {
                    model.deleteTemplate(id: t.id)
                    selectedId = Template.builtIn[0].id
                }
            }
        }
    }

    private func canvas(_ t: Template, readOnly: Bool) -> some View {
        let width = Self.canvasWidth
        let height = width / CGFloat(aspect.ratio)
        let starts = t.columns.indices.map { i in t.columns[..<i].reduce(0) { $0 + $1.width } }
        return ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 6).fill(Color(nsColor: .underPageBackgroundColor))
            RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.6), lineWidth: 2)
            ForEach(Array(t.columns.enumerated()), id: \.offset) { index, column in
                columnView(t, index: index, column: column, readOnly: readOnly, height: height)
                    .frame(width: max(0, width * column.width - 8), height: height - 8)
                    .offset(x: width * starts[index] + 4, y: 4)
            }
            ForEach(0..<max(0, t.columns.count - 1), id: \.self) { i in
                divider(t, index: i, boundary: starts[i + 1], width: width, readOnly: readOnly)
            }
        }
        .coordinateSpace(name: "screen")
        .frame(width: width, height: height)
    }

    private func columnView(_ t: Template, index: Int, column: TemplateColumn, readOnly: Bool, height: CGFloat) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6).fill(Color.accentColor.opacity(0.12))
            RoundedRectangle(cornerRadius: 6).stroke(Color.accentColor.opacity(0.6), lineWidth: 1)
            VStack(spacing: 4) {
                Text("\(Int((column.width * 100).rounded())) %").font(.caption.bold())
                ForEach(0..<column.slots, id: \.self) { n in
                    ZStack {
                        RoundedRectangle(cornerRadius: 4)
                            .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                            .foregroundStyle(.secondary)
                        Text("Hueco \(n + 1)").font(.caption2).foregroundStyle(.secondary)
                    }
                }
                if !readOnly { slotStepper(t, index: index, slots: column.slots) }
            }
            .padding(6)
            if !readOnly && t.columns.count > 1 {
                VStack {
                    HStack {
                        Spacer()
                        Button {
                            mutate(t) { $0.removeColumn(at: index) }
                        } label: {
                            Image(systemName: "minus.circle.fill")
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Quitar columna \(index + 1)")
                    }
                    Spacer()
                }
                .padding(4)
            }
        }
    }

    private func slotStepper(_ t: Template, index: Int, slots: Int) -> some View {
        HStack(spacing: 6) {
            Button {
                mutate(t) { $0.setSlots(slots - 1, at: index) }
            } label: { Image(systemName: "minus") }
                .accessibilityLabel("Menos huecos en la columna \(index + 1)")
            Text(slots == 1 ? "1 hueco" : "\(slots) huecos").font(.caption2)
            Button {
                mutate(t) { $0.setSlots(slots + 1, at: index) }
            } label: { Image(systemName: "plus") }
                .accessibilityLabel("Más huecos en la columna \(index + 1)")
        }
        .buttonStyle(.borderless)
    }

    private func divider(_ t: Template, index: Int, boundary: Double, width: CGFloat, readOnly: Bool) -> some View {
        Capsule()
            .fill(activeDivider == index ? Color.accentColor : Color.secondary)
            .frame(width: 4, height: 46)
            .frame(width: 18, height: 46)
            .contentShape(Rectangle())
            .position(x: width * boundary, y: width / CGFloat(aspect.ratio) / 2)
            .onHover { inside in
                guard !readOnly else { return }
                if inside { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
            }
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .named("screen"))
                    .onChanged { value in
                        guard !readOnly else { return }
                        activeDivider = index
                        var draft = TemplateDraft(columns: t.columns)
                        draft.moveDivider(index, to: Double(value.location.x / width))
                        let moved = [draft.columns[index].width, draft.columns[index + 1].width]
                        snapped = moved.first { w in TemplateDraft.snaps.contains(w) }
                        model.update(Template(id: t.id, name: t.name, columns: draft.columns))
                    }
                    .onEnded { _ in
                        activeDivider = nil
                        snapped = nil
                    }
            )
    }

    private func ruler(_ t: Template) -> some View {
        let width = Self.canvasWidth
        var edge = 0.0
        let boundaries = t.columns.dropLast().map { column -> Double in edge += column.width; return edge }
        return ZStack(alignment: .topLeading) {
            ForEach(TemplateDraft.snaps, id: \.self) { snap in
                Text("\(Int((snap * 100).rounded()))")
                    .font(.system(size: 9)).foregroundStyle(.secondary)
                    .position(x: width * snap, y: 14)
            }
            ForEach(Array(boundaries.enumerated()), id: \.offset) { _, b in
                Circle().fill(Color.accentColor).frame(width: 6, height: 6)
                    .position(x: width * b, y: 3)
            }
        }
        .frame(width: width, height: 24)
        .accessibilityHidden(true)
    }
}
