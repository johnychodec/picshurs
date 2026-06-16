import SwiftUI

struct LibrarySettingsView: View {
    @Environment(AppViewModel.self) private var viewModel
    @Binding var folders: [LibraryFolder]
    @Binding var excludedPaths: Set<String>
    @Binding var includeSubfolders: Bool

    @State private var showResetLibraryAlert = false

    private let homePath = FileManager.default.homeDirectoryForCurrentUser.path

    var body: some View {
        Form {
            Section {
                FolderTreeView(
                    rootPath: homePath,
                    includeSubfolders: includeSubfolders,
                    watchedRoots: $folders,
                    excludedPaths: $excludedPaths
                )
                .frame(minHeight: 220, idealHeight: 300)
            } header: {
                Text("Watched Folders")
            } footer: {
                Text(includeSubfolders
                    ? "Check a folder to add it and all its subfolders to your library."
                    : "Check a folder to add only its direct photos. Check subfolders individually to include them.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Scanning") {
                Toggle(isOn: $includeSubfolders) {
                    Text("Include subfolders automatically")
                    Text("When off, checking a folder in the tree adds only that folder — its subfolders stay unchecked until you add them individually.")
                }
            }

            Section {
                if viewModel.isScanningText {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        if let p = viewModel.textScanProgress, p.total > 0 {
                            Text("Reading text… \(p.done) of \(p.total)")
                                .foregroundStyle(.secondary)
                        } else {
                            Text("Reading text…").foregroundStyle(.secondary)
                        }
                    }
                } else {
                    HStack {
                        Button("Clear Text Index", role: .destructive) {
                            viewModel.resetTextData()
                        }
                        Spacer()
                        Button("Index Text in Photos") {
                            viewModel.scanForText()
                        }
                        .disabled(folders.isEmpty)
                    }
                }
            } header: {
                Text("Search")
            } footer: {
                Text("Recognizes text inside your photos — signs, receipts, screenshots, slides — so you can find them from the search bar. Runs on-device; large libraries take a while.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                HStack {
                    Button("Reset Library", role: .destructive) {
                        showResetLibraryAlert = true
                    }
                    .disabled(folders.isEmpty)

                    Spacer()

                    Button("Rescan All Folders") {
                        viewModel.openAllPhotos()
                    }
                    .disabled(folders.isEmpty)
                }
            }
        }
        .formStyle(.grouped)
        .alert("Reset Library?", isPresented: $showResetLibraryAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Reset", role: .destructive) {
                folders = []
                excludedPaths = []
            }
        } message: {
            Text("This removes all library folders and exclusions. Your photo files are not affected. Press OK in the settings window to apply.")
        }
    }
}
