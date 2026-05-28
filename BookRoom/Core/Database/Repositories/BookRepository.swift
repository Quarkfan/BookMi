import Foundation
import GRDB

/// Repository for book CRUD operations
final class BookRepository {
    private let dbQueue: DatabaseQueue

    init(dbQueue: DatabaseQueue) {
        self.dbQueue = dbQueue
    }

    // MARK: - Fetch

    func fetchAll(excludeDeleted: Bool = true, limit: Int? = nil, offset: Int = 0) throws -> [Book] {
        try dbQueue.read { db in
            var query = Book.all()
            if excludeDeleted {
                query = query.filter(Column("deleted_at") == nil)
            }
            if let limit {
                query = query.limit(limit, offset: offset)
            }
            return try query.order(Column("created_at").desc).fetchAll(db)
        }
    }

    func fetchCount(excludeDeleted: Bool = true) throws -> Int {
        try dbQueue.read { db in
            var query = Book.all()
            if excludeDeleted {
                query = query.filter(Column("deleted_at") == nil)
            }
            return try query.fetchCount(db)
        }
    }

    func fetch(byID id: String) throws -> Book? {
        try dbQueue.read { db in
            try Book.fetchOne(db, id: id)
        }
    }

    func fetch(byISBN isbn: String) throws -> [Book] {
        try dbQueue.read { db in
            try Book
                .filter(Column("deleted_at") == nil)
                .filter(Column("isbn10") == isbn || Column("isbn13") == isbn)
                .fetchAll(db)
        }
    }

    func fetch(byShelfID shelfID: String) throws -> [Book] {
        try dbQueue.read { db in
            try Book
                .filter(Column("deleted_at") == nil)
                .filter(Column("shelf_id") == shelfID)
                .order(Column("created_at").desc)
                .fetchAll(db)
        }
    }

    func fetch(byTagID tagID: String) throws -> [Book] {
        try dbQueue.read { db in
            try Book
                .filter(Column("deleted_at") == nil)
                .joining(optional: BookTag.filter(Column("tag_id") == tagID))
                .order(Column("created_at").desc)
                .fetchAll(db)
        }
    }

    // MARK: - Create/Update

    @discardableResult
    func insert(_ book: Book) throws -> Book {
        try dbQueue.write { db in
            var book = book
            try book.insert(db)
            return book
        }
    }

    @discardableResult
    func update(_ book: Book) throws -> Book {
        try dbQueue.write { db in
            var book = book
            book.updatedAt = ISO8601()
            try book.update(db)
            return book
        }
    }

    // MARK: - Delete (soft)

    func softDelete(id: String) throws {
        try dbQueue.write { db in
            try db.execute(
                sql: "UPDATE books SET deleted_at = ?, updated_at = ? WHERE id = ?",
                arguments: [ISO8601(), ISO8601(), id])
        }
    }

    func softDelete(ids: [String]) throws {
        try dbQueue.write { db in
            try db.execute(
                sql: "UPDATE books SET deleted_at = ?, updated_at = ? WHERE id IN (?)",
                arguments: [ISO8601(), ISO8601(), ids.joined(separator: ",")])
        }
    }

    func permanentDelete(id: String) throws {
        try dbQueue.write { db in
            try Book.deleteOne(db, id: id)
        }
    }

    // MARK: - Batch Operations

    func batchUpdateShelf(bookIDs: [String], shelfID: String?) throws {
        try dbQueue.write { db in
            let shelfValue: DatabaseValue = shelfID.map { .string($0) } ?? .null
            try db.execute(
                sql: """
                UPDATE books SET shelf_id = ?, updated_at = ? WHERE id IN (\(bookIDs.map { _ in "?" }.joined(separator: ",")))
                """,
                arguments: [shelfValue, ISO8601()] + bookIDs.map { .string($0) })
        }
    }

    func batchUpdateReadingStatus(bookIDs: [String], status: ReadingStatus) throws {
        try dbQueue.write { db in
            try db.execute(
                sql: """
                UPDATE books SET reading_status = ?, updated_at = ? WHERE id IN (\(bookIDs.map { _ in "?" }.joined(separator: ",")))
                """,
                arguments: [status.rawValue, ISO8601()] + bookIDs.map { .string($0) })
        }
    }

    func batchMarkFinished(bookIDs: [String]) throws {
        try dbQueue.write { db in
            try db.execute(
                sql: """
                UPDATE books SET reading_status = 'finished', progress_percent = 100, finished_at = ?, updated_at = ?
                WHERE id IN (\(bookIDs.map { _ in "?" }.joined(separator: ",")))
                """,
                arguments: [ISO8601(), ISO8601()] + bookIDs.map { .string($0) })
        }
    }

