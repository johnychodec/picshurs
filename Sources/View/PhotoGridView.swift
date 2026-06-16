import SwiftUI

struct PhotoGridView: View {
    @Environment(AppViewModel.self) private var viewModel
    @Environment(AppSettings.self) private var settings
    let onSelect: (PhotoItem) -> Void

    @State private var lastSelectedPhoto: PhotoItem?
    private let spacing: CGFloat = 3
    private let statusBarHeight: CGFloat = 28

    var body: some View {
        Group {
            if viewModel.isLoading {
                ProgressView("Scanning images...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if viewModel.filteredPhotos.isEmpty {
                emptyView
            } else {
                photoGrid
            }
        }
        .onChange(of: viewModel.displayMode) { _, _ in
            viewModel.temporarilySelectedPhotos = []
            viewModel.selectedPhoto = nil
            lastSelectedPhoto = nil
        }
        .onChange(of: viewModel.photos.count) { _, _ in
            lastSelectedPhoto = nil
        }
    }

    private var photoGrid: some View {
        VStack(spacing: 0) {
            gridScrollView
            statusBar
        }
    }

    private var gridScrollView: some View {
        let cellSize = CGFloat(viewModel.thumbnailSize)
        let columns = [GridItem(.adaptive(minimum: cellSize, maximum: cellSize * 2), spacing: spacing)]

        return ScrollViewReader { proxy in
            ScrollView {
                switch viewModel.displayMode {
                case .library:
                    libraryGrid(cellSize: cellSize, columns: columns)

                case .dot:
                    flatGridWithMarquee(photos: viewModel.filteredPhotos, cellSize: cellSize, columns: columns)

                case .tray:
                    TrayReorderGrid(photos: viewModel.trayPhotoOrder, cellSize: cellSize, columns: columns, spacing: spacing) { photo in
                        trayGridCell(photo: photo, size: cellSize)
                    }

                case .folder:
                    if viewModel.sortOrder == .date {
                        sectionGrid(cellSize: cellSize, columns: columns)
                    } else {
                        flatGridWithMarquee(photos: viewModel.filteredPhotos, cellSize: cellSize, columns: columns)
                    }

                case .year:
                    if viewModel.sortOrder == .date {
                        sectionGrid(cellSize: cellSize, columns: columns)
                    } else {
                        flatGridWithMarquee(photos: viewModel.filteredPhotos, cellSize: cellSize, columns: columns)
                    }

                case .person:
                    flatGridWithMarquee(photos: viewModel.filteredPhotos, cellSize: cellSize, columns: columns)

                // .map / .people render their own views in ContentView, not the
                // grid; these arms are unreachable fallbacks for exhaustiveness.
                case .map, .people:
                    flatGridWithMarquee(photos: viewModel.filteredPhotos, cellSize: cellSize, columns: columns)
                }
            }
            // Keep keyboard-moved selection visible (anchor nil = minimal scroll)
            .onChange(of: viewModel.selectedPhoto?.id) { _, id in
                guard let id, !viewModel.isViewingPhoto else { return }
                withAnimation(.easeInOut(duration: 0.15)) {
                    proxy.scrollTo(id)
                }
            }
            // Returning from the viewer recreates the grid at the top — jump
            // back to the photo the user was looking at
            .onAppear {
                guard let id = viewModel.selectedPhoto?.id else { return }
                DispatchQueue.main.async {
                    proxy.scrollTo(id, anchor: .center)
                }
            }
        }
        .contextMenu {
            Button("Select All") { viewModel.selectAll() }
            Divider()
            Button("Refresh") { viewModel.refreshCurrentView() }
            if case .folder = viewModel.displayMode, let url = viewModel.folderURL {
                Button("Show in Finder") {
                    NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: url.path)
                }
            }
        }
    }

