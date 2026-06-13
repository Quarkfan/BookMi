import SwiftUI
import GRDB

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
                    NavigationLink("图书数据源") {
                        BookLookupSettingsView()
                    }
                }

                // AI / OCR
                Section("AI / OCR") {
                    NavigationLink("AI / OCR 设置") {
                        AIOCRSettingsView()
                    }
                }

                // Borrowing
                Section("借阅") {
                    NavigationLink("借出管理") {
                        BorrowedBooksView()
                    }
                }

                // Data Management
                Section("数据管理") {
                    NavigationLink("导入导出") {
                        ImportExportView()
                    }
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
                    bookCount = try await appContainer.bookRepo.fetchCount()
                } catch {
                    print("Failed to fetch book count: \(error)")
                }
            }
        }
    }

    private func rebuildIndex() {
        Task {
            do {
                try await appContainer.searchRepo.rebuildIndex()
            } catch {
                print("Failed to rebuild index: \(error)")
            }
        }
    }

    private func rebuildPinyinIndex() {
        Task {
            do {
                try await appContainer.searchRepo.rebuildPinyinIndex()
            } catch {
                print("Failed to rebuild pinyin index: \(error)")
            }
        }
    }
}

// MARK: - Book Lookup Settings

struct BookLookupSettingsView: View {
    @EnvironmentObject var appContainer: AppContainer
    @State private var juheEnabled = false
    @State private var juheKey = ""
    @State private var jisuEnabled = false
    @State private var jisuKey = ""
    @State private var guguEnabled = false
    @State private var guguKey = ""
    @State private var aiISBNEnabled = false
    @State private var overseasEnabled = false
    @State private var providerOrder = BookLookupProviderKey.defaultOrder
    @State private var showKey = false

