import Foundation
import CoreLocation

struct PhotoItem: Identifiable, Hashable {
    var id: String { url.path }
    let url: URL
    let filename: String
    let fileSize: Int64
    let modificationDate: Date
    let folderPath: String
    var dotColor: Int = 0
    var isPinned: Bool = false
    var isStarred: Bool = false
    var trayOrder: Int?
    var width: Int?
    var height: Int?
    var cameraModel: String?
    var lensModel: String?
    var focalLength: Double?
    var aperture: Double?
    var shutterSpeed: String?
    var iso: Int?
    var dateTakenOriginal: Date?
    var latitude: Double?
    var longitude: Double?

    init(url: URL, fileSize: Int64, modificationDate: Date, folderPath: String = "", width: Int? = nil, height: Int? = nil, cameraModel: String? = nil, lensModel: String? = nil, focalLength: Double? = nil, aperture: Double? = nil, shutterSpeed: String? = nil, iso: Int? = nil, dateTakenOriginal: Date? = nil, latitude: Double? = nil, longitude: Double? = nil) {
        self.url = url
        self.filename = url.lastPathComponent
        self.fileSize = fileSize
        self.modificationDate = modificationDate
        self.folderPath = folderPath
        self.width = width
        self.height = height
        self.cameraModel = cameraModel
        self.lensModel = lensModel
        self.focalLength = focalLength
        self.aperture = aperture
        self.shutterSpeed = shutterSpeed
        self.iso = iso
        self.dateTakenOriginal = dateTakenOriginal
        self.latitude = latitude
        self.longitude = longitude
    }

    /// Valid map coordinate when both EXIF GPS components are present.
    var coordinate: CLLocationCoordinate2D? {
        guard let lat = latitude, let lon = longitude else { return nil }
        return CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }

    static let rawExtensions: Set<String> = [
        "cr2", "nef", "arw", "dng", "raw", "orf", "pef", "raf", "x3f", "sr2", "rw2"
    ]

    var isRaw: Bool {
        Self.rawExtensions.contains(url.pathExtension.lowercased())
    }

    /// The photo's real date: EXIF capture date when present, file
    /// modification date otherwise. All date grouping and sorting uses this —
    /// file copies update mtime, which made copied photos jump to "today".
    var displayDate: Date {
        dateTakenOriginal ?? modificationDate
    }

    var displaySize: String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: fileSize)
    }

    var dimensionsString: String {
        if let w = width, let h = height {
            return "\(w) × \(h)"
        }
        return ""
    }

    var aspectRatio: CGFloat? {
        guard let w = width, let h = height, h > 0 else { return nil }
        return CGFloat(w) / CGFloat(h)
    }

    var exifSummary: String? {
        var parts: [String] = []
        if let aperture = aperture {
            parts.append("f/\(String(format: "%.1f", aperture))")
        }
        if let shutter = shutterSpeed {
            parts.append(shutter)
        }
        if let iso = iso {
            parts.append("ISO \(iso)")
        }
        if let fl = focalLength {
            parts.append("\(String(format: "%.0f", fl))mm")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    var cameraSummary: String? {
        var parts: [String] = []
        if let cam = cameraModel { parts.append(cam) }
        if let lens = lensModel { parts.append(lens) }
        return parts.isEmpty ? nil : parts.joined(separator: " + ")
    }

    static func == (lhs: PhotoItem, rhs: PhotoItem) -> Bool {
        lhs.url == rhs.url
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(url)
    }
}

extension PhotoItem: CustomStringConvertible {
    var description: String { filename }
}
