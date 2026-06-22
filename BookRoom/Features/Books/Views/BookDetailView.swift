import SwiftUI
import GRDB
import PhotosUI
import UIKit
import CryptoKit
import WebKit

struct BookDetailView: View {
    @State private var book: Book
    @EnvironmentObject var appContainer: AppContainer
    @Environment(\.dismiss) private var dismiss

    init(book: Book) {
        _book = State(initialValue: book)
    }

    @State private var shelf: Shelf?
    @State private var tags: [Tag] = []
    @State private var purchaseChannel: PurchaseChannel?
    @State private var borrowRecord: BorrowRecord?
    @State private var showEditForm = false
    @State private var showCoverEditor = false
    @State private var editedTagIDs: [String]?

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                // Cover
                bookCoverSection
                    .id(book.coverHash ?? book.coverFileName ?? "no-cover")
                    .onTapGesture { showCoverEditor = true }

                // Content
                VStack(alignment: .leading, spacing: 16) {
                    // Title
                    Text(book.title)
                        .font(.title2)
                        .fontWeight(.bold)

                    // Authors
                    if let authors = decodeAuthors(book.authorsJSON), !authors.isEmpty {
                        InfoRow(label: "作者", value: authors.joined(separator: " / "))
                    }

                    Divider()

                    // Basic Info
                    Section("基本信息") {
                        InfoGroup(label: "出版社", value: book.publisher)
                        InfoGroup(label: "出版日期", value: book.publishedDate)
                        InfoGroup(label: "页数", value: book.pageCount.map { "\($0) 页" })
                        InfoGroup(label: "ISBN", value: book.isbn13 ?? book.isbn10)
                        InfoGroup(label: "装帧", value: book.binding)
                        InfoGroup(label: "定价", value: book.price.flatMap { (s: String) in "¥\(s)" } ?? "")
                        InfoGroup(label: "版次", value: book.edition)
                        InfoGroup(label: "丛书", value: book.series)
                        InfoGroup(label: "语言", value: book.language)
                        InfoGroup(label: "分类", value: book.category)
                    }

                    Divider()

                    // Management Info
                    Section("管理信息") {
                        InfoGroup(label: "书柜", value: shelf?.name)
                        InfoGroup(label: "详细位置", value: book.locationDetail)
                        InfoGroup(label: "标签", value: tags.map { $0.name }.joined(separator: ", "))
                        InfoGroup(label: "购买渠道", value: purchaseChannel?.name)
                        InfoGroup(label: "购买日期", value: book.purchaseDate)
                        InfoGroup(label: "购买价格", value: book.purchasePrice.flatMap { (s: String) in "¥\(s)" } ?? "")
                        InfoGroup(label: "数据来源", value: book.dataSource)
                    }

                    Divider()

                    // Reading Info
                    Section("阅读信息") {
                        ReadingStatusControl(book: $book)

                        if book.readingStatus == .reading || book.readingStatus == .paused {
                            ReadingProgressControl(book: book)
                        }

                        InfoGroup(label: "开始阅读", value: book.startedAt.flatMap { (s: String) in formatDate(s) } ?? "")
                        InfoGroup(label: "完成阅读", value: book.finishedAt.flatMap { (s: String) in formatDate(s) } ?? "")
                    }

                    Divider()

                    // Borrow Info
                    Section("借出信息") {
                        if book.borrowStatus == .borrowed {
                            if let record = borrowRecord {
                                InfoGroup(label: "借阅人", value: record.borrowerName)
                                InfoGroup(label: "联系方式", value: record.contact)
                                InfoGroup(label: "借出时间", value: formatDate(record.borrowedAt))
                                InfoGroup(label: "预计归还", value: record.expectedReturnAt.flatMap { (s: String) in formatDate(s) } ?? "")
                            }
                        } else {
                            Text("当前未借出")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Divider()

                    // Summary
                    if let summary = book.summary, !summary.isEmpty {
                        Section("简介") {
                            Text(summary)
                                .font(.body)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Divider()

                    // Note
                    if let note = book.note, !note.isEmpty {
                        Section("备注") {
                            Text(note)
                                .font(.body)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Divider()

                    // Timestamps
                    Section("数据信息") {
                        InfoGroup(label: "添加时间", value: formatDate(book.createdAt))
                        InfoGroup(label: "编辑时间", value: formatDate(book.updatedAt))
                        if book.legacyID != nil {
                            InfoGroup(label: "旧系统 ID", value: book.legacyID)
                        }
                    }

                    // Spacer
                    Color.clear.frame(height: 100)
                }
                .padding()
            }
        }
        .navigationTitle("图书详情")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button("返回") { dismiss() }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu("操作") {
                    Button { showEditForm = true } label: {
                        Label("编辑", systemImage: "pencil")
                    }
                    Button { showCoverEditor = true } label: {
                        Label("更新封面", systemImage: "photo.badge.plus")
                    }
                    Button(role: .destructive) {
                        deleteBook()
                    } label: {
                        Label("删除", systemImage: "trash")
                    }
                }
            }
        }
        .task {
            await loadRelatedData()
        }
        .sheet(isPresented: $showEditForm) {
            BookEntryForm(
                initialData: editDraft,
                mode: .edit,
                initialShelfID: book.shelfID,
                initialTagIDs: tags.map(\.id),
                initialChannelID: book.purchaseChannelID,
                onSaveManagement: { shelfID, tagIDs, channelID in
                    updateBookManagement(shelfID: shelfID, tagIDs: tagIDs, channelID: channelID)
                },
                onSave: { draft in updateBook(with: draft) }
            )
        }
        .sheet(isPresented: $showCoverEditor) {
            CoverEditorSheet(book: book) { image in
                await saveCover(image)
            }
        }
    }

    // MARK: - Cover Section

    private var bookCoverSection: some View {
        ZStack {
            Rectangle()
                .fill(Color.gray.opacity(0.1))
                .frame(height: 300)

            if let fileName = book.coverFileName {
                AsyncImage(url: AppPaths.coversURL.appendingPathComponent(fileName)) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxHeight: 300)
                } placeholder: {
                    coverPlaceholder
                }
            } else if let coverURL = URL(string: book.coverURL ?? "") {
                AsyncImage(url: coverURL) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxHeight: 300)
                } placeholder: {
                    coverPlaceholder
                }
            } else {
                coverPlaceholder
            }
        }
        .overlay(alignment: .bottomTrailing) {
            Label("更新封面", systemImage: "camera.fill")
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(.ultraThinMaterial, in: Capsule())
                .padding(12)
        }
    }

    private var coverPlaceholder: some View {
        VStack(spacing: 8) {
            Image(systemName: "book.fill")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text(book.title)
                .font(.headline)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 300)
        .background(Color.gray.opacity(0.1))
    }

    // MARK: - Data Loading

    @MainActor
    private func loadRelatedData() async {
        let bookID = book.id
        let purchaseChannelID = book.purchaseChannelID
        let shelfID = book.shelfID
        do {
            // Load shelf
            if let shelfID {
                shelf = try await appContainer.shelfRepo.fetch(byID: shelfID)
            }

            // Load tags
            tags = try await appContainer.tagRepo.fetchTags(forBookID: bookID)

            // Load purchase channel
            if let channelID = purchaseChannelID {
                purchaseChannel = try await appContainer.databaseManager.dbQueue.read { (db: Database) in
                    try PurchaseChannel.fetchOne(db, key: channelID)
                }
            }

            // Load active borrow record
            borrowRecord = try await appContainer.databaseManager.dbQueue.read { (db: Database) in
                try BorrowRecord
                    .filter(Column("book_id") == bookID)
                    .filter(Column("status") == "borrowed")
                    .fetchOne(db)
            }
        } catch {
            print("Failed to load related data: \(error)")
        }
    }

    // MARK: - Delete

    private func deleteBook() {
        Task {
            do {
                try await appContainer.bookRepo.softDelete(id: book.id)
                dismiss()
            } catch {
                print("Failed to delete book: \(error)")
            }
        }
    }

    @MainActor
    private func saveCover(_ image: UIImage) async -> Bool {
        guard let data = image.jpegData(compressionQuality: 0.82) else { return false }
        do {
            try appContainer.fileStorage.saveCover(data, for: book.id)
            var updated = book
            updated.coverFileName = "\(book.id).jpg"
            updated.coverURL = "manual:cover-editor"
            updated.coverHash = Insecure.MD5.hash(data: data).map { String(format: "%02hhx", $0) }.joined()
            book = try await appContainer.bookRepo.update(updated)
            return true
        } catch {
            print("Failed to save cover: \(error)")
            return false
        }
    }

    private var editDraft: BookMetadataDraft {
        BookMetadataDraft(
            title: book.title,
            subtitle: book.subtitle,
            authors: decodeAuthors(book.authorsJSON),
            translators: decodeAuthors(book.translatorsJSON),
            isbn10: book.isbn10,
            isbn13: book.isbn13,
            publisher: book.publisher,
            publishedDate: book.publishedDate,
            pageCount: book.pageCount,
            price: book.price,
            edition: book.edition,
            series: book.series,
            binding: book.binding,
            language: book.language,
            category: book.category,
            summary: book.summary,
            coverURL: book.coverURL.flatMap(URL.init(string:)),
            dataSource: book.dataSource,
            rawJSON: book.sourceRawData
        )
    }

    private func updateBook(with draft: BookMetadataDraft) {
        Task {
            do {
                var updated = book
                updated.title = draft.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? book.title
                updated.subtitle = draft.subtitle
                updated.authorsJSON = encodeNames(draft.authors)
                updated.translatorsJSON = encodeNames(draft.translators)
                updated.isbn10 = draft.isbn10
                updated.isbn13 = draft.isbn13
                updated.publisher = draft.publisher
                updated.publishedDate = draft.publishedDate
                updated.pageCount = draft.pageCount
                updated.price = draft.price
                updated.edition = draft.edition
                updated.series = draft.series
                updated.binding = draft.binding
                updated.language = draft.language
                updated.category = draft.category
                updated.summary = draft.summary
                book = try await appContainer.bookRepo.update(updated)
                if let editedTagIDs {
                    try await appContainer.tagRepo.setTags(tagIDs: editedTagIDs, forBook: book.id)
                    self.editedTagIDs = nil
                }
                showEditForm = false
                await loadRelatedData()
            } catch {
                print("Failed to update book: \(error)")
            }
        }
    }

    private func updateBookManagement(shelfID: String?, tagIDs: [String], channelID: String?) {
        book.shelfID = shelfID
        book.purchaseChannelID = channelID
        editedTagIDs = tagIDs
    }

    // MARK: - Helpers

    private func decodeAuthors(_ json: String?) -> [String]? {
        guard let json, let data = json.data(using: .utf8),
              let arr = try? JSONDecoder().decode([String].self, from: data) else {
            return nil
        }
        return arr
    }

    private func encodeNames(_ names: [String]?) -> String? {
        guard let names, !names.isEmpty,
              let data = try? JSONEncoder().encode(names) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func formatDate(_ dateStr: String) -> String? {
        let formatter = ISO8601DateFormatter()
        guard let date = formatter.date(from: dateStr) else { return dateStr }
        let display = DateFormatter()
        display.dateFormat = "yyyy-MM-dd"
        return display.string(from: date)
    }
}

