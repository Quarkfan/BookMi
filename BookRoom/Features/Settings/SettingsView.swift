import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var appContainer: AppContainer
    @State private var bookCount = 0

    var body: some View {
        NavigationView {
            List {
                // Overview
                Section("数据概览") {
                    HStack {
                        Text("藏书总数")
                        Spacer()
                        Text("\(bookCount) 本")
                            .foregroundStyle(.secondary)
                    }
                }

                // Entry Settings
                Section("录入设置") {
                    NavigationLink("默认书柜") {
                        DefaultShelfSettingView()
                    }
                    NavigationLink("默认标签") {
                        DefaultTagsSettingView()
                    }
                    NavigationLink("默认购买渠道") {
                        DefaultChannelSettingView()
                    }
                }

                // AI / OCR
                Section("AI / OCR") {
                    NavigationLink("AI / OCR 设置") {
                        AIOCRSettingsView()
                    }
                }

                // Data Management
                Section("数据管理") {
                    NavigationLink("标签管理") {
                        TagManagementView()
                    }
                    NavigationLink("购买渠道管理") {
                        ChannelManagementView()
                    }
                }

                // Data Maintenance
                Section("数据维护") {
                    Button { rebuildIndex() } label: {
                        Label("重建搜索索引", systemImage: "arrow.clockwise")
                    }
                    Button { rebuildPinyinIndex() } label: {
                        Label("重建拼音索引", systemImage: "character.book.closed")
                    }
                    NavigationLink("数据质量检查") {
                        DataQualityView()
                    }
                }

                // Data Security
                Section("数据安全") {
                    NavigationLink("数据备份与恢复") {
                        BackupRestoreView()
                    }
                    Toggle("启动密码", isOn: Binding(
                        get: { appContainer.settings.isPasscodeEnabled },
                        set: { appContainer.settings.isPasscodeEnabled = $0 }
                    ))
                }

                // Display
                Section("显示设置") {
                    NavigationLink("显示模式") {
                        DisplayModeSettingView()
                    }
                    NavigationLink("排序方式") {
                        SortSettingView()
                    }
                }

                // About
                Section("关于") {
                    HStack {
                        Text("版本")
                        Spacer()
                        Text("1.0.0")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("设置")
            .task {
                do {
                    bookCount = try appContainer.bookRepo.fetchCount()
                } catch {
                    print("Failed to fetch book count: \(error)")
                }
            }
        }
    }

    private func rebuildIndex() {
        Task {
            do {
                try appContainer.searchRepo.rebuildIndex()
            } catch {
                print("Failed to rebuild index: \(error)")
            }
        }
    }

    private func rebuildPinyinIndex() {
        Task {
            do {
                try appContainer.searchRepo.rebuildPinyinIndex()
            } catch {
                print("Failed to rebuild pinyin index: \(error)")
            }
        }
    }
}

// MARK: - AIOCR Settings

struct AIOCRSettingsView: View {
    @EnvironmentObject var appContainer: AppContainer
    @State private var isEnabled = false
    @State private var baseURL = ""
    @State private var modelName = ""
    @State private var isTesting = false
    @State private var testResult: String?

    var body: some View {
        Form {
            Section {
                Toggle("启用 AI/OCR", isOn: $isEnabled)
                    .onChange(of: isEnabled) { _, newValue in
                        appContainer.settings.isAICapabilityEnabled = newValue
                    }

                TextField("API Base URL", text: $baseURL)
                    .onChange(of: baseURL) { _, newValue in
                        appContainer.settings.aiBaseURL = newValue.nilIfEmpty
                    }

                TextField("Model Name", text: $modelName)
                    .onChange(of: modelName) { _, newValue in
                        appContainer.settings.aiModelName = newValue.nilIfEmpty
                    }
            }

            Section {
                Button(isTesting ? "测试中..." : "测试连接") {
                    testConnection()
                }
                .disabled(isEnabled && baseURL.isEmpty)

                if let result = testResult {
                    Text(result)
                        .font(.caption)
                        .foregroundStyle(result.hasPrefix("成功") ? .green : .red)
                }
            }
        }
        .navigationTitle("AI / OCR 设置")
        .onAppear {
            isEnabled = appContainer.settings.isAICapabilityEnabled
            baseURL = appContainer.settings.aiBaseURL ?? ""
            modelName = appContainer.settings.aiModelName ?? ""
        }
    }

    private func testConnection() {
        guard !baseURL.isEmpty else {
            testResult = "请先配置 API Base URL"
            return
        }
        isTesting = true
        // TODO: Actually test the connection
        testResult = "测试功能待实现"
        isTesting = false
    }
}

// MARK: - Default Channel Setting

struct DefaultChannelSettingView: View {
    @EnvironmentObject var appContainer: AppContainer
    @State private var channels: [PurchaseChannel] = []
    @State private var selectedID: String?

    var body: some View {
        List {
            Section {
                Button("无") {
                    appContainer.settings.defaultPurchaseChannelID = nil
                    selectedID = nil
                }
                .foregroundColor(selectedID == nil ? .accentColor : .primary)

                ForEach(channels, id: \.id) { channel in
                    Button(channel.name) {
                        appContainer.settings.defaultPurchaseChannelID = channel.id
                        selectedID = channel.id
                    }
                    .foregroundColor(selectedID == channel.id ? .accentColor : .primary)
                }
            }
        }
        .navigationTitle("默认购买渠道")
        .task {
            do {
                channels = try appContainer.dbQueue.read { db in
                    try PurchaseChannel.fetchAll(db)
                }
                selectedID = appContainer.settings.defaultPurchaseChannelID
            } catch {
                print("Failed to load channels: \(error)")
            }
        }
    }
}

// MARK: - Channel Management

struct ChannelManagementView: View {
    @EnvironmentObject var appContainer: AppContainer
    @State private var channels: [PurchaseChannel] = []
    @State private var showAddChannel = false

    var body: some View {
        List {
            ForEach(channels, id: \.id) { channel in
                Text(channel.name)
            }
            .onDelete(perform: deleteChannel)
        }
        .navigationTitle("购买渠道管理")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    showAddChannel = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .task { loadChannels() }
        .sheet(isPresented: $showAddChannel) {
            ChannelEditView(onSave: { _ in
                showAddChannel = false
                loadChannels()
            })
        }
    }

    private func loadChannels() {
        do {
            channels = try appContainer.dbQueue.read { db in
                try PurchaseChannel.fetchAll(db)
            }
        } catch {
            print("Failed to load channels: \(error)")
        }
    }

    private func deleteChannel(at offsets: IndexSet) {
        // TODO: Implement channel deletion
    }
}

struct ChannelEditView: View {
    let channel: PurchaseChannel?
    let onSave: (PurchaseChannel) -> Void
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var appContainer: AppContainer

    @State private var name = ""

    init(channel: PurchaseChannel? = nil, onSave: @escaping (PurchaseChannel) -> Void) {
        self.channel = channel
        self.onSave = onSave
    }

    var body: some View {
        NavigationView {
            Form {
                Section {
                    TextField("渠道名称 *", text: $name)
                }
            }
            .navigationTitle(channel == nil ? "新渠道" : "编辑渠道")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("保存") {
                        let now = ISO8601DateFormatter().string(from: Date())
                        var ch = channel ?? PurchaseChannel(
                            id: UUID().uuidString, name: name, sortOrder: 0,
                            createdAt: now, updatedAt: now, deletedAt: nil)
                        ch.name = name
                        ch.updatedAt = now
                        // TODO: save to database
                        onSave(ch)
                    }
                    .disabled(name.isEmpty)
                }
            }
            .onAppear {
                if let channel { name = channel.name }
            }
        }
    }
}

