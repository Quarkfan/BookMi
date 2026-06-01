import SwiftUI
import UniformTypeIdentifiers

struct BackupRestoreView: View {
    @EnvironmentObject var appContainer: AppContainer
    @State private var backups: [BackupInfo] = []
    @State private var isLoading = true
    @State private var showRestoreMode = false
    @State private var selectedBackup: BackupInfo?
    @State private var isCreatingBackup = false
    @State private var showSuccess = false
    @State private var successMessage = ""
    @State private var showError = false
    @State private var errorMessage = ""

    var body: some View {
        List {
            Section {
                Button {
                    createBackup()
                } label: {
                    HStack {
                        if isCreatingBackup {
                            ProgressView()
                        } else {
                            Image(systemName: "arrow.clockwise.circle.fill")
                                .foregroundColor(.accentColor)
                        }
                        Text("创建备份")
                    }
                }
                .disabled(isCreatingBackup)

                Text("备份包含：数据库 + 封面图片 + JSON 导出 + manifest")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if !backups.isEmpty {
                Section("本地备份") {
                    ForEach(backups) { backup in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(backup.fileName)
                                .font(.subheadline)
                            HStack {
                                Text(backup.date.formatted(date: .abbreviated, time: .shortened))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text(backup.sizeDescription)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .contextMenu {
                            Button {
                                selectedBackup = backup
                                showRestoreMode = true
                            } label: {
                                Label("恢复", systemImage: "arrow.counterclockwise")
                            }
                            Button(role: .destructive) {
                                deleteBackup(backup)
                            } label: {
                                Label("删除", systemImage: "trash")
                            }
                        }
                    }
                    .onDelete(perform: deleteBackup)
                }
            }
        }
        .navigationTitle("数据备份与恢复")
        .task { await loadBackups() }
        .sheet(item: $selectedBackup) { backup in
            RestoreModeSheet(backup: backup, onComplete: { mode in
                selectedBackup = nil
                restoreBackup(backup, mode: mode)
            })
        }
        .alert("成功", isPresented: $showSuccess) {
            Button("确定", role: .cancel) {}
        } message: {
            Text(successMessage)
        }
        .alert("错误", isPresented: $showError) {
            Button("确定", role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
    }

    @MainActor
    private func loadBackups() async {
        isLoading = true
        defer { isLoading = false }

        do {
            backups = try BackupService.listLocalBackups()
        } catch {
            print("Failed to list backups: \(error)")
        }
    }

    private func createBackup() {
        isCreatingBackup = true
        Task {
            do {
                let url = try await BackupService.createBackup()
                await MainActor.run {
                    isCreatingBackup = false
                    successMessage = "备份已创建：\(url.lastPathComponent)"
                    showSuccess = true
                    Task { await loadBackups() }
                }
            } catch {
                await MainActor.run {
                    isCreatingBackup = false
                    errorMessage = error.localizedDescription
                    showError = true
                }
            }
        }
    }

    private func restoreBackup(_ backup: BackupInfo, mode: RestoreMode) {
        Task {
            do {
                try await BackupService.restore(from: backup.url, mode: mode)
                await MainActor.run {
                    successMessage = "备份已恢复（\(modeName(mode))）"
                    showSuccess = true
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    showError = true
                }
            }
        }
    }

    private func deleteBackup(_ backup: BackupInfo) {
        do {
            try BackupService.deleteBackup(backup)
            Task { await loadBackups() }
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
    }

    private func modeName(_ mode: RestoreMode) -> String {
        switch mode {
        case .overwrite: return "覆盖"
        case .merge: return "合并"
        case .booksOnly: return "仅图书"
        }
    }
}

// MARK: - Restore Mode Sheet

struct RestoreModeSheet: View {
    let backup: BackupInfo
    let onComplete: (RestoreMode) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            Form {
                Section("选择恢复模式") {
                    Button {
                        onComplete(.overwrite)
                        dismiss()
                    } label: {
                        VStack(alignment: .leading) {
                            Text("覆盖恢复")
                                .font(.headline)
                            Text("清空当前数据，用备份替换")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .foregroundColor(.red)

                    Button {
                        onComplete(.merge)
                        dismiss()
                    } label: {
                        VStack(alignment: .leading) {
                            Text("合并恢复")
                                .font(.headline)
                            Text("保留当前数据，合并备份内容")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Button {
                        onComplete(.booksOnly)
                        dismiss()
                    } label: {
                        VStack(alignment: .leading) {
                            Text("仅导入图书")
                                .font(.headline)
                            Text("只导入图书、封面、标签、书柜")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Section("备份信息") {
                    HStack {
                        Text("文件名")
                        Spacer()
                        Text(backup.fileName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("大小")
                        Spacer()
                        Text(backup.sizeDescription)
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("时间")
                        Spacer()
                        Text(backup.date.formatted())
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("恢复备份")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("取消") { dismiss() }
                }
            }
        }
    }
}

#Preview {
    BackupRestoreView()
        .environmentObject(AppContainer.shared)
}
