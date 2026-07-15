import AppKit
import QuickLookThumbnailing
import GRDB
import CoreImage
import CoreGraphics

@Observable
final class AppViewModel {
    enum DisplayMode: Equatable {
        static func == (lhs: DisplayMode, rhs: DisplayMode) -> Bool {
            switch (lhs, rhs) {
            case (.library, .library): return true
            case let (.dot(l), .dot(r)): return l == r
            case (.tray, .tray): return true
            case let (.folder(l), .folder(r)): return l.path == r.path
            case let (.year(l), .year(r)): return l == r
            case (.map, .map): return true
            case (.people, .people): return true
            case let (.person(l), .person(r)): return l == r
            default: return false
            }
        }

        case library
        case dot(Int)
        case tray
        case folder(LibraryFolder)
        case year(Int)
        case map
        case people
        case person(String)

        var dotColor: Int? {
            if case let .dot(n) = self { return n }
            return nil
        }
    }

    var folderURL: URL?
    var folderName: String?
    var photos: [PhotoItem] = []
    var selectedPhoto: PhotoItem?
    var temporarilySelectedPhotos: Set<PhotoItem> = []
    var pinnedPhotos: Set<PhotoItem> = []
    var trayPhotoOrder: [PhotoItem] = []
    var displayMode: DisplayMode = .library

    // Browser-style back/forward. `backStack` holds modes we can return to (most
    // recent on top); `forwardStack` holds modes we backed out of.
    private var backStack: [DisplayMode] = []
    private var forwardStack: [DisplayMode] = []
    var canGoBack: Bool { !backStack.isEmpty }
    var canGoForward: Bool { !forwardStack.isEmpty }

    var isLoading = false
    var sortOrder: SortOrder {
        get { _sortOrder }
        set {
            guard newValue != _sortOrder else { return }
            _sortOrder = newValue
            // Each field reads most naturally in its own direction; direction
            // resets when the field changes so "Date" always leads newest-first.
            _sortAscending = newValue.defaultAscending
            rebuildFilteredPhotos()
        }
    }
    private var _sortOrder: SortOrder = .name

    var sortAscending: Bool {
        get { _sortAscending }
        set {
            guard newValue != _sortAscending else { return }
            _sortAscending = newValue
            rebuildFilteredPhotos()
        }
    }
    private var _sortAscending = true
    var thumbnailSize: Double = 160
    /// Map zoom driven by the thumbnail slider while in map mode. Normalized
    /// 0 (whole world) … 1 (street level); `MapView` maps it to a region span.
    var mapZoom: Double = 0.45
    /// Bumped by the ratio button in map mode to re-frame all pins (`.automatic`).
    var mapResetToken: Int = 0
    var libraryFolders: [LibraryFolder] = []
    var isViewingPhoto = false
    enum ViewerZoomCommand: Equatable {
        case `in`, out, reset
    }
    var viewerZoomCommandID: Int = 0
    var viewerZoomCommand: ViewerZoomCommand?
    var searchText: String {
        get { _searchText }
        set {
            guard newValue != _searchText else { return }
            _searchText = newValue
            rebuildFilteredPhotos()
        }
    }
    private var _searchText = ""
    var lastError: String?
    var successMessage: String?
    private var successDismissTask: Task<Void, Never>?

    func sendViewerZoomCommand(_ command: ViewerZoomCommand) {
        viewerZoomCommand = command
        viewerZoomCommandID += 1
    }

