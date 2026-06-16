import CoreGraphics
import CoreImage
import ImageIO
import UniformTypeIdentifiers

/// Strips all EXIF, GPS, XMP, IPTC, and other metadata from an image file
/// while preserving the original image format and ICC color profile.
enum MetadataStripper {
    static func stripMetadata(from sourceURL: URL, to destURL: URL) throws {
        guard FileManager.default.isReadableFile(atPath: sourceURL.path) else {
            throw StripError.unreadableSource
        }

        let ext = sourceURL.pathExtension.lowercased()
        let uti = utType(for: ext)

        guard let source = CGImageSourceCreateWithURL(sourceURL as CFURL, nil) else {
            throw StripError.createSourceFailed
        }

        let options: [CFString: Any] = [
            kCGImageSourceShouldCache: false,
            kCGImageSourceCreateThumbnailFromImageAlways: false
        ]
        guard let cgImage = CGImageSourceCreateImageAtIndex(source, 0, options as CFDictionary) else {
            throw StripError.createImageFailed
        }

        // CGImage retains color space (ICC profile) from the source image.
        // Passing it to CGImageDestinationAddImage preserves color accuracy
        // while EXIF/GPS/XMP/comment metadata are dropped.
        var properties: [CFString: Any] = [:]

        guard let destination = CGImageDestinationCreateWithURL(
            destURL as CFURL,
            uti,
            1,
            nil
        ) else {
            throw StripError.createDestinationFailed
        }

        // Max JPEG quality to minimize generational loss
        if ext == "jpg" || ext == "jpeg" {
            properties[kCGImageDestinationLossyCompressionQuality] = 1.0
        }

        CGImageDestinationAddImage(destination, cgImage, properties as CFDictionary)

        if !CGImageDestinationFinalize(destination) {
            throw StripError.finalizeFailed
        }
    }

    private static func utType(for ext: String) -> CFString {
        switch ext {
        case "jpg", "jpeg": return UTType.jpeg.identifier as CFString
        case "png": return UTType.png.identifier as CFString
        case "heic": return UTType.heic.identifier as CFString
        case "tiff", "tif": return UTType.tiff.identifier as CFString
        case "bmp": return UTType.bmp.identifier as CFString
        case "gif": return UTType.gif.identifier as CFString
        case "webp": return UTType.webP.identifier as CFString
        default: return UTType.jpeg.identifier as CFString
        }
    }

    enum StripError: Error, LocalizedError {
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
