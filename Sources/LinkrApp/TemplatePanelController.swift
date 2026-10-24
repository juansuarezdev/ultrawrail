import AppKit
import LayoutEngine
import LinkrCore

@MainActor
final class TemplatePanelController: NSObject {
    private let controller: Controller
    private var panel: NSPanel?
    private var boardView: TemplateBoardView?

    init(controller: Controller) {
        self.controller = controller
        super.init()
    }

    func toggle() {
        if let panel, panel.isVisible {
            close()
            controller.refocus()
        } else {
            open()
        }
    }

    private func open() {
        let ids = controller.managedWindows
        guard !ids.isEmpty else { return }
        var chips: [WindowID: WindowChip] = [:]
        for id in ids {
            let description = controller.describe(id)
            let icon = description.flatMap { NSRunningApplication(processIdentifier: pid_t($0.pid))?.icon }
            chips[id] = WindowChip(id: id, name: description?.appName ?? "Ventana", icon: icon)
        }
        let board = TemplateBoard(template: Template.all[0], windows: ids)
        let boardView = TemplateBoardView(board: board, chips: chips)
        self.boardView = boardView

        let content = NSView(frame: NSRect(x: 0, y: 0, width: 560, height: 380))
        boardView.frame.origin = NSPoint(x: 0, y: 50)
        content.addSubview(boardView)

        let apply = NSButton(title: "Aplicar", target: self, action: #selector(applyTapped))
        apply.keyEquivalent = "\r"
        apply.frame = NSRect(x: 456, y: 12, width: 88, height: 28)
        let cancel = NSButton(title: "Cancelar", target: self, action: #selector(cancelTapped))
        cancel.keyEquivalent = "\u{1b}"
        cancel.frame = NSRect(x: 360, y: 12, width: 88, height: 28)
        content.addSubview(apply)
        content.addSubview(cancel)

        let panel = NSPanel(contentRect: content.frame,
                            styleMask: [.titled, .closable, .utilityWindow],
                            backing: .buffered, defer: false)
        panel.title = "Plantillas"
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.contentView = content
        panel.defaultButtonCell = apply.cell as? NSButtonCell
        panel.center()
        self.panel = panel
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }

    private func close() {
        panel?.orderOut(nil)
        panel = nil
        boardView = nil
    }

    @objc private func applyTapped() {
        guard let board = boardView?.board else { return }
        close()
        controller.applyTemplate(board.template, assignment: board.assignment)
    }

    @objc private func cancelTapped() {
        close()
        controller.refocus()
    }
}
