import SwiftUI

/// Quick CSV import sheet for the AddBook entry point
struct CSVImportSheet: View {
    let onComplete: (ImportReport) -> Void
    @EnvironmentObject var appContainer: AppContainer

    @State private var showFullImport = false

    var body: some View {
        NavigationView {
            Form {
                Section("快速导入") {
                    Button("选择 CSV 文件") {
                        showFullImport = true
                    }
                    Text("支持 UTF-8 编码的 CSV 文件，将自动映射字段")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("CSV 导入")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showFullImport) {
                CSVImportView(onComplete: onComplete)
            }
        }
    }
}
