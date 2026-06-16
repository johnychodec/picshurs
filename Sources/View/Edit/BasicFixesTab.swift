import SwiftUI

struct BasicFixesTab: View {
    @Environment(AppViewModel.self) private var viewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            rotationButtons
            Divider()
            autoEnhanceButtons
            Divider()
            cropSection
            Divider()
            straightenSection
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    // MARK: - Rotation

    private var rotationButtons: some View {
        HStack(spacing: 8) {
            Button(action: {
                viewModel.pushUndoSnapshot()
                viewModel.editPayload.rotateLeft()
                viewModel.schedulePreviewRender()
            }) {
                VStack(spacing: 2) {
                    Image(systemName: "rotate.left")
                    Text("Left").font(.caption2)
                }
                .frame(maxWidth: .infinity)
            }

            Button(action: {
                viewModel.pushUndoSnapshot()
                viewModel.editPayload.rotateRight()
                viewModel.schedulePreviewRender()
            }) {
                VStack(spacing: 2) {
                    Image(systemName: "rotate.right")
                    Text("Right").font(.caption2)
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    // MARK: - Auto Enhance

    private var autoEnhanceButtons: some View {
        HStack(spacing: 6) {
            Button(action: { viewModel.applyAutoContrast() }) {
                VStack(spacing: 2) {
                    if viewModel.isAutoEnhancing {
                        ProgressView().scaleEffect(0.5).frame(height: 12)
                    } else {
                        Image(systemName: "circle.righthalf.filled").font(.system(size: 12))
                    }
                    Text("Contrast").font(.caption2)
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .tint(.secondary)
            .disabled(viewModel.isAutoEnhancing)

            Button(action: { viewModel.applyAutoColor() }) {
                VStack(spacing: 2) {
                    if viewModel.isAutoEnhancing {
                        ProgressView().scaleEffect(0.5).frame(height: 12)
                    } else {
                        Image(systemName: "paintpalette").font(.system(size: 12))
                    }
                    Text("Color").font(.caption2)
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .tint(.secondary)
            .disabled(viewModel.isAutoEnhancing)

            Button(action: { viewModel.applyImFeelingLucky() }) {
                VStack(spacing: 2) {
                    if viewModel.isAutoEnhancing {
                        ProgressView().scaleEffect(0.5).frame(height: 12)
                    } else {
                        Image(systemName: "wand.and.stars").font(.system(size: 12))
                    }
                    Text("Lucky").font(.caption2)
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .tint(.accentColor)
            .disabled(viewModel.isAutoEnhancing)
        }
    }

    // MARK: - Crop

    private var cropSection: some View {
        Group {
            if viewModel.isCropping {
                VStack(spacing: 8) {
                    Text("Crop Mode")
                        .font(.caption)
                        .fontWeight(.semibold)

                    HStack(spacing: 4) {
                        Menu {
                            Button {
                                viewModel.setCropAspectRatio(nil)
                            } label: {
                                HStack {
                                    Text("Free")
                                    if viewModel.cropAspectRatio == nil {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                            if let orig = viewModel.originalCropAspectRatio {
                                Button {
                                    viewModel.setCropAspectRatio(orig)
                                } label: {
                                    HStack {
                                        Text("Original")
                                        if viewModel.cropAspectRatio == orig {
                                            Image(systemName: "checkmark")
                                        }
                                    }
                                }
                            }
                            Divider()
                            ForEach(cropPresets, id: \.label) { preset in
                                Button {
                                    viewModel.setCropAspectRatio(preset.ratio)
                                } label: {
                                    HStack {
                                        Text(preset.label)
                                        if viewModel.cropAspectRatio == preset.ratio {
                                            Image(systemName: "checkmark")
                                        }
                                    }
                                }
                            }
                        } label: {
                            HStack(spacing: 3) {
                                Text(cropRatioLabel)
                                    .font(.caption)
                                    .lineLimit(1)
                                Image(systemName: "chevron.down")
                                    .font(.system(size: 8))
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(.regularMaterial)
                            .cornerRadius(4)
                        }
                        .buttonStyle(.plain)
                        .menuIndicator(.hidden)

                        if viewModel.cropAspectRatio != nil {
                            Button(action: { viewModel.flipCropAspectRatio() }) {
                                Image(systemName: "arrow.left.arrow.right")
                                    .font(.system(size: 11))
                            }
                            .buttonStyle(.plain)
                            .help("Rotate layout")
                        }
                    }

                    HStack(spacing: 8) {
                        Button(action: { viewModel.cancelCrop() }) {
                            Label("Cancel", systemImage: "xmark")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .tint(.secondary)

                        Button(action: { viewModel.applyCrop() }) {
                            Label("Apply", systemImage: "checkmark")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
            } else {
                Button(action: { viewModel.enterCropMode() }) {
                    Label("Crop", systemImage: "crop")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private var cropRatioLabel: String {
        guard let ratio = viewModel.cropAspectRatio else { return "Free" }
        if let orig = viewModel.originalCropAspectRatio, ratio == orig { return "Original" }
        return ratioLabel(for: ratio)
    }

    private func ratioLabel(for ratio: CGFloat) -> String {
        let known: [(String, CGFloat)] = [
            ("1:1", 1.0), ("4:6", 4.0/6.0), ("6:4", 6.0/4.0),
            ("5:7", 5.0/7.0), ("7:5", 7.0/5.0),
            ("8:10", 8.0/10.0), ("10:8", 10.0/8.0),
            ("16:9", 16.0/9.0), ("9:16", 9.0/16.0),
        ]
        for (label, value) in known {
            if abs(ratio - value) < 0.001 { return label }
        }
        return String(format: "%.2f:1", ratio)
    }

    private struct CropPreset { let label: String; let ratio: CGFloat }
    private let cropPresets: [CropPreset] = [
        CropPreset(label: "1:1", ratio: 1.0),
        CropPreset(label: "4:6", ratio: 4.0/6.0),
        CropPreset(label: "5:7", ratio: 5.0/7.0),
        CropPreset(label: "8:10", ratio: 8.0/10.0),
        CropPreset(label: "16:9", ratio: 16.0/9.0),
    ]

    // MARK: - Straighten

    private var straightenSection: some View {
        Group {
            if viewModel.isStraightening {
                VStack(spacing: 8) {
                    Text("Straightening")
                        .font(.caption)
                        .fontWeight(.semibold)

                    HStack {
                        Button(action: {
                            viewModel.pushUndoSnapshot()
                            viewModel.editPayload.straightenAngle = max(-45, viewModel.editPayload.straightenAngle - 0.5)
                            viewModel.schedulePreviewRender()
                        }) {
                            Image(systemName: "chevron.left").font(.system(size: 10))
                        }
                        .buttonStyle(.plain)

                        Text(String(format: "%.1f°", viewModel.editPayload.straightenAngle))
                            .font(.caption)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)

                        Button(action: {
                            viewModel.pushUndoSnapshot()
                            viewModel.editPayload.straightenAngle = min(45, viewModel.editPayload.straightenAngle + 0.5)
                            viewModel.schedulePreviewRender()
                        }) {
                            Image(systemName: "chevron.right").font(.system(size: 10))
                        }
                        .buttonStyle(.plain)
                    }

                    Button(action: {
                        viewModel.pushUndoSnapshot()
                        viewModel.editPayload.straightenAngle = 0
                        viewModel.schedulePreviewRender()
                    }) {
                        Label("Reset", systemImage: "arrow.counterclockwise")
                            .font(.caption)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .tint(.secondary)

                    HStack(spacing: 8) {
                        Button(action: { viewModel.cancelStraighten() }) {
                            Label("Cancel", systemImage: "xmark").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .tint(.secondary)

                        Button(action: { viewModel.applyStraighten() }) {
                            Label("Done", systemImage: "checkmark").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
            } else {
                Button(action: { viewModel.enterStraightenMode() }) {
                    Label("Straighten", systemImage: "rotate.right")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
        }
    }
}
