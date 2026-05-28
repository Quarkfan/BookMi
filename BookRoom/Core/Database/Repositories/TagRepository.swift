import Foundation
import GRDB

/// Repository for tag CRUD and book-tag association
final class TagRepository {
    private let dbQueue: DatabaseQueue

    init(dbQueue: DatabaseQueue) {
        self.dbQueue = dbQueue
    }

    // MARK: - Fetch

    func fetchAll() throws -> [Tag] {
        try dbQueue.read { db in
            try Tag
                .filter(Column("deleted_at") == nil)
                .order(Column("sort_order").asc, Column("name").asc)
                .fetchAll(db)
        }
    }

    func fetch(byID id: String) throws -> Tag? {
        try dbQueue.read { db in
            try Tag.fetchOne(db, id: id)
        }
    }

    func fetch(byName name: String) throws -> Tag? {
        try dbQueue.read { db in
            try Tag
                .filter(Column("deleted_at") == nil)
                .filter(Column("name") == name)
                .fetchOne(db)
        }
    }

    func fetchTags(forBookID bookID: String) throws -> [Tag] {
        try dbQueue.read { db in
            try Tag
                .filter(Column("deleted_at") == nil)
                .joining(required: BookTag.filter(Column("book_id") == bookID).annotated(with: [Column("tag_id")]))
                .order(Column("name").asc)
                .fetchAll(db)
        }
    }

    func fetchAllWithCounts() throws -> [(tag: Tag, bookCount: Int)] {
        try dbQueue.read { db in
            let tags = try Tag
                .filter(Column("deleted_at") == nil)
                .order(Column("name").asc)
                .fetchAll(db)

            return try tags.map { tag in
                let count = try BookTag
                    .filter(Column("tag_id") == tag.id)
                    .fetchCount(db)
                return (tag, count)
            }
        }
    }

    // MARK: - Create/Update

    @discardableResult
    func insert(_ tag: Tag) throws -> Tag {
        try dbQueue.write { db in
            var tag = tag
            try tag.insert(db)
            return tag
        }
    }

    @discardableResult
    func update(_ tag: Tag) throws -> Tag {
        try dbQueue.write { db in
            var tag = tag
            tag.updatedAt = ISO8601()
            try tag.update(db)
            return tag
        }
    }

    /// Get or create a tag by name
    func getOrCreate(name: String, color: String? = nil) throws -> Tag {
        if let existing = try fetch(byName: name) {
            return existing
        }
        let newTag = Tag(
            id: UUID().uuidString,
            name: name,
            color: color,
            sortOrder: 0,
            createdAt: ISO8601(),
            updatedAt: ISO8601(),
            deletedAt: nil)
        return try insert(newTag)
    }

    // MARK: - Delete

    func delete(id: String) throws {
        try dbQueue.write { db in
            try db.execute(
                sql: "DELETE FROM book_tags WHERE tag_id = ?",
                arguments: [id])
            try db.execute(
                sql: "DELETE FROM tags WHERE id = ?",
                arguments: [id])
        }
    }

    // MARK: - Book-Tag Association

    func addTag(tagID: String, toBook bookID: String) throws {
        try dbQueue.write { db in
            let relation = BookTag(
                bookID: bookID,
                tagID: tagID,
                createdAt: ISO8601())
            try relation.insert(db, onConflict: .ignore)
        }
    }

    func removeTag(tagID: String, fromBook bookID: String) throws {
        try dbQueue.write { db in
            try db.execute(
                sql: "DELETE FROM book_tags WHERE book_id = ? AND tag_id = ?",
                arguments: [bookID, tagID])
        }
    }

    func setTags(tagIDs: [String], forBook bookID: String) throws {
        try dbQueue.write { db in
            try db.execute(
                sql: "DELETE FROM book_tags WHERE book_id = ?",
                arguments: [bookID])
            for tagID in tagIDs {
                let relation = BookTag(
                    bookID: bookID,
                    tagID: tagID,
                    createdAt: ISO8601())
                try relation.insert(db, onConflict: .ignore)
            }
        }
    }

    func addTags(tagIDs: [String], toBooks bookIDs: [String]) throws {
        try dbQueue.write { db in
            let now = ISO8601()
            for bookID in bookIDs {
                for tagID in tagIDs {
                    let relation = BookTag(
                        bookID: bookID,
                        tagID: tagID,
                        createdAt: now)
                    try relation.insert(db, onConflict: .ignore)
                }
            }
        }
    }

    func removeTags(tagIDs: [String], fromBooks bookIDs: [String]) throws {
        try dbQueue.write { db in
            let placeholders = bookIDs.map { _ in "?" }.joined(separator: ",")
            try db.execute(
                sql: "DELETE FROM book_tags WHERE book_id IN (\(placeholders)) AND tag_id IN (\(tagIDs.map { _ in "?" }.joined(separator: ",")))",
                arguments: bookIDs.map { .string($0) } + tagIDs.map { .string($0) })
        }
    }
}

private func ISO8601() -> String {
    ISO8601DateFormatter().string(from: Date())
}
