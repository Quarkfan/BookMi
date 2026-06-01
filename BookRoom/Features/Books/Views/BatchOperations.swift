import SwiftUI

struct BatchActionSheet: View {
    let selectedBookIDs: [String]
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var appContainer: AppContainer
    @State private var showShelfPicker = false
    @State private var showTagPicker = false
    @State private var showStatusPicker = false
    @State private var isProcessing = false

    var body: some View {
        NavigationView {
            List {
                Section("批量操作 (\(selectedBookIDs.count) 本)") {
                    Button { showShelfPicker = true } label: { Label("移动书柜", systemImage: "shelf") }
                    Button { showTagPicker = true } label: { Label("添加标签", systemImage: "tag") }
                    Button { showStatusPicker = true } label: { Label("设置阅读状态", systemImage: "book") }
                    Button { markFinished() } label: { Label("标记读完", systemImage: "checkmark.circle") }
                    Button(role: .destructive) { deleteBooks() } label: { Label("删除图书", systemImage: "trash") }
                }
            }
            .navigationTitle("批量操作")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .navigationBarTrailing) { Button("关闭") { dismiss() } } }
            .sheet(isPresented: $showShelfPicker) {
                BatchShelfPicker(bookIDs: selectedBookIDs, onComplete: { dismiss() })
            }
            .sheet(isPresented: $showTagPicker) {
                BatchTagPicker(bookIDs: selectedBookIDs, onComplete: { dismiss() })
            }
            .sheet(isPresented: $showStatusPicker) {
                BatchStatusPicker(bookIDs: selectedBookIDs, onComplete: { dismiss() })
            }
            .overlay {
                if isProcessing {
                    ProgressView("处理中...")
                        .padding(20)
                        .background(Color.secondary.colorInvert())
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }
        }
    }

    private func markFinished() {
        isProcessing = true
        Task {
            do {
                try await appContainer.bookRepo.batchMarkFinished(bookIDs: selectedBookIDs)
            } catch { print("Failed: \(error)") }
            await MainActor.run { isProcessing = false; dismiss() }
        }
    }

    private func deleteBooks() {
        isProcessing = true
        Task {
            do {
                try await appContainer.bookRepo.softDelete(ids: selectedBookIDs)
            } catch { print("Failed: \(error)") }
            await MainActor.run { isProcessing = false; dismiss() }
        }
    }
}

struct BatchShelfPicker: View {
    let bookIDs: [String]
    let onComplete: () -> Void
    @EnvironmentObject var appContainer: AppContainer
    @State private var shelves: [Shelf] = []
    @State private var isProcessing = false

    var body: some View {
        NavigationView {
            List {
                if isProcessing {
                    ProgressView()
                } else {
                    Button("取消书柜关联") { moveShelf(to: nil) }.foregroundColor(.accentColor)
                    ForEach(shelves, id: \.id) { shelf in
                        Button(shelf.name) { moveShelf(to: shelf.id) }
                    }
                }
            }
            .navigationTitle("选择书柜")
            .task { do { shelves = try await appContainer.shelfRepo.fetchAll() } catch { print("Failed: \(error)") } }
        }
    }

    private func moveShelf(to shelfID: String?) {
        isProcessing = true
        Task {
            do {
                try await appContainer.bookRepo.batchUpdateShelf(bookIDs: bookIDs, shelfID: shelfID)
            } catch { print("Failed: \(error)") }
            await MainActor.run { isProcessing = false; onComplete() }
        }
    }
}

struct BatchTagPicker: View {
    let bookIDs: [String]
    let onComplete: () -> Void
    @EnvironmentObject var appContainer: AppContainer
    @State private var tags: [Tag] = []
    @State private var isProcessing = false

    var body: some View {
        NavigationView {
            List {
                if isProcessing { ProgressView() }
                else {
                    ForEach(tags, id: \.id) { tag in
                        Button(tag.name) { addTag(tag.id) }
                    }
                }
            }
            .navigationTitle("添加标签")
            .task { do { tags = try await appContainer.tagRepo.fetchAll() } catch { print("Failed: \(error)") } }
        }
    }

    private func addTag(_ tagID: String) {
        isProcessing = true
        Task {
            do {
                try await appContainer.tagRepo.addTags(tagIDs: [tagID], toBooks: bookIDs)
            } catch { print("Failed: \(error)") }
            await MainActor.run { isProcessing = false; onComplete() }
        }
    }
}

struct BatchStatusPicker: View {
    let bookIDs: [String]
    let onComplete: () -> Void
    @EnvironmentObject var appContainer: AppContainer
    @State private var isProcessing = false

    var body: some View {
        NavigationView {
            List {
                if isProcessing { ProgressView() }
                else {
                    ForEach(ReadingStatus.allCases, id: \.self) { status in
                        Button(status.displayName) { setStatus(to: status) }
                    }
                }
            }
            .navigationTitle("设置阅读状态")
        }
    }

    private func setStatus(to status: ReadingStatus) {
        isProcessing = true
        Task {
            do {
                try await appContainer.bookRepo.batchUpdateReadingStatus(bookIDs: bookIDs, status: status)
            } catch { print("Failed: \(error)") }
            await MainActor.run { isProcessing = false; onComplete() }
        }
    }
}

#Preview {
    BatchActionSheet(selectedBookIDs: []).environmentObject(AppContainer.shared)
}
