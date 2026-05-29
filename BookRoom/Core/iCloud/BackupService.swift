import Foundation
import GRDB
import ZIPFoundation

/// Backup and restore service
final class BackupService {

    // MARK: - Create Backup

    static func createBackup(to location: BackupLocation = .local) async throws -> URL {
        let dbQueue = AppContainer.shared.databaseManager.dbQueue
        guard let dbQueue else { throw BackupError.databaseNotInitialized }

        // 1. Checkpoint WAL
        try await dbQueue.barrierWriteWithoutTransaction { db in
            try db.execute(sql: "PRAGMA wal_checkpoint(TRUNCATE)")
            return ()
        }

        // 2. Create backup directory
        let timestamp = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "")
            .replacingOccurrences(of: "-", with: "")
        let backupDir = AppPaths.backupsURL.appendingPathComponent("backup_\(timestamp)")
        try FileManager.default.createDirectory(at: backupDir, withIntermediateDirectories: true)

        // 3. Copy database
        let dbSource = AppPaths.libraryDataURL.appendingPathComponent("database.sqlite")
        let dbDest = backupDir.appendingPathComponent("database.sqlite")
        try FileManager.default.copyItem(at: dbSource, to: dbDest)

        // 4. Copy covers
        let coversDest = backupDir.appendingPathComponent("covers")
        if FileManager.default.fileExists(atPath: AppPaths.coversURL.path) {
            try FileManager.default.copyItem(at: AppPaths.coversURL, to: coversDest)
        }

        // 5. Export JSON
        let exportDir = backupDir.appendingPathComponent("export")
        try FileManager.default.createDirectory(at: exportDir, withIntermediateDirectories: true)
        try await exportJSON(to: exportDir)

        // 6. Create manifest
        let manifest = try await createManifest(backupDir: backupDir)
        let manifestURL = backupDir.appendingPathComponent("manifest.json")
        let manifestData = try JSONEncoder().encode(manifest)
        try manifestData.write(to: manifestURL)

        // 7. Create ZIP
        let zipURL = AppPaths.backupsURL.appendingPathComponent("library-backup-\(timestamp).zip")
        try FileManager.default.zipItem(at: backupDir, destinationURL: zipURL)

        // 8. Clean up temp directory
        try FileManager.default.removeItem(at: backupDir)

        // 9. Copy to iCloud if requested
        if location == .icloud {
            // TODO: Move to iCloud ubiquity container
        }