// MARK: - Cover Editor

struct CoverEditorSheet: View {
    let book: Book
    let onSave: (UIImage) async -> Bool

    @Environment(\.dismiss) private var dismiss
    @State private var photoItem: PhotosPickerItem?
    @State private var sourceImage: UIImage?
    @State private var showCamera = false
    @State private var showAutoMatch = false
    @State private var showBaiduBrowser = false
    @State private var showCropper = false
    @State private var isSaving = false
    @State private var errorMessage: String?

    private var baiduURL: URL? {
        var components = URLComponents(string: "https://image.baidu.com/search/index")
        components?.queryItems = [
            URLQueryItem(name: "tn", value: "baiduimage"),
            URLQueryItem(name: "word", value: "\(book.title) 图书封面")
        ]
        return components?.url
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(book.title)
                            .font(.title3.bold())
                        Text("拍照或选择图片后，会进入裁剪和压缩页面。")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    CoverSourceButton(
                        title: "拍摄封面",
                        subtitle: "直接拍摄实体书，随后裁剪",
                        icon: "camera.fill",
                        tint: .orange
                    ) {
                        showCamera = true
                    }

                    PhotosPicker(selection: $photoItem, matching: .images) {
                        CoverSourceLabel(
                            title: "从相册选择",
                            subtitle: "支持截图、下载图片和已有照片",
                            icon: "photo.on.rectangle.angled",
                            tint: .blue
                        )
                    }
                    .buttonStyle(.plain)

                    CoverSourceButton(
                        title: "自动匹配封面",
                        subtitle: "从微信读书等渠道查找候选封面",
                        icon: "sparkles.rectangle.stack",
                        tint: .teal
                    ) {
                        showAutoMatch = true
                    }

                    CoverSourceButton(
                        title: "百度图片搜索",
                        subtitle: "应用内搜索，长按图片直接用作封面",
                        icon: "magnifyingglass",
                        tint: .green
                    ) {
                        showBaiduBrowser = true
                    }

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }
                .padding()
            }
            .navigationTitle("更新封面")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
            }
            .onChange(of: photoItem) { _, newItem in
                guard let newItem else { return }
                Task {
                    do {
                        guard let data = try await newItem.loadTransferable(type: Data.self),
                              let image = UIImage(data: data) else {
                            throw CoverEditorError.invalidImage
                        }
                        sourceImage = image.normalizedOrientation()
                        showCropper = true
                    } catch {
                        errorMessage = "无法读取这张图片，请换一张重试。"
                    }
                }
            }
            .fullScreenCover(isPresented: $showCamera) {
                CameraImagePicker { image in
                    sourceImage = image.normalizedOrientation()
                    showCamera = false
                    showCropper = true
                }
                .ignoresSafeArea()
            }
            .fullScreenCover(isPresented: $showAutoMatch) {
                CoverAutoMatchFlow(book: book, onSave: onSave) {
                    showAutoMatch = false
                    dismiss()
                }
            }
            .fullScreenCover(isPresented: $showBaiduBrowser) {
                if let baiduURL {
                    CoverImageBrowser(url: baiduURL, onSave: onSave) {
                        showBaiduBrowser = false
                        dismiss()
                    }
                }
            }
            .fullScreenCover(isPresented: $showCropper) {
                if let sourceImage {
                    CoverCropView(image: sourceImage, isSaving: isSaving) { cropped in
                        isSaving = true
                        Task {
                            let success = await onSave(cropped)
                            await MainActor.run {
                                isSaving = false
                                if success {
                                    showCropper = false
                                    dismiss()
                                } else {
                                    errorMessage = "封面保存失败，请重试。"
                                }
                            }
                        }
                    } onCancel: {
                        showCropper = false
                    }
                }
            }
        }
    }
}

