import SwiftUI
import AppKit

/// Observable model threaded through NSOpenPanel accessory so the caller can
/// read the final template after `runModal()` returns.
@Observable
final class ExportTemplateModel {
    var template: String
    let defaultTemplate: String
    let sampleItem: ExportNamer.Item
    let batchCount: Int

    init(template: String, defaultTemplate: String, sampleItem: ExportNamer.Item, batchCount: Int) {
        self.template = template
        self.defaultTemplate = defaultTemplate
        self.sampleItem = sampleItem
        self.batchCount = batchCount
    }

    var liveExample: String {
        let effective = ExportNamer.effectiveTemplate(template, fallback: defaultTemplate)
        let pw = ExportNamer.padWidth(for: max(1, batchCount))
        let stem = ExportNamer.renderStem(template: effective, item: sampleItem, index: 1, padWidth: pw)
        let ext = sampleItem.ext.isEmpty ? "" : ".\(sampleItem.ext)"
        let suffix = ExportNamer.effectiveTemplate(template, fallback: "") == "" ? " (default)" : ""
        return stem + ext + suffix
    }
}

struct ExportTemplateAccessoryView: View {
    @Bindable var model: ExportTemplateModel

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text("Filename template:")
                    .font(.callout)
                    .fixedSize()
                TextField(model.defaultTemplate, text: $model.template)
                    .font(.callout.monospaced())
                    .textFieldStyle(.roundedBorder)
            }

            HStack {
                Text("Placeholders: {name} original · {n} sequence · {date} photo date · {today} export date")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(model.liveExample)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(width: 460)
    }
}

/// Creates an NSHostingView wrapping `ExportTemplateAccessoryView`, sized to
/// fit content. Pass this to `panel.accessoryView` before calling `runModal`.
func makeExportTemplateAccessory(model: ExportTemplateModel) -> NSView {
    let swiftUIView = ExportTemplateAccessoryView(model: model)
    let hosting = NSHostingView(rootView: swiftUIView)
    hosting.frame = NSRect(x: 0, y: 0, width: 460, height: 72)
    return hosting
}
