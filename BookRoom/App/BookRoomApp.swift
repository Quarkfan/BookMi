import SwiftUI

@main
struct BookRoomApp: App {
    @StateObject private var appContainer = AppContainer.shared

    var body: some Scene {
        WindowGroup {
            Group {
                if appContainer.isInitializing {
                    LaunchScreenView()
                } else if appContainer.isAuthenticated {
                    MainTabView()
                } else {
                    PasscodeView(onAuthenticated: { appContainer.authenticate() })
                }
            }
            .environmentObject(appContainer)
            .task {
                await appContainer.initialize()
            }
        }
    }
}
