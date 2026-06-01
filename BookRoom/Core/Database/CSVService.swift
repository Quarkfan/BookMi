import Foundation
import GRDB

/// CSV import/export service
final class CSVService {

    // MARK: - Export

    /// Export books to CSV with selected fields
    static func exportBooks(
        books: [Book],
        fields: [CSVField],
        shelfRepo: ShelfRepository?,
        tagRepo: TagRepository?,
        dbQueue: DatabaseQueue?
    ) async throws -> URL {

        // Build header
        let header = fields.map { $0.header }

        // Build rows
        var rows: [[String]] = []
        for book in books {
            var row: [String] = []
            for field in fields {
                row.append(try await field.value(from: book, shelfRepo: shelfRepo, tagRepo: tagRepo, dbQueue: dbQueue))
            }
            rows.append(row)
        }

        // Write CSV file
        let fileURL = AppPaths.exportsURL.appendingPathComponent("books_export_\(dateString()).csv")
        var content = header.joined(separator: ",") + "\n"
        for row in rows {
            content += row.map(encodeCSVCell).joined(separator: ",") + "\n"
        }
        try content.write(to: fileURL, atomically: true, encoding: .utf8)
        return fileURL
    }

    // MARK: - Import

    /// Import books from CSV with field mapping
    static func importBooks(
        csvURL: URL,
        fieldMapping: [String: CSVField],
        defaultShelfID: String?,
        defaultTagIDs: [String],
        defaultPurchaseChannelID: String?,
        duplicateStrategy: DuplicateStrategy,
        bookRepo: BookRepository,
        tagRepo: TagRepository,
        searchRepo: SearchRepository
    ) async throws -> ImportReport {
        let content = try String(contentsOf: csvURL, encoding: .utf8)
        let lines = content.split(omittingEmptySubsequences: true) { $0.isNewline }.map(String.init)
        guard lines.count > 1 else {
            throw CSVError.emptyFile
        }

        // Parse header
        let headerLine = lines[0]
        let headers = parseCSVLine(headerLine)

        // Build column index mapping
        let columnMapping: [Int: CSVField] = [:]
        var fieldIndexMap: [Int: CSVField] = [:]
        for (i, header) in headers.enumerated() {
            if let field = fieldMapping[header.trimmingCharacters(in: .whitespaces)] {
                fieldIndexMap[i] = field
            }
        }

        var report = ImportReport(totalRows: lines.count - 1)

        // Parse data rows
        for rowLine in lines.dropFirst() {
            let cells = parseCSVLine(rowLine)

            // Build draft from cells
            var draft = BookMetadataDraft()
            for (colIndex, cell) in cells.enumerated() {
                guard let field = fieldIndexMap[colIndex], !cell.isEmpty else { continue }
                field.apply(&draft, value: cell.trimmingCharacters(in: .whitespaces))
            }

            guard draft.hasContent else {
                report.skipped += 1
                continue
            }

            // Check duplicates
            let existing = try await checkDuplicate(
                draft: draft,
                strategy: duplicateStrategy,
                bookRepo: bookRepo
            )

            switch existing {
            case .skip:
                report.skipped += 1
            case .overwrite(let book):
                var updated = book
                applyDraftToBook(&updated, draft: draft, shelfID: defaultShelfID, tagIDs: defaultTagIDs, channelID: defaultPurchaseChannelID)
                try await bookRepo.update(updated)
                try await searchRepo.updateIndex(for: updated)
                report.updated += 1
            case .createNew:
                var book = Book(from: draft, shelfID: defaultShelfID, purchaseChannelID: defaultPurchaseChannelID)
                book = try await bookRepo.insert(book)

                // Add default tags
                if !defaultTagIDs.isEmpty {
                    try await tagRepo.addTags(tagIDs: defaultTagIDs, toBooks: [book.id])
                }

                // Download cover
                if draft.coverURL != nil {
                    let fileName = await draft.downloadCover(forBookID: book.id)
                    var updated = book
                    updated.coverFileName = fileName
                    try await bookRepo.update(updated)
                }

                try await searchRepo.updateIndex(for: book)
                report.created += 1
            }
        }

        return report
    }

    // MARK: - Helpers

