import SwiftUI

/// Add book entry point - scanner, search, manual, OCR, CSV
struct AddBookView: View {
    @EnvironmentObject var appContainer: AppContainer

    @State private var showScanner = false
    @State private var showSearch = false
    @State private var showManualEntry = false
    @State private var showCSVImport = false
    @State private var showOCR = false
    @State private var selectedSearchDraft: BookMetadataDraft?
    @State private var entryMode: BookEntryMode = .manual
    @State private var scannedISBN: String?
    @State private var isLoadingLookup = false
    @State private var lookupProvider: String?
    @State private var lookupError: String?
    @State private var lookupProgress: [String] = []
    @State private var failedLookupDraft: BookMetadataDraft?
    @State private var lookupTask: Task<Void, Never>?
    @State private var lookupCheckpoint: AILookupCheckpoint?
    @State private var checkpointContinuation: CheckedContinuation<Bool, Never>?
    @State private var aiLiveStatus: AILookupLiveStatus?
    @State private var acceptCurrentAIResult = false
    @State private var isAcceptingCurrentInformation = false
    @State private var entryPresentationTask: Task<Void, Never>?

    var body: some View {
        NavigationView {
            List {
                Section("录入方式") {
                    // Scanner
                    Button {
                        showScanner = true
                    } label: {
                        Label("扫码录入", systemImage: "barcode.viewfinder")
                    }

                    // Network search
                    Button {
                        showSearch = true
                    } label: {
                        Label("网络搜索", systemImage: "magnifyingglass")
                    }

                    // Manual entry
                    Button {
                        selectedSearchDraft = nil
                        entryMode = .manual
                        showManualEntry = true
                    } label: {
                        Label("手动录入", systemImage: "square.and.pencil")
                    }

                    // OCR
                    Button {
                        showOCR = true
                    } label: {
                        Label("拍照识别", systemImage: "doc.viewfinder")
                    }

                    // CSV import
                    Button {
                        showCSVImport = true
                    } label: {
                        Label("CSV 导入", systemImage: "doc.badge.plus")
                    }
                }

                // Quick settings
                Section("扫码默认设置") {
                    NavigationLink("默认书柜") {
                        DefaultShelfSettingView()
                    }
                    NavigationLink("默认标签") {
                        DefaultTagsSettingView()
                    }
                }
            }
            .navigationTitle("录入")
            .overlay {
                if isLoadingLookup {
                    lookupProgressOverlay
                }
            }
            .alert("查询失败", isPresented: Binding(
                get: { lookupError != nil },
                set: { if !$0 { lookupError = nil } }
            )) {
                Button("手动录入") {
                    if let draft = failedLookupDraft {
                        openManualEntryAfterSheetDismiss(draft, mode: .scannedISBN)
                    }
                    failedLookupDraft = nil
                }
                Button("取消", role: .cancel) {
                    failedLookupDraft = nil
                }
            } message: {
                Text(lookupError ?? "")
            }
            .alert("AI 阶段调查完成", isPresented: Binding(
                get: { lookupCheckpoint != nil },
                set: { if !$0, lookupCheckpoint != nil { resolveCheckpoint(continueLookup: false) } }
            )) {
                Button("继续调查") {
                    resolveCheckpoint(continueLookup: true)
                }
                Button("使用当前结果") {
                    resolveCheckpoint(continueLookup: false)
                }
            } message: {
                Text(checkpointMessage)
            }
            .sheet(isPresented: $showScanner) {
                ScannerView(onISBNScanned: { isbn in
                    showScanner = false
                    lookupISBN(isbn)
                })
            }
            .sheet(isPresented: $showSearch) {
                BookSearchSheet(onSelect: { draft in
                    enrichSearchDraftAndOpen(draft)
                })
            }
            .sheet(isPresented: $showManualEntry) {
                BookEntryForm(initialData: selectedSearchDraft, mode: entryMode) { draft in
                    saveBook(draft)
                    showManualEntry = false
                    selectedSearchDraft = nil
                    entryMode = .manual
                }
            }
            .sheet(isPresented: $showCSVImport) {
                CSVImportSheet(onComplete: { _ in
                    showCSVImport = false
                })
            }
        }
    }

    // MARK: - ISBN Lookup

