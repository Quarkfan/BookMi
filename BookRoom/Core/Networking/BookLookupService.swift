import Foundation

protocol BookLookupProvider {
    var name: String { get }
    func lookup(isbn: String) async throws -> [BookMetadataDraft]
    func search(keyword: String) async throws -> [BookMetadataDraft]
}

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

    var hasContent: Bool { title != nil && !title!.isEmpty }

    func merging(with other: BookMetadataDraft) -> BookMetadataDraft {
        var m = self
        if m.title == nil || m.title!.isEmpty { m.title = other.title }
        if m.subtitle == nil { m.subtitle = other.subtitle }
        if m.authors == nil || m.authors!.isEmpty { m.authors = other.authors }
        if m.translators == nil { m.translators = other.translators }
        if m.isbn10 == nil { m.isbn10 = other.isbn10 }
        if m.isbn13 == nil { m.isbn13 = other.isbn13 }
        if m.publisher == nil { m.publisher = other.publisher }
        if m.publishedDate == nil { m.publishedDate = other.publishedDate }
        if m.pageCount == nil { m.pageCount = other.pageCount }
        if m.price == nil { m.price = other.price }
        if m.edition == nil { m.edition = other.edition }
        if m.series == nil { m.series = other.series }
        if m.binding == nil { m.binding = other.binding }
        if m.language == nil { m.language = other.language }
        if m.category == nil { m.category = other.category }
        if m.summary == nil { m.summary = other.summary }
        if m.coverURL == nil { m.coverURL = other.coverURL }
        return m
    }
}

enum BookLookupError: Error, LocalizedError {
    case networkError(String)
    case invalidResponse
    case notFound

    var errorDescription: String? {
        switch self {
        case .networkError(let msg): return "Network error: \(msg)"
        case .invalidResponse: return "Invalid response"
        case .notFound: return "Not found"
        }
    }
}

extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}

/// Book lookup service combining multiple providers
final class BookLookupService {
    static var defaultProviders: [any BookLookupProvider] {
        [OpenLibraryProvider(), GoogleBooksProvider()]
    }

    private let providers: [any BookLookupProvider]

    init(providers: [any BookLookupProvider]) {
        self.providers = providers
    }

    convenience init() {
        self.init(providers: Self.defaultProviders)
    }

    func lookup(isbn: String) async -> [BookMetadataDraft] {
        var results: [BookMetadataDraft] = []

        await withTaskGroup(of: [BookMetadataDraft].self) { group in
            for provider in providers {
                group.addTask {
                    do {
                        return try await provider.lookup(isbn: isbn)
                    } catch {
                        print("[\(type(of: provider))] ISBN lookup failed: \(error)")
                        return []
                    }
                }
            }
            for await result in group {
                results.append(contentsOf: result)
            }
        }

        return mergeResults(results)
    }

