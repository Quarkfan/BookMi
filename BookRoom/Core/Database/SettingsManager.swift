import Foundation

/// Sync settings manager using UserDefaults (fire-and-forget persistence)
final class SettingsManager: ObservableObject {
    static let shared = SettingsManager()

    @Published var displayMode: DisplayMode = .list {
        didSet { UserDefaults.standard.set(displayMode.rawValue, forKey: "ui.display_mode") }
    }
    @Published var sortField: SortField = .pinyin {
        didSet { UserDefaults.standard.set(sortField.rawValue, forKey: "ui.sort_field") }
    }
    @Published var sortOrder: SortOrder = .ascending {
        didSet { UserDefaults.standard.set(sortOrder.rawValue, forKey: "ui.sort_order") }
    }
    @Published var defaultShelfID: String? {
        didSet { UserDefaults.standard.set(defaultShelfID, forKey: "scan.default_shelf_id") }
    }
    @Published var defaultTagIDs: [String] = [] {
        didSet { try? UserDefaults.standard.set(JSONEncoder().encode(defaultTagIDs), forKey: "scan.default_tag_ids") }
    }
    @Published var defaultPurchaseChannelID: String? {
        didSet { UserDefaults.standard.set(defaultPurchaseChannelID, forKey: "scan.default_purchase_channel_id") }
    }
    @Published var isPasscodeEnabled: Bool = false {
        didSet { UserDefaults.standard.set(isPasscodeEnabled, forKey: "security.passcode_enabled") }
    }
    @Published var isBiometricEnabled: Bool = false {
        didSet { UserDefaults.standard.set(isBiometricEnabled, forKey: "security.biometric_enabled") }
    }
    @Published var isAICapabilityEnabled: Bool = false {
        didSet { UserDefaults.standard.set(isAICapabilityEnabled, forKey: "ai.enabled") }
    }
    @Published var aiBaseURL: String? {
        didSet { UserDefaults.standard.set(aiBaseURL, forKey: "ai.base_url") }
    }
    @Published var aiModelName: String? {
        didSet { UserDefaults.standard.set(aiModelName, forKey: "ai.model_name") }
    }
    @Published var aiTimeout: Int = 60 {
        didSet { UserDefaults.standard.set(aiTimeout, forKey: "ai.timeout_seconds") }
    }
    @Published var aiMaxTokens: Int = 2000 {
        didSet { UserDefaults.standard.set(aiMaxTokens, forKey: "ai.max_tokens") }
    }

    func load() {
        if let raw = UserDefaults.standard.string(forKey: "ui.display_mode"),
           let v = DisplayMode(rawValue: raw) { displayMode = v }
        if let raw = UserDefaults.standard.string(forKey: "ui.sort_field"),
           let v = SortField(rawValue: raw) { sortField = v }
        if let raw = UserDefaults.standard.string(forKey: "ui.sort_order"),
           let v = SortOrder(rawValue: raw) { sortOrder = v }
        defaultShelfID = UserDefaults.standard.string(forKey: "scan.default_shelf_id")
        if let data = UserDefaults.standard.data(forKey: "scan.default_tag_ids"),
           let arr = try? JSONDecoder().decode([String].self, from: data) { defaultTagIDs = arr }
        defaultPurchaseChannelID = UserDefaults.standard.string(forKey: "scan.default_purchase_channel_id")
        isPasscodeEnabled = UserDefaults.standard.bool(forKey: "security.passcode_enabled")
        isBiometricEnabled = UserDefaults.standard.bool(forKey: "security.biometric_enabled")
        isAICapabilityEnabled = UserDefaults.standard.bool(forKey: "ai.enabled")
        aiBaseURL = UserDefaults.standard.string(forKey: "ai.base_url")
        aiModelName = UserDefaults.standard.string(forKey: "ai.model_name")
        aiTimeout = UserDefaults.standard.integer(forKey: "ai.timeout_seconds")
        if aiTimeout == 0 { aiTimeout = 60 }
        aiMaxTokens = UserDefaults.standard.integer(forKey: "ai.max_tokens")
        if aiMaxTokens == 0 { aiMaxTokens = 2000 }
    }
}

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
