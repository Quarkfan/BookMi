import Foundation
import GRDB

/// Settings keys
enum SettingsKey: String {
    case aiEnabled = "ai.enabled"
    case aiBaseURL = "ai.base_url"
    case aiModelName = "ai.model_name"
    case aiRequestFormat = "ai.request_format"
    case aiTimeout = "ai.timeout_seconds"
    case aiTemperature = "ai.temperature"
    case aiMaxTokens = "ai.max_tokens"
    case aiLanguagePreference = "ai.language_preference"
    case aiSaveRawResponse = "ai.save_raw_response"

    case uiDisplayMode = "ui.display_mode"
    case uiListVisibleFields = "ui.list_visible_fields"
    case uiSortField = "ui.sort_field"
    case uiSortOrder = "ui.sort_order"

    case scanDefaultShelfID = "scan.default_shelf_id"
    case scanDefaultTagIDs = "scan.default_tag_ids"
    case scanDefaultPurchaseChannelID = "scan.default_purchase_channel_id"

    case backupAutoEnabled = "backup.auto_enabled"
    case backupAutoFrequency = "backup.auto_frequency"
    case backupLastBackupAt = "backup.last_backup_at"

    case securityPasscodeEnabled = "security.passcode_enabled"
    case securityBiometricEnabled = "security.biometric_enabled"

    case searchIndexVersion = "search.index_version"

    // Legacy keys for backward compatibility
    case defaultShelfID = "default_shelf_id"
    case defaultTagIDs = "default_tag_ids"
    case defaultPurchaseChannel = "default_purchase_channel"
    case displayMode = "display_mode"
    case sortField = "sort_field"
    case sortOrder = "sort_order"
    case passcodeEnabled = "passcode_enabled"
    case passwordHash = "password_hash"
    case icloudSyncEnabled = "icloud_sync_enabled"
    case pinyinIndexVersion = "pinyin_index_version"
}

/// Settings manager backed by SQLite settings table
final class SettingsManager {
    static let shared = SettingsManager()

    private(set) var dbQueue: DatabaseQueue!

    func configure(with dbQueue: DatabaseQueue) {
        self.dbQueue = dbQueue
    }

    // MARK: - Get/Set

    func string(forKey key: SettingsKey) -> String? {
        try? dbQueue.read { db in
            try String.fetchOne(db,
                sql: "SELECT value FROM settings WHERE key = ?",
                arguments: [key.rawValue])
        }
    }

    func set(_ value: String?, forKey key: SettingsKey) {
        _ = try? dbQueue.write { db in
            if value != nil {
                try db.execute(
                    sql: """
                    INSERT INTO settings (key, value, updated_at)
                    VALUES (?, ?, ?)
                    ON CONFLICT(key) DO UPDATE SET value = ?, updated_at = ?
                    """,
                    arguments: [key.rawValue, value, ISO8601(), value, ISO8601()])
            } else {
                try db.execute(
                    sql: "DELETE FROM settings WHERE key = ?",
                    arguments: [key.rawValue])
            }
            return true
        }
    }

    func bool(forKey key: SettingsKey) -> Bool {
        string(forKey: key).map { Bool($0) ?? false } ?? false
    }

    func set(_ value: Bool, forKey key: SettingsKey) {
        set(value ? "true" : "false", forKey: key)
    }

    func int(forKey key: SettingsKey) -> Int? {
        string(forKey: key).flatMap { Int($0) }
    }

    func set(_ value: Int?, forKey key: SettingsKey) {
        set(value.map { String($0) }, forKey: key)
    }

    func double(forKey key: SettingsKey) -> Double? {
        string(forKey: key).flatMap { Double($0) }
    }

    func set(_ value: Double?, forKey key: SettingsKey) {
        set(value.map { String($0) }, forKey: key)
    }

    func array(forKey key: SettingsKey) -> [String] {
        guard let json = string(forKey: key),
              let data = json.data(using: .utf8),
              let arr = try? JSONDecoder().decode([String].self, from: data) else {
            return []
        }
        return arr
    }

    func set(_ value: [String], forKey key: SettingsKey) {
        guard let data = try? JSONEncoder().encode(value),
              let json = String(data: data, encoding: .utf8) else { return }
        set(json, forKey: key)
    }

    // MARK: - Convenience Accessors

    var displayMode: DisplayMode {
        get {
            string(forKey: .uiDisplayMode).flatMap { DisplayMode(rawValue: $0) } ?? .list
        }
        set { set(newValue.rawValue, forKey: .uiDisplayMode) }
    }

    var sortField: SortField {
        get {
            string(forKey: .uiSortField).flatMap { SortField(rawValue: $0) } ?? .pinyin
        }
        set { set(newValue.rawValue, forKey: .uiSortField) }
    }

    var sortOrder: SortOrder {
        get {
            string(forKey: .uiSortOrder).flatMap { SortOrder(rawValue: $0) } ?? .ascending
        }
        set { set(newValue.rawValue, forKey: .uiSortOrder) }
    }

    var defaultShelfID: String? {
        get { string(forKey: .scanDefaultShelfID) }
        set { set(newValue, forKey: .scanDefaultShelfID) }
    }

    var defaultTagIDs: [String] {
        get { array(forKey: .scanDefaultTagIDs) }
        set { set(newValue, forKey: .scanDefaultTagIDs) }
    }

    var defaultPurchaseChannelID: String? {
        get { string(forKey: .scanDefaultPurchaseChannelID) }
        set { set(newValue, forKey: .scanDefaultPurchaseChannelID) }
    }

    var isPasscodeEnabled: Bool {
        get { bool(forKey: .securityPasscodeEnabled) }
        set { set(newValue, forKey: .securityPasscodeEnabled) }
    }

    var isBiometricEnabled: Bool {
        get { bool(forKey: .securityBiometricEnabled) }
        set { set(newValue, forKey: .securityBiometricEnabled) }
    }

    var isAICapabilityEnabled: Bool {
        get { bool(forKey: .aiEnabled) }
        set { set(newValue, forKey: .aiEnabled) }
    }

    var aiBaseURL: String? {
        get { string(forKey: .aiBaseURL) }
        set { set(newValue, forKey: .aiBaseURL) }
    }

    var aiModelName: String? {
        get { string(forKey: .aiModelName) }
        set { set(newValue, forKey: .aiModelName) }
    }

    var searchIndexVersion: Int? {
        get { int(forKey: .searchIndexVersion) }
        set { set(newValue, forKey: .searchIndexVersion) }
    }
}

// MARK: - Supporting Types

enum DisplayMode: String {
    case list
    case grid
}

enum SortField: String {
    case pinyin
    case firstLetter
    case createdAt
    case updatedAt
}

enum SortOrder: String {
    case ascending
    case descending
}

private func ISO8601() -> String {
    ISO8601DateFormatter().string(from: Date())
}
