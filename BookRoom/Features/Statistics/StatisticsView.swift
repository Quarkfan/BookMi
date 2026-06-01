import SwiftUI
import Charts

struct StatisticsView: View {
    @EnvironmentObject var appContainer: AppContainer

    @State private var totalBooks = 0
    @State private var yearlyStats: [(year: String, count: Int)] = []
    @State private var shelfStats: [(shelfName: String?, count: Int)] = []
    @State private var readingStats: [(status: String, count: Int)] = []
    @State private var duplicateStats: [(isbn: String, count: Int)] = []
    @State private var authorStats: [(name: String, count: Int)] = []
    @State private var publisherStats: [(name: String, count: Int)] = []
    @State private var channelStats: [(name: String?, count: Int)] = []
    @State private var tagStats: [(name: String, count: Int)] = []
    @State private var missingISBN = 0
    @State private var missingCover = 0
    @State private var missingShelf = 0
    @State private var isLoading = true

    var body: some View {
        NavigationView {
            if isLoading {
                ProgressView("加载中...")
            } else {
                ScrollView {
                    VStack(spacing: 20) {
                        // Overview Cards
                        overviewCards

                        // Reading Status Distribution
                        readingChart

                        // Yearly Trend
                        yearlyChart

                        // Shelf Distribution
                        shelfChart

                        // Author Top 10
                        authorChart

                        // Publisher Top 10
                        publisherChart

                        // Purchase Channel
                        channelChart

                        // Tag Cloud (Top 20)
                        tagChart

                        // Data Quality
                        dataQualityCards

                        // Duplicate Books
                        duplicateSection

                        Spacer(minLength: 40)
                    }
                    .padding()
                }
            }
        }
        .navigationTitle("统计")
        .task { await loadStatistics() }
    }

    // MARK: - Overview Cards

    private var overviewCards: some View {
        HStack(spacing: 16) {
            StatCard(title: "总藏书", value: "\(totalBooks)", icon: "books.vertical.fill", color: .blue)
            StatCard(title: "在读", value: "\(readingStats.first(where: { $0.status == "reading" })?.count ?? 0)", icon: "book.fill", color: .orange)
            StatCard(title: "已读", value: "\(readingStats.first(where: { $0.status == "finished" })?.count ?? 0)", icon: "checkmark.circle.fill", color: .green)
        }
    }

    // MARK: - Reading Status Chart

    private var readingChart: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("阅读状态分布")
                .font(.headline)

