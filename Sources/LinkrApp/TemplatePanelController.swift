import AppKit
import LayoutEngine
import LinkrCore

@MainActor
final class TemplatePanelController: NSObject {
    private let controller: Controller

    init(controller: Controller) {
        self.controller = controller
        super.init()
    }

    func toggle() {}
}
