import Foundation
import GRDB

/// One detected face. `rect*` are the normalized Vision boundingBox
/// (bottom-left origin). `featurePrint` is an archived `VNFeaturePrintObservation`
/// computed on the cropped face, used for clustering. `personId` links to a
/// `PersonRecord` once clustered.
struct FaceRecord: Codable, Identifiable {
    var id: Int64?
    var photoURL: String
    var rectX: Double
    var rectY: Double
    var rectW: Double
    var rectH: Double
    var featurePrint: Data?
    var personId: String?
}

extension FaceRecord: FetchableRecord, MutablePersistableRecord {
    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }

    enum Columns: String, ColumnExpression {
        case id, photoURL, rectX, rectY, rectW, rectH, featurePrint, personId
    }

    static let databaseTableName = "faces"
}
