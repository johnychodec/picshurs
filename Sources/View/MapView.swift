import SwiftUI
import MapKit

/// Map of geotagged photos. One thumbnail pin per photo that has EXIF GPS;
/// tapping a pin opens it in the detail viewer (prev/next walk the same
/// `filteredPhotos` set, so navigation works out of the box).
struct MapView: View {
    @Environment(AppViewModel.self) private var viewModel
    @State private var position: MapCameraPosition = .automatic
    /// Center of whatever the camera currently shows; tracked so the zoom
    /// slider can change span without yanking the map off the user's location.
    @State private var currentCenter: CLLocationCoordinate2D?

    private var geotagged: [PhotoItem] {
        viewModel.filteredPhotos.filter { $0.coordinate != nil }
    }

    /// Maps the normalized slider value (0…1) to a coordinate span. Zoom is
    /// perceptually logarithmic, so interpolate the span geometrically:
    /// 0 → ~120° (whole world), 1 → ~0.004° (street level).
    private func span(for zoom: Double) -> MKCoordinateSpan {
        let maxDelta = 120.0
        let minDelta = 0.004
        let delta = maxDelta * pow(minDelta / maxDelta, max(0, min(1, zoom)))
        return MKCoordinateSpan(latitudeDelta: delta, longitudeDelta: delta)
    }

    private func applyZoom(_ zoom: Double) {
        let center = currentCenter ?? geotagged.first?.coordinate
        guard let center else { return }
        withAnimation(.easeInOut(duration: 0.2)) {
            position = .region(MKCoordinateRegion(center: center, span: span(for: zoom)))
        }
    }

    var body: some View {
        Map(position: $position) {
            ForEach(geotagged) { photo in
                Annotation(photo.filename, coordinate: photo.coordinate!) {
                    Button {
                        viewModel.selectSingle(photo)
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.9)) {
                            viewModel.isViewingPhoto = true
                        }
                    } label: {
                        PinThumbnail(photo: photo)
                    }
                    .buttonStyle(.plain)
                }
                .annotationTitles(.hidden)
            }
        }
        .mapStyle(.standard(elevation: .flat))
        .onMapCameraChange { context in
            currentCenter = context.region.center
        }
        // Thumbnail zoom slider drives map zoom while in map mode.
        .onChange(of: viewModel.mapZoom) { _, newZoom in
            applyZoom(newZoom)
        }
        // Ratio button re-frames all pins.
        .onChange(of: viewModel.mapResetToken) { _, _ in
            withAnimation(.easeInOut(duration: 0.2)) { position = .automatic }
        }
        .overlay(alignment: .topTrailing) {
            Text("\(geotagged.count) geotagged")
                .font(.caption)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.ultraThinMaterial, in: Capsule())
                .padding(10)
        }
        // Frame all pins when the set changes (folder switch, fresh index).
        .onChange(of: geotagged.map(\.id)) { _, _ in
            position = .automatic
        }
    }
}

/// Circular thumbnail "teardrop" pin.
private struct PinThumbnail: View {
    let photo: PhotoItem

    var body: some View {
        ThumbnailImage(url: photo.url, modificationDate: photo.modificationDate)
            .frame(width: 40, height: 40)
            .clipShape(Circle())
            .overlay(Circle().stroke(.white, lineWidth: 2))
            .shadow(radius: 2)
    }
}
