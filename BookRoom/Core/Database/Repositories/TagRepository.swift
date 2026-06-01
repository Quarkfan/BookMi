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
            let ids = try BookTag.filter(Column("book_id") == bookID).fetchAll(db).map(\.tagID)
            guard !ids.isEmpty else { return [] }
            return try Tag.filter(Column("deleted_at") == nil)
                .filter(ids.contains(Column("id")))
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
        let now = ISO8601()
        try await dbQueue.writeWithoutTransaction { db in
            try db.execute(sql: """
                INSERT INTO tags (id, name, color, sort_order, created_at, updated_at, deleted_at)
                VALUES (?, ?, ?, ?, ?, ?, ?)
                """, arguments: [tag.id, tag.name, tag.color, tag.sortOrder, now, now, tag.deletedAt])
        }
        return tag
    }

    @discardableResult func update(_ tag: Tag) async throws -> Tag {
        let now = ISO8601()
        try await dbQueue.writeWithoutTransaction { db in
            try db.execute(sql: """
                UPDATE tags SET name=?, color=?, sort_order=?, updated_at=? WHERE id=?
                """, arguments: [tag.name, tag.color, tag.sortOrder, now, tag.id])
        }
        return tag
    }

    func getOrCreate(name: String, color: String? = nil) async throws -> Tag {
        if let existing = try await fetch(byName: name) { return existing }
        let newTag = Tag(id: UUID().uuidString, name: name, color: color, sortOrder: 0, createdAt: ISO8601(), updatedAt: ISO8601(), deletedAt: nil)
        return try await insert(newTag)
    }

    func delete(id: String) async throws {
        try await dbQueue.writeWithoutTransaction { db in
            try db.execute(sql: "DELETE FROM book_tags WHERE tag_id=?", arguments: [id])
            try db.execute(sql: "DELETE FROM tags WHERE id=?", arguments: [id])
        }
    }

    func addTag(tagID: String, toBook bookID: String) async throws {
        let now = ISO8601()
        try await dbQueue.writeWithoutTransaction { db in
            try db.execute(sql: "INSERT INTO book_tags (book_id, tag_id, created_at) VALUES (?, ?, ?)",
                arguments: [bookID, tagID, now])
        }
    }

    func removeTag(tagID: String, fromBook bookID: String) async throws {
        try await dbQueue.writeWithoutTransaction { db in
            try db.execute(sql: "DELETE FROM book_tags WHERE book_id=? AND tag_id=?", arguments: [bookID, tagID])
        }
    }

    func setTags(tagIDs: [String], forBook bookID: String) async throws {
        let now = ISO8601()
        try await dbQueue.writeWithoutTransaction { db in
            try db.execute(sql: "DELETE FROM book_tags WHERE book_id=?", arguments: [bookID])
            for tagID in tagIDs {
                try db.execute(sql: "INSERT INTO book_tags (book_id, tag_id, created_at) VALUES (?, ?, ?)",
                    arguments: [bookID, tagID, now])
            }
        }
    }

    func addTags(tagIDs: [String], toBooks bookIDs: [String]) async throws {
        let now = ISO8601()
        try await dbQueue.writeWithoutTransaction { db in
            for bookID in bookIDs {
                for tagID in tagIDs {
                    try db.execute(sql: "INSERT INTO book_tags (book_id, tag_id, created_at) VALUES (?, ?, ?)",
                        arguments: [bookID, tagID, now])
                }
            }
        }
    }

    func removeTags(tagIDs: [String], fromBooks bookIDs: [String]) async throws {
        try await dbQueue.writeWithoutTransaction { db in
            let ph1 = bookIDs.map { _ in "?" }.joined(separator: ",")
            let ph2 = tagIDs.map { _ in "?" }.joined(separator: ",")
            var args: [any DatabaseValueConvertible] = bookIDs
            args.append(contentsOf: tagIDs)
            try db.execute(sql: "DELETE FROM book_tags WHERE book_id IN (\(ph1)) AND tag_id IN (\(ph2))",
                arguments: args)
        }
    }
}

private func ISO8601() -> String { ISO8601DateFormatter().string(from: Date()) }