    private func openManualEntryAfterSheetDismiss(_ draft: BookMetadataDraft, mode: BookEntryMode) {
        selectedSearchDraft = draft
        entryMode = mode
        showSearch = false
        showScanner = false

        entryPresentationTask?.cancel()
        entryPresentationTask = Task { @MainActor in
            // Sheets and alerts must finish dismissing before SwiftUI can present
            // the entry form reliably. Retry briefly instead of relying on one
            // animation-dependent delay.
            for _ in 0..<12 {
                try? await Task.sleep(for: .milliseconds(150))
                guard !Task.isCancelled else { return }
                if !showScanner, !showSearch, lookupCheckpoint == nil {
                    showManualEntry = true
                    entryPresentationTask = nil
                    return
                }
            }
            showManualEntry = true
            entryPresentationTask = nil
        }
    }

    private func lookupISBN(_ isbn: String) {
        scannedISBN = isbn
        isLoadingLookup = true
        lookupProvider = nil
        lookupProgress = ["已识别 ISBN \(isbn)"]
        lookupError = nil
        failedLookupDraft = nil
        lookupCheckpoint = nil
        checkpointContinuation = nil
        aiLiveStatus = nil
        acceptCurrentAIResult = false
        isAcceptingCurrentInformation = false

        lookupTask?.cancel()
        lookupTask = Task {
            let results = await BookLookupService().lookup(
                isbn: isbn,
                onProviderChange: { provider in
                    lookupProvider = provider
                },
                onProgress: { message in
                    appendLookupProgress(message)
                },
                onAICheckpoint: { checkpoint in
                    await requestCheckpointDecision(checkpoint)
                },
                onAIStatus: { status in
                    aiLiveStatus = status
                },
                shouldAcceptAIResult: {
                    acceptCurrentAIResult
                }
            )
            await MainActor.run {
                if acceptCurrentAIResult {
                    lookupTask = nil
                    return
                }
                isLoadingLookup = false
                lookupProvider = nil
                lookupTask = nil
                aiLiveStatus = nil
                acceptCurrentAIResult = false

                if let first = results.first {
                    openManualEntryAfterSheetDismiss(first, mode: .scannedISBN)
                } else if Task.isCancelled {
                    lookupError = "已停止查询。\n\n\(lookupProgressSummary)"
                } else {
                    failedLookupDraft = BookMetadataDraft(
                        isbn10: isbn.count == 10 ? isbn : nil,
                        isbn13: isbn.count == 13 ? isbn : nil
                    )
                    lookupError = "未找到 ISBN \(isbn) 对应的图书。\n\n查询过程：\n\(lookupProgressSummary)"
                }
            }
        }
    }

    private func enrichSearchDraftAndOpen(_ draft: BookMetadataDraft) {
        guard let isbn = draft.isbn13 ?? draft.isbn10 else {
            openManualEntryAfterSheetDismiss(draft, mode: .searchResult)
            return
        }

        isLoadingLookup = true
        lookupProvider = nil

        Task {
            let details = await BookLookupService().lookup(
                isbn: isbn,
                onProviderChange: { provider in
                    lookupProvider = provider
                }
            )
            await MainActor.run {
                isLoadingLookup = false
                lookupProvider = nil
                if let first = details.first {
                    openManualEntryAfterSheetDismiss(draft.merging(with: first), mode: .searchResult)
                } else {
                    openManualEntryAfterSheetDismiss(draft, mode: .searchResult)
                }
            }
        }
    }

    private var lookupStatusMessage: String {
        if let lookupProvider {
            return "正在从 \(lookupProvider) 查询图书信息..."
        }
        return "正在准备可用数据源..."
    }

