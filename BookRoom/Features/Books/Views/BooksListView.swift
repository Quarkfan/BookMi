import SwiftUI

struct BooksListView: View {
    @EnvironmentObject var appContainer: AppContainer
    @State private var searchText = ""
    @State private var books: [Book] = []
    @State private var isLoading = true
    @State private var displayMode: DisplayMode
    @State private var sortField: SortField
    @State private var sortOrder: SortOrder
    @State private var showFilterSheet = false
    @State private var filterShelfID: String?
    @State private var filterTagID: String?
    @State private var filterReadingStatus: ReadingStatus?
    @State private var selectedBooks: Set<String> = []
    @State private var isEditing = false
    @State private var showBatchActions = false

    init() {
        _displayMode = State(initialValue: AppContainer.shared.settings.displayMode)
        _sortField = State(initialValue: AppContainer.shared.settings.sortField)
        _sortOrder = State(initialValue: AppContainer.shared.settings.sortOrder)
    }

    var body: some View {
        NavigationView {
            Group {
                if isLoading {
                    ProgressView("加载中...")
                } else if books.isEmpty && !hasActiveFilters {
                    emptyState
                } else if books.isEmpty {
                    noResultsState
                } else {
                    bookList
                }
            }
            .navigationTitle("藏书")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, prompt: "搜索书名、作者、ISBN...")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    if isEditing {
                        Button("取消") {
                            isEditing = false
                            selectedBooks.removeAll()
                        }
                    } else {
                        Button { showFilterSheet = true } label: {
                            Label("筛选", systemImage: "line.3.horizontal.decrease.circle")
                        }
                        .badge(activeFilterCount)
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    if isEditing {
                        Button("批量操作 (\(selectedBooks.count))") { showBatchActions = true }
                            .disabled(selectedBooks.isEmpty)
                    } else {
                        HStack {
                            Picker("", selection: $displayMode) {
                                Image(systemName: "list.bullet").tag(DisplayMode.list)
                                Image(systemName: "square.grid.2x2").tag(DisplayMode.grid)
                            }
                            .pickerStyle(.menu)
                            .onChange(of: displayMode) { _, newValue in
                                appContainer.settings.displayMode = newValue
                            }
                            Button { isEditing = true } label: { Image(systemName: "checkmark.circle") }
                        }
                    }
                }
            }
            .onChange(of: searchText) { _, _ in searchBooks() }
            .task { await loadBooks() }
            .sheet(isPresented: $showFilterSheet) {
                FilterSheetView(selectedShelfID: $filterShelfID, selectedTagID: $filterTagID,
                    selectedReadingStatus: $filterReadingStatus, onApply: { searchBooks() })
            }
            .sheet(isPresented: $showBatchActions) {
                BatchActionSheet(selectedBookIDs: Array(selectedBooks))
            }
        }
    }

    private var bookList: some View {
        Group {
            switch displayMode {
            case .list:
                List {
                    ForEach(books, id: \.id) { book in
                        if isEditing {
                            Button { toggleSelect(book.id) } label: {
                                HStack {
                                    Image(systemName: selectedBooks.contains(book.id) ? "checkmark.circle.fill" : "circle")
                                        .foregroundColor(selectedBooks.contains(book.id) ? .accentColor : .secondary)
                                    BookRowView(book: book)
                                }
                            }
                        } else {
                            NavigationLink(destination: BookDetailView(book: book)) { BookRowView(book: book) }
                        }
                    }
                }
                .listStyle(.plain)
            case .grid:
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 12)], spacing: 12) {
                        ForEach(books, id: \.id) { book in
                            if isEditing {
                                Button { toggleSelect(book.id) } label: {
                                    ZStack(alignment: .topTrailing) {
                                        BookCoverView(book: book)
                                        Image(systemName: selectedBooks.contains(book.id) ? "checkmark.circle.fill" : "circle")
                                            .foregroundColor(selectedBooks.contains(book.id) ? .accentColor : .white)
                                            .padding(4)
                                    }
                                }
                            } else {
                                NavigationLink(destination: BookDetailView(book: book)) { BookCoverView(book: book) }
                            }
                        }
                    }
                    .padding()
                }
            }
        }
    }

    private func toggleSelect(_ id: String) {
        if selectedBooks.contains(id) { selectedBooks.remove(id) } else { selectedBooks.insert(id) }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "books.vertical").font(.system(size: 64)).foregroundStyle(.secondary)
            Text("还没有藏书").font(.headline).foregroundStyle(.secondary)
            Text("点击底部「录入」添加第一本书").font(.subheadline).foregroundStyle(.secondary)
        }
    }

    private var noResultsState: some View {
        VStack(spacing: 16) {
            Image(systemName: "magnifyingglass").font(.system(size: 48)).foregroundStyle(.secondary)
            Text("没有找到匹配的图书").font(.headline).foregroundStyle(.secondary)
            if hasActiveFilters || !searchText.isEmpty {
                Button("清除筛选") { clearFilters() }
            }
        }
    }

    private var hasActiveFilters: Bool {
        filterShelfID != nil || filterTagID != nil || filterReadingStatus != nil
    }
    private var activeFilterCount: Int {
        [filterShelfID, filterTagID, filterReadingStatus?.rawValue].compactMap { $0 }.count
    }

    private func clearFilters() {
        filterShelfID = nil
        filterTagID = nil
        filterReadingStatus = nil
        searchText = ""
        Task { await loadBooks() }
    }

    @MainActor
    private func loadBooks() async {
        isLoading = true
        defer { isLoading = false }
        do {
            var query = try await appContainer.bookRepo.fetchAll()
            books = sortBooks(query)
        } catch {
            print("Failed to load books: \(error)")
        }
    }

    private func searchBooks() {
        guard !searchText.isEmpty else { Task { await loadBooks() }; return }
        Task {
            do {
                let results = try await appContainer.searchRepo.searchWithLike(keyword: searchText)
                books = sortBooks(results)
            } catch {
                print("Search failed: \(error)")
            }
        }
    }

    private func sortBooks(_ books: [Book]) -> [Book] {
        let order = sortOrder == .ascending ? 1 : -1
        return books.sorted { a, b in
            switch sortField {
            case .pinyin:
                let ea = Pinyin.analyze(a.title)
                let eb = Pinyin.analyze(b.title)
                return ea.full < eb.full ? order == 1 : order == -1
            case .firstLetter:
                let ea = Pinyin.analyze(a.title)
                let eb = Pinyin.analyze(b.title)
                return ea.initials < eb.initials ? order == 1 : order == -1
            case .createdAt: return a.createdAt < b.createdAt ? order == 1 : order == -1
            case .updatedAt: return a.updatedAt < b.updatedAt ? order == 1 : order == -1
            }
        }
    }
}