    private func libraryGrid(cellSize: CGFloat, columns: [GridItem]) -> some View {
        LazyVStack(spacing: 24, pinnedViews: .sectionHeaders) {
            ForEach(viewModel.libraryYearGroups) { year in
                Section {
                    LazyVStack(spacing: 16, pinnedViews: .sectionHeaders) {
                        ForEach(year.folderGroups) { group in
                            Section {
                                MarqueeGrid(photos: group.photos, cellSize: cellSize, columns: columns, spacing: spacing) { photo in
                                    gridCell(photo: photo, size: cellSize)
                                }
                            } header: {
                                folderHeader(leaf: group.leafName, parent: group.parentPath ?? "", count: group.photos.count, path: group.path)
                            }
                        }
                    }
                } header: {
                    yearHeader(for: year.year, count: year.folderGroups.reduce(0) { $0 + $1.photos.count })
                }
            }
        }
        .padding(spacing)
    }

    private func sectionGrid(cellSize: CGFloat, columns: [GridItem]) -> some View {
        LazyVStack(spacing: 24, pinnedViews: .sectionHeaders) {
            ForEach(viewModel.groupedPhotos) { group in
                Section {
                    MarqueeGrid(photos: group.photos, cellSize: cellSize, columns: columns, spacing: spacing) { photo in
                        gridCell(photo: photo, size: cellSize)
                    }
                } header: {
                    dateHeader(for: group.date, count: group.photos.count)
                }
            }
        }
        .padding(spacing)
    }

    private func gridCell(photo: PhotoItem, size: CGFloat) -> some View {
        let cell = thumbnailCell(photo: photo, size: size)
            .onTapGesture(count: 2) { onSelect(photo) }
            .simultaneousGesture(
                TapGesture(count: 1)
                    .onEnded { _ in handleTap(photo: photo) }
            )
            .contextMenu { contextMenu(for: photo) }

        return Group {
            if viewModel.temporarilySelectedPhotos.contains(photo) {
                cell.onDrag { NSItemProvider(object: photo.url as NSURL) }
            } else {
                cell
            }
        }
        .id(photo.id)
    }

    // Tray-mode cell: no .onDrag file-drag wrapper — dragging a photo in the
    // tray grid means reorder (handled by TrayReorderGrid's gesture), and a
    // competing system drag session would swallow it.
    private func trayGridCell(photo: PhotoItem, size: CGFloat) -> some View {
        thumbnailCell(photo: photo, size: size)
            .onTapGesture(count: 2) { onSelect(photo) }
            .simultaneousGesture(
                TapGesture(count: 1)
                    .onEnded { _ in handleTap(photo: photo) }
            )
            .contextMenu { contextMenu(for: photo) }
            .id(photo.id)
    }

    private func flatGridWithMarquee(photos: [PhotoItem], cellSize: CGFloat, columns: [GridItem]) -> some View {
        MarqueeGrid(photos: photos, cellSize: cellSize, columns: columns, spacing: spacing) { photo in
            gridCell(photo: photo, size: cellSize)
        }
    }

    private func handleTap(photo: PhotoItem) {
        let flags = NSEvent.modifierFlags
        if flags.contains(.command) {
            viewModel.toggleSelection(photo)
            lastSelectedPhoto = photo
        } else if flags.contains(.shift) {
            if let last = lastSelectedPhoto {
                viewModel.selectRange(from: last, to: photo)
            } else {
                viewModel.selectSingle(photo)
            }
            lastSelectedPhoto = photo
        } else {
            viewModel.selectSingle(photo)
            lastSelectedPhoto = photo
        }
    }

    private func folderHeader(leaf: String, parent: String, count: Int, path: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Image(systemName: "folder.fill")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 1) {
                Text(leaf)
                    .font(.headline)
                if !parent.isEmpty {
                    Text(parent)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            Spacer()
            Text("\(count)")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            viewModel.openLibraryFolderByPath(path)
        }
        .padding(.horizontal, spacing + 4)
        .padding(.vertical, 8)
        .background(.regularMaterial)
    }

