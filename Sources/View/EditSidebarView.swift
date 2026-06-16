import SwiftUI

struct EditSidebarView: View {
    @Environment(AppViewModel.self) private var viewModel
    @State private var selectedTab: EditTab = .basicFixes

    var body: some View {
        VStack(spacing: 0) {
            if viewModel.selectedPhoto != nil {
                DisclosureGroup {
                    PhotoMetadataView()
                        .padding(.top, 4)
                } label: {
                    HStack {
                        Image(systemName: "chart.bar.fill")
                            .foregroundStyle(.secondary)
                        Text("Photo Info")
                            .font(.headline)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.top, 12)
                .padding(.bottom, 8)

                Divider()
            }

            EditTabPicker(selectedTab: $selectedTab)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)

            Divider()

            ScrollView {
                // Tab content first — the filter grid keeps a fixed position;
                // the variable-height layer stack lives below it.
                switch selectedTab {
                case .basicFixes:
                    BasicFixesTab()
                case .tuning:
                    TuningTab()
                case .effectsEssential:
                    EffectsGridTab(filters: LayerType.essentialFilters)
                case .effectsCreative:
                    EffectsGridTab(filters: LayerType.creativeFilters)
                case .effectsExperimental:
                    EffectsGridTab(filters: LayerType.experimentalFilters)
                }

                layerListView
            }
        }
        .safeAreaInset(edge: .bottom) {
            EditActionsBar()
        }
    }

    // MARK: - Layer List

    private var layerListView: some View {
        let layers = viewModel.editPayload.layers
        let rowHeight: CGFloat = 30

        return Group {
            if !layers.isEmpty {
                Divider()
                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        Text("Adjustments").font(.caption).fontWeight(.semibold)
                        Spacer()
                        if layers.count > 1 {
                            Text("drag to reorder")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                        Text("\(layers.count)")
                            .font(.caption)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)

                    // List (not ForEach-in-VStack) for native .onMove drag
                    // reordering — layers composite in this order, so order
                    // changes are real edits and get undo + re-render.
                    List {
                        ForEach(layers) { layer in
                            layerRow(layer)
                                .listRowInsets(EdgeInsets(top: 1, leading: 8, bottom: 1, trailing: 8))
                                .listRowSeparator(.hidden)
                        }
                        .onMove { source, destination in
                            viewModel.pushUndoSnapshot()
                            viewModel.editPayload.moveLayers(from: source, to: destination)
                            viewModel.schedulePreviewRender()
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                    .scrollDisabled(true)
                    .environment(\.defaultMinListRowHeight, rowHeight)
                    .frame(height: CGFloat(layers.count) * rowHeight)
                }
            }
        }
    }

    private func layerRow(_ layer: AdjustmentLayer) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 9))
                .foregroundStyle(.tertiary)

            Image(systemName: layer.type.iconName)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .frame(width: 18)

            Text(layer.type.displayName)
                .font(.caption)
                .lineLimit(1)

            Spacer()

            let value = layer.param(layer.type.defaultParamKey)
            if layer.type.hasPrimaryParam && layer.type.isFilter {
                Text(String(format: "%.0f%%", value * 100))
                    .font(.caption2)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }

            Button(action: {
                viewModel.pushUndoSnapshot()
                viewModel.editPayload.removeLayer(id: layer.id)
                viewModel.schedulePreviewRender()
            }) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 4))
    }
}