struct BookRowView: View {
    let book: Book
    var body: some View {
        HStack(spacing: 12) {
            coverImage.frame(width: 50, height: 70).clipShape(RoundedRectangle(cornerRadius: 4))
            VStack(alignment: .leading, spacing: 4) {
                Text(book.title).font(.headline).lineLimit(1)
                if let authors = decodeAuthors(book.authorsJSON), !authors.isEmpty {
                    Text(authors.joined(separator: " / ")).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                }
                if let publisher = book.publisher {
                    Text(publisher).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                HStack(spacing: 8) {
                    ReadingStatusBadge(status: book.readingStatus)
                    if book.borrowStatus == .borrowed {
                        Label("借出", systemImage: "person").font(.caption).foregroundColor(.orange)
                    }
                }
            }
            Spacer()
        }
        .padding(.vertical, 4)
    }
    private var coverImage: some View {
        Group {
            if let fileName = book.coverFileName {
                AsyncImage(url: AppPaths.coversURL.appendingPathComponent(fileName)) { i in i.resizable().aspectRatio(contentMode: .fill) } placeholder: { coverPlaceholder }
            } else { coverPlaceholder }
        }
    }
    private var coverPlaceholder: some View {
        Rectangle().fill(Color.gray.opacity(0.2)).overlay(Image(systemName: "book.fill").foregroundStyle(.secondary))
    }
    private func decodeAuthors(_ json: String?) -> [String]? {
        guard let json, let data = json.data(using: .utf8), let arr = try? JSONDecoder().decode([String].self, from: data) else { return nil }
        return arr
    }
}

struct BookCoverView: View {
    let book: Book
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Group {
                if let fileName = book.coverFileName {
                    AsyncImage(url: AppPaths.coversURL.appendingPathComponent(fileName)) { i in i.resizable().aspectRatio(contentMode: .fill) } placeholder: { coverPlaceholder }
                } else { coverPlaceholder }
            }
            .aspectRatio(0.7, contentMode: .fit).clipShape(RoundedRectangle(cornerRadius: 4))
            Text(book.title).font(.caption).lineLimit(2).foregroundStyle(.primary)
        }
    }
    private var coverPlaceholder: some View {
        Rectangle().fill(Color.gray.opacity(0.2)).overlay(Image(systemName: "book.fill").foregroundStyle(.secondary))
    }
}