private struct CoverAutoMatchFlow: View {
    let book: Book
    let onSave: (UIImage) async -> Bool
    let onSaved: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var candidates: [CoverMatchCandidate] = []
    @State private var cropImage: UIImage?
    @State private var isLoading = true
    @State private var isDownloading = false
    @State private var isSaving = false
    @State private var errorMessage: String?

    var body: some View {
        ZStack {
            if let cropImage {
                CoverCropView(image: cropImage, isSaving: isSaving) { cropped in
                    isSaving = true
                    Task {
                        let success = await onSave(cropped)
                        await MainActor.run {
                            isSaving = false
                            if success {
                                onSaved()
                            } else {
                                errorMessage = "封面保存失败，请重试。"
                            }
                        }
                    }
                } onCancel: {
                    self.cropImage = nil
                }
            } else {
                NavigationStack {
                    Group {
                        if isLoading {
                            ProgressView("正在匹配封面…")
                        } else if candidates.isEmpty {
                            ContentUnavailableView(
                                "没有找到合适的封面",
                                systemImage: "books.vertical",
                                description: Text("可以返回后使用百度图片、拍照或相册。")
                            )
                        } else {
                            ScrollView {
                                LazyVGrid(columns: [GridItem(.adaptive(minimum: 145), spacing: 16)], spacing: 18) {
                                    ForEach(candidates) { candidate in
                                        Button {
                                            download(candidate)
                                        } label: {
                                            VStack(alignment: .leading, spacing: 8) {
                                                AsyncImage(url: candidate.imageURL) { image in
                                                    image.resizable().scaledToFit()
                                                } placeholder: {
                                                    ProgressView()
                                                }
                                                .frame(maxWidth: .infinity)
                                                .frame(height: 210)
                                                .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))

                                                Text(candidate.title)
                                                    .font(.subheadline.weight(.semibold))
                                                    .lineLimit(2)
                                                Text(candidate.sourceName)
                                                    .font(.caption)
                                                    .foregroundStyle(.secondary)
                                            }
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                                .padding()
                            }
                        }
                    }
                    .navigationTitle("自动匹配封面")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("关闭") { dismiss() }
                        }
                    }
                }
            }
        }
        .overlay {
            if isDownloading {
                ZStack {
                    Color.black.opacity(0.28).ignoresSafeArea()
                    ProgressView("正在获取封面…")
                        .padding(22)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                }
            }
        }
        .alert("自动匹配失败", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("好", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
        .task {
            do {
                candidates = try await CoverMatchService().search(book: book)
            } catch {
                errorMessage = "暂时无法获取候选封面，请稍后重试。"
            }
            isLoading = false
        }
    }

    private func download(_ candidate: CoverMatchCandidate) {
        isDownloading = true
        Task {
            do {
                var request = URLRequest(url: candidate.imageURL)
                request.setValue(candidate.referer, forHTTPHeaderField: "Referer")
                request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 Mobile/15E148", forHTTPHeaderField: "User-Agent")
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let http = response as? HTTPURLResponse,
                      (200..<300).contains(http.statusCode),
                      let image = UIImage(data: data) else {
                    throw CoverEditorError.invalidImage
                }
                await MainActor.run {
                    isDownloading = false
                    cropImage = image.normalizedOrientation()
                }
            } catch {
                await MainActor.run {
                    isDownloading = false
                    errorMessage = "无法获取这张封面，请选择其他候选。"
                }
            }
        }
    }
}

private struct CoverMatchCandidate: Identifiable {
    let id: String
    let title: String
    let author: String?
    let imageURL: URL
    let sourceName: String
    let referer: String
}

private protocol CoverMatchProvider {
    func search(book: Book) async throws -> [CoverMatchCandidate]
}

private struct CoverMatchService {
    private let providers: [any CoverMatchProvider] = [WeReadCoverMatchProvider()]

