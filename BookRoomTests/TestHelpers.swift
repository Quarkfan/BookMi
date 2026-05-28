import XCTest
@testable import BookRoom

/// Shared test helper for creating Book instances
extension DatabaseTestCase {
    func createBook(title: String, isbn13: String? = nil) -> Book {
        let now = ISO8601DateFormatter().string(from: Date())
        return Book(
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
    }
}
