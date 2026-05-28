import XCTest
@testable import BookRoom

final class SettingsTests: DatabaseTestCase {

    func testStringSetting() {
        let manager = SettingsManager()
        manager.configure(with: dbQueue)

        manager.set("test-value", forKey: .aiBaseURL)
        XCTAssertEqual(manager.string(forKey: .aiBaseURL), "test-value")
    }

    func testBoolSetting() {
        let manager = SettingsManager()
        manager.configure(with: dbQueue)

        XCTAssertFalse(manager.bool(forKey: .aiEnabled))

        manager.set(true, forKey: .aiEnabled)
        XCTAssertTrue(manager.bool(forKey: .aiEnabled))

        manager.set(false, forKey: .aiEnabled)
        XCTAssertFalse(manager.bool(forKey: .aiEnabled))
    }

    func testIntSetting() {
        let manager = SettingsManager()
        manager.configure(with: dbQueue)

        manager.set(42, forKey: .aiTimeout)
        XCTAssertEqual(manager.int(forKey: .aiTimeout), 42)
    }

    func testDoubleSetting() {
        let manager = SettingsManager()
        manager.configure(with: dbQueue)

        manager.set(0.7, forKey: .aiTemperature)
        XCTAssertEqual(manager.double(forKey: .aiTemperature), 0.7)
    }

    func testArraySetting() {
        let manager = SettingsManager()
        manager.configure(with: dbQueue)

        let tags = ["tag-1", "tag-2", "tag-3"]
        manager.set(tags, forKey: .scanDefaultTagIDs)
        XCTAssertEqual(manager.array(forKey: .scanDefaultTagIDs), tags)
    }

    func testDeleteSetting() {
        let manager = SettingsManager()
        manager.configure(with: dbQueue)

        manager.set("value", forKey: .aiBaseURL)
        XCTAssertNotNil(manager.string(forKey: .aiBaseURL))

        manager.set(nil, forKey: .aiBaseURL)
        XCTAssertNil(manager.string(forKey: .aiBaseURL))
    }

    func testDisplayModePersisted() {
        let manager = SettingsManager()
        manager.configure(with: dbQueue)

        XCTAssertEqual(manager.displayMode, .list)

        manager.displayMode = .grid
        XCTAssertEqual(manager.displayMode, .grid)
    }

    func testSortSettings() {
        let manager = SettingsManager()
        manager.configure(with: dbQueue)

        XCTAssertEqual(manager.sortField, .pinyin)
        XCTAssertEqual(manager.sortOrder, .ascending)

        manager.sortField = .createdAt
        manager.sortOrder = .descending
        XCTAssertEqual(manager.sortField, .createdAt)
        XCTAssertEqual(manager.sortOrder, .descending)
    }
}