    func search(book: Book) async throws -> [CoverMatchCandidate] {
        var results: [CoverMatchCandidate] = []
        for provider in providers {
            if Task.isCancelled { break }
            results.append(contentsOf: try await provider.search(book: book))
        }
        return Array(Dictionary(grouping: results, by: \.imageURL.absoluteString).compactMap(\.value.first))
    }
}

private struct WeReadCoverMatchProvider: CoverMatchProvider {
    func search(book: Book) async throws -> [CoverMatchCandidate] {
        var components = URLComponents(string: "https://weread.qq.com/web/search/books")
        components?.queryItems = [URLQueryItem(name: "keyword", value: book.title)]
        guard let url = components?.url else { return [] }
        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 Mobile/15E148 BookRoom/1.0", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode),
              let page = String(data: data, encoding: .utf8) else {
            throw CoverEditorError.invalidImage
        }

        return captures(page, #"<li class="wr_bookList_item"[^>]*>(.*?)</li>"#).prefix(12).compactMap { chunk in
            guard let title = clean(first(chunk, #"wr_bookList_item_title[^>]*>(.*?)</p>"#)),
                  let imageText = first(chunk, #"<img[^>]+src="([^"]+)"[^>]*alt="书籍封面""#),
                  let imageURL = normalizedURL(imageText) else { return nil }
            let author = clean(first(chunk, #"wr_bookList_item_author[^>]*>(.*?)</p>"#))
            return CoverMatchCandidate(
                id: imageURL.absoluteString,
                title: author.map { "\(title) · \($0)" } ?? title,
                author: author,
                imageURL: imageURL,
                sourceName: "微信读书",
                referer: "https://weread.qq.com/"
            )
        }
    }

    private func captures(_ value: String, _ pattern: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators, .caseInsensitive]) else { return [] }
        return regex.matches(in: value, range: NSRange(value.startIndex..., in: value)).compactMap {
            guard $0.numberOfRanges > 1, let range = Range($0.range(at: 1), in: value) else { return nil }
            return String(value[range])
        }
    }

    private func first(_ value: String, _ pattern: String) -> String? {
        captures(value, pattern).first
    }

    private func clean(_ value: String?) -> String? {
        value?
            .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfEmpty
    }

    private func normalizedURL(_ value: String) -> URL? {
        let decoded = value.replacingOccurrences(of: "&amp;", with: "&")
        if decoded.hasPrefix("//") { return URL(string: "https:\(decoded)") }
        return URL(string: decoded)
    }
}

private struct CoverImageBrowser: View {
    let url: URL
    let onSave: (UIImage) async -> Bool
    let onSaved: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selectedImageURL: URL?
    @State private var cropImage: UIImage?
    @State private var isDownloading = false
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var canGoBack = false
    @State private var reloadToken = 0
    @State private var goBackToken = 0

    var body: some View {
        ZStack {
            if let cropImage {
                CoverCropView(image: cropImage, isSaving: isSaving) { cropped in
                    isSaving = true
                    Task {
                        let success = await onSave(cropped)
                        await MainActor.run {
                            isSaving = false
                            if success {
                                onSaved()
                            } else {
                                errorMessage = "封面保存失败，请重试。"
                            }
                        }
                    }
                } onCancel: {
                    self.cropImage = nil
                }
            } else {
                browserContent
            }
        }
        .overlay {
            if isDownloading {
                ZStack {
                    Color.black.opacity(0.28).ignoresSafeArea()
                    ProgressView("正在获取图片…")
                        .padding(22)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                }
            }
        }
        .confirmationDialog("使用这张图片作为封面？", isPresented: Binding(
            get: { selectedImageURL != nil },
            set: { if !$0 { selectedImageURL = nil } }
        )) {
            Button("使用并裁剪") {
                guard let selectedImageURL else { return }
                downloadImage(from: selectedImageURL)
            }
            Button("取消", role: .cancel) { selectedImageURL = nil }
        } message: {
            Text("图片会直接进入裁剪页面，不会保存到系统相册。")
        }
        .alert("无法使用图片", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("好", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var browserContent: some View {
        VStack(spacing: 0) {
            HStack(spacing: 16) {
                Button { goBackToken += 1 } label: {
                    Image(systemName: "chevron.left")
                }
                .disabled(!canGoBack)

                VStack(alignment: .leading, spacing: 2) {
                    Text("选择封面")
                        .font(.headline)
                    Text("长按图片，然后选择用作封面")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button { reloadToken += 1 } label: {
                    Image(systemName: "arrow.clockwise")
                }
                Button("关闭") { dismiss() }
            }
            .padding(.horizontal)
            .frame(height: 58)
            .background(.bar)

            BaiduImageWebView(
                url: url,
                selectedImageURL: $selectedImageURL,
                canGoBack: $canGoBack,
                reloadToken: reloadToken,
                goBackToken: goBackToken
            )
            .ignoresSafeArea(edges: .bottom)
        }
    }

    private func downloadImage(from url: URL) {
        selectedImageURL = nil
        isDownloading = true
        Task {
            do {
                var request = URLRequest(url: url)
                request.setValue("https://image.baidu.com/", forHTTPHeaderField: "Referer")
                request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 Mobile/15E148", forHTTPHeaderField: "User-Agent")
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let http = response as? HTTPURLResponse,
                      (200..<300).contains(http.statusCode),
                      let image = UIImage(data: data) else {
                    throw CoverEditorError.invalidImage
                }
                await MainActor.run {
                    isDownloading = false
                    cropImage = image.normalizedOrientation()
                }
            } catch {
                await MainActor.run {
                    isDownloading = false
                    errorMessage = "图片获取失败，请换一张图片重试。"
                }
            }
        }
    }
}

private struct BaiduImageWebView: UIViewRepresentable {
    let url: URL
    @Binding var selectedImageURL: URL?
    @Binding var canGoBack: Bool
    let reloadToken: Int
    let goBackToken: Int

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> WKWebView {
        let controller = WKUserContentController()
        controller.add(context.coordinator, name: "coverImage")
        controller.addUserScript(WKUserScript(
            source: Self.longPressScript,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: false
        ))
        let configuration = WKWebViewConfiguration()
        configuration.userContentController = controller
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        let longPress = UILongPressGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleLongPress(_:))
        )
        longPress.minimumPressDuration = 0.55
        longPress.delegate = context.coordinator
        webView.addGestureRecognizer(longPress)
        context.coordinator.webView = webView
        webView.load(URLRequest(url: url))
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        if reloadToken != context.coordinator.lastReloadToken {
            context.coordinator.lastReloadToken = reloadToken
            webView.reload()
        }
        if goBackToken != context.coordinator.lastGoBackToken {
            context.coordinator.lastGoBackToken = goBackToken
            if webView.canGoBack { webView.goBack() }
        }
    }

    static func dismantleUIView(_ webView: WKWebView, coordinator: Coordinator) {
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "coverImage")
    }

    final class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate, WKUIDelegate, UIGestureRecognizerDelegate {
        var parent: BaiduImageWebView
        weak var webView: WKWebView?
        var lastReloadToken = 0
        var lastGoBackToken = 0

        init(_ parent: BaiduImageWebView) {
            self.parent = parent
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.name == "coverImage",
                  let value = message.body as? String,
                  let url = URL(string: value),
                  ["http", "https"].contains(url.scheme?.lowercased() ?? "") else { return }
            DispatchQueue.main.async {
                self.parent.selectedImageURL = url
            }
        }

        @objc func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
            guard gesture.state == .began, let webView else { return }
            let point = gesture.location(in: webView)
            let script = Self.imageURLScript(x: point.x, y: point.y)
            webView.evaluateJavaScript(script) { [weak self] result, _ in
                guard let self,
                      let value = result as? String,
                      let url = URL(string: value),
                      ["http", "https"].contains(url.scheme?.lowercased() ?? "") else { return }
                DispatchQueue.main.async {
                    self.parent.selectedImageURL = url
                }
            }
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            true
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation?) {
            DispatchQueue.main.async {
                self.parent.canGoBack = webView.canGoBack
            }
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            // Baidu image previews commonly use target="_blank". Keep them inside our browser.
            if navigationAction.targetFrame == nil, let requestURL = navigationAction.request.url {
                webView.load(URLRequest(url: requestURL))
                decisionHandler(.cancel)
                return
            }
            decisionHandler(.allow)
        }

        func webView(
            _ webView: WKWebView,
            createWebViewWith configuration: WKWebViewConfiguration,
            for navigationAction: WKNavigationAction,
            windowFeatures: WKWindowFeatures
        ) -> WKWebView? {
            if let requestURL = navigationAction.request.url {
                webView.load(URLRequest(url: requestURL))
            }
            return nil
        }

        func webViewDidClose(_ webView: WKWebView) {
            if webView.canGoBack { webView.goBack() }
        }

        func webView(
            _ webView: WKWebView,
            contextMenuConfigurationForElement elementInfo: WKContextMenuElementInfo,
            completionHandler: @escaping (UIContextMenuConfiguration?) -> Void
        ) {
            completionHandler(nil)
        }

        private static func imageURLScript(x: CGFloat, y: CGFloat) -> String {
            """
            (() => {
              let node = document.elementFromPoint(\(x), \(y));
              for (let i = 0; node && i < 8; i++, node = node.parentElement) {
                if (node.tagName === 'IMG') {
                  const candidates = [
                    node.getAttribute('data-original'),
                    node.getAttribute('data-src'),
                    node.getAttribute('data-imgurl'),
                    node.getAttribute('data-objurl'),
                    node.currentSrc,
                    node.src
                  ];
                  const found = candidates.find(value => value && /^https?:\\/\\//i.test(value));
                  if (found) return found;
                }
                for (const attr of ['data-imgurl', 'data-objurl', 'data-original', 'data-src']) {
                  const value = node.getAttribute && node.getAttribute(attr);
                  if (value && /^https?:\\/\\//i.test(value)) return value;
                }
                const bg = getComputedStyle(node).backgroundImage;
                const match = bg && bg.match(/url\\(["']?(.*?)["']?\\)/);
                if (match && /^https?:\\/\\//i.test(match[1])) return match[1];
              }
              return null;
            })();
            """
        }
    }

    private static let longPressScript = """
    (() => {
      if (window.__bookRoomCoverPickerInstalled) return;
      window.__bookRoomCoverPickerInstalled = true;
      const imageURL = (element) => {
        let node = element;
        for (let i = 0; node && i < 5; i++, node = node.parentElement) {
          if (node.tagName === 'IMG') return node.currentSrc || node.src;
          const bg = getComputedStyle(node).backgroundImage;
          const match = bg && bg.match(/url\\(["']?(.*?)["']?\\)/);
          if (match && match[1]) return match[1];
        }
        return null;
      };
      document.addEventListener('contextmenu', event => {
        const url = imageURL(event.target);
        if (!url) return;
        event.preventDefault();
        window.webkit.messageHandlers.coverImage.postMessage(url);
      }, true);
    })();
    """
}

private struct CoverSourceButton: View {
    let title: String
    let subtitle: String
    let icon: String
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            CoverSourceLabel(title: title, subtitle: subtitle, icon: icon, tint: tint)
        }
        .buttonStyle(.plain)
    }
}

private struct CoverSourceLabel: View {
    let title: String
    let subtitle: String
    let icon: String
    let tint: Color

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(.white)
                .frame(width: 48, height: 48)
                .background(tint.gradient, in: RoundedRectangle(cornerRadius: 14))
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.headline)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .foregroundStyle(.tertiary)
        }
        .padding()
        .background(.background, in: RoundedRectangle(cornerRadius: 18))
        .overlay {
            RoundedRectangle(cornerRadius: 18)
                .stroke(Color.secondary.opacity(0.15))
        }
    }
}

