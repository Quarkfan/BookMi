import SwiftUI

/// Book entry form - used after scanning, searching, or for manual entry
struct BookEntryForm: View {
    let initialData: BookMetadataDraft?
    let onSave: (BookMetadataDraft) -> Void
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var appContainer: AppContainer

    @State private var title = ""
    @State private var authors = ""
    @State private var publisher = ""
    @State private var publishedDate = ""
    @State private var isbn = ""
    @State private var pageCount = ""
    @State private var price = ""
    @State private var summary = ""

    @State private var selectedShelfID: String?
    @State private var selectedTags: [String] = []
    @State private var selectedChannelID: String?

    @State private var isSaving = false
    @State private var showError = false
    @State private var errorMessage = ""

    init(initialData: BookMetadataDraft? = nil, onSave: @escaping (BookMetadataDraft) -> Void) {
        self.initialData = initialData
        self.onSave = onSave
    }

    var body: some View {
        NavigationView {
            Form {
                // Basic Info
                Section("基本信息") {
                    TextField("书名 *", text: $title)
                    TextField("作者（多人用 / 分隔）", text: $authors)
                    TextField("出版社", text: $publisher)
                    TextField("出版日期", text: $publishedDate)
                    TextField("ISBN", text: $isbn)
                        .keyboardType(.numbersAndPunctuation)
                    TextField("页数", text: $pageCount)
                        .keyboardType(.numberPad)
                    TextField("定价", text: $price)
                        .keyboardType(.numbersAndPunctuation)
                }

                // Management Info
                Section("管理信息") {
                    // Shelf picker
                    NavigationLink("书柜") {
                        ShelfSelectionView(selectedShelfID: $selectedShelfID)
                    }

                    // Tag picker
                    NavigationLink("标签") {
                        TagSelectionView(selectedTagIDs: $selectedTags)
                    }

                    // Purchase channel
                    NavigationLink("购买渠道") {
                        ChannelSelectionView(selectedChannelID: $selectedChannelID)
                    }
                }

                // Summary
                Section("简介") {
                    TextEditor(text: $summary)
                        .frame(minHeight: 100)
                }

                // Save button
                Section {
                    Button(isSaving ? "保存中..." : "保存") {
                        saveBook()
                    }
                    .disabled(title.isEmpty || isSaving)
                }
            }
            .navigationTitle(initialData != nil ? "确认图书信息" : "手动录入")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("取消") { dismiss() }
                }
            }
            .onAppear {
                populateFromDraft()
            }
        }
    }

    // MARK: - Data Population

    private func populateFromDraft() {
        guard let draft = initialData else { return }

        title = draft.title ?? ""
        authors = (draft.authors ?? []).joined(separator: " / ")
        publisher = draft.publisher ?? ""
        publishedDate = draft.publishedDate ?? ""
        isbn = draft.isbn13 ?? draft.isbn10 ?? ""
        pageCount = draft.pageCount.map { String($0) } ?? ""
        price = draft.price ?? ""
        summary = draft.summary ?? ""

        // Apply default shelf and tags from settings
        selectedShelfID = appContainer.settings.defaultShelfID
        selectedTags = appContainer.settings.defaultTagIDs
        selectedChannelID = appContainer.settings.defaultPurchaseChannelID
    }

    // MARK: - Save

    private func saveBook() {
        isSaving = true

        let draft = BookMetadataDraft(
            title: title.nilIfEmpty,
            subtitle: nil,
            authors: authors.components(separatedBy: "/").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty },
            translators: nil,
            isbn10: isbn.count == 10 ? isbn : nil,
            isbn13: isbn.count == 13 ? isbn : nil,
            publisher: publisher.nilIfEmpty,
            publishedDate: publishedDate.nilIfEmpty,
            pageCount: Int(pageCount),
            price: price.nilIfEmpty,
            edition: nil,
            series: nil,
            binding: nil,
            language: nil,
            category: nil,
            summary: summary.nilIfEmpty,
            coverURL: initialData?.coverURL,
            dataSource: initialData?.dataSource ?? "manual",
            rawJSON: initialData?.rawJSON
        )

        onSave(draft)
        isSaving = false
    }
}

// MARK: - Shelf Selection View

struct ShelfSelectionView: View {
    @Binding var selectedShelfID: String?
    @EnvironmentObject var appContainer: AppContainer
    @State private var shelves: [(shelf: Shelf, bookCount: Int)] = []
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            Section {
                Button("未分类") {
                    selectedShelfID = nil
                    dismiss()
                }
                .foregroundColor(selectedShelfID == nil ? .accentColor : .primary)

                ForEach(shelves, id: \.shelf.id) { item in
                    Button(item.shelf.name) {
                        selectedShelfID = item.shelf.id
                        dismiss()
                    }
                    .foregroundColor(selectedShelfID == item.shelf.id ? .accentColor : .primary)
                }
            }
        }
        .navigationTitle("选择书柜")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            do {
                shelves = try await appContainer.shelfRepo.fetchAllWithBookCounts()
            } catch {
                print("Failed to fetch shelves: \(error)")
            }
        }
    }
}

// MARK: - Tag Selection View

struct TagSelectionView: View {
    @Binding var selectedTagIDs: [String]
    @EnvironmentObject var appContainer: AppContainer
    @State private var tags: [Tag] = []
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            ForEach(tags, id: \.id) { tag in
                Button(tag.name) {
                    if let index = selectedTagIDs.firstIndex(of: tag.id) {
                        selectedTagIDs.remove(at: index)
                    } else {
                        selectedTagIDs.append(tag.id)
                    }
                }
                .foregroundColor(selectedTagIDs.contains(tag.id) ? .accentColor : .primary)
            }
        }
        .navigationTitle("选择标签")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("完成") { dismiss() }
            }
        }
        .task {
            do {
                tags = try await appContainer.tagRepo.fetchAll()
            } catch {
                print("Failed to fetch tags: \(error)")
            }
        }
    }
}

// MARK: - Channel Selection View

struct ChannelSelectionView: View {
    @Binding var selectedChannelID: String?
    @EnvironmentObject var appContainer: AppContainer
    @State private var channels: [PurchaseChannel] = []
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            Section {
                Button("未设置") {
                    selectedChannelID = nil
                    dismiss()
                }
                .foregroundColor(selectedChannelID == nil ? .accentColor : .primary)

                ForEach(channels, id: \.id) { channel in
                    Button(channel.name) {
                        selectedChannelID = channel.id
                        dismiss()
                    }
                    .foregroundColor(selectedChannelID == channel.id ? .accentColor : .primary)
                }
            }
        }
        .navigationTitle("选择购买渠道")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            do {
                channels = try await appContainer.databaseManager.dbQueue.read { (db: Database) in
                    try PurchaseChannel.fetchAll(db)
                }
            } catch {
                print("Failed to fetch channels: \(error)")
            }
        }
    }
}

#Preview {
    BookEntryForm(onSave: { _ in })
        .environmentObject(AppContainer.shared)
}
