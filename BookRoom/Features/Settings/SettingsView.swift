import SwiftUI

/// Placeholder - Settings view
struct SettingsView: View {
    var body: some View {
        NavigationView {
            List {
                Section("录入设置") {
                    Text("默认书柜")
                    Text("默认标签")
                    Text("默认购买渠道")
                }
                Section("AI / OCR") {
                    Text("AI / OCR 设置")
                }
                Section("数据安全") {
                    Text("数据备份与恢复")
                    Text("启动密码")
                    Text("iCloud 同步")
                }
                Section("数据维护") {
                    Text("重建索引")
                    Text("数据质量检查")
                    Text("导出诊断报告")
                }
                Section("关于") {
                    Text("BookRoom v1.0.0")
                }
            }
            .navigationTitle("设置")
        }
    }
}

#Preview {
    SettingsView()
}
