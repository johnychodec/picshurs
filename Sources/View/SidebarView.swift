import SwiftUI

struct SidebarView: View {
    @Environment(AppViewModel.self) private var viewModel
    @Environment(AppSettings.self) private var settings
    @Environment(\.openWindow) private var openWindow
    @State private var selectedID: String? = "all"
    @State private var expandedGroups: Set<String> = []
    @State private var isSidebarDropTargeted = false

    var body: some View {
        List(selection: $selectedID) {
            Section("Library") {
                Label("All Photos", systemImage: "photo.on.rectangle.angled")
                    .tag("all")
                Label("Tray", systemImage: "pin.fill")
                    .tag("tray")
                if settings.enableMap, viewModel.hasGeotaggedPhotos {
                    Label("Map", systemImage: "map")
                        .tag("map")
                }
                // Always available once there's a library, so the first scan can
                // be started from the People view's empty-state button.
                if settings.enableFaces, !viewModel.libraryFolders.isEmpty {
                    let peopleCount = viewModel.persons.filter { $0.name != nil || $0.count >= 2 }.count
                    Label("People", systemImage: "person.2.crop.square.stack.fill")
                        .badge(peopleCount == 0 ? nil : Text("\(peopleCount)"))
                        .tag("people")
                }
            }

            if !viewModel.usedDotColors.isEmpty {
                Section("Dot Colors") {
                    ForEach(DotColor.all.filter { viewModel.usedDotColors.contains($0.rawValue) }) { dot in
                        Label {
                            Text(dot.name)
                                .font(.body)
                        } icon: {
                            Circle()
                                .fill(dot.color)
                                .frame(width: 12, height: 12)
                        }
                        .tag("dot:\(dot.rawValue)")
                        .contextMenu {
                            Button("Clear all from \(dot.name)") {
                                viewModel.clearDotColorFromAllPhotos(color: dot.rawValue)
                            }
                        }
                    }
                }
            }

            Section("Folders") {
                if !viewModel.sidebarGroups.isEmpty {
                    Picker("Group by", selection: Bindable(viewModel).sidebarGrouping) {
                        Text("Year").tag(AppViewModel.SidebarGrouping.byYear)
                        Text("Source").tag(AppViewModel.SidebarGrouping.bySource)
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                }

                ForEach(viewModel.sidebarGroups) { group in
                    Group {
                        let header = HStack(spacing: 4) {
                            Image(systemName: expandedGroups.contains(group.id) ? "chevron.down" : "chevron.right")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .frame(width: 16, height: 16)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    if expandedGroups.contains(group.id) {
                                        expandedGroups.remove(group.id)
                                    } else {
                                        expandedGroups.insert(group.id)
                                    }
                                }

                            Text(group.title)
                                .font(.callout)

                            if group.photoCount > 0 {
                                Spacer()
                                Text("(\(group.photoCount))")
                                    .foregroundStyle(.secondary)
                                    .font(.caption)
                            }
                        }
                        .padding(.vertical, 4)

                        if let rootPath = group.rootPath {
                            header.tag(rootPath)
                        } else {
                            header
                        }
                    }

                    if expandedGroups.contains(group.id) {
                        ForEach(group.folders, id: \.path) { folder in
                            let (leaf, parent) = viewModel.folderNameComponents(for: folder.path)
                            Label {
                                HStack {
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(leaf)
                                            .font(.body)
                                        if let parent = parent {
                                            Text(parent)
                                                .font(.caption)
                                                .foregroundStyle(.tertiary)
                                        }
                                    }
                                    Spacer()
                                    Text("\(viewModel.photoCount(for: folder.path))")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            } icon: {
                                Image(systemName: "folder.fill")
                            }
                            .tag(folder.path)
                            .padding(.leading, 20)
                            .help(folder.path)
                            .contextMenu {
                                Button("Remove from Library") {
                                    viewModel.excludeLeafFolder(folder.path)
                                }
                            }
                        }
                    }
                }
            }
        }
        .dropDestination(for: URL.self) { urls, _ in
            let dirs = urls.filter { url in
                var isDir: ObjCBool = false
                guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) else { return false }
                return isDir.boolValue
            }
            guard !dirs.isEmpty else { return false }
            for dir in dirs {
                viewModel.addFolderToLibrary(dir)
            }
            return true
        } isTargeted: { targeted in
            isSidebarDropTargeted = targeted
        }
        .overlay {
            if viewModel.sidebarGroups.isEmpty && viewModel.libraryFolders.isEmpty {
                VStack {
                    Spacer()
                    Text("No folders added")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
            }
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.accentColor, lineWidth: 2)
                .opacity(isSidebarDropTargeted ? 1 : 0)
                .animation(.easeInOut(duration: 0.15), value: isSidebarDropTargeted)
        }
        .onChange(of: selectedID) { _, newID in
            guard let newID else { return }
            switch newID {
            case "all":
                if viewModel.displayMode != .library {
                    viewModel.openAllPhotos()
                }
            case let id where id.hasPrefix("dot:"):
                guard let color = Int(String(id.dropFirst(4))) else { return }
                if viewModel.displayMode != .dot(color) {
                    viewModel.openDotColorPhotos(color)
                }
            case "tray":
                if viewModel.displayMode != .tray {
                    viewModel.openTrayPhotos()
                }
            case "map":
                if viewModel.displayMode != .map {
                    viewModel.openMap()
                }
            case "people":
                if viewModel.displayMode != .people {
                    viewModel.openPeople()
                }
            case let id where id.hasPrefix("person:"):
                let pid = String(id.dropFirst("person:".count))
                if viewModel.displayMode != .person(pid) {
                    viewModel.openPerson(pid, name: viewModel.personName(for: pid))
                }
            case let id where id.hasPrefix("year:"):
                guard let year = Int(String(id.dropFirst(5))) else { return }
                viewModel.openYearPhotos(year)
            default:
                // Ignore selection IDs that are not real file paths (e.g. year headers in byYear mode)
                guard newID.hasPrefix("/") else { return }
                if viewModel.folderURL?.path != newID {
                    viewModel.openLibraryFolderByPath(newID)
                }
            }
        }
        .onChange(of: viewModel.displayMode) { _, newMode in
            switch newMode {
            case .library:
                selectedID = "all"
            case let .dot(color):
                selectedID = "dot:\(color)"
            case .tray:
                selectedID = "tray"
            case let .folder(folder):
                selectedID = folder.path
            case let .year(year):
                selectedID = "year:\(year)"
            case .map:
                selectedID = "map"
            case .people, .person:
                selectedID = "people"
            }
        }
        .onAppear {
            switch viewModel.displayMode {
            case .library:
                selectedID = "all"
            case let .dot(color):
                selectedID = "dot:\(color)"
            case .tray:
                selectedID = "tray"
            case let .folder(folder):
                selectedID = folder.path
            case let .year(year):
                selectedID = "year:\(year)"
            case .map:
                selectedID = "map"
            case .people, .person:
                selectedID = "people"
            }
            expandedGroups = Set(viewModel.sidebarGroups.map(\.id))
        }
        .onChange(of: viewModel.sidebarGrouping) { _, _ in
            expandedGroups = Set(viewModel.sidebarGroups.map(\.id))
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 0) {
                Button {
                    openWindow(id: "settings")
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "gearshape.fill")
                            .font(.system(size: 15))
                        Text("Settings")
                            .font(.body)
                        Spacer()
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 16)
                // 40pt matches the tray's bottom tools row (28pt content +
                // 2×6pt padding) so the two dividers align horizontally.
                .frame(height: 40)
            }
            .background(.bar)
        }
    }
}
