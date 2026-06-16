import Foundation
import ImageIO
import QuickLookThumbnailing
import CryptoKit

actor ThumbnailService {
    static let shared = ThumbnailService()

    // NSCache is documented thread-safe — nonisolated(unsafe) lets the
    // synchronous cachedThumbnail() peek read it from the main thread.
    nonisolated(unsafe) private let cache = NSCache<NSString, CGImageWrapper>()
    private let cacheDir: URL
    private var runningTasks = 0
    private let maxConcurrent = max(4, ProcessInfo.processInfo.activeProcessorCount)
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private var lastKeyForPath: [String: String] = [:]

    static let gridTier = 256
    static let detailTier = 1024

    private init() {
        cache.totalCostLimit = 384 * 1024 * 1024
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        cacheDir = caches.appendingPathComponent("com.picshurs.thumbnails")
        try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
    }

    private static func cacheKey(for path: String, modificationDate: Date, tier: Int) -> String {
        let raw = "\(path)_\(modificationDate.timeIntervalSince1970)_\(tier)"
        let digest = SHA256.hash(data: Data(raw.utf8))
        return digest.compactMap { String(format: "%02x", $0) }.joined()
    }

    private func cacheKey(for path: String, modificationDate: Date, tier: Int) -> String {
        Self.cacheKey(for: path, modificationDate: modificationDate, tier: tier)
    }

    /// Synchronous memory-cache peek — lets a freshly recreated cell render its
    /// image on first frame instead of flashing the placeholder while the
    /// actor-isolated async path round-trips.
    nonisolated func cachedThumbnail(for url: URL, modificationDate: Date, tier: Int = ThumbnailService.gridTier) -> CGImage? {
        let key = Self.cacheKey(for: url.path, modificationDate: modificationDate, tier: tier)
        return cache.object(forKey: key as NSString)?.image
    }

    private func diskCacheURL(for path: String, modificationDate: Date, tier: Int) -> URL {
        cacheDir.appendingPathComponent(cacheKey(for: path, modificationDate: modificationDate, tier: tier) + ".jpg")
    }

    private func acquireSlot() async {
        if runningTasks < maxConcurrent {
            runningTasks += 1
            return
        }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    private func releaseSlot() {
        if let waiter = waiters.first {
            waiters.removeFirst()
            waiter.resume()
        } else {
            runningTasks -= 1
        }
    }

    func thumbnail(for url: URL, modificationDate: Date, tier: Int = gridTier) async -> CGImage? {
        let path = url.path
        let key = cacheKey(for: path, modificationDate: modificationDate, tier: tier)
        let nsKey = key as NSString

        if let cached = cache.object(forKey: nsKey) {
            return cached.image
        }

        let diskURL = diskCacheURL(for: path, modificationDate: modificationDate, tier: tier)
        if let diskImage = loadFromDisk(diskURL) {
            let cost = diskImage.bytesPerRow * diskImage.height
            cache.setObject(CGImageWrapper(diskImage), forKey: nsKey, cost: cost)
            lastKeyForPath[path] = key
            return diskImage
        }

        if Task.isCancelled { return nil }

        await acquireSlot()
        defer { releaseSlot() }

        if Task.isCancelled { return nil }

        if let image = imageIOThumbnail(for: url, maxPixelSize: tier) {
            let cost = image.bytesPerRow * image.height
            saveToDisk(image, at: diskURL)
            cache.setObject(CGImageWrapper(image), forKey: nsKey, cost: cost)
            lastKeyForPath[path] = key
            return image
        }

        if Task.isCancelled { return nil }

        if let image = await qlThumbnail(for: url, size: tier) {
            let cost = image.bytesPerRow * image.height
            saveToDisk(image, at: diskURL)
            cache.setObject(CGImageWrapper(image), forKey: nsKey, cost: cost)
            lastKeyForPath[path] = key
            return image
        }

        return nil
    }

    func invalidate(path: String) {
        if let key = lastKeyForPath[path] {
            cache.removeObject(forKey: key as NSString)
            lastKeyForPath.removeValue(forKey: path)
        }
    }

    private func imageIOThumbnail(for url: URL, maxPixelSize: Int) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageIfAbsent: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    private func qlThumbnail(for url: URL, size: Int) async -> CGImage? {
        await withCheckedContinuation { continuation in
            let cgSize = CGSize(width: size, height: size)
            let request = QLThumbnailGenerator.Request(
                fileAt: url,
                size: cgSize,
                scale: 1.0,
                representationTypes: .thumbnail
            )
            QLThumbnailGenerator.shared.generateRepresentations(for: request) { thumbnail, _, error in
                guard let thumbnail = thumbnail, error == nil else {
                    continuation.resume(returning: nil)
                    return
                }
                continuation.resume(returning: thumbnail.cgImage)
            }
        }
    }

    private func loadFromDisk(_ url: URL) -> CGImage? {
        guard let data = try? Data(contentsOf: url),
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else { return nil }
        return image
    }

    private func saveToDisk(_ image: CGImage, at url: URL) {
        let tmpURL = url.appendingPathExtension("tmp")
        guard let destination = CGImageDestinationCreateWithURL(
            tmpURL as CFURL, "public.jpeg" as CFString, 1, nil
        ) else { return }
        CGImageDestinationAddImage(
            destination, image,
            [kCGImageDestinationLossyCompressionQuality: 0.7] as CFDictionary
        )
        guard CGImageDestinationFinalize(destination) else {
            try? FileManager.default.removeItem(at: tmpURL)
            return
        }
        _ = try? FileManager.default.replaceItemAt(url, withItemAt: tmpURL, backupItemName: nil, options: [])
    }
}

final class CGImageWrapper {
    let image: CGImage
    init(_ image: CGImage) { self.image = image }
}
