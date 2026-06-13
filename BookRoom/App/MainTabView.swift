import SwiftUI

struct MainTabView: View {
    @EnvironmentObject var appContainer: AppContainer

    var body: some View {
        TabView {
            BooksListView()
                .tabItem {
                    Label("藏书", systemImage: "books.vertical")
                }

            ShelvesListView()
                .tabItem {
                    Label("书柜", systemImage: "archivebox")
                }

            AddBookView()
                .tabItem {
                    Label("录入", systemImage: "plus.circle")
                }

            StatisticsView()
                .tabItem {
                    Label("统计", systemImage: "chart.bar")
                }

            SettingsView()
                .tabItem {
                    Label("设置", systemImage: "gearshape")
                }
        }
    }
}

#Preview {
    MainTabView()
        .environmentObject(AppContainer.shared)
}
