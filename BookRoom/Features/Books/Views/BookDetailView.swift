import SwiftUI

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

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                // Cover
                bookCoverSection

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
                        InfoGroup(label: "定价", value: book.price.map { "¥\($0)" })
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
                        InfoGroup(label: "购买价格", value: book.purchasePrice.map { "¥\($0)" })
                        InfoGroup(label: "数据来源", value: book.dataSource)
                    }

                    Divider()

                    // Reading Info
                    Section("阅读信息") {
                        ReadingStatusControl(book: $book)

                        if book.readingStatus == .reading || book.readingStatus == .paused {
                            ReadingProgressControl(book: book)
                        }

                        InfoGroup(label: "开始阅读", value: book.startedAt.map { formatDate($0) })
                        InfoGroup(label: "完成阅读", value: book.finishedAt.map { formatDate($0) })
                    }

                    Divider()

                    // Borrow Info
                    Section("借出信息") {
                        if book.borrowStatus == .borrowed {
                            if let record = borrowRecord {
                                InfoGroup(label: "借阅人", value: record.borrowerName)
                                InfoGroup(label: "联系方式", value: record.contact)
                                InfoGroup(label: "借出时间", value: formatDate(record.borrowedAt))
                                InfoGroup(label: "预计归还", value: record.expectedReturnAt.map { formatDate($0) })
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
        do {
            // Load shelf
            if let shelfID = book.shelfID {
                shelf = try await appContainer.shelfRepo.fetch(byID: shelfID)
            }

            // Load tags
            tags = try await appContainer.tagRepo.fetchTags(forBookID: book.id)

            // Load purchase channel
            if let channelID = book.purchaseChannelID {
                purchaseChannel = try await appContainer.databaseManager.dbQueue.read { (db: Database) in
                    try PurchaseChannel.fetchOne(db, key: channelID)
                }
            }

            // Load active borrow record
            borrowRecord = try await appContainer.databaseManager.dbQueue.read { (db: Database) in
                try BorrowRecord
                    .filter(Column("book_id") == book.id)
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

    // MARK: - Helpers

    private func decodeAuthors(_ json: String?) -> [String]? {
        guard let json, let data = json.data(using: .utf8),
              let arr = try? JSONDecoder().decode([String].self, from: data) else {
            return nil
        }
        return arr
    }

    private func formatDate(_ dateStr: String) -> String? {
        let formatter = ISO8601DateFormatter()
        guard let date = formatter.date(from: dateStr) else { return dateStr }
        let display = DateFormatter()
        display.dateFormat = "yyyy-MM-dd"
        return display.string(from: date)
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
                    try? await appContainer.bookRepo.update(updated)
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
