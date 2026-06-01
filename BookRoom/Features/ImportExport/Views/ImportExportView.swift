import SwiftUI

struct ImportExportView: View {
    @EnvironmentObject var appContainer: AppContainer
    @State private var showCSVImport = false
    @State private var showCSVExport = false
    @State private var showJSONExport = false
    @State private var importReport: ImportReport?
    @State private var showError = false
    @State private var errorMessage = ""

    var body: some View {
        List {
            Section("导入") {
                Button {
                    showCSVImport = true
                } label: {
                    Label("从 CSV 导入", systemImage: "square.and.arrow.down")
                }

                Button {
                    // TODO: JSON import
                } label: {
                    Label("从 JSON 导入", systemImage: "square.and.arrow.down")
                }
                .opacity(0.6)
            }

            Section("导出") {
                Button {
                    showCSVExport = true
                } label: {
                    Label("导出为 CSV", systemImage: "square.and.arrow.up")
                }

                Button {
                    showJSONExport = true
                } label: {
                    Label("导出为 JSON", systemImage: "square.and.arrow.up")
                }
            }
        }
        .navigationTitle("导入导出")
        .sheet(isPresented: $showCSVImport) {
            CSVImportView(onComplete: { report in
                importReport = report
                showCSVImport = false
            })
        }
        .sheet(isPresented: $showCSVExport) {
            CSVExportView(onComplete: {
                showCSVExport = false
            })
        }
        .sheet(isPresented: $showJSONExport) {
            JSONExportView(onComplete: {
                showJSONExport = false
            })
        }
        .alert("导入完成", isPresented: Binding(
            get: { importReport != nil },
            set: { if !$0 { importReport = nil } }
        )) {
            Button("确定", role: .cancel) {}
        } message: {
            if let report = importReport {
                Text(report.summary)
            }
        }
        .alert("错误", isPresented: $showError) {
            Button("确定", role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
    }
}

// MARK: - CSV Import View

struct CSVImportView: View {
    let onComplete: (ImportReport) -> Void
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var appContainer: AppContainer

    @State private var selectedFileURL: URL?
    @State private var fieldMapping: [String: CSVField] = [:]
    @State private var headers: [String] = []
    @State private var previewRows: [[String]] = []
    @State private var duplicateStrategy: DuplicateStrategy = .skip
    @State private var isImporting = false

    let availableFields: [(field: CSVField, defaultHeader: String)] = [
        (.title, "书名"),
        (.authors, "作者"),
        (.isbn13, "ISBN-13"),
        (.isbn10, "ISBN-10"),
        (.publisher, "出版社"),
        (.publishedDate, "出版日期"),
        (.pageCount, "页数"),
        (.price, "定价"),
        (.summary, "简介"),
        (.category, "分类"),
        (.edition, "版次"),
        (.series, "丛书"),
        (.binding, "装帧"),
    ]

    var body: some View {
        NavigationView {
            Form {
                if selectedFileURL == nil {
                    Section("选择文件") {
                        Button("选择 CSV 文件") {
                            // In a real app, use .fileImporter
                            // For now, simulate with a test file
                            loadSampleCSV()
                        }
                    }
                } else {
                    Section("已选择文件") {
                        Text(selectedFileURL?.lastPathComponent ?? "")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Section("字段映射") {
                        ForEach(headers, id: \.self) { header in
                            HStack {
                                Text(header)
                                    .font(.caption)
                                Spacer()
                                Picker("", selection: fieldBinding(for: header)) {
                                    Text("不映射").tag(CSVField?.none)
                                    ForEach(availableFields, id: \.field) { item in
                                        Text(item.defaultHeader).tag(CSVField?.some(item.field))
                                    }
                                }
                                .labelsHidden()
                            }
                        }
                    }

                    Section("重复处理") {
                        Picker("策略", selection: $duplicateStrategy) {
                            Text("跳过已有").tag(DuplicateStrategy.skip)
                            Text("覆盖已有").tag(DuplicateStrategy.overwrite)
                            Text("仅填空").tag(DuplicateStrategy.fillEmptyOnly)
                            Text("创建新副本").tag(DuplicateStrategy.createNewCopy)
                        }
                    }

                    Section("预览") {
                        ForEach(previewRows.prefix(3).enumerated(), id: \.offset) { i, row in
                            Text(row.joined(separator: " | "))
                                .font(.caption2)
                        }
                    }

                    Section {
                        Button(isImporting ? "导入中..." : "开始导入") {
                            startImport()
                        }
                        .disabled(!hasValidMapping)
                    }
                }
            }
            .navigationTitle("CSV 导入")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("取消") { dismiss() }
                }
            }
        }
    }

    private var hasValidMapping: Bool {
        fieldMapping.values.contains(.title)
    }

    private func fieldBinding(for header: String) -> Binding<CSVField?> {
        Binding(
            get: { fieldMapping[header] },
            set: { fieldMapping[header] = $0 }
        )
    }

    private func loadSampleCSV() {
        let sampleContent = """
        书名,作者,ISBN-13,出版社,出版日期,页数,定价
        三体,刘慈欣,9787536692930,重庆出版社,2008-01,302,23.00
        三体Ⅱ：黑暗森林,刘慈欣,9787536698628,重庆出版社,2008-05,351,32.00
        活着,余华,9787506365437,作家出版社,2012-08,191,20.00
        """
        let tempURL = AppPaths.tempImportURL.appendingPathComponent("sample_import.csv")
        try? sampleContent.write(to: tempURL, atomically: true, encoding: .utf8)
        selectedFileURL = tempURL
        parseHeaders()
    }

    private func parseHeaders() {
        guard let url = selectedFileURL,
              let content = try? String(contentsOf: url, encoding: .utf8) else { return }

        let lines = content.split(omittingEmptySubsequences: true) { $0.isNewline }
        guard let headerLine = lines.first else { return }

        headers = headerLine.split(separator: ",").map(String.init)
        previewRows = lines.dropFirst().prefix(3).map { line in
            line.split(separator: ",").map(String.init)
        }

        // Auto-map based on common header names
        let autoMap: [String: CSVField] = [
            "书名": .title,
            "作者": .authors,
            "ISBN-13": .isbn13,
            "isbn": .isbn13,
            "出版社": .publisher,
            "出版日期": .publishedDate,
            "页数": .pageCount,
            "定价": .price,
            "简介": .summary,
            "分类": .category,
        ]

        for header in headers {
            let trimmed = header.trimmingCharacters(in: .whitespaces)
            if let field = autoMap[trimmed] {
                fieldMapping[trimmed] = field
            }
        }
    }

    private func startImport() {
        guard let url = selectedFileURL else { return }
        isImporting = true

        Task {
            do {
                let report = try await CSVService.importBooks(
                    csvURL: url,
                    fieldMapping: fieldMapping,
                    defaultShelfID: appContainer.settings.defaultShelfID,
                    defaultTagIDs: appContainer.settings.defaultTagIDs,
                    defaultPurchaseChannelID: appContainer.settings.defaultPurchaseChannelID,
                    duplicateStrategy: duplicateStrategy,
                    bookRepo: appContainer.bookRepo,
                    tagRepo: appContainer.tagRepo,
                    searchRepo: appContainer.searchRepo
                )
                await MainActor.run {
                    isImporting = false
                    onComplete(report)
                }
            } catch {
                await MainActor.run {
                    isImporting = false
                    errorMessage = error.localizedDescription
                    showError = true
                }
            }
        }
    }
}

// MARK: - CSV Export View

struct CSVExportView: View {
    let onComplete: () -> Void
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var appContainer: AppContainer

