import SwiftUI

struct TuningTab: View {
    @Environment(AppViewModel.self) private var viewModel

    private var payload: EditPayload { viewModel.editPayload }

    private func layerValue(for type: LayerType) -> Double {
        payload.tuningValue(for: type) ?? defaultValue(for: type)
    }

    private func defaultValue(for type: LayerType) -> Double {
        switch type {
        case .brightness: 0
        case .contrast: 1
        case .exposure: 0
        case .saturation: 1
        case .temperature: 6500
        case .tint: 0
        case .shadows: 0
        case .sharpness: 0
        default: 0
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            tuningSlider(label: "Brightness", type: .brightness, range: -1.0...1.0, format: "%.2f")
            tuningSlider(label: "Contrast",   type: .contrast,   range:  0.0...2.0, format: "%.2f")
            tuningSlider(label: "Exposure",   type: .exposure,   range: -1.0...1.0, format: "%.2f")
            tuningSlider(label: "Saturation", type: .saturation, range:  0.0...2.0, format: "%.2f")
            tuningSlider(label: "Shadow Detail", type: .shadows, range: -1.0...1.0, format: "%.2f")
            tuningSlider(label: "Sharpness",  type: .sharpness,  range:  0.0...2.0, format: "%.2f")
            Divider()
            temperatureSliders
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private func tuningSlider(
        label: String,
        type: LayerType,
        range: ClosedRange<Double>,
        format: String
    ) -> some View {
        let currentValue = layerValue(for: type)
        let isActive = payload.hasLayer(ofType: type)

        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label).font(.caption)
                Spacer()
                Text(String(format: format, currentValue))
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(isActive ? Color.accentColor : .secondary)
            }
            Slider(
                value: Binding(
                    get: { currentValue },
                    set: { newValue in
                        viewModel.editPayload.setTuningValue(newValue, for: type)
                        viewModel.schedulePreviewRender()
                    }
                ),
                in: range,
                step: type == .temperature ? 50 : type == .tint ? 1 : 0.01,
                onEditingChanged: { editing in
                    if editing { viewModel.pushUndoSnapshot() }
                }
            )
        }
    }

    private var temperatureSliders: some View {
        let tempKey = LayerType.temperature.defaultParamKey
        let tintKey = LayerType.tint.defaultParamKey
        let tempLayer = viewModel.editPayload.layers.first(where: { $0.type == LayerType.temperature })
        let currentTemp = tempLayer?.param(tempKey) ?? 6500
        let currentTint = tempLayer?.param(tintKey) ?? 0
        let isActive = tempLayer != nil

        return Group {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Temperature").font(.caption)
                    Spacer()
                    Text(String(format: "%.0fK", currentTemp))
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(isActive ? Color.accentColor : .secondary)
                }
                Slider(
                    value: Binding(
                        get: { currentTemp },
                        set: { newValue in
                            viewModel.editPayload.setTuningValue(newValue, for: .temperature)
                            viewModel.schedulePreviewRender()
                        }
                    ),
                    in: 3000...9000,
                    step: 50,
                    onEditingChanged: { editing in
                        if editing { viewModel.pushUndoSnapshot() }
                    }
                )
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Tint").font(.caption)
                    Spacer()
                    Text(String(format: "%.0f", currentTint))
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(isActive ? Color.accentColor : .secondary)
                }
                Slider(
                    value: Binding(
                        get: { currentTint },
                        set: { newValue in
                            viewModel.editPayload.setTuningValue(newValue, for: .tint)
                            viewModel.schedulePreviewRender()
                        }
                    ),
                    in: -150...150,
                    step: 1,
                    onEditingChanged: { editing in
                        if editing { viewModel.pushUndoSnapshot() }
                    }
                )
            }
        }
    }
}
