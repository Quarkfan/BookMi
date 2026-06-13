import XCTest
@testable import BookRoom

final class SearchRepositoryTests: DatabaseTestCase {

    private func createAndIndexBook(title: String, authors: [String]? = nil, isbn13: String? = nil) async throws -> Book {
        var book = createBook(title: title, isbn13: isbn13)
        if let authors {
            book.authorsJSON = try? String(data: JSONEncoder().encode(authors), encoding: .utf8)
        }
        let saved = try await bookRepo.insert(book)
        try await searchRepo.updateIndex(for: saved)
        return saved
    }

    func testSearchByTitle() async throws {
        _ = try await createAndIndexBook(title: "三体")
        _ = try await createAndIndexBook(title: "流浪地球")

        let results = try await searchRepo.searchWithLike(keyword: "三体")
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.title, "三体")
    }

    func testSearchByPinyin() async throws {
        _ = try await createAndIndexBook(title: "数据结构")

        let resultsFull = try await searchRepo.searchWithLike(keyword: "shujujiegou")
        XCTAssertFalse(resultsFull.isEmpty)

        let resultsInitials = try await searchRepo.searchWithLike(keyword: "sjjg")
        XCTAssertFalse(resultsInitials.isEmpty)
    }

    func testSearchByISBN() async throws {
        _ = try await createAndIndexBook(title: "ISBN Book", isbn13: "9787536692930")

        let results = try await searchRepo.searchWithLike(keyword: "9787536692930")
        XCTAssertEqual(results.count, 1)
    }

    func testSearchByAuthor() async throws {
        _ = try await createAndIndexBook(title: "作者测试", authors: ["刘慈欣"])

        let results = try await searchRepo.searchWithLike(keyword: "刘慈欣")
        XCTAssertEqual(results.count, 1)
    }

    func testEmptySearch() async throws {
        _ = try await createAndIndexBook(title: "Test Book")

        let results = try await searchRepo.searchWithLike(keyword: "")
        XCTAssertTrue(results.isEmpty)
    }

    func testRebuildIndex() async throws {
        _ = try await bookRepo.insert(createBook(title: "Book A"))
        _ = try await bookRepo.insert(createBook(title: "Book B"))

        // Rebuild should not throw
        try await searchRepo.rebuildIndex()

        // After rebuild, search should still work
        let results = try await searchRepo.searchWithLike(keyword: "Book")
        XCTAssertGreaterThanOrEqual(results.count, 2)
    }

    func testRebuildPinyinIndex() async throws {
        _ = try await createAndIndexBook(title: "中文书名")

        try await searchRepo.rebuildPinyinIndex()

        let results = try await searchRepo.searchWithLike(keyword: "zwsm")
        XCTAssertFalse(results.isEmpty)
    }

    func testSearchExcludesDeleted() async throws {
        let book = try await createAndIndexBook(title: "Delete Me")
        try await bookRepo.softDelete(id: book.id)

        let results = try await searchRepo.searchWithLike(keyword: "Delete")
        XCTAssertTrue(results.isEmpty)
    }
}