    @State private var selectedFields: Set<CSVField> = Set(CSVField.allCases.prefix(5))
    @State private var isExporting = false

    var body: some View {
        NavigationView {
            Form {
                Section("选择导出字段") {
                    ForEach(CSVField.allCases, id: \.self) { field in
                        Button {
                            if selectedFields.contains(field) {
                                selectedFields.remove(field)
                            } else {
                                selectedFields.insert(field)
                            }
                        } label: {
                            HStack {
                                Text(field.header)
                                Spacer()
                                if selectedFields.contains(field) {
                                    Image(systemName: "checkmark")
                                        .foregroundColor(.accentColor)
                                }
                            }
                        }
                    }
                }

                Section {
                    Button(isExporting ? "导出中..." : "导出 CSV") {
                        exportCSV()
                    }
                    .disabled(selectedFields.isEmpty || isExporting)
                }
            }
            .navigationTitle("导出 CSV")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("取消") { dismiss() }
                }
            }
        }
    }

    private func exportCSV() {
        isExporting = true

        Task {
            do {
                let books = try await appContainer.bookRepo.fetchAll()
                let url = try await CSVService.exportBooks(
                    books: books,
                    fields: selectedFields.sorted(by: { $0.rawValue < $1.rawValue }),
                    shelfRepo: appContainer.shelfRepo,
                    tagRepo: appContainer.tagRepo,
                    dbQueue: appContainer.databaseManager.dbQueue
                )

                // Share the file
                let activityVC = UIActivityViewController(
                    activityItems: [url],
                    applicationActivities: nil
                )

                // Find the key window
                if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                   let rootVC = windowScene.windows.first?.rootViewController {
                    await MainActor.run {
                        isExporting = false
                        rootVC.present(activityVC, animated: true) {
                            onComplete()
                        }
                    }
                } else {
                    await MainActor.run {
                        isExporting = false
                        onComplete()
                    }
                }
            } catch {
                await MainActor.run {
                    isExporting = false
                    // Show error
                }
            }
        }
    }
}

// MARK: - JSON Export View

struct JSONExportView: View {
    let onComplete: () -> Void
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var appContainer: AppContainer

    var body: some View {
        NavigationView {
            Form {
                Section {
                    Button("导出 JSON") {
                        exportJSON()
                    }
                    Text("将导出所有图书、书柜、标签、借出记录、购买渠道和设置")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("导出 JSON")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("取消") { dismiss() }
                }
            }
        }
    }

    private func exportJSON() {
        Task {
            // Use BackupService's JSON export logic
            do {
                let dir = AppPaths.tempExportURL
                try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true, attributes: nil)

                // Export all entities (reuse BackupService logic)
                // For simplicity, we just call create backup and share the export directory
                let zipURL = try await BackupService.createBackup()

                if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                   let rootVC = windowScene.windows.first?.rootViewController {
                    await MainActor.run {
                        let activityVC = UIActivityViewController(
                            activityItems: [zipURL],
                            applicationActivities: nil
                        )
                        rootVC.present(activityVC, animated: true) {
                            onComplete()
                        }
                    }
                }
            } catch {
                print("Export failed: \(error)")
            }
        }
    }
}

#Preview {
    ImportExportView()
        .environmentObject(AppContainer.shared)
}
