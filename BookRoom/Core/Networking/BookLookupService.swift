import Foundation

// MARK: - Book Metadata Draft

struct BookMetadataDraft: Codable, Identifiable {
    var id: String { isbn13 ?? isbn10 ?? UUID().uuidString }

    var title: String?
    var subtitle: String?
    var authors: [String]?
    var translators: [String]?
    var isbn10: String?
    var isbn13: String?
    var publisher: String?
    var publishedDate: String?
    var pageCount: Int?
    var price: String?
    var edition: String?
    var series: String?
    var binding: String?
    var language: String?
    var category: String?
    var summary: String?
    var coverURL: URL?
    var dataSource: String?
    var rawJSON: String?

    /// Check if this draft has meaningful data
    var hasContent: Bool {
        title != nil && !title!.isEmpty
    }

    /// Merge another draft into this one, filling empty fields
    func merging(with other: BookMetadataDraft) -> BookMetadataDraft {
        var merged = self
        if merged.title == nil || merged.title!.isEmpty { merged.title = other.title }
        if merged.subtitle == nil { merged.subtitle = other.subtitle }
        if merged.authors == nil || merged.authors!.isEmpty { merged.authors = other.authors }
        if merged.translators == nil { merged.translators = other.translators }
        if merged.isbn10 == nil { merged.isbn10 = other.isbn10 }
        if merged.isbn13 == nil { merged.isbn13 = other.isbn13 }
        if merged.publisher == nil { merged.publisher = other.publisher }
        if merged.publishedDate == nil { merged.publishedDate = other.publishedDate }
        if merged.pageCount == nil { merged.pageCount = other.pageCount }
        if merged.price == nil { merged.price = other.price }
        if merged.edition == nil { merged.edition = other.edition }
        if merged.series == nil { merged.series = other.series }
        if merged.binding == nil { merged.binding = other.binding }
        if merged.language == nil { merged.language = other.language }
        if merged.category == nil { merged.category = other.category }
        if merged.summary == nil { merged.summary = other.summary }
        if merged.coverURL == nil { merged.coverURL = other.coverURL }
        return merged
    }
}

// MARK: - Book Lookup Protocol

protocol BookLookupProvider {
    var name: String { get }
    func lookup(isbn: String) async throws -> [BookMetadataDraft]
    func search(keyword: String) async throws -> [BookMetadataDraft]
}

// MARK: - Book Lookup Service

final class BookLookupService {
    /// Providers in priority order (Chinese-first)
    static let defaultProviders: [BookLookupProvider] = [
        OpenLibraryProvider(),
        GoogleBooksProvider()
    ]

    private let providers: [BookLookupProvider]

    init(providers: [BookLookupProvider] = Self.defaultProviders) {
        self.providers = providers
    }

    /// Look up a book by ISBN across all providers, return merged results
    func lookup(isbn: String) async -> [BookMetadataDraft] {
        var results: [BookMetadataDraft] = []

        await withTaskGroup(of: [BookMetadataDraft].self) { group in
            for provider in providers {
                group.addTask {
                    do {
                        return try await provider.lookup(isbn: isbn)
                    } catch {
                        print("[\(provider.name)] ISBN lookup failed: \(error)")
                        return []
                    }
                }
            }
            for await result in group {
                results.append(contentsOf: result)
            }
        }

        // Merge duplicates by ISBN
        return mergeResults(results)
    }

    /// Search books by keyword across all providers
    func search(keyword: String) async -> [BookMetadataDraft] {
        var results: [BookMetadataDraft] = []

        await withTaskGroup(of: [BookMetadataDraft].self) { group in
            for provider in providers {
                group.addTask {
                    do {
                        return try await provider.search(keyword: keyword)
                    } catch {
                        print("[\(provider.name)] Search failed: \(error)")
                        return []
                    }
                }
            }
            for await result in group {
                results.append(contentsOf: result)
            }
        }

        return results
    }

    private func mergeResults(_ results: [BookMetadataDraft]) -> [BookMetadataDraft] {
        var grouped: [String: BookMetadataDraft] = [:]
        for result in results {
            let key = result.id
            if let existing = grouped[key] {
                grouped[key] = existing.merging(with: result)
            } else {
                grouped[key] = result
            }
        }
        return Array(grouped.values)
    }
}