    var body: some View {
        Form {
            Section {
                Toggle("启用极速数据 ISBN", isOn: $jisuEnabled)
                    .onChange(of: jisuEnabled) { _, newValue in
                        appContainer.settings.isJisuISBNEnabled = newValue
                    }

                HStack {
                    if showKey {
                        TextField("极速数据 AppKey", text: $jisuKey)
                    } else {
                        SecureField("极速数据 AppKey", text: $jisuKey)
                    }
                    Button {
                        showKey.toggle()
                    } label: {
                        Image(systemName: showKey ? "eye.slash" : "eye")
                            .foregroundStyle(.secondary)
                    }
                }
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .onChange(of: jisuKey) { _, newValue in
                    if newValue.isEmpty {
                        appContainer.keychain.deleteJisuISBNAppKey()
                    } else {
                        _ = appContainer.keychain.setJisuISBNAppKey(newValue)
                    }
                }
            } header: {
                Text("中文搜索优先")
            } footer: {
                Text("极速数据支持书名关键词搜索和 ISBN 查询，价格更适合个人小次数使用，建议作为默认中文搜索源。")
            }

            Section {
                Toggle("启用咕咕数据 ISBN", isOn: $guguEnabled)
                    .onChange(of: guguEnabled) { _, newValue in
                        appContainer.settings.isGuguISBNEnabled = newValue
                    }

                HStack {
                    if showKey {
                        TextField("咕咕数据 AppKey", text: $guguKey)
                    } else {
                        SecureField("咕咕数据 AppKey", text: $guguKey)
                    }
                    Button {
                        showKey.toggle()
                    } label: {
                        Image(systemName: showKey ? "eye.slash" : "eye")
                            .foregroundStyle(.secondary)
                    }
                }
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .onChange(of: guguKey) { _, newValue in
                    if newValue.isEmpty {
                        appContainer.keychain.deleteGuguISBNAppKey()
                    } else {
                        _ = appContainer.keychain.setGuguISBNAppKey(newValue)
                    }
                }
            } header: {
                Text("高覆盖付费源")
            } footer: {
                Text("咕咕数据也支持 ISBN 和关键词参数，但价格偏企业化；个人使用可先关闭。")
            }

            Section {
                Toggle("启用聚合数据 ISBN", isOn: $juheEnabled)
                    .onChange(of: juheEnabled) { _, newValue in
                        appContainer.settings.isJuheISBNEnabled = newValue
                    }

                HStack {
                    if showKey {
                        TextField("聚合数据 API Key", text: $juheKey)
                    } else {
                        SecureField("聚合数据 API Key", text: $juheKey)
                    }
                    Button {
                        showKey.toggle()
                    } label: {
                        Image(systemName: showKey ? "eye.slash" : "eye")
                            .foregroundStyle(.secondary)
                    }
                }
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .onChange(of: juheKey) { _, newValue in
                    if newValue.isEmpty {
                        appContainer.keychain.deleteJuheISBNAPIKey()
                    } else {
                        _ = appContainer.keychain.setJuheISBNAPIKey(newValue)
                    }
                }
            } header: {
                Text("扫码 ISBN 兜底")
            } footer: {
                Text("聚合数据适合 ISBN 查询，主要用于扫码后的图书信息获取。")
            }

            Section {
                Toggle("启用海外数据源兜底", isOn: $overseasEnabled)
                    .onChange(of: overseasEnabled) { _, newValue in
                        appContainer.settings.isOverseasBookLookupEnabled = newValue
                    }
            } header: {
                Text("海外源")
            } footer: {
                Text("Open Library 和 Google Books 在中国境内可能无法访问或很慢。默认关闭，只有需要国际图书兜底时再启用。")
            }

            Section {
                Toggle("启用 AI ISBN 查询", isOn: $aiISBNEnabled)
                    .onChange(of: aiISBNEnabled) { _, newValue in
                        appContainer.settings.isAIBookLookupEnabled = newValue
                        if newValue {
                            // AI ISBN is a concrete AI capability; enabling it should not require
                            // the user to discover and toggle a second master switch elsewhere.
                            appContainer.settings.isAICapabilityEnabled = true
                        }
                    }
            } header: {
                Text("AI 兜底")
            } footer: {
                Text("复用「AI / OCR 设置」中的模型配置。模型会调度 App 提供的百度检索、网页读取、开放 ISBN 查询和图片验证工具；仅接受 ISBN 完全一致且带来源的结果。模型接口需支持 Tool Calling。")
            }

            Section("当前顺序") {
                ForEach(providerOrder) { provider in
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(provider.displayName)
                            Text(provider.detail)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if let status = providerUnavailableReason(provider) {
                            Text(status)
                                .font(.caption)
                                .foregroundStyle(status == "未启用" ? Color.secondary.opacity(0.55) : Color.orange)
                        }
                    }
                }
                .onMove { source, destination in
                    providerOrder.move(fromOffsets: source, toOffset: destination)
                    appContainer.settings.bookLookupProviderOrder = providerOrder.map(\.rawValue)
                }
            }
        }
        .navigationTitle("图书数据源")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            EditButton()
        }
        .task {
            juheEnabled = appContainer.settings.isJuheISBNEnabled
            juheKey = appContainer.keychain.getJuheISBNAPIKey() ?? ""
            jisuEnabled = appContainer.settings.isJisuISBNEnabled
            jisuKey = appContainer.keychain.getJisuISBNAppKey() ?? ""
            guguEnabled = appContainer.settings.isGuguISBNEnabled
            guguKey = appContainer.keychain.getGuguISBNAppKey() ?? ""
            aiISBNEnabled = appContainer.settings.isAIBookLookupEnabled
            overseasEnabled = appContainer.settings.isOverseasBookLookupEnabled
            providerOrder = appContainer.settings.bookLookupProviderOrder.compactMap(BookLookupProviderKey.init(rawValue:))
        }
    }

    private func providerUnavailableReason(_ provider: BookLookupProviderKey) -> String? {
        switch provider {
        case .jisu:
            if !jisuEnabled { return "未启用" }
            return jisuKey.isEmpty ? "缺少 AppKey" : nil
        case .gugu:
            if !guguEnabled { return "未启用" }
            return guguKey.isEmpty ? "缺少 AppKey" : nil
        case .juhe:
            if !juheEnabled { return "未启用" }
            return juheKey.isEmpty ? "缺少 API Key" : nil
        case .aiISBN:
            if !aiISBNEnabled { return "未启用" }
            if !appContainer.settings.isAICapabilityEnabled { return "AI 总开关关闭" }
            if appContainer.settings.aiBaseURL?.nilIfEmpty == nil
                || appContainer.settings.aiModelName?.nilIfEmpty == nil
                || appContainer.keychain.getLLMAPIKey()?.nilIfEmpty == nil {
                return "缺少模型配置"
            }
            return nil
        case .openLibrary, .googleBooks:
            return overseasEnabled ? nil : "未启用"
        }
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
                channels = try await appContainer.databaseManager.dbQueue.read { (db: Database) in
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
        Task {
            do {
                channels = try await appContainer.databaseManager.dbQueue.read { (db: Database) in
                    try PurchaseChannel.fetchAll(db)
                }
            } catch {
                print("Failed to load channels: \(error)")
            }
        }
    }

    private func deleteChannel(at offsets: IndexSet) {
        for index in offsets {
            let channel = channels[index]
            Task {
                do {
                    try await appContainer.databaseManager.dbQueue.write { (db: Database) in
                        try db.execute(
                            sql: "UPDATE purchase_channels SET deleted_at = ?, updated_at = ? WHERE id = ?",
                            arguments: [ISO8601DateFormatter().string(from: Date()), ISO8601DateFormatter().string(from: Date()), channel.id])
                    }
                    loadChannels()
                } catch {
                    print("Failed to delete channel: \(error)")
                }
            }
        }
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
                        Task {
                            let now = ISO8601DateFormatter().string(from: Date())
                            let ch = channel ?? PurchaseChannel(
                                id: UUID().uuidString, name: name, sortOrder: 0,
                                createdAt: now, updatedAt: now, deletedAt: nil)
                            do {
                                if channel != nil {
                                    try await appContainer.databaseManager.dbQueue.write { (db: Database) in
                                        try db.execute(sql: "UPDATE purchase_channels SET name=?, sort_order=?, updated_at=? WHERE id=?", arguments: [ch.name, ch.sortOrder, now, ch.id])
                                    }
                                } else {
                                    try await appContainer.databaseManager.dbQueue.write { (db: Database) in
                                        try db.execute(sql: "INSERT INTO purchase_channels (id, name, sort_order, created_at, updated_at) VALUES (?, ?, ?, ?, ?)", arguments: [ch.id, ch.name, ch.sortOrder, now, now])
                                    }
                                }
                                await MainActor.run { onSave(ch) }
                            } catch {
                                print("Failed to save channel: \(error)")
                            }
                        }
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
            do {
                let books = try await appContainer.bookRepo.fetchAll()
                missingISBN = books.filter { $0.isbn13 == nil && $0.isbn10 == nil }.count
                missingCover = books.filter { $0.coverFileName == nil }.count
                missingShelf = books.filter { $0.shelfID == nil }.count
            } catch {
                print("Failed to calculate quality metrics: \(error)")
            }
        }
    }
}

// MARK: - Stub Views (TODO: implement)

struct DisplayModeSettingView: View {
    @AppStorage("displayMode") private var displayMode: String = "list"
    var body: some View {
        Form {
            Picker("显示模式", selection: $displayMode) {
                Text("列表").tag("list")
                Text("网格").tag("grid")
            }
        }
        .navigationTitle("显示模式")
    }
}

struct SortSettingView: View {
    @AppStorage("sortMode") private var sortMode: String = "createdAt"
    var body: some View {
        Form {
            Picker("排序方式", selection: $sortMode) {
                Text("添加时间").tag("createdAt")
                Text("书名拼音").tag("pinyin")
                Text("首字母").tag("firstLetter")
            }
        }
        .navigationTitle("排序方式")
    }
}

#Preview {
    SettingsView()
        .environmentObject(AppContainer.shared)
}
