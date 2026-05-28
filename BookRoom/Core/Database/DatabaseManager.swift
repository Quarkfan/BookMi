import Foundation
import GRDB

/// Database manager - initializes and provides database queue
final class DatabaseManager {
    static let shared = DatabaseManager()

    private(set) var dbQueue: DatabaseQueue!

    private init() {}

    func initialize() throws {
        let dbURL = AppPaths.databaseURL
        var config = Configuration()
        config.automaticMemoryManagement = true
        config.prepareDatabase { db in
            db.trace { print($0.expandedDescription) }
        }

        dbQueue = try DatabaseQueue(path: dbURL.path, configuration: config)

        try migrator.migrate(dbQueue)
    }

    private var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()
        #if DEBUG
        migrator.eraseDatabaseOnSchemaChange = true
        #endif

        migrator.registerMigration("v1_initial_schema") { db in
            try createBooksTable(db)
            try createShelvesTable(db)
            try createTagsTable(db)
            try createBookTagsTable(db)
            try createPurchaseChannelsTable(db)
            try createBorrowRecordsTable(db)
            try createSearchIndexTable(db)
            try createSettingsTable(db)
            try createSchemaInfoTable(db)
            try createAIOCRLogsTable(db)
            try createOperationLogsTable(db)
            try createFTS5Table(db)
            try createIndexes(db)
        }

