import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

enum WebOptimizer {
    static func optimize(
        forWeb sourceURL: URL,
        to destURL: URL,
        maxDimension: Int = 2048,
        quality: CGFloat = 0.82
    ) throws {
        guard FileManager.default.isReadableFile(atPath: sourceURL.path) else {
            throw OptimizeError.unreadableSource
        }

        guard let source = CGImageSourceCreateWithURL(sourceURL as CFURL, nil) else {
            throw OptimizeError.createSourceFailed
        }

        let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let originalWidth = props?[kCGImagePropertyPixelWidth] as? Int ?? 0
        let originalHeight = props?[kCGImagePropertyPixelHeight] as? Int ?? 0
        let longest = max(originalWidth, originalHeight)

        let cgImage: CGImage
        if longest > maxDimension {
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: maxDimension,
                kCGImageSourceShouldCache: false
            ]
            guard let thumb = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
                throw OptimizeError.createImageFailed
            }
            cgImage = thumb
        } else {
            let options: [CFString: Any] = [
                kCGImageSourceShouldCache: false
            ]
            guard let full = CGImageSourceCreateImageAtIndex(source, 0, options as CFDictionary) else {
                throw OptimizeError.createImageFailed
            }
            cgImage = full
        }

        let hasAlpha = cgImage.hasAlpha
        let outputUTType: UTType = hasAlpha ? .png : .jpeg

        guard let destination = CGImageDestinationCreateWithURL(
            destURL as CFURL,
            outputUTType.identifier as CFString,
            1,
            nil
        ) else {
            throw OptimizeError.createDestinationFailed
        }

        let properties: [CFString: Any] = hasAlpha
            ? [:]  // PNG is lossless — no quality parameter
            : [kCGImageDestinationLossyCompressionQuality: quality]

        CGImageDestinationAddImage(destination, cgImage, properties as CFDictionary)

        if !CGImageDestinationFinalize(destination) {
            throw OptimizeError.finalizeFailed
        }
    }

    static func fileExtension(for sourceURL: URL) -> String {
        guard let source = CGImageSourceCreateWithURL(sourceURL as CFURL, nil),
              let full = CGImageSourceCreateImageAtIndex(source, 0, [
                kCGImageSourceShouldCache: false
              ] as CFDictionary) else {
            return "jpg"
        }
        return full.hasAlpha ? "png" : "jpg"
    }

    enum OptimizeError: Error, LocalizedError {
        case unreadableSource
        case createSourceFailed
        case createImageFailed
        case createDestinationFailed
        case finalizeFailed

        var errorDescription: String? {
            switch self {
            case .unreadableSource: return "Source file is not readable."
            case .createSourceFailed: return "Failed to create image source."
            case .createImageFailed: return "Failed to decode image."
            case .createDestinationFailed: return "Failed to create image destination."
            case .finalizeFailed: return "Failed to finalize image write."
            }
        }
    }
}

private extension CGImage {
    var hasAlpha: Bool {
        switch alphaInfo {
        case .first, .last, .premultipliedFirst, .premultipliedLast, .alphaOnly:
            return true
        case .none, .noneSkipFirst, .noneSkipLast:
            return false
        @unknown default:
            return false
        }
    }
}
