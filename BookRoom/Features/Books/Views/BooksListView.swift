import SwiftUI

/// Placeholder - Books list view
struct BooksListView: View {
    var body: some View {
        NavigationView {
            VStack {
                Spacer()
                Image(systemName: "books.vertical")
                    .font(.system(size: 48))
                    .foregroundStyle(.secondary)
                Text("藏书列表")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .navigationTitle("藏书")
            .searchable(text: .constant(""))
        }
    }
}

#Preview {
    BooksListView()
}
