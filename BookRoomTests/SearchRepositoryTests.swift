import XCTest
@testable import BookRoom

final class SearchRepositoryTests: DatabaseTestCase {

    private func createAndIndexBook(title: String, authors: [String]? = nil, isbn13: String? = nil) throws -> Book {
        let book = createBook(title: title, isbn13: isbn13)
        if let authors {
            book.authorsJSON = try? String(data: JSONEncoder().encode(authors), encoding: .utf8)
        }
        let saved = try bookRepo.insert(book)
        try searchRepo.updateIndex(for: saved)
        return saved
    }

    func testSearchByTitle() throws {
        try createAndIndexBook(title: "三体")
        try createAndIndexBook(title: "流浪地球")

        let results = try searchRepo.searchWithLike(keyword: "三体")
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.title, "三体")
    }

    func testSearchByPinyin() throws {
        try createAndIndexBook(title: "数据结构")

        let resultsFull = try searchRepo.searchWithLike(keyword: "shujujiegou")
        XCTAssertFalse(resultsFull.isEmpty)

        let resultsInitials = try searchRepo.searchWithLike(keyword: "sjjg")
        XCTAssertFalse(resultsInitials.isEmpty)
    }

    func testSearchByISBN() throws {
        try createAndIndexBook(title: "ISBN Book", isbn13: "9787536692930")

        let results = try searchRepo.searchWithLike(keyword: "9787536692930")
        XCTAssertEqual(results.count, 1)
    }

    func testSearchByAuthor() throws {
        try createAndIndexBook(title: "作者测试", authors: ["刘慈欣"])

        let results = try searchRepo.searchWithLike(keyword: "刘慈欣")
        XCTAssertEqual(results.count, 1)
    }

    func testEmptySearch() throws {
        try createAndIndexBook(title: "Test Book")

        let results = try searchRepo.searchWithLike(keyword: "")
        XCTAssertTrue(results.isEmpty)
    }

    func testRebuildIndex() throws {
        try createBook(title: "Book A")
        try createBook(title: "Book B")
        let books = try bookRepo.fetchAll()

        // Rebuild should not throw
        XCTAssertNoThrow(try searchRepo.rebuildIndex())

        // After rebuild, search should still work
        let results = try searchRepo.searchWithLike(keyword: "Book")
        XCTAssertGreaterThanOrEqual(results.count, 2)
    }

    func testRebuildPinyinIndex() throws {
        try createAndIndexBook(title: "中文书名")

        XCTAssertNoThrow(try searchRepo.rebuildPinyinIndex())

        let results = try searchRepo.searchWithLike(keyword: "zwsm")
        XCTAssertFalse(results.isEmpty)
    }

    func testSearchExcludesDeleted() throws {
        let book = try createAndIndexBook(title: "Delete Me")
        try bookRepo.softDelete(id: book.id)

        let results = try searchRepo.searchWithLike(keyword: "Delete")
        XCTAssertTrue(results.isEmpty)
    }
}
