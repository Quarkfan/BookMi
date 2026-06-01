import Foundation
import GRDB
import ZIPFoundation

enum BackupLocation {
    case local
    case icloud
}

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

enum RestoreMode {
    case overwrite
    case merge
    case booksOnly
}

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

final class BackupService {
    static func createBackup(to location: BackupLocation = .local) async throws -> URL {
        let dbQueue = AppContainer.shared.databaseManager.dbQueue
        guard let dbQueue else { throw BackupError.databaseNotInitialized }

        try await dbQueue.writeWithoutTransaction { (db: Database) in
            try db.execute(sql: "PRAGMA wal_checkpoint(TRUNCATE)")
        }

        let timestamp = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "")
            .replacingOccurrences(of: "-", with: "")
        let backupDir = AppPaths.backupsURL.appendingPathComponent("backup_\(timestamp)")
        try FileManager.default.createDirectory(at: backupDir, withIntermediateDirectories: true)

        let dbSource = AppPaths.libraryDataURL.appendingPathComponent("database.sqlite")
        let dbDest = backupDir.appendingPathComponent("database.sqlite")
        try FileManager.default.copyItem(at: dbSource, to: dbDest)

        let coversDest = backupDir.appendingPathComponent("covers")
        if FileManager.default.fileExists(atPath: AppPaths.coversURL.path) {
            try FileManager.default.copyItem(at: AppPaths.coversURL, to: coversDest)
        }

        let exportDir = backupDir.appendingPathComponent("export")
        try FileManager.default.createDirectory(at: exportDir, withIntermediateDirectories: true)
        try await exportJSON(to: exportDir)

        let manifest = try await createManifest(backupDir: backupDir)
        let manifestURL = backupDir.appendingPathComponent("manifest.json")
        try JSONEncoder().encode(manifest).write(to: manifestURL)

        let zipURL = AppPaths.backupsURL.appendingPathComponent("library-backup-\(timestamp).zip")
        try FileManager.default.zipItem(at: backupDir, to: zipURL)
        try FileManager.default.removeItem(at: backupDir)

        if location == .icloud {
            // TODO: Move to iCloud
        }

