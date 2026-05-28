import Foundation

/// Convert BookMetadataDraft to Book entity for database storage
extension Book {
    init(from draft: BookMetadataDraft, shelfID: String? = nil, tags: [String] = [], purchaseChannelID: String? = nil) {
        let now = ISO8601DateFormatter().string(from: Date())

        self.id = UUID().uuidString
        self.legacyID = nil
        self.title = draft.title ?? "未知书名"
        self.subtitle = draft.subtitle
        self.originalTitle = nil
        self.authorsJSON = encodeArray(draft.authors)
        self.translatorsJSON = encodeArray(draft.translators)
        self.isbn10 = draft.isbn10
        self.isbn13 = draft.isbn13
        self.publisher = draft.publisher
        self.publishedDate = draft.publishedDate
        self.pageCount = draft.pageCount
        self.price = draft.price
        self.edition = draft.edition
        self.printing = nil
        self.series = draft.series
        self.binding = draft.binding
        self.language = draft.language
        self.category = draft.category
        self.summary = draft.summary
        self.coverFileName = nil
        self.coverURL = draft.coverURL?.absoluteString
        self.coverHash = nil
        self.shelfID = shelfID
        self.locationDetail = nil
        self.purchaseChannelID = purchaseChannelID
        self.purchaseDate = nil
        self.purchasePrice = nil
        self.readingStatus = .unread
        self.readingProgressType = nil
        self.currentPage = nil
        self.progressPercent = nil
        self.startedAt = nil
        self.finishedAt = nil
        self.borrowStatus = .available
        self.note = nil
        self.dataSource = draft.dataSource
        self.sourceRawData = draft.rawJSON
        self.duplicateGroupID = nil
        self.copyIndex = 1
        self.isFavorite = false
        self.customSortKey = nil
        self.createdAt = now
        self.updatedAt = now
        self.deletedAt = nil
    }

    /// Download and save cover image for this book
    func downloadCover() async throws {
        guard let url = URL(string: coverURL ?? ""),
              let fileName = coverFileName else { return }

        let (data, response) = try await URLSession.shared.data(from: url)
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else { return }

        let destination = AppPaths.coversURL.appendingPathComponent(fileName)
        try data.write(to: destination, options: .atomic)
    }
}

/// Download cover for a BookMetadataDraft and return local file name
extension BookMetadataDraft {
    func downloadCover(forBookID bookID: String) async -> String? {
        guard let coverURL else { return nil }

        do {
            let (data, response) = try await URLSession.shared.data(from: coverURL)
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else { return nil }

            let fileName = "\(bookID).jpg"
            let destination = AppPaths.coversURL.appendingPathComponent(fileName)
            try data.write(to: destination, options: .atomic)
            return fileName
        } catch {
            print("Failed to download cover: \(error)")
            return nil
        }
    }
}

private func encodeArray(_ arr: [String]?) -> String? {
    guard let arr, !arr.isEmpty else { return nil }
    return try? String(data: JSONEncoder().encode(arr), encoding: .utf8)
}
