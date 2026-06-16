import SwiftUI

struct FilterButton: View {
    @Environment(AppViewModel.self) private var viewModel
    let layerType: LayerType
    @Binding var selectedFilter: LayerType?

    private var isActive: Bool {
        viewModel.editPayload.layers.contains { $0.type == layerType }
    }

    private var isSelected: Bool {
        selectedFilter == layerType
    }

    var body: some View {
        Button {
            viewModel.pushUndoSnapshot()
            if isActive {
                viewModel.editPayload.removeLayer(ofType: layerType)
                if isSelected { selectedFilter = nil }
            } else {
                let layer = AdjustmentLayer(type: layerType, parameters: ["value": 0.7])
                viewModel.editPayload.addLayer(layer)
                selectedFilter = layerType.hasParameters ? layerType : nil
            }
            viewModel.schedulePreviewRender()
        } label: {
            VStack(spacing: 5) {
                Image(systemName: layerType.iconName)
                    .font(.system(size: 18, weight: .regular))
                    .frame(height: 28)
                    .foregroundStyle(isActive ? Color.accentColor : Color.primary)

                Text(layerType.displayName)
                    .font(.caption2)
                    .lineLimit(1)
                    .foregroundStyle(isActive ? Color.accentColor : Color.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(isActive ? Color.accentColor.opacity(0.12) : Color.primary.opacity(0.04))
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(
                        isActive ? Color.accentColor : Color.primary.opacity(0.12),
                        lineWidth: isSelected ? 2 : (isActive ? 1.5 : 1)
                    )
            )
        }
        .buttonStyle(.plain)
        // Right-click or click-when-active selects for slider adjustment
        .simultaneousGesture(
            TapGesture().modifiers(.option).onEnded {
                if isActive, layerType.hasParameters {
                    selectedFilter = layerType
                }
            }
        )
    }
}
