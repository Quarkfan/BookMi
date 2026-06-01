import Foundation
import GRDB

/// Repository for shelf CRUD operations
final class ShelfRepository {
    private let dbQueue: DatabaseQueue

    init(dbQueue: DatabaseQueue) {
        self.dbQueue = dbQueue
    }

    // MARK: - Fetch

    func fetchAll() async throws -> [Shelf] {
        try await dbQueue.read { (db: Database) in
            try Shelf
                .filter(Column("deleted_at") == nil)
                .order(Column("sort_order").asc, Column("name").asc)
                .fetchAll(db)
        }
    }

    func fetch(byID id: String) async throws -> Shelf? {
        try await dbQueue.read { (db: Database) in
            try Shelf.fetchOne(db, key: id)
        }
    }

    func fetchBookCount(forShelfID shelfID: String) async throws -> Int {
        try await dbQueue.read { (db: Database) in
            try Book
                .filter(Column("deleted_at") == nil)
                .filter(Column("shelf_id") == shelfID)
                .fetchCount(db)
        }
    }

    func fetchAllWithBookCounts() async throws -> [(shelf: Shelf, bookCount: Int)] {
        try await dbQueue.read { (db: Database) in
            let shelves = try Shelf
                .filter(Column("deleted_at") == nil)
                .order(Column("sort_order").asc, Column("name").asc)
                .fetchAll(db)

            return try shelves.map { shelf in
                let count = try Book
                    .filter(Column("deleted_at") == nil)
                    .filter(Column("shelf_id") == shelf.id)
                    .fetchCount(db)
                return (shelf, count)
            }
        }
    }

    // MARK: - Create/Update

    @discardableResult
    func insert(_ shelf: Shelf) async throws -> Shelf {
        try await dbQueue.write { (db: Database) in
            var shelf = shelf
            try shelf.insert(db)
            return shelf
        }
    }

    @discardableResult
    func update(_ shelf: Shelf) async throws -> Shelf {
        try await dbQueue.write { (db: Database) in
            var shelf = shelf
            shelf.updatedAt = ISO8601()
            try shelf.update(db)
            return shelf
        }
    }

    // MARK: - Delete

    /// Delete a shelf, moving its books to unclassified (shelf_id = nil)
    func deleteAndUnclassify(id: String) async throws {
        try await dbQueue.write { (db: Database) in
            try db.execute(
                sql: "UPDATE books SET shelf_id = NULL, updated_at = ? WHERE shelf_id = ?",
                arguments: [ISO8601(), id])
            try db.execute(
                sql: "UPDATE shelves SET deleted_at = ?, updated_at = ? WHERE id = ?",
                arguments: [ISO8601(), ISO8601(), id])
        }
    }

    func permanentDelete(id: String) async throws {
        try await dbQueue.write { (db: Database) in
            try Shelf.deleteOne(db, key: id)
        }
    }

    // MARK: - Find by name

    func fetch(byName name: String) async throws -> Shelf? {
        try await dbQueue.read { (db: Database) in
            try Shelf
                .filter(Column("deleted_at") == nil)
                .filter(Column("name") == name)
                .fetchOne(db)
        }
    }
}

private func ISO8601() -> String {
    ISO8601DateFormatter().string(from: Date())
}
