import Foundation

/// Google Books API provider (free, optional API key)
struct GoogleBooksProvider: BookLookupProvider {
    let name = "Google Books"

    private let baseURL = "https://www.googleapis.com/books/v1"

    func lookup(isbn: String) async throws -> [BookMetadataDraft] {
        let encoded = isbn.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? isbn
        let url = URL(string: "\(baseURL)/volumes?q=isbn:\(encoded)")!

        let (data, _) = try await URLSession.shared.data(from: url)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        guard let items = json?["items"] as? [[String: Any]], !items.isEmpty else {
            return []
        }

        return items.compactMap { parseGoogleBook($0) }
    }

    func search(keyword: String) async throws -> [BookMetadataDraft] {
        let encoded = keyword.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? keyword
        let url = URL(string: "\(baseURL)/volumes?q=\(encoded)&maxResults=20")!

        let (data, _) = try await URLSession.shared.data(from: url)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        guard let items = json?["items"] as? [[String: Any]] else {
            return []
        }

        return items.compactMap { parseGoogleBook($0) }
    }

    // MARK: - Helpers

    private func parseGoogleBook(_ item: [String: Any]) -> BookMetadataDraft? {
        guard let volumeInfo = item["volumeInfo"] as? [String: Any] else { return nil }

        let industryIdentifiers = volumeInfo["industryIdentifiers"] as? [[String: Any]] ?? []
        let isbn10 = industryIdentifiers.first(where: { $0["type"] as? String == "ISBN_10" })?["identifier"] as? String
        let isbn13 = industryIdentifiers.first(where: { $0["type"] as? String == "ISBN_13" })?["identifier"] as? String

        let imageLinks = volumeInfo["imageLinks"] as? [String: Any]
        let coverURL: URL? = (imageLinks?["thumbnail"] as? String)
            .map { $0.replacingOccurrences(of: "http://", with: "https://") }
            .flatMap { URL(string: $0) }

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

extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
