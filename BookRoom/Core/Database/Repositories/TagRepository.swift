import Foundation
import GRDB

final class TagRepository {
    private let dbQueue: DatabaseQueue
    init(dbQueue: DatabaseQueue) { self.dbQueue = dbQueue }

    func fetchAll() async throws -> [Tag] {
        try await dbQueue.read { db in
            try Tag.filter(Column("deleted_at") == nil)
                .order(Column("sort_order").asc, Column("name").asc)
                .fetchAll(db)
        }
    }

    func fetch(byID id: String) async throws -> Tag? {
        try await dbQueue.read { db in try Tag.fetchOne(db, key: id) }
    }

    func fetch(byName name: String) async throws -> Tag? {
        try await dbQueue.read { db in
            try Tag.filter(Column("deleted_at") == nil)
                .filter(Column("name") == name)
                .fetchOne(db)
        }
    }

    func fetchTags(forBookID bookID: String) async throws -> [Tag] {
        try await dbQueue.read { db in
            try Tag.filter(Column("deleted_at") == nil)
                .joining(required: BookTag.filter(Column("book_id") == bookID).annotated(with: [Column("tag_id")]))
                .order(Column("name").asc)
                .fetchAll(db)
        }
    }

    func fetchAllWithCounts() async throws -> [(tag: Tag, bookCount: Int)] {
        try await dbQueue.read { db in
            let tags = try Tag.filter(Column("deleted_at") == nil)
                .order(Column("name").asc)
                .fetchAll(db)
            return try tags.map { tag in
                let count = try BookTag.filter(Column("tag_id") == tag.id).fetchCount(db)
                return (tag, count)
            }
        }
    }

    @discardableResult func insert(_ tag: Tag) async throws -> Tag {
        try await dbQueue.write { db in
            var t = tag
            try t.insert(db)
            return t
        }
    }

    @discardableResult func update(_ tag: Tag) async throws -> Tag {
        try await dbQueue.write { db in
            var t = tag
            t.updatedAt = ISO8601()
            try t.update(db)
            return t
        }
    }

    func getOrCreate(name: String, color: String? = nil) async throws -> Tag {
        if let existing = try await fetch(byName: name) { return existing }
        let now = ISO8601()
        return try await insert(Tag(id: UUID().uuidString, name: name, color: color, sortOrder: 0, createdAt: now, updatedAt: now, deletedAt: nil))
    }

    func delete(id: String) async throws {
        try await dbQueue.write { db in
            try db.execute(sql: "DELETE FROM book_tags WHERE tag_id = ?", arguments: [id])
            try db.execute(sql: "DELETE FROM tags WHERE id = ?", arguments: [id])
        }
    }

    func addTag(tagID: String, toBook bookID: String) async throws {
        try await dbQueue.write { db in
            try BookTag(bookID: bookID, tagID: tagID, createdAt: ISO8601()).insert(db, onConflict: .ignore)
        }
    }

    func removeTag(tagID: String, fromBook bookID: String) async throws {
        try await dbQueue.write { db in
            try db.execute(sql: "DELETE FROM book_tags WHERE book_id = ? AND tag_id = ?", arguments: [bookID, tagID])
        }
    }

    func setTags(tagIDs: [String], forBook bookID: String) async throws {
        try await dbQueue.write { db in
            try db.execute(sql: "DELETE FROM book_tags WHERE book_id = ?", arguments: [bookID])
            for tagID in tagIDs {
                try BookTag(bookID: bookID, tagID: tagID, createdAt: ISO8601()).insert(db, onConflict: .ignore)
            }
        }
    }

    func addTags(tagIDs: [String], toBooks bookIDs: [String]) async throws {
        try await dbQueue.write { db in
            let now = ISO8601()
            for bookID in bookIDs {
                for tagID in tagIDs {
                    try BookTag(bookID: bookID, tagID: tagID, createdAt: now).insert(db, onConflict: .ignore)
                }
            }
        }
    }

    func removeTags(tagIDs: [String], fromBooks bookIDs: [String]) async throws {
        try await dbQueue.write { db in
            let ph = bookIDs.map { _ in "?" }.joined(separator: ",")
            let ph2 = tagIDs.map { _ in "?" }.joined(separator: ",")
            try db.execute(sql: "DELETE FROM book_tags WHERE book_id IN (\(ph)) AND tag_id IN (\(ph2))",
                arguments: bookIDs.map { .string($0) } + tagIDs.map { .string($0) })
        }
    }
}

private func ISO8601() -> String { ISO8601DateFormatter().string(from: Date()) }
