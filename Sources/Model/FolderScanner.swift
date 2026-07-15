import Foundation
import ImageIO

struct ExifInfo {
    var cameraModel: String?
    var lensModel: String?
    var focalLength: Double?
    var aperture: Double?
    var shutterSpeed: String?
    var iso: Int?
    var dateTakenOriginal: Date?
    var latitude: Double?
    var longitude: Double?
}

struct FolderScanner {
    private static let imageExtensions = PhotoItem.imageExtensions.union(PhotoItem.rawExtensions)
    private static let videoExtensions = PhotoItem.videoExtensions
    private static let supportedExtensions = imageExtensions.union(videoExtensions)

    /// Cheap stat-only pass — no file opens, no EXIF. `needsMetadata(path:size:date:)`
    /// decides per-file whether to pay for the ImageIO read (new or changed files only).
    /// `includeSubfolders: false` indexes only the folder's direct contents.
    static func scan(
        _ url: URL,
        includeSubfolders: Bool = true,
        needsMetadata: (String, Int64, Date) -> Bool = { _, _, _ in true }
    ) -> [PhotoItem] {
        var options: FileManager.DirectoryEnumerationOptions = [.skipsPackageDescendants, .skipsHiddenFiles]
        if !includeSubfolders {
            options.insert(.skipsSubdirectoryDescendants)
        }
        let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey, .isDirectoryKey],
            options: options
        )

        var items: [PhotoItem] = []
        let resourceKeys: Set<URLResourceKey> = [.fileSizeKey, .contentModificationDateKey, .isDirectoryKey]

        while let fileURL = enumerator?.nextObject() as? URL {
            guard let resourceValues = try? fileURL.resourceValues(forKeys: resourceKeys),
                  let isDirectory = resourceValues.isDirectory,
                  !isDirectory
            else { continue }

            let ext = fileURL.pathExtension.lowercased()
            guard supportedExtensions.contains(ext) else { continue }

            let fileSize = Int64(resourceValues.fileSize ?? 0)
            let modDate = resourceValues.contentModificationDate ?? Date()
            let folderPath = fileURL.deletingLastPathComponent().path
            let mediaKind: MediaKind = videoExtensions.contains(ext) ? .video : .image

            if needsMetadata(fileURL.path, fileSize, modDate) {
                let (width, height, exif) = mediaKind == .image
                    ? imageProperties(for: fileURL)
                    : (nil, nil, nil)
                items.append(PhotoItem(
                    url: fileURL,
                    fileSize: fileSize,
                    modificationDate: modDate,
                    folderPath: folderPath,
                    mediaKind: mediaKind,
                    width: width,
                    height: height,
                    cameraModel: exif?.cameraModel,
                    lensModel: exif?.lensModel,
                    focalLength: exif?.focalLength,
                    aperture: exif?.aperture,
                    shutterSpeed: exif?.shutterSpeed,
                    iso: exif?.iso,
                    dateTakenOriginal: exif?.dateTakenOriginal,
                    latitude: exif?.latitude,
                    longitude: exif?.longitude
                ))
            } else {
                items.append(PhotoItem(
                    url: fileURL,
                    fileSize: fileSize,
                    modificationDate: modDate,
                    folderPath: folderPath,
                    mediaKind: mediaKind
                ))
            }
        }

        return items
    }

    private static func imageProperties(for url: URL) -> (Int?, Int?, ExifInfo?) {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            return (nil, nil, nil)
        }
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any] else {
            return (nil, nil, nil)
        }
        let width = (properties[kCGImagePropertyPixelWidth as String] as? NSNumber)?.intValue
        let height = (properties[kCGImagePropertyPixelHeight as String] as? NSNumber)?.intValue

        var exif = ExifInfo()

        if let tiff = properties[kCGImagePropertyTIFFDictionary as String] as? [String: Any] {
            exif.cameraModel = (tiff[kCGImagePropertyTIFFModel as String] as? String)
        }

        if let maker = properties[kCGImagePropertyExifDictionary as String] as? [String: Any] {
            exif.lensModel = (maker[kCGImagePropertyExifLensModel as String] as? String)
            exif.focalLength = (maker[kCGImagePropertyExifFocalLength as String] as? NSNumber)?.doubleValue

            if let fNumber = maker[kCGImagePropertyExifFNumber as String] as? NSNumber {
                exif.aperture = fNumber.doubleValue
            }

            if let exposureTime = maker[kCGImagePropertyExifExposureTime as String] as? NSNumber {
                let t = exposureTime.doubleValue
                if t >= 1.0 {
                    exif.shutterSpeed = String(format: "%.0fs", t)
                } else {
                    let denom = Int(round(1.0 / t))
                    exif.shutterSpeed = "1/\(denom)s"
                }
            }

            if let isoValues = maker[kCGImagePropertyExifISOSpeedRatings as String] as? [NSNumber],
               let isoVal = isoValues.first {
                exif.iso = isoVal.intValue
            }

            if let dateString = maker[kCGImagePropertyExifDateTimeOriginal as String] as? String {
                let formatter = DateFormatter()
                formatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
                exif.dateTakenOriginal = formatter.date(from: dateString)
            }
        }

        // GPS values from ImageIO are positive decimal degrees; the Ref keys
        // (N/S, E/W) carry the sign.
        if let gps = properties[kCGImagePropertyGPSDictionary as String] as? [String: Any] {
            if let lat = (gps[kCGImagePropertyGPSLatitude as String] as? NSNumber)?.doubleValue {
                let ref = gps[kCGImagePropertyGPSLatitudeRef as String] as? String
                exif.latitude = (ref == "S") ? -lat : lat
            }
            if let lon = (gps[kCGImagePropertyGPSLongitude as String] as? NSNumber)?.doubleValue {
                let ref = gps[kCGImagePropertyGPSLongitudeRef as String] as? String
                exif.longitude = (ref == "W") ? -lon : lon
            }
        }

        let hasExif = exif.cameraModel != nil || exif.lensModel != nil
            || exif.focalLength != nil || exif.aperture != nil
            || exif.shutterSpeed != nil || exif.iso != nil
            || exif.dateTakenOriginal != nil
            || exif.latitude != nil || exif.longitude != nil

        return (width, height, hasExif ? exif : nil)
    }
}