    func showSuccess(_ message: String) {
        successMessage = message
        successDismissTask?.cancel()
        successDismissTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            guard !Task.isCancelled else { return }
            successMessage = nil
        }
    }

    let quickLookController = QuickLookController()
    let settings: AppSettings
    private var fileWatcher: FileSystemWatcher?
    private var watcherDebounceTask: Task<Void, Never>?
    private var externalVideoReturnURL: URL?
    private var suppressGalleryCloseUntil: Date?

    private let libraryKey = "PicshursLibraryFolders"
    private let excludedLeafPathsKey = "PicshursExcludedLeafPaths"
    var excludedLeafPaths: Set<String> = []

    struct SidebarGroup: Identifiable {
        let title: String
        let folders: [LibraryFolder]
        let rootPath: String?
        let photoCount: Int
        var id: String { (rootPath ?? "") + title }
    }

    enum SidebarGrouping: String, CaseIterable {
        case byYear = "Year"
        case bySource = "Source"
    }

    var sidebarGroups: [SidebarGroup] = []

    var usedDotColors: Set<Int> = []

    /// Whether any photo in the library has GPS coordinates — gates the sidebar
    /// "Map" row. Recomputed from the DB in `refreshSidebarGroups()`.
    var hasGeotaggedPhotos = false

    var sidebarGrouping: SidebarGrouping {
        get { _sidebarGrouping }
        set {
            guard newValue != _sidebarGrouping else { return }
            _sidebarGrouping = newValue
            UserDefaults.standard.set(newValue.rawValue, forKey: "PicshursSidebarGrouping")
            refreshSidebarGroups()
        }
    }
    private var _sidebarGrouping: SidebarGrouping = .byYear

    enum SortOrder: String, CaseIterable {
        case name = "Name"
        case date = "Date"
        case size = "Size"

        /// Direction used when the field is first selected: names read A→Z,
        /// dates and sizes lead with newest/largest.
        var defaultAscending: Bool {
            switch self {
            case .name: return true
            case .date, .size: return false
            }
        }

        func comparator(ascending: Bool) -> (PhotoItem, PhotoItem) -> Bool {
            { a, b in
                // Swap operands instead of negating the result so equal
                // elements keep returning false (strict weak ordering).
                let (x, y) = ascending ? (a, b) : (b, a)
                switch self {
                case .name: return x.filename.localizedStandardCompare(y.filename) == .orderedAscending
                case .date: return x.displayDate < y.displayDate
                case .size: return x.fileSize < y.fileSize
                }
            }
        }

        func next() -> SortOrder {
            switch self {
            case .name: return .date
            case .date: return .size
            case .size: return .name
            }
        }
    }

    var filteredPhotos: [PhotoItem] { _filteredPhotos }
    private var _filteredPhotos: [PhotoItem] = []
    var visiblePhotos: [PhotoItem] { _visiblePhotos }
    private var _visiblePhotos: [PhotoItem] = []
    private(set) var groupedPhotos: [DateGroup] = []
    private(set) var folderGroups: [FolderGroup] = []
    private(set) var libraryYearGroups: [YearGroup] = []
    private var photoIndexByPath: [String: Int] = [:]
    private var visiblePhotoIndexByPath: [String: Int] = [:]

    func photoIndex(for path: String) -> Int? {
        photoIndexByPath[path]
    }

    private func rebuildFilteredPhotos() {
        var result = photos.sorted(by: _sortOrder.comparator(ascending: _sortAscending))
        if !settings.showVideos {
            result = result.filter { !$0.isVideo }
        }
        if !_searchText.isEmpty {
            let query = _searchText.lowercased()
            result = result.filter { photo in
                photo.filename.lowercased().contains(query)
                || photo.url.deletingLastPathComponent().lastPathComponent.lowercased().contains(query)
                || photo.cameraModel?.lowercased().contains(query) == true
                || photo.lensModel?.lowercased().contains(query) == true
                // `ocrTextByPath` values are pre-lowercased; `query` already is too.
                || ocrTextByPath[photo.url.path]?.contains(query) == true
            }
        }
        _filteredPhotos = result

        var indexMap = [String: Int]()
        indexMap.reserveCapacity(result.count)
        for (i, photo) in result.enumerated() {
            indexMap[photo.url.path] = i
        }
        photoIndexByPath = indexMap

        rebuildTotalDiskUsage(for: result)
        rebuildGroupedViews()
        rebuildVisiblePhotos()
    }

    private func rebuildGroupedViews() {
        let filtered = _filteredPhotos
        let sort = _sortOrder.comparator(ascending: _sortAscending)

        let dateDict = Dictionary(grouping: filtered) { photo in
            Calendar.current.startOfDay(for: photo.displayDate)
        }
        groupedPhotos = dateDict.map { DateGroup(date: $0.key, photos: $0.value.sorted(by: sort)) }
            .sorted { $0.date > $1.date }

        let folderDict = Dictionary(grouping: filtered) { $0.folderPath }
        folderGroups = folderDict.map { pair in
            let (leaf, parent) = self.folderNameComponents(for: pair.key)
            return FolderGroup(leafName: leaf, parentPath: parent, photos: pair.value.sorted(by: sort), path: pair.key)
        }.sorted { a, b in
            let aMax = a.photos.map(\.displayDate).max() ?? .distantPast
            let bMax = b.photos.map(\.displayDate).max() ?? .distantPast
            return aMax > bMax
        }

        // Folder-centric years: every folder appears whole under exactly one
        // year — its MAJORITY year (ties go to the newer one). A folder of
        // 2026 photos with one 2023 stray is a "2026 folder"; splitting it
        // across year sections contradicted the sidebar and confused users.
        let calendar = Calendar.current
        let folderBuckets = Dictionary(grouping: filtered) { $0.folderPath }
        var foldersByYear: [Int: [FolderGroup]] = [:]
        for (path, photosInFolder) in folderBuckets {
            var counts: [Int: Int] = [:]
            for photo in photosInFolder {
                counts[calendar.component(.year, from: photo.displayDate), default: 0] += 1
            }
            guard let year = Self.majorityYear(from: counts) else { continue }
            let (leaf, parent) = folderNameComponents(for: path)
            let group = FolderGroup(leafName: leaf, parentPath: parent, photos: photosInFolder.sorted(by: sort), path: path)
            foldersByYear[year, default: []].append(group)
        }
        libraryYearGroups = foldersByYear.map { year, folders in
            YearGroup(year: year, folderGroups: folders.sorted {
                $0.leafName.localizedStandardCompare($1.leafName) == .orderedAscending
            })
        }.sorted { $0.year > $1.year }
    }

    private func navigationPhotos() -> [PhotoItem] {
        switch displayMode {
        case .library:
            return libraryYearGroups.flatMap { year in
                year.folderGroups.flatMap(\.photos)
            }
        case .folder, .year:
            return _sortOrder == .date ? groupedPhotos.flatMap(\.photos) : filteredPhotos
        case .tray:
            return visibleTrayPhotoOrder
        case .dot, .person, .map, .people:
            return filteredPhotos
        }
    }

    private func rebuildVisiblePhotos() {
        let result = navigationPhotos()
        _visiblePhotos = result

        var indexMap = [String: Int]()
        indexMap.reserveCapacity(result.count)
        for (i, photo) in result.enumerated() {
            indexMap[photo.url.path] = i
        }
        visiblePhotoIndexByPath = indexMap
    }

    func visiblePhotoIndex(for path: String) -> Int? {
        visiblePhotoIndexByPath[path]
    }

    private struct SelectionSnapshot {
        let selectedPath: String?
        let selectedIndex: Int?
        let temporarySelectionPaths: Set<String>
        let wasViewingPhoto: Bool
    }

    private func makeSelectionSnapshot() -> SelectionSnapshot? {
        guard let selected = selectedPhoto else { return nil }
        return SelectionSnapshot(
            selectedPath: selected.url.path,
            selectedIndex: visiblePhotoIndex(for: selected.url.path),
            temporarySelectionPaths: Set(temporarilySelectedPhotos.map(\.url.path)),
            wasViewingPhoto: isViewingPhoto
        )
    }

    private func restoreSelectionAfterReload(_ snapshot: SelectionSnapshot?) {
        guard let snapshot else { return }
        let current = visiblePhotos

        guard !current.isEmpty else {
            temporarilySelectedPhotos.removeAll()
            selectedPhoto = nil
            isViewingPhoto = false
            return
        }

        let survivingTemporary = Set(snapshot.temporarySelectionPaths.compactMap { path in
            current.first { $0.url.path == path }
        })

        if let selectedPath = snapshot.selectedPath,
           let refreshed = current.first(where: { $0.url.path == selectedPath }) {
            selectedPhoto = refreshed
            temporarilySelectedPhotos = survivingTemporary.isEmpty ? [refreshed] : survivingTemporary
            isViewingPhoto = snapshot.wasViewingPhoto
            return
        }

        let fallbackIndex = min(max(0, snapshot.selectedIndex ?? 0), current.count - 1)
        let fallback = current[fallbackIndex]
        selectedPhoto = fallback
        temporarilySelectedPhotos = survivingTemporary.isEmpty ? [fallback] : survivingTemporary
        isViewingPhoto = snapshot.wasViewingPhoto
    }

    struct DateGroup: Identifiable, Equatable {
        let date: Date
        let photos: [PhotoItem]
        var id: Date { date }

        static func == (lhs: DateGroup, rhs: DateGroup) -> Bool {
            lhs.date == rhs.date && lhs.photos.count == rhs.photos.count
                && lhs.photos.first?.id == rhs.photos.first?.id
                && lhs.photos.last?.id == rhs.photos.last?.id
        }
    }

    struct FolderGroup: Identifiable, Equatable {
        let leafName: String
        let parentPath: String?
        let photos: [PhotoItem]
        let path: String
        var id: String { path }

        static func == (lhs: FolderGroup, rhs: FolderGroup) -> Bool {
            lhs.path == rhs.path && lhs.photos.count == rhs.photos.count
                && lhs.photos.first?.id == rhs.photos.first?.id
                && lhs.photos.last?.id == rhs.photos.last?.id
        }
    }

    struct YearGroup: Identifiable, Equatable {
        let year: Int
        let folderGroups: [FolderGroup]
        var id: Int { year }

        static func == (lhs: YearGroup, rhs: YearGroup) -> Bool {
            lhs.year == rhs.year && lhs.folderGroups.count == rhs.folderGroups.count
        }
    }

    func folderNameComponents(for path: String) -> (leaf: String, parent: String?) {
        if let folder = libraryFolders.first(where: { $0.path == path }) {
            return (folder.name, nil)
        }
        for root in libraryFolders {
            let rootPath = root.path.hasSuffix("/") ? root.path : root.path + "/"
            if path.hasPrefix(rootPath) {
                let relative = String(path.dropFirst(rootPath.count))
                return relative.isEmpty ? (root.name, nil) : formatRelativePathComponents(relative)
            }
        }
        return (URL(fileURLWithPath: path).lastPathComponent, nil)
    }

    private func formatRelativePathComponents(_ path: String) -> (leaf: String, parent: String?) {
        let components = path.split(separator: "/")
        guard components.count > 1, let leaf = components.last else { return (String(components.first ?? ""), nil) }
        let parent = components.dropLast().joined(separator: "/")
        return (String(leaf), parent)
    }

    var photoCounts: [String: Int] = [:]

    func photoCount(for folderPath: String) -> Int {
        photoCounts[folderPath] ?? 0
    }

    func photoCountForYear(_ year: Int) -> Int {
        let showVideos = settings.showVideos
        return (try? DatabaseManager.shared.dbQueue.read { db in
            if showVideos {
                return try Int.fetchOne(db, sql: """
                    SELECT COUNT(*) FROM photos
                    WHERE CAST(strftime('%Y', COALESCE(dateTakenOriginal, modificationDate)) AS INTEGER) = ?
                """, arguments: [year])
            }
            return try Int.fetchOne(db, sql: """
                SELECT COUNT(*) FROM photos
                WHERE CAST(strftime('%Y', COALESCE(dateTakenOriginal, modificationDate)) AS INTEGER) = ?
                  AND mediaKind != ?
            """, arguments: [year, MediaKind.video.rawValue])
        }) ?? 0
    }

    private(set) var totalDiskUsage: String = ""

    private func rebuildTotalDiskUsage(for items: [PhotoItem]) {
        let total = items.reduce(into: Int64(0)) { $0 += $1.fileSize }
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        totalDiskUsage = formatter.string(fromByteCount: total)
    }

    var trayPhotos: Set<PhotoItem> {
        temporarilySelectedPhotos.union(pinnedPhotos)
    }

    var visibleTrayPhotoOrder: [PhotoItem] {
        settings.showVideos ? trayPhotoOrder : trayPhotoOrder.filter { !$0.isVideo }
    }

    var visibleTrayPhotos: Set<PhotoItem> {
        Set(visibleTrayPhotoOrder)
    }



    init(settings: AppSettings = AppSettings()) {
        self.settings = settings
        thumbnailSize = settings.defaultThumbnailSize
        if let raw = UserDefaults.standard.string(forKey: "PicshursSidebarGrouping"),
           let grouping = SidebarGrouping(rawValue: raw) {
            _sidebarGrouping = grouping
        }
        loadLibrary()
        loadExcludedLeafPaths()
        cleanOrphanedPhotos()
        cleanOrphanedBackups()
        if !libraryFolders.isEmpty {
            openAllPhotos()
        }
    }

    /// Removes .picshurs_backups/ leftovers older than 7 days (created by save-to-original on crash).
    private func cleanOrphanedBackups() {
        let cutoff = Date(timeIntervalSinceNow: -7 * 86400)
        let fm = FileManager.default
        Task.detached(priority: .background) {
            for folder in self.libraryFolders {
                guard let url = folder.url else { continue }
                let backupDir = url.appendingPathComponent(".picshurs_backups", isDirectory: true)
                guard let files = try? fm.contentsOfDirectory(at: backupDir, includingPropertiesForKeys: [.contentModificationDateKey], options: .skipsHiddenFiles) else { continue }
                for file in files {
                    let mod = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
                    if mod < cutoff { try? fm.removeItem(at: file) }
                }
            }
        }
    }

    /// Deletes DB rows whose folderPath no longer belongs to any tracked LibraryFolder.
    private func cleanOrphanedPhotos() {
        guard !libraryFolders.isEmpty else { return }
        let watchedPaths = libraryFolders.map { $0.path }
        let validPrefixes = watchedPaths.map { $0 + "/" }
        writeToDB { db in
            let allPaths: [String] = try String.fetchAll(db, sql: "SELECT DISTINCT folderPath FROM photos")
            let orphaned = allPaths.filter { path in
                !watchedPaths.contains(path) && !validPrefixes.contains(where: { path.hasPrefix($0) })
            }
            if !orphaned.isEmpty {
                let placeholders = orphaned.map { _ in "?" }.joined(separator: ",")
                _ = try db.execute(
                    sql: "DELETE FROM photos WHERE folderPath IN (\(placeholders))",
                    arguments: StatementArguments(orphaned)
                )
            }
        }
    }

    // MARK: - Selection

    func selectSingle(_ photo: PhotoItem) {
        let oldTemp = Array(temporarilySelectedPhotos)
        temporarilySelectedPhotos.removeAll()
        selectedPhoto = photo
        clearExternalVideoReturnStateIfSelectionChanged()
        temporarilySelectedPhotos.insert(photo)
        addToTrayOrder(photo)
        for p in oldTemp {
            removeFromTrayOrderIfNoLongerInTray(p)
        }
    }

    func toggleSelection(_ photo: PhotoItem) {
        if temporarilySelectedPhotos.contains(photo) {
            temporarilySelectedPhotos.remove(photo)
            if selectedPhoto == photo {
                selectedPhoto = temporarilySelectedPhotos.first
                clearExternalVideoReturnStateIfSelectionChanged()
            }
            removeFromTrayOrderIfNoLongerInTray(photo)
        } else {
            temporarilySelectedPhotos.insert(photo)
            selectedPhoto = photo
            clearExternalVideoReturnStateIfSelectionChanged()
            addToTrayOrder(photo)
        }
    }

    func selectRange(from start: PhotoItem, to end: PhotoItem) {
        let list = visiblePhotos
        guard let startIdx = visiblePhotoIndex(for: start.url.path),
              let endIdx = visiblePhotoIndex(for: end.url.path) else { return }
        let range = min(startIdx, endIdx)...max(startIdx, endIdx)
        for i in range {
            let photo = list[i]
            temporarilySelectedPhotos.insert(photo)
            addToTrayOrder(photo)
        }
        selectedPhoto = end
        clearExternalVideoReturnStateIfSelectionChanged()
    }

    func selectAll() {
        let cap = min(visiblePhotos.count, 200)
        let capped = Array(visiblePhotos.prefix(cap))
        temporarilySelectedPhotos = Set(capped)
        selectedPhoto = capped.first
        clearExternalVideoReturnStateIfSelectionChanged()
        for photo in capped {
            addToTrayOrder(photo)
        }
    }

    func clearTemporarySelection() {
        let removed = Array(temporarilySelectedPhotos)
        temporarilySelectedPhotos.removeAll()
        selectedPhoto = pinnedPhotos.first
        clearExternalVideoReturnStateIfSelectionChanged()
        for photo in removed {
            removeFromTrayOrderIfNoLongerInTray(photo)
        }
    }

    func toggleFilenameLabels() {
        settings.showFilenameLabels.toggle()
    }

    func removeFromTemporarySelection(_ photo: PhotoItem) {
        temporarilySelectedPhotos.remove(photo)
        if selectedPhoto == photo {
            selectedPhoto = temporarilySelectedPhotos.first ?? pinnedPhotos.first
            clearExternalVideoReturnStateIfSelectionChanged()
        }
        removeFromTrayOrderIfNoLongerInTray(photo)
    }

    // MARK: - PhotoItem Mutation Helpers

    private func updatePhotoEverywhere(_ photo: PhotoItem) {
        let urlPath = photo.url.path
        var mutated = false
        if let index = photos.firstIndex(where: { $0.url.path == urlPath }) {
            photos[index] = photo
            mutated = true
        }
        if selectedPhoto?.url.path == urlPath { selectedPhoto = photo }
        if pinnedPhotos.remove(photo) != nil { pinnedPhotos.insert(photo) }
        if temporarilySelectedPhotos.remove(photo) != nil { temporarilySelectedPhotos.insert(photo) }
        for i in trayPhotoOrder.indices {
            if trayPhotoOrder[i].url.path == urlPath { trayPhotoOrder[i] = photo }
        }
        if mutated { rebuildFilteredPhotos() }
    }

    private func batchUpdatePhotos(_ updates: [PhotoItem]) {
        let updateMap = Dictionary(uniqueKeysWithValues: updates.map { ($0.url.path, $0) })
        for i in photos.indices {
            if let update = updateMap[photos[i].url.path] { photos[i] = update }
        }
        if let current = selectedPhoto, let update = updateMap[current.url.path] { selectedPhoto = update }
        pinnedPhotos = Set(pinnedPhotos.map { updateMap[$0.url.path] ?? $0 })
        temporarilySelectedPhotos = Set(temporarilySelectedPhotos.map { updateMap[$0.url.path] ?? $0 })
        trayPhotoOrder = trayPhotoOrder.map { updateMap[$0.url.path] ?? $0 }
        rebuildFilteredPhotos()
    }

    // MARK: - Pin / Unpin

    func pinPhoto(_ photo: PhotoItem) {
        var updated = photo
        updated.isPinned = true
        pinnedPhotos.insert(updated)
        updatePhotoEverywhere(updated)
        addToTrayOrder(updated)
        writeToDBAsync { db in
            try db.execute(literal: "UPDATE photos SET isPinned = 1 WHERE url = \(photo.url.path)")
        }
    }

    func unpinPhoto(_ photo: PhotoItem) {
        var updated = photo
        updated.isPinned = false
        pinnedPhotos.remove(photo)
        updatePhotoEverywhere(updated)
        removeFromTrayOrderIfNoLongerInTray(updated)
        writeToDBAsync { db in
            try db.execute(literal: "UPDATE photos SET isPinned = 0 WHERE url = \(photo.url.path)")
        }
    }

    func togglePin(_ photo: PhotoItem) {
        if pinnedPhotos.contains(photo) {
            var updated = photo
            updated.isPinned = false
            pinnedPhotos.remove(photo)
            updatePhotoEverywhere(updated)
            writeToDBAsync { db in
                try db.execute(literal: "UPDATE photos SET isPinned = 0 WHERE url = \(photo.url.path)")
            }
        } else {
            var updated = photo
            updated.isPinned = true
            pinnedPhotos.insert(updated)
            updatePhotoEverywhere(updated)
            writeToDBAsync { db in
                try db.execute(literal: "UPDATE photos SET isPinned = 1 WHERE url = \(photo.url.path)")
            }
        }
    }

    func isPinned(_ photo: PhotoItem) -> Bool {
        pinnedPhotos.contains(photo)
    }

    // MARK: - Star / Unstar

    func starPhoto(_ photo: PhotoItem) {
        var updated = photo
        updated.isStarred = true
        updatePhotoEverywhere(updated)
        writeToDBAsync { db in
            try db.execute(literal: "UPDATE photos SET isStarred = 1 WHERE url = \(photo.url.path)")
        }
    }

    func unstarPhoto(_ photo: PhotoItem) {
        var updated = photo
        updated.isStarred = false
        updatePhotoEverywhere(updated)
        writeToDBAsync { db in
            try db.execute(literal: "UPDATE photos SET isStarred = 0 WHERE url = \(photo.url.path)")
        }
    }

    func toggleStarred(_ photo: PhotoItem) {
        if photo.isStarred {
            unstarPhoto(photo)
        } else {
            starPhoto(photo)
        }
    }

    func toggleDotColor(_ photo: PhotoItem, color: Int) {
        let bit = DotColor.bitMask(for: color)
        let hasIt = (photo.dotColor & bit) != 0
        var updated = photo
        updated.dotColor = hasIt ? (photo.dotColor & ~bit) : (photo.dotColor | bit)
        updatePhotoEverywhere(updated)
        let dotColor = updated.dotColor
        let urlPath = updated.url.path
        mutateDotColorsThenRefresh { db in
            try db.execute(literal: "UPDATE photos SET dotColor = \(dotColor) WHERE url = \(urlPath)")
        }
    }

    func clearDotColor(_ photo: PhotoItem) {
        var updated = photo
        updated.dotColor = 0
        updatePhotoEverywhere(updated)
        let urlPath = updated.url.path
        mutateDotColorsThenRefresh { db in
            try db.execute(literal: "UPDATE photos SET dotColor = 0 WHERE url = \(urlPath)")
        }
    }

    func clearDotColorFromAllPhotos(color: Int) {
        let bit = DotColor.bitMask(for: color)
        let deduped = Set(photos + pinnedPhotos + temporarilySelectedPhotos + trayPhotoOrder)
        let updated = deduped.map { photo -> PhotoItem in
            var p = photo
            p.dotColor &= ~bit
            return p
        }
        batchUpdatePhotos(updated)
        mutateDotColorsThenRefresh { db in
            try db.execute(literal: "UPDATE photos SET dotColor = dotColor & ~\(bit)")
        }
    }

    func moveTrayItem(from sourceIndex: Int, toDropZone dropZone: Int) {
        guard sourceIndex >= 0, sourceIndex < trayPhotoOrder.count else { return }
        let clampedZone = min(max(0, dropZone), trayPhotoOrder.count)

        if clampedZone == 0 && sourceIndex == 0 { return }
        if clampedZone == trayPhotoOrder.count && sourceIndex == trayPhotoOrder.count - 1 { return }

        let item = trayPhotoOrder.remove(at: sourceIndex)
        let adjustedZone = clampedZone > sourceIndex ? clampedZone - 1 : clampedZone
        let finalIndex = min(max(0, adjustedZone), trayPhotoOrder.count)
        trayPhotoOrder.insert(item, at: finalIndex)

        persistTrayOrder()
        if displayMode == .tray { rebuildVisiblePhotos() }
    }

    /// Moves a block of photos to the given drop zone, preserving their
    /// current relative order. Used by drag-reorder in the tray grid view —
    /// dragging any selected photo moves the whole selection.
    /// A folder's year is the year most of its photos are from; ties go to
    /// the newer year. Shared by grid grouping, sidebar grouping, and year
    /// filtering so the three views always agree.
    static func majorityYear(from counts: [Int: Int]) -> Int? {
        counts.max(by: { ($0.value, $0.key) < ($1.value, $1.key) })?.key
    }

    /// Pure block-move math, extracted for testability: moves `items` (in
    /// their current relative order) so the block starts at `dropZone`,
    /// where the zone is an insertion index into the original array.
    static func reorderedTray(_ order: [PhotoItem], moving items: Set<PhotoItem>, toDropZone dropZone: Int) -> [PhotoItem] {
        let moving = order.filter { items.contains($0) }
        guard !moving.isEmpty else { return order }
        let movingSet = Set(moving)
        let clampedZone = min(max(0, dropZone), order.count)

        // Insertion index shifts left by however many moving items sat before the zone
        let movedBeforeZone = order.prefix(clampedZone).filter { movingSet.contains($0) }.count
        var remaining = order.filter { !movingSet.contains($0) }
        let insertAt = min(max(0, clampedZone - movedBeforeZone), remaining.count)
        remaining.insert(contentsOf: moving, at: insertAt)
        return remaining
    }

    func moveTrayItems(_ items: Set<PhotoItem>, toDropZone dropZone: Int) {
        let reordered = Self.reorderedTray(trayPhotoOrder, moving: items, toDropZone: dropZone)
        guard reordered != trayPhotoOrder else { return }
        trayPhotoOrder = reordered
        persistTrayOrder()
        if displayMode == .tray { rebuildVisiblePhotos() }
    }

    private func persistTrayOrder() {
        let snapshot = trayPhotoOrder
        Task.detached {
            do {
                try await DatabaseManager.shared.dbQueue.write { db in
                    let stmt = try db.makeStatement(sql: "UPDATE photos SET trayOrder = ? WHERE url = ?")
                    for (index, photo) in snapshot.enumerated() {
                        try stmt.execute(arguments: [index, photo.url.path])
                    }
                }
            } catch {
                await MainActor.run { self.lastError = error.localizedDescription }
            }
        }
    }

    private func addToTrayOrder(_ photo: PhotoItem) {
        guard !trayPhotoOrder.contains(photo) else { return }
        guard trayPhotoOrder.count < 200 else { return }
        trayPhotoOrder.append(photo)
        if displayMode == .tray { rebuildVisiblePhotos() }
    }

    func addToTrayOrderIfNeeded(_ photo: PhotoItem) {
        guard !trayPhotoOrder.contains(photo) else { return }
        guard trayPhotoOrder.count < 200 else {
            showAlert(message: "Tray is full (200 items max).")
            return
        }
        trayPhotoOrder.append(photo)
        if displayMode == .tray { rebuildVisiblePhotos() }
    }

    private func removeFromTrayOrderIfNoLongerInTray(_ photo: PhotoItem) {
        if !temporarilySelectedPhotos.contains(photo) && !pinnedPhotos.contains(photo) {
            trayPhotoOrder.removeAll { $0 == photo }
            if displayMode == .tray { rebuildVisiblePhotos() }
        }
    }

    func removeFromTray(_ photo: PhotoItem) {
        if temporarilySelectedPhotos.contains(photo) {
            temporarilySelectedPhotos.remove(photo)
        } else if pinnedPhotos.contains(photo) {
            pinnedPhotos.remove(photo)
        }
        if selectedPhoto == photo {
            selectedPhoto = temporarilySelectedPhotos.first ?? pinnedPhotos.first
        }
        removeFromTrayOrderIfNoLongerInTray(photo)
    }

    /// User-facing variant — confirms before discarding a curated tray.
    /// Programmatic callers use clearAllFromTray() directly.
    func clearAllFromTrayWithConfirmation() {
        if trayPhotoOrder.count > 3 {
            let alert = NSAlert()
            alert.messageText = "Clear all \(trayPhotoOrder.count) items from tray?"
            alert.informativeText = "Photos stay in your library — only the tray and its ordering are cleared."
            alert.alertStyle = .warning
            alert.addButton(withTitle: "Clear Tray")
            alert.addButton(withTitle: "Cancel")
            if alert.runModal() == .alertSecondButtonReturn { return }
        }
        clearAllFromTray()
    }

    func clearAllFromTray() {
        let pinnedURLs = pinnedPhotos.map(\.url.path)
        if !pinnedURLs.isEmpty {
            writeToDBAsync { db in
                _ = try db.execute(literal: "UPDATE photos SET isPinned = 0 WHERE url IN \(pinnedURLs)")
            }
        }
        temporarilySelectedPhotos.removeAll()
        pinnedPhotos.removeAll()
        trayPhotoOrder.removeAll()
        selectedPhoto = nil
        if displayMode == .tray { rebuildVisiblePhotos() }
    }

    // MARK: - Navigation / Viewer

    var trayContainsVideos: Bool {
        visibleTrayPhotoOrder.contains { $0.isVideo }
    }

    var selectedPhotosInVisibleOrder: [PhotoItem] {
        let selectedPaths = Set(temporarilySelectedPhotos.map(\.url.path))
        if selectedPaths.isEmpty {
            if let selectedPhoto { return [selectedPhoto] }
            return []
        }
        let ordered = visiblePhotos.filter { selectedPaths.contains($0.url.path) }
        return ordered.isEmpty ? Array(temporarilySelectedPhotos) : ordered
    }

    var canRunPhotoOnlyTrayActions: Bool {
        !trayContainsVideos
    }

    func handleVideoVisibilityChanged() {
        if !settings.showVideos {
            temporarilySelectedPhotos = temporarilySelectedPhotos.filter { !$0.isVideo }
        }
        rebuildFilteredPhotos()
        guard !settings.showVideos, selectedPhoto?.isVideo == true else { return }
        isViewingPhoto = false
        isEditing = false
        if let replacement = visiblePhotos.first {
            selectSingle(replacement)
        } else {
            selectedPhoto = nil
            temporarilySelectedPhotos.removeAll()
        }
    }

    func openMedia(_ photo: PhotoItem) {
        let preserveSelection = temporarilySelectedPhotos.contains(photo) && temporarilySelectedPhotos.count > 1
        if preserveSelection {
            selectedPhoto = photo
            clearExternalVideoReturnStateIfSelectionChanged()
        } else {
            selectSingle(photo)
        }
        isViewingPhoto = true
    }

    func prepareForExternalVideoOpen(_ photo: PhotoItem) {
        guard photo.isVideo else { return }
        selectedPhoto = photo
        isViewingPhoto = true
        isEditing = false
        externalVideoReturnURL = photo.url
        suppressGalleryCloseUntil = Date().addingTimeInterval(2.0)
    }

    func openVideoInDefaultPlayer(_ photo: PhotoItem) {
        guard photo.isVideo else { return }
        prepareForExternalVideoOpen(photo)
        if !NSWorkspace.shared.open(photo.url) {
            externalVideoReturnURL = nil
            suppressGalleryCloseUntil = nil
            if selectedPhoto == photo {
                isViewingPhoto = true
            }
            lastError = "Could not open this video."
        }
    }

    func handleReturnFromExternalVideoPlayer() {
        guard let externalVideoReturnURL,
              selectedPhoto?.url == externalVideoReturnURL
        else { return }
        isViewingPhoto = true
        isEditing = false
        suppressGalleryCloseUntil = Date().addingTimeInterval(1.0)
    }

    func shouldSuppressGalleryCloseShortcut() -> Bool {
        guard selectedPhoto?.isVideo == true,
              externalVideoReturnURL == selectedPhoto?.url,
              let suppressGalleryCloseUntil,
              Date() <= suppressGalleryCloseUntil
        else { return false }
        self.suppressGalleryCloseUntil = nil
        return true
    }

    func clearExternalVideoReturnStateIfSelectionChanged() {
        guard let externalVideoReturnURL else { return }
        if selectedPhoto?.url != externalVideoReturnURL {
            self.externalVideoReturnURL = nil
            suppressGalleryCloseUntil = nil
        }
    }

    func openSelectedPhoto() {
        if let selectedPhoto {
            openMedia(selectedPhoto)
        }
    }

    func closeViewer() {
        isViewingPhoto = false
    }

    func navigateBackward() {
        let list = visiblePhotos
        guard !list.isEmpty else { return }
        if let current = selectedPhoto,
           let idx = visiblePhotoIndex(for: current.url.path),
           idx > 0 {
            let target = list[idx - 1]
            if isViewingPhoto {
                openMedia(target)
            } else {
                selectSingle(target)
            }
        } else if let first = list.first {
            if isViewingPhoto {
                openMedia(first)
            } else {
                selectSingle(first)
            }
        }
    }

    /// Reported by the grid views (they own the container width) so vertical
    /// arrow navigation knows how many cells one row spans.
    @ObservationIgnored var gridColumnCount: Int = 1

    func navigateRow(up: Bool) {
        let list = visiblePhotos
        guard !list.isEmpty, gridColumnCount > 0 else { return }
        guard let current = selectedPhoto,
              let idx = visiblePhotoIndex(for: current.url.path) else {
            if let first = list.first { selectSingle(first) }
            return
        }
        let target = up ? idx - gridColumnCount : idx + gridColumnCount
        guard target >= 0, target < list.count else { return }
        if isViewingPhoto {
            openMedia(list[target])
        } else {
            selectSingle(list[target])
        }
    }

    func navigateForward() {
        let list = visiblePhotos
        guard !list.isEmpty else { return }
        if let current = selectedPhoto,
           let idx = visiblePhotoIndex(for: current.url.path),
           idx < list.count - 1 {
            let target = list[idx + 1]
            if isViewingPhoto {
                openMedia(target)
            } else {
                selectSingle(target)
            }
        } else if let first = list.first {
            if isViewingPhoto {
                openMedia(first)
            } else {
                selectSingle(first)
            }
        }
    }

    // MARK: - Delete

    func deleteCurrentPhoto() {
        guard let current = selectedPhoto else { return }
        if temporarilySelectedPhotos.count > 1 {
            batchDelete()
        } else {
            let idx = visiblePhotoIndex(for: current.url.path) ?? 0
            guard deletePhotos([current]) else { return }
            if visiblePhotos.isEmpty {
                isViewingPhoto = false
                clearAllFromTray()
            } else {
                let newIndex = min(idx, visiblePhotos.count - 1)
                let next = visiblePhotos[newIndex]
                if isViewingPhoto {
                    openMedia(next)
                } else {
                    selectSingle(next)
                }
            }
        }
    }

    /// Moves photos to trash. Returns false if the user cancelled the confirm dialog.
    /// Only removes photos from the in-memory model and DB when the file operation succeeds.
    @discardableResult
    func deletePhotos(_ photos: [PhotoItem]) -> Bool {
        guard !photos.isEmpty else { return false }

        if settings.confirmBeforeTrash {
            let alert = NSAlert()
            alert.messageText = photos.count == 1 ? "Move to Trash?" : "Move \(photos.count) items to Trash?"
            alert.informativeText = photos.count == 1
                ? "\(photos.first?.filename ?? "File") will be moved to the Trash."
                : "These \(photos.count) items will be moved to the Trash."
            alert.alertStyle = .warning
            alert.addButton(withTitle: "Move to Trash")
            alert.addButton(withTitle: "Cancel")
            if alert.runModal() == .alertSecondButtonReturn { return false }
        }

        var trashed: [PhotoItem] = []
        var failures: [String] = []
        for photo in photos {
            do {
                try FileManager.default.trashItem(at: photo.url, resultingItemURL: nil)
                trashed.append(photo)
            } catch {
                failures.append(photo.filename)
            }
        }

        if !failures.isEmpty {
            showAlert(message: "Failed to move to Trash:\n\(failures.joined(separator: "\n"))")
        }

        guard !trashed.isEmpty else { return false }

        self.photos.removeAll { trashed.contains($0) }
        rebuildFilteredPhotos()
        temporarilySelectedPhotos.subtract(trashed)
        pinnedPhotos.subtract(trashed)
        trayPhotoOrder.removeAll { trashed.contains($0) }
        if let selected = selectedPhoto, trashed.contains(selected) {
            selectedPhoto = temporarilySelectedPhotos.first ?? pinnedPhotos.first
        }

        let paths = trashed.map { $0.url.path }
        writeToDB { db in
            let placeholders = Array(repeating: "?", count: paths.count).joined(separator: ",")
            try db.execute(sql: "DELETE FROM photos WHERE url IN (\(placeholders))",
                           arguments: StatementArguments(paths))
        }

        return true
    }

    // MARK: - Batch Operations (temporary selection)

    func batchDelete() {
        guard !temporarilySelectedPhotos.isEmpty else { return }
        let toDelete = Array(temporarilySelectedPhotos)
        let fallbackIndex = selectedPhoto.flatMap { visiblePhotoIndex(for: $0.url.path) }
        deletePhotos(toDelete)
        if visiblePhotos.isEmpty {
            isViewingPhoto = false
            clearAllFromTray()
        } else {
            let index = min(fallbackIndex ?? 0, visiblePhotos.count - 1)
            selectSingle(visiblePhotos[index])
        }
    }

    // MARK: - Export panel helper

    private enum ExportTemplateScope {
        case selection, tray, trayStripped, trayWeb
        var defaultTemplate: String {
            switch self {
            case .selection:    return ExportNamer.selectionDefault
            case .tray:         return ExportNamer.trayDefault
            case .trayStripped: return ExportNamer.trayStrippedDefault
            case .trayWeb:      return ExportNamer.trayWebDefault
            }
        }
        func storedTemplate(from settings: AppSettings) -> String {
            switch self {
            case .selection:    return settings.exportTemplateSelection
            case .tray:         return settings.exportTemplateTray
            case .trayStripped: return settings.exportTemplateTrayStripped
            case .trayWeb:      return settings.exportTemplateTrayWeb
            }
        }
        func saveTemplate(_ t: String, to settings: AppSettings) {
            switch self {
            case .selection:    settings.exportTemplateSelection = t
            case .tray:         settings.exportTemplateTray = t
            case .trayStripped: settings.exportTemplateTrayStripped = t
            case .trayWeb:      settings.exportTemplateTrayWeb = t
            }
        }
    }

    /// Presents an NSOpenPanel with a template-naming accessory. Returns the
    /// chosen directory URL and the effective template on OK, nil on cancel.
    @MainActor
    private func runExportPanel(
        message: String,
        count: Int,
        samplePhoto: PhotoItem?,
        scope: ExportTemplateScope
    ) -> (dest: URL, template: String)? {
        let storedRaw = scope.storedTemplate(from: settings)
        let sampleItem = samplePhoto.map {
            ExportNamer.Item(
                originalName: $0.url.deletingPathExtension().lastPathComponent,
                date: $0.displayDate,
                ext: $0.url.pathExtension
            )
        } ?? ExportNamer.Item(originalName: "photo", date: Date(), ext: "jpg")

        let model = ExportTemplateModel(
            template: storedRaw,
            defaultTemplate: scope.defaultTemplate,
            sampleItem: sampleItem,
            batchCount: count
        )

        let panel = NSOpenPanel()
        panel.title = "Choose export destination"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Export"
        panel.message = message
        panel.accessoryView = makeExportTemplateAccessory(model: model)
        panel.isAccessoryViewDisclosed = true

        guard panel.runModal() == .OK, let dest = panel.url else { return nil }
        panel.orderOut(nil)

        scope.saveTemplate(model.template, to: settings)
        let effective = ExportNamer.effectiveTemplate(model.template, fallback: scope.defaultTemplate)
        return (dest, effective)
    }

    @MainActor
    func batchExport() {
        guard !temporarilySelectedPhotos.isEmpty else { return }
        // Build ordered array from the user-visible filteredPhotos order — Set
        // iteration is nondeterministic, which breaks {n} numbering.
        let ordered = filteredPhotos.filter { temporarilySelectedPhotos.contains($0) }
        let count = ordered.count

        guard let (destURL, template) = runExportPanel(
            message: "Choose a folder to export \(count) photo(s)",
            count: count,
            samplePhoto: ordered.first,
            scope: .selection
        ) else { return }

        let items = ordered.map {
            ExportNamer.Item(
                originalName: $0.url.deletingPathExtension().lastPathComponent,
                date: $0.displayDate,
                ext: $0.url.pathExtension
            )
        }
        let names = ExportNamer.renderBatch(template: template, items: items)

        var failures: [String] = []
        for (photo, name) in zip(ordered, names) {
            let dest = destURL.appendingPathComponent(name)
            do { try FileManager.default.copyItem(at: photo.url, to: dest) }
            catch { failures.append(photo.filename) }
        }
        if !failures.isEmpty {
            showAlert(message: "Failed to export \(failures.count) file(s):\n\(failures.joined(separator: "\n"))")
        } else {
            showSuccess("Exported \(count) photo(s) to \(destURL.lastPathComponent)")
        }
    }

    func batchCopy() {
        guard !temporarilySelectedPhotos.isEmpty else { return }
        let panel = NSOpenPanel()
        panel.title = "Choose destination folder"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Copy"
        panel.message = "Choose a folder to copy \(temporarilySelectedPhotos.count) photos"

        guard panel.runModal() == .OK, let destURL = panel.url else { return }
        panel.orderOut(nil)

        var failures: [String] = []
        for photo in temporarilySelectedPhotos {
            let dest = destURL.appendingPathComponent(photo.filename)
            do { try FileManager.default.copyItem(at: photo.url, to: dest) }
            catch { failures.append(photo.filename) }
        }
        if !failures.isEmpty {
            showAlert(message: "Failed to copy \(failures.count) file(s):\n\(failures.joined(separator: "\n"))")
        } else {
            showSuccess("Copied \(temporarilySelectedPhotos.count) photo(s) to \(destURL.lastPathComponent)")
        }
    }

    func batchMove() {
        guard !temporarilySelectedPhotos.isEmpty else { return }
        let panel = NSOpenPanel()
        panel.title = "Choose destination folder"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Move"
        panel.message = "Choose a folder to move \(temporarilySelectedPhotos.count) photos"

        guard panel.runModal() == .OK, let destURL = panel.url else { return }
        panel.orderOut(nil)

        var failures: [String] = []
        for photo in temporarilySelectedPhotos {
            let dest = destURL.appendingPathComponent(photo.filename)
            do {
                try FileManager.default.moveItem(at: photo.url, to: dest)
                writeToDB { db in
                    try db.execute(sql: "UPDATE photos SET url = ?, folderPath = ? WHERE url = ?",
                                   arguments: [dest.path, destURL.path, photo.url.path])
                }
            } catch {
                failures.append(photo.filename)
            }
        }
        if !failures.isEmpty {
            showAlert(message: "Failed to move \(failures.count) file(s):\n\(failures.joined(separator: "\n"))")
        } else {
            showSuccess("Moved \(temporarilySelectedPhotos.count) photo(s) to \(destURL.lastPathComponent)")
        }
        if let url = folderURL {
            loadPhotos(from: url)
        } else {
            loadAllLibraryPhotos()
        }
    }

    func batchToggleDotColor(_ color: Int) {
        let bit = DotColor.bitMask(for: color)
        let updated = temporarilySelectedPhotos.map { photo -> PhotoItem in
            let hasIt = (photo.dotColor & bit) != 0
            var p = photo
            p.dotColor = hasIt ? (photo.dotColor & ~bit) : (photo.dotColor | bit)
            return p
        }
        batchUpdatePhotos(updated)
        let updates = updated.map { (url: $0.url.path, dotColor: $0.dotColor) }
        mutateDotColorsThenRefresh { db in
            let stmt = try db.makeStatement(sql: "UPDATE photos SET dotColor = ? WHERE url = ?")
            for (url, dotColor) in updates {
                try stmt.execute(arguments: [dotColor, url])
            }
        }
    }

    func batchClearDotColor() {
        let updated = temporarilySelectedPhotos.map { (photo: PhotoItem) -> PhotoItem in
            var p = photo
            p.dotColor = 0
            return p
        }
        batchUpdatePhotos(updated)
        let urls = updated.map { $0.url.path }
        mutateDotColorsThenRefresh { db in
            _ = try db.execute(literal: "UPDATE photos SET dotColor = 0 WHERE url IN \(urls)")
        }
    }

    // MARK: - Tray Batch Operations

    func trayBatchDelete() {
        let toDelete = visibleTrayPhotoOrder
        guard !toDelete.isEmpty else { return }
        let fallbackIndex = selectedPhoto.flatMap { visiblePhotoIndex(for: $0.url.path) }
        deletePhotos(toDelete)
        if visiblePhotos.isEmpty {
            isViewingPhoto = false
            clearAllFromTray()
        } else {
            let index = min(fallbackIndex ?? 0, visiblePhotos.count - 1)
            selectSingle(visiblePhotos[index])
        }
    }

    @MainActor
    func trayBatchExport() {
        let ordered = visibleTrayPhotoOrder
        guard !ordered.isEmpty else { return }
        let count = ordered.count

        guard let (destURL, template) = runExportPanel(
            message: "Choose a folder to export \(count) photo(s) in order",
            count: count,
            samplePhoto: ordered.first,
            scope: .tray
        ) else { return }

        let items = ordered.map {
            ExportNamer.Item(
                originalName: $0.url.deletingPathExtension().lastPathComponent,
                date: $0.displayDate,
                ext: $0.url.pathExtension
            )
        }
        let names = ExportNamer.renderBatch(template: template, items: items)

        var failures: [String] = []
        for (photo, name) in zip(ordered, names) {
            let dest = destURL.appendingPathComponent(name)
            do { try FileManager.default.copyItem(at: photo.url, to: dest) }
            catch { failures.append(photo.filename) }
        }
        if !failures.isEmpty {
            showAlert(message: "Failed to export \(failures.count) file(s):\n\(failures.joined(separator: "\n"))")
        } else {
            showSuccess("Exported \(count) photo(s) in tray order to \(destURL.lastPathComponent)")
        }
    }

    func trayBatchDuplicate() {
        let ordered = visibleTrayPhotoOrder
        guard !ordered.isEmpty else { return }
        let panel = NSOpenPanel()
        panel.title = "Choose destination folder"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Duplicate"
        panel.message = "Choose a folder to duplicate \(ordered.count) photos"

        guard panel.runModal() == .OK, let destURL = panel.url else { return }
        panel.orderOut(nil)

        var failures: [String] = []
        for photo in ordered {
            let dest = destURL.appendingPathComponent(photo.filename)
            do { try FileManager.default.copyItem(at: photo.url, to: dest) }
            catch { failures.append(photo.filename) }
        }
        if !failures.isEmpty {
            showAlert(message: "Failed to duplicate \(failures.count) file(s):\n\(failures.joined(separator: "\n"))")
        } else {
            showSuccess("Duplicated \(ordered.count) photo(s) to \(destURL.lastPathComponent)")
        }
    }

    @MainActor
    func trayBatchExportNoMetadata() {
        let ordered = visibleTrayPhotoOrder
        guard !ordered.isEmpty else { return }
        guard canRunPhotoOnlyTrayActions else {
            showAlert(message: "Export without metadata is only available for photos.")
            return
        }
        let count = ordered.count

        guard let (destURL, template) = runExportPanel(
            message: "Choose a folder to export \(count) photo(s) with no metadata",
            count: count,
            samplePhoto: ordered.first,
            scope: .trayStripped
        ) else { return }

        let items = ordered.map {
            ExportNamer.Item(
                originalName: $0.url.deletingPathExtension().lastPathComponent,
                date: $0.displayDate,
                ext: $0.url.pathExtension
            )
        }
        let names = ExportNamer.renderBatch(template: template, items: items)

        var failures: [String] = []
        for (photo, name) in zip(ordered, names) {
            let dest = destURL.appendingPathComponent(name)
            do { try MetadataStripper.stripMetadata(from: photo.url, to: dest) }
            catch { failures.append(photo.filename) }
        }
        if !failures.isEmpty {
            showAlert(message: "Failed to export \(failures.count) file(s):\n\(failures.joined(separator: "\n"))")
        } else {
            showSuccess("Exported \(count) photo(s) without metadata to \(destURL.lastPathComponent)")
        }
    }

    @MainActor
    func trayBatchExportForWeb() {
        let ordered = visibleTrayPhotoOrder
        guard !ordered.isEmpty else { return }
        guard canRunPhotoOnlyTrayActions else {
            showAlert(message: "Web export is only available for photos.")
            return
        }
        let count = ordered.count

        guard let (destURL, template) = runExportPanel(
            message: "Choose a folder to export \(count) photo(s) optimized for web",
            count: count,
            samplePhoto: ordered.first,
            scope: .trayWeb
        ) else { return }

        let maxDim = settings.webExportMaxDimension
        let quality = CGFloat(settings.webExportQuality)

        let items = ordered.map {
            ExportNamer.Item(
                originalName: $0.url.deletingPathExtension().lastPathComponent,
                date: $0.displayDate,
                ext: WebOptimizer.fileExtension(for: $0.url)
            )
        }
        let names = ExportNamer.renderBatch(template: template, items: items)

        var failures: [String] = []
        for (photo, name) in zip(ordered, names) {
            let dest = destURL.appendingPathComponent(name)
            do { try WebOptimizer.optimize(forWeb: photo.url, to: dest, maxDimension: maxDim, quality: quality) }
            catch { failures.append(photo.filename) }
        }
        if !failures.isEmpty {
            showAlert(message: "Failed to export \(failures.count) file(s) for web:\n\(failures.joined(separator: "\n"))")
        } else {
            showSuccess("Exported \(count) photo(s) for web to \(destURL.lastPathComponent)")
        }
    }

    func trayBatchMove() {
        let ordered = visibleTrayPhotoOrder
        guard !ordered.isEmpty else { return }
        let panel = NSOpenPanel()
        panel.title = "Choose destination folder"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Move"
        panel.message = "Choose a folder to move \(ordered.count) photos"

        guard panel.runModal() == .OK, let destURL = panel.url else { return }
        panel.orderOut(nil)

        var failures: [String] = []
        for photo in ordered {
            let dest = destURL.appendingPathComponent(photo.filename)
            do {
                try FileManager.default.moveItem(at: photo.url, to: dest)
                writeToDB { db in
                    try db.execute(sql: "UPDATE photos SET url = ?, folderPath = ? WHERE url = ?",
                                   arguments: [dest.path, destURL.path, photo.url.path])
                }
            } catch {
                failures.append(photo.filename)
            }
        }
        if !failures.isEmpty {
            showAlert(message: "Failed to move \(failures.count) file(s):\n\(failures.joined(separator: "\n"))")
        } else {
            showSuccess("Moved \(ordered.count) photo(s) to \(destURL.lastPathComponent)")
        }
        if let url = folderURL {
            loadPhotos(from: url)
        } else {
            loadAllLibraryPhotos()
        }
    }

    func trayBatchToggleDotColor(_ color: Int) {
        let bit = DotColor.bitMask(for: color)
        let updated = visibleTrayPhotoOrder.map { photo -> PhotoItem in
            let hasIt = (photo.dotColor & bit) != 0
            var p = photo
            p.dotColor = hasIt ? (photo.dotColor & ~bit) : (photo.dotColor | bit)
            return p
        }
        batchUpdatePhotos(updated)
        let updates = updated.map { (url: $0.url.path, dotColor: $0.dotColor) }
        mutateDotColorsThenRefresh { db in
            let stmt = try db.makeStatement(sql: "UPDATE photos SET dotColor = ? WHERE url = ?")
            for (url, dotColor) in updates {
                try stmt.execute(arguments: [dotColor, url])
            }
        }
    }

    func trayBatchClearDotColor() {
        let updated = visibleTrayPhotoOrder.map { (photo: PhotoItem) -> PhotoItem in
            var p = photo
            p.dotColor = 0
            return p
        }
        batchUpdatePhotos(updated)
        let urls = visibleTrayPhotoOrder.map { $0.url.path }
        mutateDotColorsThenRefresh { db in
            _ = try db.execute(literal: "UPDATE photos SET dotColor = 0 WHERE url IN \(urls)")
        }
    }

    // MARK: - Library

    func openFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.message = "Choose a folder with photos"

        guard panel.runModal() == .OK, let url = panel.url else { return }
        addFolderToLibrary(url)
        panel.orderOut(nil)
    }

    func refreshCurrentView(preserveSelection: Bool = true) {
        switch displayMode {
        case .library:
            loadAllLibraryPhotos(preserveSelection: preserveSelection)
        case .dot:
            loadDotColorPhotos(preserveSelection: preserveSelection)
        case .tray:
            if preserveSelection {
                let snapshot = makeSelectionSnapshot()
                photos = Array(trayPhotoOrder)
                rebuildFilteredPhotos()
                restoreSelectionAfterReload(snapshot)
            } else {
                openTrayPhotos(pushHistory: false)
            }
        case let .folder(folder):
            if let url = folder.url {
                loadPhotos(from: url, preserveSelection: preserveSelection)
            }
        case let .year(year):
            loadPhotosForYear(year, preserveSelection: preserveSelection)
        case .map:
            loadMapPhotos(preserveSelection: preserveSelection)
        case .people:
            refreshPersons()
        case let .person(id):
            loadPersonPhotos(id, preserveSelection: preserveSelection)
        }
    }

    // MARK: - Navigation History

    /// Called *before* `displayMode` changes — records the mode being left so Back
    /// can return to it, and starts a fresh forward branch.
    func pushNavigation() {
        guard backStack.last != displayMode else { return }
        backStack.append(displayMode)
        forwardStack.removeAll()
    }

    func goBack() {
        guard let target = backStack.popLast() else { return }
        forwardStack.append(displayMode)
        applyNavigationMode(target)
    }

    func goForward() {
        guard let target = forwardStack.popLast() else { return }
        backStack.append(displayMode)
        applyNavigationMode(target)
    }

    private func applyNavigationMode(_ mode: DisplayMode) {
        switch mode {
        case .library: openAllPhotos(pushHistory: false)
        case let .dot(color): openDotColorPhotos(color, pushHistory: false)
        case .tray: openTrayPhotos(pushHistory: false)
        case let .folder(folder): openLibraryFolder(folder, pushHistory: false)
        case let .year(year): openYearPhotos(year, pushHistory: false)
        case .map: openMap(pushHistory: false)
        case .people: openPeople(pushHistory: false)
        case let .person(id): openPerson(id, name: personName(for: id), pushHistory: false)
        }
    }

    func openLibraryFolder(_ folder: LibraryFolder, pushHistory: Bool = true) {
        if pushHistory { pushNavigation() }
        displayMode = .folder(folder)
        guard let url = folder.url else { return }
        folderURL = url
        folderName = folder.name
        loadPhotos(from: url, preserveSelection: false)
    }

    func addFolderToLibrary(_ url: URL) {
        let path = url.path
        guard !libraryFolders.contains(where: { $0.path == path }) else {
            openLibraryFolder(libraryFolders.first(where: { $0.path == path })!)
            return
        }

        let wasEmpty = libraryFolders.isEmpty
        let folder = LibraryFolder(name: url.lastPathComponent, path: path)
        libraryFolders.append(folder)
        saveLibrary()

        if wasEmpty {
            openAllPhotos()
        } else {
            openLibraryFolder(folder)
        }
    }

    func openAllPhotos(pushHistory: Bool = true) {
        if pushHistory { pushNavigation() }
        displayMode = .library
        folderURL = nil
        folderName = "All Photos"
        loadAllLibraryPhotos(preserveSelection: false)
    }

    func openDotColorPhotos(_ color: Int, pushHistory: Bool = true) {
        if pushHistory { pushNavigation() }
        displayMode = .dot(color)
        folderURL = nil
        folderName = DotColor.name(for: color) ?? "Photos"
        loadDotColorPhotos(preserveSelection: false)
    }

    func openTrayPhotos(pushHistory: Bool = true) {
        if pushHistory { pushNavigation() }
        displayMode = .tray
        folderURL = nil
        folderName = "Tray"
        photos = Array(trayPhotoOrder)
        rebuildFilteredPhotos()
        clearTemporarySelection()
        if let first = visiblePhotos.first {
            selectedPhoto = first
            temporarilySelectedPhotos.insert(first)
        } else {
            selectedPhoto = nil
        }
    }

    // MARK: - Map

    func openMap(pushHistory: Bool = true) {
        if pushHistory { pushNavigation() }
        displayMode = .map
        folderURL = nil
        folderName = "Map"
        loadMapPhotos(preserveSelection: false)
    }

    /// Loads only geotagged photos (latitude present), scoped to the library,
    /// for the MapKit annotations. Mirrors `loadDotColorPhotos`.
    private func loadMapPhotos(preserveSelection: Bool = false) {
        let snapshot = preserveSelection ? makeSelectionSnapshot() : nil
        if !preserveSelection {
            clearTemporarySelection()
            selectedPhoto = nil
        }
        loadGeneration += 1
        let generation = loadGeneration

        Task { @MainActor in
            isLoading = true
            let geoRecords: [PhotoRecord] = (try? await DatabaseManager.shared.dbQueue.read { db in
                try PhotoRecord.filter(Column("latitude") != nil).fetchAll(db)
            }) ?? []
            guard generation == loadGeneration else { return }

            photos = filterLibraryRecords(geoRecords)
            rebuildFilteredPhotos()
            restoreSelectionAfterReload(snapshot)
            await refreshPinnedPhotos()
            guard generation == loadGeneration else { return }
            isLoading = false
        }
    }

    // MARK: - People (faces)
    // Sidebar chip for one clustered person. `coverFaceRect` is the normalized
    // Vision boundingBox (bottom-left origin) of the representative face.
    struct PersonChip: Identifiable, Equatable {
        let id: String
        var name: String?
        let count: Int
        let coverFaceURL: URL?
        let coverFaceRect: CGRect?
    }

    var persons: [PersonChip] = []
    var isScanningFaces = false
    var faceScanProgress: (done: Int, total: Int)?

    func personName(for id: String) -> String? {
        persons.first { $0.id == id }?.name
    }

    /// Rebuilds the People list from the faces/persons tables. A single
    /// self-joined query resolves each person's representative face inline —
    /// avoids an `IN (?,?,…)` param explosion when clusters run to the thousands.
    /// Detached read → main-actor assign, mirroring `refreshUsedDotColors`.
    func refreshPersons() {
        Task.detached { [weak self] in
            let chips: [PersonChip] = (try? await DatabaseManager.shared.dbQueue.read { db -> [PersonChip] in
                let rows = try Row.fetchAll(db, sql: """
                    SELECT p.id AS id, p.name AS name, COUNT(f.id) AS cnt,
                           cover.photoURL AS coverURL,
                           cover.rectX AS rx, cover.rectY AS ry,
                           cover.rectW AS rw, cover.rectH AS rh
                    FROM persons p
                    JOIN faces f ON f.personId = p.id
                    JOIN faces cover ON cover.id = COALESCE(
                        p.coverFaceId,
                        (SELECT MIN(f2.id) FROM faces f2 WHERE f2.personId = p.id)
                    )
                    WHERE p.isHidden = 0
                    GROUP BY p.id
                    ORDER BY cnt DESC, p.id
                """)
                return rows.map { row in
                    let url = (row["coverURL"] as String?).map { URL(fileURLWithPath: $0) }
                    let rect = CGRect(x: row["rx"] as Double? ?? 0, y: row["ry"] as Double? ?? 0,
                                      width: row["rw"] as Double? ?? 0, height: row["rh"] as Double? ?? 0)
                    return PersonChip(
                        id: row["id"], name: row["name"], count: row["cnt"],
                        coverFaceURL: url, coverFaceRect: rect
                    )
                }
            }) ?? []
            guard let self else { return }
            await MainActor.run { self.persons = chips }
        }
    }

    /// Manual, throttled face scan. Updates progress live; refreshes People when done.
    /// Progress flows through an AsyncStream so the `@Sendable` scan callback
    /// captures only the (Sendable) continuation, never `self`.
    func scanForFaces() {
        guard !isScanningFaces else { return }
        isScanningFaces = true
        faceScanProgress = (0, 0)

        let (stream, continuation) = AsyncStream.makeStream(of: (Int, Int).self)
        Task.detached {
            await FaceService.shared.scanForFaces { done, total in
                continuation.yield((done, total))
            }
            continuation.finish()
        }
        Task { @MainActor in
            for await (done, total) in stream {
                faceScanProgress = (done, total)
            }
            isScanningFaces = false
            faceScanProgress = nil
            refreshPersons()
        }
    }

    /// Wipes all detected faces/persons and resets the scanned flag, so a future
    /// scan starts clean (e.g. after scanning a folder that was all noise).
    func resetFaceData() {
        Task { @MainActor in
            await FaceService.shared.resetFaceData()
            persons = []
            switch displayMode {
            case .people, .person: openAllPhotos()
            default: break
            }
        }
    }

    // MARK: - Text (OCR) search index

    /// Lowercased recognized-text per photo path, loaded from `photos.ocrText`.
    /// Kept off `PhotoItem` so the value type stays cheap to copy; the in-memory
    /// search filter consults this map directly.
    private var ocrTextByPath: [String: String] = [:]
    var isScanningText = false
    var textScanProgress: (done: Int, total: Int)?

    /// Loads the OCR text index from the DB into memory, then re-runs the search
    /// filter so freshly-indexed text becomes searchable immediately. Detached
    /// read → main-actor assign, mirroring `refreshPersons`.
    func refreshOcrText() {
        Task.detached { [weak self] in
            let map: [String: String] = (try? await DatabaseManager.shared.dbQueue.read { db in
                var result = [String: String]()
                let rows = try Row.fetchAll(db, sql: "SELECT url, ocrText FROM photos WHERE ocrText IS NOT NULL AND ocrText != ''")
                for row in rows {
                    if let url = row["url"] as String?, let text = row["ocrText"] as String? {
                        result[url] = text.lowercased()
                    }
                }
                return result
            }) ?? [:]
            guard let self else { return }
            await MainActor.run {
                self.ocrTextByPath = map
                self.rebuildFilteredPhotos()
            }
        }
    }

    /// Manual, throttled text scan. Updates progress live; refreshes the OCR
    /// index when done. Progress flows through an AsyncStream so the `@Sendable`
    /// scan callback captures only the (Sendable) continuation, never `self`.
    func scanForText() {
        guard !isScanningText else { return }
        isScanningText = true
        textScanProgress = (0, 0)

        let (stream, continuation) = AsyncStream.makeStream(of: (Int, Int).self)
        Task.detached {
            await OcrService.shared.scanForText { done, total in
                continuation.yield((done, total))
            }
            continuation.finish()
        }
        Task { @MainActor in
            for await (done, total) in stream {
                textScanProgress = (done, total)
            }
            isScanningText = false
            textScanProgress = nil
            refreshOcrText()
        }
    }

    /// Wipes all recognized text and resets the scanned flag, so a future scan
    /// starts clean.
    func resetTextData() {
        Task { @MainActor in
            await OcrService.shared.resetTextData()
            ocrTextByPath = [:]
            rebuildFilteredPhotos()
        }
    }

    func renamePerson(_ id: String, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let newName: String? = trimmed.isEmpty ? nil : trimmed
        if case let .person(current) = displayMode, current == id {
            folderName = newName ?? "Unnamed Person"
        }
        mutatePersonsThenRefresh { db in
            try db.execute(sql: "UPDATE persons SET name = ? WHERE id = ?", arguments: [newName, id])
        }
    }

    /// Folds `source` into `target`: repoint its faces, delete the empty person.
    func mergePerson(_ source: String, into target: String) {
        guard source != target else { return }
        mutatePersonsThenRefresh { db in
            try db.execute(sql: "UPDATE faces SET personId = ? WHERE personId = ?", arguments: [target, source])
            try db.execute(sql: "DELETE FROM persons WHERE id = ?", arguments: [source])
        }
        if case let .person(current) = displayMode, current == source {
            openPerson(target, name: personName(for: target))
        }
    }

    /// Hides a person from the sidebar without deleting its faces (so they aren't
    /// re-clustered into a fresh person on the next scan).
    func hidePerson(_ id: String) {
        if case let .person(current) = displayMode, current == id {
            openAllPhotos()
        }
        mutatePersonsThenRefresh { db in
            try db.execute(sql: "UPDATE persons SET isHidden = 1 WHERE id = ?", arguments: [id])
        }
    }

    private func mutatePersonsThenRefresh(_ mutation: @escaping @Sendable (Database) throws -> Void) {
        Task.detached { [weak self] in
            do {
                try await DatabaseManager.shared.dbQueue.write(mutation)
            } catch {
                let msg = error.localizedDescription
                guard let self else { return }
                await MainActor.run { self.lastError = msg }
                return
            }
            guard let self else { return }
            await MainActor.run { self.refreshPersons() }
        }
    }

    /// Opens the People browser (a destination view in the main area, not a
    /// sidebar list — clusters can run into the thousands on large libraries).
    func openPeople(pushHistory: Bool = true) {
        if pushHistory { pushNavigation() }
        displayMode = .people
        folderURL = nil
        folderName = "People"
        refreshPersons()
    }

    func openPerson(_ id: String, name: String?, pushHistory: Bool = true) {
        if pushHistory { pushNavigation() }
        displayMode = .person(id)
        folderURL = nil
        folderName = name ?? "Unnamed Person"
        loadPersonPhotos(id, preserveSelection: false)
    }

    /// Loads every library photo that contains a face assigned to this person.
    /// Reads the `faces` table by raw SQL (no record type needed); returns empty
    /// until the faces table exists (v9 migration / first scan).
    private func loadPersonPhotos(_ id: String, preserveSelection: Bool = false) {
        let snapshot = preserveSelection ? makeSelectionSnapshot() : nil
        if !preserveSelection {
            clearTemporarySelection()
            selectedPhoto = nil
        }
        loadGeneration += 1
        let generation = loadGeneration

        Task { @MainActor in
            isLoading = true
            let records: [PhotoRecord] = (try? await DatabaseManager.shared.dbQueue.read { db in
                try PhotoRecord
                    .filter(sql: "url IN (SELECT DISTINCT photoURL FROM faces WHERE personId = ?)",
                            arguments: [id])
                    .fetchAll(db)
            }) ?? []
            guard generation == loadGeneration else { return }

            photos = filterLibraryRecords(records)
            rebuildFilteredPhotos()
            restoreSelectionAfterReload(snapshot)
            await refreshPinnedPhotos()
            guard generation == loadGeneration else { return }
            isLoading = false
        }
    }

    // Incremented at the start of every load; in-flight tasks compare their
    // captured value before each write so a stale load can't clobber a newer view.
    private var loadGeneration = 0

    /// With automatic subfolders off, a folder view shows the folder's own
    /// photos plus those of any explicitly watched descendant folders —
    /// unchecked subfolders stay hidden.
    private func scopeFolderRecords(_ records: [PhotoRecord], folderPath: String) -> [PhotoRecord] {
        guard !settings.includeSubfolders else { return records }
        let watchedPaths = Set(libraryFolders.map(\.path))
        let prefix = folderPath + "/"
        return records.filter { record in
            record.folderPath == folderPath
                || (record.folderPath.hasPrefix(prefix) && watchedPaths.contains(record.folderPath))
        }
    }

    private func loadPhotos(from url: URL, preserveSelection: Bool = false) {
        let snapshot = preserveSelection ? makeSelectionSnapshot() : nil
        if !preserveSelection {
            clearTemporarySelection()
            selectedPhoto = nil
        }
        loadGeneration += 1
        let generation = loadGeneration

        Task { @MainActor in
            let cachedRecords = await PhotoIndexer.shared.fetchRecords(forFolderPath: url.path)
            guard generation == loadGeneration else { return }
            let cachedScoped = scopeFolderRecords(cachedRecords, folderPath: url.path)
            let hasCache = !cachedScoped.isEmpty
            if hasCache {
                photos = cachedScoped.map { $0.toPhotoItem() }
                rebuildFilteredPhotos()
                restoreSelectionAfterReload(snapshot)
                isLoading = false
            } else {
                isLoading = true
                photos = []
                rebuildFilteredPhotos()
                restoreSelectionAfterReload(snapshot)
            }

            await PhotoIndexer.shared.indexFolder(url, includeSubfolders: settings.includeSubfolders)
            guard generation == loadGeneration else { return }

            let freshRecords = await PhotoIndexer.shared.fetchRecords(forFolderPath: url.path)
            guard generation == loadGeneration else { return }
            photos = scopeFolderRecords(freshRecords, folderPath: url.path).map { $0.toPhotoItem() }
            rebuildFilteredPhotos()
            restoreSelectionAfterReload(snapshot)

            await refreshPinnedPhotos()
            guard generation == loadGeneration else { return }
            isLoading = false
        }
    }

    func removeFolderFromLibrary(_ folder: LibraryFolder) {
        let prefix = folder.path + "/"
        writeToDBAsync { db in
            try db.execute(literal: "DELETE FROM photos WHERE folderPath = \(folder.path)")
            try db.execute(literal: "DELETE FROM photos WHERE folderPath LIKE \(prefix + "%")")
        }

        libraryFolders.removeAll { $0.id == folder.id }
        saveLibrary()

        excludedLeafPaths = excludedLeafPaths.filter { !$0.hasPrefix(prefix) && $0 != folder.path }
        saveExcludedLeafPaths()
        refreshSidebarGroups()

        if case let .folder(current) = displayMode, current.path == folder.path || current.path.hasPrefix(prefix) {
            if libraryFolders.isEmpty {
                folderURL = nil
                folderName = nil
                photos = []
                rebuildFilteredPhotos()
                clearAllFromTray()
                displayMode = .library
            } else {
                openAllPhotos()
            }
        } else if case .year = displayMode {
            if libraryFolders.isEmpty {
                folderURL = nil
                folderName = nil
                photos = []
                rebuildFilteredPhotos()
                clearAllFromTray()
                displayMode = .library
            } else {
                refreshCurrentView()
            }
        } else if displayMode == .library {
            loadAllLibraryPhotos()
        } else if case .dot = displayMode {
            loadDotColorPhotos()
        } else if displayMode == .tray {
            openTrayPhotos()
        }
    }

    func excludeLeafFolder(_ path: String) {
        excludedLeafPaths.insert(path)
        saveExcludedLeafPaths()

        writeToDBAsync { db in
            try db.execute(literal: "DELETE FROM photos WHERE folderPath = \(path)")
        }

        if case let .folder(current) = displayMode, current.path == path {
            photos = []
            rebuildFilteredPhotos()
        } else if case .year = displayMode {
            refreshCurrentView()
        } else if displayMode == .library {
            loadAllLibraryPhotos()
        } else if displayMode == .tray {
            openTrayPhotos()
        }
        refreshSidebarGroups()
    }

    func openLibraryFolderByPath(_ path: String) {
        let folder = LibraryFolder(name: URL(fileURLWithPath: path).lastPathComponent, path: path)
        openLibraryFolder(folder)
    }

    func openYearPhotos(_ year: Int, pushHistory: Bool = true) {
        if pushHistory { pushNavigation() }
        displayMode = .year(year)
        folderURL = nil
        folderName = String(year)
        loadPhotosForYear(year, preserveSelection: false)
    }

    private func filterYearRecords(_ records: [PhotoRecord], year: Int) -> [PhotoItem] {
        let includeSubfolders = settings.includeSubfolders
        let validPrefixes = libraryFolders.map { $0.path + "/" }

        let scoped = records.filter { record in
            guard !excludedLeafPaths.contains(record.folderPath) else { return false }
            let isDirect = libraryFolders.contains { $0.path == record.folderPath }
            let isNested = includeSubfolders && validPrefixes.contains { record.folderPath.hasPrefix($0) }
            return isDirect || isNested
        }

        // Folder-centric: a year view contains WHOLE folders whose majority
        // year matches (ties → newer year) — same rule as sidebar and grid,
        // so all three views always agree on where a folder lives.
        var yearCounts: [String: [Int: Int]] = [:]
        for record in scoped {
            guard let y = record.dayKey.flatMap({ Int($0.prefix(4)) }) else { continue }
            yearCounts[record.folderPath, default: [:]][y, default: 0] += 1
        }
        let matchingFolders = Set(yearCounts.compactMap { path, counts -> String? in
            return Self.majorityYear(from: counts) == year ? path : nil
        })

        return scoped
            .filter { matchingFolders.contains($0.folderPath) }
            .map { $0.toPhotoItem() }
    }

    private func loadPhotosForYear(_ year: Int, preserveSelection: Bool = false) {
        let snapshot = preserveSelection ? makeSelectionSnapshot() : nil
        if !preserveSelection {
            clearTemporarySelection()
            selectedPhoto = nil
        }
        loadGeneration += 1
        let generation = loadGeneration

        Task { @MainActor in
            let cachedRecords = await PhotoIndexer.shared.fetchAllRecords()
            guard generation == loadGeneration else { return }
            let cachedItems = filterYearRecords(cachedRecords, year: year)
            let hasCache = !cachedItems.isEmpty
            if hasCache {
                photos = cachedItems
                rebuildFilteredPhotos()
                restoreSelectionAfterReload(snapshot)
                isLoading = false
            } else {
                isLoading = true
                photos = []
                rebuildFilteredPhotos()
                restoreSelectionAfterReload(snapshot)
            }

            await PhotoIndexer.shared.indexAllFolders(libraryFolders, excludedPaths: excludedLeafPaths, includeSubfolders: settings.includeSubfolders)
            guard generation == loadGeneration else { return }

            let freshRecords = await PhotoIndexer.shared.fetchAllRecords()
            guard generation == loadGeneration else { return }
            photos = filterYearRecords(freshRecords, year: year)
            rebuildFilteredPhotos()
            restoreSelectionAfterReload(snapshot)

            await refreshPinnedPhotos()
            guard generation == loadGeneration else { return }
            refreshSidebarGroups()
            isLoading = false
        }
    }

    /// Recomputes which dot colors exist across the **entire library** (not just the
    /// currently-loaded/filtered `photos` array). Reading from the DB keeps the sidebar's
    /// dot-color row stable when browsing a single dot album — otherwise colors absent from
    /// the filtered subset would disappear from the sidebar.
    private func refreshUsedDotColors() {
        let showVideos = settings.showVideos
        Task.detached { [weak self] in
            let bits = (try? await DatabaseManager.shared.dbQueue.read { db in
                if showVideos {
                    return try Int.fetchAll(db, sql: "SELECT DISTINCT dotColor FROM photos WHERE dotColor != 0")
                        .reduce(0, |)
                }
                return try Int.fetchAll(
                    db,
                    sql: "SELECT DISTINCT dotColor FROM photos WHERE dotColor != 0 AND mediaKind != ?",
                    arguments: [MediaKind.video.rawValue]
                ).reduce(0, |)
            }) ?? 0
            guard let self else { return }
            await MainActor.run { self.applyUsedDotColorBits(bits) }
        }
    }

    private func refreshHasGeotaggedPhotos() {
        Task.detached { [weak self] in
            let exists = (try? await DatabaseManager.shared.dbQueue.read { db in
                try Bool.fetchOne(db, sql: "SELECT EXISTS(SELECT 1 FROM photos WHERE latitude IS NOT NULL)")
            }) ?? false
            guard let self else { return }
            await MainActor.run { self.hasGeotaggedPhotos = exists }
        }
    }

    /// Runs a dot-color mutation and recomputes `usedDotColors` in a single serialized
    /// transaction, so the recompute always reflects the just-written change (no read-after-write
    /// race against a separate `writeToDBAsync` task).
    private func mutateDotColorsThenRefresh(_ mutation: @escaping @Sendable (Database) throws -> Void) {
        let showVideos = settings.showVideos
        Task.detached { [weak self] in
            do {
                let bits = try await DatabaseManager.shared.dbQueue.write { db -> Int in
                    try mutation(db)
                    if showVideos {
                        return try Int.fetchAll(db, sql: "SELECT DISTINCT dotColor FROM photos WHERE dotColor != 0")
                            .reduce(0, |)
                    }
                    return try Int.fetchAll(
                        db,
                        sql: "SELECT DISTINCT dotColor FROM photos WHERE dotColor != 0 AND mediaKind != ?",
                        arguments: [MediaKind.video.rawValue]
                    ).reduce(0, |)
                }
                guard let self else { return }
                await MainActor.run { self.applyUsedDotColorBits(bits) }
            } catch {
                let msg = error.localizedDescription
                guard let self else { return }
                await MainActor.run { self.lastError = msg }
            }
        }
    }

    @MainActor
    private func applyUsedDotColorBits(_ bits: Int) {
        var result = Set<Int>()
        for i in 1...8 where bits & DotColor.bitMask(for: i) != 0 { result.insert(i) }
        usedDotColors = result
    }

    func refreshSidebarGroups() {
        guard !libraryFolders.isEmpty else {
            sidebarGroups = []
            usedDotColors = []
            hasGeotaggedPhotos = false
            return
        }

        refreshUsedDotColors()
        refreshHasGeotaggedPhotos()
        refreshPersons()
        refreshOcrText()

        let grouping = sidebarGrouping
        let excluded = excludedLeafPaths
        let includeSubfolders = settings.includeSubfolders
        let showVideos = settings.showVideos
        let watchedPaths = Set(libraryFolders.map(\.path))

        Task.detached(priority: .userInitiated) { [weak self] in
            var dbPaths: [String] = (try? await DatabaseManager.shared.dbQueue.read { db in
                if showVideos {
                    return try String.fetchAll(db, sql: "SELECT DISTINCT folderPath FROM photos ORDER BY folderPath")
                }
                return try String.fetchAll(
                    db,
                    sql: "SELECT DISTINCT folderPath FROM photos WHERE mediaKind != ? ORDER BY folderPath",
                    arguments: [MediaKind.video.rawValue]
                )
            }) ?? []
            // With subfolders off, hide subfolder entries left by earlier scans
            if !includeSubfolders {
                dbPaths = dbPaths.filter { watchedPaths.contains($0) }
            }

            let countRows: [Row] = (try? await DatabaseManager.shared.dbQueue.read { db in
                if showVideos {
                    return try Row.fetchAll(db, sql: "SELECT folderPath, COUNT(*) AS cnt FROM photos GROUP BY folderPath")
                }
                return try Row.fetchAll(
                    db,
                    sql: "SELECT folderPath, COUNT(*) AS cnt FROM photos WHERE mediaKind != ? GROUP BY folderPath",
                    arguments: [MediaKind.video.rawValue]
                )
            }) ?? []
            let counts: [String: Int] = countRows.reduce(into: [:]) { $0[$1["folderPath"]] = $1["cnt"] }

            let leafFolders = dbPaths
                .filter { !excluded.contains($0) }
                .map { path in
                    LibraryFolder(name: URL(fileURLWithPath: path).lastPathComponent, path: path)
                }
                .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }

            let groups: [SidebarGroup]
            switch grouping {
            case .bySource:
                let grouped = Dictionary(grouping: leafFolders) { folder -> String in
                    URL(fileURLWithPath: folder.path).deletingLastPathComponent().path
                }
                groups = grouped.compactMap { parentPath, folders -> SidebarGroup? in
                    let children = folders.sorted {
                        $0.name.localizedStandardCompare($1.name) == .orderedAscending
                    }
                    let parentName = URL(fileURLWithPath: parentPath).lastPathComponent
                    let count = counts[parentPath] ?? 0
                    return children.isEmpty ? nil : SidebarGroup(title: parentName, folders: children, rootPath: parentPath, photoCount: count)
                }.sorted {
                    $0.title.localizedStandardCompare($1.title) == .orderedAscending
                }

            case .byYear:
                // Majority year per folder (ties → newer year) — must match
                // the grid's libraryYearGroups rule exactly
                let folderYears: [String: Int] = (try? await DatabaseManager.shared.dbQueue.read { db in
                    let rows: [Row]
                    if showVideos {
                        rows = try Row.fetchAll(db, sql: """
                            SELECT folderPath,
                                   CAST(strftime('%Y', COALESCE(dateTakenOriginal, modificationDate)) AS INTEGER) AS year,
                                   COUNT(*) AS cnt
                            FROM photos
                            GROUP BY folderPath, year
                        """)
                    } else {
                        rows = try Row.fetchAll(
                            db,
                            sql: """
                                SELECT folderPath,
                                       CAST(strftime('%Y', COALESCE(dateTakenOriginal, modificationDate)) AS INTEGER) AS year,
                                       COUNT(*) AS cnt
                                FROM photos
                                WHERE mediaKind != ?
                                GROUP BY folderPath, year
                            """,
                            arguments: [MediaKind.video.rawValue]
                        )
                    }
                    var best: [String: (year: Int, cnt: Int)] = [:]
                    for row in rows {
                        guard let path = row["folderPath"] as String?,
                              let year = row["year"] as Int?,
                              let cnt = row["cnt"] as Int? else { continue }
                        if let current = best[path] {
                            if (cnt, year) > (current.cnt, current.year) {
                                best[path] = (year, cnt)
                            }
                        } else {
                            best[path] = (year, cnt)
                        }
                    }
                    return best.mapValues { $0.year }
                }) ?? [:]

                let grouped = Dictionary(grouping: leafFolders) { folder -> String in
                    if let year = folderYears[folder.path] {
                        return String(year)
                    }
                    return "Unknown"
                }

                var result: [SidebarGroup] = grouped.compactMap { year, folders in
                    let sorted = folders.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
                    guard !sorted.isEmpty else { return nil }
                    let yearCount = sorted.reduce(0) { $0 + (counts[$1.path] ?? 0) }
                    return SidebarGroup(title: year, folders: sorted, rootPath: "year:\(year)", photoCount: yearCount)
                }

                result.sort { a, b in
                    if a.title == "Unknown" { return false }
                    if b.title == "Unknown" { return true }
                    return a.title > b.title
                }

                groups = result
            }

            await MainActor.run { [weak self] in
                guard let self else { return }
                self.photoCounts = counts
                self.sidebarGroups = groups
            }
        }
    }

    // MARK: - Persistence

    func saveExcludedLeafPaths() {
        UserDefaults.standard.set(Array(excludedLeafPaths), forKey: excludedLeafPathsKey)
    }

    private func loadExcludedLeafPaths() {
        guard let array = UserDefaults.standard.array(forKey: excludedLeafPathsKey) as? [String] else { return }
        excludedLeafPaths = Set(array)
        refreshSidebarGroups()
    }

    func saveLibrary() {
        guard let data = try? JSONEncoder().encode(libraryFolders) else { return }
        UserDefaults.standard.set(data, forKey: libraryKey)
        setupFileWatcher()
    }

    private func loadLibrary() {
        guard let data = UserDefaults.standard.data(forKey: libraryKey),
              let folders = try? JSONDecoder().decode([LibraryFolder].self, from: data)
        else { return }
        libraryFolders = folders
        refreshSidebarGroups()
        setupFileWatcher()
    }

    private func setupFileWatcher() {
        fileWatcher?.stop()
        let paths = libraryFolders.compactMap { $0.url?.path }
        guard !paths.isEmpty else {
            fileWatcher = nil
            return
        }
        fileWatcher = FileSystemWatcher { [weak self] _ in
            self?.handleFileSystemChange()
        }
        fileWatcher?.watch(paths: paths)
    }

    private func handleFileSystemChange() {
        watcherDebounceTask?.cancel()
        watcherDebounceTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard !Task.isCancelled, let self else { return }
            // Reloading photos mid-edit would orphan selectedPhoto and break
            // crop/straighten overlay state — re-check until editing ends.
            while self.isEditing {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                guard !Task.isCancelled else { return }
            }
            self.refreshCurrentView()
        }
    }

    private func filterLibraryRecords(_ records: [PhotoRecord]) -> [PhotoItem] {
        // With subfolders off, only photos directly inside a watched folder
        // count — stale subfolder records stay in the DB but are hidden.
        let includeSubfolders = settings.includeSubfolders
        let validPrefixes = libraryFolders.map { $0.path + "/" }
        return records.filter { record in
            guard !excludedLeafPaths.contains(record.folderPath) else { return false }
            if libraryFolders.contains(where: { $0.path == record.folderPath }) { return true }
            guard includeSubfolders else { return false }
            return validPrefixes.contains { record.folderPath.hasPrefix($0) }
        }.map { $0.toPhotoItem() }
    }

    private func refreshPinnedPhotos() async {
        let pinnedRecords = await PhotoIndexer.shared.fetchPinnedRecords()
        let pinnedItems = pinnedRecords.map { $0.toPhotoItem() }
        pinnedPhotos = Set(pinnedItems)
        let existingOrder = trayPhotoOrder.filter { pinnedPhotos.contains($0) }
        let newPins = pinnedItems.filter { !existingOrder.contains($0) }
        trayPhotoOrder = existingOrder + newPins
    }

    private func loadAllLibraryPhotos(preserveSelection: Bool = false) {
        let snapshot = preserveSelection ? makeSelectionSnapshot() : nil
        if !preserveSelection {
            clearTemporarySelection()
            selectedPhoto = nil
        }
        loadGeneration += 1
        let generation = loadGeneration

        Task { @MainActor in
            let cachedRecords = await PhotoIndexer.shared.fetchAllRecords()
            guard generation == loadGeneration else { return }
            let cachedItems = filterLibraryRecords(cachedRecords)
            let hasCache = !cachedItems.isEmpty
            if hasCache {
                photos = cachedItems
                rebuildFilteredPhotos()
                restoreSelectionAfterReload(snapshot)
                isLoading = false
            } else {
                isLoading = true
                photos = []
                rebuildFilteredPhotos()
                restoreSelectionAfterReload(snapshot)
            }

            await PhotoIndexer.shared.indexAllFolders(libraryFolders, excludedPaths: excludedLeafPaths, includeSubfolders: settings.includeSubfolders)
            guard generation == loadGeneration else { return }

            let freshRecords = await PhotoIndexer.shared.fetchAllRecords()
            guard generation == loadGeneration else { return }
            photos = filterLibraryRecords(freshRecords)
            rebuildFilteredPhotos()
            restoreSelectionAfterReload(snapshot)

            await refreshPinnedPhotos()
            guard generation == loadGeneration else { return }
            refreshSidebarGroups()
            isLoading = false
        }
    }

    private func loadDotColorPhotos(preserveSelection: Bool = false) {
        guard case let .dot(color) = displayMode else { return }
        let bit = DotColor.bitMask(for: color)
        let snapshot = preserveSelection ? makeSelectionSnapshot() : nil
        if !preserveSelection {
            clearTemporarySelection()
            selectedPhoto = nil
        }

        Task { @MainActor in
            isLoading = true
            let allRecords: [PhotoRecord] = (try? await DatabaseManager.shared.dbQueue.read { db in
                try PhotoRecord.filter(literal: "(dotColor & \(bit)) != 0").fetchAll(db)
            }) ?? []

            photos = filterLibraryRecords(allRecords)
            rebuildFilteredPhotos()
            restoreSelectionAfterReload(snapshot)

            await refreshPinnedPhotos()
            refreshSidebarGroups()
            isLoading = false
        }
    }

    // MARK: - Edit

    var isEditing = false
    var editPayload = EditPayload()
    var previewImage: NSImage?
    private var renderTask: Task<Void, Never>?

    // Caches FileManager.fileExists checks for sidecar files — called per
    // visible cell on every grid render, so uncached it is a disk hit per cell.
    // @ObservationIgnored: mutated during view body evaluation; observation
    // tracking here would invalidate views mid-render.
    @ObservationIgnored private var editExistsCache: [String: Bool] = [:]

    func hasEdits(for url: URL) -> Bool {
        let key = url.path
        if let cached = editExistsCache[key] { return cached }
        let exists = EditStore.exists(for: url)
        editExistsCache[key] = exists
        return exists
    }

    // Sidecar rotation (90° steps) so thumbnails can show the edited
    // orientation. Cached per path — a sidecar JSON read per cell per
    // render would be a disk hit in the scroll path.
    @ObservationIgnored private var editRotationCache: [String: Int] = [:]

    func editRotation(for url: URL) -> Int {
        let key = url.path
        if let cached = editRotationCache[key] { return cached }
        let rotation = hasEdits(for: url) ? (EditStore.load(for: url)?.rotation ?? 0) : 0
        editRotationCache[key] = rotation
        return rotation
    }

    func invalidateEditCache(for url: URL) {
        editExistsCache.removeValue(forKey: url.path)
        editRotationCache.removeValue(forKey: url.path)
    }

    var histogramData: HistogramData?
    var histogramMode: HistogramView.HistogramMode = .rgb
    private var histogramPhotoID: String? = nil

    var isAutoEnhancing = false

    var isCropping = false
    var cropRect = CropRect.full
    var cropAspectRatio: CGFloat? = nil

    var isStraightening = false
    private var priorStraightenAngle: Double = 0.0

    private var undoStacks: [String: [EditPayload]] = [:]
    private var redoStacks: [String: [EditPayload]] = [:]
    private let maxUndoLevels = 50

    var canUndo: Bool {
        guard let id = selectedPhoto?.id else { return false }
        return !(undoStacks[id] ?? []).isEmpty
    }

    var canRedo: Bool {
        guard let id = selectedPhoto?.id else { return false }
        return !(redoStacks[id] ?? []).isEmpty
    }

    func pushUndoSnapshot() {
        guard isEditing, let id = selectedPhoto?.id else { return }
        undoStacks[id, default: []].append(editPayload)
        if undoStacks[id]!.count > maxUndoLevels { undoStacks[id]!.removeFirst() }
        redoStacks[id, default: []].removeAll()
    }

    func undoEdit() {
        guard isEditing, let id = selectedPhoto?.id,
              var stack = undoStacks[id], !stack.isEmpty else { return }
        exitCropOrStraightenMode()
        redoStacks[id, default: []].append(editPayload)
        editPayload = stack.removeLast()
        undoStacks[id] = stack
        schedulePreviewRender()
    }

    func redoEdit() {
        guard isEditing, let id = selectedPhoto?.id,
              var stack = redoStacks[id], !stack.isEmpty else { return }
        exitCropOrStraightenMode()
        undoStacks[id, default: []].append(editPayload)
        editPayload = stack.removeLast()
        redoStacks[id] = stack
        schedulePreviewRender()
    }

    private func exitCropOrStraightenMode() {
        if isCropping { cancelCrop() }
        if isStraightening { cancelStraighten() }
    }

    var effectiveCropImageSize: CGSize {
        guard let photo = selectedPhoto else { return CGSize(width: 400, height: 400) }
        let w = CGFloat(photo.width ?? 400)
        let h = CGFloat(photo.height ?? 400)
        if editPayload.rotation == 90 || editPayload.rotation == 270 {
            return CGSize(width: h, height: w)
        }
        return CGSize(width: w, height: h)
    }

    var originalCropAspectRatio: CGFloat? {
        guard let photo = selectedPhoto else { return nil }
        let w = CGFloat(photo.width ?? 400)
        let h = CGFloat(photo.height ?? 400)
        if editPayload.rotation == 90 || editPayload.rotation == 270 {
            return h / w
        }
        return w / h
    }

    func setCropAspectRatio(_ ratio: CGFloat?) {
        cropAspectRatio = ratio
        guard let ratio = ratio else { return }

        let current = cropRect
        let cx = current.x + current.width / 2
        let cy = current.y + current.height / 2

        var maxW = min(cx * 2, (1.0 - cx) * 2)
        var maxH = maxW / ratio
        if maxH > min(cy * 2, (1.0 - cy) * 2) {
            maxH = min(cy * 2, (1.0 - cy) * 2)
            maxW = maxH * ratio
        }

        cropRect = CropRect(x: cx - maxW / 2, y: cy - maxH / 2, width: maxW, height: maxH).clamped()
    }

    func flipCropAspectRatio() {
        guard let ratio = cropAspectRatio else { return }
        setCropAspectRatio(1.0 / ratio)
    }

    func enterCropMode() {
        if isStraightening { cancelStraighten() }
        cropRect = editPayload.cropRect ?? CropRect.full
        cropAspectRatio = nil
        isCropping = true
        schedulePreviewRender()
    }

    func exitCropMode() {
        isCropping = false
    }

    func applyCrop() {
        pushUndoSnapshot()
        editPayload.cropRect = cropRect.isFull ? nil : cropRect
        isCropping = false
        schedulePreviewRender()
    }

    func cancelCrop() {
        cropRect = editPayload.cropRect ?? CropRect.full
        isCropping = false
    }

    func enterStraightenMode() {
        if isCropping { cancelCrop() }
        priorStraightenAngle = editPayload.straightenAngle
        isStraightening = true
        schedulePreviewRender()
    }

    func applyStraighten() {
        isStraightening = false
        schedulePreviewRender()
    }

    func cancelStraighten() {
        editPayload.straightenAngle = priorStraightenAngle
        isStraightening = false
        schedulePreviewRender()
    }

    func applyAutoContrast() {
        guard let photo = selectedPhoto, !isAutoEnhancing else { return }
        pushUndoSnapshot()
        isAutoEnhancing = true
        let url = photo.url
        let payload = editPayload
        Task.detached(priority: .userInitiated) {
            guard let values = ImageProcessor.suggestAutoAdjustments(from: url, payload: payload, mode: .contrast) else {
                await MainActor.run { self.isAutoEnhancing = false }
                return
            }
            await MainActor.run {
                self.editPayload.removeLayer(ofType: .autoContrast)
                self.editPayload.removeLayer(ofType: .autoColor)
                self.editPayload.removeLayer(ofType: .autoLucky)
                var layer = AdjustmentLayer(type: .autoContrast)
                layer.parameters = [
                    "brightness": values.brightness,
                    "contrast": values.contrast,
                    "exposure": values.exposure
                ]
                self.editPayload.addLayer(layer)
                self.isAutoEnhancing = false
                self.schedulePreviewRender()
            }
        }
    }

    func applyAutoColor() {
        guard let photo = selectedPhoto, !isAutoEnhancing else { return }
        pushUndoSnapshot()
        isAutoEnhancing = true
        let url = photo.url
        let payload = editPayload
        Task.detached(priority: .userInitiated) {
            guard let values = ImageProcessor.suggestAutoAdjustments(from: url, payload: payload, mode: .color) else {
                await MainActor.run { self.isAutoEnhancing = false }
                return
            }
            await MainActor.run {
                self.editPayload.removeLayer(ofType: .autoContrast)
                self.editPayload.removeLayer(ofType: .autoColor)
                self.editPayload.removeLayer(ofType: .autoLucky)
                var layer = AdjustmentLayer(type: .autoColor)
                layer.parameters = [
                    "saturation": values.saturation,
                    "temp": values.colorTemperature,
                    "tint": values.colorTint
                ]
                self.editPayload.addLayer(layer)
                self.isAutoEnhancing = false
                self.schedulePreviewRender()
            }
        }
    }

    func applyImFeelingLucky() {
        guard let photo = selectedPhoto, !isAutoEnhancing else { return }
        pushUndoSnapshot()
        isAutoEnhancing = true
        let url = photo.url
        let payload = editPayload
        Task.detached(priority: .userInitiated) {
            guard let values = ImageProcessor.suggestAutoAdjustments(from: url, payload: payload, mode: .full) else {
                await MainActor.run { self.isAutoEnhancing = false }
                return
            }
            await MainActor.run {
                self.editPayload.removeLayer(ofType: .autoContrast)
                self.editPayload.removeLayer(ofType: .autoColor)
                self.editPayload.removeLayer(ofType: .autoLucky)
                var layer = AdjustmentLayer(type: .autoLucky)
                layer.parameters = [
                    "brightness": values.brightness,
                    "contrast": values.contrast,
                    "exposure": values.exposure,
                    "saturation": values.saturation,
                    "temp": values.colorTemperature,
                    "tint": values.colorTint
                ]
                self.editPayload.addLayer(layer)
                self.isAutoEnhancing = false
                self.schedulePreviewRender()
            }
        }
    }

    func toggleEditMode() {
        if let photo = selectedPhoto, photo.isVideo {
            showAlert(message: "Videos can't be edited here. Open them in Quick Look instead.")
            return
        }
        if !isEditing, let photo = selectedPhoto, photo.isRaw {
            showAlert(message: "RAW files can't be edited.\n\nPicshurs can view \(photo.url.pathExtension.uppercased()) files, but editing is only supported for JPEG, PNG, HEIC, and TIFF. Convert the file first if you need to edit it.")
            return
        }
        isEditing.toggle()
        if isEditing {
            loadSidecarForSelectedPhoto()
            schedulePreviewRender()
        } else {
            doneEditing()
        }
    }

    func doneEditing() {
        if isStraightening { applyStraighten() }
        if isCropping { applyCrop() }
        if let photo = selectedPhoto, editPayload.hasAdjustments {
            do {
                try EditStore.save(editPayload, for: photo.url)
            } catch {
                lastError = "Failed to save edits: \(error.localizedDescription)"
            }
            invalidateEditCache(for: photo.url)
        } else if let photo = selectedPhoto {
            EditStore.delete(for: photo.url)
            invalidateEditCache(for: photo.url)
        }
        isEditing = false
        renderTask?.cancel()
        renderTask = Task { @MainActor in
            await renderPreview()
        }
    }

    func loadSidecarForSelectedPhoto() {
        guard let photo = selectedPhoto else {
            editPayload = EditPayload()
            previewImage = nil
            histogramData = nil
            histogramPhotoID = nil
            return
        }
        guard photo.isImage else {
            editPayload = EditPayload()
            previewImage = nil
            histogramData = nil
            histogramPhotoID = nil
            return
        }
        if let stored = EditStore.load(for: photo.url) {
            editPayload = stored
            if !isEditing {
                schedulePreviewRender()
            }
        } else {
            editPayload = EditPayload()
            previewImage = nil
        }
        refreshHistogram(for: photo)
    }

    private func refreshHistogram(for photo: PhotoItem) {
        guard photo.isImage else {
            histogramData = nil
            histogramPhotoID = photo.id
            return
        }
        guard histogramPhotoID != photo.id else { return }
        histogramPhotoID = photo.id
        let photoID = photo.id
        let photoURL = photo.url
        Task.detached(priority: .userInitiated) {
            guard let data = HistogramService.compute(from: photoURL) else { return }
            await MainActor.run {
                if self.selectedPhoto?.id == photoID {
                    self.histogramData = data
                }
            }
        }
    }

    func schedulePreviewRender() {
        guard selectedPhoto?.isImage != false else {
            previewImage = nil
            renderTask?.cancel()
            return
        }
        renderTask?.cancel()
        renderTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 80_000_000)
            guard !Task.isCancelled else { return }
            await renderPreview(skipCrop: isCropping || isStraightening)
        }
    }

    private func renderPreview(skipCrop: Bool = false) async {
        guard let photo = selectedPhoto, photo.isImage else {
            previewImage = nil
            return
        }
        let photoID = photo.id
        let photoURL = photo.url
        let payload = editPayload
        let screenSize = NSScreen.main?.visibleFrame.size ?? CGSize(width: 1200, height: 800)
        let displaySize = CGSize(width: screenSize.width * 0.7, height: screenSize.height * 0.7)
        let image = await Task.detached(priority: .userInitiated) {
            ImageProcessor.renderPreview(from: photoURL, payload: payload, displaySize: displaySize, skipCrop: skipCrop)
        }.value
        if selectedPhoto?.id == photoID {
            previewImage = image
        }
    }

    // MARK: - Edit / Export

    private static let rawExtensions = PhotoItem.rawExtensions

    func saveEditsToOriginal(photo: PhotoItem, payload: EditPayload) {
        guard photo.isImage else {
            showAlert(message: "Save to Original is only available for photos.")
            return
        }
        if isCropping { applyCrop() }
        if isStraightening { applyStraighten() }
        let finalPayload = editPayload

        guard photo.url.isFileURL else {
            showAlert(message: "Invalid file path.")
            return
        }
        guard FileManager.default.fileExists(atPath: photo.url.path) else {
            showAlert(message: "The original file no longer exists at: \(photo.url.path)")
            return
        }

        guard finalPayload.hasAdjustments else {
            EditStore.delete(for: photo.url)
            invalidateEditCache(for: photo.url)
            return
        }

        let ext = photo.url.pathExtension.lowercased()
        if Self.rawExtensions.contains(ext) {
            showAlert(message: "Save to Original is not supported for RAW files. Use Export Edited Copy instead.")
            return
        }

        guard let cgImage = ImageProcessor.renderFullResolution(from: photo.url, payload: finalPayload) else {
            showAlert(message: "Failed to render edited image.")
            return
        }

        let uti = Self.utType(for: ext)
        let tempDir = photo.url.deletingLastPathComponent()
        let tempURL = tempDir.appendingPathComponent(".picshurs_edit_\(UUID().uuidString).\(ext)")
        var backupURL: URL?

        var extra: [CFString: Any] = [:]
        if ext == "jpg" || ext == "jpeg" {
            extra[kCGImageDestinationLossyCompressionQuality] = 1.0
        }
        let properties = MetadataPreserver.buildOutputProperties(from: photo.url, extraProperties: extra)

        guard let destination = CGImageDestinationCreateWithURL(tempURL as CFURL, uti, 1, nil) else {
            showAlert(message: "Failed to create image destination.")
            return
        }
        CGImageDestinationAddImage(destination, cgImage, properties as CFDictionary)
        if !CGImageDestinationFinalize(destination) {
            try? FileManager.default.removeItem(at: tempURL)
            showAlert(message: "Failed to write edited image.")
            return
        }

        // 2. Validate temp file
        guard let validatedImage = NSImage(contentsOf: tempURL),
              validatedImage.size.width > 0,
              validatedImage.size.height > 0 else {
            try? FileManager.default.removeItem(at: tempURL)
            showAlert(message: "Generated image file is invalid or corrupted.")
            return
        }

        // 3. Create backup of original BEFORE modification
        let backupDir = tempDir.appendingPathComponent(".picshurs_backups", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: backupDir, withIntermediateDirectories: true)
            backupURL = backupDir.appendingPathComponent(UUID().uuidString + "." + ext)
            try FileManager.default.copyItem(at: photo.url, to: backupURL!)
        } catch {
            try? FileManager.default.removeItem(at: tempURL)
            showAlert(message: "Failed to create backup. Save aborted to protect the original file.")
            return
        }

        // 4. Atomic swap using replaceItemAt (eliminates the remove+move gap)
        do {
            guard FileManager.default.fileExists(atPath: photo.url.path) else {
                showAlert(message: "The original file was moved or deleted during processing.")
                try? FileManager.default.removeItem(at: tempURL)
                return
            }

            _ = try FileManager.default.replaceItemAt(photo.url, withItemAt: tempURL, backupItemName: nil, options: [])

            // 5. Validate the new file at the original location
            guard FileManager.default.fileExists(atPath: photo.url.path),
                  let verifyImage = NSImage(contentsOf: photo.url),
                  verifyImage.size.width > 0,
                  verifyImage.size.height > 0 else {
                // Restore from backup
                if let backup = backupURL, FileManager.default.fileExists(atPath: backup.path) {
                    _ = try? FileManager.default.replaceItemAt(photo.url, withItemAt: backup, backupItemName: nil, options: [])
                }
                showAlert(message: "Saved file failed validation. Original has been restored from backup.")
                return
            }

            // 6. Success — clean up
            if let backup = backupURL { try? FileManager.default.removeItem(at: backup) }
            EditStore.delete(for: photo.url)
            invalidateEditCache(for: photo.url)
            refreshPhotoMetadata(photo: photo)
            editPayload.reset()
            doneEditing()

        } catch {
            // Restore from backup on any error
            if let backup = backupURL, FileManager.default.fileExists(atPath: backup.path) {
                _ = try? FileManager.default.replaceItemAt(photo.url, withItemAt: backup, backupItemName: nil, options: [])
            }
            try? FileManager.default.removeItem(at: tempURL)
            showAlert(message: "Failed to save: \(error.localizedDescription). Original restored from backup.")
        }
    }

    /// Exports an edited copy to a user-chosen location.
    func exportEditedCopy(photo: PhotoItem, payload: EditPayload) {
        guard photo.isImage else {
            showAlert(message: "Export Edited Copy is only available for photos.")
            return
        }
        // Validate file URL is valid and accessible
        guard photo.url.isFileURL else {
            showAlert(message: "Invalid file path: \(photo.url.absoluteString)")
            return
        }
        
        // Validate file exists before attempting any operations
        guard FileManager.default.fileExists(atPath: photo.url.path) else {
            showAlert(message: "The original file no longer exists at: \(photo.url.path)")
            return
        }

        guard payload.hasAdjustments else {
            // Just copy original; NSSavePanel already confirmed overwrite if dest exists.
            let panel = NSSavePanel()
            panel.nameFieldStringValue = photo.filename
            panel.canCreateDirectories = true
            guard panel.runModal() == .OK, let destURL = panel.url else { return }
            do {
                // replaceItemAt handles the pre-existing destination that copyItem would reject.
                let tmpURL = destURL.deletingLastPathComponent()
                    .appendingPathComponent(".picshurs_copy_\(UUID().uuidString).\(photo.url.pathExtension)")
                try FileManager.default.copyItem(at: photo.url, to: tmpURL)
                _ = try FileManager.default.replaceItemAt(destURL, withItemAt: tmpURL, backupItemName: nil, options: [])
            } catch {
                showAlert(message: "Failed to copy original file: \(error.localizedDescription)")
            }
            return
        }

        guard let cgImage = ImageProcessor.renderFullResolution(from: photo.url, payload: payload) else {
            showAlert(message: "Failed to render edited image.")
            return
        }

        let ext = photo.url.pathExtension.lowercased()
        let uti = Self.utType(for: ext)

        let panel = NSSavePanel()
        panel.nameFieldStringValue = photo.filename
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let destURL = panel.url else { return }

        var extra: [CFString: Any] = [:]
        if ext == "jpg" || ext == "jpeg" {
            extra[kCGImageDestinationLossyCompressionQuality] = 1.0
        }
        let properties = MetadataPreserver.buildOutputProperties(from: photo.url, extraProperties: extra)

        guard let destination = CGImageDestinationCreateWithURL(
            destURL as CFURL,
            uti,
            1,
            nil
        ) else {
            showAlert(message: "Failed to create export destination.")
            return
        }
        CGImageDestinationAddImage(destination, cgImage, properties as CFDictionary)
        if !CGImageDestinationFinalize(destination) {
            showAlert(message: "Failed to finalize export.")
            return
        }
    }

    private func refreshPhotoMetadata(photo: PhotoItem) {
        Task { @MainActor in
            guard let attrs = try? FileManager.default.attributesOfItem(atPath: photo.url.path),
                  let modDate = attrs[.modificationDate] as? Date,
                  let fileSize = attrs[.size] as? Int64 else { return }

            // Evict stale thumbnail so the grid reloads from the freshly-saved file.
            await ThumbnailService.shared.invalidate(path: photo.url.path)

            let (w, h) = Self.readImageDimensions(from: photo.url)
            writeToDB { db in
                try db.execute(literal: """
                    UPDATE photos SET fileSize = \(fileSize), modificationDate = \(modDate)
                    WHERE url = \(photo.url.path)
                    """)
                if let w { try db.execute(sql: "UPDATE photos SET width = ? WHERE url = ?", arguments: [w, photo.url.path]) }
                if let h { try db.execute(sql: "UPDATE photos SET height = ? WHERE url = ?", arguments: [h, photo.url.path]) }
            }
            if let idx = photos.firstIndex(where: { $0.url.path == photo.url.path }) {
                var updated = photos[idx]
                updated.width = w
                updated.height = h
                photos[idx] = updated
            }
            if var sp = selectedPhoto, sp.url.path == photo.url.path {
                sp.width = w
                sp.height = h
                selectedPhoto = sp
            }
        }
    }

    private static func readImageDimensions(from url: URL) -> (Int?, Int?) {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let w = props[kCGImagePropertyPixelWidth] as? Int,
              let h = props[kCGImagePropertyPixelHeight] as? Int else { return (nil, nil) }
        return (w, h)
    }

    private func showAlert(message: String) {
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = message
            alert.alertStyle = .warning
            alert.addButton(withTitle: "OK")
            alert.runModal()
        }
    }

    private func writeToDB(_ block: (Database) throws -> Void) {
        do {
            try DatabaseManager.shared.dbQueue.write(block)
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func writeToDBAsync(_ block: @escaping @Sendable (Database) throws -> Void) {
        Task.detached {
            do {
                try await DatabaseManager.shared.dbQueue.write(block)
            } catch {
                await MainActor.run { self.lastError = error.localizedDescription }
            }
        }
    }

    static func utType(for ext: String) -> CFString {
        switch ext {
        case "jpg", "jpeg":
            return UTType.jpeg.identifier as CFString
        case "png":
            return UTType.png.identifier as CFString
        case "heic":
            return UTType.heic.identifier as CFString
        case "tiff", "tif":
            return UTType.tiff.identifier as CFString
        case "bmp":
            return UTType.bmp.identifier as CFString
        case "gif":
            return UTType.gif.identifier as CFString
        case "webp":
            return UTType.webP.identifier as CFString
        default:
            return UTType.jpeg.identifier as CFString
        }
    }

}
