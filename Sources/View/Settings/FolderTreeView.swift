import SwiftUI

struct FolderTreeView: View {
    let rootPath: String
    var includeSubfolders: Bool = true
    @Binding var watchedRoots: [LibraryFolder]
    @Binding var excludedPaths: Set<String>

    @State private var expandedPaths: Set<String> = []
    @State private var initialized = false

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                FolderTreeRow(
                    path: rootPath,
                    name: URL(fileURLWithPath: rootPath).lastPathComponent,
                    depth: 0,
                    includeSubfolders: includeSubfolders,
                    watchedRoots: $watchedRoots,
                    excludedPaths: $excludedPaths,
                    expandedPaths: $expandedPaths
                )
            }
            .padding(4)
        }
        .onAppear {
            guard !initialized else { return }
            initialized = true
            var paths = Set<String>()
            for root in watchedRoots {
                var p = root.path
                while p != "/" {
                    paths.insert(p)
                    p = (p as NSString).deletingLastPathComponent
                }
            }
            for path in excludedPaths {
                var p = path
                while p != "/" {
                    paths.insert(p)
                    p = (p as NSString).deletingLastPathComponent
                }
            }
            expandedPaths = paths
        }
    }
}

private enum FolderState {
    case watched
    case excluded
    case unwatched
}

private struct FolderTreeRow: View {
    let path: String
    let name: String
    let depth: Int
    let includeSubfolders: Bool
    @Binding var watchedRoots: [LibraryFolder]
    @Binding var excludedPaths: Set<String>
    @Binding var expandedPaths: Set<String>

    @State private var children: [String]? = nil

    private var isExpanded: Bool {
        expandedPaths.contains(path)
    }

    private var state: FolderState {
        if excludedPaths.contains(path) { return .excluded }
        if watchedRoots.contains(where: { $0.path == path }) { return .watched }
        // Subfolders inherit "watched" from an ancestor root only when
        // automatic inclusion is enabled
        if includeSubfolders {
            for root in watchedRoots {
                let prefix = root.path + "/"
                if path.hasPrefix(prefix) { return .watched }
            }
        }
        return .unwatched
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 2) {
                ForEach(0..<depth, id: \.self) { _ in
                    Color.clear.frame(width: 16, height: 16)
                }

                Button {
                    if expandedPaths.contains(path) {
                        expandedPaths.remove(path)
                    } else {
                        expandedPaths.insert(path)
                        if children == nil { loadChildren() }
                    }
                } label: {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .frame(width: 16, height: 20)
                .opacity((children?.isEmpty == false || children == nil) ? 1 : 0)

                Image(systemName: state == .watched ? "checkmark.circle.fill" : state == .excluded ? "xmark.circle.fill" : "circle")
                    .foregroundStyle(state == .watched ? .green : state == .excluded ? .red : .secondary)
                    .font(.system(size: 12))

                Text(name)
                    .font(.system(size: 13))
                    .lineLimit(1)
                    .help(path)

                Spacer()
            }
            .frame(height: 24)
            .contentShape(Rectangle())
            .onTapGesture {
                toggleState()
            }

            if isExpanded, let childPaths = children {
                ForEach(childPaths, id: \.self) { childPath in
                    FolderTreeRow(
                        path: childPath,
                        name: URL(fileURLWithPath: childPath).lastPathComponent,
                        depth: depth + 1,
                        includeSubfolders: includeSubfolders,
                        watchedRoots: $watchedRoots,
                        excludedPaths: $excludedPaths,
                        expandedPaths: $expandedPaths
                    )
                }
            }
        }
        .onAppear {
            if expandedPaths.contains(path), children == nil {
                loadChildren()
            }
        }
    }

    private func loadChildren() {
        let url = URL(fileURLWithPath: path)
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )) ?? []

        children = contents
            .filter { url in
                (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
                    && !url.lastPathComponent.hasPrefix(".")
            }
            .map(\.path)
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    private func toggleState() {
        switch state {
        case .unwatched:
            let folder = LibraryFolder(name: URL(fileURLWithPath: path).lastPathComponent, path: path)
            watchedRoots.append(folder)
            excludedPaths = excludedPaths.filter { !$0.hasPrefix(path + "/") && $0 != path }
        case .watched:
            if watchedRoots.contains(where: { $0.path == path }) {
                watchedRoots.removeAll { $0.path == path }
                excludedPaths = excludedPaths.filter { !$0.hasPrefix(path + "/") }
            } else {
                excludedPaths.insert(path)
            }
        case .excluded:
            excludedPaths.remove(path)
        }
    }
}
