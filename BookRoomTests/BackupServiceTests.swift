import XCTest
@testable import BookRoom

final class BackupServiceTests: DatabaseTestCase {

    func testCreateBackup() async throws {
        // Create some test data
        let shelf = Shelf(
            id: UUID().uuidString,
            name: "测试柜",
            locationNote: nil,
            sortOrder: 0,
            note: nil,
            createdAt: ISO8601DateFormatter().string(from: Date()),
            updatedAt: ISO8601DateFormatter().string(from: Date()),
            deletedAt: nil
        )
        try shelfRepo.insert(shelf)

        let book = createBook(title: "备份测试书")
        try bookRepo.insert(book)

        // Create backup
        let zipURL = try await BackupService.createBackup()

        // Verify ZIP file exists
        XCTAssertTrue(FileManager.default.fileExists(atPath: zipURL.path))

        // Verify ZIP is not empty
        let attrs = try FileManager.default.attributesOfItem(atPath: zipURL.path)
        let size = attrs[.size] as? UInt64 ?? 0
        XCTAssertGreaterThan(size, 0)
    }

    func testListBackups() async throws {
        // Create at least one backup
        _ = try await BackupService.createBackup()

        let backups = try BackupService.listLocalBackups()
        XCTAssertFalse(backups.isEmpty)
    }

    func testDeleteBackup() async throws {
        let zipURL = try await BackupService.createBackup()
        let backups = try BackupService.listLocalBackups()

        guard let backup = backups.first else {
            XCTFail("No backups found")
            return
        }

        try BackupService.deleteBackup(backup)
        XCTAssertFalse(FileManager.default.fileExists(atPath: zipURL.path))
    }

    func testBackupManifest() async throws {
        // Create data
        let shelf = Shelf(
            id: UUID().uuidString,
            name: "ManifestTest",
            locationNote: nil,
            sortOrder: 0,
            note: nil,
            createdAt: ISO8601DateFormatter().string(from: Date()),
            updatedAt: ISO8601DateFormatter().string(from: Date()),
            deletedAt: nil
        )
        try shelfRepo.insert(shelf)

        for i in 0..<5 {
            try bookRepo.insert(createBook(title: "Book \(i)"))
        }

        let tag = Tag(
            id: UUID().uuidString,
            name: "Tag",
            color: nil,
            sortOrder: 0,
            createdAt: ISO8601DateFormatter().string(from: Date()),
            updatedAt: ISO8601DateFormatter().string(from: Date()),
            deletedAt: nil
        )
        try tagRepo.insert(tag)

        let zipURL = try await BackupService.createBackup()

        // Extract and verify manifest
        let tempDir = AppPaths.tempURL.appendingPathComponent("manifest_test_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        try FileManager.default.unzipItem(at: zipURL, to: tempDir)

        let manifestURL = tempDir.appendingPathComponent("manifest.json")
        XCTAssertTrue(FileManager.default.fileExists(atPath: manifestURL.path))

        let data = try Data(contentsOf: manifestURL)
        let manifest = try JSONDecoder().decode(BackupManifest.self, from: data)

        XCTAssertEqual(manifest.appName, "BookRoom")
        XCTAssertEqual(manifest.backupVersion, 1)
        XCTAssertEqual(manifest.bookCount, 5)
        XCTAssertEqual(manifest.shelfCount, 1)
        XCTAssertEqual(manifest.tagCount, 1)
        XCTAssertFalse(manifest.containsAPIKey)

        // Cleanup
        try FileManager.default.removeItem(at: tempDir)
    }
}
