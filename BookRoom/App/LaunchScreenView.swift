import SwiftUI

struct LaunchScreenView: View {
    let onAuthenticated: () -> Void

    var body: some View {
        VStack {
            Spacer()

            Image(systemName: "books.vertical.fill")
                .resizable()
                .scaledToFit()
                .frame(width: 80, height: 80)
                .foregroundColor(.accentColor)

            Text("BookRoom")
                .font(.largeTitle)
                .fontWeight(.bold)
                .padding(.top)

            Text("书房管理")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Spacer()
        }
        .padding()
        .onAppear {
            // TODO: Check if passcode/FaceID is enabled
            // If not, authenticate immediately
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                onAuthenticated()
            }
        }
    }
}

#Preview {
    LaunchScreenView(onAuthenticated: {})
}