private struct CoverCropView: View {
    let image: UIImage
    let isSaving: Bool
    let onSave: (UIImage) -> Void
    let onCancel: () -> Void

    @State private var cropRect: CGRect = .zero
    @State private var dragStartRect: CGRect?

    var body: some View {
        GeometryReader { proxy in
            let imageFrame = aspectFitFrame(
                imageSize: image.size,
                in: CGRect(x: 18, y: 74, width: proxy.size.width - 36, height: proxy.size.height - 160)
            )

            ZStack {
                Color.black.ignoresSafeArea()

                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(width: imageFrame.width, height: imageFrame.height)
                    .position(x: imageFrame.midX, y: imageFrame.midY)

                cropOverlay(imageFrame: imageFrame)

                VStack {
                    HStack {
                        Button("取消", action: onCancel)
                            .foregroundStyle(.white)
                        Spacer()
                        Text("裁剪封面")
                            .font(.headline)
                            .foregroundStyle(.white)
                        Spacer()
                        Button("保存") {
                            onSave(renderCropped(imageFrame: imageFrame))
                        }
                        .disabled(isSaving || cropRect.isEmpty)
                        .foregroundStyle(.white)
                    }
                    .padding()

                    Spacer()

                    Text("拖动裁剪框调整位置，拖动四角自由调整大小")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.8))
                        .padding(.bottom, 24)
                }
            }
            .onAppear {
                initializeCropRect(in: imageFrame)
            }
            .onChange(of: imageFrame) { _, newFrame in
                initializeCropRect(in: newFrame)
            }
        }
    }

    @ViewBuilder
    private func cropOverlay(imageFrame: CGRect) -> some View {
        if !cropRect.isEmpty {
            Rectangle()
                .fill(.black.opacity(0.52))
                .mask {
                    Path { path in
                        path.addRect(imageFrame)
                        path.addRect(cropRect)
                    }
                    .fill(style: FillStyle(eoFill: true))
                }

            Rectangle()
                .fill(.clear)
                .frame(width: cropRect.width, height: cropRect.height)
                .position(x: cropRect.midX, y: cropRect.midY)
                .contentShape(Rectangle())
                .gesture(moveGesture(in: imageFrame))
                .overlay {
                    Rectangle()
                        .stroke(.white, lineWidth: 2)
                }

            ForEach(CropCorner.allCases, id: \.self) { corner in
                Circle()
                    .fill(.white)
                    .frame(width: 24, height: 24)
                    .overlay(Circle().stroke(.black.opacity(0.35), lineWidth: 1))
                    .position(corner.point(in: cropRect))
                    .gesture(resizeGesture(corner: corner, in: imageFrame))
            }
        }
    }

    private func moveGesture(in bounds: CGRect) -> some Gesture {
        DragGesture()
            .onChanged { value in
                let start = dragStartRect ?? cropRect
                if dragStartRect == nil { dragStartRect = start }
                let proposed = start.offsetBy(dx: value.translation.width, dy: value.translation.height)
                cropRect.origin.x = min(max(proposed.minX, bounds.minX), bounds.maxX - proposed.width)
                cropRect.origin.y = min(max(proposed.minY, bounds.minY), bounds.maxY - proposed.height)
            }
            .onEnded { _ in dragStartRect = nil }
    }

    private func resizeGesture(corner: CropCorner, in bounds: CGRect) -> some Gesture {
        DragGesture()
            .onChanged { value in
                let start = dragStartRect ?? cropRect
                if dragStartRect == nil { dragStartRect = start }
                cropRect = resizedRect(start, corner: corner, translation: value.translation, bounds: bounds)
            }
            .onEnded { _ in dragStartRect = nil }
    }

    private func initializeCropRect(in bounds: CGRect) {
        guard cropRect.isEmpty, bounds.width > 0, bounds.height > 0 else { return }
        cropRect = bounds.insetBy(dx: bounds.width * 0.1, dy: bounds.height * 0.1)
    }

    private func resizedRect(
        _ rect: CGRect,
        corner: CropCorner,
        translation: CGSize,
        bounds: CGRect
    ) -> CGRect {
        let minimum: CGFloat = 72
        var minX = rect.minX
        var maxX = rect.maxX
        var minY = rect.minY
        var maxY = rect.maxY

        if corner.isLeft {
            minX = min(max(rect.minX + translation.width, bounds.minX), maxX - minimum)
        } else {
            maxX = max(min(rect.maxX + translation.width, bounds.maxX), minX + minimum)
        }
        if corner.isTop {
            minY = min(max(rect.minY + translation.height, bounds.minY), maxY - minimum)
        } else {
            maxY = max(min(rect.maxY + translation.height, bounds.maxY), minY + minimum)
        }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    private func aspectFitFrame(imageSize: CGSize, in bounds: CGRect) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0, bounds.width > 0, bounds.height > 0 else {
            return .zero
        }
        let scale = min(bounds.width / imageSize.width, bounds.height / imageSize.height)
        let size = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        return CGRect(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2, width: size.width, height: size.height)
    }

    private func renderCropped(imageFrame: CGRect) -> UIImage {
        let normalized = image.normalizedOrientation()
        let scaleX = normalized.size.width / imageFrame.width
        let scaleY = normalized.size.height / imageFrame.height
        let sourceRect = CGRect(
            x: (cropRect.minX - imageFrame.minX) * scaleX,
            y: (cropRect.minY - imageFrame.minY) * scaleY,
            width: cropRect.width * scaleX,
            height: cropRect.height * scaleY
        ).integral.intersection(CGRect(origin: .zero, size: normalized.size))

        guard let cgImage = normalized.cgImage?.cropping(to: sourceRect) else { return normalized }
        let cropped = UIImage(cgImage: cgImage)
        let maxDimension: CGFloat = 1600
        let resizeScale = min(1, maxDimension / max(cropped.size.width, cropped.size.height))
        guard resizeScale < 1 else { return cropped }
        let outputSize = CGSize(width: cropped.size.width * resizeScale, height: cropped.size.height * resizeScale)
        return UIGraphicsImageRenderer(size: outputSize).image { _ in
            cropped.draw(in: CGRect(origin: .zero, size: outputSize))
        }
    }
}

