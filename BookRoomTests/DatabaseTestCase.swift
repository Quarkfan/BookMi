import XCTest
@testable import BookRoom
import GRDB

/// Base test class providing an in-memory database
class DatabaseTestCase: XCTestCase {
    var dbQueue: DatabaseQueue!
    var bookRepo: BookRepository!
    var shelfRepo: ShelfRepository!
    var tagRepo: TagRepository!
    var searchRepo: SearchRepository!

    override func setUp() async throws {
        try await super.setUp()
        dbQueue = try DatabaseQueue()
        try DatabaseManager.shared.initializeTestDatabase(dbQueue)
        bookRepo = BookRepository(dbQueue: dbQueue)
        shelfRepo = ShelfRepository(dbQueue: dbQueue)
        tagRepo = TagRepository(dbQueue: dbQueue)
        searchRepo = SearchRepository(dbQueue: dbQueue)
    }

    override func tearDown() async throws {
        dbQueue = nil
        bookRepo = nil
        shelfRepo = nil
        tagRepo = nil
        searchRepo = nil
        try await super.tearDown()
    }
}
