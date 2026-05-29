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

    func testInsertAndFetch() async throws {
        let tag = createTag(name: "科幻")
        let saved = try await tagRepo.insert(tag)
        XCTAssertEqual(saved.name, "科幻")

        let fetched = try await tagRepo.fetch(byID: saved.id)
        XCTAssertEqual(fetched?.name, "科幻")
    }

    func testUniqueName() async throws {
        let tag1 = createTag(name: "UniqueTag")
        try await tagRepo.insert(tag1)

        let tag2 = createTag(name: "UniqueTag")
        // Should fail due to unique constraint
        XCTAssertThrowsError(try await tagRepo.insert(tag2))
    }

    func testGetOrCreate() async throws {
        // First call creates
        let tag1 = try await tagRepo.getOrCreate(name: "NewLabel")
        XCTAssertEqual(tag1.name, "NewLabel")

        // Second call returns existing
        let tag2 = try await tagRepo.getOrCreate(name: "NewLabel")
        XCTAssertEqual(tag2.id, tag1.id)
    }

    func testDeleteRemovesAssociations() async throws {
        let tag = createTag(name: "TempTag")
        let savedTag = try await tagRepo.insert(tag)

        let book = createBook(title: "Tagged Book")
        let savedBook = try await bookRepo.insert(book)

        try await tagRepo.addTag(tagID: savedTag.id, toBook: savedBook.id)

        try await tagRepo.delete(id: savedTag.id)

        // Book should still exist
        let fetchedBook = try await bookRepo.fetch(byID: savedBook.id)
        XCTAssertNotNil(fetchedBook)

        // Tag association should be removed
        let tags = try await tagRepo.fetchTags(forBookID: savedBook.id)
        XCTAssertTrue(tags.isEmpty)
    }

    func testAddAndRemoveTags() async throws {
        let tag1 = createTag(name: "TagA")
        let tag2 = createTag(name: "TagB")
        let tag3 = createTag(name: "TagC")
        try await tagRepo.insert(tag1)
        try await tagRepo.insert(tag2)
        try await tagRepo.insert(tag3)

        let book = createBook(title: "MultiTag Book")
        let savedBook = try await bookRepo.insert(book)

        // Add tags
        try await tagRepo.setTags(tagIDs: [tag1.id, tag2.id], forBook: savedBook.id)
        var tags = try await tagRepo.fetchTags(forBookID: savedBook.id)
        XCTAssertEqual(tags.count, 2)

        // Remove one tag
        try await tagRepo.removeTag(tagID: tag1.id, fromBook: savedBook.id)
        tags = try await tagRepo.fetchTags(forBookID: savedBook.id)
        XCTAssertEqual(tags.count, 1)
        XCTAssertEqual(tags.first?.name, "TagB")
    }

    func testBatchAddTags() async throws {
        let tag = createTag(name: "BatchTag")
        try await tagRepo.insert(tag)

        let book1 = createBook(title: "Book 1")
        let book2 = createBook(title: "Book 2")
        let saved1 = try await bookRepo.insert(book1)
        let saved2 = try await bookRepo.insert(book2)

        try await tagRepo.addTags(tagIDs: [tag.id], toBooks: [saved1.id, saved2.id])

        let tags1 = try await tagRepo.fetchTags(forBookID: saved1.id)
        let tags2 = try await tagRepo.fetchTags(forBookID: saved2.id)

        XCTAssertEqual(tags1.count, 1)
        XCTAssertEqual(tags2.count, 1)
    }

    func testFetchAllWithCounts() async throws {
        let tag1 = createTag(name: "CountTag1")
        let tag2 = createTag(name: "CountTag2")
        try await tagRepo.insert(tag1)
        try await tagRepo.insert(tag2)

        let book1 = createBook(title: "Book A")
        let book2 = createBook(title: "Book B")
        let saved1 = try await bookRepo.insert(book1)
        let saved2 = try await bookRepo.insert(book2)

        try await tagRepo.addTag(tagID: tag1.id, toBook: saved1.id)
        try await tagRepo.addTag(tagID: tag1.id, toBook: saved2.id)
        try await tagRepo.addTag(tagID: tag2.id, toBook: saved1.id)

        let result = try await tagRepo.fetchAllWithCounts()
        let tag1Result = result.first(where: { $0.tag.id == tag1.id })
        let tag2Result = result.first(where: { $0.tag.id == tag2.id })

        XCTAssertEqual(tag1Result?.bookCount, 2)
        XCTAssertEqual(tag2Result?.bookCount, 1)
    }
}
