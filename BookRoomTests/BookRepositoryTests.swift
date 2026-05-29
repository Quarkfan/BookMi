import XCTest
@testable import BookRoom

final class BookRepositoryTests: DatabaseTestCase {

    // MARK: - Tests

    func testInsertAndFetch() async throws {
        let book = createBook(title: "测试图书")
        let saved = try await bookRepo.insert(book)
        XCTAssertNotNil(saved.id)

        let fetched = try await bookRepo.fetch(byID: saved.id)
        XCTAssertNotNil(fetched)
        XCTAssertEqual(fetched?.title, "测试图书")
    }

    func testFetchAllExcludesDeleted() async throws {
        let book1 = createBook(title: "Book 1")
        let book2 = createBook(title: "Book 2")
        try await bookRepo.insert(book1)
        try await bookRepo.insert(book2)

        var all = try await bookRepo.fetchAll()
        XCTAssertEqual(all.count, 2)

        try await bookRepo.softDelete(id: book1.id)
        all = try await bookRepo.fetchAll()
        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(all.first?.title, "Book 2")
    }

    func testFetchByISBN() async throws {
        let book = createBook(title: "ISBN Book", isbn13: "9787536692930")
        try await bookRepo.insert(book)

        let found = try await bookRepo.fetch(byISBN: "9787536692930")
        XCTAssertEqual(found.count, 1)
        XCTAssertEqual(found.first?.title, "ISBN Book")
    }

    func testUpdate() async throws {
        let book = createBook(title: "Original Title")
        var saved = try await bookRepo.insert(book)

        saved.title = "Updated Title"
        let updated = try await bookRepo.update(saved)

        let fetched = try await bookRepo.fetch(byID: updated.id)
        XCTAssertEqual(fetched?.title, "Updated Title")
    }

    func testSoftDelete() async throws {
        let book = createBook(title: "To Delete")
        let saved = try await bookRepo.insert(book)

        try await bookRepo.softDelete(id: saved.id)

        // Should not appear in active list
        let active = try await bookRepo.fetchAll()
        XCTAssertTrue(active.isEmpty)

        // But should still exist in DB
        let fetched = try await bookRepo.fetch(byID: saved.id)
        XCTAssertNotNil(fetched?.deletedAt)
    }

    func testBatchUpdateReadingStatus() async throws {
        let book1 = createBook(title: "Book A")
        let book2 = createBook(title: "Book B")
        let book3 = createBook(title: "Book C")
        try await bookRepo.insert(book1)
        try await bookRepo.insert(book2)
        try await bookRepo.insert(book3)

        let ids = [book1.id, book2.id]
        try await bookRepo.batchUpdateReadingStatus(bookIDs: ids, status: .finished)

        let fetched1 = try await bookRepo.fetch(byID: book1.id)
        let fetched2 = try await bookRepo.fetch(byID: book2.id)
        let fetched3 = try await bookRepo.fetch(byID: book3.id)

        XCTAssertEqual(fetched1?.readingStatus, .finished)
        XCTAssertEqual(fetched2?.readingStatus, .finished)
        XCTAssertEqual(fetched3?.readingStatus, .unread) // Not in batch
    }

    func testBatchMarkFinished() async throws {
        let book1 = createBook(title: "Reading 1")
        book1.readingStatus = .reading
        let book2 = createBook(title: "Reading 2")
        book2.readingStatus = .reading
        try await bookRepo.insert(book1)
        try await bookRepo.insert(book2)

        try await bookRepo.batchMarkFinished(bookIDs: [book1.id, book2.id])

        let fetched = try await bookRepo.fetch(byID: book1.id)
        XCTAssertEqual(fetched?.readingStatus, .finished)
        XCTAssertEqual(fetched?.progressPercent, 100)
        XCTAssertNotNil(fetched?.finishedAt)
    }

    func testBatchUpdateShelf() async throws {
        let shelf = Shelf(
            id: UUID().uuidString,
            name: "新书柜",
            locationNote: nil,
            sortOrder: 0,
            note: nil,
            createdAt: ISO8601DateFormatter().string(from: Date()),
            updatedAt: ISO8601DateFormatter().string(from: Date()),
            deletedAt: nil
        )
        try await dbQueue.write { db in
            try shelf.insert(db)
        }

        let book1 = createBook(title: "Book X")
        let book2 = createBook(title: "Book Y")
        try await bookRepo.insert(book1)
        try await bookRepo.insert(book2)

        try await bookRepo.batchUpdateShelf(bookIDs: [book1.id], shelfID: shelf.id)

        let fetched1 = try await bookRepo.fetch(byID: book1.id)
        let fetched2 = try await bookRepo.fetch(byID: book2.id)
        XCTAssertEqual(fetched1?.shelfID, shelf.id)
        XCTAssertNil(fetched2?.shelfID) // Not in batch
    }

    func testCountByReadingStatus() async throws {
        let unread = createBook(title: "Unread")
        let reading = createBook(title: "Reading")
        reading.readingStatus = .reading
        let finished = createBook(title: "Finished")
        finished.readingStatus = .finished
        try await bookRepo.insert(unread)
        try await bookRepo.insert(reading)
        try await bookRepo.insert(finished)

        let stats = try await bookRepo.countByReadingStatus()
        let statusMap = Dictionary(stats.map { ($0.status, $0.count) }, uniquingKeysWith: +)

        XCTAssertEqual(statusMap["unread"], 1)
        XCTAssertEqual(statusMap["reading"], 1)
        XCTAssertEqual(statusMap["finished"], 1)
    }

    func testCountByYear() async throws {
        let now = ISO8601DateFormatter().string(from: Date())
        let book = createBook(title: "New Book")
        book.createdAt = now
        try await bookRepo.insert(book)

        let yearly = try await bookRepo.countByYear()
        XCTAssertFalse(yearly.isEmpty)
    }

    func testCountByShelf() async throws {
        let shelf = Shelf(
            id: UUID().uuidString,
            name: "书房A柜",
            locationNote: nil,
            sortOrder: 0,
            note: nil,
            createdAt: ISO8601DateFormatter().string(from: Date()),
            updatedAt: ISO8601DateFormatter().string(from: Date()),
            deletedAt: nil
        )
        try await dbQueue.write { db in
            try shelf.insert(db)
        }

        let book1 = createBook(title: "Book 1")
        book1.shelfID = shelf.id
        let book2 = createBook(title: "Book 2")
        try await bookRepo.insert(book1)
        try await bookRepo.insert(book2)

        let shelfStats = try await bookRepo.countByShelf()
        let shelfCount = shelfStats.first(where: { $0.shelfID == shelf.id })
        XCTAssertEqual(shelfCount?.count, 1)
    }

    func testBatchDelete() async throws {
        let book1 = createBook(title: "Del 1")
        let book2 = createBook(title: "Del 2")
        let book3 = createBook(title: "Keep")
        try await bookRepo.insert(book1)
        try await bookRepo.insert(book2)
        try await bookRepo.insert(book3)

        try await bookRepo.softDelete(ids: [book1.id, book2.id])

        let remaining = try await bookRepo.fetchAll()
        XCTAssertEqual(remaining.count, 1)
        XCTAssertEqual(remaining.first?.title, "Keep")
    }
}