    private var lookupProgressOverlay: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                ProgressView()
                Text(lookupStatusMessage)
                    .font(.headline)
                    .lineLimit(2)
            }

            Divider()

            if let status = aiLiveStatus {
                HStack {
                    Text("已获取 \(status.acquired.count) 项")
                    Spacer()
                    Text("待补充 \(status.pending.count) 项")
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color(uiColor: .secondaryLabel))

                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        aiWorkBoard(status.workItems)

                        aiProcessTimeline

                        Text("当前动作：\(status.currentActivity)")
                            .font(.callout.weight(.medium))
                            .foregroundStyle(Color(uiColor: .label))
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color(uiColor: .tertiarySystemBackground), in: RoundedRectangle(cornerRadius: 10))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 2)
                }
                // ScrollView has a near-zero ideal height inside an overlay VStack.
                // Give the live task details guaranteed space so the action buttons
                // cannot squeeze all acquired/current information out of view.
                .frame(minHeight: 240, maxHeight: 390)
                .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))

                if status.canAcceptCurrentResult {
                    Button {
                        acceptCurrentInformation(status)
                    } label: {
                        Label(
                            isAcceptingCurrentInformation ? "正在固化当前信息…" : "接受当前信息",
                            systemImage: isAcceptingCurrentInformation
                                ? "arrow.triangle.2.circlepath"
                                : "checkmark.seal.fill"
                        )
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isAcceptingCurrentInformation)
                }
            } else {
                ForEach(Array(lookupProgress.suffix(4).enumerated()), id: \.offset) { _, message in
                    Text(message)
                        .font(.callout)
                        .foregroundStyle(Color(uiColor: .label))
                        .lineLimit(2)
                }
            }

            Button("停止查询", role: .destructive) {
                resolveCheckpoint(continueLookup: false)
                lookupTask?.cancel()
            }
            .frame(maxWidth: .infinity)
        }
        .padding(18)
        .frame(maxWidth: 340, alignment: .leading)
        .background(Color(uiColor: .systemBackground), in: RoundedRectangle(cornerRadius: 18))
        .overlay {
            RoundedRectangle(cornerRadius: 18)
                .stroke(Color(uiColor: .separator), lineWidth: 0.5)
        }
        .shadow(color: .black.opacity(0.24), radius: 20, y: 8)
        .padding()
    }

    private func lookupStatusSection(
        title: String,
        systemImage: String,
        color: Color,
        values: [String]
    ) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Label(title, systemImage: systemImage)
                .font(.caption.weight(.semibold))
                .foregroundStyle(color)
            ForEach(Array(values.enumerated()), id: \.offset) { _, value in
                Text(value)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(title == "已获取" ? 3 : 2)
            }
        }
    }

    private func aiWorkBoard(_ items: [AILookupWorkItem]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("AI 调查任务", systemImage: "checklist")
                .font(.callout.weight(.bold))
                .foregroundStyle(Color(uiColor: .label))

            ForEach(items) { item in
                HStack(alignment: .top, spacing: 9) {
                    Group {
                        switch item.state {
                        case .completed:
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(Color(uiColor: .systemGreen))
                        case .active:
                            ProgressView()
                                .controlSize(.small)
                        case .pending:
                            Image(systemName: "circle")
                                .foregroundStyle(Color(uiColor: .secondaryLabel))
                        }
                    }
                    .frame(width: 18, height: 18)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.title)
                            .font(.callout.weight(item.state == .active ? .bold : .semibold))
                            .foregroundStyle(Color(uiColor: .label))
                        Text(item.detail)
                            .font(.caption)
                            .foregroundStyle(Color(uiColor: .secondaryLabel))
                            .lineLimit(2)
                    }
                    Spacer(minLength: 0)
                    Text(workItemStateText(item.state))
                        .font(.caption.weight(.bold))
                        .foregroundStyle(workItemStateColor(item.state))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 4)
                        .background(workItemStateColor(item.state).opacity(0.14), in: Capsule())
                }
                .padding(10)
                .background(workItemBackgroundColor(item.state), in: RoundedRectangle(cornerRadius: 9))
                .overlay {
                    RoundedRectangle(cornerRadius: 9)
                        .stroke(workItemStateColor(item.state).opacity(item.state == .active ? 0.45 : 0.16), lineWidth: 0.7)
                }
            }
        }
    }

    private func workItemStateText(_ state: AILookupWorkItem.State) -> String {
        switch state {
        case .pending: return "待处理"
        case .active: return "处理中"
        case .completed: return "已完成"
        }
    }

    private func workItemStateColor(_ state: AILookupWorkItem.State) -> Color {
        switch state {
        case .pending: return Color(uiColor: .secondaryLabel)
        case .active: return Color(uiColor: .systemBlue)
        case .completed: return Color(uiColor: .systemGreen)
        }
    }

    private func workItemBackgroundColor(_ state: AILookupWorkItem.State) -> Color {
        switch state {
        case .pending: return Color(uiColor: .tertiarySystemBackground)
        case .active: return Color(uiColor: .systemBlue).opacity(0.12)
        case .completed: return Color(uiColor: .systemGreen).opacity(0.10)
        }
    }

    private var aiProcessTimeline: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("AI 工作进程", systemImage: "brain.head.profile")
                .font(.callout.weight(.bold))
                .foregroundStyle(Color(uiColor: .systemBlue))

            let events = Array(lookupProgress.suffix(6))
            ForEach(Array(events.enumerated()), id: \.offset) { index, event in
                HStack(alignment: .top, spacing: 8) {
                    if index == events.count - 1 {
                        ProgressView()
                            .controlSize(.mini)
                            .frame(width: 14, height: 14)
                    } else {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(Color(uiColor: .systemGreen))
                            .frame(width: 14, height: 14)
                    }

                    Text(event)
                        .font(.caption.weight(index == events.count - 1 ? .semibold : .regular))
                        .foregroundStyle(index == events.count - 1
                            ? Color(uiColor: .label)
                            : Color(uiColor: .secondaryLabel))
                        .lineLimit(3)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .padding(10)
        .background(Color(uiColor: .tertiarySystemBackground), in: RoundedRectangle(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color(uiColor: .separator), lineWidth: 0.5)
        }
    }

    @MainActor
    private func acceptCurrentInformation(_ status: AILookupLiveStatus) {
        guard !isAcceptingCurrentInformation else { return }
        guard let draft = status.currentDraft else {
            appendLookupProgress("当前信息仍在校验，请稍候再试")
            return
        }

        isAcceptingCurrentInformation = true
        acceptCurrentAIResult = true
        appendLookupProgress("正在固化当前信息并打开确认页")
        resolveCheckpoint(continueLookup: false)
        lookupTask?.cancel()
        lookupTask = nil

        selectedSearchDraft = draft
        entryMode = .scannedISBN
        showScanner = false
        showSearch = false

        Task { @MainActor in
            // Let the button visibly acknowledge the tap before replacing the
            // lookup overlay with the entry sheet.
            await Task.yield()
            isLoadingLookup = false
            lookupProvider = nil
            aiLiveStatus = nil
            showManualEntry = true
            isAcceptingCurrentInformation = false
        }
    }

    @MainActor
    private func appendLookupProgress(_ message: String) {
        guard lookupProgress.last != message else { return }
        lookupProgress.append(message)
        if lookupProgress.count > 30 {
            lookupProgress.removeFirst(lookupProgress.count - 30)
        }
    }

    private var lookupProgressSummary: String {
        lookupProgress.suffix(10).map { "• \($0)" }.joined(separator: "\n")
    }

    private var checkpointMessage: String {
        guard let checkpoint = lookupCheckpoint else { return "" }
        let acquired = checkpoint.acquired.isEmpty ? "暂无可确认字段" : checkpoint.acquired.joined(separator: "、")
        let missing = checkpoint.missing.isEmpty ? "无" : checkpoint.missing.joined(separator: "、")
        let opportunities = checkpoint.nextOpportunities.map { "• \($0)" }.joined(separator: "\n")
        return """
        当前已获得：\(acquired)

        尚缺少：\(missing)

        继续调查可能：
        \(opportunities)
        """
    }

    @MainActor
    private func requestCheckpointDecision(_ checkpoint: AILookupCheckpoint) async -> Bool {
        await withCheckedContinuation { continuation in
            checkpointContinuation = continuation
            lookupCheckpoint = checkpoint
        }
    }

    @MainActor
    private func resolveCheckpoint(continueLookup: Bool) {
        guard let continuation = checkpointContinuation else {
            lookupCheckpoint = nil
            return
        }
        checkpointContinuation = nil
        lookupCheckpoint = nil
        continuation.resume(returning: continueLookup)
    }

    // MARK: - Save

    private func saveBook(_ draft: BookMetadataDraft) {
        Task {
            do {
                var book = Book(from: draft, shelfID: appContainer.settings.defaultShelfID, purchaseChannelID: appContainer.settings.defaultPurchaseChannelID)
                book = try await appContainer.bookRepo.insert(book)
                if !appContainer.settings.defaultTagIDs.isEmpty {
                    try await appContainer.tagRepo.addTags(tagIDs: appContainer.settings.defaultTagIDs, toBooks: [book.id])
                }
                if draft.coverURL != nil {
                    let fileName = await draft.downloadCover(forBookID: book.id)
                    var updated = book
                    updated.coverFileName = fileName
                    try await appContainer.bookRepo.update(updated)
                }
                try await appContainer.searchRepo.updateIndex(for: book)
            } catch {
                print("Failed to save book: \(error)")
            }
        }
    }
}

