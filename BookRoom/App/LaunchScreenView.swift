import SwiftUI

struct LaunchScreenView: View {
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

            ProgressView()
                .padding(.top)

            Spacer()
        }
        .padding()
    }
}

#Preview {
    LaunchScreenView()
}
