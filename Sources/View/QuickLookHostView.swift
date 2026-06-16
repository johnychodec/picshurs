import SwiftUI
import Quartz

struct QuickLookHostView: NSViewRepresentable {
    let controller: QuickLookController

    func makeNSView(context: Context) -> QuickLookResponderView {
        QuickLookResponderView(controller: controller)
    }

    func updateNSView(_ nsView: QuickLookResponderView, context: Context) {}
}

final class QuickLookResponderView: NSView {
    private weak var controller: QuickLookController?

    init(controller: QuickLookController) {
        self.controller = controller
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func acceptsPreviewPanelControl(_ panel: QLPreviewPanel!) -> Bool {
        true
    }

    override func beginPreviewPanelControl(_ panel: QLPreviewPanel!) {
        panel.dataSource = controller
        panel.delegate = controller
    }

    override func endPreviewPanelControl(_ panel: QLPreviewPanel!) {
        panel.dataSource = nil
        panel.delegate = nil
    }
}