// MARK: - Book Search Sheet

struct BookSearchSheet: View {
    let onSelect: (BookMetadataDraft) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var searchText = ""
    @State private var results: [BookMetadataDraft] = []
    @State private var isSearching = false
    @State private var searchError: String?
    @State private var hasSearched = false
    @State private var searchTask: Task<Void, Never>?
    @State private var currentProvider: String?
    @State private var searchProgress: [String] = []

    var body: some View {
        NavigationView {
            ZStack {
                LinearGradient(
                    colors: [
                        Color(red: 0.98, green: 0.95, blue: 0.88),
                        Color(red: 0.91, green: 0.95, blue: 0.92)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()

                VStack(spacing: 18) {
                    searchHero

                    Group {
                        if isSearching {
                            SearchEmptyState(
                                systemImage: "books.vertical",
                                title: "正在翻书架...",
                                message: searchStatusMessage
                            ) {
                                VStack(spacing: 12) {
                                    ProgressView()
                                    VStack(alignment: .leading, spacing: 7) {
                                        ForEach(Array(searchProgress.suffix(5).enumerated()), id: \.offset) { index, message in
                                            HStack(alignment: .top, spacing: 7) {
                                                Image(systemName: index == searchProgress.suffix(5).count - 1 ? "sparkles" : "checkmark.circle.fill")
                                                    .foregroundStyle(index == searchProgress.suffix(5).count - 1 ? .blue : .green)
                                                Text(message)
                                                    .font(.caption)
                                                    .foregroundStyle(Color(uiColor: .label))
                                                    .frame(maxWidth: .infinity, alignment: .leading)
                                            }
                                        }
                                    }
                                    .padding(10)
                                    .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
                                    Button("停止搜索") { cancelSearch() }
                                        .buttonStyle(.bordered)
                                }
                            }
                        } else if let error = searchError {
                            SearchEmptyState(
                                systemImage: "exclamationmark.cloud",
                                title: "数据源暂不可用",
                                message: error
                            ) {
                                Button("重试") { search() }
                                    .buttonStyle(.borderedProminent)
                            }
                        } else if !results.isEmpty {
                            ScrollView {
                                LazyVStack(spacing: 12) {
                                    HStack {
                                        Text("找到 \(results.count) 本可能匹配")
                                            .font(.subheadline.weight(.semibold))
                                            .foregroundStyle(.secondary)
                                        Spacer()
                                    }
                                    .padding(.horizontal, 20)

                                    ForEach(results, id: \.id) { draft in
                                        Button {
                                            onSelect(draft)
                                        } label: {
                                            SearchResultRow(draft: draft)
                                        }
                                        .buttonStyle(.plain)
                                        .padding(.horizontal, 16)
                                    }
                                }
                                .padding(.bottom, 20)
                            }
                        } else if hasSearched {
                            SearchEmptyState(
                                systemImage: "questionmark.app.dashed",
                                title: "暂时没找到",
                                message: "当前启用的数据源没有命中，可以换 ISBN 搜索，或先手动录入。"
                            ) {
                                Button("手动录入这个关键词") {
                                    onSelect(BookMetadataDraft(title: searchText))
                                }
                                .buttonStyle(.bordered)
                            }
                        } else {
                            SearchEmptyState(
                                systemImage: "text.magnifyingglass",
                                title: "搜书名、作者或 ISBN",
                                message: "中国境内优先使用咕咕数据和聚合数据；海外源默认关闭"
                            ) {
                                EmptyView()
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .navigationTitle("网络搜索")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("取消") {
                        cancelSearch()
                        dismiss()
                    }
                }
                if isSearching {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("停止") { cancelSearch() }
                    }
                }
            }
            .onDisappear {
                cancelSearch()
            }
        }
    }

    private var searchHero: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("找到一本书的身份")
                .font(.system(.title2, design: .serif).weight(.bold))
                .foregroundStyle(Color(red: 0.20, green: 0.14, blue: 0.09))
            Text("搜索时会显示当前数据源；中文书名优先避开境内不稳定的 Google Books")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("例如：三体、活着、9787536692930", text: $searchText)
                    .textInputAutocapitalization(.never)
                    .submitLabel(.search)
                    .onSubmit { search() }
                if !searchText.isEmpty {
                    Button {
                        cancelSearch()
                        searchText = ""
                        results = []
                        searchError = nil
                        hasSearched = false
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                }
                Button {
                    search()
                } label: {
                    Image(systemName: "arrow.right")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(width: 38, height: 38)
                        .background(Color(red: 0.16, green: 0.38, blue: 0.30), in: Circle())
                }
                .disabled(searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSearching)
            }
            .padding(12)
            .background(.white.opacity(0.92), in: RoundedRectangle(cornerRadius: 18))
            .shadow(color: .black.opacity(0.08), radius: 18, y: 8)
        }
        .padding(20)
        .background(.white.opacity(0.45), in: RoundedRectangle(cornerRadius: 28))
        .padding(.horizontal, 16)
        .padding(.top, 14)
    }

    private func search() {
        let keyword = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !keyword.isEmpty else { return }
        searchTask?.cancel()
        isSearching = true
        searchError = nil
        results = []
        hasSearched = true
        currentProvider = nil
        searchProgress = ["准备搜索「\(keyword)」"]

        searchTask = Task {
            let result = await BookLookupService().search(
                keyword: keyword,
                onProviderChange: { provider in currentProvider = provider },
                onProgress: { message in
                    guard searchProgress.last != message else { return }
                    searchProgress.append(message)
                    if searchProgress.count > 20 { searchProgress.removeFirst(searchProgress.count - 20) }
                }
            )
            await MainActor.run {
                guard !Task.isCancelled else { return }
                isSearching = false
                searchTask = nil
                currentProvider = nil
                switch result {
                case .success(let drafts):
                    results = drafts
                case .error(let message):
                    searchError = message
                case .notFound:
                    results = []
                }
            }
        }
    }

    private func cancelSearch() {
        searchTask?.cancel()
        searchTask = nil
        isSearching = false
        currentProvider = nil
    }

    private var searchStatusMessage: String {
        if let currentProvider {
            return "正在从 \(currentProvider) 获取图书信息；网络慢时可以先停止并手动录入"
        }
        return "正在准备可用数据源；如果网络慢，可以先停下来手动录入"
    }
}

struct SearchEmptyState<Action: View>: View {
    let systemImage: String
    let title: String
    let message: String
    @ViewBuilder var action: Action

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: systemImage)
                .font(.system(size: 46, weight: .light))
                .foregroundStyle(Color(red: 0.16, green: 0.38, blue: 0.30))
            Text(title)
                .font(.headline)
                .foregroundStyle(.primary)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            action
                .padding(.top, 4)
        }
        .padding(28)
        .frame(maxWidth: .infinity)
        .background(.white.opacity(0.72), in: RoundedRectangle(cornerRadius: 26))
        .padding(.horizontal, 18)
    }
}

