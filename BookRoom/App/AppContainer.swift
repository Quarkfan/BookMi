import Foundation
import GRDB
import SwiftUI

/// Main application container managing shared services
final class AppContainer: ObservableObject {
    static let shared = AppContainer()

    // Core services
    let databaseManager = DatabaseManager.shared
    let fileStorage = FileStorageManager.shared
    let keychain = KeychainManager.shared
    let settings = SettingsManager.shared

    // Repositories (initialized after database)
    private(set) var bookRepo: BookRepository!
    private(set) var shelfRepo: ShelfRepository!
    private(set) var tagRepo: TagRepository!
    private(set) var searchRepo: SearchRepository!

    // UI state
    @Published var isAuthenticated = false
    @Published var isInitializing = true
    @Published var errorMessage: String?

    private init() {}

    /// Initialize all services. Call once at app launch.
    func initialize() async {
        do {
            // 1. Initialize database (creates tables if needed)
            try databaseManager.initialize()

            // 2. Configure settings manager with database
            settings.configure(with: databaseManager.dbQueue)

            // 3. Create repositories
            bookRepo = BookRepository(dbQueue: databaseManager.dbQueue)
            shelfRepo = ShelfRepository(dbQueue: databaseManager.dbQueue)
            tagRepo = TagRepository(dbQueue: databaseManager.dbQueue)
            searchRepo = SearchRepository(dbQueue: databaseManager.dbQueue)

            // 4. Seed default purchase channels if empty
            try seedDefaultPurchaseChannels()

            // 5. Check security settings
            await checkAuthentication()

            await MainActor.run {
                isInitializing = false
            }
        } catch {
            await MainActor.run {
                isInitializing = false
                errorMessage = "数据库初始化失败: \(error.localizedDescription)"
            }
        }
    }

    // MARK: - Authentication

    private func checkAuthentication() async {
        let passcodeEnabled = settings.isPasscodeEnabled
        if !passcodeEnabled {
            // No security, auto-authenticate
            await MainActor.run {
                isAuthenticated = true
            }
        } else {
            // TODO: Show passcode/FaceID authentication screen
            await MainActor.run {
                isAuthenticated = false
            }
        }
    }

    func authenticate() {
        isAuthenticated = true
    }

    // MARK: - Seeding

    private func seedDefaultPurchaseChannels() throws {
        let count = try databaseManager.dbQueue.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM purchase_channels") ?? 0
        }

        guard count == 0 else { return }

        let defaults: [(id: String, name: String, order: Int)] = [
            (UUID().uuidString, "京东", 1),
            (UUID().uuidString, "当当", 2),
            (UUID().uuidString, "淘宝", 3),
            (UUID().uuidString, "线下书店", 4),
            (UUID().uuidString, "二手书", 5),
            (UUID().uuidString, "朋友赠送", 6),
            (UUID().uuidString, "其他", 7)
        ]

        let now = ISO8601DateFormatter().string(from: Date())
        try databaseManager.dbQueue.write { db in
            for (id, name, order) in defaults {
                try db.execute(
                    sql: "INSERT INTO purchase_channels (id, name, sort_order, created_at, updated_at) VALUES (?, ?, ?, ?, ?)",
                    arguments: [id, name, order, now, now])
            }
        }
    }
}

private func ISO8601() -> String {
    ISO8601DateFormatter().string(from: Date())
}
