import XCTest
@testable import BookRoom

final class TagRepositoryTests: DatabaseTestCase {

    private func createTag(name: String) -> Tag {
        let now = ISO8601DateFormatter().string(from: Date())
        return Tag(
            id: UUID().uuidString,
            name: name,
            color: "blue",
            sortOrder: 0,
            createdAt: now,
            updatedAt: now,
            deletedAt: nil
        )
    }

    func testInsertAndFetch() throws {
        let tag = createTag(name: "科幻")
        let saved = try tagRepo.insert(tag)
        XCTAssertEqual(saved.name, "科幻")

        let fetched = try tagRepo.fetch(byID: saved.id)
        XCTAssertEqual(fetched?.name, "科幻")
    }

    func testUniqueName() throws {
        let tag1 = createTag(name: "UniqueTag")
        try tagRepo.insert(tag1)

        let tag2 = createTag(name: "UniqueTag")
        // Should fail due to unique constraint
        XCTAssertThrowsError(try tagRepo.insert(tag2))
    }

    func testGetOrCreate() throws {
        // First call creates
        let tag1 = try tagRepo.getOrCreate(name: "NewLabel")
        XCTAssertEqual(tag1.name, "NewLabel")

        // Second call returns existing
        let tag2 = try tagRepo.getOrCreate(name: "NewLabel")
        XCTAssertEqual(tag2.id, tag1.id)
    }

    func testDeleteRemovesAssociations() throws {
        let tag = createTag(name: "TempTag")
        let savedTag = try tagRepo.insert(tag)

        let book = createBook(title: "Tagged Book")
        let savedBook = try bookRepo.insert(book)

        try tagRepo.addTag(tagID: savedTag.id, toBook: savedBook.id)

        try tagRepo.delete(id: savedTag.id)

        // Book should still exist
        let fetchedBook = try bookRepo.fetch(byID: savedBook.id)
        XCTAssertNotNil(fetchedBook)

        // Tag association should be removed
        let tags = try tagRepo.fetchTags(forBookID: savedBook.id)
        XCTAssertTrue(tags.isEmpty)
    }

    func testAddAndRemoveTags() throws {
        let tag1 = createTag(name: "TagA")
        let tag2 = createTag(name: "TagB")
        let tag3 = createTag(name: "TagC")
        try tagRepo.insert(tag1)
        try tagRepo.insert(tag2)
        try tagRepo.insert(tag3)

        let book = createBook(title: "MultiTag Book")
        let savedBook = try bookRepo.insert(book)

        // Add tags
        try tagRepo.setTags(tagIDs: [tag1.id, tag2.id], forBook: savedBook.id)
        var tags = try tagRepo.fetchTags(forBookID: savedBook.id)
        XCTAssertEqual(tags.count, 2)

        // Remove one tag
        try tagRepo.removeTag(tagID: tag1.id, fromBook: savedBook.id)
        tags = try tagRepo.fetchTags(forBookID: savedBook.id)
        XCTAssertEqual(tags.count, 1)
        XCTAssertEqual(tags.first?.name, "TagB")
    }

    func testBatchAddTags() throws {
        let tag = createTag(name: "BatchTag")
        try tagRepo.insert(tag)

        let book1 = createBook(title: "Book 1")
        let book2 = createBook(title: "Book 2")
        let saved1 = try bookRepo.insert(book1)
        let saved2 = try bookRepo.insert(book2)

        try tagRepo.addTags(tagIDs: [tag.id], toBooks: [saved1.id, saved2.id])

        let tags1 = try tagRepo.fetchTags(forBookID: saved1.id)
        let tags2 = try tagRepo.fetchTags(forBookID: saved2.id)

        XCTAssertEqual(tags1.count, 1)
        XCTAssertEqual(tags2.count, 1)
    }

    func testFetchAllWithCounts() throws {
        let tag1 = createTag(name: "CountTag1")
        let tag2 = createTag(name: "CountTag2")
        try tagRepo.insert(tag1)
        try tagRepo.insert(tag2)

        let book1 = createBook(title: "Book A")
        let book2 = createBook(title: "Book B")
        let saved1 = try bookRepo.insert(book1)
        let saved2 = try bookRepo.insert(book2)

        try tagRepo.addTag(tagID: tag1.id, toBook: saved1.id)
        try tagRepo.addTag(tagID: tag1.id, toBook: saved2.id)
        try tagRepo.addTag(tagID: tag2.id, toBook: saved1.id)

        let result = try tagRepo.fetchAllWithCounts()
        let tag1Result = result.first(where: { $0.tag.id == tag1.id })
        let tag2Result = result.first(where: { $0.tag.id == tag2.id })

        XCTAssertEqual(tag1Result?.bookCount, 2)
        XCTAssertEqual(tag2Result?.bookCount, 1)
    }
}
