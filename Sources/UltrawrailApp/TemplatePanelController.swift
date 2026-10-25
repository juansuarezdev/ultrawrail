import AppKit
import LayoutEngine
import UltrawrailCore

@MainActor
final class TemplatePanelController: NSObject {
    private let controller: Controller
    private let templates: () -> [Template]
    private var panel: NSPanel?
    private var boardView: TemplateBoardView?
    private var content: NSView?
    private let previousButton = NSButton(title: "◀", target: nil, action: nil)
    private let nextButton = NSButton(title: "▶", target: nil, action: nil)
    private let pageLabel = NSTextField(labelWithString: "")

    init(controller: Controller, templates: @escaping () -> [Template]) {
        self.controller = controller
        self.templates = templates
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
        let content = NSView(frame: NSRect(x: 0, y: 0, width: 560, height: 414))
        self.content = content
        installBoard(selecting: nil)

        previousButton.target = self
        previousButton.action = #selector(previousPageTapped)
        previousButton.frame = NSRect(x: 16, y: 380, width: 36, height: 24)
        nextButton.target = self
        nextButton.action = #selector(nextPageTapped)
        nextButton.frame = NSRect(x: 508, y: 380, width: 36, height: 24)
        pageLabel.alignment = .center
        pageLabel.frame = NSRect(x: 60, y: 382, width: 440, height: 20)
        content.addSubview(previousButton)
        content.addSubview(nextButton)
        content.addSubview(pageLabel)
        refreshPageHeader()

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
        content = nil
    }

    /// Builds the board for the current page, keeping `template` selected when given.
    private func installBoard(selecting template: Template?) {
        guard let content else { return }
        boardView?.removeFromSuperview()
        let ids = controller.managedWindows
        var chips: [WindowID: WindowChip] = [:]
        for id in ids {
            let description = controller.describe(id)
            let icon = description.flatMap { NSRunningApplication(processIdentifier: pid_t($0.pid))?.icon }
            chips[id] = WindowChip(id: id, name: description?.appName ?? "Ventana", icon: icon)
        }
        let available = templates()
        let board = TemplateBoard(template: template ?? available.first ?? Template.all[0], windows: ids)
        let boardView = TemplateBoardView(board: board, chips: chips, templates: available)
        boardView.frame.origin = NSPoint(x: 0, y: 50)
        content.addSubview(boardView)
        self.boardView = boardView
    }

    private func refreshPageHeader() {
        let overview = controller.overview()
        guard let zoneIndex = overview.firstIndex(where: \.isFocused) else { return }
        let pages = overview[zoneIndex].pages
        let pageIndex = pages.firstIndex(where: \.isCurrent) ?? 0
        let zonePart = overview.count > 1 ? "Zona \(zoneIndex + 1) · " : ""
        pageLabel.stringValue = "\(zonePart)Página \(pageIndex + 1) de \(pages.count)"
        previousButton.isEnabled = pageIndex > 0
        nextButton.isEnabled = pageIndex + 1 < pages.count || !pages[pageIndex].windows.isEmpty
    }

    private func switchPage(_ command: Command) {
        let selected = boardView?.board.template
        controller.handle(command)
        installBoard(selecting: selected)
        refreshPageHeader()
    }

    @objc private func previousPageTapped() { switchPage(.previousPage) }
    @objc private func nextPageTapped() { switchPage(.nextPage) }

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