        return zipURL
    }

    static func restore(from zipURL: URL, mode: RestoreMode) async throws {
        let tempDir = AppPaths.tempURL.appendingPathComponent("restore_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        try FileManager.default.unzipItem(at: zipURL, to: tempDir)

        let manifestURL = tempDir.appendingPathComponent("manifest.json")
        guard FileManager.default.fileExists(atPath: manifestURL.path) else {
            throw BackupError.invalidBackup("Missing manifest.json")
        }
        let _ = try JSONDecoder().decode(BackupManifest.self, from: Data(contentsOf: manifestURL))

        let dbFile = tempDir.appendingPathComponent("database.sqlite")
        guard FileManager.default.fileExists(atPath: dbFile.path) else {
            throw BackupError.invalidBackup("Missing database.sqlite")
        }

        let dbQueue = AppContainer.shared.databaseManager.dbQueue
        guard let dbQueue else { throw BackupError.databaseNotInitialized }

        switch mode {
        case .overwrite:
            try await dbQueue.writeWithoutTransaction { (db: Database) in
                try db.execute(sql: "PRAGMA wal_checkpoint(TRUNCATE)")
            }
            let currentDB = AppPaths.libraryDataURL.appendingPathComponent("database.sqlite")
            try FileManager.default.removeItem(at: currentDB)
            try FileManager.default.copyItem(at: dbFile, to: currentDB)

            let currentCovers = AppPaths.coversURL
            try? FileManager.default.removeItem(at: currentCovers)
            let backupCovers = tempDir.appendingPathComponent("covers")
            if FileManager.default.fileExists(atPath: backupCovers.path) {
                try FileManager.default.copyItem(at: backupCovers, to: currentCovers)
            }

        case .merge, .booksOnly:
            try await mergeBackup(from: dbFile, mode: mode)
        }

        try FileManager.default.removeItem(at: tempDir)
    }

    static func listLocalBackups() throws -> [BackupInfo] {
        guard FileManager.default.fileExists(atPath: AppPaths.backupsURL.path) else { return [] }
        let files = try FileManager.default.contentsOfDirectory(atPath: AppPaths.backupsURL.path)
        let zipFiles = files.filter { $0.hasSuffix(".zip") && $0.hasPrefix("library-backup-") }

        return zipFiles.compactMap { fileName -> BackupInfo? in
            let url = AppPaths.backupsURL.appendingPathComponent(fileName)
            let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
            let size = attributes?[.size] as? UInt64 ?? 0
            let date = attributes?[.modificationDate] as? Date ?? Date()
            return BackupInfo(fileName: fileName, url: url, date: date, sizeBytes: size, isICloud: false)
        }
        .sorted(by: { $0.date > $1.date })
    }

    static func deleteBackup(_ info: BackupInfo) throws {
        try FileManager.default.removeItem(at: info.url)
    }

    private static func exportJSON(to dir: URL) async throws {
        let dbQueue = AppContainer.shared.databaseManager.dbQueue
        guard let dbQueue else { return }

        let books = try await dbQueue.read { (db: Database) in try Book.fetchAll(db) }
        try JSONEncoder().encode(books).write(to: dir.appendingPathComponent("books.json"))

        let shelves = try await dbQueue.read { (db: Database) in try Shelf.fetchAll(db) }
        try JSONEncoder().encode(shelves).write(to: dir.appendingPathComponent("shelves.json"))

        let tags = try await dbQueue.read { (db: Database) in try Tag.fetchAll(db) }
        try JSONEncoder().encode(tags).write(to: dir.appendingPathComponent("tags.json"))

        let bookTags = try await dbQueue.read { (db: Database) in try BookTag.fetchAll(db) }
        try JSONEncoder().encode(bookTags).write(to: dir.appendingPathComponent("book_tags.json"))

        let borrows = try await dbQueue.read { (db: Database) in try BorrowRecord.fetchAll(db) }
        try JSONEncoder().encode(borrows).write(to: dir.appendingPathComponent("borrow_records.json"))

        let channels = try await dbQueue.read { (db: Database) in try PurchaseChannel.fetchAll(db) }
        try JSONEncoder().encode(channels).write(to: dir.appendingPathComponent("purchase_channels.json"))

        let settings: [Row] = try await dbQueue.read { (db: Database) in
            try Row.fetchAll(db, sql: "SELECT * FROM settings")
        }
        let settingsMap = Dictionary<String, String?>(settings.map { ($0["key"] as String, $0["value"] as String?) }, uniquingKeysWith: { $1 })
        try JSONEncoder().encode(settingsMap).write(to: dir.appendingPathComponent("settings.json"))
    }

    private static func createManifest(backupDir: URL) async throws -> BackupManifest {
        let coverCount: Int
        if let files = try? FileManager.default.contentsOfDirectory(atPath: AppPaths.coversURL.path) {
            coverCount = files.filter { $0.hasSuffix(".jpg") }.count
        } else { coverCount = 0 }

        let dbQueue = AppContainer.shared.databaseManager.dbQueue
        let bookCount = try await (dbQueue?.read { (db: Database) in try Book.fetchCount(db) }) ?? 0
        let shelfCount = try await (dbQueue?.read { (db: Database) in try Shelf.fetchCount(db) }) ?? 0
        let tagCount = try await (dbQueue?.read { (db: Database) in try Tag.fetchCount(db) }) ?? 0

        return BackupManifest(
            appName: "BookRoom", backupVersion: 1, createdAt: ISO8601DateFormatter().string(from: Date()),
            bookCount: bookCount, shelfCount: shelfCount, tagCount: tagCount, coverCount: coverCount,
            databaseFile: "database.sqlite", jsonExportPath: "export/", coversPath: "covers/", containsAPIKey: false
        )
    }

    private static func mergeBackup(from dbFile: URL, mode: RestoreMode) async throws {
        let dbQueue = AppContainer.shared.databaseManager.dbQueue
        guard let dbQueue else { return }

        try await dbQueue.writeWithoutTransaction { (db: Database) in
            try db.execute(sql: "ATTACH DATABASE ? AS backup", arguments: [dbFile.path])
            defer { try? db.execute(sql: "DETACH DATABASE backup") }

            try db.execute(sql: "INSERT INTO books SELECT * FROM backup.books WHERE id NOT IN (SELECT id FROM books)")
            try db.execute(sql: "INSERT INTO shelves SELECT * FROM backup.shelves WHERE id NOT IN (SELECT id FROM shelves)")
            try db.execute(sql: "INSERT INTO tags SELECT * FROM backup.tags WHERE id NOT IN (SELECT id FROM tags)")
            try db.execute(sql: "INSERT INTO book_tags SELECT * FROM backup.book_tags WHERE (book_id, tag_id) NOT IN (SELECT book_id, tag_id FROM book_tags)")
            try db.execute(sql: "INSERT INTO borrow_records SELECT * FROM backup.borrow_records WHERE id NOT IN (SELECT id FROM borrow_records)")
            try db.execute(sql: "INSERT INTO purchase_channels SELECT * FROM backup.purchase_channels WHERE id NOT IN (SELECT id FROM purchase_channels)")

            if mode == .merge {
                try db.execute(sql: """
                    INSERT INTO settings SELECT * FROM backup.settings
                    ON CONFLICT(key) DO UPDATE SET value = excluded.value, updated_at = excluded.updated_at
                    """)
            }
        }
    }
}

private func ISO8601() -> String { ISO8601DateFormatter().string(from: Date()) }
