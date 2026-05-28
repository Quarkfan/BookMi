import SwiftUI
import GRDB

/// Borrow management view for a single book
struct BorrowManagementView: View {
    let book: Book
    @EnvironmentObject var appContainer: AppContainer
    @Environment(\.dismiss) private var dismiss

    @State private var borrowRecords: [BorrowRecord] = []
    @State private var showNewBorrow = false
    @State private var borrowerName = ""
    @State private var contact = ""
    @State private var expectedReturnDate = ""

    var body: some View {
        NavigationView {
            List {
                // Current status
                Section("当前状态") {
                    HStack {
                        Text("借出状态")
                        Spacer()
                        if book.borrowStatus == .borrowed {
                            Text("借出中")
                                .foregroundStyle(.orange)
                        } else {
                            Text("在馆")
                                .foregroundStyle(.green)
                        }
                    }

                    if book.borrowStatus == .borrowed,
                       let activeRecord = borrowRecords.first(where: { $0.status == "borrowed" }) {
                        HStack {
                            Text("借阅人")
                            Spacer()
                            Text(activeRecord.borrowerName)
                        }
                        if let contact = activeRecord.contact, !contact.isEmpty {
                            HStack {
                                Text("联系方式")
                                Spacer()
                                Text(contact)
                            }
                        }
                        if let expected = activeRecord.expectedReturnAt {
                            HStack {
                                Text("预计归还")
                                Spacer()
                                Text(formatDate(expected))
                            }
                        }

                        Button("确认归还") {
                            returnBook(activeRecord)
                        }
                        .foregroundColor(.accentColor)
                    }
                }

                // New borrow
                Section("新增借出") {
                    TextField("借阅人姓名 *", text: $borrowerName)
                    TextField("联系方式", text: $contact)
                    TextField("预计归还日期（可选）", text: $expectedReturnDate)

                    Button("记录借出") {
                        createBorrow()
                    }
                    .disabled(borrowerName.isEmpty || book.borrowStatus == .borrowed)
                    .foregroundColor(book.borrowStatus == .borrowed ? .secondary : .accentColor)
                }

                // History
                if !borrowRecords.isEmpty {
                    Section("借出历史") {
                        ForEach(borrowRecords, id: \.id) { record in
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(record.borrowerName)
                                        .font(.headline)
                                    Spacer()
                                    if record.status == "borrowed" {
                                        Text("借出中")
                                            .font(.caption)
                                            .foregroundStyle(.orange)
                                    } else {
                                        Text("已归还")
                                            .font(.caption)
                                            .foregroundStyle(.green)
                                    }
                                }
                                Text("借出: \(formatDate(record.borrowedAt))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                if let returned = record.returnedAt {
                                    Text("归还: \(formatDate(returned))")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
            }
            .navigationTitle("借出管理")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("关闭") { dismiss() }
                }
            }
            .task {
                await loadBorrowRecords()
            }
        }
    }

    @MainActor
    private func loadBorrowRecords() async {
        do {
            borrowRecords = try appContainer.dbQueue.read { db in
                try BorrowRecord
                    .filter(Column("book_id") == book.id)
                    .order(Column("borrowed_at").desc)
                    .fetchAll(db)
            }
        } catch {
            print("Failed to load borrow records: \(error)")
        }
    }

    private func createBorrow() {
        let now = ISO8601DateFormatter().string(from: Date())
        let record = BorrowRecord(
            id: UUID().uuidString,
            bookID: book.id,
            borrowerName: borrowerName,
            contact: contact.nilIfEmpty,
            borrowedAt: now,
            expectedReturnAt: expectedReturnDate.nilIfEmpty,
            returnedAt: nil,
            status: "borrowed",
            note: nil,
            createdAt: now,
            updatedAt: now
        )

        Task {
            do {
                try await appContainer.dbQueue.write { db in
                    try record.insert(db)
                    try db.execute(
                        sql: "UPDATE books SET borrow_status = 'borrowed', updated_at = ? WHERE id = ?",
                        arguments: [now, book.id])
                }
                await loadBorrowRecords()
                borrowerName = ""
                contact = ""
                expectedReturnDate = ""
            } catch {
                print("Failed to create borrow record: \(error)")
            }
        }
    }

    private func returnBook(_ record: BorrowRecord) {
        let now = ISO8601DateFormatter().string(from: Date())

        Task {
            do {
                try await appContainer.dbQueue.write { db in
                    try db.execute(
                        sql: """
                        UPDATE borrow_records
                        SET status = 'returned', returned_at = ?, updated_at = ?
                        WHERE id = ?
                        """,
                        arguments: [now, now, record.id])
                    try db.execute(
                        sql: "UPDATE books SET borrow_status = 'available', updated_at = ? WHERE id = ?",
                        arguments: [now, book.id])
                }
                await loadBorrowRecords()
            } catch {
                print("Failed to return book: \(error)")
            }
        }
    }

    private func formatDate(_ dateStr: String) -> String {
        let formatter = ISO8601DateFormatter()
        guard let date = formatter.date(from: dateStr) else { return dateStr }
        let display = DateFormatter()
        display.dateFormat = "yyyy-MM-dd"
        return display.string(from: date)
    }
}

/// Borrow management list view - shows all borrowed books
struct BorrowedBooksView: View {
    @EnvironmentObject var appContainer: AppContainer
    @State private var borrowedBooks: [Book] = []
    @State private var isLoading = true

    var body: some View {
        List {
            if isLoading {
                ProgressView()
            } else if borrowedBooks.isEmpty {
                Text("当前没有借出的图书")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(borrowedBooks, id: \.id) { book in
                    NavigationLink(destination: BorrowManagementView(book: book)) {
                        VStack(alignment: .leading) {
                            Text(book.title)
                                .font(.headline)
                            if let authors = decodeAuthors(book.authorsJSON), !authors.isEmpty {
                                Text(authors.joined(separator: " / "))
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("借出管理")
        .task { await loadBorrowedBooks() }
    }

    @MainActor
    private func loadBorrowedBooks() async {
        isLoading = true
        defer { isLoading = false }

        do {
            borrowedBooks = try appContainer.bookRepo.fetchAll().filter {
                $0.borrowStatus == .borrowed
            }
        } catch {
            print("Failed to load borrowed books: \(error)")
        }
    }

    private func decodeAuthors(_ json: String?) -> [String]? {
        guard let json, let data = json.data(using: .utf8),
              let arr = try? JSONDecoder().decode([String].self, from: data) else {
            return nil
        }
        return arr
    }
}

#Preview {
    BorrowedBooksView()
        .environmentObject(AppContainer.shared)
}
