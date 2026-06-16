import SwiftUI
import AppKit

struct ContentView: View {
    @Environment(AppViewModel.self) private var viewModel
    @Environment(AppSettings.self) private var settings

    @State private var keyMonitor: Any?
    @State private var scrollMonitor: Any?
    @State private var sidebarVisibility: NavigationSplitViewVisibility = .automatic
    @State private var preEditSidebarVisibility: NavigationSplitViewVisibility = .automatic
    @State private var showGridInfo = false
    @State private var isRenamingPerson = false
    @State private var personRenameText = ""

    /// Non-nil only while viewing a single person/face group.
    private var currentPersonID: String? {
        if case let .person(id) = viewModel.displayMode { return id }
        return nil
    }

    var body: some View {
        NavigationSplitView(columnVisibility: $sidebarVisibility) {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 280)
        } detail: {
            HStack(spacing: 0) {
                ZStack {
                    if let error = viewModel.lastError {
                        VStack {
                            HStack {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundColor(.yellow)
                                Text(error)
                                    .font(.callout)
                                Spacer()
                                Button {
                                    viewModel.lastError = nil
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundColor(.secondary)
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(10)
                            .background(.ultraThinMaterial)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .padding(.horizontal)
                            .padding(.top, 8)
                            Spacer()
                        }
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .zIndex(100)
                    }

                    if let success = viewModel.successMessage {
                        VStack {
                            HStack {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                                Text(success)
                                    .font(.callout)
                                Spacer()
                            }
                            .padding(10)
                            .background(.ultraThinMaterial)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .padding(.horizontal)
                            .padding(.top, 8)
                            Spacer()
                        }
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .zIndex(99)
                        .animation(.easeInOut(duration: 0.2), value: viewModel.successMessage)
                    }

                    if viewModel.isViewingPhoto, viewModel.selectedPhoto != nil {
                        PhotoDetailView()
                            .transition(.scale(0.96).combined(with: .opacity))
                    } else if viewModel.displayMode == .map {
                        MapView()
                    } else if viewModel.displayMode == .people {
                        PeopleView()
                    } else {
                        PhotoGridView(onSelect: { photo in
                            viewModel.selectSingle(photo)
                            withAnimation(.spring(response: 0.28, dampingFraction: 0.9)) { viewModel.isViewingPhoto = true }
                        })
                        .overlay(alignment: .bottom) {
                            if showGridInfo, let photo = viewModel.selectedPhoto {
                                PhotoInfoOverlay(photo: photo)
                            }
                        }
                    }
                }
                .safeAreaInset(edge: .bottom) {
                    if !viewModel.isEditing {
                        PhotoTrayView()
                    }
                }
                .frame(maxWidth: .infinity)

                if viewModel.isEditing {
                    Divider()
                    EditSidebarView()
                        .frame(minWidth: 220, idealWidth: 260, maxWidth: 320)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
            .animation(.spring(response: 0.3, dampingFraction: 0.85), value: viewModel.isEditing)
        }
        .navigationTitle(viewModel.folderName ?? "Picshurs")
        .toolbar { toolbarContent }
        .alert("Rename Person", isPresented: $isRenamingPerson) {
            TextField("Name", text: $personRenameText)
            Button("Cancel", role: .cancel) {}
            Button("Save") {
                if let pid = currentPersonID {
                    viewModel.renamePerson(pid, to: personRenameText)
                }
            }
        }
        .searchable(text: Bindable(viewModel).searchText, placement: .toolbar, prompt: "Search photos...")
        .background(QuickLookHostView(controller: viewModel.quickLookController).frame(width: 0, height: 0))
        .onChange(of: viewModel.isEditing) { _, editing in
            withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                if editing {
                    preEditSidebarVisibility = sidebarVisibility
                    sidebarVisibility = .detailOnly
                } else {
                    sidebarVisibility = preEditSidebarVisibility
                }
            }
        }
        .onAppear {
            guard scrollMonitor == nil else { return }
            if keyMonitor != nil { return }

            keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                // QuickLook owns the keyboard while its panel is up — letting
                // shortcuts through would navigate the grid behind the preview.
                if let panel = NSApp.keyWindow, panel.className.contains("QLPreviewPanel") {
                    return event
                }
                let isEditingText = NSApp.keyWindow?.firstResponder is NSText
                let flags = event.modifierFlags
                let isCmd = flags.contains(.command)
                let isShift = flags.contains(.shift)

                // Handle ⌘⇧A — Deselect all (must precede ⌘A)
                if isCmd, isShift, event.keyCode == 0 { // 'a'
                    viewModel.clearTemporarySelection()
                    return nil
                }

                // Handle ⌘A (select all)
                if isCmd, event.keyCode == 0 { // 'a'
                    viewModel.selectAll()
                    return nil
                }

                // Handle ⌘C — Copy selected files to clipboard
                if isCmd, event.keyCode == 8 { // 'c'
                    if !viewModel.temporarilySelectedPhotos.isEmpty {
                        let urls = viewModel.temporarilySelectedPhotos.map { $0.url as NSURL }
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.writeObjects(urls)
                    } else if let photo = viewModel.selectedPhoto {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.writeObjects([photo.url as NSURL])
                    }
                    return nil
                }

                // Handle Escape — viewer check must precede selection-clear:
                // in gallery mode the current photo is always selected, so the
                // old order cleared selection instead of closing the viewer.
                if event.keyCode == 53 {
                    if viewModel.isEditing {
                        withAnimation(.easeInOut(duration: 0.25)) { viewModel.toggleEditMode() }
                        return nil
                    } else if viewModel.isViewingPhoto {
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.9)) {
                            viewModel.closeViewer()
                        }
                        return nil
                    } else if !viewModel.temporarilySelectedPhotos.isEmpty {
                        viewModel.clearTemporarySelection()
                        return nil
                    }
                    return event
                }

                // Handle Delete
                if event.keyCode == 51 || event.keyCode == 117 {
                    if !isEditingText, !viewModel.temporarilySelectedPhotos.isEmpty {
                        viewModel.deleteCurrentPhoto()
                        return nil
                    }
                    return event
                }

                // Spacebar — open/close gallery view (Photos.app convention)
                if event.keyCode == 49, !isCmd, !isEditingText, !viewModel.isEditing {
                    if viewModel.isViewingPhoto {
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.9)) {
                            viewModel.closeViewer()
                        }
                    } else if viewModel.selectedPhoto != nil {
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.9)) {
                            viewModel.isViewingPhoto = true
                        }
                    }
                    return nil
                }

                // ⌘Y — Quick Look (Finder convention)
                if event.keyCode == 16, isCmd, !isShift, !isEditingText { // 'y'
                    let urls = viewModel.filteredPhotos.map { $0.url }
                    viewModel.quickLookController.show(urls: urls)
                    return nil
                }

                // Handle S — Star/unstar selected (guard text editing) - REMOVED
                // if event.keyCode == 1, !isCmd, !isEditingText { // 's'
                //     if !viewModel.temporarilySelectedPhotos.isEmpty {
                //         let allStarred = viewModel.temporarilySelectedPhotos.allSatisfy { $0.isStarred }
                //         for photo in viewModel.temporarilySelectedPhotos {
                //             allStarred ? viewModel.unstarPhoto(photo) : viewModel.starPhoto(photo)
                //         }
                //     } else if let photo = viewModel.selectedPhoto {
                //         viewModel.toggleStarred(photo)
                //     }
                //     return nil
                // }

                // Handle P — Pin/unpin selected (guard text editing)
                if event.keyCode == 35, !isCmd, !isEditingText { // 'p'
                    if !viewModel.temporarilySelectedPhotos.isEmpty {
                        let allPinned = viewModel.temporarilySelectedPhotos.allSatisfy { viewModel.isPinned($0) }
                        for photo in viewModel.temporarilySelectedPhotos {
                            allPinned ? viewModel.unpinPhoto(photo) : viewModel.pinPhoto(photo)
                        }
                    } else if let photo = viewModel.selectedPhoto {
                        viewModel.isPinned(photo) ? viewModel.unpinPhoto(photo) : viewModel.pinPhoto(photo)
                    }
                    return nil
                }

                // Handle ⌥1-8 — Toggle dot color on selected (guard text editing)
                let isOpt = flags.contains(.option)
                let dotKeyCodes: [UInt16: Int] = [18: 1, 19: 2, 20: 3, 21: 4, 23: 5, 22: 6, 26: 7, 28: 8]
                if !isCmd, isOpt, let color = dotKeyCodes[event.keyCode], !isEditingText {
                    if !viewModel.temporarilySelectedPhotos.isEmpty {
                        viewModel.batchToggleDotColor(color)
                    } else if let photo = viewModel.selectedPhoto {
                        viewModel.toggleDotColor(photo, color: color)
                    }
                    return nil
                }

                // Handle ⌥0 — Clear dot color on selected (guard text editing)
                if event.keyCode == 29, !isCmd, isOpt, !isEditingText {
                    if !viewModel.temporarilySelectedPhotos.isEmpty {
                        viewModel.batchClearDotColor()
                    } else if let photo = viewModel.selectedPhoto {
                        viewModel.clearDotColor(photo)
                    }
                    return nil
                }

                // Handle ⌘↵ — Reveal in Finder
                if isCmd, event.keyCode == 36 { // return
                    if !viewModel.temporarilySelectedPhotos.isEmpty {
                        for photo in viewModel.temporarilySelectedPhotos {
                            NSWorkspace.shared.activateFileViewerSelecting([photo.url])
                        }
                    } else if let photo = viewModel.selectedPhoto {
                        NSWorkspace.shared.selectFile(photo.url.path, inFileViewerRootedAtPath: "")
                    }
                    return nil
                }

                // Handle F — Toggle filename labels
                if event.keyCode == 3, !isCmd, !isEditingText { // 'f'
                    viewModel.toggleFilenameLabels()
                    return nil
                }

                // Handle I — Toggle photo info card in the gallery (the
                // viewer handles its own "i" via onKeyPress)
                if event.keyCode == 34, !isCmd, !isEditingText, !viewModel.isViewingPhoto { // 'i'
                    if viewModel.selectedPhoto != nil {
                        showGridInfo.toggle()
                        return nil
                    }
                    return event
                }

                // Handle E — Toggle edit mode (viewer only, guard text editing)
                if event.keyCode == 14, !isCmd, !isEditingText, viewModel.isViewingPhoto, viewModel.selectedPhoto != nil { // 'e'
                    withAnimation(.easeInOut(duration: 0.25)) { viewModel.toggleEditMode() }
                    return nil
                }

                // Handle ⌘Z — Undo edit
                if isCmd, !isShift, event.keyCode == 6, viewModel.isEditing { // 'z'
                    viewModel.undoEdit()
                    return nil
                }

                // Handle ⌘⇧Z — Redo edit
                if isCmd, isShift, event.keyCode == 6, viewModel.isEditing { // 'z'
                    viewModel.redoEdit()
                    return nil
                }

                // Handle ⌘[ — Navigate back
                if isCmd, !isShift, event.keyCode == 33 {
                    viewModel.goBack()
                    return nil
                }

                // Handle ⌘] — Navigate forward
                if isCmd, !isShift, event.keyCode == 30 {
                    viewModel.goForward()
                    return nil
                }

                // Handle 1-5 — Thumbnail size presets
                if !isCmd, !isOpt, !isEditingText {
                    switch Int(event.keyCode) {
                    case 18: viewModel.thumbnailSize = 80; return nil   // 1
                    case 19: viewModel.thumbnailSize = 160; return nil  // 2
                    case 20: viewModel.thumbnailSize = 240; return nil  // 3
                    case 21: viewModel.thumbnailSize = 320; return nil  // 4
                    case 23: viewModel.thumbnailSize = 400; return nil  // 5
                    default: break
                    }
                }

                guard viewModel.isViewingPhoto ||
                      (viewModel.selectedPhoto != nil && !isEditingText)
                else { return event }

                switch Int(event.keyCode) {
                case 123:
                    viewModel.navigateBackward()
                    return nil
                case 124:
                    viewModel.navigateForward()
                    return nil
                case 125 where !viewModel.isViewingPhoto: // down — move one grid row
                    viewModel.navigateRow(up: false)
                    return nil
                case 126 where !viewModel.isViewingPhoto: // up
                    viewModel.navigateRow(up: true)
                    return nil
                default:
                    return event
                }
            }

            scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { event in
                guard event.modifierFlags.contains(.command) else { return event }
                let delta = event.scrollingDeltaY * 2
                viewModel.thumbnailSize = min(max(viewModel.thumbnailSize + delta, 80), 400)
                return nil
            }
        }
        .onDisappear {
            if let monitor = keyMonitor {
                NSEvent.removeMonitor(monitor)
                keyMonitor = nil
            }
            if let monitor = scrollMonitor {
                NSEvent.removeMonitor(monitor)
                scrollMonitor = nil
            }
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        // Photos-style thumbnail controls, pinned to the leading edge
        ToolbarItemGroup(placement: .navigation) {
            if !viewModel.isViewingPhoto, viewModel.canGoBack {
                Button {
                    viewModel.goBack()
                } label: {
                    Image(systemName: "chevron.left")
                }
                .help("Back (⌘[)")
            }

            if !viewModel.isViewingPhoto, let pid = currentPersonID {
                Button {
                    personRenameText = viewModel.personName(for: pid) ?? ""
                    isRenamingPerson = true
                } label: {
                    Label("Rename", systemImage: "pencil")
                }
                .help("Rename this person")
            }

            if !viewModel.isViewingPhoto, viewModel.displayMode == .map {
                Button {
                    viewModel.mapResetToken += 1
                } label: {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                }
                .help("Fit all pins")

                Button {
                    viewModel.mapZoom = max(0, viewModel.mapZoom - 0.05)
                } label: {
                    Image(systemName: "minus")
                }
                .help("Zoom out")

                Slider(value: Bindable(viewModel).mapZoom, in: 0...1)
                    .frame(width: 110)

                Button {
                    viewModel.mapZoom = min(1, viewModel.mapZoom + 0.05)
                } label: {
                    Image(systemName: "plus")
                }
                .help("Zoom in")
            } else if !viewModel.isViewingPhoto, !viewModel.photos.isEmpty {
                Button {
                    settings.preserveAspectRatio.toggle()
                } label: {
                    Image(systemName: settings.preserveAspectRatio
                          ? "rectangle.arrowtriangle.2.inward"
                          : "rectangle.arrowtriangle.2.outward")
                }
                .help(settings.preserveAspectRatio
                      ? "Switch to square thumbnails"
                      : "Switch to aspect-ratio thumbnails")

                Button {
                    viewModel.thumbnailSize = max(80, viewModel.thumbnailSize - 20)
                } label: {
                    Image(systemName: "minus")
                }
                .help("Smaller thumbnails")

                Slider(value: Bindable(viewModel).thumbnailSize, in: 80...400, step: 20)
                    .frame(width: 110)

                Button {
                    viewModel.thumbnailSize = min(400, viewModel.thumbnailSize + 20)
                } label: {
                    Image(systemName: "plus")
                }
                .help("Larger thumbnails")
            }
        }
        ToolbarItemGroup {
            Picker("Sort", selection: Bindable(viewModel).sortOrder) {
                ForEach(AppViewModel.SortOrder.allCases, id: \.self) { order in
                    Text(order.rawValue).tag(order)
                }
            }
            Button(action: { viewModel.sortAscending.toggle() }) {
                Image(systemName: viewModel.sortAscending ? "arrow.up" : "arrow.down")
            }
            .help(viewModel.sortAscending ? "Sorted ascending — click to reverse" : "Sorted descending — click to reverse")

            Button(action: { viewModel.refreshCurrentView() }) {
                Image(systemName: "arrow.clockwise")
            }
            .help("Refresh (⌘R)")
        }
    }
}
