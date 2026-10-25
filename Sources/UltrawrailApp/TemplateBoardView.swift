import AppKit
import LayoutEngine
import UltrawrailCore

let windowDragType = NSPasteboard.PasteboardType("dev.ultrawrail.window-id")

struct WindowChip {
    let id: WindowID
    let name: String
    let icon: NSImage?
}

final class TemplateBoardView: NSView {
    var board: TemplateBoard { didSet { needsDisplay = true } }
    private let chips: [WindowID: WindowChip]
    private let templates: [Template]
    private var cardScroll: CGFloat = 0 { didSet { needsDisplay = true } }
    private var dragCandidate: WindowID?
    private var dragOrigin: NSPoint = .zero

    init(board: TemplateBoard, chips: [WindowID: WindowChip], templates: [Template]) {
        self.board = board
        self.chips = chips
        self.templates = templates
        super.init(frame: NSRect(x: 0, y: 0, width: 560, height: 330))
        registerForDraggedTypes([windowDragType])
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override var isFlipped: Bool { true }

    // MARK: geometry

    private func cardRect(_ index: Int) -> NSRect {
        NSRect(x: 16 + CGFloat(index) * 162 - cardScroll, y: 16, width: 150, height: 70)
    }

    private let slotArea = NSRect(x: 16, y: 100, width: 330, height: 190)
    private let listArea = NSRect(x: 366, y: 100, width: 178, height: 190)
    private let listPitch: CGFloat = 40
    private static let scrollerWidth: CGFloat = 8
    private var listScroll: CGFloat = 0 { didSet { needsDisplay = true } }

    private var maxListScroll: CGFloat {
        max(0, CGFloat(board.windows.count) * listPitch - 6 - listArea.height)
    }

    /// One rect per slot, in slot order: columns split `slotArea` by their width share.
    private func slotRects() -> [NSRect] {
        let template = board.template
        let gap: CGFloat = 6
        let totalWidth = template.columns.reduce(0) { $0 + $1.width }
        let usable = slotArea.width - gap * CGFloat(template.columns.count - 1)
        var rects: [NSRect] = []
        var x = slotArea.minX
        for column in template.columns {
            let width = usable * CGFloat(column.width / totalWidth)
            let height = (slotArea.height - gap * CGFloat(column.slots - 1)) / CGFloat(column.slots)
            for row in 0..<column.slots {
                rects.append(NSRect(x: x, y: slotArea.minY + CGFloat(row) * (height + gap), width: width, height: height))
            }
            x += width + gap
        }
        return rects
    }

    private func chipRect(inList index: Int) -> NSRect {
        NSRect(x: listArea.minX, y: listArea.minY + CGFloat(index) * listPitch - listScroll,
               width: listArea.width - Self.scrollerWidth, height: 34)
    }

    private func listChips() -> [WindowID] { board.windows }

    // MARK: drawing

    override func draw(_ dirtyRect: NSRect) {
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(rect: NSRect(x: 0, y: 8, width: bounds.width, height: 86)).addClip()
        for (index, template) in templates.enumerated() {
            drawCard(template, in: cardRect(index), selected: template.id == board.template.id)
        }
        NSGraphicsContext.restoreGraphicsState()
        for (index, rect) in slotRects().enumerated() {
            let path = NSBezierPath(roundedRect: rect, xRadius: 8, yRadius: 8)
            NSColor.quaternaryLabelColor.setFill()
            path.fill()
            NSColor.separatorColor.setStroke()
            path.lineWidth = 1
            path.stroke()
            if let id = board.assignment[index], let chip = chips[id] {
                drawChip(chip, in: rect.insetBy(dx: 6, dy: 6), highlighted: true)
            } else {
                draw(text: "Hueco \(index + 1)", in: rect, color: .tertiaryLabelColor, centered: true)
            }
        }
        draw(text: "Huecos", in: NSRect(x: 16, y: 86, width: 330, height: 14), color: .secondaryLabelColor, centered: false)
        draw(text: "Ventanas (arrastra a un hueco)", in: NSRect(x: listArea.minX, y: 86, width: listArea.width, height: 14),
             color: .secondaryLabelColor, centered: false)
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(rect: listArea).addClip()
        defer { NSGraphicsContext.restoreGraphicsState(); drawScroller() }
        for (index, id) in listChips().enumerated() {
            guard let chip = chips[id] else { continue }
            let placed = !board.unassigned.contains(id)
            drawChip(chip, in: chipRect(inList: index), highlighted: false, dimmed: placed)
        }
        let extra = board.unassigned.count
        if extra > 0 {
            let text = extra == 1 ? "1 ventana irá a una columna extra" : "\(extra) ventanas irán a columnas extra"
            draw(text: text, in: NSRect(x: 16, y: 298, width: 330, height: 20), color: .secondaryLabelColor, centered: false)
        }
    }

    private func drawScroller() {
        guard maxListScroll > 0 else { return }
        let track = NSRect(x: listArea.maxX - Self.scrollerWidth + 2, y: listArea.minY, width: 4, height: listArea.height)
        let content = CGFloat(board.windows.count) * listPitch - 6
        let thumbHeight = max(24, track.height * listArea.height / content)
        let thumbY = track.minY + (track.height - thumbHeight) * (listScroll / maxListScroll)
        NSColor.quaternaryLabelColor.setFill()
        NSBezierPath(roundedRect: track, xRadius: 2, yRadius: 2).fill()
        NSColor.secondaryLabelColor.setFill()
        NSBezierPath(roundedRect: NSRect(x: track.minX, y: thumbY, width: track.width, height: thumbHeight), xRadius: 2, yRadius: 2).fill()
    }

    override func scrollWheel(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if point.y < 100 {
            let maxScroll = max(0, CGFloat(templates.count) * 162 + 16 - bounds.width)
            guard maxScroll > 0 else { return super.scrollWheel(with: event) }
            let raw = abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY) ? event.scrollingDeltaX : event.scrollingDeltaY
            let delta = raw * (event.hasPreciseScrollingDeltas ? 1 : 8)
            cardScroll = min(maxScroll, max(0, cardScroll - delta))
            return
        }
        guard listArea.contains(point), maxListScroll > 0 else { return }
        listScroll = min(maxListScroll, max(0, listScroll - event.scrollingDeltaY * (event.hasPreciseScrollingDeltas ? 1 : 8)))
    }

