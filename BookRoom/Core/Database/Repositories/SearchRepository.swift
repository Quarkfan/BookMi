import Foundation
import GRDB

final class SearchRepository {
    private let dbQueue: DatabaseQueue
    init(dbQueue: DatabaseQueue) { self.dbQueue = dbQueue }

    func search(keyword: String, limit: Int = 100) async throws -> [Book] {
        let trimmed = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        let pe = Pinyin.analyze(trimmed)
        let term = trimmed.replacingOccurrences(of: "\"", with: "\"\"")

        return try await dbQueue.read { (db: Database) in
            var ftsArgs = StatementArguments()
            ftsArgs.append(term)
            ftsArgs.append(limit)
            let ftsResults = try Row.fetchAll(db, sql: "SELECT fts.book_id FROM books_fts fts WHERE books_fts MATCH ? LIMIT ?", arguments: ftsArgs)
            let ftsIDs = Set(ftsResults.map { $0["book_id"] as String })

            let pinyinSQL = """
                SELECT book_id FROM search_index
                WHERE pinyin_title_full LIKE ? OR pinyin_title_initials LIKE ?
                OR pinyin_authors_full LIKE ? OR pinyin_authors_initials LIKE ?
                LIMIT ?
                """
            var pArgs = StatementArguments()
            pArgs.append("%\(pe.full)%")
            pArgs.append("%\(pe.initials)%")
            pArgs.append("%\(pe.full)%")
            pArgs.append("%\(pe.initials)%")
            pArgs.append(limit)
            let pinyinResults = try Row.fetchAll(db, sql: pinyinSQL, arguments: pArgs)
            let pinyinIDs = Set(pinyinResults.map { $0["book_id"] as String })

            let allIDs = Array(ftsIDs.union(pinyinIDs))
            guard !allIDs.isEmpty else { return [] }

            let ph = allIDs.map { "?" }.joined(separator: ",")
            let sql = "SELECT * FROM books WHERE id IN (\(ph)) AND deleted_at IS NULL"
            var bookArgs = StatementArguments()
            for id in allIDs { bookArgs.append(id) }
            return try Book.fetchAll(db, sql: sql, arguments: bookArgs)
        }
    }

    func searchWithLike(keyword: String, limit: Int = 100) async throws -> [Book] {
        let trimmed = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        let pe = Pinyin.analyze(trimmed)
        let kw = trimmed.lowercased()

        return try await dbQueue.read { (db: Database) in
            let sql = """
                SELECT DISTINCT b.* FROM books b
                LEFT JOIN search_index si ON b.id = si.book_id
                WHERE b.deleted_at IS NULL AND (
                    LOWER(b.title) LIKE ? OR LOWER(si.normalized_authors) LIKE ?
                    OR LOWER(b.publisher) LIKE ? OR si.pinyin_title_full LIKE ?
                    OR si.pinyin_title_initials LIKE ? OR si.pinyin_authors_full LIKE ?
                    OR si.pinyin_authors_initials LIKE ? OR LOWER(b.isbn10) LIKE ?
                    OR LOWER(b.isbn13) LIKE ?
                ) LIMIT ?
                """
            var args = StatementArguments()
            for _ in 0..<3 { args.append("%\(kw)%") }
            args.append("%\(pe.full)%")
            args.append("%\(pe.initials)%")
            args.append("%\(pe.full)%")
            args.append("%\(pe.initials)%")
            for _ in 0..<2 { args.append("%\(kw)%") }
            args.append(limit)
            return try Book.fetchAll(db, sql: sql, arguments: args)
        }
    }

