import SwiftUI
import UniformTypeIdentifiers

struct TrayDragItem: Codable, Transferable {
    let photoID: String
    let photoURL: URL

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .plainText)
    }
}

struct PhotoTrayView: View {
    @Environment(AppViewModel.self) private var viewModel
    @Environment(AppSettings.self) private var settings

    @State private var trayWidth: CGFloat = 0
    private let rowSpacing: CGFloat = 4
    private let trayInfoWidth: CGFloat = 34

    var body: some View {
        VStack(spacing: 0) {
            ScrollView(.vertical, showsIndicators: true) {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: settings.trayThumbnailSize, maximum: settings.trayThumbnailSize), spacing: rowSpacing)],
                    spacing: rowSpacing
                ) {
                    if viewModel.visibleTrayPhotoOrder.isEmpty {
                        Text("Select items then press P to pin · Right-click for more options")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.vertical, 12)
                    } else {
                        ForEach(viewModel.visibleTrayPhotoOrder) { photo in
                            trayCell(photo: photo)
                        }
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(height: gridHeight)
            .clipped()
            .background(
                GeometryReader { geo in
                    Color.clear
                        .onAppear { trayWidth = geo.size.width }
                        .onChange(of: geo.size.width) { _, newWidth in
                            trayWidth = newWidth
                        }
                }
            )
            // Same actions, order, and icons as the button row below the tray.
            .contextMenu {
                if !viewModel.visibleTrayPhotoOrder.isEmpty {
                    Button { viewModel.clearAllFromTrayWithConfirmation() } label: {
                        Label("Clear Tray", systemImage: "pin.slash")
                    }
                    Divider()
                    Button { viewModel.trayBatchExport() } label: {
                        Label("Export in tray order", systemImage: "square.and.arrow.up")
                    }
                    Button { viewModel.trayBatchExportNoMetadata() } label: {
                        Label("Export without metadata (tray order)", systemImage: "square.and.arrow.up.trianglebadge.exclamationmark")
                    }
                    .disabled(!viewModel.canRunPhotoOnlyTrayActions)
                    Button { viewModel.trayBatchExportForWeb() } label: {
                        Label("Export for web (tray order)", systemImage: "globe")
                    }
                    .disabled(!viewModel.canRunPhotoOnlyTrayActions)
                    Divider()
                    Button { viewModel.trayBatchDuplicate() } label: {
                        Label("Duplicate", systemImage: "doc.on.doc")
                    }
                    Button { viewModel.trayBatchMove() } label: {
                        Label("Move to...", systemImage: "document.badge.arrow.up")
                    }
                    Divider()
                    Button(role: .destructive) { viewModel.trayBatchDelete() } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
            .dropDestination(for: TrayDragItem.self) { items, location in
                guard let draggedItem = items.first else { return false }
                guard let sourceIndex = viewModel.trayPhotoOrder.firstIndex(where: { $0.id == draggedItem.photoID }) else { return false }

                let dropZone = dropZone(from: location)
                if dropZone == sourceIndex || dropZone == sourceIndex + 1 { return false }

                viewModel.moveTrayItem(from: sourceIndex, toDropZone: dropZone)
                return true
            }
            .dropDestination(for: URL.self) { urls, _ in
                guard let url = urls.first else { return false }
                guard let photo = viewModel.photos.first(where: { $0.url == url }) else { return false }
                if viewModel.temporarilySelectedPhotos.contains(photo) {
                    for p in viewModel.temporarilySelectedPhotos {
                        viewModel.pinPhoto(p)
                    }
                } else {
                    viewModel.pinPhoto(photo)
                }
                return true
            }

            if !viewModel.visibleTrayPhotoOrder.isEmpty {
                Divider()
                    .padding(.horizontal, 8)

                HStack(spacing: 0) {
                    trayInfo

                    Divider()
                        .frame(height: 28)
                        .padding(.horizontal, 8)

                    batchActions
                }
                .padding(.horizontal, 8)
                // Fixed 40pt — matches the sidebar's Settings row so the two
                // dividers sit on the same horizontal line.
                .frame(height: 40)
            }
        }
        .frame(maxHeight: trayMaxHeight)
        .padding(.horizontal, 8)
        .background(.regularMaterial)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Color.primary.opacity(0.08))
                .frame(height: 0.5)
        }
    }

    // MARK: — Drop helpers

    private func columnsCount() -> Int {
        let size = settings.trayThumbnailSize
        let totalSpacing = rowSpacing
        let available = trayWidth - 16 // subtract horizontal padding
        if available <= size { return max(1, Int(available / size)) }
        let cols = Int((available + totalSpacing) / (size + totalSpacing))
        return max(1, cols)
    }

    private func dropZone(from location: CGPoint) -> Int {
        let cols = columnsCount()
        let size = settings.trayThumbnailSize
        let count = viewModel.trayPhotoOrder.count

        // Adjust for grid padding (8 horizontal, 4 vertical)
        let adjustedX = location.x - 8
        let adjustedY = location.y - 4

        let col = max(0, Int(adjustedX / (size + rowSpacing)))
        let row = max(0, Int(adjustedY / (size + rowSpacing)))
        var idx = row * cols + col
        idx = min(idx, count)
        return idx
    }

    // MARK: — Dimensions

    private var gridHeight: CGFloat {
        let thumbnail = settings.trayThumbnailSize
        let rows = CGFloat(settings.trayVisibleRows)
        return rows * thumbnail + (rows - 1) * rowSpacing + 8 // padding
    }

    private var trayMaxHeight: CGFloat {
        let actionsHeight: CGFloat = viewModel.visibleTrayPhotoOrder.isEmpty ? 0 : 44
        return gridHeight + actionsHeight
    }

    // MARK: — Cells

    private func trayCell(photo: PhotoItem) -> some View {
        let size = settings.trayThumbnailSize
        let isTemp = viewModel.temporarilySelectedPhotos.contains(photo)
        let isPinned = viewModel.isPinned(photo)
        let isFocus = viewModel.selectedPhoto == photo

        return ZStack(alignment: .topTrailing) {
            ThumbnailImage(url: photo.url, modificationDate: photo.modificationDate, mediaKind: photo.mediaKind)
                .frame(width: size, height: size)
                .clipped()
                .rotationEffect(.degrees(Double(viewModel.editRotation(for: photo.url))))

            if isPinned {
                Image(systemName: "pin.fill")
                    .font(.system(size: max(8, size * 0.2)))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.4), radius: 2, y: 1)
                    .offset(x: -2, y: 2)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }

            let activeDots = DotColor.activeColors(from: photo.dotColor)
            if !activeDots.isEmpty {
                HStack(spacing: 2) {
                    ForEach(activeDots) { dot in
                        Circle().fill(dot.color)
                            .frame(width: max(6, size * 0.15), height: max(6, size * 0.15))
                            .shadow(color: .black.opacity(0.2), radius: 1)
                    }
                }
                .padding(3)
            }

            if viewModel.hasEdits(for: photo.url) {
                Image(systemName: "pencil.circle.fill")
                    .font(.system(size: max(8, size * 0.2)))
                    .foregroundStyle(.orange)
                    .shadow(color: .black.opacity(0.4), radius: 2, y: 1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .offset(x: -2, y: 2)
            }

            if photo.isVideo {
                VideoBadge(size: max(8, size * 0.16))
                    .padding(4)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
            }

            if size >= 40 {
                Button {
                    if isTemp {
                        viewModel.removeFromTemporarySelection(photo)
                    } else if isPinned {
                        viewModel.unpinPhoto(photo)
                    }
                    if viewModel.selectedPhoto == photo {
                        viewModel.selectedPhoto = viewModel.temporarilySelectedPhotos.first ?? viewModel.pinnedPhotos.first
                        viewModel.clearExternalVideoReturnStateIfSelectionChanged()
                    }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: max(10, size * 0.25)))
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, .black.opacity(0.55))
                        .shadow(color: .black.opacity(0.3), radius: 2, y: 1)
                }
                .buttonStyle(.plain)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: max(4, size * 0.1)))
        .shadow(color: .black.opacity(0.12), radius: 2, y: 1)
        .overlay {
            if isFocus {
                RoundedRectangle(cornerRadius: max(4, size * 0.1))
                    .strokeBorder(Color.accentColor, lineWidth: 2)
            } else if isTemp {
                RoundedRectangle(cornerRadius: max(4, size * 0.1))
                    .strokeBorder(Color.accentColor.opacity(0.5), lineWidth: 1.5)
            } else if isPinned {
                RoundedRectangle(cornerRadius: max(4, size * 0.1))
                    .strokeBorder(Color.yellow.opacity(0.8), lineWidth: 1.5)
            }
        }
        .onTapGesture(count: 2) {
            viewModel.selectSingle(photo)
            viewModel.openSelectedPhoto()
        }
        .simultaneousGesture(
            TapGesture(count: 1)
                .onEnded { _ in
                    viewModel.selectSingle(photo)
                }
        )
        .contextMenu {
            if isPinned {
                Button("Unpin from tray") {
                    viewModel.unpinPhoto(photo)
                }
            } else {
                Button("Pin to tray") {
                    viewModel.pinPhoto(photo)
                }
            }
            if photo.isVideo {
                Button("Open Video") {
                    viewModel.openVideoInDefaultPlayer(photo)
                }
            }
            Button("Show in Finder") {
                NSWorkspace.shared.selectFile(photo.url.path, inFileViewerRootedAtPath: "")
            }
        }
        .draggable(TrayDragItem(photoID: photo.id, photoURL: photo.url))
        .id(photo.id)
    }

    // MARK: — Info

    private var trayInfo: some View {
        VStack(spacing: 2) {
            Text("Tray")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
            Text("\(viewModel.visibleTrayPhotoOrder.count)")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .frame(width: trayInfoWidth)
    }

    // MARK: — Batch Actions

    private var batchActions: some View {
        HStack(spacing: 6) {
            trayIconButton(icon: "pin.slash", help: "Clear tray") {
                viewModel.clearAllFromTrayWithConfirmation()
            }

            trayIconButton(icon: "square.and.arrow.up", help: "Export in tray order") {
                viewModel.trayBatchExport()
            }

            trayIconButton(icon: "square.and.arrow.up.trianglebadge.exclamationmark", help: "Export without metadata (tray order)") {
                viewModel.trayBatchExportNoMetadata()
            }
            .disabled(!viewModel.canRunPhotoOnlyTrayActions)

            trayIconButton(icon: "globe", help: "Export for web (tray order)") {
                viewModel.trayBatchExportForWeb()
            }
            .disabled(!viewModel.canRunPhotoOnlyTrayActions)

            trayIconButton(icon: "doc.on.doc", help: "Duplicate") {
                viewModel.trayBatchDuplicate()
            }

            trayIconButton(icon: "document.badge.arrow.up", help: "Move to...") {
                viewModel.trayBatchMove()
            }

            trayIconButton(icon: "trash", help: "Delete", color: .red) {
                viewModel.trayBatchDelete()
            }

            Spacer()
        }
        .padding(.leading, 4)
    }

    private func trayIconButton(icon: String, help: String, color: Color = .secondary, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 13))
                .foregroundStyle(color)
                .frame(width: 28, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }
}
