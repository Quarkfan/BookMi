import Foundation
import GRDB
import SwiftUI

final class AppContainer: ObservableObject {
    static let shared = AppContainer()

    let databaseManager = DatabaseManager.shared
    let fileStorage = FileStorageManager.shared
    let keychain = KeychainManager.shared
    let settings = SettingsManager.shared

    private(set) var bookRepo: BookRepository!
    private(set) var shelfRepo: ShelfRepository!
    private(set) var tagRepo: TagRepository!
    private(set) var searchRepo: SearchRepository!

    @Published var isAuthenticated = false
    @Published var isInitializing = true
    @Published var errorMessage: String?

    private init() {}

    func initialize() async {
        do {
            try databaseManager.initialize()
            settings.load()

            bookRepo = BookRepository(dbQueue: databaseManager.dbQueue)
            shelfRepo = ShelfRepository(dbQueue: databaseManager.dbQueue)
            tagRepo = TagRepository(dbQueue: databaseManager.dbQueue)
            searchRepo = SearchRepository(dbQueue: databaseManager.dbQueue)

            try await seedDefaultPurchaseChannels()
            await checkAuthentication()

            await MainActor.run { isInitializing = false }
        } catch {
            await MainActor.run {
                isInitializing = false
                errorMessage = "数据库初始化失败: \(error.localizedDescription)"
            }
        }
    }

    private func checkAuthentication() async {
        await MainActor.run { isAuthenticated = !settings.isPasscodeEnabled }
    }

    func authenticate() { isAuthenticated = true }

    private func seedDefaultPurchaseChannels() async throws {
        let count = try await databaseManager.dbQueue.read { (db: Database) in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM purchase_channels") ?? 0
        }
        guard count == 0 else { return }

        let defaults: [(String, Int)] = [
            ("京东", 1), ("当当", 2), ("淘宝", 3),
            ("线下书店", 4), ("二手书", 5), ("朋友赠送", 6), ("其他", 7)
        ]
        let now = ISO8601DateFormatter().string(from: Date())
        try await databaseManager.dbQueue.write { (db: Database) in
            for (name, order) in defaults {
                try db.execute(
                    sql: "INSERT INTO purchase_channels (id, name, sort_order, created_at, updated_at) VALUES (?, ?, ?, ?, ?)",
                    arguments: [UUID().uuidString, name, order, now, now])
            }
        }
    }
}
