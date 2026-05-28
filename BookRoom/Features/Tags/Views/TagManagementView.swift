import SwiftUI

struct TagManagementView: View {
    @EnvironmentObject var appContainer: AppContainer
    @State private var tags: [(tag: Tag, bookCount: Int)] = []
    @State private var isLoading = true
    @State private var showAddTag = false

    var body: some View {
        List {
            if isLoading {
                ProgressView()
            } else if tags.isEmpty {
                Text("还没有标签")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(tags, id: \.tag.id) { item in
                    HStack {
                        Circle()
                            .fill(Color(item.tag.color ?? "gray"))
                            .frame(width: 12, height: 12)
                        Text(item.tag.name)
                        Spacer()
                        Text("\(item.bookCount)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .onDelete(perform: deleteTag)
            }
        }
        .navigationTitle("标签管理")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    showAddTag = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .task { await loadTags() }
        .sheet(isPresented: $showAddTag) {
            TagEditView(onSave: { _ in
                showAddTag = false
                Task { await loadTags() }
            })
        }
    }

    @MainActor
    private func loadTags() async {
        isLoading = true
        defer { isLoading = false }

        do {
            tags = try appContainer.tagRepo.fetchAllWithCounts()
        } catch {
            print("Failed to load tags: \(error)")
        }
    }

    private func deleteTag(at offsets: IndexSet) {
        for index in offsets {
            let tag = tags[index].tag
            do {
                try appContainer.tagRepo.delete(id: tag.id)
            } catch {
                print("Failed to delete tag: \(error)")
            }
        }
        Task { await loadTags() }
    }
}

// MARK: - Tag Edit View

struct TagEditView: View {
    let tag: Tag?
    let onSave: (Tag) -> Void
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var appContainer: AppContainer

    @State private var name = ""
    @State private var color: String = "blue"

    let availableColors: [(name: String, color: Color)] = [
        ("blue", .blue), ("green", .green), ("red", .red),
        ("orange", .orange), ("purple", .purple), ("pink", .pink),
        ("yellow", .yellow), ("gray", .gray)
    ]

    init(tag: Tag? = nil, onSave: @escaping (Tag) -> Void) {
        self.tag = tag
        self.onSave = onSave
    }

    var body: some View {
        NavigationView {
            Form {
                Section("标签信息") {
                    TextField("标签名称 *", text: $name)
                }

                Section("颜色") {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 16) {
                            ForEach(availableColors, id: \.name) { item in
                                Button {
                                    color = item.name
                                } label: {
                                    Circle()
                                        .fill(item.color)
                                        .frame(width: 30, height: 30)
                                        .overlay(
                                            Circle()
                                                .stroke(color == item.name ? Color.primary : Color.clear, lineWidth: 2)
                                        )
                                }
                            }
                        }
                        .padding(.vertical, 8)
                    }
                }
            }
            .navigationTitle(tag == nil ? "新标签" : "编辑标签")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("保存") { saveTag() }
                        .disabled(name.isEmpty)
                }
            }
            .onAppear {
                if let tag {
                    name = tag.name
                    color = tag.color ?? "blue"
                }
            }
        }
    }

    private func saveTag() {
        let now = ISO8601DateFormatter().string(from: Date())
        var tagItem = tag ?? Tag(
            id: UUID().uuidString,
            name: name,
            color: color,
            sortOrder: 0,
            createdAt: now,
            updatedAt: now,
            deletedAt: nil
        )

        tagItem.name = name
        tagItem.color = color
        tagItem.updatedAt = now

        do {
            if tag != nil {
                tagItem = try appContainer.tagRepo.update(tagItem)
            } else {
                tagItem = try appContainer.tagRepo.insert(tagItem)
            }
            onSave(tagItem)
        } catch {
            print("Failed to save tag: \(error)")
        }
    }
}

// MARK: - Color Extension

extension Color {
    init(_ name: String) {
        switch name {
        case "blue": self = .blue
        case "green": self = .green
        case "red": self = .red
        case "orange": self = .orange
        case "purple": self = .purple
        case "pink": self = .pink
        case "yellow": self = .yellow
        default: self = .gray
        }
    }
}

#Preview {
    TagManagementView()
        .environmentObject(AppContainer.shared)
}
