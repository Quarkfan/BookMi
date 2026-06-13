import XCTest
@testable import BookRoom

final class CSVServiceTests: DatabaseTestCase {

    // MARK: - Helper

    private func createBook(title: String, authors: [String]? = nil, isbn13: String? = nil) async throws -> Book {
        let now = ISO8601DateFormatter().string(from: Date())
        var book = Book(
            id: UUID().uuidString,
            legacyID: nil,
            title: title,
            subtitle: nil,
            originalTitle: nil,
            authorsJSON: nil,
            translatorsJSON: nil,
            isbn10: nil,
            isbn13: isbn13,
            publisher: nil,
            publishedDate: nil,
            pageCount: nil,
            price: nil,
            edition: nil,
            printing: nil,
            series: nil,
            binding: nil,
            language: nil,
            category: nil,
            summary: nil,
            coverFileName: nil,
            coverURL: nil,
            coverHash: nil,
            shelfID: nil,
            locationDetail: nil,
            purchaseChannelID: nil,
            purchaseDate: nil,
            purchasePrice: nil,
            readingStatus: .unread,
            readingProgressType: nil,
            currentPage: nil,
            progressPercent: nil,
            startedAt: nil,
            finishedAt: nil,
            borrowStatus: .available,
            note: nil,
            dataSource: "test",
            sourceRawData: nil,
            duplicateGroupID: nil,
            copyIndex: 1,
            isFavorite: false,
            customSortKey: nil,
            createdAt: now,
            updatedAt: now,
            deletedAt: nil
        )
        if let authors {
            book.authorsJSON = try? String(data: JSONEncoder().encode(authors), encoding: .utf8)
        }
        return try await bookRepo.insert(book)
    }

    // MARK: - Export Tests

    func testExportToCSV() async throws {
        _ = try await createBook(title: "三体", authors: ["刘慈欣"], isbn13: "9787536692930")
        _ = try await createBook(title: "流浪地球", authors: ["刘慈欣"])

        let fields: [CSVField] = [.title, .authors, .isbn13]
        let url = try await CSVService.exportBooks(
            books: try await bookRepo.fetchAll(),
            fields: fields,
            shelfRepo: shelfRepo,
            tagRepo: tagRepo,
            dbQueue: dbQueue
        )

        let content = try String(contentsOf: url, encoding: .utf8)
        let lines = content.split(omittingEmptySubsequences: true) { $0.isNewline }

        // Header + 2 data rows
        XCTAssertEqual(lines.count, 3)

        // Check header
        XCTAssertEqual(lines[0], "书名,作者,ISBN-13")

        // Check data contains our books
        XCTAssertTrue(content.contains("三体"))
        XCTAssertTrue(content.contains("流浪地球"))
    }

    func testExportAllFields() async throws {
        _ = try await createBook(title: "测试书")

        let url = try await CSVService.exportBooks(
            books: try await bookRepo.fetchAll(),
            fields: CSVField.allCases,
            shelfRepo: shelfRepo,
            tagRepo: tagRepo,
            dbQueue: dbQueue
        )

        let content = try String(contentsOf: url, encoding: .utf8)
        let header = content.split(separator: "\n").first!
        let headers = header.split(separator: ",").map(String.init)
        XCTAssertEqual(headers.count, CSVField.allCases.count)
    }

    // MARK: - Import Tests

    func testParseCSVHandlesQuotedCommasQuotesAndNewlines() {
        let csvContent = """
        书名,作者,简介
        "书, 一号","作者A","他说""很好""
        还能换行"
        """

        let rows = CSVService.parseCSV(csvContent)

        XCTAssertEqual(rows.count, 2)
        XCTAssertEqual(rows[0], ["书名", "作者", "简介"])
        XCTAssertEqual(rows[1][0], "书, 一号")
        XCTAssertEqual(rows[1][1], "作者A")
        XCTAssertEqual(rows[1][2], "他说\"很好\"\n还能换行")
    }