    private func yearHeader(for year: Int, count: Int) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(verbatim: String(year))
                .font(.largeTitle.weight(.bold))
            Spacer()
            Text("\(count) \(count == 1 ? "photo" : "photos")")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, spacing + 4)
        .padding(.vertical, 10)
        .background(.regularMaterial)
    }

    private func dateHeader(for date: Date, count: Int) -> some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 1) {
                Text(date, format: .dateTime.month(.wide).day())
                    .font(.title3.weight(.semibold))
                Text(date, format: .dateTime.weekday(.wide))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text("\(count) \(count == 1 ? "photo" : "photos")")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, spacing + 4)
        .padding(.vertical, 8)
        .background(.regularMaterial)
    }

    private var statusBar: some View {
        HStack(spacing: 8) {
            Button(action: { viewModel.sortOrder = viewModel.sortOrder.next() }) {
                HStack(spacing: 4) {
                    Text("\(viewModel.filteredPhotos.count) \(viewModel.filteredPhotos.count == 1 ? "item" : "items")")
                        .font(.caption)
                    Text("·")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(viewModel.sortOrder.rawValue)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .padding(.leading, 8)

            if !viewModel.photos.isEmpty {
                Text(viewModel.totalDiskUsage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .frame(height: statusBarHeight)
        .background(.bar)
    }

    private func contextMenu(for photo: PhotoItem) -> some View {
        let isTemp = viewModel.temporarilySelectedPhotos.contains(photo)
        let isPinned = viewModel.isPinned(photo)
        let multiSelected = viewModel.temporarilySelectedPhotos.count > 1 && isTemp

        return Group {
            if multiSelected {
                ShareLink("Share \(viewModel.temporarilySelectedPhotos.count) selected",
                          items: viewModel.temporarilySelectedPhotos.map(\.url))
            } else {
                ShareLink("Share", item: photo.url)
            }

            if multiSelected {
                Divider()
                Button("Pin \(viewModel.temporarilySelectedPhotos.count) selected to tray") {
                    for p in viewModel.temporarilySelectedPhotos {
                        viewModel.pinPhoto(p)
                    }
                }
                Button("Unpin \(viewModel.temporarilySelectedPhotos.count) selected from tray") {
                    for p in viewModel.temporarilySelectedPhotos {
                        viewModel.unpinPhoto(p)
                    }
                }
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

    private func thumbnailCell(photo: PhotoItem, size: CGFloat) -> some View {
        ThumbnailCellView(photo: photo, size: size)
    }

    @ViewBuilder
    private var emptyView: some View {
        if !viewModel.searchText.isEmpty {
            contextualEmptyState(
                icon: "magnifyingglass",
                title: "No results for “\(viewModel.searchText)”",
                subtitle: "Try a different search term or clear the search."
            )
        } else if case let .dot(color) = viewModel.displayMode {
            contextualEmptyState(
                icon: "circle.fill",
                title: "No photos tagged \(DotColor.name(for: color) ?? "this color")",
                subtitle: "Tag photos with ⌥\(color) or via the right-click menu."
            )
        } else if case let .year(year) = viewModel.displayMode {
            contextualEmptyState(
                icon: "calendar",
                title: "No photos from \(String(year))",
                subtitle: "Try another year in the sidebar."
            )
        } else if viewModel.displayMode == .tray {
            contextualEmptyState(
                icon: "pin",
                title: "Tray is empty",
                subtitle: "Pin photos with P or right-click and choose Pin to Tray."
            )
        } else if !viewModel.libraryFolders.isEmpty {
            contextualEmptyState(
                icon: "photo.on.rectangle.angled",
                title: "No photos here",
                subtitle: "This folder has no photos, or they were filtered out."
            )
        } else {
            WelcomeView()
        }
    }

    private func contextualEmptyState(icon: String, title: String, subtitle: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 40))
                .foregroundStyle(.tertiary)
            Text(title)
                .font(.title3.weight(.semibold))
            Text(subtitle)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// Reusable LazyVGrid wrapper with marquee drag-selection. Holds its own
// drag state so each section in the library/date views gets an independent
// marquee — cell frames stay computable (regular grid) per section, which is
// what lets the library view have drag selection without per-cell GeometryReaders.
private struct MarqueeGrid<Cell: View>: View {
    @Environment(AppViewModel.self) private var viewModel
    let photos: [PhotoItem]
    let cellSize: CGFloat
    let columns: [GridItem]
    let spacing: CGFloat
    @ViewBuilder let cell: (PhotoItem) -> Cell

    @State private var isDraggingMarquee = false
    @State private var isDraggingFiles = false
    @State private var marqueeStart: CGPoint = .zero
    @State private var marqueeEnd: CGPoint = .zero
    @State private var isCommandDrag = false
    @State private var marqueeBaseSelection: Set<PhotoItem> = []
    @State private var containerWidth: CGFloat = 0

    var body: some View {
        ZStack {
            LazyVGrid(columns: columns, spacing: spacing) {
                ForEach(photos) { photo in
                    cell(photo)
                }
            }
            .padding(spacing)
            .background(
                GeometryReader { geo in
                    Color.clear
                        .onAppear {
                            containerWidth = geo.size.width
                            viewModel.gridColumnCount = columnCount
                        }
                        .onChange(of: geo.size.width) { _, newWidth in
                            containerWidth = newWidth
                            viewModel.gridColumnCount = columnCount
                        }
                }
            )

            Rectangle()
                .fill(Color.accentColor.opacity(0.15))
                .stroke(Color.accentColor.opacity(0.8), lineWidth: 1)
                .frame(
                    width: max(0, abs(marqueeEnd.x - marqueeStart.x)),
                    height: max(0, abs(marqueeEnd.y - marqueeStart.y))
                )
                .position(
                    x: marqueeStart.x + (marqueeEnd.x - marqueeStart.x) / 2,
                    y: marqueeStart.y + (marqueeEnd.y - marqueeStart.y) / 2
                )
                .opacity(isDraggingMarquee ? 1 : 0)
                .allowsHitTesting(false)
        }
        .simultaneousGesture(
            // 8pt threshold — at 4pt a click with slight hand movement became a
            // tiny marquee that replaced the tap's selection.
            DragGesture(minimumDistance: 8)
                .onChanged { value in
                    if !isDraggingMarquee && !isDraggingFiles {
                        let isCmd = NSEvent.modifierFlags.contains(.command)
                        let hitPhoto = hitTestPhoto(at: value.startLocation)
                        let hitSelected = hitPhoto.map { viewModel.temporarilySelectedPhotos.contains($0) } ?? false
                        if hitSelected && !isCmd {
                            isDraggingFiles = true
                            return
                        }
                        isDraggingMarquee = true
                        marqueeStart = value.startLocation
                        isCommandDrag = isCmd
                        // Plain drag in one section replaces the whole selection,
                        // ⌘-drag toggles against it — same semantics across sections.
                        if isCommandDrag {
                            marqueeBaseSelection = viewModel.temporarilySelectedPhotos
                        } else {
                            marqueeBaseSelection = []
                        }
                    }
                    guard !isDraggingFiles else { return }
                    marqueeEnd = value.location
                    updateMarqueeSelection()
                }
                .onEnded { _ in
                    // Deferred from per-tick updates — O(selection) work that
                    // only needs to happen once the marquee settles.
                    if isDraggingMarquee {
                        for photo in viewModel.temporarilySelectedPhotos {
                            viewModel.addToTrayOrderIfNeeded(photo)
                        }
                    }
                    isDraggingMarquee = false
                    isDraggingFiles = false
                    marqueeStart = .zero
                    marqueeEnd = .zero
                }
        )
    }

    private var columnCount: Int {
        guard containerWidth > 0, cellSize > 0 else { return 1 }
        let available = containerWidth - spacing * 2
        return max(1, Int((available + spacing) / (cellSize + spacing)))
    }

    // The grid uses .adaptive(minimum: cellSize, maximum: cellSize*2), so
    // LazyVGrid STRETCHES columns to fill the row. The frame math must use the
    // stretched column width — assuming cellSize-wide columns drifts further
    // off the visible cells with every column to the right.
    private var actualColumnWidth: CGFloat {
        let cols = CGFloat(columnCount)
        let available = containerWidth - spacing * 2 - (cols - 1) * spacing
        return min(max(cellSize, available / cols), cellSize * 2)
    }

    private func cellFrame(index: Int) -> CGRect {
        let cols = columnCount
        let colWidth = actualColumnWidth
        let row = index / cols
        let col = index % cols
        // Cell content is centered within its stretched column
        let columnX = spacing + CGFloat(col) * (colWidth + spacing)
        let x = columnX + (colWidth - cellSize) / 2
        let y = spacing + CGFloat(row) * (cellSize + spacing)
        return CGRect(x: x, y: y, width: cellSize, height: cellSize)
    }

    private func hitTestPhoto(at point: CGPoint) -> PhotoItem? {
        let cols = columnCount
        guard cellSize > 0, cols > 0 else { return nil }
        let colWidth = actualColumnWidth
        let col = Int((point.x - spacing) / (colWidth + spacing))
        let row = Int((point.y - spacing) / (cellSize + spacing))
        guard col >= 0, col < cols, row >= 0 else { return nil }
        let index = row * cols + col
        guard index >= 0, index < photos.count else { return nil }
        return cellFrame(index: index).contains(point) ? photos[index] : nil
    }

    private func updateMarqueeSelection() {
        let rect = CGRect(
            x: min(marqueeStart.x, marqueeEnd.x),
            y: min(marqueeStart.y, marqueeEnd.y),
            width: abs(marqueeEnd.x - marqueeStart.x),
            height: abs(marqueeEnd.y - marqueeStart.y)
        )

        let cols = columnCount
        guard cols > 0, cellSize > 0 else { return }
        let colWidth = actualColumnWidth

        let startRow = max(0, Int((rect.minY - spacing) / (cellSize + spacing)))
        let endRow = min(photos.count / cols, Int((rect.maxY - spacing) / (cellSize + spacing)))
        let startCol = max(0, Int((rect.minX - spacing) / (colWidth + spacing)))
        let endCol = min(cols - 1, Int((rect.maxX - spacing) / (colWidth + spacing)))
        guard startRow <= endRow, startCol <= endCol else { return }

        var newSelection = isCommandDrag ? marqueeBaseSelection : Set<PhotoItem>()
        for row in startRow...endRow {
            for col in startCol...endCol {
                let index = row * cols + col
                guard index < photos.count else { continue }
                guard cellFrame(index: index).intersects(rect) else { continue }
                let photo = photos[index]
                if isCommandDrag {
                    if marqueeBaseSelection.contains(photo) {
                        newSelection.remove(photo)
                    } else {
                        newSelection.insert(photo)
                    }
                } else {
                    newSelection.insert(photo)
                }
            }
        }

        viewModel.temporarilySelectedPhotos = newSelection
        viewModel.selectedPhoto = newSelection.first
    }
}

// Tray grid with drag-to-reorder (Photos.app album semantics):
//   drag a photo            → reorder it (whole selection if it's selected)
//   drag from empty space   → marquee selection
//   ⌘-drag anywhere         → marquee with toggle (consistent with other views)
// Reordering is handled with a plain DragGesture instead of .draggable so the
// ⌘ modifier can still route to marquee, and so a block of selected photos
// moves together via moveTrayItems().
private struct TrayReorderGrid<Cell: View>: View {
    @Environment(AppViewModel.self) private var viewModel
    let photos: [PhotoItem]
    let cellSize: CGFloat
    let columns: [GridItem]
    let spacing: CGFloat
    @ViewBuilder let cell: (PhotoItem) -> Cell

    private enum DragMode { case none, marquee, reorder }

    @State private var dragMode: DragMode = .none
    @State private var draggedPhotos: Set<PhotoItem> = []
    @State private var dropZone: Int?
    @State private var marqueeStart: CGPoint = .zero
    @State private var marqueeEnd: CGPoint = .zero
    @State private var isCommandDrag = false
    @State private var marqueeBaseSelection: Set<PhotoItem> = []
    @State private var containerWidth: CGFloat = 0

    var body: some View {
        ZStack {
            LazyVGrid(columns: columns, spacing: spacing) {
                ForEach(photos) { photo in
                    cell(photo)
                        .opacity(dragMode == .reorder && draggedPhotos.contains(photo) ? 0.4 : 1.0)
                }
            }
            .padding(spacing)
            .background(
                GeometryReader { geo in
                    Color.clear
                        .onAppear {
                            containerWidth = geo.size.width
                            viewModel.gridColumnCount = columnCount
                        }
                        .onChange(of: geo.size.width) { _, newWidth in
                            containerWidth = newWidth
                            viewModel.gridColumnCount = columnCount
                        }
                }
            )

            // Marquee rectangle
            Rectangle()
                .fill(Color.accentColor.opacity(0.15))
                .stroke(Color.accentColor.opacity(0.8), lineWidth: 1)
                .frame(
                    width: max(0, abs(marqueeEnd.x - marqueeStart.x)),
                    height: max(0, abs(marqueeEnd.y - marqueeStart.y))
                )
                .position(
                    x: marqueeStart.x + (marqueeEnd.x - marqueeStart.x) / 2,
                    y: marqueeStart.y + (marqueeEnd.y - marqueeStart.y) / 2
                )
                .opacity(dragMode == .marquee ? 1 : 0)
                .allowsHitTesting(false)

            // Insertion indicator
            if dragMode == .reorder, let zone = dropZone {
                let frame = insertionIndicatorFrame(zone: zone)
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(Color.accentColor)
                    .frame(width: 3, height: frame.height)
                    .position(x: frame.midX, y: frame.midY)
                    .allowsHitTesting(false)
            }
        }
        .simultaneousGesture(
            DragGesture(minimumDistance: 8)
                .onChanged { value in
                    if dragMode == .none {
                        let isCmd = NSEvent.modifierFlags.contains(.command)
                        let hitPhoto = hitTestPhoto(at: value.startLocation)
                        if let photo = hitPhoto, !isCmd {
                            dragMode = .reorder
                            draggedPhotos = viewModel.temporarilySelectedPhotos.contains(photo)
                                ? viewModel.temporarilySelectedPhotos
                                : [photo]
                        } else {
                            dragMode = .marquee
                            marqueeStart = value.startLocation
                            isCommandDrag = isCmd
                            marqueeBaseSelection = isCmd ? viewModel.temporarilySelectedPhotos : []
                        }
                    }
                    switch dragMode {
                    case .reorder:
                        dropZone = dropZoneIndex(at: value.location)
                    case .marquee:
                        marqueeEnd = value.location
                        updateMarqueeSelection()
                    case .none:
                        break
                    }
                }
                .onEnded { value in
                    switch dragMode {
                    case .reorder:
                        if let zone = dropZoneIndex(at: value.location) {
                            viewModel.moveTrayItems(draggedPhotos, toDropZone: zone)
                        }
                    case .marquee:
                        for photo in viewModel.temporarilySelectedPhotos {
                            viewModel.addToTrayOrderIfNeeded(photo)
                        }
                    case .none:
                        break
                    }
                    dragMode = .none
                    draggedPhotos = []
                    dropZone = nil
                    marqueeStart = .zero
                    marqueeEnd = .zero
                }
        )
    }

    // MARK: Geometry (mirrors MarqueeGrid)

    private var columnCount: Int {
        guard containerWidth > 0, cellSize > 0 else { return 1 }
        let available = containerWidth - spacing * 2
        return max(1, Int((available + spacing) / (cellSize + spacing)))
    }

    private var actualColumnWidth: CGFloat {
        let cols = CGFloat(columnCount)
        let available = containerWidth - spacing * 2 - (cols - 1) * spacing
        return min(max(cellSize, available / cols), cellSize * 2)
    }

    private func cellFrame(index: Int) -> CGRect {
        let cols = columnCount
        let colWidth = actualColumnWidth
        let row = index / cols
        let col = index % cols
        let columnX = spacing + CGFloat(col) * (colWidth + spacing)
        let x = columnX + (colWidth - cellSize) / 2
        let y = spacing + CGFloat(row) * (cellSize + spacing)
        return CGRect(x: x, y: y, width: cellSize, height: cellSize)
    }

    private func hitTestPhoto(at point: CGPoint) -> PhotoItem? {
        let cols = columnCount
        guard cellSize > 0, cols > 0 else { return nil }
        let colWidth = actualColumnWidth
        let col = Int((point.x - spacing) / (colWidth + spacing))
        let row = Int((point.y - spacing) / (cellSize + spacing))
        guard col >= 0, col < cols, row >= 0 else { return nil }
        let index = row * cols + col
        guard index >= 0, index < photos.count else { return nil }
        return cellFrame(index: index).contains(point) ? photos[index] : nil
    }

    /// Insertion index (0...count) for a drop at the given point — snaps to
    /// the nearest gap between cells.
    private func dropZoneIndex(at point: CGPoint) -> Int? {
        let cols = columnCount
        guard cols > 0, cellSize > 0, !photos.isEmpty else { return nil }
        let colWidth = actualColumnWidth

        let lastRow = (photos.count - 1) / cols
        let row = min(max(0, Int((point.y - spacing) / (cellSize + spacing))), lastRow)
        // Snap x to the nearest column gap (0...cols)
        let gapCol = min(max(0, Int((point.x - spacing + (colWidth + spacing) / 2) / (colWidth + spacing))), cols)
        return min(row * cols + gapCol, photos.count)
    }

    private func insertionIndicatorFrame(zone: Int) -> CGRect {
        let cols = columnCount
        let colWidth = actualColumnWidth
        let clamped = min(max(0, zone), photos.count)
        let row = min(clamped / cols, max(0, (photos.count - 1) / cols))
        let col = clamped - row * cols
        let x = spacing + CGFloat(col) * (colWidth + spacing) - spacing / 2
        let y = spacing + CGFloat(row) * (cellSize + spacing)
        return CGRect(x: x - 1.5, y: y, width: 3, height: cellSize)
    }

    private func updateMarqueeSelection() {
        let rect = CGRect(
            x: min(marqueeStart.x, marqueeEnd.x),
            y: min(marqueeStart.y, marqueeEnd.y),
            width: abs(marqueeEnd.x - marqueeStart.x),
            height: abs(marqueeEnd.y - marqueeStart.y)
        )

        let cols = columnCount
        guard cols > 0, cellSize > 0 else { return }
        let colWidth = actualColumnWidth

        let startRow = max(0, Int((rect.minY - spacing) / (cellSize + spacing)))
        let endRow = min(photos.count / cols, Int((rect.maxY - spacing) / (cellSize + spacing)))
        let startCol = max(0, Int((rect.minX - spacing) / (colWidth + spacing)))
        let endCol = min(cols - 1, Int((rect.maxX - spacing) / (colWidth + spacing)))
        guard startRow <= endRow, startCol <= endCol else { return }

        var newSelection = isCommandDrag ? marqueeBaseSelection : Set<PhotoItem>()
        for row in startRow...endRow {
            for col in startCol...endCol {
                let index = row * cols + col
                guard index < photos.count else { continue }
                guard cellFrame(index: index).intersects(rect) else { continue }
                let photo = photos[index]
                if isCommandDrag {
                    if marqueeBaseSelection.contains(photo) {
                        newSelection.remove(photo)
                    } else {
                        newSelection.insert(photo)
                    }
                } else {
                    newSelection.insert(photo)
                }
            }
        }

        viewModel.temporarilySelectedPhotos = newSelection
        viewModel.selectedPhoto = newSelection.first
    }
}

// Standalone view so the hover @State is per-cell — a shared hover property on
// PhotoGridView would invalidate the entire grid body on every mouse move.
private struct ThumbnailCellView: View {
    @Environment(AppViewModel.self) private var viewModel
    @Environment(AppSettings.self) private var settings
    let photo: PhotoItem
    let size: CGFloat

    @State private var isHovered = false

    var body: some View {
        let isFocus = viewModel.selectedPhoto == photo
        let isSelected = viewModel.temporarilySelectedPhotos.contains(photo)
        let isPinned = viewModel.isPinned(photo)
        let useAspect = settings.preserveAspectRatio

        // Aspect mode letterboxes inside a uniform square — variable-height
        // cells made a low-res portrait look bigger than a 4K landscape.
        ZStack(alignment: .bottom) {
            // Reflect the sidecar rotation edit — square cells make 90° steps
            // map exactly onto the same footprint, so this is free.
            ThumbnailImage(url: photo.url, modificationDate: photo.modificationDate, fill: !useAspect)
                .frame(width: size, height: size)
                .clipped()
                .rotationEffect(.degrees(Double(viewModel.editRotation(for: photo.url))))

            if isHovered && settings.showFilenameLabels {
                Text(photo.filename)
                    .font(.caption2)
                    .lineLimit(1)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .frame(maxWidth: .infinity)
                    .background(.ultraThinMaterial)
                    .transition(.opacity)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        // Full square is clickable in both thumbnail modes — without this,
        // aspect mode's transparent letterbox bands don't hit-test
        .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        // Selection wash + inset ring
        .overlay {
            if isFocus || isSelected {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.accentColor.opacity(0.12))
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color.accentColor.opacity(isFocus ? 0.7 : 0.4), lineWidth: 1.5)
            }
        }
        // Top-left: selection check badge
        .overlay(alignment: .topLeading) {
            if isSelected || isFocus {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(.white, Color.accentColor)
                    .shadow(color: .black.opacity(0.3), radius: 2, y: 1)
                    .padding(5)
            } else if viewModel.hasEdits(for: photo.url) {
                Image(systemName: "pencil.circle.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(.orange)
                    .shadow(color: .black.opacity(0.4), radius: 1, y: 1)
                    .padding(5)
            }
        }
        // Top-right: pinned badge + dot colors
        .overlay(alignment: .topTrailing) {
            HStack(spacing: 3) {
                let activeDots = DotColor.activeColors(from: photo.dotColor)
                ForEach(activeDots) { dot in
                    Circle().fill(dot.color)
                        .frame(width: 8, height: 8)
                        .shadow(color: .black.opacity(0.2), radius: 1)
                }
                if isPinned {
                    Image(systemName: "pin.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(.white, .green)
                        .shadow(color: .black.opacity(0.3), radius: 2, y: 1)
                }
            }
            .padding(5)
        }
        // Bottom-left: star
        .overlay(alignment: .bottomLeading) {
            if photo.isStarred {
                Image(systemName: "star.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(.yellow)
                    .shadow(color: .black.opacity(0.4), radius: 1, y: 1)
                    .padding(5)
            }
        }
        // Bottom-right: RAW badge
        .overlay(alignment: .bottomTrailing) {
            if photo.isRaw {
                Text("RAW")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                    .background(.black.opacity(0.55), in: Capsule())
                    .padding(5)
            }
        }
        .scaleEffect(isHovered && !isSelected && !isFocus ? 1.03 : 1.0)
        .shadow(color: .black.opacity(isHovered ? 0.15 : 0), radius: 4, y: 2)
        .animation(.spring(response: 0.25, dampingFraction: 0.8), value: isHovered)
        .animation(.easeInOut(duration: 0.15), value: isSelected)
        .animation(.easeInOut(duration: 0.15), value: isFocus)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

