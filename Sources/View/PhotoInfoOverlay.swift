import SwiftUI

/// Floating metadata card shown when the user presses "i" — over the viewer
/// (with histogram) and over the gallery grid (photo facts only).
struct PhotoInfoOverlay: View {
    let photo: PhotoItem
    var histogramData: HistogramData? = nil
    var histogramMode: HistogramView.HistogramMode = .rgb

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(photo.filename).fontWeight(.semibold)
                    HStack(spacing: 16) {
                        Text(photo.dimensionsString)
                        Text(photo.displaySize)
                        Text((photo.dateTakenOriginal ?? photo.modificationDate).formatted(date: .abbreviated, time: .shortened))
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                Spacer()
            }

            if let data = histogramData {
                HistogramView(data: data, mode: histogramMode)
                    .frame(height: 56)
            }

            if let exif = photo.exifSummary {
                HStack {
                    Text(exif)
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                    if let cam = photo.cameraSummary {
                        Text(cam)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                }
            }
        }
        .padding(12)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .padding(12)
    }
}
