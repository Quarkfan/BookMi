import SwiftUI

/// Placeholder - Add book entry point (scanner, search, manual, OCR, CSV)
struct AddBookView: View {
    var body: some View {
        NavigationView {
            List {
                Section("录入方式") {
                    Button {
                        // TODO: Open scanner
                    } label: {
                        Label("扫码录入", systemImage: "barcode.viewfinder")
                    }
                    Button {
                        // TODO: Open network search
                    } label: {
                        Label("网络搜索", systemImage: "magnifyingglass")
                    }
                    Button {
                        // TODO: Open manual entry form
                    } label: {
                        Label("手动录入", systemImage: "square.and.pencil")
                    }
                    Button {
                        // TODO: Open camera for OCR
                    } label: {
                        Label("拍照识别", systemImage: "doc.viewfinder")
                    }
                    Button {
                        // TODO: Open CSV import
                    } label: {
                        Label("CSV 导入", systemImage: "doc.badge.plus")
                    }
                }
            }
            .navigationTitle("录入")
        }
    }
}

#Preview {
    AddBookView()
}