private enum CropCorner: CaseIterable {
    case topLeft, topRight, bottomLeft, bottomRight

    var isLeft: Bool { self == .topLeft || self == .bottomLeft }
    var isTop: Bool { self == .topLeft || self == .topRight }

    func point(in rect: CGRect) -> CGPoint {
        CGPoint(x: isLeft ? rect.minX : rect.maxX, y: isTop ? rect.minY : rect.maxY)
    }
}

private struct CameraImagePicker: UIViewControllerRepresentable {
    let onImage: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = UIImagePickerController.isSourceTypeAvailable(.camera) ? .camera : .photoLibrary
        picker.cameraCaptureMode = .photo
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        let parent: CameraImagePicker
        init(_ parent: CameraImagePicker) { self.parent = parent }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            guard let image = info[.originalImage] as? UIImage else {
                parent.dismiss()
                return
            }
            parent.onImage(image)
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}

private enum CoverEditorError: Error {
    case invalidImage
}

private extension UIImage {
    func normalizedOrientation() -> UIImage {
        guard imageOrientation != .up else { return self }
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { _ in draw(in: CGRect(origin: .zero, size: size)) }
    }
}

// MARK: - Info Row

struct InfoRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .multilineTextAlignment(.trailing)
        }
    }
}

// MARK: - Info Group

