import XCTest
@testable import BookRoom

final class SettingsTests: XCTestCase {
    private let keys = [
        "ui.display_mode",
        "ui.sort_field",
        "ui.sort_order",
        "scan.default_shelf_id",
        "scan.default_tag_ids",
        "scan.default_purchase_channel_id",
        "security.passcode_enabled",
        "security.biometric_enabled",
        "ai.enabled",
        "ai.base_url",
        "ai.model_name",
        "ai.timeout_seconds",
        "ai.max_tokens",
    ]

    override func setUp() {
        super.setUp()
        clearSettings()
    }

    override func tearDown() {
        clearSettings()
        super.tearDown()
    }

    func testDisplayModePersistedAndLoaded() {
        let manager = SettingsManager()
        manager.displayMode = .grid

        let loaded = SettingsManager()
        loaded.load()

        XCTAssertEqual(loaded.displayMode, .grid)
    }

    func testSortSettingsPersistedAndLoaded() {
        let manager = SettingsManager()
        manager.sortField = .createdAt
        manager.sortOrder = .descending

        let loaded = SettingsManager()
        loaded.load()

        XCTAssertEqual(loaded.sortField, .createdAt)
        XCTAssertEqual(loaded.sortOrder, .descending)
    }

    func testScanDefaultsPersistedAndLoaded() {
        let manager = SettingsManager()
        manager.defaultShelfID = "shelf-1"
        manager.defaultTagIDs = ["tag-1", "tag-2"]
        manager.defaultPurchaseChannelID = "channel-1"

        let loaded = SettingsManager()
        loaded.load()

        XCTAssertEqual(loaded.defaultShelfID, "shelf-1")
        XCTAssertEqual(loaded.defaultTagIDs, ["tag-1", "tag-2"])
        XCTAssertEqual(loaded.defaultPurchaseChannelID, "channel-1")
    }

    func testSecurityAndAISettingsPersistedAndLoaded() {
        let manager = SettingsManager()
        manager.isPasscodeEnabled = true
        manager.isBiometricEnabled = true
        manager.isAICapabilityEnabled = true
        manager.aiBaseURL = "https://example.com/v1"
        manager.aiModelName = "test-model"
        manager.aiTimeout = 42
        manager.aiMaxTokens = 1234

        let loaded = SettingsManager()
        loaded.load()

        XCTAssertTrue(loaded.isPasscodeEnabled)
        XCTAssertTrue(loaded.isBiometricEnabled)
        XCTAssertTrue(loaded.isAICapabilityEnabled)
        XCTAssertEqual(loaded.aiBaseURL, "https://example.com/v1")
        XCTAssertEqual(loaded.aiModelName, "test-model")
        XCTAssertEqual(loaded.aiTimeout, 42)
        XCTAssertEqual(loaded.aiMaxTokens, 1234)
    }

    func testDefaultTimeoutsWhenUnset() {
        let manager = SettingsManager()
        manager.load()

        XCTAssertEqual(manager.aiTimeout, 60)
        XCTAssertEqual(manager.aiMaxTokens, 2000)
    }

    private func clearSettings() {
        for key in keys {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }
}
