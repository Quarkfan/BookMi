import SwiftUI

/// Add book entry point - scanner, search, manual, OCR, CSV
struct AddBookView: View {
    @EnvironmentObject var appContainer: AppContainer

    @State private var showScanner = false
    @State private var showSearch = false
    @State private var showManualEntry = false
    @State private var showCSVImport = false
    @State private var selectedSearchDraft: BookMetadataDraft?
    @State private var scannedISBN: String?
    @State private var isLoadingLookup = false
    @State private var lookupError: String?

    var body: some View {
        NavigationView {
            List {
                Section("录入方式") {
                    // Scanner
                    Button {
                        showScanner = true
                    } label: {
                        Label("扫码录入", systemImage: "barcode.viewfinder")
                    }

                    // Network search
                    Button {
                        showSearch = true
                    } label: {
                        Label("网络搜索", systemImage: "magnifyingglass")
                    }

                    // Manual entry
                    Button {
                        showManualEntry = true
                    } label: {
                        Label("手动录入", systemImage: "square.and.pencil")
                    }

                    // OCR
                    Button {
                        showOCR = true
                    } label: {
                        Label("拍照识别", systemImage: "doc.viewfinder")
                    }

                    // CSV import
                    Button {
                        showCSVImport = true
                    } label: {
                        Label("CSV 导入", systemImage: "doc.badge.plus")
                    }
                }

                // Quick settings
                Section("扫码默认设置") {
                    NavigationLink("默认书柜") {
                        DefaultShelfSettingView()
                    }
                    NavigationLink("默认标签") {
                        DefaultTagsSettingView()
                    }
                }
            }
            .navigationTitle("录入")
            .overlay {
                if isLoadingLookup {
                    ProgressView("查询图书信息...")
                        .padding(20)
                        .background(Color.secondary.colorInvert())
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }
            .alert("查询失败", isPresented: Binding(
                get: { lookupError != nil },
                set: { if !$0 { lookupError = nil } }
            )) {
                Button("确定", role: .cancel) {}
            } message: {
                Text(lookupError ?? "")
            }
            .sheet(isPresented: $showScanner) {
                ScannerView(onISBNScanned: { isbn in
                    showScanner = false
                    lookupISBN(isbn)
                })
            }
            .sheet(isPresented: $showSearch) {
                BookSearchSheet(onSelect: { draft in
                    showSearch = false
                    selectedSearchDraft = draft
                    showManualEntry = true
                })
            }
            .sheet(isPresented: $showManualEntry) {
                BookEntryForm(initialData: selectedSearchDraft) { draft in
                    saveBook(draft)
                    showManualEntry = false
                    selectedSearchDraft = nil
                }
            }
            .sheet(isPresented: $showCSVImport) {
                CSVImportSheet(onComplete: { _ in
                    showCSVImport = false
                })
            }
        }
    }

    // MARK: - ISBN Lookup

    private func lookupISBN(_ isbn: String) {
        scannedISBN = isbn
        isLoadingLookup = true

        Task {
            let results = await BookLookupService().lookup(isbn: isbn)
            await MainActor.run {
                isLoadingLookup = false

                if let first = results.first {
                    selectedSearchDraft = first
                    showManualEntry = true
                } else {
                    lookupError = "未找到 ISBN \(isbn) 对应的图书，请手动录入"
                    // Open manual entry with ISBN pre-filled
                    selectedSearchDraft = BookMetadataDraft(
                        isbn10: isbn.count == 10 ? isbn : nil,
                        isbn13: isbn.count == 13 ? isbn : nil
                    )
                    showManualEntry = true
                }
            }
        }
    }
}

// MARK: - Book Search Sheet

struct BookSearchSheet: View {
    let onSelect: (BookMetadataDraft) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var searchText = ""
    @State private var results: [BookMetadataDraft] = []
    @State private var isSearching = false

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Search bar
                HStack {
                    TextField("搜索书名、作者、ISBN", text: $searchText)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit { search() }
                    Button("搜索") { search() }
                        .disabled(searchText.isEmpty)
                }
                .padding()

