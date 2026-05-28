import Foundation

/// Pinyin utility for converting Chinese characters to pinyin.
/// Uses iOS built-in CFStringTransform (no external dependency needed).
enum Pinyin {

    /// Convert Chinese text to full pinyin (lowercase, no spaces)
    /// e.g. "数据结构" -> "shujujiegou"
    static func toFullPinyin(_ text: String) -> String {
        let mutable = NSMutableString(string: text)
        CFStringTransform(mutable, nil, kCFStringTransformToLatin, false)
        CFStringTransform(mutable, nil, kCFStringTransformStripDiacritics, false)

        // Result is "shù jù jié gòu" -> strip spaces and lowercase
        let transformed = mutable as String
        return transformed
            .lowercased()
            .components(separatedBy: .whitespaces)
            .joined()
    }

    /// Get pinyin initials (first letter of each syllable)
    /// e.g. "数据结构" -> "sjjg"
    static func toInitials(_ text: String) -> String {
        analyze(text).initials
    }

    /// Generate both full pinyin and initials in one pass
    /// Returns (fullPinyinWithoutSpaces, initials)
    static func analyze(_ text: String) -> (full: String, initials: String) {
        let mutable = NSMutableString(string: text)
        CFStringTransform(mutable, nil, kCFStringTransformToLatin, false)
        CFStringTransform(mutable, nil, kCFStringTransformStripDiacritics, false)

        let withSpaces = (mutable as String).lowercased()
        let full = withSpaces.replacingOccurrences(of: " ", with: "")
        let initials = withSpaces
            .components(separatedBy: .whitespaces)
            .compactMap { $0.first }
            .map { String($0) }
            .joined()

        return (full, initials)
    }
}

/// Search index entry for a book
struct SearchIndexEntry {
    let bookID: String
    let normalizedTitle: String
    let normalizedAuthors: String
    let normalizedTranslators: String
    let normalizedPublisher: String
    let normalizedISBN: String
    let normalizedTags: String
    let normalizedShelf: String
    let normalizedLocation: String
    let normalizedPurchaseChannel: String
    let pinyinTitleFull: String
    let pinyinTitleInitials: String
    let pinyinAuthorsFull: String
    let pinyinAuthorsInitials: String
    let combinedSearchText: String
}

extension SearchIndexEntry {
    /// Build a search index entry from book metadata
    static func from(
        title: String?,
        authors: [String]?,
        translators: [String]?,
        publisher: String?,
        isbn: String?,
        tags: [String]?,
        shelf: String?,
        location: String?,
        purchaseChannel: String?,
        bookID: String
    ) -> SearchIndexEntry {
        let title = title ?? ""
        let titlePinyin = Pinyin.analyze(title)

        let authorText = (authors ?? []).joined(separator: " ")
        let authorPinyin = Pinyin.analyze(authorText)

        let combined = [
            title,
            authorText,
            (translators ?? []).joined(separator: " "),
            publisher ?? "",
            isbn ?? "",
            (tags ?? []).joined(separator: " "),
            shelf ?? "",
            location ?? "",
            purchaseChannel ?? ""
        ].joined(separator: " ").lowercased()

        return SearchIndexEntry(
            bookID: bookID,
            normalizedTitle: normalize(title),
            normalizedAuthors: normalize(authorText),
            normalizedTranslators: normalize((translators ?? []).joined(separator: " ")),
            normalizedPublisher: normalize(publisher ?? ""),
            normalizedISBN: normalizeISBN(isbn ?? ""),
            normalizedTags: ((tags ?? []).joined(separator: " ")).lowercased(),
            normalizedShelf: (shelf ?? "").lowercased(),
            normalizedLocation: (location ?? "").lowercased(),
            normalizedPurchaseChannel: (purchaseChannel ?? "").lowercased(),
            pinyinTitleFull: titlePinyin.full,
            pinyinTitleInitials: titlePinyin.initials,
            pinyinAuthorsFull: authorPinyin.full,
            pinyinAuthorsInitials: authorPinyin.initials,
            combinedSearchText: combined
        )
    }

    private static func normalize(_ text: String) -> String {
        text
            .lowercased()
            .folding(options: .diacriticInsensitive, locale: .current)
            .components(separatedBy: .whitespaces)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private static func normalizeISBN(_ isbn: String) -> String {
        isbn.replacingOccurrences(of: "-", with: "").replacingOccurrences(of: " ", with: "")
    }
}