    func testImportFromCSV() async throws {
        // Create a CSV file
        let csvContent = """
        书名,作者,ISBN-13
        导入书一,作者A,9781111111111
        导入书二,作者B,9782222222222
        导入书三,作者C,9783333333333
        """
        let csvURL = AppPaths.tempImportURL.appendingPathComponent("test_import.csv")
        try csvContent.write(to: csvURL, atomically: true, encoding: .utf8)

        let fieldMapping: [String: CSVField] = [
            "书名": .title,
            "作者": .authors,
            "ISBN-13": .isbn13
        ]

        let report = try await CSVService.importBooks(
            csvURL: csvURL,
            fieldMapping: fieldMapping,
            defaultShelfID: nil,
            defaultTagIDs: [],
            defaultPurchaseChannelID: nil,
            duplicateStrategy: .createNewCopy,
            bookRepo: bookRepo,
            tagRepo: tagRepo,
            searchRepo: searchRepo
        )

        XCTAssertEqual(report.created, 3)
        XCTAssertEqual(report.skipped, 0)
        XCTAssertEqual(report.totalRows, 3)

        // Verify books are in database
        let books = try await bookRepo.fetchAll()
        XCTAssertGreaterThanOrEqual(books.count, 3)
        XCTAssertTrue(books.contains { $0.title == "导入书一" })
        XCTAssertTrue(books.contains { $0.title == "导入书二" })
        XCTAssertTrue(books.contains { $0.title == "导入书三" })
    }

    func testImportSkipsDuplicates() async throws {
        // Create CSV with duplicate ISBNs
        let csvContent = """
        书名,ISBN-13
        书一,9789999999999
        书二,9789999999999
        """
        let csvURL = AppPaths.tempImportURL.appendingPathComponent("test_dup.csv")
        try csvContent.write(to: csvURL, atomically: true, encoding: .utf8)

        let fieldMapping: [String: CSVField] = [
            "书名": .title,
            "ISBN-13": .isbn13
        ]

        // First import
        let report1 = try await CSVService.importBooks(
            csvURL: csvURL,
            fieldMapping: fieldMapping,
            defaultShelfID: nil,
            defaultTagIDs: [],
            defaultPurchaseChannelID: nil,
            duplicateStrategy: .skip,
            bookRepo: bookRepo,
            tagRepo: tagRepo,
            searchRepo: searchRepo
        )
        XCTAssertEqual(report1.created, 2)

        // Second import with skip strategy
        let report2 = try await CSVService.importBooks(
            csvURL: csvURL,
            fieldMapping: fieldMapping,
            defaultShelfID: nil,
            defaultTagIDs: [],
            defaultPurchaseChannelID: nil,
            duplicateStrategy: .skip,
            bookRepo: bookRepo,
            tagRepo: tagRepo,
            searchRepo: searchRepo
        )
        XCTAssertEqual(report2.skipped, 2) // Both should be skipped
        XCTAssertEqual(report2.created, 0)
    }

    func testImportWithDefaultShelfAndTags() async throws {
        // Create default shelf
        let shelf = Shelf(
            id: UUID().uuidString,
            name: "默认柜",
            locationNote: nil,
            sortOrder: 0,
            note: nil,
            createdAt: ISO8601DateFormatter().string(from: Date()),
            updatedAt: ISO8601DateFormatter().string(from: Date()),
            deletedAt: nil
        )
        try await shelfRepo.insert(shelf)

        // Create default tag
        let tag = Tag(
            id: UUID().uuidString,
            name: "默认标签",
            color: "blue",
            sortOrder: 0,
            createdAt: ISO8601DateFormatter().string(from: Date()),
            updatedAt: ISO8601DateFormatter().string(from: Date()),
            deletedAt: nil
        )
        try await tagRepo.insert(tag)

        let csvContent = """
        书名
        默认测试书
        """
        let csvURL = AppPaths.tempImportURL.appendingPathComponent("test_defaults.csv")
        try csvContent.write(to: csvURL, atomically: true, encoding: .utf8)

        let fieldMapping: [String: CSVField] = ["书名": .title]

        let report = try await CSVService.importBooks(
            csvURL: csvURL,
            fieldMapping: fieldMapping,
            defaultShelfID: shelf.id,
            defaultTagIDs: [tag.id],
            defaultPurchaseChannelID: nil,
            duplicateStrategy: .createNewCopy,
            bookRepo: bookRepo,
            tagRepo: tagRepo,
            searchRepo: searchRepo
        )

        XCTAssertEqual(report.created, 1)

        // Verify shelf assignment
        let book = try await bookRepo.fetchAll().first { $0.title == "默认测试书" }
        XCTAssertNotNil(book)
        XCTAssertEqual(book?.shelfID, shelf.id)

        // Verify tag assignment
        let bookTags = try await tagRepo.fetchTags(forBookID: book!.id)
        XCTAssertEqual(bookTags.count, 1)
        XCTAssertEqual(bookTags.first?.name, "默认标签")
    }
}
