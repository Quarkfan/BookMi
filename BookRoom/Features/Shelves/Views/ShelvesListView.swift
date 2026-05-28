import SwiftUI

/// Placeholder - Shelves list view
struct ShelvesListView: View {
    var body: some View {
        NavigationView {
            VStack {
                Spacer()
                Image(systemName: "shelf")
                    .font(.system(size: 48))
                    .foregroundStyle(.secondary)
                Text("书柜管理")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .navigationTitle("书柜")
        }
    }
}

#Preview {
    ShelvesListView()
}