struct InfoGroup: View {
    let label: String
    let value: String?

    var body: some View {
        if let value, !value.isEmpty {
            InfoRow(label: label, value: value)
        }
    }
}

// MARK: - Reading Status Control

struct ReadingStatusControl: View {
    @Binding var book: Book
    @EnvironmentObject var appContainer: AppContainer

    var body: some View {
        HStack {
            Text("阅读状态")
                .foregroundStyle(.secondary)
            Spacer()
            Picker("", selection: $book.readingStatus) {
                ForEach(ReadingStatus.allCases, id: \.self) { status in
                    Text(status.displayName).tag(status)
                }
            }
            .pickerStyle(.menu)
            .onChange(of: book.readingStatus) { _, newStatus in
                Task {
                    var updated = book
                    updated.readingStatus = newStatus
                    if newStatus == .finished {
                        updated.finishedAt = ISO8601DateFormatter().string(from: Date())
                        updated.progressPercent = 100
                    }
                    _ = try? await appContainer.bookRepo.update(updated)
                    book = updated
                }
            }
        }
    }
}

// MARK: - Reading Progress Control

struct ReadingProgressControl: View {
    let book: Book

    var body: some View {
        HStack {
            Text("阅读进度")
                .foregroundStyle(.secondary)
            Spacer()
            if let progress = book.progressPercent {
                Text("\(Int(progress))%")
                    .foregroundStyle(.secondary)
            }
            if let current = book.currentPage, let total = book.pageCount {
                Text("\(current)/\(total) 页")
                    .foregroundStyle(.secondary)
            }
        }
    }
}

