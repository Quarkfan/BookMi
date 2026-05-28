import Foundation
import GRDB

/// Main application container managing shared services
final class AppContainer: ObservableObject {
    static let shared = AppContainer()

    let databaseManager: DatabaseManager
    let fileStorage: FileStorageManager
    let keychain: KeychainManager

    private init() {
        self.databaseManager = DatabaseManager.shared
        self.fileStorage = FileStorageManager.shared
        self.keychain = KeychainManager.shared
    }
}
