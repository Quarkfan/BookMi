import SwiftUI

struct ShelvesListView: View {
    @EnvironmentObject var appContainer: AppContainer
    @State private var shelves: [(shelf: Shelf, bookCount: Int)] = []
    @State private var isLoading = true
    @State private var showAddShelf = false

    var body: some View {
        NavigationView {
            Group {
                if isLoading {
                    ProgressView("加载中...")
                } else if shelves.isEmpty {
                    emptyState
                } else {
                    List {
                        ForEach(shelves, id: \.shelf.id) { item in
                            NavigationLink(destination: ShelfDetailView(shelf: item.shelf)) {
                                ShelfRowView(shelf: item.shelf, bookCount: item.bookCount)
                            }
                        }
                        .onDelete(perform: deleteShelf)
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("书柜")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showAddShelf = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .task { await loadShelves() }
            .sheet(isPresented: $showAddShelf) {
                ShelfEditView(onSave: { _ in
                    showAddShelf = false
                    Task { await loadShelves() }
                })
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "shelf")
                .font(.system(size: 64))
                .foregroundStyle(.secondary)
            Text("还没有书柜")
                .font(.headline)
                .foregroundStyle(.secondary)
            Button("创建第一个书柜") {
                showAddShelf = true
            }
            .buttonStyle(.borderedProminent)
        }
    }

    @MainActor
    private func loadShelves() async {
        isLoading = true
        defer { isLoading = false }

        do {
            shelves = try appContainer.shelfRepo.fetchAllWithBookCounts()
        } catch {
            print("Failed to load shelves: \(error)")
        }
    }

    private func deleteShelf(at offsets: IndexSet) {
        for index in offsets {
            let shelf = shelves[index].shelf
            do {
                try appContainer.shelfRepo.deleteAndUnclassify(id: shelf.id)
            } catch {
                print("Failed to delete shelf: \(error)")
            }
        }
        Task { await loadShelves() }
    }
}

// MARK: - Shelf Row

struct ShelfRowView: View {
    let shelf: Shelf
    let bookCount: Int

    var body: some View {
        HStack {
            Image(systemName: "books.vertical")
                .foregroundStyle(.accentColor)
            VStack(alignment: .leading) {
                Text(shelf.name)
                    .font(.headline)
                if let note = shelf.locationNote, !note.isEmpty {
                    Text(note)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Text("\(bookCount) 本")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Shelf Detail View

struct ShelfDetailView: View {
    let shelf: Shelf
    @EnvironmentObject var appContainer: AppContainer
    @State private var books: [Book] = []
    @State private var showEditSheet = false

    var body: some View {
        ScrollView {
            if books.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "books.vertical")
                        .font(.system(size: 48))
                        .foregroundStyle(.secondary)
                    Text("该书柜暂无图书")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 100)
            } else {
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
        .navigationTitle(shelf.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu("操作") {
                    Button { showEditSheet = true } label: {
                        Label("编辑", systemImage: "pencil")
                    }
                    Button(role: .destructive) { deleteShelf() } label: {
                        Label("删除", systemImage: "trash")
                    }
                }
            }
        }
        .task {
            do {
                books = try appContainer.bookRepo.fetch(byShelfID: shelf.id)
            } catch {
                print("Failed to load books: \(error)")
            }
        }
        .sheet(isPresented: $showEditSheet) {
            ShelfEditView(shelf: shelf, onSave: { _ in
                showEditSheet = false
            })
        }
    }

    private func deleteShelf() {
        do {
            try appContainer.shelfRepo.deleteAndUnclassify(id: shelf.id)
        } catch {
            print("Failed to delete shelf: \(error)")
        }
    }
}

// MARK: - Shelf Edit View

struct ShelfEditView: View {
    let shelf: Shelf?
    let onSave: (Shelf) -> Void
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var appContainer: AppContainer

    @State private var name = ""
    @State private var locationNote = ""
    @State private var note = ""
    @State private var isSaving = false

    init(shelf: Shelf? = nil, onSave: @escaping (Shelf) -> Void) {
        self.shelf = shelf
        self.onSave = onSave
    }

    var body: some View {
        NavigationView {
            Form {
                Section("基本信息") {
                    TextField("书柜名称 *", text: $name)
                    TextField("位置说明", text: $locationNote)
                    TextField("备注", text: $note, axis: .vertical)
                        .lineLimit(3...6)
                }
            }
            .navigationTitle(shelf == nil ? "新书柜" : "编辑书柜")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(isSaving ? "保存中..." : "保存") {
                        saveShelf()
                    }
                    .disabled(name.isEmpty || isSaving)
                }
            }
            .onAppear {
                if let shelf {
                    name = shelf.name
                    locationNote = shelf.locationNote ?? ""
                    note = shelf.note ?? ""
                }
            }
        }
    }

    private func saveShelf() {
        isSaving = true

        let now = ISO8601DateFormatter().string(from: Date())
        var shelfItem = shelf ?? Shelf(
            id: UUID().uuidString,
            name: name,
            locationNote: locationNote.nilIfEmpty,
            sortOrder: 0,
            note: note.nilIfEmpty,
            createdAt: now,
            updatedAt: now,
            deletedAt: nil
        )

        shelfItem.name = name
        shelfItem.locationNote = locationNote.nilIfEmpty
        shelfItem.note = note.nilIfEmpty
        shelfItem.updatedAt = now

        do {
            if shelf != nil {
                shelfItem = try appContainer.shelfRepo.update(shelfItem)
            } else {
                shelfItem = try appContainer.shelfRepo.insert(shelfItem)
            }
            onSave(shelfItem)
        } catch {
            print("Failed to save shelf: \(error)")
        }
        isSaving = false
    }
}

#Preview {
    ShelvesListView()
        .environmentObject(AppContainer.shared)
}
