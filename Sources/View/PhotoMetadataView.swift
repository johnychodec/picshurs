import SwiftUI

struct PhotoMetadataView: View {
    @Environment(AppViewModel.self) private var viewModel

    var body: some View {
        VStack(spacing: 0) {
            if let photo = viewModel.selectedPhoto {
                histogramSection(photo: photo)

                if photo.cameraModel != nil || photo.lensModel != nil
                    || photo.aperture != nil || photo.shutterSpeed != nil
                    || photo.iso != nil {
                    Divider()
                        .padding(.vertical, 8)
                    exifSection(photo: photo)
                }
            }
        }
    }

    private func histogramSection(photo: PhotoItem) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Histogram")
                    .font(.caption)
                    .fontWeight(.semibold)
                Spacer()
                Picker("Mode", selection: Bindable(viewModel).histogramMode) {
                    Text("RGB").tag(HistogramView.HistogramMode.rgb)
                    Text("Mono").tag(HistogramView.HistogramMode.luminance)
                }
                .pickerStyle(.segmented)
                .controlSize(.mini)
                .frame(width: 80)
            }

            if let data = viewModel.histogramData {
                HistogramView(data: data, mode: viewModel.histogramMode)
                    .frame(height: 64)
            } else {
                Rectangle()
                    .fill(Color.black.opacity(0.1))
                    .frame(height: 64)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                    .overlay {
                        ProgressView()
                            .controlSize(.small)
                            .scaleEffect(0.7)
                    }
            }
        }
    }

    private func exifSection(photo: PhotoItem) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if let summary = photo.exifSummary {
                HStack {
                    Image(systemName: "camera.aperture")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                    Text(summary)
                        .font(.caption)
                        .monospacedDigit()
                }
            }

            if let cam = photo.cameraSummary {
                HStack {
                    Image(systemName: "camera.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                    Text(cam)
                        .font(.caption)
                        .lineLimit(2)
                }
            }
        }
    }
}
