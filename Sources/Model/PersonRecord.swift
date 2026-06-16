import Foundation
import GRDB

/// A clustered person. `id` is a caller-assigned UUID string (so this is a
/// non-mutable `PersistableRecord`). `name` is nil until the user renames;
/// `isHidden` removes the person from the sidebar without deleting its faces
/// (so they aren't re-clustered into a new person on the next scan).
struct PersonRecord: Codable, Identifiable {
    var id: String
    var name: String?
    var isHidden: Bool
    var coverFaceId: Int64?
}

extension PersonRecord: FetchableRecord, PersistableRecord {
    enum Columns: String, ColumnExpression {
        case id, name, isHidden, coverFaceId
    }

    static let databaseTableName = "persons"
}
