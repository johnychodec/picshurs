import SwiftUI

struct PhotoDetailView: View {
    @Environment(AppViewModel.self) private var viewModel

    @State private var zoomScale: CGFloat = 1.0
    @State private var lastZoomScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero
    @State private var showInfo = false
    @State private var showDotPicker = false
    @State private var fallbackImage: NSImage?
    @State private var fallbackPhotoID: String?
    private let minZoom: CGFloat = 0.1
    private let maxZoom: CGFloat = 8.0
    private let zoomStep: CGFloat = 1.25
    private let stripHeight: CGFloat = 90

    var body: some View {
        VStack(spacing: 0) {
            toolbarBar

            ZStack {
                Color.black

                displayedImage
            }
            .overlay {
                if viewModel.isCropping, let photo = viewModel.selectedPhoto {
                    cropOverlay(photo: photo)
                }
                if viewModel.isStraightening, let photo = viewModel.selectedPhoto {
                    straightenGridOverlay(photo: photo)
                }
            }
            .overlay(alignment: .bottom) {
                if showInfo, let photo = viewModel.selectedPhoto {
                    PhotoInfoOverlay(
                        photo: photo,
                        histogramData: viewModel.histogramData,
                        histogramMode: viewModel.histogramMode)
                }
                if viewModel.isStraightening {
                    straightenBottomBar
                }
            }
            .padding(.vertical, viewModel.isEditing ? 8 : 0)
            .background(Color.black)

            if !viewModel.isEditing {
                thumbnailStrip
            }
        }
        .onKeyPress(characters: .alphanumerics, phases: .down) { press in
            if press.characters == "i" { showInfo.toggle(); return .handled }
            return .ignored
        }
        .onChange(of: viewModel.viewerZoomCommandID) { _, _ in
            handleViewerZoomCommand(viewModel.viewerZoomCommand)
        }
        .onChange(of: viewModel.selectedPhoto?.id) { _, _ in
            resetZoom()
            seedFallbackFromThumbnail()
            viewModel.loadSidecarForSelectedPhoto()
            viewModel.schedulePreviewRender()
        }
        .onAppear {
            seedFallbackFromThumbnail()
            viewModel.loadSidecarForSelectedPhoto()
            viewModel.schedulePreviewRender()
        }
        .task(id: viewModel.selectedPhoto?.id) {
            guard let photo = viewModel.selectedPhoto else { return }
            await loadFallbackImage(for: photo)
        }
    }

    /// The grid thumbnail is almost always in the memory cache — show it
    /// scaled up immediately so the gallery never opens to a blank spinner.
    private func seedFallbackFromThumbnail() {
        fallbackImage = nil
        fallbackPhotoID = nil
        guard let photo = viewModel.selectedPhoto,
              let thumb = ThumbnailService.shared.cachedThumbnail(
                  for: photo.url, modificationDate: photo.modificationDate)
        else { return }
        fallbackImage = NSImage(cgImage: thumb, size: NSSize(width: thumb.width, height: thumb.height))
        fallbackPhotoID = photo.id
    }

    // MARK: - Image Display

