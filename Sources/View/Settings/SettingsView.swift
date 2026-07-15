import SwiftUI

struct SettingsView: View {
    @Environment(AppViewModel.self) private var viewModel
    @Environment(AppSettings.self) private var settings
    @Environment(\.dismiss) private var dismiss

    // General drafts
    @State private var draftConfirmBeforeTrash = false
    @State private var draftShowFilenameLabels = true
    @State private var draftShowVideos = true
    @State private var draftPreserveAspectRatio = true
    @State private var draftDefaultThumbnailSize: Double = 160
    @State private var draftTrayThumbnailSize: Double = 60
    @State private var draftTrayVisibleRows = 3
    @State private var draftEnableMap = true
    @State private var draftEnableFaces = false
    @State private var draftWebExportMaxDimension = 2048
    @State private var draftWebExportQuality: Double = 0.82

    // Library drafts
    @State private var draftIncludeSubfolders = true
    @State private var draftFolders: [LibraryFolder] = []
    @State private var draftExcludedPaths: Set<String> = []

    @State private var selectedTab = 0

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $selectedTab) {
                GeneralSettingsView(
                    confirmBeforeTrash: $draftConfirmBeforeTrash,
                    showFilenameLabels: $draftShowFilenameLabels,
                    showVideos: $draftShowVideos,
                    preserveAspectRatio: $draftPreserveAspectRatio,
                    defaultThumbnailSize: $draftDefaultThumbnailSize,
                    trayThumbnailSize: $draftTrayThumbnailSize,
                    trayVisibleRows: $draftTrayVisibleRows,
                    enableMap: $draftEnableMap,
                    enableFaces: $draftEnableFaces,
                    webExportMaxDimension: $draftWebExportMaxDimension,
                    webExportQuality: $draftWebExportQuality,
                    onResetToDefaults: resetToDefaults
                )
                .tabItem {
                    Label("General", systemImage: "gearshape")
                }
                .tag(0)

                LibrarySettingsView(
                    folders: $draftFolders,
                    excludedPaths: $draftExcludedPaths,
                    includeSubfolders: $draftIncludeSubfolders
                )
                .tabItem {
                    Label("Library", systemImage: "books.vertical")
                }
                .tag(1)
            }
            .padding(.horizontal, 8)
            .padding(.top, 8)

            Divider()

            HStack {
                Spacer()

                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.escape, modifiers: [])

                Button("Apply") {
                    applyChanges()
                }

                Button("OK") {
                    applyChanges()
                    dismiss()
                }
                .keyboardShortcut(.return, modifiers: [])
            }
            .padding([.horizontal, .bottom], 20)
            .padding(.top, 12)
        }
        .frame(width: 560, height: 700)
        .onAppear {
            draftConfirmBeforeTrash = settings.confirmBeforeTrash
            draftShowFilenameLabels = settings.showFilenameLabels
            draftShowVideos = settings.showVideos
            draftPreserveAspectRatio = settings.preserveAspectRatio
            draftDefaultThumbnailSize = settings.defaultThumbnailSize
            draftTrayThumbnailSize = settings.trayThumbnailSize
            draftTrayVisibleRows = settings.trayVisibleRows
            draftEnableMap = settings.enableMap
            draftEnableFaces = settings.enableFaces
            draftWebExportMaxDimension = settings.webExportMaxDimension
            draftWebExportQuality = settings.webExportQuality
            draftIncludeSubfolders = settings.includeSubfolders
            draftFolders = viewModel.libraryFolders
            draftExcludedPaths = viewModel.excludedLeafPaths
        }
    }

    private func applyChanges() {
        // General settings
        settings.confirmBeforeTrash = draftConfirmBeforeTrash
        settings.showFilenameLabels = draftShowFilenameLabels
        let wasShowingVideos = settings.showVideos
        settings.showVideos = draftShowVideos
        settings.preserveAspectRatio = draftPreserveAspectRatio
        settings.defaultThumbnailSize = draftDefaultThumbnailSize
        settings.trayThumbnailSize = draftTrayThumbnailSize
        settings.trayVisibleRows = draftTrayVisibleRows
        settings.enableMap = draftEnableMap
        settings.enableFaces = draftEnableFaces

        // If the user just turned off the feature they're currently viewing,
        // fall back to the library so they aren't stranded on a hidden view.
        let viewingFaces: Bool
        switch viewModel.displayMode {
        case .people, .person: viewingFaces = true
        default: viewingFaces = false
        }
        if (!draftEnableMap && viewModel.displayMode == .map) || (!draftEnableFaces && viewingFaces) {
            viewModel.openAllPhotos()
        }
        if wasShowingVideos != draftShowVideos {
            viewModel.handleVideoVisibilityChanged()
        }
        settings.webExportMaxDimension = draftWebExportMaxDimension
        settings.webExportQuality = draftWebExportQuality

        // Library settings
        settings.includeSubfolders = draftIncludeSubfolders

        viewModel.thumbnailSize = settings.defaultThumbnailSize

        // Library folders logic (same as existing applyChanges)
        let oldPaths = Set(viewModel.libraryFolders.map(\.path))
        let newPaths = Set(draftFolders.map(\.path))
        let removedPaths = oldPaths.subtracting(newPaths)

        for path in removedPaths {
            let prefix = path + "/"
            try? DatabaseManager.shared.dbQueue.write { db in
                try db.execute(literal: "DELETE FROM photos WHERE folderPath = \(path)")
                try db.execute(literal: "DELETE FROM photos WHERE folderPath LIKE \(prefix + "%")")
            }
        }

        viewModel.libraryFolders = draftFolders
        viewModel.excludedLeafPaths = draftExcludedPaths
        viewModel.saveLibrary()
        viewModel.saveExcludedLeafPaths()
        viewModel.refreshSidebarGroups()

        if !draftFolders.isEmpty {
            viewModel.openAllPhotos()
        } else {
            viewModel.photos = []
            viewModel.clearAllFromTray()
            viewModel.displayMode = .library
        }
    }

    private func resetToDefaults() {
        draftConfirmBeforeTrash = true
        draftShowFilenameLabels = true
        draftShowVideos = true
        draftPreserveAspectRatio = true
        draftDefaultThumbnailSize = 160
        draftTrayThumbnailSize = 60
        draftTrayVisibleRows = 3
        draftEnableMap = true
        draftEnableFaces = false
        draftWebExportMaxDimension = 2048
        draftWebExportQuality = 0.82
        draftIncludeSubfolders = true
    }
}
