import SwiftUI

struct ThumbnailImage: View {
    let url: URL
    let modificationDate: Date
    var fill: Bool = true

    @State private var image: CGImage?
    @State private var opacity: Double
    @State private var loadTask: Task<Void, Never>?

    init(url: URL, modificationDate: Date, fill: Bool = true) {
        self.url = url
        self.modificationDate = modificationDate
        self.fill = fill
        // Seed from the memory cache so a cell that SwiftUI recreates (e.g. its
        // selection state changed identity) renders its image on the first
        // frame — no placeholder flash, no fade-in replay.
        let cached = ThumbnailService.shared.cachedThumbnail(for: url, modificationDate: modificationDate)
        _image = State(initialValue: cached)
        _opacity = State(initialValue: cached != nil ? 1 : 0)
    }

    var body: some View {
        Group {
            if let image {
                Image(decorative: image, scale: 1.0)
                    .resizable()
                    .aspectRatio(contentMode: fill ? .fill : .fit)
                    .opacity(opacity)
                    .onAppear {
                        withAnimation(.easeIn(duration: 0.18)) { opacity = 1 }
                    }
            } else {
                Rectangle()
                    .fill(.quaternary)
                    .shimmering()
            }
        }
        .onAppear {
            guard image == nil else { return }
            loadTask = Task {
                let result = await ThumbnailService.shared.thumbnail(
                    for: url,
                    modificationDate: modificationDate
                )
                if !Task.isCancelled {
                    image = result
                }
            }
        }
        .onDisappear {
            loadTask?.cancel()
            loadTask = nil
        }
    }
}

struct ShimmerModifier: ViewModifier {
    @State private var phase: CGFloat = -1

    func body(content: Content) -> some View {
        content
            .overlay(
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0),
                        .init(color: .white.opacity(0.12), location: 0.4),
                        .init(color: .clear, location: 1),
                    ],
                    startPoint: .init(x: phase, y: 0),
                    endPoint: .init(x: phase + 1, y: 0)
                )
            )
            .mask(content)
            .onAppear {
                withAnimation(.linear(duration: 1.2).repeatForever(autoreverses: false)) {
                    phase = 1.5
                }
            }
    }
}

extension View {
    func shimmering() -> some View { modifier(ShimmerModifier()) }
}
