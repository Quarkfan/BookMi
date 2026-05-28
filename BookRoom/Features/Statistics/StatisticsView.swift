import SwiftUI

/// Placeholder - Statistics view
struct StatisticsView: View {
    var body: some View {
        NavigationView {
            VStack {
                Spacer()
                Image(systemName: "chart.bar")
                    .font(.system(size: 48))
                    .foregroundStyle(.secondary)
                Text("统计分析")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .navigationTitle("统计")
        }
    }
}

#Preview {
    StatisticsView()
}