    private func drawCard(_ template: Template, in rect: NSRect, selected: Bool) {
        let path = NSBezierPath(roundedRect: rect, xRadius: 8, yRadius: 8)
        (selected ? NSColor.controlAccentColor.withAlphaComponent(0.15) : NSColor.quaternaryLabelColor).setFill()
        path.fill()
        (selected ? NSColor.controlAccentColor : NSColor.separatorColor).setStroke()
        path.lineWidth = selected ? 2 : 1
        path.stroke()
        let thumb = rect.insetBy(dx: 10, dy: 8)
        let preview = NSRect(x: thumb.minX, y: thumb.minY, width: thumb.width, height: 38)
        let gap: CGFloat = 3
        let total = template.columns.reduce(0) { $0 + $1.width }
        let usable = preview.width - gap * CGFloat(template.columns.count - 1)
        var x = preview.minX
        for column in template.columns {
            let width = usable * CGFloat(column.width / total)
            let height = (preview.height - gap * CGFloat(column.slots - 1)) / CGFloat(column.slots)
            for row in 0..<column.slots {
                let r = NSRect(x: x, y: preview.minY + CGFloat(row) * (height + gap), width: width, height: height)
                NSColor.secondaryLabelColor.setFill()
                NSBezierPath(roundedRect: r, xRadius: 2, yRadius: 2).fill()
            }
            x += width + gap
        }
        draw(text: template.name, in: NSRect(x: rect.minX, y: rect.maxY - 22, width: rect.width, height: 18),
             color: .labelColor, centered: true)
    }