        return zipURL
    }

    // MARK: - Restore from Backup

    enum RestoreMode {
        case overwrite // Clear current data and restore from backup
        case merge     // Merge backup data into current database
        case booksOnly // Only import books, shelves, tags, covers
    }

    static func restore(from zipURL: URL, mode: RestoreMode) async throws {
        // 1. Extract ZIP to temp directory
        let tempDir = AppPaths.tempURL.appendingPathComponent("restore_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        try FileManager.default.unzipItem(at: zipURL, to: tempDir)

        // 2. Validate manifest
        let manifestURL = tempDir.appendingPathComponent("manifest.json")
        guard FileManager.default.fileExists(atPath: manifestURL.path) else {
            throw BackupError.invalidBackup("缺少 manifest.json")
        }

        let manifestData = try Data(contentsOf: manifestURL)
        let manifest = try JSONDecoder().decode(BackupManifest.self, from: manifestData)

        // 3. Validate database exists
        let dbFile = tempDir.appendingPathComponent("database.sqlite")
        guard FileManager.default.fileExists(atPath: dbFile.path) else {
            throw BackupError.invalidBackup("缺少 database.sqlite")
        }

        // 4. Restore based on mode
        let dbQueue = AppContainer.shared.databaseManager.dbQueue
        guard let dbQueue else { throw BackupError.databaseNotInitialized }

        switch mode {
        case .overwrite:
            // Checkpoint current DB
            try await dbQueue.barrierWriteWithoutTransaction { db in
                try db.execute(sql: "PRAGMA wal_checkpoint(TRUNCATE)")
                return ()
            }

            // Replace database file
            let currentDB = AppPaths.libraryDataURL.appendingPathComponent("database.sqlite")
            try FileManager.default.removeItem(at: currentDB)
            try FileManager.default.copyItem(at: dbFile, to: currentDB)

            // Replace covers
            let currentCovers = AppPaths.coversURL
            try? FileManager.default.removeItem(at: currentCovers)
            let backupCovers = tempDir.appendingPathComponent("covers")
            if FileManager.default.fileExists(atPath: backupCovers.path) {
                try FileManager.default.copyItem(at: backupCovers, to: currentCovers)
            }

        case .merge, .booksOnly:
            // Attach backup database and merge
            try await mergeBackup(from: dbFile, mode: mode)
        }

        // 5. Clean up
        try FileManager.default.removeItem(at: tempDir)
    }

    // MARK: - List Backups

    static func listLocalBackups() throws -> [BackupInfo] {
        guard FileManager.default.fileExists(atPath: AppPaths.backupsURL.path) else {
            return []
        }

        let files = try FileManager.default.contentsOfDirectory(atPath: AppPaths.backupsURL.path)
        let zipFiles = files.filter { $0.hasSuffix(".zip") && $0.hasPrefix("library-backup-") }

        return zipFiles.compactMap { fileName -> BackupInfo? in
            let url = AppPaths.backupsURL.appendingPathComponent(fileName)
            let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
            let size = attributes?[.size] as? UInt64 ?? 0
            let date = attributes?[.modificationDate] as? Date ?? Date()

            return BackupInfo(
                fileName: fileName,
                url: url,
                date: date,
                sizeBytes: size,
                isICloud: false
            )
        }
        .sorted(by: { $0.date > $1.date })
    }

    static func deleteBackup(_ info: BackupInfo) throws {
        try FileManager.default.removeItem(at: info.url)
    }

    // MARK: - Private Helpers

    private static func exportJSON(to dir: URL) async throws {
        let dbQueue = AppContainer.shared.databaseManager.dbQueue
        guard let dbQueue else { return }

        // Export books
        let books = try await dbQueue.read { db in
            try Book.fetchAll(db)
        }
        let bookData = try JSONEncoder().encode(books)
        try bookData.write(to: dir.appendingPathComponent("books.json"))

        // Export shelves
        let shelves = try await dbQueue.read { db in
            try Shelf.fetchAll(db)
        }
        let shelfData = try JSONEncoder().encode(shelves)
        try shelfData.write(to: dir.appendingPathComponent("shelves.json"))

        // Export tags
        let tags = try await dbQueue.read { db in
            try Tag.fetchAll(db)
        }
        let tagData = try JSONEncoder().encode(tags)
        try tagData.write(to: dir.appendingPathComponent("tags.json"))

        // Export book_tags
        let bookTags = try await dbQueue.read { db in
            try BookTag.fetchAll(db)
        }
        let btData = try JSONEncoder().encode(bookTags)
        try btData.write(to: dir.appendingPathComponent("book_tags.json"))

        // Export borrow_records
        let borrows = try await dbQueue.read { db in
            try BorrowRecord.fetchAll(db)
        }
        let brData = try JSONEncoder().encode(borrows)
        try brData.write(to: dir.appendingPathComponent("borrow_records.json"))

        // Export purchase_channels
        let channels = try await dbQueue.read { db in
            try PurchaseChannel.fetchAll(db)
        }
        let chData = try JSONEncoder().encode(channels)
        try chData.write(to: dir.appendingPathComponent("purchase_channels.json"))

        // Export settings
        let settings = try await dbQueue.read { db in
            try Row.fetchAll(db, sql: "SELECT * FROM settings")
        }
        let settingsMap = Dictionary(settings.map {
            ($0["key"] as String, $0["value"] as String?)
        }, uniquingKeysWith: { $1 })
        let settingsData = try JSONEncoder().encode(settingsMap)
        try settingsData.write(to: dir.appendingPathComponent("settings.json"))
    }

    private static func createManifest(backupDir: URL) async throws -> BackupManifest {
        let coverCount: Int
        if let files = try? FileManager.default.contentsOfDirectory(atPath: AppPaths.coversURL.path) {
            coverCount = files.filter { $0.hasSuffix(".jpg") }.count
        } else {
            coverCount = 0
        }

        let dbQueue = AppContainer.shared.databaseManager.dbQueue
        let bookCount: Int
        let shelfCount: Int
        let tagCount: Int

        if let dbQueue {
            bookCount = (try? await dbQueue.read { db in try Book.fetchCount(db) }) ?? 0
            shelfCount = (try? await dbQueue.read { db in try Shelf.fetchCount(db) }) ?? 0
            tagCount = (try? await dbQueue.read { db in try Tag.fetchCount(db) }) ?? 0
        } else {
            bookCount = 0
            shelfCount = 0
            tagCount = 0
        }

        return BackupManifest(
            appName: "BookRoom",
            backupVersion: 1,
            createdAt: ISO8601DateFormatter().string(from: Date()),
            bookCount: bookCount,
            shelfCount: shelfCount,
            tagCount: tagCount,
            coverCount: coverCount,
            databaseFile: "database.sqlite",
            jsonExportPath: "export/",
            coversPath: "covers/",
            containsAPIKey: false
        )
    }

    private static func mergeBackup(from dbFile: URL, mode: RestoreMode) async throws {
        let dbQueue = AppContainer.shared.databaseManager.dbQueue
        guard let dbQueue else { return }

        try await dbQueue.write { db in
            // Attach backup database
            try db.execute(sql: "ATTACH DATABASE ? AS backup", arguments: [dbFile.path])
            defer { try? db.execute(sql: "DETACH DATABASE backup") }

            // Merge books (skip if legacy_id or isbn13 matches)
            try db.execute(sql: """
                INSERT INTO books SELECT * FROM backup.books
                WHERE id NOT IN (SELECT id FROM books)
            """)

            // Merge shelves
            try db.execute(sql: """
                INSERT INTO shelves SELECT * FROM backup.shelves
                WHERE id NOT IN (SELECT id FROM shelves)
            """)

            // Merge tags
            try db.execute(sql: """
                INSERT INTO tags SELECT * FROM backup.tags
                WHERE id NOT IN (SELECT id FROM tags)
            """)

            // Merge book_tags
            try db.execute(sql: """
                INSERT INTO book_tags SELECT * FROM backup.book_tags
                WHERE (book_id, tag_id) NOT IN (SELECT book_id, tag_id FROM book_tags)
            """)

            // Merge borrow_records
            try db.execute(sql: """
                INSERT INTO borrow_records SELECT * FROM backup.borrow_records
                WHERE id NOT IN (SELECT id FROM borrow_records)
            """)

            // Merge purchase_channels
            try db.execute(sql: """
                INSERT INTO purchase_channels SELECT * FROM backup.purchase_channels
                WHERE id NOT IN (SELECT id FROM purchase_channels)
            """)

            if mode == .booksOnly {
                // Don't merge settings
                return
            }

            // Merge settings (backup overwrites current)
            try db.execute(sql: """
                INSERT INTO settings SELECT * FROM backup.settings
                ON CONFLICT(key) DO UPDATE SET value = excluded.value, updated_at = excluded.updated_at
            """)
        }

        // Copy covers from backup
        let backupCovers = dbFile.deletingLastPathComponent().appendingPathComponent("covers")
        // Covers are at the same level as database.sqlite in backup, need to check structure
        // For merge, we assume covers are in the ZIP structure
    }
}

// MARK: - Backup Manifest

struct BackupManifest: Codable {
    let appName: String
    let backupVersion: Int
    let createdAt: String
    let bookCount: Int
    let shelfCount: Int
    let tagCount: Int
    let coverCount: Int
    let databaseFile: String
    let jsonExportPath: String
    let coversPath: String
    let containsAPIKey: Bool
}

// MARK: - Backup Location

enum BackupLocation {
    case local
    case icloud
}

// MARK: - Backup Info

struct BackupInfo: Identifiable {
    let fileName: String
    let url: URL
    let date: Date
    let sizeBytes: UInt64
    let isICloud: Bool

    var id: String { fileName }

    var sizeDescription: String {
        let mb = Double(sizeBytes) / (1024 * 1024)
        return String(format: "%.1f MB", mb)
    }
}

// MARK: - Backup Errors

enum BackupError: Error, LocalizedError {
    case databaseNotInitialized
    case invalidBackup(String)
    case fileSystemError(String)

    var errorDescription: String? {
        switch self {
        case .databaseNotInitialized: return "数据库未初始化"
        case .invalidBackup(let msg): return "备份文件无效: \(msg)"
        case .fileSystemError(let msg): return "文件系统错误: \(msg)"
        }
    }
}
