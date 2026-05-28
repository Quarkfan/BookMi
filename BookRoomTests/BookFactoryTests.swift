import XCTest
@testable import BookRoom

final class BookFactoryTests: XCTestCase {

    func testDraftToBook() {
        let draft = BookMetadataDraft(
            title: "测试图书",
            subtitle: "副标题",
            authors: ["作者一", "作者二"],
            isbn13: "9787536692930",
            publisher: "测试出版社",
            publishedDate: "2023-01-01",
            pageCount: 300,
            price: "59.00",
            dataSource: "openlibrary"
        )

        let book = Book(from: draft)

        XCTAssertEqual(book.title, "测试图书")
        XCTAssertEqual(book.isbn13, "9787536692930")
        XCTAssertEqual(book.publisher, "测试出版社")
        XCTAssertEqual(book.pageCount, 300)
        XCTAssertEqual(book.price, "59.00")
        XCTAssertEqual(book.dataSource, "openlibrary")
        XCTAssertEqual(book.readingStatus, .unread)
        XCTAssertEqual(book.borrowStatus, .available)

        // Authors should be JSON encoded
        let authors = try? JSONDecoder().decode([String].self, from: Data(book.authorsJSON!.utf8))
        XCTAssertEqual(authors, ["作者一", "作者二"])
    }

    func testDraftToBookWithDefaults() {
        let draft = BookMetadataDraft(title: "Minimal Book")
        let book = Book(from: draft)

        XCTAssertEqual(book.title, "Minimal Book")
        XCTAssertNotNil(book.id)
        XCTAssertNotNil(book.createdAt)
        XCTAssertNotNil(book.updatedAt)
        XCTAssertEqual(book.copyIndex, 1)
        XCTAssertFalse(book.isFavorite)
    }

    func testDraftToBookWithShelfAndTags() {
        let draft = BookMetadataDraft(title: "Tagged Book")
        let book = Book(from: draft, shelfID: "shelf-1", tags: ["tag-1"], purchaseChannelID: "channel-1")

        XCTAssertEqual(book.shelfID, "shelf-1")
        XCTAssertEqual(book.purchaseChannelID, "channel-1")
    }

    func testEmptyTitleFallback() {
        let draft = BookMetadataDraft()
        let book = Book(from: draft)

        // Empty title should fallback to "未知书名"
        XCTAssertEqual(book.title, "未知书名")
    }

    func testISBNNormalization() {
        let isbn1 = BookRepository.normalizeISBN("978-7-5366-9293-0")
        XCTAssertEqual(isbn1, "9787536692930")

        let isbn2 = BookRepository.normalizeISBN("978 7 5366 9293 0")
        XCTAssertEqual(isbn2, "9787536692930")
    }

    func testParseISBN10() {
        let result = BookRepository.parseISBN("7111544307")
        XCTAssertEqual(result.isbn10, "7111544307")
        XCTAssertNil(result.isbn13)
    }

    func testParseISBN13() {
        let result = BookRepository.parseISBN("9787111544302")
        XCTAssertNil(result.isbn10)
        XCTAssertEqual(result.isbn13, "9787111544302")
    }

    func testParseISBNWithSeparators() {
        let result = BookRepository.parseISBN("978-7-111-54430-2")
        XCTAssertNil(result.isbn10)
        XCTAssertEqual(result.isbn13, "9787111544302")
    }

    func testMergeDrafts() {
        let draft1 = BookMetadataDraft(
            title: "Title1",
            authors: ["Author1"],
            coverURL: URL(string: "https://example.com/cover1.jpg")
        )
        let draft2 = BookMetadataDraft(
            title: nil,
            publisher: "Publisher2",
            pageCount: 400,
            coverURL: URL(string: "https://example.com/cover2.jpg")
        )

        let merged = draft1.merging(with: draft2)

        XCTAssertEqual(merged.title, "Title1") // draft1 has it
        XCTAssertEqual(merged.authors, ["Author1"]) // draft1 has it
        XCTAssertEqual(merged.publisher, "Publisher2") // filled from draft2
        XCTAssertEqual(merged.pageCount, 400) // filled from draft2
    }
}
