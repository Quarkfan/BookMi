import Foundation

/// App sandbox paths
enum AppPaths {
    static let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!

    static var libraryDataURL: URL {
        documents.appendingPathComponent("LibraryData")
    }

    static var databaseURL: URL {
        libraryDataURL.appendingPathComponent("database.sqlite")
    }

    static var coversURL: URL {
        libraryDataURL.appendingPathComponent("covers")
    }

    static var backupsURL: URL {
        documents.appendingPathComponent("Backups")
    }

    static var exportsURL: URL {
        documents.appendingPathComponent("Exports")
    }

    static var tempURL: URL {
        documents.appendingPathComponent("Temp")
    }

    static var tempImportURL: URL {
        tempURL.appendingPathComponent("import")
    }

    static var tempOCRURL: URL {
        tempURL.appendingPathComponent("ocr")
    }

    static var tempExportURL: URL {
        tempURL.appendingPathComponent("export")
    }

    /// Ensure all directories exist
    static func ensureDirectories() throws {
        let dirs = [libraryDataURL, coversURL, backupsURL, exportsURL, tempURL, tempImportURL, tempOCRURL, tempExportURL]
        for dir in dirs {
            if !FileManager.default.fileExists(atPath: dir.path) {
                try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            }
        }
    }
}