struct ReadingStatusBadge: View {
    let status: ReadingStatus
    var body: some View {
        Text(status.displayName).font(.caption2).padding(.horizontal, 6).padding(.vertical, 2)
            .background(statusColor).foregroundStyle(.white).clipShape(Capsule())
    }
    private var statusColor: Color {
        switch status {
        case .unread: return .gray
        case .reading: return .blue
        case .finished: return .green
        case .paused: return .orange
        case .abandoned: return .red
        }
    }
}

struct FilterSheetView: View {
    @Binding var selectedShelfID: String?
    @Binding var selectedTagID: String?
    @Binding var selectedReadingStatus: ReadingStatus?
    let onApply: () -> Void
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var appContainer: AppContainer
    @State private var shelves: [Shelf] = []
    @State private var tags: [Tag] = []

    var body: some View {
        NavigationView {
            Form {
                Section("书柜") {
                    Button("全部") { selectedShelfID = nil }.foregroundColor(selectedShelfID == nil ? .accentColor : .primary)
                    ForEach(shelves, id: \.id) { shelf in
                        Button(shelf.name) { selectedShelfID = shelf.id }.foregroundColor(selectedShelfID == shelf.id ? .accentColor : .primary)
                    }
                }
                Section("标签") {
                    Button("全部") { selectedTagID = nil }.foregroundColor(selectedTagID == nil ? .accentColor : .primary)
                    ForEach(tags, id: \.id) { tag in
                        Button(tag.name) { selectedTagID = tag.id }.foregroundColor(selectedTagID == tag.id ? .accentColor : .primary)
                    }
                }
                Section("阅读状态") {
                    Button("全部") { selectedReadingStatus = nil }.foregroundColor(selectedReadingStatus == nil ? .accentColor : .primary)
                    ForEach(ReadingStatus.allCases, id: \.self) { status in
                        Button(status.displayName) { selectedReadingStatus = status }.foregroundColor(selectedReadingStatus == status ? .accentColor : .primary)
                    }
                }
            }
            .navigationTitle("筛选")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .navigationBarTrailing) { Button("应用") { onApply(); dismiss() } }
            }
            .task {
                do {
                    shelves = try await appContainer.shelfRepo.fetchAll()
                    tags = try await appContainer.tagRepo.fetchAll()
                } catch { print("Failed to load shelves/tags: \(error)") }
            }
        }
    }
}

#Preview {
    BooksListView().environmentObject(AppContainer.shared)
}