    func search(keyword: String) async -> [BookMetadataDraft] {
        var results: [BookMetadataDraft] = []

        await withTaskGroup(of: [BookMetadataDraft].self) { group in
            for provider in providers {
                group.addTask {
                    do {
                        return try await provider.search(keyword: keyword)
                    } catch {
                        print("[\(type(of: provider))] Search failed: \(error)")
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

struct OpenLibraryProvider: BookLookupProvider {
    let name = "Open Library"
    private let baseURL = "https://openlibrary.org"

    func lookup(isbn: String) async throws -> [BookMetadataDraft] {
        let url = URL(string: "\(baseURL)/api/books?bibkeys=ISBN:\(isbn)&format=json&jscmd=data")!
        let (data, response) = try await URLSession.shared.data(from: url)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw BookLookupError.networkError("Invalid response")
        }

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let key = "ISBN:\(isbn)"
        guard let bookData = json?[key] as? [String: Any] else { return [] }

        let draft = BookMetadataDraft(
            title: (bookData["title"] as? String)?.nilIfEmpty,
            subtitle: nil,
            authors: parseOLContributors(bookData["authors"] as? [[String: Any]]),
            translators: nil,
            isbn10: parseISBNFromKey(key, length: 10),
            isbn13: parseISBNFromKey(key, length: 13),
            publisher: (bookData["publishers"] as? [[String: Any]])?.first?["name"] as? String,
            publishedDate: (bookData["publish_date"] as? String)?.nilIfEmpty,
            pageCount: bookData["number_of_pages"] as? Int,
            price: nil,
            edition: (bookData["edition_name"] as? String)?.nilIfEmpty,
            series: nil,
            binding: nil,
            language: nil,
            category: (bookData["subjects"] as? [[String: Any]])?.first?["name"] as? String,
            summary: (bookData["notes"] as? [String: Any])?["value"] as? String,
            coverURL: parseCoverURL(bookData, isbn: isbn),
            dataSource: "openlibrary",
            rawJSON: String(data: data, encoding: .utf8)
        )

        return draft.hasContent ? [draft] : []
    }

    func search(keyword: String) async throws -> [BookMetadataDraft] {
        let encoded = keyword.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? keyword
        let url = URL(string: "\(baseURL)/search.json?title=\(encoded)&limit=20")!
        let (data, _) = try await URLSession.shared.data(from: url)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let docs = json?["docs"] as? [[String: Any]] else { return [] }

        return docs.compactMap { doc -> BookMetadataDraft? in
            guard let title = doc["title"] as? String, !title.isEmpty else { return nil }
            return BookMetadataDraft(
                title: title,
                subtitle: doc["subtitle"] as? String,
                authors: (doc["author_name"] as? [String])?.filter { !$0.isEmpty },
                translators: nil,
                isbn10: (doc["isbn"] as? [String])?.first(where: { $0.count == 10 }),
                isbn13: (doc["isbn"] as? [String])?.first(where: { $0.count == 13 }),
                publisher: (doc["publisher"] as? [String])?.first,
                publishedDate: (doc["first_publish_date"] as? String),
                pageCount: doc["number_of_pages_median"] as? Int,
                price: nil,
                edition: nil,
                series: nil,
                binding: nil,
                language: nil,
                category: (doc["subject"] as? [String])?.first,
                summary: nil,
                coverURL: nil,
                dataSource: "openlibrary",
                rawJSON: nil
            )
        }
    }

    private func parseOLContributors(_ contributors: [[String: Any]]?) -> [String]? {
        contributors?.compactMap { $0["name"] as? String }.filter { !$0.isEmpty }
    }

    private func parseISBNFromKey(_ key: String, length: Int) -> String? {
        let cleaned = key.replacingOccurrences(of: "ISBN:", with: "")
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: " ", with: "")
        return cleaned.count == length ? cleaned : nil
    }

    private func parseCoverURL(_ bookData: [String: Any], isbn: String) -> URL? {
        if let identifies = bookData["identifiers"] as? [String: Any],
           let goodreads = identifies["goodreads"] as? [[String: Any]],
           let id = goodreads.first?["value"] as? String {
            return URL(string: "https://images-na.ssl-images-amazon.com/images/I/\(id).jpg")
        }
        return URL(string: "\(baseURL)/covers/isbn/\(isbn)-M.jpg")
    }
}

struct GoogleBooksProvider: BookLookupProvider {
    let name = "Google Books"
    private let baseURL = "https://www.googleapis.com/books/v1"

    func lookup(isbn: String) async throws -> [BookMetadataDraft] {
        let encoded = isbn.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? isbn
        let url = URL(string: "\(baseURL)/volumes?q=isbn:\(encoded)")!
        let (data, _) = try await URLSession.shared.data(from: url)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let items = json?["items"] as? [[String: Any]], !items.isEmpty else { return [] }
        return items.compactMap { parseGoogleBook($0) }
    }

    func search(keyword: String) async throws -> [BookMetadataDraft] {
        let encoded = keyword.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? keyword
        let url = URL(string: "\(baseURL)/volumes?q=\(encoded)&maxResults=20")!
        let (data, _) = try await URLSession.shared.data(from: url)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let items = json?["items"] as? [[String: Any]] else { return [] }
        return items.compactMap { parseGoogleBook($0) }
    }

    private func parseGoogleBook(_ item: [String: Any]) -> BookMetadataDraft? {
        guard let volumeInfo = item["volumeInfo"] as? [String: Any] else { return nil }
        let industryIdentifiers = volumeInfo["industryIdentifiers"] as? [[String: Any]] ?? []
        let isbn10 = industryIdentifiers.first(where: { $0["type"] as? String == "ISBN_10" })?["identifier"] as? String
        let isbn13 = industryIdentifiers.first(where: { $0["type"] as? String == "ISBN_13" })?["identifier"] as? String

        let imageLinks = volumeInfo["imageLinks"] as? [String: Any]
        let coverURL: URL? = (imageLinks?["thumbnail"] as? String).flatMap { URL(string: $0) }

        return BookMetadataDraft(
            title: (volumeInfo["title"] as? String)?.nilIfEmpty,
            subtitle: (volumeInfo["subtitle"] as? String)?.nilIfEmpty,
            authors: volumeInfo["authors"] as? [String],
            translators: nil,
            isbn10: isbn10,
            isbn13: isbn13,
            publisher: (volumeInfo["publisher"] as? String)?.nilIfEmpty,
            publishedDate: (volumeInfo["publishedDate"] as? String)?.nilIfEmpty,
            pageCount: volumeInfo["pageCount"] as? Int,
            price: nil,
            edition: nil,
            series: nil,
            binding: nil,
            language: volumeInfo["language"] as? String,
            category: (volumeInfo["categories"] as? [String])?.first,
            summary: (volumeInfo["description"] as? String)?.nilIfEmpty,
            coverURL: coverURL,
            dataSource: "googlebooks",
            rawJSON: nil
        )
    }
}
