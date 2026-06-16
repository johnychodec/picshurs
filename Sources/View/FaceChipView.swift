import SwiftUI
import ImageIO

/// Small circular thumbnail of a single detected face, for the People sidebar.
/// Loads a downscaled image off-main and crops to the normalized face rect
/// (Vision bottom-left origin → flipped for CGImage's top-left pixels). Results
/// are cached by photo+rect so sidebar rebuilds don't re-decode.
struct FaceChipView: View {
    let url: URL?
    let faceRect: CGRect?
    var size: CGFloat = 22

    @State private var image: CGImage?

    private static let cache = NSCache<NSString, CGImage>()

    var body: some View {
        Group {
            if let image {
                Image(decorative: image, scale: 1.0)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Image(systemName: "person.crop.circle.fill")
                    .resizable()
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .task(id: cacheKey) { await load() }
    }

    private var cacheKey: String {
        guard let url, let r = faceRect else { return "none" }
        return "\(url.path)|\(r.minX),\(r.minY),\(r.width),\(r.height)"
    }

    private func load() async {
        guard let url, let faceRect else { return }
        let key = cacheKey as NSString
        if let cached = Self.cache.object(forKey: key) { image = cached; return }

        let rect = faceRect
        let cropped: CGImage? = await Task.detached(priority: .utility) {
            guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
            let opts: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: 400,
                kCGImageSourceCreateThumbnailWithTransform: true
            ]
            guard let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary) else { return nil }
            let w = CGFloat(cg.width), h = CGFloat(cg.height)
            let px = CGRect(
                x: rect.minX * w,
                y: (1 - rect.maxY) * h,
                width: rect.width * w,
                height: rect.height * h
            ).integral
            guard px.width >= 1, px.height >= 1 else { return nil }
            return cg.cropping(to: px)
        }.value

        guard let cropped else { return }
        Self.cache.setObject(cropped, forKey: key)
        image = cropped
    }
}
