import SwiftUI

@main
struct BookRoomApp: App {
    @StateObject private var appContainer = AppContainer.shared

    var body: some Scene {
        WindowGroup {
            AppRootView()
                .environmentObject(appContainer)
        }
    }
}
