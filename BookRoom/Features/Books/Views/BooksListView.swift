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
                    Button {
                        showFilterSheet = true
                    } label: {
                        Label("筛选", systemImage: "line.3.horizontal.decrease.circle")
                    }
                    .badge(activeFilterCount)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    displayModeToggle
                }
            }
            .onChange(of: searchText) { _, _ in searchBooks() }
            .task { await loadBooks() }
            .sheet(isPresented: $showFilterSheet) {
                FilterSheetView(
                    selectedShelfID: $filterShelfID,
                    selectedTagID: $filterTagID,
                    selectedReadingStatus: $filterReadingStatus,
                    onApply: { applyFilters() }
                )
            }
        }
    }

    // MARK: - Book List

    private var bookList: some View {
        Group {
            switch displayMode {
            case .list:
                List {
                    ForEach(books, id: \.id) { book in
                        NavigationLink(destination: BookDetailView(book: book)) {
                            BookRowView(book: book)
                        }
                    }
                }
                .listStyle(.plain)
            case .grid:
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 12)], spacing: 12) {
                        ForEach(books, id: \.id) { book in
                            NavigationLink(destination: BookDetailView(book: book)) {
                                BookCoverView(book: book)
                            }
                        }
                    }
                    .padding()
                }
            }
        }
        .overlay(alignment: .bottomTrailing) {
            // Book count badge
            Text("\(books.count) 本")
                .font(.caption2)
                .padding(8)
                .background(Color.secondary.opacity(0.8))
                .foregroundStyle(.white)
                .clipShape(Capsule())
                .padding()
        }
    }

    // MARK: - States

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "books.vertical")
                .font(.system(size: 64))
                .foregroundStyle(.secondary)
            Text("还没有藏书")
                .font(.headline)
                .foregroundStyle(.secondary)
            Text("点击底部「录入」添加第一本书")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var noResultsState: some View {
        VStack(spacing: 16) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("没有找到匹配的图书")
                .font(.headline)
                .foregroundStyle(.secondary)
            if hasActiveFilters || !searchText.isEmpty {
                Button("清除筛选") {
                    clearFilters()
                }
            }
        }
    }

    // MARK: - Display Mode Toggle

    private var displayModeToggle: some View {
        Picker("显示模式", selection: $displayMode) {
            Image(systemName: "list.bullet").tag(DisplayMode.list)
            Image(systemName: "square.grid.2x2").tag(DisplayMode.grid)
        }
        .pickerStyle(.menu)
        .onChange(of: displayMode) { _, newValue in
            AppContainer.shared.settings.displayMode = newValue
        }
    }

    // MARK: - Filters

    private var hasActiveFilters: Bool {
        filterShelfID != nil || filterTagID != nil || filterReadingStatus != nil
    }

    private var activeFilterCount: Int {
        [filterShelfID, filterTagID, filterReadingStatus?.rawValue].compactMap { $0 }.count
    }

    private func applyFilters() {
        searchBooks()
    }

    private func clearFilters() {
        filterShelfID = nil
        filterTagID = nil
        filterReadingStatus = nil
        searchText = ""
        Task { await loadBooks() }
    }

    // MARK: - Data Loading

    @MainActor
    private func loadBooks() async {
        isLoading = true
        defer { isLoading = false }

        do {
            var query = try appContainer.bookRepo.fetchAll()
            books = sortBooks(query)
        } catch {
            print("Failed to load books: \(error)")
        }
    }

    private func searchBooks() {
        guard !searchText.isEmpty else {
            Task { await loadBooks() }
            return
        }

        Task {
            do {
                let results = try appContainer.searchRepo.searchWithLike(keyword: searchText)
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
                let entryA = Pinyin.analyze(a.title)
                let entryB = Pinyin.analyze(b.title)
                return entryA.full < entryB.full ? order == 1 : order == -1
            case .firstLetter:
                let entryA = Pinyin.analyze(a.title)
                let entryB = Pinyin.analyze(b.title)
                return entryA.initials < entryB.initials ? order == 1 : order == -1
            case .createdAt:
                return a.createdAt < b.createdAt ? order == 1 : order == -1
            case .updatedAt:
                return a.updatedAt < b.updatedAt ? order == 1 : order == -1
            }
        }
    }
}

// MARK: - Filter Sheet

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
                    Button("全部") {
                        selectedShelfID = nil
                    }
                    .foregroundColor(selectedShelfID == nil ? .accentColor : .primary)

                    ForEach(shelves, id: \.id) { shelf in
                        Button(shelf.name) {
                            selectedShelfID = shelf.id
                        }
                        .foregroundColor(selectedShelfID == shelf.id ? .accentColor : .primary)
                    }
                }

                Section("标签") {
                    Button("全部") {
                        selectedTagID = nil
                    }
                    .foregroundColor(selectedTagID == nil ? .accentColor : .primary)

                    ForEach(tags, id: \.id) { tag in
                        Button(tag.name) {
                            selectedTagID = tag.id
                        }
                        .foregroundColor(selectedTagID == tag.id ? .accentColor : .primary)
                    }
                }

                Section("阅读状态") {
                    Button("全部") {
                        selectedReadingStatus = nil
                    }
                    .foregroundColor(selectedReadingStatus == nil ? .accentColor : .primary)

                    ForEach(ReadingStatus.allCases, id: \.self) { status in
                        Button(status.displayName) {
                            selectedReadingStatus = status
                        }
                        .foregroundColor(selectedReadingStatus == status ? .accentColor : .primary)
                    }
                }
            }
            .navigationTitle("筛选")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("应用") {
                        onApply()
                        dismiss()
                    }
                }
            }
            .task {
                do {
                    shelves = try appContainer.shelfRepo.fetchAll()
                    tags = try appContainer.tagRepo.fetchAll()
                } catch {
                    print("Failed to load shelves/tags: \(error)")
                }
            }
        }
    }
}

#Preview {
    BooksListView()
        .environmentObject(AppContainer.shared)
}
