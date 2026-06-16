import SwiftUI

struct EffectsGridTab: View {
    @Environment(AppViewModel.self) private var viewModel
    let filters: [LayerType]

    @State private var selectedFilter: LayerType?

    private let columns = [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)]

    /// Active filters (from this tab) that have adjustable parameters.
    private var adjustableActiveFilters: [LayerType] {
        filters.filter { type in
            type.hasParameters && viewModel.editPayload.layers.contains { $0.type == type }
        }
    }

    var body: some View {
        VStack(spacing: 10) {
            // Fixed-height slider area ABOVE the grid — the buttons below
            // never move, whether or not a filter is active/adjustable.
            FilterSliderPanel(
                layerType: resolvedSelection,
                adjustableFilters: adjustableActiveFilters,
                selectedFilter: $selectedFilter
            )

            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(filters) { filterType in
                    FilterButton(layerType: filterType, selectedFilter: $selectedFilter)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .onChange(of: viewModel.selectedPhoto?.id) { _, _ in
            selectedFilter = nil
        }
    }

    /// Falls back to the first adjustable active filter if the selected one
    /// was removed (or none is selected yet but filters are active).
    private var resolvedSelection: LayerType? {
        if let selected = selectedFilter,
           adjustableActiveFilters.contains(selected) {
            return selected
        }
        return adjustableActiveFilters.first
    }
}

/// Fixed-height slider panel — reserves space for a header plus two sliders
/// even when empty, so the filter grid below it never shifts.
private struct FilterSliderPanel: View {
    @Environment(AppViewModel.self) private var viewModel
    let layerType: LayerType?
    let adjustableFilters: [LayerType]
    @Binding var selectedFilter: LayerType?

    private static let panelHeight: CGFloat = 124

    private var activeLayer: AdjustmentLayer? {
        guard let layerType else { return nil }
        return viewModel.editPayload.layers.first { $0.type == layerType }
    }

    var body: some View {
        Group {
            if let layerType {
                VStack(spacing: 8) {
                    HStack {
                        if adjustableFilters.count > 1 {
                            Menu {
                                ForEach(adjustableFilters) { filter in
                                    Button(filter.displayName) { selectedFilter = filter }
                                }
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: layerType.iconName)
                                        .font(.caption)
                                    Text(layerType.displayName)
                                        .font(.caption.weight(.medium))
                                    Image(systemName: "chevron.up.chevron.down")
                                        .font(.system(size: 8))
                                }
                                .foregroundStyle(Color.accentColor)
                            }
                            .menuStyle(.borderlessButton)
                            .fixedSize()
                        } else {
                            HStack(spacing: 4) {
                                Image(systemName: layerType.iconName)
                                    .font(.caption)
                                Text(layerType.displayName)
                                    .font(.caption.weight(.medium))
                            }
                            .foregroundStyle(Color.accentColor)
                        }
                        Spacer()
                    }

                    if layerType.hasPrimaryParam {
                        filterSlider(
                            label: layerType.primaryParamLabel,
                            value: paramBinding("value", fallback: 0.7)
                        )
                    }
                    if layerType.hasSecondaryParam {
                        filterSlider(
                            label: layerType.secondaryParamLabel,
                            value: paramBinding("secondary", fallback: 0.5)
                        )
                    }

                    Spacer(minLength: 0)
                }
            } else {
                VStack {
                    Text("Select a filter to adjust")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding(10)
        .frame(height: Self.panelHeight)
        .frame(maxWidth: .infinity)
        .background(Color.accentColor.opacity(layerType != nil ? 0.06 : 0.02))
        .cornerRadius(8)
    }

    private func paramBinding(_ key: String, fallback: Double) -> Binding<Double> {
        Binding(
            get: { activeLayer?.param(key) ?? fallback },
            set: { newVal in
                guard let layerType else { return }
                if let index = viewModel.editPayload.layers.firstIndex(where: { $0.type == layerType }) {
                    viewModel.editPayload.layers[index].setParam(key, newVal)
                    viewModel.schedulePreviewRender()
                }
            }
        )
    }

    private func filterSlider(label: String, value: Binding<Double>) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(label).font(.caption2).foregroundStyle(.secondary)
                Spacer()
                Text(String(format: "%.0f%%", value.wrappedValue * 100))
                    .font(.caption2)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            Slider(value: value, in: 0.0...1.0, step: 0.01,
                   onEditingChanged: { editing in
                if editing { viewModel.pushUndoSnapshot() }
            })
        }
    }
}
