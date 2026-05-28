import Foundation
import GRDB

/// Repository for search and index management
final class SearchRepository {
    private let dbQueue: DatabaseQueue

    init(dbQueue: DatabaseQueue) {
        self.dbQueue = dbQueue
    }

    // MARK: - Search

    /// Search books using FTS5 + pinyin index
    func search(keyword: String, limit: Int = 100) throws -> [Book] {
        let trimmed = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        let pinyinEntry = Pinyin.analyze(trimmed)

        return try dbQueue.read { db in
            // Search via FTS5
            let ftsResults = try Row.fetchAll(db, sql: """
                SELECT fts.book_id FROM books_fts fts
                WHERE books_fts MATCH ?
                LIMIT ?
            """, arguments: [ftsMatchTerm(for: trimmed), limit])

            let ftsBookIDs = Set(ftsResults.map { $0["book_id"] as String })

            // Search via pinyin index
            let pinyinResults = try Row.fetchAll(db, sql: """
                SELECT book_id FROM search_index
                WHERE pinyin_title_full LIKE ?
                   OR pinyin_title_initials LIKE ?
                   OR pinyin_authors_full LIKE ?
                   OR pinyin_authors_initials LIKE ?
                LIMIT ?
            """, arguments: ["%\(pinyinEntry.full)%", "%\(pinyinEntry.initials)%",
                            "%\(pinyinEntry.full)%", "%\(pinyinEntry.initials)%", limit])

            let pinyinBookIDs = Set(pinyinResults.map { $0["book_id"] as String })

            // Combine results
            let allBookIDs = Array(ftsBookIDs.union(pinyinBookIDs))
            guard !allBookIDs.isEmpty else { return [] }

            let placeholders = allBookIDs.map { _ in "?" }.joined(separator: ",")
            return try Book.fetchAll(db, sql: """
                SELECT * FROM books
                WHERE id IN (\(placeholders)) AND deleted_at IS NULL
            """, arguments: allBookIDs.map { .string($0) })
        }
    }

    /// Simple SQL LIKE search (fallback / broad search)
    func searchWithLike(keyword: String, limit: Int = 100) throws -> [Book] {
        let trimmed = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        let pinyinEntry = Pinyin.analyze(trimmed)

        return try dbQueue.read { db in
            try Book.fetchAll(db, sql: """
                SELECT DISTINCT b.* FROM books b
                LEFT JOIN search_index si ON b.id = si.book_id
                WHERE b.deleted_at IS NULL AND (
                    LOWER(b.title) LIKE ?
                    OR LOWER(si.normalized_authors) LIKE ?
                    OR LOWER(b.publisher) LIKE ?
                    OR si.pinyin_title_full LIKE ?
                    OR si.pinyin_title_initials LIKE ?
                    OR si.pinyin_authors_full LIKE ?
                    OR si.pinyin_authors_initials LIKE ?
                    OR LOWER(b.isbn10) LIKE ?
                    OR LOWER(b.isbn13) LIKE ?
                )
                LIMIT ?
            """, arguments: [
                "%\(trimmed.lowercased())%",
                "%\(trimmed.lowercased())%",
                "%\(trimmed.lowercased())%",
                "%\(pinyinEntry.full)%",
                "%\(pinyinEntry.initials)%",
                "%\(pinyinEntry.full)%",
                "%\(pinyinEntry.initials)%",
                "%\(trimmed.lowercased())%",
                "%\(trimmed.lowercased())%",
                limit
            ])
        }
    }

    // MARK: - Index Management

    /// Update search index for a single book
    func updateIndex(for book: Book) throws {
        let entry = SearchIndexEntry.from(
            title: book.title,
            authors: parseAuthors(book.authorsJSON),
            translators: parseArray(book.translatorsJSON),
            publisher: book.publisher,
            isbn: book.isbn13 ?? book.isbn10,
            tags: fetchTagNames(forBookID: book.id),
            shelf: fetchShelfName(forShelfID: book.shelfID),
            location: book.locationDetail,
            purchaseChannel: nil, // TODO: join with purchase_channels
            bookID: book.id)

        try dbQueue.write { db in
            try db.execute(sql: """
                INSERT INTO search_index (
                    book_id, normalized_title, normalized_authors, normalized_translators,
                    normalized_publisher, normalized_isbn, normalized_tags, normalized_shelf,
                    normalized_location, normalized_purchase_channel,
                    pinyin_title_full, pinyin_title_initials,
                    pinyin_authors_full, pinyin_authors_initials,
                    combined_search_text, updated_at
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(book_id) DO UPDATE SET
                    normalized_title = ?, normalized_authors = ?, normalized_translators = ?,
                    normalized_publisher = ?, normalized_isbn = ?, normalized_tags = ?,
                    normalized_shelf = ?, normalized_location = ?,
                    normalized_purchase_channel = ?,
                    pinyin_title_full = ?, pinyin_title_initials = ?,
                    pinyin_authors_full = ?, pinyin_authors_initials = ?,
                    combined_search_text = ?, updated_at = ?
            """, arguments: indexArgs(entry, forUpdate: true))
        }
    }

