import Foundation
import GRDB

// MARK: - Book Model

struct Book: Codable, Identifiable, FetchableRecord, MutablePersistableRecord {
    static let databaseTableName = "books"

    var id: String
    var legacyID: String?
    var title: String
    var subtitle: String?
    var originalTitle: String?
    var authorsJSON: String?
    var translatorsJSON: String?
    var isbn10: String?
    var isbn13: String?
    var publisher: String?
    var publishedDate: String?
    var pageCount: Int?
    var price: String?
    var edition: String?
    var printing: String?
    var series: String?
    var binding: String?
    var language: String?
    var category: String?
    var summary: String?
    var coverFileName: String?
    var coverURL: String?
    var coverHash: String?
    var shelfID: String?
    var locationDetail: String?
    var purchaseChannelID: String?
    var purchaseDate: String?
    var purchasePrice: String?
    var readingStatus: ReadingStatus
    var readingProgressType: String?
    var currentPage: Int?
    var progressPercent: Double?
    var startedAt: String?
    var finishedAt: String?
    var borrowStatus: BorrowStatus
    var note: String?
    var dataSource: String?
    var sourceRawData: String?
    var duplicateGroupID: String?
    var copyIndex: Int
    var isFavorite: Bool
    var customSortKey: String?
    var createdAt: String
    var updatedAt: String
    var deletedAt: String?

    enum CodingKeys: String, CodingKey {
        case id, legacyID = "legacy_id", title, subtitle
        case originalTitle = "original_title"
        case authorsJSON = "authors_json", translatorsJSON = "translators_json"
        case isbn10, isbn13, publisher
        case publishedDate = "published_date"
        case pageCount = "page_count", price, edition, printing, series
        case binding, language, category, summary
        case coverFileName = "cover_file_name"
        case coverURL = "cover_url", coverHash = "cover_hash"
        case shelfID = "shelf_id"
        case locationDetail = "location_detail"
        case purchaseChannelID = "purchase_channel_id"
        case purchaseDate = "purchase_date"
        case purchasePrice = "purchase_price"
        case readingStatus = "reading_status"
        case readingProgressType = "reading_progress_type"
        case currentPage = "current_page"
        case progressPercent = "progress_percent"
        case startedAt = "started_at", finishedAt = "finished_at"
        case borrowStatus = "borrow_status"
        case note
        case dataSource = "data_source"
        case sourceRawData = "source_raw_data"
        case duplicateGroupID = "duplicate_group_id"
        case copyIndex = "copy_index"
        case isFavorite = "is_favorite"
        case customSortKey = "custom_sort_key"
        case createdAt = "created_at", updatedAt = "updated_at"
        case deletedAt = "deleted_at"
    }

    // GRDB column encoding: camelCase property -> snake_case DB column
    static var databaseColumnEncodingStrategy: DatabaseColumnEncodingStrategy {
        .convertToSnakeCase
    }
}

// MARK: - Reading Status

enum ReadingStatus: String, Codable, CaseIterable {
    case unread
    case reading
    case finished
    case paused
    case abandoned

    var displayName: String {
        switch self {
        case .unread: return "未读"
        case .reading: return "在读"
        case .finished: return "已读"
        case .paused: return "暂停"
        case .abandoned: return "放弃"
        }
    }
}

// MARK: - Borrow Status

enum BorrowStatus: String, Codable, CaseIterable {
    case available
    case borrowed

    var displayName: String {
        switch self {
        case .available: return "在馆"
        case .borrowed: return "借出中"
        }
    }
}
