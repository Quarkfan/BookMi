import Foundation

/// File storage manager for covers, backups, exports
final class FileStorageManager {
    static let shared = FileStorageManager()

    private init() {
        try? AppPaths.ensureDirectories()
    }

    // MARK: - Cover Images

    func coverURL(for bookID: String) -> URL {
        AppPaths.coversURL.appendingPathComponent("\(bookID).jpg")
    }

    func saveCover(_ data: Data, for bookID: String) throws {
        let url = coverURL(for: bookID)
        try data.write(to: url, options: .atomic)
    }

    func loadCover(for bookID: String) -> Data? {
        let url = coverURL(for: bookID)
        return try? Data(contentsOf: url)
    }

    func deleteCover(for bookID: String) {
        let url = coverURL(for: bookID)
        try? FileManager.default.removeItem(at: url)
    }

    func hasCover(for bookID: String) -> Bool {
        FileManager.default.fileExists(atPath: coverURL(for: bookID).path)
    }

    // MARK: - File Management

    func fileExists(at url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path)
    }

    func deleteFile(at url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    func listCovers() -> [String] {
        guard let files = try? FileManager.default.contentsOfDirectory(atPath: AppPaths.coversURL.path) else {
            return []
        }
        return files.filter { $0.hasSuffix(".jpg") }
    }
}
