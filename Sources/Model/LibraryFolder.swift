import Foundation

struct LibraryFolder: Identifiable, Codable, Hashable {
    var id: UUID
    var name: String
    var path: String

    init(id: UUID = UUID(), name: String, path: String) {
        self.id = id
        self.name = name
        self.path = path
    }

    var url: URL? {
        URL(fileURLWithPath: path)
    }
}