struct SearchResultRow: View {
    let draft: BookMetadataDraft

    var body: some View {
        HStack(spacing: 14) {
            BookCoverThumbnail(coverURL: draft.coverURL)

            VStack(alignment: .leading, spacing: 4) {
                Text(draft.title ?? "未知书名")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                if let authors = draft.authors, !authors.isEmpty {
                    Text(authors.joined(separator: " / "))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                if let publisher = draft.publisher {
                    Text(publisher)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let source = draft.dataSource {
                    Text("来自 \(sourceDisplayName(source))")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(Color(red: 0.16, green: 0.38, blue: 0.30))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color(red: 0.16, green: 0.38, blue: 0.30).opacity(0.10), in: Capsule())
                }
            }

            Spacer()

            Image(systemName: "plus")
                .font(.headline)
                .foregroundStyle(.white)
                .frame(width: 34, height: 34)
                .background(Color(red: 0.16, green: 0.38, blue: 0.30), in: Circle())
        }
        .padding(14)
        .background(.white.opacity(0.88), in: RoundedRectangle(cornerRadius: 20))
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(.white.opacity(0.65), lineWidth: 1)
        )
    }

    private func sourceDisplayName(_ source: String) -> String {
        switch source {
        case "openlibrary": return "Open Library"
        case "googlebooks": return "Google Books"
        case "juhe_isbn": return "聚合数据 ISBN"
        case "gugu_isbn": return "咕咕数据 ISBN"
        case "jisu_isbn": return "极速数据 ISBN"
        case "ai_isbn": return "AI ISBN 查询"
        case "ai_search": return "AI 搜书 Agent"
        default: return source
        }
    }
}

