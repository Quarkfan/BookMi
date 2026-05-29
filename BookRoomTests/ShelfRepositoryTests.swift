import XCTest
@testable import BookRoom

final class ShelfRepositoryTests: DatabaseTestCase {

    private func createShelf(name: String) -> Shelf {
        let now = ISO8601DateFormatter().string(from: Date())
        return Shelf(
            id: UUID().uuidString,
            name: name,
            locationNote: nil,
            sortOrder: 0,
            note: nil,
            createdAt: now,
            updatedAt: now,
            deletedAt: nil
        )
    }

    func testInsertAndFetch() async throws {
        let shelf = createShelf(name: "书房A柜")
        let saved = try await shelfRepo.insert(shelf)
        XCTAssertEqual(saved.name, "书房A柜")

        let fetched = try await shelfRepo.fetch(byID: saved.id)
        XCTAssertNotNil(fetched)
        XCTAssertEqual(fetched?.name, "书房A柜")
    }

    func testFetchAllOrdered() async throws {
        let shelf1 = createShelf(name: "Z书架")
        let shelf2 = createShelf(name: "A书柜")
        try await shelfRepo.insert(shelf1)
        try await shelfRepo.insert(shelf2)

        let shelves = try await shelfRepo.fetchAll()
        // Sorted by name ascending (sort_order is 0 for both)
        XCTAssertEqual(shelves.first?.name, "A书柜")
    }

    func testDeleteAndUnclassify() async throws {
        let shelf = createShelf(name: "Temp Shelf")
        let saved = try await shelfRepo.insert(shelf)

        let book = createBook(title: "Book in Shelf")
        var bookWithShelf = book
        bookWithShelf.shelfID = saved.id
        try await bookRepo.insert(bookWithShelf)

        try await shelfRepo.deleteAndUnclassify(id: saved.id)

        // Book should have nil shelf_id
        let updatedBook = try await bookRepo.fetch(byID: book.id)
        XCTAssertNil(updatedBook?.shelfID)

        // Shelf should be soft-deleted
        let fetchedShelf = try await shelfRepo.fetch(byID: saved.id)
        // It's deleted, so fetchAll won't return it
        let all = try await shelfRepo.fetchAll()
        XCTAssertFalse(all.contains { $0.id == saved.id })
    }

    func testFetchAllWithBookCounts() async throws {
        let shelf = createShelf(name: "书房柜")
        try await shelfRepo.insert(shelf)

        let book1 = createBook(title: "Book 1")
        book1.shelfID = shelf.id
        let book2 = createBook(title: "Book 2")
        book2.shelfID = shelf.id
        try await bookRepo.insert(book1)
        try await bookRepo.insert(book2)

        let result = try await shelfRepo.fetchAllWithBookCounts()
        let shelfResult = result.first(where: { $0.shelf.id == shelf.id })
        XCTAssertEqual(shelfResult?.bookCount, 2)
    }

    func testFetchByName() async throws {
        let shelf = createShelf(name: "UniqueShelf")
        try await shelfRepo.insert(shelf)

        let found = try await shelfRepo.fetch(byName: "UniqueShelf")
        XCTAssertNotNil(found)
    }
}