    private func drawChip(_ chip: WindowChip, in rect: NSRect, highlighted: Bool, dimmed: Bool = false) {
        let path = NSBezierPath(roundedRect: rect, xRadius: 6, yRadius: 6)
        (highlighted ? NSColor.controlAccentColor.withAlphaComponent(0.25) : NSColor.controlBackgroundColor)
            .withAlphaComponent(dimmed ? 0.5 : 1).setFill()
        path.fill()
        NSColor.separatorColor.setStroke()
        path.lineWidth = 1
        path.stroke()
        let iconSize: CGFloat = 22
        let iconRect = NSRect(x: rect.minX + 6, y: rect.midY - iconSize / 2, width: iconSize, height: iconSize)
        chip.icon?.draw(in: iconRect, from: .zero, operation: .sourceOver, fraction: dimmed ? 0.5 : 1,
                        respectFlipped: true, hints: nil)
        draw(text: chip.name, in: NSRect(x: iconRect.maxX + 6, y: rect.minY, width: rect.width - iconSize - 18, height: rect.height),
             color: dimmed ? .tertiaryLabelColor : .labelColor, centered: false, verticallyCentered: true)
    }

    private func draw(text: String, in rect: NSRect, color: NSColor, centered: Bool, verticallyCentered: Bool = false) {
        let style = NSMutableParagraphStyle()
        style.alignment = centered ? .center : .left
        style.lineBreakMode = .byTruncatingTail
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12),
            .foregroundColor: color,
            .paragraphStyle: style,
        ]
        var target = rect
        if verticallyCentered || centered {
            let height = (text as NSString).size(withAttributes: attributes).height
            target.origin.y = rect.midY - height / 2
            target.size.height = height
        }
        (text as NSString).draw(in: target, withAttributes: attributes)
    }

    // MARK: mouse and dragging

    private func windowAt(_ point: NSPoint) -> WindowID? {
        for (index, rect) in slotRects().enumerated() where rect.contains(point) {
            if let id = board.assignment[index] { return id }
        }
        for (index, id) in listChips().enumerated().reversed() where listArea.contains(point) && chipRect(inList: index).contains(point) {
            return id
        }
        return nil
    }

    private func slotIndex(at point: NSPoint) -> Int? {
        slotRects().firstIndex { $0.contains(point) }
    }

    override func mouseDown(with event: NSEvent) {
        dragCandidate = nil
        let point = convert(event.locationInWindow, from: nil)
        if point.y < 100 {
            for (index, template) in templates.enumerated() where cardRect(index).contains(point) {
                board.select(template)
                return
            }
        }
        dragCandidate = windowAt(point)
        dragOrigin = point
    }

    override func mouseDragged(with event: NSEvent) {
        guard let id = dragCandidate, let chip = chips[id] else { return }
        let point = convert(event.locationInWindow, from: nil)
        guard hypot(point.x - dragOrigin.x, point.y - dragOrigin.y) > 4 else { return }
        dragCandidate = nil
        let item = NSPasteboardItem()
        item.setString(String(id.rawValue), forType: windowDragType)
        let dragging = NSDraggingItem(pasteboardWriter: item)
        let size = NSSize(width: 150, height: 34)
        let image = NSImage(size: size, flipped: true) { rect in
            let path = NSBezierPath(roundedRect: rect, xRadius: 6, yRadius: 6)
            NSColor.controlAccentColor.withAlphaComponent(0.4).setFill()
            path.fill()
            chip.icon?.draw(in: NSRect(x: 6, y: 6, width: 22, height: 22))
            (chip.name as NSString).draw(at: NSPoint(x: 34, y: 9), withAttributes: [
                .font: NSFont.systemFont(ofSize: 12),
                .foregroundColor: NSColor.labelColor,
            ])
            return true
        }
        dragging.setDraggingFrame(NSRect(x: point.x - 75, y: point.y - 17, width: size.width, height: size.height), contents: image)
        beginDraggingSession(with: [dragging], event: event, source: self)
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation { .move }
    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation { .move }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let raw = sender.draggingPasteboard.string(forType: windowDragType),
              let value = Int(raw) else { return false }
        let id = WindowID(value)
        let point = convert(sender.draggingLocation, from: nil)
        if let slot = slotIndex(at: point) {
            board.drop(id, onSlot: slot)
        } else if listArea.contains(point) {
            board.unassign(id)
        } else {
            return false
        }
        return true
    }
}

extension TemplateBoardView: NSDraggingSource {
    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        .move
    }
}