    @ViewBuilder
    private var displayedImage: some View {
        if let photo = viewModel.selectedPhoto {
            if photo.isVideo {
                videoPosterView(photo: photo)
            } else if let preview = viewModel.previewImage {
                let image = Image(nsImage: preview)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .scaleEffect(zoomScale)
                    .offset(offset)

                Group {
                    if viewModel.isCropping || viewModel.isStraightening {
                        image
                    } else {
                        image
                            .gesture(magnificationGesture)
                            .gesture(dragGesture)
                    }
                }
                .onTapGesture(count: 2) { handleDoubleTapImage() }
                .contextMenu {
                    contextMenu(for: photo)
                }
            } else if let fb = fallbackImage, fallbackPhotoID == photo.id {
                let image = Image(nsImage: fb)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .scaleEffect(zoomScale)
                    .offset(offset)

                Group {
                    if viewModel.isCropping || viewModel.isStraightening {
                        image
                    } else {
                        image
                            .gesture(magnificationGesture)
                            .gesture(dragGesture)
                    }
                }
                .onTapGesture(count: 2) { handleDoubleTapImage() }
                .contextMenu {
                    contextMenu(for: photo)
                }
            } else {
                ProgressView()
                    .controlSize(.large)
                    .foregroundStyle(.white)
                    // Integral frame avoids AppKit's fractional-constraint
                    // warning from the platform progress view
                    .frame(width: 32, height: 32)
            }
        } else {
            VStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.largeTitle)
                    .foregroundStyle(.secondary)
                Text("No photo selected")
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func videoPosterView(photo: PhotoItem) -> some View {
        if let fb = fallbackImage, fallbackPhotoID == photo.id {
            Image(nsImage: fb)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .scaleEffect(zoomScale)
                .offset(offset)
                .overlay {
                    Image(systemName: "play.circle.fill")
                        .font(.system(size: 72, weight: .semibold))
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, .black.opacity(0.45))
                        .shadow(color: .black.opacity(0.45), radius: 10, y: 3)
                }
                .contentShape(Rectangle())
                .onTapGesture { viewModel.openVideoInDefaultPlayer(photo) }
                .onTapGesture(count: 2) { viewModel.openVideoInDefaultPlayer(photo) }
                .contextMenu {
                    contextMenu(for: photo)
                }
        } else {
            ProgressView()
                .controlSize(.large)
                .foregroundStyle(.white)
                .frame(width: 32, height: 32)
        }
    }