struct BookCoverThumbnail: View {
    let coverURL: URL?

    var body: some View {
        Group {
            if let coverURL {
                AsyncImage(url: coverURL) { phase in
                    switch phase {
                    case .empty:
                        coverPlaceholder(title: "加载封面", systemImage: "arrow.down.doc")
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    case .failure:
                        coverPlaceholder(title: "封面失败", systemImage: "exclamationmark.triangle")
                    @unknown default:
                        coverPlaceholder(title: "无封面", systemImage: "book.closed")
                    }
                }
            } else {
                coverPlaceholder(title: "无封面", systemImage: "book.closed")
            }
        }
        .frame(width: 58, height: 82)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .shadow(color: .black.opacity(0.12), radius: 8, y: 4)
    }

    private func coverPlaceholder(title: String, systemImage: String) -> some View {
        ZStack {
            LinearGradient(
                colors: [.brown.opacity(0.25), .orange.opacity(0.18)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            VStack(spacing: 4) {
                Image(systemName: systemImage)
                    .font(.caption)
                    .foregroundStyle(.brown.opacity(0.62))
                Text(title)
                    .font(.system(size: 8, weight: .medium))
                    .foregroundStyle(.brown.opacity(0.68))
                    .lineLimit(1)
            }
        }
    }
}

// MARK: - Default Shelf Setting

struct DefaultShelfSettingView: View {
    @EnvironmentObject var appContainer: AppContainer
    @State private var shelves: [Shelf] = []
    @State private var selectedID: String?

    var body: some View {
        List {
            Section {
                Button("无") {
                    appContainer.settings.defaultShelfID = nil
                    selectedID = nil
                }
                .foregroundColor(selectedID == nil ? .accentColor : .primary)

                ForEach(shelves, id: \.id) { shelf in
                    Button(shelf.name) {
                        appContainer.settings.defaultShelfID = shelf.id
                        selectedID = shelf.id
                    }
                    .foregroundColor(selectedID == shelf.id ? .accentColor : .primary)
                }
            }
        }
        .navigationTitle("默认书柜")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            do {
                shelves = try await appContainer.shelfRepo.fetchAll()
                selectedID = appContainer.settings.defaultShelfID
            } catch {
                print("Failed to load shelves: \(error)")
            }
        }
    }
}

// MARK: - Default Tags Setting

struct DefaultTagsSettingView: View {
    @EnvironmentObject var appContainer: AppContainer
    @State private var tags: [Tag] = []
    @State private var selectedIDs: [String] = []

    var body: some View {
        List {
            ForEach(tags, id: \.id) { tag in
                Button(tag.name) {
                    if let index = selectedIDs.firstIndex(of: tag.id) {
                        selectedIDs.remove(at: index)
                    } else {
                        selectedIDs.append(tag.id)
                    }
                    appContainer.settings.defaultTagIDs = selectedIDs
                }
                .foregroundColor(selectedIDs.contains(tag.id) ? .accentColor : .primary)
            }
        }
        .navigationTitle("默认标签")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            do {
                tags = try await appContainer.tagRepo.fetchAll()
                selectedIDs = appContainer.settings.defaultTagIDs
            } catch {
                print("Failed to load tags: \(error)")
            }
        }
    }
}

#Preview {
    AddBookView()
        .environmentObject(AppContainer.shared)
}
