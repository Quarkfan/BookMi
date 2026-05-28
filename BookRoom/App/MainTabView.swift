import SwiftUI

struct AppRootView: View {
    @State private var isAuthenticated = false

    var body: some View {
        Group {
            if isAuthenticated {
                MainTabView()
            } else {
                LaunchScreenView(onAuthenticated: { isAuthenticated = true })
            }
        }
    }
}

struct MainTabView: View {
    var body: some View {
        TabView {
            BooksListView()
                .tabItem {
                    Label("藏书", systemImage: "books.vertical")
                }

            ShelvesListView()
                .tabItem {
                    Label("书柜", systemImage: "shelf")
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
}