#Preview {
    NavigationView {
        BookDetailView(book: previewBook)
            .environmentObject(AppContainer.shared)
    }
}

private var previewBook: Book {
    Book(
        id: "preview",
        legacyID: nil,
        title: "数据结构与算法分析",
        subtitle: nil,
        originalTitle: nil,
        authorsJSON: try? String(data: JSONEncoder().encode(["Mark Allen Weiss"]), encoding: .utf8),
        translatorsJSON: nil,
        isbn10: nil,
        isbn13: "9787111544302",
        publisher: "机械工业出版社",
        publishedDate: "2016-09",
        pageCount: 702,
        price: "119.00",
        edition: nil,
        printing: nil,
        series: nil,
        binding: "平装",
        language: "zh",
        category: "计算机科学",
        summary: "本书是数据结构方面的经典教材，以C++语言描述，深入讲解了各种数据结构及其应用。",
        coverFileName: nil,
        coverURL: nil,
        coverHash: nil,
        shelfID: nil,
        locationDetail: nil,
        purchaseChannelID: nil,
        purchaseDate: nil,
        purchasePrice: nil,
        readingStatus: .reading,
        readingProgressType: nil,
        currentPage: 120,
        progressPercent: 17.0,
        startedAt: nil,
        finishedAt: nil,
        borrowStatus: .available,
        note: nil,
        dataSource: "manual",
        sourceRawData: nil,
        duplicateGroupID: nil,
        copyIndex: 1,
        isFavorite: false,
        customSortKey: nil,
        createdAt: ISO8601DateFormatter().string(from: Date()),
        updatedAt: ISO8601DateFormatter().string(from: Date()),
        deletedAt: nil
    )
}
