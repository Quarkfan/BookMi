import Foundation
import GRDB

struct BorrowRecord: Codable, FetchableRecord, MutablePersistableRecord {
    static let databaseTableName = "borrow_records"

    var id: String
    var bookID: String
    var borrowerName: String
    var contact: String?
    var borrowedAt: String
    var expectedReturnAt: String?
    var returnedAt: String?
    var status: String
    var note: String?
    var createdAt: String
    var updatedAt: String

    enum CodingKeys: String, CodingKey {
        case id
        case bookID = "book_id"
        case borrowerName = "borrower_name"
        case contact
        case borrowedAt = "borrowed_at"
        case expectedReturnAt = "expected_return_at"
        case returnedAt = "returned_at"
        case status, note
        case createdAt = "created_at", updatedAt = "updated_at"
    }

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID.value as? String ?? id
    }
}

struct PurchaseChannel: Codable, FetchableRecord, MutablePersistableRecord {
    static let databaseTableName = "purchase_channels"

    var id: String
    var name: String
    var sortOrder: Int
    var createdAt: String
    var updatedAt: String
    var deletedAt: String?

    enum CodingKeys: String, CodingKey {
        case id, name
        case sortOrder = "sort_order"
        case createdAt = "created_at", updatedAt = "updated_at"
        case deletedAt = "deleted_at"
    }

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID.value as? String ?? id
    }
}
