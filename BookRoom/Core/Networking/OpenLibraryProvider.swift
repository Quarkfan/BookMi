import Foundation

/// Open Library API provider (free, no API key needed)
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

        guard let bookData = json?[key] as? [String: Any] else {
            return [] // Not found, not an error
        }

        let draft = BookMetadataDraft(
            title: (bookData["title"] as? String)?.nilIfEmpty,
            subtitle: nil,
            authors: parseOpenLibraryContributors(bookData["authors"] as? [[String: Any]]),
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

        guard let docs = json?["docs"] as? [[String: Any]] else {
            return []
        }

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

    // MARK: - Helpers

    private func parseOpenLibraryContributors(_ contributors: [[String: Any]]?) -> [String]? {
        contributors?.compactMap { $0["name"] as? String }.filter { !$0.isEmpty }
    }

    private func parseISBNFromKey(_ key: String, length: Int) -> String? {
        let cleaned = key.replacingOccurrences(of: "ISBN:", with: "")
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: " ", with: "")
        return cleaned.count == length ? cleaned : nil
    }

    private func parseCoverURL(_ bookData: [String: Any], isbn: String) -> URL? {
        // Try identify, then cover API
        if let identifies = bookData["identifiers"] as? [String: Any],
           let goodreads = identifies["goodreads"] as? [[String: Any]],
           let id = goodreads.first?["value"] as? String {
            return URL(string: "https://images-na.ssl-images-amazon.com/images/I/\(id).jpg")
        }
        // Fallback to covers API
        return URL(string: "\(baseURL)/covers/isbn/\(isbn)-M.jpg")
    }
}