        return migrator
    }

    // MARK: - Table Creation

    private func createBooksTable(_ db: Database) throws {
        try db.create(table: "books") { t in
            t.column("id", .text).primaryKey()
            t.column("legacy_id", .text)
            t.column("title", .text).notNull()
            t.column("subtitle", .text)
            t.column("original_title", .text)
            t.column("authors_json", .text)
            t.column("translators_json", .text)
            t.column("isbn10", .text)
            t.column("isbn13", .text)
            t.column("publisher", .text)
            t.column("published_date", .text)
            t.column("page_count", .integer)
            t.column("price", .text)
            t.column("edition", .text)
            t.column("printing", .text)
            t.column("series", .text)
            t.column("binding", .text)
            t.column("language", .text)
            t.column("category", .text)
            t.column("summary", .text)
            t.column("cover_file_name", .text)
            t.column("cover_url", .text)
            t.column("cover_hash", .text)
            t.column("shelf_id", .text)
            t.column("location_detail", .text)
            t.column("purchase_channel_id", .text)
            t.column("purchase_date", .text)
            t.column("purchase_price", .text)
            t.column("reading_status", .text).notNull().defaults(to: "unread")
            t.column("reading_progress_type", .text)
            t.column("current_page", .integer)
            t.column("progress_percent", .double)
            t.column("started_at", .text)
            t.column("finished_at", .text)
            t.column("borrow_status", .text).notNull().defaults(to: "available")
            t.column("note", .text)
            t.column("data_source", .text)
            t.column("source_raw_data", .text)
            t.column("duplicate_group_id", .text)
            t.column("copy_index", .integer).notNull().defaults(to: 1)
            t.column("is_favorite", .boolean).notNull().defaults(to: false)
            t.column("custom_sort_key", .text)
            t.column("created_at", .text).notNull()
            t.column("updated_at", .text).notNull()
            t.column("deleted_at", .text)
        }
    }

    private func createShelvesTable(_ db: Database) throws {
        try db.create(table: "shelves") { t in
            t.column("id", .text).primaryKey()
            t.column("name", .text).notNull()
            t.column("location_note", .text)
            t.column("sort_order", .integer).notNull().defaults(to: 0)
            t.column("note", .text)
            t.column("created_at", .text).notNull()
            t.column("updated_at", .text).notNull()
            t.column("deleted_at", .text)
        }
    }

    private func createTagsTable(_ db: Database) throws {
        try db.create(table: "tags") { t in
            t.column("id", .text).primaryKey()
            t.column("name", .text).notNull().unique()
            t.column("color", .text)
            t.column("sort_order", .integer).notNull().defaults(to: 0)
            t.column("created_at", .text).notNull()
            t.column("updated_at", .text).notNull()
            t.column("deleted_at", .text)
        }
    }

    private func createBookTagsTable(_ db: Database) throws {
        try db.create(table: "book_tags") { t in
            t.column("book_id", .text).notNull()
            t.column("tag_id", .text).notNull()
            t.column("created_at", .text).notNull()
            t.primaryKey(["book_id", "tag_id"])
        }
    }

    private func createPurchaseChannelsTable(_ db: Database) throws {
        try db.create(table: "purchase_channels") { t in
            t.column("id", .text).primaryKey()
            t.column("name", .text).notNull().unique()
            t.column("sort_order", .integer).notNull().defaults(to: 0)
            t.column("created_at", .text).notNull()
            t.column("updated_at", .text).notNull()
            t.column("deleted_at", .text)
        }
    }

    private func createBorrowRecordsTable(_ db: Database) throws {
        try db.create(table: "borrow_records") { t in
            t.column("id", .text).primaryKey()
            t.column("book_id", .text).notNull()
            t.column("borrower_name", .text).notNull()
            t.column("contact", .text)
            t.column("borrowed_at", .text).notNull()
            t.column("expected_return_at", .text)
            t.column("returned_at", .text)
            t.column("status", .text).notNull()
            t.column("note", .text)
            t.column("created_at", .text).notNull()
            t.column("updated_at", .text).notNull()
        }
    }

    private func createSearchIndexTable(_ db: Database) throws {
        try db.create(table: "search_index") { t in
            t.column("book_id", .text).primaryKey()
            t.column("normalized_title", .text)
            t.column("normalized_authors", .text)
            t.column("normalized_translators", .text)
            t.column("normalized_publisher", .text)
            t.column("normalized_isbn", .text)
            t.column("normalized_tags", .text)
            t.column("normalized_shelf", .text)
            t.column("normalized_location", .text)
            t.column("normalized_purchase_channel", .text)
            t.column("pinyin_title_full", .text)
            t.column("pinyin_title_initials", .text)
            t.column("pinyin_authors_full", .text)
            t.column("pinyin_authors_initials", .text)
            t.column("combined_search_text", .text)
            t.column("updated_at", .text).notNull()
        }
    }

    private func createSettingsTable(_ db: Database) throws {
        try db.create(table: "settings") { t in
            t.column("key", .text).primaryKey()
            t.column("value", .text)
            t.column("updated_at", .text).notNull()
        }
    }

    private func createSchemaInfoTable(_ db: Database) throws {
        try db.create(table: "schema_info") { t in
            t.column("key", .text).primaryKey()
            t.column("value", .text).notNull()
        }
        try db.execute(sql: "INSERT INTO schema_info (key, value) VALUES ('schema_version', '1')")
        try db.execute(sql: "INSERT INTO schema_info (key, value) VALUES ('app_version', '1.0.0')")
    }

    private func createAIOCRLogsTable(_ db: Database) throws {
        try db.create(table: "ai_ocr_logs") { t in
            t.column("id", .text).primaryKey()
            t.column("task_type", .text).notNull()
            t.column("related_book_id", .text)
            t.column("image_file_name", .text)
            t.column("request_summary", .text)
            t.column("response_json", .text)
            t.column("raw_response", .text)
            t.column("success", .boolean).notNull()
            t.column("error_message", .text)
            t.column("duration_ms", .integer)
            t.column("model_name", .text)
            t.column("created_at", .text).notNull()
        }
    }

    private func createOperationLogsTable(_ db: Database) throws {
        try db.create(table: "operation_logs") { t in
            t.column("id", .text).primaryKey()
            t.column("operation_type", .text).notNull()
            t.column("summary", .text)
            t.column("detail_json", .text)
            t.column("success", .boolean).notNull()
            t.column("error_message", .text)
            t.column("created_at", .text).notNull()
        }
    }

    private func createFTS5Table(_ db: Database) throws {
        try db.execute(sql: """
            CREATE VIRTUAL TABLE IF NOT EXISTS books_fts USING fts5(
                book_id UNINDEXED,
                title, authors, translators, publisher, isbn,
                tags, shelf, location, summary, note,
                pinyin_full, pinyin_initials, combined
            )
        """)
    }

    private func createIndexes(_ db: Database) throws {
        try db.execute(sql: "CREATE INDEX IF NOT EXISTS idx_books_title ON books(title)")
        try db.execute(sql: "CREATE INDEX IF NOT EXISTS idx_books_isbn10 ON books(isbn10)")
        try db.execute(sql: "CREATE INDEX IF NOT EXISTS idx_books_isbn13 ON books(isbn13)")
        try db.execute(sql: "CREATE INDEX IF NOT EXISTS idx_books_shelf_id ON books(shelf_id)")
        try db.execute(sql: "CREATE INDEX IF NOT EXISTS idx_books_purchase_channel_id ON books(purchase_channel_id)")
        try db.execute(sql: "CREATE INDEX IF NOT EXISTS idx_books_reading_status ON books(reading_status)")
        try db.execute(sql: "CREATE INDEX IF NOT EXISTS idx_books_borrow_status ON books(borrow_status)")
        try db.execute(sql: "CREATE INDEX IF NOT EXISTS idx_books_created_at ON books(created_at)")
        try db.execute(sql: "CREATE INDEX IF NOT EXISTS idx_books_updated_at ON books(updated_at)")
        try db.execute(sql: "CREATE INDEX IF NOT EXISTS idx_books_deleted_at ON books(deleted_at)")
        try db.execute(sql: "CREATE INDEX IF NOT EXISTS idx_book_tags_tag_id ON book_tags(tag_id)")
        try db.execute(sql: "CREATE INDEX IF NOT EXISTS idx_borrow_records_book_id ON borrow_records(book_id)")
        try db.execute(sql: "CREATE INDEX IF NOT EXISTS idx_borrow_records_status ON borrow_records(status)")
    }
}