    private static func checkDuplicate(
        draft: BookMetadataDraft,
        strategy: DuplicateStrategy,
        bookRepo: BookRepository
    ) async throws -> DuplicateAction {
        let isbn = draft.isbn13 ?? draft.isbn10
        guard let isbn else {
            // No ISBN, check by title + author
            if let title = draft.title,
               let authors = draft.authors,
               !title.isEmpty, !authors.isEmpty {
                // Simplified: search by title
                let existing = try await bookRepo.fetchAll().first { book in
                    book.title == title
                }
                if let existing {
                    switch strategy {
                    case .skip: return .skip
                    case .overwrite: return .overwrite(existing)
                    case .fillEmptyOnly: return .overwrite(existing)
                    case .createNewCopy: return .createNew
                    }
                }
            }
            return .createNew
        }

        // Check by ISBN
        let existing = try await bookRepo.fetch(byISBN: isbn).first
        guard let existing else { return .createNew }

        switch strategy {
        case .skip: return .skip
        case .overwrite: return .overwrite(existing)
        case .fillEmptyOnly: return .overwrite(existing)
        case .createNewCopy: return .createNew
        }
    }

    private static func applyDraftToBook(
        _ book: inout Book,
        draft: BookMetadataDraft,
        shelfID: String?,
        tagIDs: [String],
        channelID: String?
    ) {
        // Only fill empty fields for fillEmptyOnly strategy
        if book.title.isEmpty { book.title = draft.title ?? "未知书名" }
        if book.authorsJSON == nil { book.authorsJSON = encodeArray(draft.authors) }
        if book.publisher == nil { book.publisher = draft.publisher }
        if book.publishedDate == nil { book.publishedDate = draft.publishedDate }
        if book.pageCount == nil { book.pageCount = draft.pageCount }
        if book.price == nil { book.price = draft.price }
        if book.summary == nil { book.summary = draft.summary }
        if book.coverURL == nil { book.coverURL = draft.coverURL?.absoluteString }
        if book.shelfID == nil { book.shelfID = shelfID }
        if book.purchaseChannelID == nil { book.purchaseChannelID = channelID }
    }

    private static func encodeArray(_ arr: [String]?) -> String? {
        guard let arr, !arr.isEmpty else { return nil }
        return try? String(data: JSONEncoder().encode(arr), encoding: .utf8)
    }

    private static func parseCSVLine(_ line: String) -> [String] {
        var cells: [String] = []
        var current = ""
        var inQuotes = false

        for char in line {
            switch char {
            case "\"":
                inQuotes.toggle()
            case "," where !inQuotes:
                cells.append(current)
                current = ""
            default:
                current.append(char)
            }
        }
        cells.append(current)
        return cells
    }

    private static func encodeCSVCell(_ value: String) -> String {
        if value.contains(",") || value.contains("\"") || value.contains("\n") {
            return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return value
    }

    private static func dateString() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        return formatter.string(from: Date())
    }
}

// MARK: - CSV Field Definition

enum CSVField: String, CaseIterable {
    case title
    case subtitle
    case authors
    case translators
    case isbn10
    case isbn13
    case publisher
    case publishedDate
    case pageCount
    case price
    case edition
    case series
    case binding
    case language
    case category
    case summary
    case shelf
    case locationDetail
    case tags
    case purchaseChannel
    case purchaseDate
    case purchasePrice
    case readingStatus
    case currentPage
    case progressPercent
    case note
    case createdAt
    case updatedAt

    var header: String {
        switch self {
        case .title: return "书名"
        case .subtitle: return "副标题"
        case .authors: return "作者"
        case .translators: return "译者"
        case .isbn10: return "ISBN-10"
        case .isbn13: return "ISBN-13"
        case .publisher: return "出版社"
        case .publishedDate: return "出版日期"
        case .pageCount: return "页数"
        case .price: return "定价"
        case .edition: return "版次"
        case .series: return "丛书"
        case .binding: return "装帧"
        case .language: return "语言"
        case .category: return "分类"
        case .summary: return "简介"
        case .shelf: return "书柜"
        case .locationDetail: return "详细位置"
        case .tags: return "标签"
        case .purchaseChannel: return "购买渠道"
        case .purchaseDate: return "购买日期"
        case .purchasePrice: return "购买价格"
        case .readingStatus: return "阅读状态"
        case .currentPage: return "当前页码"
        case .progressPercent: return "阅读进度"
        case .note: return "备注"
        case .createdAt: return "添加时间"
        case .updatedAt: return "编辑时间"
        }
    }