    private func loadFallbackImage(for photo: PhotoItem) async {
        if photo.isVideo {
            let url = photo.url
            let photoID = photo.id
            let image = await ThumbnailService.shared.thumbnail(
                for: url,
                modificationDate: photo.modificationDate,
                tier: ThumbnailService.detailTier,
                mediaKind: .video
            )
            guard !Task.isCancelled, viewModel.selectedPhoto?.id == photoID else { return }
            if let image {
                fallbackImage = NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
                fallbackPhotoID = photoID
            } else {
                fallbackImage = nil
                fallbackPhotoID = nil
            }
            return
        }
        let url = photo.url
        let photoID = photo.id
        let screenSize = NSScreen.main?.visibleFrame.size ?? CGSize(width: 1200, height: 800)
        let maxDimension = max(screenSize.width, screenSize.height)

        let image = await Task.detached(priority: .userInitiated) { () -> NSImage? in
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
                return nil
            }
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: maxDimension,
            ]
            guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
                return nil
            }
            return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
        }.value

        guard !Task.isCancelled, viewModel.selectedPhoto?.id == photoID else { return }
        fallbackImage = image
        fallbackPhotoID = photoID
        viewModel.schedulePreviewRender()
    }

    // MARK: - Toolbar

    private var toolbarBar: some View {
        HStack(spacing: 12) {
            Button(action: {
                if viewModel.isEditing {
                    withAnimation(.easeInOut(duration: 0.25)) { viewModel.toggleEditMode() }
                }
                viewModel.closeViewer()
            }) {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 13, weight: .medium))
                    Text("Back to library")
                        .font(.system(size: 13, weight: .medium))
                }
            }
            .buttonStyle(.plain)

            Spacer()

            if let photo = viewModel.selectedPhoto {
                VStack(spacing: 1) {
                    Text(photo.filename)
                        .font(.system(size: 13, weight: .medium))
                        .lineLimit(1)
                    if !photo.dimensionsString.isEmpty {
                        Text("\(photo.dimensionsString) · \(photo.displaySize)")
                            .font(.system(size: 10.5))
                            .foregroundStyle(.tertiary)
                    } else {
                        Text(photo.displaySize)
                            .font(.system(size: 10.5))
                            .foregroundStyle(.tertiary)
                    }
                }
            }

            Spacer()

            HStack(spacing: 4) {
                if !viewModel.isEditing {
                    toolbarButton(image: "minus.magnifyingglass", color: .secondary) {
                        zoomOut()
                    }
                    .disabled(!canZoomOut)
                    .help("Zoom out")

                    toolbarButton(image: "plus.magnifyingglass", color: .secondary) {
                        zoomIn()
                    }
                    .disabled(!canZoomIn)
                    .help("Zoom in")

                    toolbarButton(image: "arrow.up.left.and.down.right.magnifyingglass", color: .secondary) {
                        resetZoom()
                    }
                    .disabled(!canResetZoom)
                    .help("Reset zoom")
                }

                if let photo = viewModel.selectedPhoto {
                    toolbarButton(
                        image: photo.dotColor > 0 ? "circle.fill" : "circle",
                        color: DotColor.activeColors(from: photo.dotColor).first?.color ?? .secondary
                    ) {
                        showDotPicker.toggle()
                    }
                    .popover(isPresented: $showDotPicker, arrowEdge: .bottom) {
                        DotPickerView(dotColor: photo.dotColor) { color in
                            if let color {
                                viewModel.toggleDotColor(photo, color: color)
                            } else {
                                viewModel.clearDotColor(photo)
                            }
                        }
                    }
                }

                toolbarButton(
                    image: viewModel.isEditing ? "pencil.circle.fill" : "pencil.circle",
                    color: viewModel.isEditing ? .accentColor
                        : ((viewModel.selectedPhoto?.isRaw == true || viewModel.selectedPhoto?.isVideo == true) ? Color.secondary.opacity(0.4) : .secondary)
                ) { withAnimation(.easeInOut(duration: 0.25)) { viewModel.toggleEditMode() } }
                .disabled(viewModel.selectedPhoto?.isVideo == true)
                .help(editButtonHelp)

                toolbarButton(image: "info.circle", color: .secondary) { showInfo.toggle() }

                toolbarButton(image: "trash", color: .secondary) { viewModel.deleteCurrentPhoto() }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.bar)
    }

    private func toolbarButton(image: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: image)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(color)
        }
        .buttonStyle(.plain)
    }

    private var editButtonHelp: String {
        if viewModel.selectedPhoto?.isVideo == true { return "Videos can't be edited" }
        if viewModel.selectedPhoto?.isRaw == true { return "RAW files can't be edited" }
        return "Edit photo (E)"
    }

    // MARK: - Thumbnail Strip

    private var thumbnailStrip: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 2) {
                    ForEach(viewModel.filteredPhotos) { photo in
                        thumbnailCell(photo: photo)
                            .id(photo.id)
                            .onTapGesture {
                                viewModel.selectSingle(photo)
                            }
                    }
                }
            }
            .frame(height: stripHeight)
            .background(.ultraThinMaterial)
            .onChange(of: viewModel.selectedPhoto?.id) { _, new in
                if let new {
                    withAnimation { proxy.scrollTo(new, anchor: .center) }
                }
            }
            .onAppear {
                if let id = viewModel.selectedPhoto?.id {
                    Task {
                        try? await Task.sleep(nanoseconds: 50_000_000)
                        withAnimation { proxy.scrollTo(id, anchor: .center) }
                    }
                }
            }
        }
    }

    private func thumbnailCell(photo: PhotoItem) -> some View {
        let isFocus = viewModel.selectedPhoto == photo
        let isInTray = viewModel.trayPhotos.contains(photo)
        let isTemp = viewModel.temporarilySelectedPhotos.contains(photo)
        let isPinned = viewModel.isPinned(photo)

        return ThumbnailImage(url: photo.url, modificationDate: photo.modificationDate, mediaKind: photo.mediaKind)
                .frame(width: stripHeight, height: stripHeight)
                .clipped()
                .rotationEffect(.degrees(Double(viewModel.editRotation(for: photo.url))))
                .overlay {
                    if isInTray {
                        Color.accentColor.opacity(0.25)
                            .frame(width: stripHeight, height: stripHeight)
                    }
                    if isFocus {
                        Rectangle().stroke(Color.accentColor, lineWidth: 3)
                    } else if isTemp {
                        Rectangle().stroke(Color.accentColor.opacity(0.6), lineWidth: 2)
                    } else if isPinned {
                        Rectangle().stroke(Color.yellow.opacity(0.6), lineWidth: 2)
                    }
                }
                .overlay(alignment: .topLeading) {
                    if viewModel.hasEdits(for: photo.url) {
                        Image(systemName: "pencil.circle.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(.orange)
                            .shadow(color: .black.opacity(0.4), radius: 1, y: 1)
                            .padding(3)
                    }
                }
                .overlay(alignment: .bottomTrailing) {
                    if photo.isVideo {
                        VideoBadge(size: 9)
                            .padding(4)
                    }
                }
                .opacity(isFocus ? 1.0 : (isInTray ? 0.75 : 0.5))
                .contextMenu {
                    contextMenu(for: photo)
                }
    }

    private func contextMenu(for photo: PhotoItem) -> some View {
        let isTemp = viewModel.temporarilySelectedPhotos.contains(photo)
        let isPinned = viewModel.isPinned(photo)
        let multiSelected = viewModel.temporarilySelectedPhotos.count > 1 && isTemp

        return Group {
            if multiSelected {
                Divider()
                Button("Export \(viewModel.temporarilySelectedPhotos.count) selected") {
                    viewModel.batchExport()
                }
                Button("Copy \(viewModel.temporarilySelectedPhotos.count) selected") {
                    viewModel.batchCopy()
                }
                Button("Move \(viewModel.temporarilySelectedPhotos.count) selected") {
                    viewModel.batchMove()
                }
                Divider()
                Menu("Virtual albums") {
                    ForEach(DotColor.all) { dot in
                        Button {
                            viewModel.batchToggleDotColor(dot.rawValue)
                        } label: {
                            HStack {
                                Circle().fill(dot.color).frame(width: 12, height: 12)
                                Text(dot.name)
                            }
                        }
                    }
                    Divider()
                    Button("Clear All") {
                        viewModel.batchClearDotColor()
                    }
                }
                Divider()
                Button("Delete \(viewModel.temporarilySelectedPhotos.count) selected") {
                    viewModel.batchDelete()
                }
                Divider()
            } else {
                // Star functionality removed - using dot colors instead
                Divider()
                if isPinned {
                    Button("Unpin from tray") {
                        viewModel.unpinPhoto(photo)
                    }
                } else {
                    Button("Pin to tray") {
                        viewModel.pinPhoto(photo)
                    }
                }
                Divider()
                Menu("Virtual albums") {
                    ForEach(DotColor.all) { dot in
                        Button {
                            viewModel.toggleDotColor(photo, color: dot.rawValue)
                        } label: {
                            HStack {
                                Circle().fill(dot.color).frame(width: 12, height: 12)
                                Text(dot.name)
                            }
                        }
                    }
                    Divider()
                    Button("Clear All") {
                        viewModel.clearDotColor(photo)
                    }
                }
                Divider()
            }

            if photo.isVideo {
                Button("Open Video") {
                    viewModel.openVideoInDefaultPlayer(photo)
                }
            }

            Button("Show in Finder") {
                NSWorkspace.shared.selectFile(photo.url.path, inFileViewerRootedAtPath: "")
            }

            if !multiSelected {
                Divider()
                Button("Move to Trash") {
                    viewModel.deletePhotos([photo])
                }
            }
        }
    }

    // MARK: - Gestures

    private var magnificationGesture: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                let newScale = lastZoomScale * value.magnification
                zoomScale = min(max(newScale, minZoom), maxZoom)
            }
            .onEnded { _ in lastZoomScale = zoomScale }
    }

    private var dragGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                guard zoomScale > 1.0 else {
                    offset = .zero
                    return
                }
                offset = CGSize(
                    width: lastOffset.width + value.translation.width,
                    height: lastOffset.height + value.translation.height
                )
            }
            .onEnded { value in
                if zoomScale <= 1.0 {
                    let h = value.translation.width
                    if !viewModel.isStraightening && !viewModel.isCropping {
                        if h < -60 {
                            viewModel.navigateForward()
                        } else if h > 60 {
                            viewModel.navigateBackward()
                        }
                    }
                    withAnimation(.spring()) {
                        offset = .zero
                        lastOffset = .zero
                    }
                } else {
                    lastOffset = offset
                }
            }
    }

    private var canZoomIn: Bool {
        zoomScale < maxZoom
    }

    private var canZoomOut: Bool {
        zoomScale > minZoom
    }

    private var canResetZoom: Bool {
        zoomScale != 1.0 || offset != .zero || lastOffset != .zero
    }

    private func zoomIn() {
        setZoom(zoomScale * zoomStep)
    }

    private func zoomOut() {
        setZoom(zoomScale / zoomStep)
    }

    private func setZoom(_ scale: CGFloat) {
        let clamped = min(max(scale, minZoom), maxZoom)
        withAnimation(.easeInOut(duration: 0.18)) {
            zoomScale = clamped
            lastZoomScale = clamped
            if clamped <= 1.0 {
                offset = .zero
                lastOffset = .zero
            }
        }
    }

    private func resetZoom() {
        setZoom(1.0)
    }

    private func handleViewerZoomCommand(_ command: AppViewModel.ViewerZoomCommand?) {
        guard let command else { return }
        switch command {
        case .in:
            zoomIn()
        case .out:
            zoomOut()
        case .reset:
            resetZoom()
        }
    }

    private func handleDoubleTapImage() {
        if zoomScale > 1.0 {
            resetZoom()
        } else {
            withAnimation(.easeInOut(duration: 0.25)) { viewModel.toggleEditMode() }
        }
    }

    private func cropOverlay(photo: PhotoItem) -> some View {
        CropOverlayView(
            imageSize: viewModel.effectiveCropImageSize,
            cropRect: Bindable(viewModel).cropRect,
            aspectRatio: viewModel.cropAspectRatio
        )
    }

    private func straightenGridOverlay(photo: PhotoItem) -> some View {
        StraightenGridView(imageSize: viewModel.effectiveCropImageSize)
    }

    private var straightenBottomBar: some View {
        HStack(spacing: 12) {
            Button(action: { viewModel.cancelStraighten() }) {
                Text("Cancel")
                    .font(.system(size: 12, weight: .medium))
            }
            .buttonStyle(.plain)

            Slider(
                value: Binding(
                    get: { viewModel.editPayload.straightenAngle },
                    set: { newValue in
                        viewModel.editPayload.straightenAngle = newValue
                        viewModel.schedulePreviewRender()
                    }
                ),
                in: -45.0...45.0,
                step: 0.5,
                onEditingChanged: { editing in
                    if editing { viewModel.pushUndoSnapshot() }
                }
            )

            Text(String(format: "%.1f°", viewModel.editPayload.straightenAngle))
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 48, alignment: .trailing)

            Button(action: { viewModel.applyStraighten() }) {
                Text("Done")
                    .font(.system(size: 12, weight: .semibold))
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
    }

}

struct DotPickerView: View {
    let dotColor: Int
    let onSelect: (Int?) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        HStack(spacing: 8) {
            ForEach(DotColor.all) { dot in
                let active = (DotColor.bitMask(for: dot.rawValue) & dotColor) != 0
                Button {
                    onSelect(dot.rawValue)
                    dismiss()
                } label: {
                    Circle().fill(dot.color)
                        .frame(width: 24, height: 24)
                        .overlay(
                            Circle().stroke(active ? Color.white : Color.secondary.opacity(0.3), lineWidth: active ? 2 : 1)
                        )
                }
                .buttonStyle(.plain)
                .help(dot.name)
            }
            Divider().frame(height: 24)
            Button {
                onSelect(nil)
                dismiss()
            } label: {
                Image(systemName: "circle")
                    .font(.system(size: 20))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Clear All")
        }
        .padding(12)
    }
}
