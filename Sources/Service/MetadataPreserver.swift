import Foundation
import ImageIO

enum MetadataPreserver {
    static func readProperties(from url: URL) -> [CFString: Any]? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
    }

    /// Builds the metadata dictionary to attach when writing a rendered image.
    ///
    /// Because `ImageProcessor` loads every image with
    /// `.applyOrientationProperty: true`, the pixel buffer is always upright.
    /// We therefore always strip both orientation tags so viewers don't
    /// double-rotate the already-upright pixels, regardless of whether
    /// the edit payload included an explicit rotation step.
    static func buildOutputProperties(
        from sourceURL: URL,
        extraProperties: [CFString: Any] = [:]
    ) -> [CFString: Any] {
        var props = readProperties(from: sourceURL) ?? [:]

        // Pixels are always written upright — drop both orientation tags.
        props[kCGImagePropertyOrientation] = nil
        if var tiff = props[kCGImagePropertyTIFFDictionary] as? [CFString: Any] {
            tiff[kCGImagePropertyTIFFOrientation] = nil
            props[kCGImagePropertyTIFFDictionary] = tiff
        }

        for (key, value) in extraProperties {
            props[key] = value
        }

        return props
    }
}
