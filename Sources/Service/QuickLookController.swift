import Cocoa
import Quartz

final class QuickLookController: NSObject, QLPreviewPanelDataSource, QLPreviewPanelDelegate {
    var photos: [URL] = []
    private var selectedIndex = 0

    func show(urls: [URL], selectedURL: URL? = nil) {
        photos = urls
        guard !photos.isEmpty else { return }
        if let selectedURL,
           let index = photos.firstIndex(of: selectedURL) {
            selectedIndex = index
        } else {
            selectedIndex = 0
        }
        guard let panel = QLPreviewPanel.shared() else { return }
        panel.makeKeyAndOrderFront(nil)
        panel.currentPreviewItemIndex = selectedIndex
    }

    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
        photos.count
    }

    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> QLPreviewItem! {
        guard index >= 0, index < photos.count else { return nil }
        return photos[index] as NSURL
    }

    func previewPanel(_ panel: QLPreviewPanel!, sourceFrameOnScreenFor item: QLPreviewItem!) -> NSRect {
        NSRect(x: 200, y: 200, width: 400, height: 400)
    }
}
