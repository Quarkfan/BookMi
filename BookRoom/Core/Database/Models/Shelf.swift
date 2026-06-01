import Foundation
import GRDB

struct Shelf: Codable, FetchableRecord, MutablePersistableRecord {
    static let databaseTableName = "shelves"

    var id: String
    var name: String
    var locationNote: String?
    var sortOrder: Int
    var note: String?
    var createdAt: String
    var updatedAt: String
    var deletedAt: String?

    enum CodingKeys: String, CodingKey {
        case id, name
        case locationNote = "location_note"
        case sortOrder = "sort_order", note
        case createdAt = "created_at", updatedAt = "updated_at"
        case deletedAt = "deleted_at"
    }

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID as? String ?? id
    }
}
