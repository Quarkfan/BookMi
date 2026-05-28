import SwiftUI

struct BooksListView: View {
    @EnvironmentObject var appContainer: AppContainer
    @State private var searchText = ""
    @State private var books: [Book] = []
    @State private var isLoading = false
    @State private var displayMode: DisplayMode = .list

    var body: some View {
        NavigationView {
            Group {
                if isLoading {
                    ProgressView()
                } else if books.isEmpty && searchText.isEmpty {
                    emptyState
                } else {
                    bookList
                }
            }
            .navigationTitle("藏书")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, prompt: "搜索书名、作者、ISBN...")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    displayModeToggle
                }
            }
            .onChange(of: searchText) { _, _ in
                searchBooks()
            }
            .task {
                await loadBooks()
            }
        }
    }

    // MARK: - Book List

    private var bookList: some View {
        Group {
            switch displayMode {
            case .list:
                List(books, id: \.id) { book in
                    NavigationLink(destination: EmptyView()) {
                        BookRowView(book: book)
                    }
                }
            case .grid:
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 12)], spacing: 12) {
                        ForEach(books, id: \.id) { book in
                            BookCoverView(book: book)
                        }
                    }
                    .padding()
                }
            }
        }
    }

    // MARK: - Empty State

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

    // MARK: - Display Mode Toggle

    private var displayModeToggle: some View {
        Picker("显示模式", selection: $displayMode) {
            Label("列表", systemImage: "list.bullet").tag(DisplayMode.list)
            Label("平铺", systemImage: "square.grid.2x2").tag(DisplayMode.grid)
        }
        .pickerStyle(.menu)
    }

    // MARK: - Data Loading

    @MainActor
    private func loadBooks() async {
        isLoading = true
        defer { isLoading = false }

        do {
            books = try appContainer.bookRepo.fetchAll()
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
                books = try appContainer.searchRepo.searchWithLike(keyword: searchText)
            } catch {
                print("Search failed: \(error)")
            }
        }
    }
}

// MARK: - Book Row View

struct BookRowView: View {
    let book: Book

    var body: some View {
        HStack(spacing: 12) {
            // Cover thumbnail
            AsyncImage(url: coverURL) { image in
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } placeholder: {
                Rectangle()
                    .fill(Color.gray.opacity(0.2))
                    .overlay(
                        Image(systemName: "book.fill")
                            .foregroundStyle(.secondary)
                    )
            }
            .frame(width: 50, height: 70)
            .clipShape(RoundedRectangle(cornerRadius: 4))

            // Info
            VStack(alignment: .leading, spacing: 4) {
                Text(book.title)
                    .font(.headline)
                    .lineLimit(1)

                if let authors = decodeAuthors(book.authorsJSON), !authors.isEmpty {
                    Text(authors.joined(separator: " / "))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                if let publisher = book.publisher {
                    Text(publisher)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                HStack(spacing: 8) {
                    ReadingStatusBadge(status: book.readingStatus)
                    if book.borrowStatus == .borrowed {
                        Label("借出", systemImage: "person")
                            .font(.caption)
                            .foregroundColor(.orange)
                    }
                }
            }

            Spacer()
        }
        .padding(.vertical, 4)
    }

    private var coverURL: URL? {
        if let fileName = book.coverFileName {
            return AppPaths.coversURL.appendingPathComponent(fileName)
        }
        return nil
    }

    private func decodeAuthors(_ json: String?) -> [String]? {
        guard let json, let data = json.data(using: .utf8),
              let arr = try? JSONDecoder().decode([String].self, from: data) else {
            return nil
        }
        return arr
    }
}

// MARK: - Book Cover View (Grid Mode)

struct BookCoverView: View {
    let book: Book

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            AsyncImage(url: coverURL) { image in
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } placeholder: {
                Rectangle()
                    .fill(Color.gray.opacity(0.2))
                    .overlay(
                        Image(systemName: "book.fill")
                            .foregroundStyle(.secondary)
                    )
            }
            .aspectRatio(0.7, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 4))

            Text(book.title)
                .font(.caption)
                .lineLimit(2)
                .foregroundStyle(.primary)
        }
    }

    private var coverURL: URL? {
        if let fileName = book.coverFileName {
            return AppPaths.coversURL.appendingPathComponent(fileName)
        }
        return nil
    }
}

// MARK: - Reading Status Badge

struct ReadingStatusBadge: View {
    let status: ReadingStatus

    var body: some View {
        Text(status.displayName)
            .font(.caption2)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(statusColor)
            .foregroundStyle(.white)
            .clipShape(Capsule())
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

#Preview {
    BooksListView()
        .environmentObject(AppContainer.shared)
}
