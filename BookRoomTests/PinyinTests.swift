import XCTest
@testable import BookRoom

final class PinyinTests: XCTestCase {

    func testFullPinyin() {
        let (full, initials) = Pinyin.analyze("数据结构")
        XCTAssertEqual(full, "shujujiegou")
        XCTAssertEqual(initials, "sjjg")
    }

    func testFullPinyinMixed() {
        let (full, _) = Pinyin.analyze("C++编程")
        // "C" stays as-is, Chinese chars convert
        XCTAssertFalse(full.isEmpty)
    }

    func testInitialsOnly() {
        let initials = Pinyin.toInitials("测试")
        XCTAssertEqual(initials, "cs")
    }

    func testEmptyString() {
        let (full, initials) = Pinyin.analyze("")
        XCTAssertEqual(full, "")
        XCTAssertEqual(initials, "")
    }

    func testPureEnglish() {
        let (full, initials) = Pinyin.analyze("Hello World")
        XCTAssertEqual(full, "hello world")
        XCTAssertEqual(initials, "hw")
    }

    func testSearchIndexEntry() {
        let entry = SearchIndexEntry.from(
            title: "三体",
            authors: ["刘慈欣"],
            translators: nil,
            publisher: "重庆出版社",
            isbn: "9787536692930",
            tags: ["科幻"],
            shelf: "书房A柜",
            location: nil,
            purchaseChannel: "京东",
            bookID: "test-1"
        )

        // Verify pinyin was generated
        XCTAssertFalse(entry.pinyinTitleFull.isEmpty)
        XCTAssertFalse(entry.pinyinTitleInitials.isEmpty)
        XCTAssertFalse(entry.pinyinAuthorsFull.isEmpty)
        XCTAssertFalse(entry.pinyinAuthorsInitials.isEmpty)

        // Verify normalization
        XCTAssertTrue(entry.normalizedTitle.contains("三体") || entry.normalizedTitle.contains("san"))
        XCTAssertEqual(entry.normalizedISBN, "9787536692930")
    }

    func testSearchIndexEntryISBNNormalization() {
        let entry = SearchIndexEntry.from(
            title: "Test",
            authors: nil,
            translators: nil,
            publisher: nil,
            isbn: "978-7-5366-9293-0",
            tags: nil,
            shelf: nil,
            location: nil,
            purchaseChannel: nil,
            bookID: "test-2"
        )

        XCTAssertEqual(entry.normalizedISBN, "9787536692930")
    }
}
