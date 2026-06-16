import SwiftUI

/// The People browser — a destination grid of clustered faces, shown in the main
/// content area (not the sidebar, which can't hold thousands of clusters).
/// Defaults to hiding singleton "faces" so an art/large library doesn't drown
/// the real people; the user names/merges the ones that matter.
struct PeopleView: View {
    @Environment(AppViewModel.self) private var viewModel

    enum Filter: String, CaseIterable, Identifiable {
        case groups = "Groups"      // 2+ faces
        case named = "Named"
        case all = "All"
        var id: String { rawValue }
    }

    @State private var filter: Filter = .groups
    @State private var renamingPerson: AppViewModel.PersonChip?
    @State private var renameText = ""

    private let columns = [GridItem(.adaptive(minimum: 96, maximum: 140), spacing: 16)]

    private var shown: [AppViewModel.PersonChip] {
        switch filter {
        case .all: return viewModel.persons
        case .named: return viewModel.persons.filter { $0.name != nil }
        case .groups: return viewModel.persons.filter { $0.name != nil || $0.count >= 2 }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if shown.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 18) {
                        ForEach(shown) { person in
                            chip(person)
                        }
                    }
                    .padding(16)
                }
            }
        }
        .alert("Rename Person", isPresented: Binding(
            get: { renamingPerson != nil },
            set: { if !$0 { renamingPerson = nil } }
        )) {
            TextField("Name", text: $renameText)
            Button("Cancel", role: .cancel) { renamingPerson = nil }
            Button("Save") {
                if let p = renamingPerson { viewModel.renamePerson(p.id, to: renameText) }
                renamingPerson = nil
            }
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Text("People").font(.title2).fontWeight(.semibold)
            Text("\(shown.count)").foregroundStyle(.secondary)

            Picker("", selection: $filter) {
                ForEach(Filter.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .fixedSize()

            Spacer()

            if viewModel.isScanningFaces {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    if let p = viewModel.faceScanProgress, p.total > 0 {
                        Text("Scanning \(p.done)/\(p.total)…").font(.callout).foregroundStyle(.secondary)
                    } else {
                        Text("Scanning…").font(.callout).foregroundStyle(.secondary)
                    }
                }
            } else {
                Button {
                    viewModel.scanForFaces()
                } label: {
                    Label(viewModel.persons.isEmpty ? "Scan for Faces" : "Scan for New Faces",
                          systemImage: "person.crop.square.badge.camera")
                }
            }

            Menu {
                Button(role: .destructive) { viewModel.resetFaceData() } label: {
                    Label("Reset Face Data…", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private var emptyState: some View {
        if viewModel.persons.isEmpty {
            // Never scanned (or just reset) — first-run call to action.
            VStack(spacing: 12) {
                Spacer()
                Image(systemName: "person.crop.square.badge.camera")
                    .font(.system(size: 44)).foregroundStyle(.tertiary)
                Text("Find People in Your Photos")
                    .font(.title3).fontWeight(.semibold)
                Text("Scan your library to detect faces and group them into people.\nNothing runs until you start it.")
                    .font(.callout).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                if viewModel.isScanningFaces {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.small)
                        if let p = viewModel.faceScanProgress, p.total > 0 {
                            Text("Scanning \(p.done)/\(p.total)…").foregroundStyle(.secondary)
                        } else {
                            Text("Scanning…").foregroundStyle(.secondary)
                        }
                    }
                    .padding(.top, 4)
                } else {
                    Button {
                        viewModel.scanForFaces()
                    } label: {
                        Label("Scan for Faces", systemImage: "person.crop.square.badge.camera")
                            .padding(.horizontal, 6)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .padding(.top, 4)
                }
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            // Scanned, but the current filter hides everything.
            VStack(spacing: 8) {
                Spacer()
                Image(systemName: "person.2.slash").font(.system(size: 36)).foregroundStyle(.tertiary)
                Text(filter == .named ? "No named people yet" : "No face groups found")
                    .foregroundStyle(.secondary)
                if filter != .all {
                    Button("Show all \(viewModel.persons.count)") { filter = .all }
                        .buttonStyle(.link)
                }
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func chip(_ person: AppViewModel.PersonChip) -> some View {
        Button {
            viewModel.openPerson(person.id, name: person.name)
        } label: {
            VStack(spacing: 6) {
                FaceChipView(url: person.coverFaceURL, faceRect: person.coverFaceRect, size: 92)
                    .overlay(Circle().stroke(.white.opacity(0.6), lineWidth: 1))
                    .shadow(radius: 1)
                Text(person.name ?? "Unnamed")
                    .font(.callout)
                    .foregroundStyle(person.name == nil ? .secondary : .primary)
                    .lineLimit(1)
                Text("\(person.count)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .frame(width: 110)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu { menu(person) }
    }

    @ViewBuilder
    private func menu(_ person: AppViewModel.PersonChip) -> some View {
        Button("Rename…") {
            renameText = person.name ?? ""
            renamingPerson = person
        }
        if viewModel.persons.count > 1 {
            Menu("Merge Into") {
                // Offer named people first, then other groups; cap to keep the menu sane.
                ForEach(mergeTargets(for: person)) { other in
                    Button(other.name ?? "Unnamed (\(other.count))") {
                        viewModel.mergePerson(person.id, into: other.id)
                    }
                }
            }
        }
        Divider()
        Button("Hide Person") { viewModel.hidePerson(person.id) }
    }

    private func mergeTargets(for person: AppViewModel.PersonChip) -> [AppViewModel.PersonChip] {
        let others = viewModel.persons.filter { $0.id != person.id }
        let named = others.filter { $0.name != nil }
        let groups = others.filter { $0.name == nil && $0.count >= 2 }
        return Array((named + groups).prefix(30))
    }
}
