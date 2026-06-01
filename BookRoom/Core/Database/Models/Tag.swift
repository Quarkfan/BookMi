import Foundation
import GRDB

struct Tag: Codable, FetchableRecord, MutablePersistableRecord {
    static let databaseTableName = "tags"

    var id: String
    var name: String
    var color: String?
    var sortOrder: Int
    var createdAt: String
    var updatedAt: String
    var deletedAt: String?

    enum CodingKeys: String, CodingKey {
        case id, name, color
        case sortOrder = "sort_order"
        case createdAt = "created_at", updatedAt = "updated_at"
        case deletedAt = "deleted_at"
    }

}

struct BookTag: Codable, FetchableRecord, MutablePersistableRecord {
    static let databaseTableName = "book_tags"

    var bookID: String
    var tagID: String
    var createdAt: String

    enum CodingKeys: String, CodingKey {
        case bookID = "book_id", tagID = "tag_id"
        case createdAt = "created_at"
    }
}