    func updateIndex(for book: Book) async throws {
        let entry = SearchIndexEntry.from(
            title: book.title, authors: parseJSON(book.authorsJSON),
            translators: parseJSON(book.translatorsJSON), publisher: book.publisher,
            isbn: book.isbn13 ?? book.isbn10, tags: [], shelf: nil,
            location: book.locationDetail, purchaseChannel: nil, bookID: book.id)

        try await dbQueue.writeWithoutTransaction { (db: Database) in
            let sql = """
                INSERT INTO search_index (book_id, normalized_title, normalized_authors, normalized_translators,
                    normalized_publisher, normalized_isbn, normalized_tags, normalized_shelf,
                    normalized_location, normalized_purchase_channel,
                    pinyin_title_full, pinyin_title_initials, pinyin_authors_full, pinyin_authors_initials,
                    combined_search_text, updated_at)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(book_id) DO UPDATE SET
                    normalized_title = excluded.normalized_title,
                    normalized_authors = excluded.normalized_authors,
                    normalized_translators = excluded.normalized_translators,
                    normalized_publisher = excluded.normalized_publisher,
                    normalized_isbn = excluded.normalized_isbn,
                    normalized_tags = excluded.normalized_tags,
                    normalized_shelf = excluded.normalized_shelf,
                    normalized_location = excluded.normalized_location,
                    normalized_purchase_channel = excluded.normalized_purchase_channel,
                    pinyin_title_full = excluded.pinyin_title_full,
                    pinyin_title_initials = excluded.pinyin_title_initials,
                    pinyin_authors_full = excluded.pinyin_authors_full,
                    pinyin_authors_initials = excluded.pinyin_authors_initials,
                    combined_search_text = excluded.combined_search_text,
                    updated_at = excluded.updated_at
                """
            var args = StatementArguments()
            for v in indexArgs(entry) { args.append(v) }
            args.append(ISO8601())
            try db.execute(sql: sql, arguments: args)
        }
    }

    func rebuildIndex() async throws {
        try await dbQueue.writeWithoutTransaction { (db: Database) in
            try db.execute(sql: "DELETE FROM search_index")
            try db.execute(sql: "DELETE FROM books_fts")
            let books = try Book.fetchAll(db)
            for book in books {
                let entry = SearchIndexEntry.from(title: book.title, authors: [], translators: [],
                    publisher: book.publisher, isbn: book.isbn13 ?? book.isbn10,
                    tags: [], shelf: nil, location: book.locationDetail, purchaseChannel: nil, bookID: book.id)
                var args = StatementArguments()
                for v in indexArgs(entry) { args.append(v) }
                args.append(ISO8601())
                try db.execute(sql: """
                    INSERT INTO search_index (book_id, normalized_title, normalized_authors, normalized_translators,
                        normalized_publisher, normalized_isbn, normalized_tags, normalized_shelf,
                        normalized_location, normalized_purchase_channel,
                        pinyin_title_full, pinyin_title_initials, pinyin_authors_full, pinyin_authors_initials,
                        combined_search_text, updated_at)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """, arguments: args)
            }
        }
    }

    func rebuildPinyinIndex() async throws {
        try await dbQueue.writeWithoutTransaction { (db: Database) in
            let books = try Book.fetchAll(db)
            for book in books {
                let tp = Pinyin.analyze(book.title)
                let ap = Pinyin.analyze(parseJSON(book.authorsJSON).joined(separator: " "))
                var args = StatementArguments()
                args.append(tp.full)
                args.append(tp.initials)
                args.append(ap.full)
                args.append(ap.initials)
                args.append(ISO8601())
                args.append(book.id)
                try db.execute(sql: """
                    UPDATE search_index SET
                        pinyin_title_full = ?, pinyin_title_initials = ?,
                        pinyin_authors_full = ?, pinyin_authors_initials = ?,
                        updated_at = ?
                    WHERE book_id = ?
                    """, arguments: args)
            }
        }
    }
}

private func parseJSON(_ json: String?) -> [String] {
    guard let json, let data = json.data(using: .utf8), let arr = try? JSONDecoder().decode([String].self, from: data) else { return [] }
    return arr
}

private func indexArgs(_ entry: SearchIndexEntry) -> [String] {
    [
        entry.bookID, entry.normalizedTitle, entry.normalizedAuthors, entry.normalizedTranslators,
        entry.normalizedPublisher, entry.normalizedISBN, entry.normalizedTags, entry.normalizedShelf,
        entry.normalizedLocation, entry.normalizedPurchaseChannel,
        entry.pinyinTitleFull, entry.pinyinTitleInitials, entry.pinyinAuthorsFull, entry.pinyinAuthorsInitials,
        entry.combinedSearchText
    ]
}

private func ISO8601() -> String { ISO8601DateFormatter().string(from: Date()) }
