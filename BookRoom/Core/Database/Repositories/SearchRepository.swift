import Foundation
import GRDB

final class SearchRepository {
    private let dbQueue: DatabaseQueue
    init(dbQueue: DatabaseQueue) { self.dbQueue = dbQueue }

    func search(keyword: String, limit: Int = 100) async throws -> [Book] {
        let trimmed = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        let pe = Pinyin.analyze(trimmed)

        return try await dbQueue.read { db in
            let ftsResults = try Row.fetchAll(db, sql: """
                SELECT fts.book_id FROM books_fts fts WHERE books_fts MATCH ? LIMIT ?
            """, arguments: [trimmed.replacingOccurrences(of: "\"", with: "\"\""), limit])

            let ftsIDs = Set(ftsResults.map { $0["book_id"] as String })

            let pinyinResults = try Row.fetchAll(db, sql: """
                SELECT book_id FROM search_index
                WHERE pinyin_title_full LIKE ? OR pinyin_title_initials LIKE ?
                   OR pinyin_authors_full LIKE ? OR pinyin_authors_initials LIKE ?
                LIMIT ?
            """, arguments: ["%\(pe.full)%", "%\(pe.initials)%", "%\(pe.full)%", "%\(pe.initials)%", limit])

            let pinyinIDs = Set(pinyinResults.map { $0["book_id"] as String })
            let allIDs = Array(ftsIDs.union(pinyinIDs))
            guard !allIDs.isEmpty else { return [] }

            let ph = allIDs.map { _ in "?" }.joined(separator: ",")
            return try Book.fetchAll(db, sql: """
                SELECT * FROM books WHERE id IN (\(ph)) AND deleted_at IS NULL
            """, arguments: allIDs.map { .string($0) })
        }
    }

    func searchWithLike(keyword: String, limit: Int = 100) async throws -> [Book] {
        let trimmed = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        let pe = Pinyin.analyze(trimmed)
        let kw = trimmed.lowercased()

        return try await dbQueue.read { db in
            try Book.fetchAll(db, sql: """
                SELECT DISTINCT b.* FROM books b
                LEFT JOIN search_index si ON b.id = si.book_id
                WHERE b.deleted_at IS NULL AND (
                    LOWER(b.title) LIKE ? OR LOWER(si.normalized_authors) LIKE ?
                    OR LOWER(b.publisher) LIKE ? OR si.pinyin_title_full LIKE ?
                    OR si.pinyin_title_initials LIKE ? OR si.pinyin_authors_full LIKE ?
                    OR si.pinyin_authors_initials LIKE ? OR LOWER(b.isbn10) LIKE ?
                    OR LOWER(b.isbn13) LIKE ?
                ) LIMIT ?
            """, arguments: ["%\(kw)%", "%\(kw)%", "%\(kw)%", "%\(pe.full)%", "%\(pe.initials)%", "%\(pe.full)%", "%\(pe.initials)%", "%\(kw)%", "%\(kw)%", limit])
        }
    }

    func updateIndex(for book: Book) async throws {
        let entry = SearchIndexEntry.from(
            title: book.title, authors: parseJSON(book.authorsJSON),
            translators: parseJSON(book.translatorsJSON), publisher: book.publisher,
            isbn: book.isbn13 ?? book.isbn10, tags: [], shelf: nil,
            location: book.locationDetail, purchaseChannel: nil, bookID: book.id)
        let a = indexArgs(entry, forUpdate: true)
        try await dbQueue.write { db in
            try db.execute(sql: """
                INSERT INTO search_index (book_id, normalized_title, normalized_authors, normalized_translators,
                    normalized_publisher, normalized_isbn, normalized_tags, normalized_shelf,
                    normalized_location, normalized_purchase_channel,
                    pinyin_title_full, pinyin_title_initials, pinyin_authors_full, pinyin_authors_initials,
                    combined_search_text, updated_at)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(book_id) DO UPDATE SET
                    normalized_title = ?, normalized_authors = ?, normalized_translators = ?,
                    normalized_publisher = ?, normalized_isbn = ?, normalized_tags = ?,
                    normalized_shelf = ?, normalized_location = ?, normalized_purchase_channel = ?,
                    pinyin_title_full = ?, pinyin_title_initials = ?, pinyin_authors_full = ?,
                    pinyin_authors_initials = ?, combined_search_text = ?, updated_at = ?
            """, arguments: a)
        }
    }

    func rebuildIndex() async throws {
        try await dbQueue.write { db in
            try db.execute(sql: "DELETE FROM search_index")
            try db.execute(sql: "DELETE FROM books_fts")
            let books = try Book.fetchAll(db)
            for book in books {
                let entry = SearchIndexEntry.from(title: book.title, authors: [], translators: [],
                    publisher: book.publisher, isbn: book.isbn13 ?? book.isbn10,
                    tags: [], shelf: nil, location: book.locationDetail, purchaseChannel: nil, bookID: book.id)
                try db.execute(sql: """INSERT INTO search_index (book_id, normalized_title, normalized_authors, normalized_translators, normalized_publisher, normalized_isbn, normalized_tags, normalized_shelf, normalized_location, normalized_purchase_channel, pinyin_title_full, pinyin_title_initials, pinyin_authors_full, pinyin_authors_initials, combined_search_text, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)""", arguments: indexArgs(entry))
            }
        }
    }

    func rebuildPinyinIndex() async throws {
        try await dbQueue.write { db in
            let books = try Book.fetchAll(db)
            for book in books {
                let tp = Pinyin.analyze(book.title)
                let ap = Pinyin.analyze(parseJSON(book.authorsJSON).joined(separator: " "))
                try db.execute(sql: """UPDATE search_index SET pinyin_title_full = ?, pinyin_title_initials = ?, pinyin_authors_full = ?, pinyin_authors_initials = ?, updated_at = ? WHERE book_id = ?""", arguments: [tp.full, tp.initials, ap.full, ap.initials, ISO8601(), book.id])
            }
        }
    }
}

private func parseJSON(_ json: String?) -> [String] {
    guard let json, let data = json.data(using: .utf8), let arr = try? JSONDecoder().decode([String].self, from: data) else { return [] }
    return arr
}

private func indexArgs(_ entry: SearchIndexEntry, forUpdate: Bool = false) -> [any DatabaseValueConvertible] {
    let now = ISO8601()
    let base: [any DatabaseValueConvertible] = [
        entry.bookID, entry.normalizedTitle, entry.normalizedAuthors, entry.normalizedTranslators,
        entry.normalizedPublisher, entry.normalizedISBN, entry.normalizedTags, entry.normalizedShelf,
        entry.normalizedLocation, entry.normalizedPurchaseChannel,
        entry.pinyinTitleFull, entry.pinyinTitleInitials, entry.pinyinAuthorsFull, entry.pinyinAuthorsInitials,
        entry.combinedSearchText, now
    ]
    if forUpdate { return base + base[1...] + [now] }
    return base
}

private func ISO8601() -> String { ISO8601DateFormatter().string(from: Date()) }