                // Results
                if isSearching {
                    ProgressView()
                        .padding()
                } else if results.isEmpty && !searchText.isEmpty {
                    Text("未找到相关图书")
                        .foregroundStyle(.secondary)
                        .padding()
                } else if results.isEmpty {
                    Text("输入关键词搜索网络图书")
                        .foregroundStyle(.secondary)
                        .padding()
                } else {
                    List(results, id: \.id) { draft in
                        Button {
                            onSelect(draft)
                        } label: {
                            SearchResultRow(draft: draft)
                        }
                    }
                }
            }
            .navigationTitle("网络搜索")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("取消") { dismiss() }
                }
            }
        }
    }

    private func search() {
        guard !searchText.isEmpty else { return }
        isSearching = true

        Task {
            results = await BookLookupService().search(keyword: searchText)
            await MainActor.run {
                isSearching = false
            }
        }
    }
}

struct SearchResultRow: View {
    let draft: BookMetadataDraft

    var body: some View {
        HStack(spacing: 12) {
            AsyncImage(url: draft.coverURL) { image in
                image.resizable().aspectRatio(contentMode: .fill)
            } placeholder: {
                Rectangle().fill(Color.gray.opacity(0.2))
            }
            .frame(width: 40, height: 60)
            .clipShape(RoundedRectangle(cornerRadius: 4))

            VStack(alignment: .leading, spacing: 4) {
                Text(draft.title ?? "未知书名")
                    .font(.headline)
                    .lineLimit(1)
                if let authors = draft.authors, !authors.isEmpty {
                    Text(authors.joined(separator: " / "))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                if let publisher = draft.publisher {
                    Text(publisher)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Image(systemName: "plus.circle.fill")
                .foregroundStyle(.accentColor)
        }
    }
}

// MARK: - Default Shelf Setting

struct DefaultShelfSettingView: View {
    @EnvironmentObject var appContainer: AppContainer
    @State private var shelves: [Shelf] = []
    @State private var selectedID: String?

    var body: some View {
        List {
            Section {
                Button("无") {
                    appContainer.settings.defaultShelfID = nil
                    selectedID = nil
                }
                .foregroundColor(selectedID == nil ? .accentColor : .primary)

                ForEach(shelves, id: \.id) { shelf in
                    Button(shelf.name) {
                        appContainer.settings.defaultShelfID = shelf.id
                        selectedID = shelf.id
                    }
                    .foregroundColor(selectedID == shelf.id ? .accentColor : .primary)
                }
            }
        }
        .navigationTitle("默认书柜")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            do {
                shelves = try appContainer.shelfRepo.fetchAll()
                selectedID = appContainer.settings.defaultShelfID
            } catch {
                print("Failed to load shelves: \(error)")
            }
        }
    }
}

// MARK: - Default Tags Setting

struct DefaultTagsSettingView: View {
    @EnvironmentObject var appContainer: AppContainer
    @State private var tags: [Tag] = []
    @State private var selectedIDs: [String] = []

    var body: some View {
        List {
            ForEach(tags, id: \.id) { tag in
                Button(tag.name) {
                    if let index = selectedIDs.firstIndex(of: tag.id) {
                        selectedIDs.remove(at: index)
                    } else {
                        selectedIDs.append(tag.id)
                    }
                    appContainer.settings.defaultTagIDs = selectedIDs
                }
                .foregroundColor(selectedIDs.contains(tag.id) ? .accentColor : .primary)
            }
        }
        .navigationTitle("默认标签")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            do {
                tags = try appContainer.tagRepo.fetchAll()
                selectedIDs = appContainer.settings.defaultTagIDs
            } catch {
                print("Failed to load tags: \(error)")
            }
        }
    }
}

#Preview {
    AddBookView()
        .environmentObject(AppContainer.shared)
}