            if readingStats.isEmpty {
                Text("暂无数据")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Chart {
                    ForEach(readingStats, id: \.status) { item in
                        SectorMark(
                            angle: .value("数量", item.count),
                            innerRadius: .ratio(0.5),
                            angularInset: 1.5
                        )
                        .cornerRadius(4)
                        .annotation(position: .overlay) {
                            Text("\(item.count)")
                                .font(.caption)
                                .foregroundStyle(.white)
                        }
                    }
                }
                .frame(height: 200)
                .chartLegend(.visible)
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Yearly Trend Chart

    private var yearlyChart: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("年度新增藏书")
                .font(.headline)

            if yearlyStats.isEmpty {
                Text("暂无数据")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Chart(yearlyStats, id: \.year) { item in
                    BarMark(
                        x: .value("年份", item.year),
                        y: .value("数量", item.count)
                    )
                    .cornerRadius(4)
                }
                .frame(height: 200)
                .chartXAxisLabel("年份")
                .chartYAxisLabel("数量")
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Shelf Distribution

    private var shelfChart: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("按书柜分布")
                .font(.headline)

            if shelfStats.isEmpty {
                Text("暂无数据")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(shelfStats, id: \.shelfName) { item in
                    HStack {
                        Text(item.shelfName ?? "未分类")
                            .font(.subheadline)
                            .frame(width: 100, alignment: .leading)
                            .lineLimit(1)

                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Rectangle()
                                    .fill(Color.gray.opacity(0.2))
                                    .frame(height: 8)
                                Rectangle()
                                    .fill(Color.blue)
                                    .frame(
                                        width: geo.size.width * CGFloat(item.count) / CGFloat(max(totalBooks, 1)),
                                        height: 8
                                    )
                            }
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                        }

                        Text("\(item.count)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(width: 40, alignment: .trailing)
                    }
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Author Chart

    private var authorChart: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("作者 TOP 10")
                .font(.headline)

            if authorStats.isEmpty {
                Text("暂无数据")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(authorStats.prefix(10), id: \.name) { item in
                    HStack {
                        Text(item.name)
                            .font(.subheadline)
                            .frame(width: 120, alignment: .leading)
                            .lineLimit(1)

                        Text("\(item.count)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Publisher Chart

    private var publisherChart: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("出版社 TOP 10")
                .font(.headline)

            if publisherStats.isEmpty {
                Text("暂无数据")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(publisherStats.prefix(10), id: \.name) { item in
                    HStack {
                        Text(item.name)
                            .font(.subheadline)
                            .frame(width: 120, alignment: .leading)
                            .lineLimit(1)

                        Text("\(item.count)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Channel Chart

    private var channelChart: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("购买渠道分布")
                .font(.headline)

            if channelStats.isEmpty {
                Text("暂无数据")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Chart(channelStats, id: \.name) { item in
                    BarMark(
                        x: .value("渠道", item.name ?? "未设置"),
                        y: .value("数量", item.count)
                    )
                    .cornerRadius(4)
                }
                .frame(height: 150)
                .chartXAxis {
                    AxisMarks(values: .automatic) { value in
                        AxisValueLabel {
                            if let str = value.as(String.self) {
                                Text(str).font(.caption)
                            }
                        }
                    }
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Tag Chart

    private var tagChart: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("热门标签 TOP 20")
                .font(.headline)

            if tagStats.isEmpty {
                Text("暂无数据")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                FlowLayout(items: tagStats.prefix(20), id: \.name) { item in
                    TagChip(name: item.name, count: item.count)
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Data Quality

    private var dataQualityCards: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("数据质量")
                .font(.headline)

            HStack(spacing: 16) {
                QualityItemCard(label: "缺失 ISBN", count: missingISBN, total: totalBooks)
                QualityItemCard(label: "缺失封面", count: missingCover, total: totalBooks)
                QualityItemCard(label: "未设书柜", count: missingShelf, total: totalBooks)
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Duplicate Section

    private var duplicateSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("重复图书 (\(duplicateStats.count) 组)")
                .font(.headline)

            if duplicateStats.isEmpty {
                Text("没有重复图书")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(duplicateStats, id: \.isbn) { item in
                    HStack {
                        Text("ISBN: \(item.isbn)")
                            .font(.subheadline)
                            .lineLimit(1)
                        Spacer()
                        Text("\(item.count) 本")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Data Loading

    @MainActor
    private func loadStatistics() async {
        isLoading = true
        defer { isLoading = false }

        do {
            totalBooks = try await appContainer.bookRepo.fetchCount()
            yearlyStats = try await appContainer.bookRepo.countByYear()
            shelfStats = try await appContainer.bookRepo.countByShelf()
                .map { (shelfName: $0.shelfName, count: $0.count) }
            readingStats = try await appContainer.bookRepo.countByReadingStatus()
                .map { (status: $0.status, count: $0.count) }
            duplicateStats = try await appContainer.bookRepo.countDuplicatesByISBN()
            publisherStats = try await appContainer.bookRepo.countByPublisher()
                .map { (name: $0.name, count: $0.count) }
            channelStats = try await appContainer.bookRepo.countByPurchaseChannel()
                .map { (name: $0.name, count: $0.count) }

            // Author stats from all books
            let books = try await appContainer.bookRepo.fetchAll()
            var authorCounts: [String: Int] = [:]
            for book in books {
                if let json = book.authorsJSON,
                   let data = json.data(using: .utf8),
                   let authors = try? JSONDecoder().decode([String].self, from: data) {
                    for author in authors {
                        authorCounts[author, default: 0] += 1
                    }
                }
            }
            authorStats = authorCounts.sorted { $0.value > $1.value }.prefix(10).map { (name: $0.key, count: $0.value) }

            // Tag stats
            let allTags = try await appContainer.tagRepo.fetchAllWithCounts()
            tagStats = allTags.map { (name: $0.tag.name, count: $0.bookCount) }

            // Data quality
            missingISBN = try await appContainer.bookRepo.countMissingISBN()
            missingCover = try await appContainer.bookRepo.countMissingCovers()
            missingShelf = try await appContainer.bookRepo.countMissingShelf()
        } catch {
            print("Failed to load statistics: \(error)")
        }
    }
}

// MARK: - Stat Card

struct StatCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(color)
            Text(value)
                .font(.title2)
                .fontWeight(.bold)
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Quality Item Card

struct QualityItemCard: View {
    let label: String
    let count: Int
    let total: Int

    var percentage: Double {
        guard total > 0 else { return 0 }
        return Double(count) / Double(total) * 100
    }

    var body: some View {
        VStack(spacing: 4) {
            Text("\(count)")
                .font(.title2)
                .fontWeight(.bold)
                .foregroundStyle(percentage > 20 ? .red : percentage > 10 ? .orange : .green)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(Color(.tertiarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

// MARK: - Tag Chip

struct TagChip: View {
    let name: String
    let count: Int

    var body: some View {
        HStack(spacing: 4) {
            Text(name)
                .font(.caption)
            Text("(\(count))")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.blue.opacity(0.1))
        .foregroundStyle(.blue)
        .clipShape(Capsule())
    }
}

// MARK: - Flow Layout

struct FlowLayout<Data: RandomAccessCollection, ID: Hashable, Content: View>: View {
    let items: Data
    let id: KeyPath<Data.Element, ID>
    let content: (Data.Element) -> Content

    init(items: Data, id: KeyPath<Data.Element, ID>, @ViewBuilder content: @escaping (Data.Element) -> Content) {
        self.items = items
        self.id = id
        self.content = content
    }

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 80, maximum: 120))], spacing: 8) {
            ForEach(items, id: id) { item in
                content(item)
            }
        }
    }
}

#Preview {
    StatisticsView()
        .environmentObject(AppContainer.shared)
}
