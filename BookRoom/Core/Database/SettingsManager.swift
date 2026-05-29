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
}

/// Settings manager backed by SQLite settings table
final class SettingsManager: ObservableObject {
    static let shared = SettingsManager()

    private(set) var dbQueue: DatabaseQueue!

    // MARK: - In-memory cache (backed by private vars, persisted on change)

    // (displayMode, sortField, etc. are computed properties below)

    func configure(with dbQueue: DatabaseQueue) {
        self.dbQueue = dbQueue
    }

    /// Load all settings from database into memory cache
    func load() async {
        _displayMode = (await string(forKey: .uiDisplayMode)).flatMap { DisplayMode(rawValue: $0) } ?? .list
        _sortField = (await string(forKey: .uiSortField)).flatMap { SortField(rawValue: $0) } ?? .pinyin
        _sortOrder = (await string(forKey: .uiSortOrder)).flatMap { SortOrder(rawValue: $0) } ?? .ascending
        _defaultShelfID = await string(forKey: .scanDefaultShelfID)
        _defaultTagIDs = await array(forKey: .scanDefaultTagIDs)
        _defaultPurchaseChannelID = await string(forKey: .scanDefaultPurchaseChannelID)
        _isPasscodeEnabled = await bool(forKey: .securityPasscodeEnabled)
        _isBiometricEnabled = await bool(forKey: .securityBiometricEnabled)
        _isAICapabilityEnabled = await bool(forKey: .aiEnabled)
        _aiBaseURL = await string(forKey: .aiBaseURL)
        _aiModelName = await string(forKey: .aiModelName)
    }

    // MARK: - Async DB Access

    func string(forKey key: SettingsKey) async -> String? {
        try? await dbQueue.read { db in
            try String.fetchOne(db,
                sql: "SELECT value FROM settings WHERE key = ?",
                arguments: [key.rawValue])
        }
    }

    func set(_ value: String?, forKey key: SettingsKey) {
        Task {
            _ = try? await dbQueue.write { db in
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
    }

    func bool(forKey key: SettingsKey) async -> Bool {
        (await string(forKey: key)).map { Bool($0) ?? false } ?? false
    }

    func set(_ value: Bool, forKey key: SettingsKey) {
        set(value ? "true" : "false", forKey: key)
    }

    func int(forKey key: SettingsKey) async -> Int? {
        await string(forKey: key).flatMap { Int($0) }
    }

    func set(_ value: Int?, forKey key: SettingsKey) {
        set(value.map { String($0) }, forKey: key)
    }

    func array(forKey key: SettingsKey) async -> [String] {
        guard let json = await string(forKey: key),
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

    // MARK: - Convenience Accessors (sync read, async persist)

    var displayMode: DisplayMode {
        get { _displayMode }
        set {
            _displayMode = newValue
            set(newValue.rawValue, forKey: .uiDisplayMode)
        }
    }
    @Published private var _displayMode: DisplayMode = .list

    var sortField: SortField {
        get { _sortField }
        set {
            _sortField = newValue
            set(newValue.rawValue, forKey: .uiSortField)
        }
    }
     @Published private var _sortField: SortField = .pinyin

    var sortOrder: SortOrder {
        get { _sortOrder }
        set {
            _sortOrder = newValue
            set(newValue.rawValue, forKey: .uiSortOrder)
        }
    }
     @Published private var _sortOrder: SortOrder = .ascending

    var defaultShelfID: String? {
        get { _defaultShelfID }
        set {
            _defaultShelfID = newValue
            set(newValue, forKey: .scanDefaultShelfID)
        }
    }
     @Published private var _defaultShelfID: String?

    var defaultTagIDs: [String] {
        get { _defaultTagIDs }
        set {
            _defaultTagIDs = newValue
            set(newValue, forKey: .scanDefaultTagIDs)
        }
    }
     @Published private var _defaultTagIDs: [String] = []

    var defaultPurchaseChannelID: String? {
        get { _defaultPurchaseChannelID }
        set {
            _defaultPurchaseChannelID = newValue
            set(newValue, forKey: .scanDefaultPurchaseChannelID)
        }
    }
     @Published private var _defaultPurchaseChannelID: String?

    var isPasscodeEnabled: Bool {
        get { _isPasscodeEnabled }
        set {
            _isPasscodeEnabled = newValue
            set(newValue, forKey: .securityPasscodeEnabled)
        }
    }
     @Published private var _isPasscodeEnabled: Bool = false

    var isBiometricEnabled: Bool {
        get { _isBiometricEnabled }
        set {
            _isBiometricEnabled = newValue
            set(newValue, forKey: .securityBiometricEnabled)
        }
    }
     @Published private var _isBiometricEnabled: Bool = false

    var isAICapabilityEnabled: Bool {
        get { _isAICapabilityEnabled }
        set {
            _isAICapabilityEnabled = newValue
            set(newValue, forKey: .aiEnabled)
        }
    }
     @Published private var _isAICapabilityEnabled: Bool = false

    var aiBaseURL: String? {
        get { _aiBaseURL }
        set {
            _aiBaseURL = newValue
            set(newValue, forKey: .aiBaseURL)
        }
    }
     @Published private var _aiBaseURL: String?

    var aiModelName: String? {
        get { _aiModelName }
        set {
            _aiModelName = newValue
            set(newValue, forKey: .aiModelName)
        }
    }
     @Published private var _aiModelName: String?
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