    // MARK: - Statistics

    func countByYear() throws -> [(year: String, count: Int)] {
        try dbQueue.read { db in
            try Row.fetchAll(db, sql: """
                SELECT strftime('%Y', created_at) as year, COUNT(*) as count
                FROM books
                WHERE deleted_at IS NULL
                GROUP BY year
                ORDER BY year DESC
            """).map { ($0["year"] as String, $0["count"] as Int) }
        }
    }

    func countByShelf() throws -> [(shelfID: String?, shelfName: String?, count: Int)] {
        try dbQueue.read { db in
            try Row.fetchAll(db, sql: """
                SELECT b.shelf_id, s.name as shelf_name, COUNT(*) as count
                FROM books b
                LEFT JOIN shelves s ON b.shelf_id = s.id
                WHERE b.deleted_at IS NULL
                GROUP BY b.shelf_id
                ORDER BY count DESC
            """).map { ($0["shelf_id"] as String?, $0["shelf_name"] as String?, $0["count"] as Int) }
        }
    }

    func countByReadingStatus() throws -> [(status: String, count: Int)] {
        try dbQueue.read { db in
            try Row.fetchAll(db, sql: """
                SELECT reading_status as status, COUNT(*) as count
                FROM books
                WHERE deleted_at IS NULL
                GROUP BY reading_status
            """).map { ($0["status"] as String, $0["count"] as Int) }
        }
    }

    func countDuplicatesByISBN() throws -> [(isbn: String, count: Int)] {
        try dbQueue.read { db in
            try Row.fetchAll(db, sql: """
                SELECT COALESCE(isbn13, isbn10) as isbn, COUNT(*) as count
                FROM books
                WHERE deleted_at IS NULL AND (isbn10 IS NOT NULL OR isbn13 IS NOT NULL)
                GROUP BY COALESCE(isbn13, isbn10)
                HAVING count > 1
                ORDER BY count DESC
            """).map { ($0["isbn"] as String, $0["count"] as Int) }
        }
    }

    func countByPublisher() throws -> [(name: String, count: Int)] {
        try dbQueue.read { db in
            try Row.fetchAll(db, sql: """
                SELECT publisher as name, COUNT(*) as count
                FROM books
                WHERE deleted_at IS NULL AND publisher IS NOT NULL
                GROUP BY publisher
                ORDER BY count DESC
                LIMIT 20
            """).map { ($0["name"] as String, $0["count"] as Int) }
        }
    }

    func countByPurchaseChannel() throws -> [(name: String?, count: Int)] {
        try dbQueue.read { db in
            try Row.fetchAll(db, sql: """
                SELECT pc.name as name, COUNT(*) as count
                FROM books b
                LEFT JOIN purchase_channels pc ON b.purchase_channel_id = pc.id
                WHERE b.deleted_at IS NULL
                GROUP BY b.purchase_channel_id
                ORDER BY count DESC
            """).map { ($0["name"] as String?, $0["count"] as Int) }
        }
    }

    func countMissingISBN() throws -> Int {
        try dbQueue.read { db in
            try Int.fetchOne(db, sql: """
                SELECT COUNT(*) FROM books
                WHERE deleted_at IS NULL AND isbn10 IS NULL AND isbn13 IS NULL
            """) ?? 0
        }
    }

    func countMissingCovers() throws -> Int {
        try dbQueue.read { db in
            try Int.fetchOne(db, sql: """
                SELECT COUNT(*) FROM books
                WHERE deleted_at IS NULL AND cover_file_name IS NULL
            """) ?? 0
        }
    }

    func countMissingShelf() throws -> Int {
        try dbQueue.read { db in
            try Int.fetchOne(db, sql: """
                SELECT COUNT(*) FROM books
                WHERE deleted_at IS NULL AND shelf_id IS NULL
            """) ?? 0
        }
    }
}

// MARK: - ISBN Helper

extension BookRepository {
    /// Normalize ISBN string
    static func normalizeISBN(_ isbn: String) -> String {
        isbn.replacingOccurrences(of: "-", with: "").replacingOccurrences(of: " ", with: "")
    }

    /// Validate and normalize ISBN
    static func parseISBN(_ raw: String) -> (isbn10: String?, isbn13: String?) {
        let cleaned = normalizeISBN(raw)
        if cleaned.count == 13 {
            return (nil, cleaned)
        } else if cleaned.count == 10 {
            return (cleaned, nil)
        }
        return (nil, nil)
    }
}

private func ISO8601() -> String {
    ISO8601DateFormatter().string(from: Date())
}
