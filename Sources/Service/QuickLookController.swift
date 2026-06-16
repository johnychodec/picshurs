import Cocoa
import Quartz

final class QuickLookController: NSObject, QLPreviewPanelDataSource, QLPreviewPanelDelegate {
    var photos: [URL] = []

    func show(urls: [URL]) {
        photos = urls
        guard !photos.isEmpty else { return }
        QLPreviewPanel.shared().makeKeyAndOrderFront(nil)
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
