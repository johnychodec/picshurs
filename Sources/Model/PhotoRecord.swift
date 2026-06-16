import Foundation
import GRDB

struct PhotoRecord: Codable, Identifiable {
    var id: Int64?
    var url: String
    var filename: String
    var fileSize: Int64
    var modificationDate: Date
    var folderPath: String
    var dotColor: Int
    var isPinned: Bool
    var isStarred: Bool
    var trayOrder: Int?
    var width: Double?
    var height: Double?
    var cameraModel: String?
    var lensModel: String?
    var focalLength: Double?
    var aperture: Double?
    var shutterSpeed: String?
    var iso: Int?
    var dateTakenOriginal: Date?
    var dayKey: String?
    var latitude: Double?
    var longitude: Double?
}

extension PhotoRecord: FetchableRecord, MutablePersistableRecord {
    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}

extension PhotoRecord {
    enum Columns: String, ColumnExpression {
        case id, url, filename, fileSize, modificationDate, folderPath
        case dotColor, isPinned, isStarred, trayOrder, width, height
        case cameraModel, lensModel, focalLength, aperture, shutterSpeed
        case iso, dateTakenOriginal, dayKey, latitude, longitude
    }

    static let databaseTableName = "photos"
}

extension PhotoRecord {
    func toPhotoItem() -> PhotoItem {
        var item = PhotoItem(
            url: URL(fileURLWithPath: url),
            fileSize: fileSize,
            modificationDate: modificationDate,
            folderPath: folderPath,
            width: width.map(Int.init),
            height: height.map(Int.init),
            cameraModel: cameraModel,
            lensModel: lensModel,
            focalLength: focalLength,
            aperture: aperture,
            shutterSpeed: shutterSpeed,
            iso: iso,
            dateTakenOriginal: dateTakenOriginal,
            latitude: latitude,
            longitude: longitude
        )
        item.dotColor = dotColor
        item.isPinned = isPinned
        item.isStarred = isStarred
        item.trayOrder = trayOrder
        return item
    }
}