    func value(from book: Book, shelfRepo: ShelfRepository?, tagRepo: TagRepository?, dbQueue: DatabaseQueue?) async throws -> String {
        switch self {
        case .title: return book.title
        case .subtitle: return book.subtitle ?? ""
        case .authors: return decodeArray(book.authorsJSON).joined(separator: " / ")
        case .translators: return decodeArray(book.translatorsJSON).joined(separator: " / ")
        case .isbn10: return book.isbn10 ?? ""
        case .isbn13: return book.isbn13 ?? ""
        case .publisher: return book.publisher ?? ""
        case .publishedDate: return book.publishedDate ?? ""
        case .pageCount: return book.pageCount.map { String($0) } ?? ""
        case .price: return book.price ?? ""
        case .edition: return book.edition ?? ""
        case .series: return book.series ?? ""
        case .binding: return book.binding ?? ""
        case .language: return book.language ?? ""
        case .category: return book.category ?? ""
        case .summary: return book.summary ?? ""
        case .shelf:
            if let shelfID = book.shelfID, let shelfRepo {
                if let shelf = try? await shelfRepo.fetch(byID: shelfID) {
                    return shelf.name
                }
            }
            return ""
        case .locationDetail: return book.locationDetail ?? ""
        case .tags:
            if let tagRepo {
                let tags = try? await tagRepo.fetchTags(forBookID: book.id)
                return (tags ?? []).map { $0.name }.joined(separator: ", ")
            }
            return ""
        case .purchaseChannel:
            if let channelID = book.purchaseChannelID, let dbQueue {
                if let channel = try? await dbQueue.read({ (db: Database) in try PurchaseChannel.fetchOne(db, key: channelID) }) {
                    return channel.name
                }
            }
            return ""
        case .purchaseDate: return book.purchaseDate ?? ""
        case .purchasePrice: return book.purchasePrice ?? ""
        case .readingStatus: return book.readingStatus.displayName
        case .currentPage: return book.currentPage.map { String($0) } ?? ""
        case .progressPercent: return book.progressPercent.map { String(Int($0)) + "%" } ?? ""
        case .note: return book.note ?? ""
        case .createdAt: return formatDate(book.createdAt)
        case .updatedAt: return formatDate(book.updatedAt)
        }
    }

    func apply(_ draft: inout BookMetadataDraft, value: String) {
        guard !value.isEmpty else { return }
        switch self {
        case .title: draft.title = value
        case .subtitle: draft.subtitle = value
        case .authors: draft.authors = value.components(separatedBy: "/").map { $0.trimmingCharacters(in: .whitespaces) }
        case .translators: draft.translators = value.components(separatedBy: "/").map { $0.trimmingCharacters(in: .whitespaces) }
        case .isbn10: draft.isbn10 = value
        case .isbn13: draft.isbn13 = value
        case .publisher: draft.publisher = value
        case .publishedDate: draft.publishedDate = value
        case .pageCount: draft.pageCount = Int(value)
        case .price: draft.price = value
        case .edition: draft.edition = value
        case .series: draft.series = value
        case .binding: draft.binding = value
        case .language: draft.language = value
        case .category: draft.category = value
        case .summary: draft.summary = value
        default: break
        }
    }

    private func decodeArray(_ json: String?) -> [String] {
        guard let json, let data = json.data(using: .utf8),
              let arr = try? JSONDecoder().decode([String].self, from: data) else {
            return []
        }
        return arr
    }

    private func formatDate(_ dateStr: String) -> String {
        let formatter = ISO8601DateFormatter()
        guard let date = formatter.date(from: dateStr) else { return dateStr }
        let display = DateFormatter()
        display.dateFormat = "yyyy-MM-dd"
        return display.string(from: date)
    }
}

// MARK: - Duplicate Strategy

enum DuplicateStrategy {
    case skip
    case overwrite
    case fillEmptyOnly
    case createNewCopy
}

enum DuplicateAction {
    case skip
    case overwrite(Book)
    case createNew
}

// MARK: - Import Report

struct ImportReport {
    let totalRows: Int
    var created = 0
    var updated = 0
    var skipped = 0
    var failed = 0

    var summary: String {
        "总计 \(totalRows) 行，新增 \(created)，更新 \(updated)，跳过 \(skipped)，失败 \(failed)"
    }
}

// MARK: - CSV Errors

enum CSVError: Error, LocalizedError {
    case emptyFile
    case invalidEncoding
    case fileNotFound

    var errorDescription: String? {
        switch self {
        case .emptyFile: return "CSV 文件为空或只有表头"
        case .invalidEncoding: return "文件编码不支持，请使用 UTF-8 编码"
        case .fileNotFound: return "找不到文件"
        }
    }
}