    /// Rebuild search index for all books
    func rebuildIndex() throws {
        try dbQueue.write { db in
            try db.execute(sql: "DELETE FROM search_index")
            try db.execute(sql: "DELETE FROM books_fts")

            let books = try Book.fetchAll(db)
            for book in books {
                let entry = SearchIndexEntry.from(
                    title: book.title,
                    authors: parseAuthors(book.authorsJSON),
                    translators: parseArray(book.translatorsJSON),
                    publisher: book.publisher,
                    isbn: book.isbn13 ?? book.isbn10,
                    tags: [], // Simplified for batch rebuild
                    shelf: nil,
                    location: book.locationDetail,
                    purchaseChannel: nil,
                    bookID: book.id)

                let args = indexArgs(entry)
                try db.execute(sql: """
                    INSERT INTO search_index (
                        book_id, normalized_title, normalized_authors, normalized_translators,
                        normalized_publisher, normalized_isbn, normalized_tags, normalized_shelf,
                        normalized_location, normalized_purchase_channel,
                        pinyin_title_full, pinyin_title_initials,
                        pinyin_authors_full, pinyin_authors_initials,
                        combined_search_text, updated_at
                    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """, arguments: args)
            }
        }
    }

    /// Rebuild only pinyin index
    func rebuildPinyinIndex() throws {
        try dbQueue.write { db in
            let books = try Book.fetchAll(db)
            for book in books {
                let titlePinyin = Pinyin.analyze(book.title)
                let authorPinyin = Pinyin.analyze(parseAuthors(book.authorsJSON).joined(separator: " "))

                try db.execute(sql: """
                    UPDATE search_index SET
                        pinyin_title_full = ?,
                        pinyin_title_initials = ?,
                        pinyin_authors_full = ?,
                        pinyin_authors_initials = ?,
                        updated_at = ?
                    WHERE book_id = ?
                """, arguments: [titlePinyin.full, titlePinyin.initials,
                                authorPinyin.full, authorPinyin.initials,
                                ISO8601(), book.id])
            }
        }
    }
}

// MARK: - Helpers

extension SearchRepository {
    private func ftsMatchTerm(for keyword: String) -> String {
        // Escape FTS5 special characters and create match term
        keyword
            .replacingOccurrences(of: "\"", with: "\"\"")
    }

    private func parseAuthors(_ json: String?) -> [String] {
        parseArray(json)
    }

    private func parseArray(_ json: String?) -> [String] {
        guard let json, let data = json.data(using: .utf8),
              let arr = try? JSONDecoder().decode([String].self, from: data) else {
            return []
        }
        return arr
    }

    private func fetchTagNames(forBookID bookID: String) -> [String] {
        // Simplified - would need to join with tags table
        return []
    }

    private func fetchShelfName(forShelfID shelfID: String?) -> String? {
        // Simplified - would need to join with shelves table
        return nil
    }

    private func indexArgs(_ entry: SearchIndexEntry, forUpdate: Bool = false) -> [any DatabaseValueConvertible] {
        let now = ISO8601()
        let base: [any DatabaseValueConvertible] = [
            entry.bookID, entry.normalizedTitle, entry.normalizedAuthors,
            entry.normalizedTranslators, entry.normalizedPublisher,
            entry.normalizedISBN, entry.normalizedTags, entry.normalizedShelf,
            entry.normalizedLocation, entry.normalizedPurchaseChannel,
            entry.pinyinTitleFull, entry.pinyinTitleInitials,
            entry.pinyinAuthorsFull, entry.pinyinAuthorsInitials,
            entry.combinedSearchText, now
        ]
        if forUpdate {
            return base + [
                entry.normalizedTitle, entry.normalizedAuthors, entry.normalizedTranslators,
                entry.normalizedPublisher, entry.normalizedISBN, entry.normalizedTags,
                entry.normalizedShelf, entry.normalizedLocation,
                entry.normalizedPurchaseChannel,
                entry.pinyinTitleFull, entry.pinyinTitleInitials,
                entry.pinyinAuthorsFull, entry.pinyinAuthorsInitials,
                entry.combinedSearchText, now
            ]
        }
        return base
    }
}

private func ISO8601() -> String {
    ISO8601DateFormatter().string(from: Date())
}
