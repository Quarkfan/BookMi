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

    func testInsertAndFetch() throws {
        let shelf = createShelf(name: "书房A柜")
        let saved = try shelfRepo.insert(shelf)
        XCTAssertEqual(saved.name, "书房A柜")

        let fetched = try shelfRepo.fetch(byID: saved.id)
        XCTAssertNotNil(fetched)
        XCTAssertEqual(fetched?.name, "书房A柜")
    }

    func testFetchAllOrdered() throws {
        let shelf1 = createShelf(name: "Z书架")
        let shelf2 = createShelf(name: "A书柜")
        try shelfRepo.insert(shelf1)
        try shelfRepo.insert(shelf2)

        let shelves = try shelfRepo.fetchAll()
        // Sorted by name ascending (sort_order is 0 for both)
        XCTAssertEqual(shelves.first?.name, "A书柜")
    }

    func testDeleteAndUnclassify() throws {
        let shelf = createShelf(name: "Temp Shelf")
        let saved = try shelfRepo.insert(shelf)

        let book = createBook(title: "Book in Shelf")
        var bookWithShelf = book
        bookWithShelf.shelfID = saved.id
        try bookRepo.insert(bookWithShelf)

        try shelfRepo.deleteAndUnclassify(id: saved.id)

        // Book should have nil shelf_id
        let updatedBook = try bookRepo.fetch(byID: book.id)
        XCTAssertNil(updatedBook?.shelfID)

        // Shelf should be soft-deleted
        let fetchedShelf = try shelfRepo.fetch(byID: saved.id)
        // It's deleted, so fetchAll won't return it
        let all = try shelfRepo.fetchAll()
        XCTAssertFalse(all.contains { $0.id == saved.id })
    }

    func testFetchAllWithBookCounts() throws {
        let shelf = createShelf(name: "书房柜")
        try shelfRepo.insert(shelf)

        let book1 = createBook(title: "Book 1")
        book1.shelfID = shelf.id
        let book2 = createBook(title: "Book 2")
        book2.shelfID = shelf.id
        try bookRepo.insert(book1)
        try bookRepo.insert(book2)

        let result = try shelfRepo.fetchAllWithBookCounts()
        let shelfResult = result.first(where: { $0.shelf.id == shelf.id })
        XCTAssertEqual(shelfResult?.bookCount, 2)
    }

    func testFetchByName() throws {
        let shelf = createShelf(name: "UniqueShelf")
        try shelfRepo.insert(shelf)

        let found = try shelfRepo.fetch(byName: "UniqueShelf")
        XCTAssertNotNil(found)
    }
}