// MARK: - Data Quality View

struct DataQualityView: View {
    @EnvironmentObject var appContainer: AppContainer
    @State private var missingISBN = 0
    @State private var missingCover = 0
    @State private var missingShelf = 0

    var body: some View {
        List {
            Section("数据质量") {
                HStack {
                    Text("缺失 ISBN")
                    Spacer()
                    Text("\(missingISBN)")
                        .foregroundStyle(missingISBN > 0 ? .orange : .secondary)
                }
                HStack {
                    Text("缺失封面")
                    Spacer()
                    Text("\(missingCover)")
                        .foregroundStyle(missingCover > 0 ? .orange : .secondary)
                }
                HStack {
                    Text("未设置书柜")
                    Spacer()
                    Text("\(missingShelf)")
                        .foregroundStyle(missingShelf > 0 ? .orange : .secondary)
                }
            }
        }
        .navigationTitle("数据质量检查")
        .task {
            // TODO: Calculate actual values
        }
    }
}

// MARK: - Backup Restore View

struct BackupRestoreView: View {
    var body: some View {
        List {
            Section {
                Text("备份功能待实现")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("数据备份与恢复")
    }
}

// MARK: - Display Mode Setting

struct DisplayModeSettingView: View {
    @EnvironmentObject var appContainer: AppContainer
    @State private var mode: DisplayMode

    init() {
        _mode = State(initialValue: AppContainer.shared.settings.displayMode)
    }

    var body: some View {
        Picker("显示模式", selection: $mode) {
            Text("列表模式").tag(DisplayMode.list)
            Text("平铺模式").tag(DisplayMode.grid)
        }
        .pickerStyle(.inline)
        .onChange(of: mode) { _, newValue in
            appContainer.settings.displayMode = newValue
        }
    }
}

// MARK: - Sort Setting View

struct SortSettingView: View {
    @EnvironmentObject var appContainer: AppContainer
    @State private var sortField: SortField
    @State private var sortOrder: SortOrder

    init() {
        _sortField = State(initialValue: AppContainer.shared.settings.sortField)
        _sortOrder = State(initialValue: AppContainer.shared.settings.sortOrder)
    }

    var body: some View {
        Form {
            Section("排序字段") {
                Picker("", selection: $sortField) {
                    Text("拼音").tag(SortField.pinyin)
                    Text("首字母").tag(SortField.firstLetter)
                    Text("添加时间").tag(SortField.createdAt)
                    Text("编辑时间").tag(SortField.updatedAt)
                }
                .onChange(of: sortField) { _, newValue in
                    appContainer.settings.sortField = newValue
                }
            }
            Section("排序顺序") {
                Picker("", selection: $sortOrder) {
                    Text("升序").tag(SortOrder.ascending)
                    Text("降序").tag(SortOrder.descending)
                }
                .onChange(of: sortOrder) { _, newValue in
                    appContainer.settings.sortOrder = newValue
                }
            }
        }
        .navigationTitle("排序方式")
    }
}

#Preview {
    SettingsView()
        .environmentObject(AppContainer.shared)
}
