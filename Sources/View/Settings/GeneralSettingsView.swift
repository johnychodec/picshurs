import SwiftUI

struct GeneralSettingsView: View {
    @Binding var confirmBeforeTrash: Bool
    @Binding var showFilenameLabels: Bool
    @Binding var preserveAspectRatio: Bool
    @Binding var defaultThumbnailSize: Double
    @Binding var trayThumbnailSize: Double
    @Binding var trayVisibleRows: Int
    @Binding var enableMap: Bool
    @Binding var enableFaces: Bool
    @Binding var webExportMaxDimension: Int
    @Binding var webExportQuality: Double
    var onResetToDefaults: () -> Void

    private var trayVisibleRowsDouble: Binding<Double> {
        Binding(
            get: { Double(trayVisibleRows) },
            set: { trayVisibleRows = Int($0) }
        )
    }

    private var webExportMaxDimensionDouble: Binding<Double> {
        Binding(
            get: { Double(webExportMaxDimension) },
            set: { webExportMaxDimension = Int($0) }
        )
    }

    var body: some View {
        Form {
            Section("Browsing") {
                Toggle("Confirm before moving to Trash", isOn: $confirmBeforeTrash)
                Toggle("Preserve thumbnail aspect ratio", isOn: $preserveAspectRatio)
                Toggle("Show filename labels on hover", isOn: $showFilenameLabels)
            }

            Section {
                Toggle("Show Map", isOn: $enableMap)
                Toggle("Face detection (experimental)", isOn: $enableFaces)
            } header: {
                Text("Features")
            } footer: {
                Text("Face detection is experimental — it runs on-device but may miss or mis-group faces. Off by default.")
            }

            Section("Thumbnails") {
                LabeledContent {
                    Slider(value: $defaultThumbnailSize, in: 80...400, step: 20)
                        .frame(width: 220)
                } label: {
                    Text("Default size")
                    Text("\(Int(defaultThumbnailSize)) pt")
                }
            }

            Section("Tray") {
                LabeledContent {
                    Slider(value: $trayThumbnailSize, in: 20...100, step: 4)
                        .frame(width: 220)
                } label: {
                    Text("Thumbnail size")
                    Text("\(Int(trayThumbnailSize)) pt")
                }

                LabeledContent {
                    Slider(value: trayVisibleRowsDouble, in: 1...5, step: 1)
                        .frame(width: 220)
                } label: {
                    Text("Visible rows")
                    Text("\(trayVisibleRows)")
                }
            }

            Section("Web Export") {
                LabeledContent {
                    Slider(value: webExportMaxDimensionDouble, in: 512...4096, step: 256)
                        .frame(width: 220)
                } label: {
                    Text("Max dimension")
                    Text("\(webExportMaxDimension) px")
                }

                LabeledContent {
                    Slider(value: $webExportQuality, in: 0.50...1.00, step: 0.02)
                        .frame(width: 220)
                } label: {
                    Text("JPEG quality")
                    Text("\(Int(webExportQuality * 100))%")
                }
            }

            Section {
                HStack {
                    Spacer()
                    Button("Reset to Defaults", action: onResetToDefaults)
                }
            }
        }
        .formStyle(.grouped)
    }
}
