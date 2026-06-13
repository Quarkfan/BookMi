import Foundation

// MARK: - URLSession with timeout

extension URLSession {
    static let bookLookup: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 8
        config.timeoutIntervalForResource = 12
        return URLSession(configuration: config)
    }()
}

protocol BookLookupProvider {
    var key: BookLookupProviderKey { get }
    var name: String { get }
    func lookup(isbn: String) async throws -> [BookMetadataDraft]
    func search(keyword: String) async throws -> [BookMetadataDraft]
}

enum BookLookupProviderKey: String, CaseIterable, Identifiable {
    case jisu
    case gugu
    case juhe
    case aiISBN = "ai_isbn"
    case openLibrary = "openlibrary"
    case googleBooks = "googlebooks"

    var id: String { rawValue }

    static let defaultOrder: [BookLookupProviderKey] = [.jisu, .gugu, .juhe, .aiISBN, .openLibrary, .googleBooks]

    var displayName: String {
        switch self {
        case .jisu: return "极速数据 ISBN"
        case .gugu: return "咕咕数据 ISBN"
        case .juhe: return "聚合数据 ISBN"
        case .aiISBN: return "AI ISBN 查询"
        case .openLibrary: return "Open Library"
        case .googleBooks: return "Google Books"
        }
    }

    var detail: String {
        switch self {
        case .jisu: return "中文书名与 ISBN"
        case .gugu: return "付费高覆盖源"
        case .juhe: return "ISBN 查询"
        case .aiISBN: return "模型调度受控检索工具"
        case .openLibrary, .googleBooks: return "海外兜底"
        }
    }
}

struct BookMetadataDraft: Codable, Identifiable {
    var id: String {
        isbn13
            ?? isbn10
            ?? [dataSource, title, publisher, publishedDate]
                .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .joined(separator: "|")
    }

    var title: String?
    var subtitle: String?
    var authors: [String]?
    var translators: [String]?
    var isbn10: String?
    var isbn13: String?
    var publisher: String?
    var publishedDate: String?
    var pageCount: Int?
    var price: String?
    var edition: String?
    var series: String?
    var binding: String?
    var language: String?
    var category: String?
    var summary: String?
    var coverURL: URL?
    var dataSource: String?
    var rawJSON: String?

    var hasContent: Bool { title != nil && !title!.isEmpty }

    func merging(with other: BookMetadataDraft) -> BookMetadataDraft {
        var m = self
        if m.title == nil || m.title!.isEmpty { m.title = other.title }
        if m.subtitle == nil { m.subtitle = other.subtitle }
        if m.authors == nil || m.authors!.isEmpty { m.authors = other.authors }
        if m.translators == nil { m.translators = other.translators }
        if m.isbn10 == nil { m.isbn10 = other.isbn10 }
        if m.isbn13 == nil { m.isbn13 = other.isbn13 }
        if m.publisher == nil { m.publisher = other.publisher }
        if m.publishedDate == nil { m.publishedDate = other.publishedDate }
        if m.pageCount == nil { m.pageCount = other.pageCount }
        if m.price == nil { m.price = other.price }
        if m.edition == nil { m.edition = other.edition }
        if m.series == nil { m.series = other.series }
        if m.binding == nil { m.binding = other.binding }
        if m.language == nil { m.language = other.language }
        if m.category == nil { m.category = other.category }
        if m.summary == nil { m.summary = other.summary }
        if m.coverURL == nil { m.coverURL = other.coverURL }
        return m
    }
}

struct AILookupCheckpoint {
    let acquired: [String]
    let missing: [String]
    let nextOpportunities: [String]
}

struct AILookupLiveStatus {
    let acquired: [String]
    let currentActivity: String
    let pending: [String]
    let workItems: [AILookupWorkItem]
    let canAcceptCurrentResult: Bool
    let currentDraft: BookMetadataDraft?
}

struct AILookupWorkItem: Identifiable {
    enum State {
        case pending
        case active
        case completed
    }

    let id: String
    let title: String
    let detail: String
    let state: State
}

enum BookLookupError: Error, LocalizedError {
    case networkError(String)
    case invalidResponse
    case notFound
    case rateLimited(String)

    var errorDescription: String? {
        switch self {
        case .networkError(let msg): return "网络错误：\(msg)"
        case .invalidResponse: return "接口返回格式异常"
        case .notFound: return "未找到"
        case .rateLimited(let provider): return "\(provider) 当前需要 API Key 或额度不可用"
        }
    }
}

extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}

/// Book lookup service combining multiple providers
final class BookLookupService {
    static var defaultProviders: [any BookLookupProvider] {
        var providers: [any BookLookupProvider] = []
        if SettingsManager.shared.isJisuISBNEnabled,
           let appKey = KeychainManager.shared.getJisuISBNAppKey(),
           !appKey.isEmpty {
            providers.append(JisuISBNProvider(appKey: appKey))
        }
        if SettingsManager.shared.isGuguISBNEnabled,
           let appKey = KeychainManager.shared.getGuguISBNAppKey(),
           !appKey.isEmpty {
            providers.append(GuguISBNProvider(appKey: appKey))
        }
        if SettingsManager.shared.isJuheISBNEnabled,
           let key = KeychainManager.shared.getJuheISBNAPIKey(),
           !key.isEmpty {
            providers.append(JuheISBNProvider(apiKey: key))
        }
        if SettingsManager.shared.isAIBookLookupEnabled,
           SettingsManager.shared.isAICapabilityEnabled,
           let baseURL = SettingsManager.shared.aiBaseURL,
           let model = SettingsManager.shared.aiModelName,
           let apiKey = KeychainManager.shared.getLLMAPIKey(),
           !baseURL.isEmpty, !model.isEmpty, !apiKey.isEmpty {
            providers.append(AIISBNProvider(baseURL: baseURL, apiKey: apiKey, model: model))
        }
        if SettingsManager.shared.isOverseasBookLookupEnabled {
            providers.append(OpenLibraryProvider())
            providers.append(GoogleBooksProvider())
        }
        let order = SettingsManager.shared.bookLookupProviderOrder
        return providers.sorted {
            (order.firstIndex(of: $0.key.rawValue) ?? .max) < (order.firstIndex(of: $1.key.rawValue) ?? .max)
        }
    }

    private let providers: [any BookLookupProvider]

    init(providers: [any BookLookupProvider]) {
        self.providers = providers
    }

    convenience init() {
        self.init(providers: Self.defaultProviders)
    }

    func lookup(
        isbn: String,
        onProviderChange: (@MainActor (String) -> Void)? = nil,
        onProgress: (@MainActor (String) -> Void)? = nil,
        onAICheckpoint: (@MainActor (AILookupCheckpoint) async -> Bool)? = nil,
        onAIStatus: (@MainActor (AILookupLiveStatus) -> Void)? = nil,
        shouldAcceptAIResult: (@MainActor () -> Bool)? = nil
    ) async -> [BookMetadataDraft] {
        for provider in providers {
            if Task.isCancelled { return [] }
            if let onProviderChange {
                await onProviderChange(provider.name)
            }
            await onProgress?("开始使用 \(provider.name)")

            do {
                let providerResults: [BookMetadataDraft]
                if let aiProvider = provider as? AIISBNProvider {
                    providerResults = try await aiProvider.lookup(
                        isbn: isbn,
                        onProgress: onProgress,
                        onCheckpoint: onAICheckpoint,
                        onStatus: onAIStatus,
                        shouldAcceptCurrent: shouldAcceptAIResult
                    )
                } else {
                    providerResults = try await provider.lookup(isbn: isbn)
                }
                if !providerResults.isEmpty {
                    await onProgress?("\(provider.name) 已找到图书信息")
                    return mergeResults(providerResults)
                }
                await onProgress?("\(provider.name) 未命中")
            } catch {
                print("[BookLookup][\(provider.name)] ISBN lookup failed: \(error)")
                await onProgress?("\(provider.name) 失败：\(error.localizedDescription)")
            }
        }

        await onProgress?("所有已启用数据源均未找到结果")
        return []
    }

    func search(
        keyword: String,
        onProviderChange: (@MainActor (String) -> Void)? = nil,
        onProgress: (@MainActor (String) -> Void)? = nil
    ) async -> SearchResult {
        var results: [BookMetadataDraft] = []
        var errors: [String: Error] = [:]
        let activeProviders = searchProviders(for: keyword)

        for provider in activeProviders {
            if Task.isCancelled { return .notFound }
            if let onProviderChange {
                await onProviderChange(provider.name)
            }
            await onProgress?("开始使用 \(provider.name)")

            do {
                let providerResults: [BookMetadataDraft]
                if let aiProvider = provider as? AIISBNProvider {
                    providerResults = try await aiProvider.search(keyword: keyword, onProgress: onProgress)
                } else {
                    providerResults = try await provider.search(keyword: keyword)
                }
                print("[BookLookup][\(provider.name)] Found \(providerResults.count) results for '\(keyword)'")
                if !providerResults.isEmpty {
                    await onProgress?("\(provider.name) 找到 \(providerResults.count) 个候选结果")
                    results.append(contentsOf: providerResults)
                    break
                }
                await onProgress?("\(provider.name) 未找到候选结果")
            } catch {
                if Task.isCancelled { return .notFound }
                print("[BookLookup][\(provider.name)] Search failed: \(error)")
                errors[provider.name] = error
            }

            if !BookRepository.normalizeISBN(keyword).isEmpty {
                // ISBN searches can benefit from multiple providers; title searches should stay snappy.
                continue
            }
        }

        let merged = mergeResults(results)
        print("[BookLookup] Total results: \(merged.count), Errors: \(errors.count)")

        if !merged.isEmpty {
            return .success(merged)
        } else if !errors.isEmpty {
            return .error(errors.map { "\($0.key): \($0.value.localizedDescription)" }.joined(separator: "\n"))
        } else if activeProviders.isEmpty {
            return .error("未启用可用的图书数据源。请到「设置 > 录入设置 > 图书数据源」配置聚合数据或咕咕数据。")
        } else {
            return .notFound
        }
    }

    enum SearchResult {
        case success([BookMetadataDraft])
        case error(String)
        case notFound
    }

    private func mergeResults(_ results: [BookMetadataDraft]) -> [BookMetadataDraft] {
        var grouped: [String: BookMetadataDraft] = [:]
        for result in results {
            let key = result.id
            if let existing = grouped[key] {
                grouped[key] = existing.merging(with: result)
            } else {
                grouped[key] = result
            }
        }
        return Array(grouped.values)
    }

    private func searchProviders(for keyword: String) -> [any BookLookupProvider] {
        let normalizedISBN = BookRepository.normalizeISBN(keyword)
        let isISBN = normalizedISBN.count == 10 || normalizedISBN.count == 13
        let containsCJK = keyword.unicodeScalars.contains { scalar in
            (0x4E00...0x9FFF).contains(Int(scalar.value))
        }

        guard containsCJK && !isISBN else { return providers }

        // Google Books is often slow or unavailable in China; don't let it block Chinese title search.
        return providers.filter { $0.name != "Google Books" }
    }
}

struct AIISBNProvider: BookLookupProvider {
    let key = BookLookupProviderKey.aiISBN
    let name = "AI ISBN 查询"
    private let harness: AIISBNAgentHarness

    init(baseURL: String, apiKey: String, model: String) {
        harness = AIISBNAgentHarness(baseURL: baseURL, apiKey: apiKey, model: model)
    }

    func lookup(isbn: String) async throws -> [BookMetadataDraft] {
        try await lookup(isbn: isbn, onProgress: nil)
    }

    func lookup(
        isbn: String,
        onProgress: (@MainActor (String) -> Void)?,
        onCheckpoint: (@MainActor (AILookupCheckpoint) async -> Bool)? = nil,
        onStatus: (@MainActor (AILookupLiveStatus) -> Void)? = nil,
        shouldAcceptCurrent: (@MainActor () -> Bool)? = nil
    ) async throws -> [BookMetadataDraft] {
        let normalizedISBN = BookRepository.normalizeISBN(isbn)
        guard normalizedISBN.count == 10 || normalizedISBN.count == 13 else { return [] }
        return try await harness.lookup(
            isbn: normalizedISBN,
            onProgress: onProgress,
            onCheckpoint: onCheckpoint,
            onStatus: onStatus,
            shouldAcceptCurrent: shouldAcceptCurrent
        ).map { [$0] } ?? []
    }

    func search(keyword: String) async throws -> [BookMetadataDraft] {
        let isbn = BookRepository.normalizeISBN(keyword)
        if isbn.count == 10 || isbn.count == 13 {
            return try await lookup(isbn: isbn)
        }
        return try await search(keyword: keyword, onProgress: nil)
    }

    func search(
        keyword: String,
        onProgress: (@MainActor (String) -> Void)?
    ) async throws -> [BookMetadataDraft] {
        let isbn = BookRepository.normalizeISBN(keyword)
        if isbn.count == 10 || isbn.count == 13 {
            return try await lookup(isbn: isbn, onProgress: onProgress)
        }
        return try await harness.search(keyword: keyword, onProgress: onProgress)
    }
}

private struct AIISBNAgentHarness {
    private let baseURL: String
    private let apiKey: String
    private let model: String
    private let checkpointInterval: TimeInterval = 45
    private let emergencyMaxTurns = 100
    private let maxToolOutputCharacters = 14_000

    init(baseURL: String, apiKey: String, model: String) {
        self.baseURL = baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        self.apiKey = apiKey
        self.model = model
    }

    func lookup(
        isbn: String,
        onProgress: (@MainActor (String) -> Void)?,
        onCheckpoint: (@MainActor (AILookupCheckpoint) async -> Bool)?,
        onStatus: (@MainActor (AILookupLiveStatus) -> Void)?,
        shouldAcceptCurrent: (@MainActor () -> Bool)?
    ) async throws -> BookMetadataDraft? {
        guard let endpoint = URL(string: "\(baseURL)/chat/completions") else { return nil }
        var messages: [[String: Any]] = [
            [
                "role": "system",
                "content": """
                You are the reasoning engine inside a book metadata agent harness. Investigate the exact ISBN using the available tools.
                Never rely on memory, never guess, and never treat search snippets as conclusive when a source page can be fetched.
                Core bibliographic metadata is the priority. As soon as the exact ISBN and title are supported by evidence, submit the result.
                A cover is optional: never delay or reject otherwise valid metadata because a cover cannot be found.
                Metadata fields may and should come from different reliable sources. Call record_metadata_evidence whenever a source adds useful fields.
                Once core metadata is recorded, run a separate cover subtask: search for and inspect up to three distinct promising cover candidates.
                A useful summary is an important field, not an optional afterthought. After core metadata is verified, actively search publisher,
                bookstore, library, or review pages for a reliable synopsis. Synthesize a concise factual summary from evidence and record it.
                Never invent plot details. Only finish without a summary after genuinely attempting a dedicated summary search.
                Prefer Chinese-accessible sources. Cross-check title, author, publisher and edition.
                Use report_progress to briefly tell the user what you found and what you will try next.
                If a promising cover exists, use inspect_image so your multimodal vision can judge whether it matches the book.
                Finish only by calling submit_book_result. If the exact ISBN cannot be verified, call submit_book_result with found=false.
                """
            ],
            [
                "role": "user",
                "content": "Investigate exact ISBN \(isbn) and submit the best evidence-backed metadata."
            ]
        ]
        var verifiedImages = Set<String>()
        var evidenceURLs = Set<String>()
        var hasISBNEvidence = false
        var accumulatedMetadata: [String: Any] = [:]
        var inspectedCoverCandidates = Set<String>()
        var summarySearchRequested = false
        var nextCheckpoint = Date().addingTimeInterval(checkpointInterval)

        await onProgress?("AI Agent 已启动，将核验 ISBN \(isbn)")
        await publishStatus(
            metadata: accumulatedMetadata,
            activity: "正在核验 ISBN",
            inspectedCoverCount: 0,
            hasISBNEvidence: false,
            requestedISBN: isbn,
            verifiedImages: verifiedImages,
            evidenceURLs: evidenceURLs,
            onStatus: onStatus
        )
        for turn in 1...emergencyMaxTurns {
            try Task.checkCancellation()
            if await shouldAcceptCurrent?() == true,
               let current = makeDraft(
                   accumulatedMetadata,
                   requestedISBN: isbn,
                   verifiedImages: verifiedImages,
                   evidenceURLs: evidenceURLs,
                   hasISBNEvidence: hasISBNEvidence
               ) {
                await onProgress?("已按你的选择固化当前信息")
                return current
            }
            if Date() >= nextCheckpoint, let onCheckpoint {
                let checkpoint = makeCheckpoint(
                    accumulatedMetadata,
                    inspectedCoverCount: inspectedCoverCandidates.count,
                    hasISBNEvidence: hasISBNEvidence
                )
                await onProgress?("已到阶段检查点，等待你决定是否继续")
                let shouldContinue = await onCheckpoint(checkpoint)
                if !shouldContinue {
                    if let current = makeDraft(
                        accumulatedMetadata,
                        requestedISBN: isbn,
                        verifiedImages: verifiedImages,
                        evidenceURLs: evidenceURLs,
                        hasISBNEvidence: hasISBNEvidence
                    ) {
                        await onProgress?("已按你的选择使用当前获得的信息")
                        return current
                    }
                    await onProgress?("当前信息不足以确认图书，已停止调查")
                    return nil
                }
                nextCheckpoint = Date().addingTimeInterval(checkpointInterval)
                await onProgress?("继续调查下一阶段")
            }

            await onProgress?("AI 第 \(turn) 轮：正在分析证据")
            await publishStatus(
                metadata: accumulatedMetadata,
                activity: "正在分析现有证据并决定下一步",
                inspectedCoverCount: inspectedCoverCandidates.count,
                hasISBNEvidence: hasISBNEvidence,
                requestedISBN: isbn,
                verifiedImages: verifiedImages,
                evidenceURLs: evidenceURLs,
                onStatus: onStatus
            )
            let message = try await requestAssistantMessage(endpoint: endpoint, messages: messages)
            messages.append(message)
            guard let toolCalls = message["tool_calls"] as? [[String: Any]], !toolCalls.isEmpty else {
                if let summary = cleanString(message["content"]) {
                    await onProgress?("模型回复：\(summary.prefixString(180))")
                }
                if cleanString(accumulatedMetadata["summary"]) == nil,
                   !summarySearchRequested,
                   makeDraft(
                       accumulatedMetadata,
                       requestedISBN: isbn,
                       verifiedImages: verifiedImages,
                       evidenceURLs: evidenceURLs,
                       hasISBNEvidence: hasISBNEvidence
                   ) != nil {
                    summarySearchRequested = true
                    await onProgress?("基本信息已保留，模型提前停止；继续执行简介补全")
                    messages.append([
                        "role": "user",
                        "content": "Do not finish yet. Core metadata is retained, but summary is missing. Search specifically for a reliable synopsis using ISBN, title, author and publisher; fetch evidence pages and record the summary. Do not invent details."
                    ])
                    continue
                }
                if let fallback = makeDraft(
                    accumulatedMetadata,
                    requestedISBN: isbn,
                    verifiedImages: verifiedImages,
                    evidenceURLs: evidenceURLs,
                    hasISBNEvidence: hasISBNEvidence
                ) {
                    await onProgress?("模型未正式提交，但已保留并接受累积书目信息")
                    return fallback
                }
                await onProgress?("模型未返回工具调用，接口可能不支持 Tool Calling")
                throw BookLookupError.invalidResponse
            }

            for call in toolCalls {
                guard let callID = call["id"] as? String,
                      let function = call["function"] as? [String: Any],
                      let toolName = function["name"] as? String else { continue }
                let arguments = decodeArguments(function["arguments"])

                if toolName == "report_progress" {
                    let message = cleanString(arguments["message"]) ?? "继续调查"
                    await onProgress?("AI：\(message)")
                    await publishStatus(
                        metadata: accumulatedMetadata,
                        activity: message,
                        inspectedCoverCount: inspectedCoverCandidates.count,
                        hasISBNEvidence: hasISBNEvidence,
                        requestedISBN: isbn,
                        verifiedImages: verifiedImages,
                        evidenceURLs: evidenceURLs,
                        onStatus: onStatus
                    )
                    messages.append([
                        "role": "tool",
                        "tool_call_id": callID,
                        "content": #"{"acknowledged":true}"#
                    ])
                    continue
                }

                if toolName == "record_metadata_evidence" {
                    mergeMetadata(arguments, into: &accumulatedMetadata)
                    collectSubmittedSources(from: arguments, into: &evidenceURLs)
                    if submittedISBN(arguments, matches: isbn) {
                        hasISBNEvidence = true
                    }
                    await onProgress?("AI 已累积字段：\(recordedFieldSummary(arguments))")
                    await publishStatus(
                        metadata: accumulatedMetadata,
                        activity: "正在寻找尚缺少的信息",
                        inspectedCoverCount: inspectedCoverCandidates.count,
                        hasISBNEvidence: hasISBNEvidence,
                        requestedISBN: isbn,
                        verifiedImages: verifiedImages,
                        evidenceURLs: evidenceURLs,
                        onStatus: onStatus
                    )
                    messages.append([
                        "role": "tool",
                        "tool_call_id": callID,
                        "content": encodeToolOutput([
                            "recorded": true,
                            "accumulated_fields": accumulatedMetadata.keys.sorted()
                        ])
                    ])
                    continue
                }

                if toolName == "submit_book_result" {
                    var combined = accumulatedMetadata
                    mergeMetadata(arguments, into: &combined)
                    accumulatedMetadata = combined

                    if cleanString(combined["summary"]) == nil, !summarySearchRequested {
                        summarySearchRequested = true
                        await onProgress?("基本信息已确认，开始独立补全图书简介")
                        messages.append([
                            "role": "tool",
                            "tool_call_id": callID,
                            "content": """
                            {"accepted_core_metadata":true,"finish_deferred":true,"next_task":"Search specifically for a reliable synopsis/summary. Use the verified title, author, publisher, and ISBN in queries. Fetch source pages, then call record_metadata_evidence with summary and sources. Do not invent details. After a genuine attempt, submit again even if no summary is available."}
                            """
                        ])
                        messages.append([
                            "role": "user",
                            "content": "Core metadata is safely retained. Now perform the dedicated summary enrichment task before final submission."
                        ])
                        continue
                    }

                    await onProgress?("AI 正在提交并校验最终结果")
                    let result = makeDraft(
                        combined,
                        requestedISBN: isbn,
                        verifiedImages: verifiedImages,
                        evidenceURLs: evidenceURLs,
                        hasISBNEvidence: hasISBNEvidence
                    )
                    if result != nil, cleanString(combined["summary"]) != nil {
                        await onProgress?("书目信息与简介校验通过；封面可稍后补充")
                    } else {
                        await onProgress?(result == nil ? "AI 提交结果未通过书名、ISBN 或来源校验" : "简介补全未命中，已保留完整基本信息")
                    }
                    return result
                }

                await onProgress?("AI 调用工具：\(toolDisplayName(toolName, arguments: arguments))")
                await publishStatus(
                    metadata: accumulatedMetadata,
                    activity: toolDisplayName(toolName, arguments: arguments),
                    inspectedCoverCount: inspectedCoverCandidates.count,
                    hasISBNEvidence: hasISBNEvidence,
                    requestedISBN: isbn,
                    verifiedImages: verifiedImages,
                    evidenceURLs: evidenceURLs,
                    onStatus: onStatus
                )
                let output = await runTool(named: toolName, arguments: arguments, verifiedImages: &verifiedImages)
                collectEvidence(
                    from: output,
                    toolName: toolName,
                    isbn: isbn,
                    urls: &evidenceURLs,
                    hasISBNEvidence: &hasISBNEvidence
                )
                await onProgress?("工具结果：\(toolResultSummary(output))")
                await publishStatus(
                    metadata: accumulatedMetadata,
                    activity: "已获得工具结果，正在整理可用字段",
                    inspectedCoverCount: inspectedCoverCandidates.count,
                    hasISBNEvidence: hasISBNEvidence,
                    requestedISBN: isbn,
                    verifiedImages: verifiedImages,
                    evidenceURLs: evidenceURLs,
                    onStatus: onStatus
                )
                messages.append([
                    "role": "tool",
                    "tool_call_id": callID,
                    "content": encodeToolOutput(output)
                ])
                if toolName == "inspect_image",
                   output["valid"] as? Bool == true,
                   let imageURL = cleanString(output["url"]) {
                    inspectedCoverCandidates.insert(imageURL)
                    messages.append(multimodalImageMessage(url: imageURL, isbn: isbn))
                    await onProgress?("已将第 \(inspectedCoverCandidates.count) 个候选封面交给多模态模型查看")
                }
            }
        }
        if let fallback = makeDraft(
            accumulatedMetadata,
            requestedISBN: isbn,
            verifiedImages: verifiedImages,
            evidenceURLs: evidenceURLs,
            hasISBNEvidence: hasISBNEvidence
        ) {
            await onProgress?("触发安全循环保护，已接受累积书目信息；封面可稍后补充")
            return fallback
        }
        await onProgress?("触发安全循环保护，仍未获得可确认的信息")
        return nil
    }

    func search(
        keyword: String,
        onProgress: (@MainActor (String) -> Void)?
    ) async throws -> [BookMetadataDraft] {
        guard let endpoint = URL(string: "\(baseURL)/chat/completions") else { return [] }
        var messages: [[String: Any]] = [
            [
                "role": "system",
                "content": """
                You are a book search agent. Search for books matching the user's title, author, or keyword.
                Prefer Chinese-accessible sources. Use search_web and fetch_url to verify candidates.
                Return up to 8 distinct likely editions. Every candidate must have a title and a verified ISBN-10 or ISBN-13.
                Do not invent ISBNs or metadata. Briefly report progress, then finish with submit_search_results.
                """
            ],
            ["role": "user", "content": "Search books matching: \(keyword)"]
        ]
        var verifiedImages = Set<String>()
        await onProgress?("AI 搜书 Agent 已启动，正在理解关键词「\(keyword)」")

        for turn in 1...10 {
            try Task.checkCancellation()
            await onProgress?("AI 搜书第 \(turn) 轮：正在检索和核对候选版本")
            let message = try await requestAssistantMessage(endpoint: endpoint, messages: messages)
            messages.append(message)
            guard let toolCalls = message["tool_calls"] as? [[String: Any]], !toolCalls.isEmpty else {
                await onProgress?("AI 搜书未提交候选结果")
                return []
            }

            for call in toolCalls {
                guard let callID = call["id"] as? String,
                      let function = call["function"] as? [String: Any],
                      let toolName = function["name"] as? String else { continue }
                let arguments = decodeArguments(function["arguments"])

                if toolName == "report_progress" {
                    await onProgress?("AI：\(cleanString(arguments["message"]) ?? "继续搜索")")
                    messages.append(["role": "tool", "tool_call_id": callID, "content": #"{"acknowledged":true}"#])
                    continue
                }

                if toolName == "submit_search_results" {
                    let drafts = searchDrafts(from: arguments)
                    await onProgress?("AI 已整理并核验 \(drafts.count) 个候选版本")
                    return drafts
                }

                await onProgress?("AI 调用工具：\(toolDisplayName(toolName, arguments: arguments))")
                let output = await runTool(named: toolName, arguments: arguments, verifiedImages: &verifiedImages)
                await onProgress?("工具结果：\(toolResultSummary(output))")
                messages.append([
                    "role": "tool",
                    "tool_call_id": callID,
                    "content": encodeToolOutput(output)
                ])
            }
        }
        await onProgress?("AI 搜书达到安全轮次上限")
        return []
    }

    private func searchDrafts(from payload: [String: Any]) -> [BookMetadataDraft] {
        guard let candidates = payload["candidates"] as? [[String: Any]] else { return [] }
        return candidates.compactMap { candidate in
            guard let title = cleanString(candidate["title"]) else { return nil }
            let isbn10 = cleanString(candidate["isbn10"]).map(BookRepository.normalizeISBN)
            let isbn13 = cleanString(candidate["isbn13"]).map(BookRepository.normalizeISBN)
            guard isbn10?.count == 10 || isbn13?.count == 13 else { return nil }
            return BookMetadataDraft(
                title: title,
                authors: cleanStringArray(candidate["authors"]),
                isbn10: isbn10?.count == 10 ? isbn10 : nil,
                isbn13: isbn13?.count == 13 ? isbn13 : nil,
                publisher: cleanString(candidate["publisher"]),
                publishedDate: cleanString(candidate["publishedDate"]),
                coverURL: cleanString(candidate["coverURL"]).flatMap(safePublicURL),
                dataSource: "ai_search"
            )
        }
    }

    private func publishStatus(
        metadata: [String: Any],
        activity: String,
        inspectedCoverCount: Int,
        hasISBNEvidence: Bool,
        requestedISBN: String,
        verifiedImages: Set<String>,
        evidenceURLs: Set<String>,
        onStatus: (@MainActor (AILookupLiveStatus) -> Void)?
    ) async {
        guard let onStatus else { return }
        let labels: [(String, String)] = [
            ("title", "书名"), ("authors", "作者"), ("publisher", "出版社"),
            ("publishedDate", "出版日期"), ("pageCount", "页数"), ("price", "定价"),
            ("edition", "版本"), ("binding", "装帧"), ("category", "分类"),
            ("summary", "简介"), ("coverURL", "封面")
        ]
        var acquired = labels.compactMap { key, label -> String? in
            guard let value = metadata[key] else { return nil }
            if let values = value as? [String], !values.isEmpty {
                return "\(label)：\(values.joined(separator: " / "))"
            }
            if let string = value as? String, !string.isEmpty {
                let compact = string.count > 70 ? String(string.prefix(70)) + "…" : string
                return "\(label)：\(compact)"
            }
            if let number = value as? Int { return "\(label)：\(number)" }
            return nil
        }
        if hasISBNEvidence { acquired.insert("ISBN：已核验", at: 0) }
        var pending = labels.compactMap { metadata[$0.0] == nil ? $0.1 : nil }
        if metadata["coverURL"] == nil, inspectedCoverCount > 0 {
            pending = pending.map { $0 == "封面" ? "封面（已尝试 \(inspectedCoverCount) 张）" : $0 }
        }
        let activeKey = activeWorkItemKey(for: activity, metadata: metadata, hasISBNEvidence: hasISBNEvidence)
        let workDefinitions: [(String, String, Bool, String)] = [
            ("isbn", "核验 ISBN", hasISBNEvidence, hasISBNEvidence ? "已确认与目标 ISBN 匹配" : "确认版本与来源"),
            ("title", "获取书名", metadata["title"] != nil, compactMetadataValue(metadata["title"]) ?? "查找准确书名"),
            ("authors", "获取作者", metadata["authors"] != nil, compactMetadataValue(metadata["authors"]) ?? "核对作者信息"),
            ("publisher", "获取出版社", metadata["publisher"] != nil, compactMetadataValue(metadata["publisher"]) ?? "核对出版版本"),
            ("details", "补充出版信息", hasAnyMetadata(metadata, keys: ["publishedDate", "pageCount", "price", "edition", "binding"]), detailSummary(metadata, keys: ["publishedDate", "pageCount", "price", "edition", "binding"]) ?? "日期、页数、定价与装帧"),
            ("summary", "查找图书简介", metadata["summary"] != nil, compactMetadataValue(metadata["summary"]) ?? "寻找可靠简介来源"),
            ("cover", "匹配并检查封面", metadata["coverURL"] != nil, metadata["coverURL"] != nil ? "已找到可用封面" : inspectedCoverCount > 0 ? "已检查 \(inspectedCoverCount) 张候选图" : "搜索并由多模态模型检查")
        ]
        let workItems = workDefinitions.map { key, title, completed, detail in
            AILookupWorkItem(
                id: key,
                title: title,
                detail: detail,
                state: completed ? .completed : (key == activeKey ? .active : .pending)
            )
        }
        await onStatus(AILookupLiveStatus(
            acquired: acquired,
            currentActivity: activity,
            pending: pending,
            workItems: workItems,
            canAcceptCurrentResult: metadata["title"] != nil && hasISBNEvidence,
            currentDraft: makeDraft(
                metadata,
                requestedISBN: requestedISBN,
                verifiedImages: verifiedImages,
                evidenceURLs: evidenceURLs,
                hasISBNEvidence: hasISBNEvidence
            )
        ))
    }

    private func activeWorkItemKey(
        for activity: String,
        metadata: [String: Any],
        hasISBNEvidence: Bool
    ) -> String {
        let value = activity.lowercased()
        if value.contains("封面") || value.contains("图片") || value.contains("image") { return "cover" }
        if value.contains("简介") || value.contains("summary") || value.contains("synopsis") { return "summary" }
        if value.contains("出版社") || value.contains("publisher") || value.contains("版本") { return "publisher" }
        if value.contains("作者") || value.contains("author") { return "authors" }
        if value.contains("书名") || value.contains("title") { return "title" }
        if value.contains("isbn") && !hasISBNEvidence { return "isbn" }
        if !hasISBNEvidence { return "isbn" }
        if metadata["title"] == nil { return "title" }
        if metadata["authors"] == nil { return "authors" }
        if metadata["publisher"] == nil { return "publisher" }
        return "details"
    }

    private func hasAnyMetadata(_ metadata: [String: Any], keys: [String]) -> Bool {
        keys.contains { metadata[$0] != nil }
    }

    private func detailSummary(_ metadata: [String: Any], keys: [String]) -> String? {
        let values = keys.compactMap { compactMetadataValue(metadata[$0]) }
        return values.isEmpty ? nil : values.joined(separator: " · ")
    }

    private func compactMetadataValue(_ value: Any?) -> String? {
        if let values = value as? [String], !values.isEmpty {
            return values.joined(separator: " / ").prefixString(60)
        }
        if let string = value as? String, !string.isEmpty {
            return string.prefixString(60)
        }
        if let number = value as? Int { return String(number) }
        return nil
    }

    private func makeCheckpoint(
        _ metadata: [String: Any],
        inspectedCoverCount: Int,
        hasISBNEvidence: Bool
    ) -> AILookupCheckpoint {
        let labels: [(String, String)] = [
            ("title", "书名"), ("authors", "作者"), ("publisher", "出版社"),
            ("publishedDate", "出版日期"), ("pageCount", "页数"), ("price", "定价"),
            ("edition", "版本"), ("binding", "装帧"), ("category", "分类"),
            ("summary", "简介"), ("coverURL", "封面")
        ]
        let acquired = labels.compactMap { key, label in
            metadata[key] == nil ? nil : label
        } + (hasISBNEvidence ? ["ISBN 已核验"] : [])
        let missing = labels.compactMap { key, label in
            metadata[key] == nil ? label : nil
        }
        var opportunities: [String] = []
        if metadata["summary"] == nil { opportunities.append("继续寻找并归纳可靠简介") }
        if metadata["coverURL"] == nil { opportunities.append("继续寻找并查看候选封面（已尝试 \(inspectedCoverCount) 张）") }
        if metadata["publisher"] == nil || metadata["publishedDate"] == nil {
            opportunities.append("补充版本、出版社和出版日期")
        }
        if opportunities.isEmpty { opportunities.append("交叉核验现有字段并寻找更多细节") }
        return AILookupCheckpoint(acquired: acquired, missing: missing, nextOpportunities: opportunities)
    }

    private func toolDisplayName(_ name: String, arguments: [String: Any]) -> String {
        switch name {
        case "search_web": return "百度搜索「\(cleanString(arguments["query"]) ?? "未知关键词")」"
        case "fetch_url": return "读取网页 \(cleanString(arguments["url"]) ?? "")"
        case "lookup_openlibrary": return "查询 Open Library"
        case "inspect_image": return "查看并判断候选封面"
        case "record_metadata_evidence": return "记录已确认的部分书目信息"
        default: return name
        }
    }

    private func toolResultSummary(_ output: [String: Any]) -> String {
        if let error = cleanString(output["error"]) { return "失败，\(error)" }
        if let valid = output["valid"] as? Bool { return valid ? "图片有效" : "图片无效" }
        if let found = output["found"] as? Bool { return found ? "找到候选信息" : "未找到" }
        if let links = output["links"] as? [String] { return "获得 \(links.count) 个可继续访问的链接" }
        if output["text"] != nil { return "已读取网页内容" }
        return "已完成"
    }

    private func requestAssistantMessage(endpoint: URL, messages: [[String: Any]]) async throws -> [String: Any] {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = TimeInterval(SettingsManager.shared.aiTimeout)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "model": model,
            "temperature": 0,
            "max_tokens": SettingsManager.shared.aiMaxTokens,
            "messages": messages,
            "tools": Self.tools,
            "tool_choice": "auto"
        ])

        let (data, response) = try await URLSession.shared.data(for: request)
        try validateHTTPResponse(response, provider: "AI ISBN Agent", data: data)
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = root["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any] else {
            throw BookLookupError.invalidResponse
        }
        var sanitized: [String: Any] = [
            "role": "assistant",
            "content": message["content"] ?? NSNull()
        ]
        if let toolCalls = message["tool_calls"] {
            sanitized["tool_calls"] = toolCalls
        }
        return sanitized
    }

    private func runTool(
        named name: String,
        arguments: [String: Any],
        verifiedImages: inout Set<String>
    ) async -> [String: Any] {
        do {
            switch name {
            case "search_web":
                guard let query = cleanString(arguments["query"]) else { return ["error": "query is required"] }
                return try await searchWeb(query: query)
            case "fetch_url":
                guard let value = cleanString(arguments["url"]), let url = safePublicURL(value) else {
                    return ["error": "Only public http/https URLs are allowed"]
                }
                return try await fetchPage(url)
            case "lookup_openlibrary":
                guard let isbn = cleanString(arguments["isbn"]) else { return ["error": "isbn is required"] }
                return try await lookupOpenLibrary(isbn: isbn)
            case "inspect_image":
                guard let value = cleanString(arguments["url"]), let url = safePublicURL(value) else {
                    return ["error": "Only public http/https URLs are allowed"]
                }
                let result = try await verifyImage(url)
                if result["valid"] as? Bool == true { verifiedImages.insert(url.absoluteString) }
                return result
            default:
                return ["error": "Unknown tool \(name)"]
            }
        } catch {
            return ["error": error.localizedDescription]
        }
    }

    private func searchWeb(query: String) async throws -> [String: Any] {
        var components = URLComponents(string: "https://www.baidu.com/s")!
        components.queryItems = [URLQueryItem(name: "wd", value: query)]
        guard let url = components.url else { throw BookLookupError.invalidResponse }
        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.bookLookup.data(for: request)
        try validateHTTPResponse(response, provider: "百度搜索", data: data)
        return [
            "search_url": url.absoluteString,
            "text": visibleText(data).prefixString(maxToolOutputCharacters),
            "links": extractPublicLinks(data, baseURL: url)
        ]
    }

    private func fetchPage(_ url: URL) async throws -> [String: Any] {
        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.bookLookup.data(for: request)
        try validateHTTPResponse(response, provider: url.host ?? "网页", data: data)
        guard data.count <= 500_000 else { return ["url": url.absoluteString, "error": "Page is too large"] }
        return ["url": url.absoluteString, "text": visibleText(data).prefixString(maxToolOutputCharacters)]
    }

    private func lookupOpenLibrary(isbn: String) async throws -> [String: Any] {
        let normalized = BookRepository.normalizeISBN(isbn)
        let results = try await OpenLibraryProvider().lookup(isbn: normalized)
        guard let result = results.first else { return ["found": false] }
        let data = try JSONEncoder().encode(result)
        var payload = (try JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
        payload["found"] = true
        payload["source_url"] = "https://openlibrary.org/isbn/\(normalized)"
        return payload
    }

    private func verifyImage(_ url: URL) async throws -> [String: Any] {
        var request = URLRequest(url: url)
        request.setValue("bytes=0-65535", forHTTPHeaderField: "Range")
        request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.bookLookup.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) || http.statusCode == 206 else {
            return ["valid": false, "url": url.absoluteString]
        }
        let type = http.value(forHTTPHeaderField: "Content-Type")?.lowercased() ?? ""
        let magic = data.starts(with: [0xFF, 0xD8, 0xFF])
            || data.starts(with: [0x89, 0x50, 0x4E, 0x47])
            || data.starts(with: [0x47, 0x49, 0x46, 0x38])
            || data.starts(with: [0x52, 0x49, 0x46, 0x46])
        return ["valid": type.hasPrefix("image/") || magic, "url": url.absoluteString, "content_type": type]
    }

    private func makeDraft(
        _ payload: [String: Any],
        requestedISBN: String,
        verifiedImages: Set<String>,
        evidenceURLs: Set<String>,
        hasISBNEvidence: Bool
    ) -> BookMetadataDraft? {
        guard payload["found"] as? Bool == true,
              let title = cleanString(payload["title"]) else { return nil }

        let submittedSources = (payload["sources"] as? [[String: Any]]) ?? []
        let submittedURLs = submittedSources.compactMap { source in
            cleanString(source["url"]).flatMap(safePublicURL)?.absoluteString
        }
        guard !submittedURLs.isEmpty || !evidenceURLs.isEmpty else { return nil }

        var isbn10 = cleanString(payload["isbn10"]).map(BookRepository.normalizeISBN)
        var isbn13 = cleanString(payload["isbn13"]).map(BookRepository.normalizeISBN)
        guard isbn10 == requestedISBN || isbn13 == requestedISBN || hasISBNEvidence else { return nil }
        if isbn10 == nil, isbn13 == nil {
            if requestedISBN.count == 10 { isbn10 = requestedISBN }
            if requestedISBN.count == 13 { isbn13 = requestedISBN }
        }
        let coverValue = cleanString(payload["coverURL"])
        let coverURL = coverValue.flatMap { verifiedImages.contains($0) ? URL(string: $0) : nil }
        var storedPayload = payload
        if submittedURLs.isEmpty {
            storedPayload["sources"] = evidenceURLs.sorted().map { ["url": $0, "title": "Agent 工具证据"] }
        }
        let rawJSON = (try? JSONSerialization.data(withJSONObject: storedPayload, options: [.sortedKeys]))
            .flatMap { String(data: $0, encoding: .utf8) }

        return BookMetadataDraft(
            title: title,
            subtitle: cleanString(payload["subtitle"]),
            authors: cleanStringArray(payload["authors"]),
            translators: cleanStringArray(payload["translators"]),
            isbn10: isbn10,
            isbn13: isbn13,
            publisher: cleanString(payload["publisher"]),
            publishedDate: cleanString(payload["publishedDate"]),
            pageCount: cleanInteger(payload["pageCount"]),
            price: cleanString(payload["price"]),
            edition: cleanString(payload["edition"]),
            series: cleanString(payload["series"]),
            binding: cleanString(payload["binding"]),
            language: cleanString(payload["language"]),
            category: cleanString(payload["category"]),
            summary: cleanString(payload["summary"]),
            coverURL: coverURL,
            dataSource: "ai_isbn",
            rawJSON: rawJSON
        )
    }

    private func mergeMetadata(_ source: [String: Any], into target: inout [String: Any]) {
        let arrayFields = Set(["authors", "translators", "sources"])
        let ignored = Set(["found", "note"])
        for (key, value) in source where !ignored.contains(key) && !(value is NSNull) {
            if arrayFields.contains(key),
               let incoming = value as? [Any] {
                let existing = target[key] as? [Any] ?? []
                var merged = existing
                for item in incoming where !merged.contains(where: { String(describing: $0) == String(describing: item) }) {
                    merged.append(item)
                }
                if !merged.isEmpty { target[key] = merged }
            } else if let string = value as? String {
                if !string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    target[key] = string
                }
            } else {
                target[key] = value
            }
        }
        target["found"] = true
    }

    private func collectSubmittedSources(from payload: [String: Any], into urls: inout Set<String>) {
        guard let sources = payload["sources"] as? [[String: Any]] else { return }
        for source in sources {
            if let value = cleanString(source["url"]), safePublicURL(value) != nil {
                urls.insert(value)
            }
        }
    }

    private func submittedISBN(_ payload: [String: Any], matches requestedISBN: String) -> Bool {
        ["isbn10", "isbn13"].contains { key in
            cleanString(payload[key]).map(BookRepository.normalizeISBN) == requestedISBN
        }
    }

    private func recordedFieldSummary(_ payload: [String: Any]) -> String {
        let labels: [String: String] = [
            "title": "书名", "subtitle": "副标题", "authors": "作者", "translators": "译者",
            "isbn10": "ISBN-10", "isbn13": "ISBN-13", "publisher": "出版社",
            "publishedDate": "出版日期", "pageCount": "页数", "price": "定价",
            "edition": "版本", "series": "丛书", "binding": "装帧",
            "language": "语言", "category": "分类", "summary": "简介"
        ]
        let fields = payload.keys.compactMap { labels[$0] }.sorted()
        return fields.isEmpty ? "来源证据" : fields.joined(separator: "、")
    }

    private func collectEvidence(
        from output: [String: Any],
        toolName: String,
        isbn: String,
        urls: inout Set<String>,
        hasISBNEvidence: inout Bool
    ) {
        for key in ["url", "source_url"] {
            if let value = cleanString(output[key]), safePublicURL(value) != nil {
                urls.insert(value)
            }
        }
        let canConfirmISBN = toolName == "fetch_url"
            || (toolName == "lookup_openlibrary" && output["found"] as? Bool == true)
        if canConfirmISBN,
           let data = try? JSONSerialization.data(withJSONObject: output),
           let text = String(data: data, encoding: .utf8),
           BookRepository.normalizeISBN(text).contains(isbn) {
            hasISBNEvidence = true
        }
    }

    private func multimodalImageMessage(url: String, isbn: String) -> [String: Any] {
        [
            "role": "user",
            "content": [
                [
                    "type": "text",
                    "text": "Inspect candidate cover \(url) for ISBN \(isbn). Decide whether it visibly matches the gathered title/author. If it matches, include this exact URL as coverURL in the final submission. If not, search for another candidate. A mismatch must not block submitting metadata without a cover."
                ],
                [
                    "type": "image_url",
                    "image_url": ["url": url, "detail": "low"]
                ]
            ]
        ]
    }

    private func decodeArguments(_ value: Any?) -> [String: Any] {
        guard let string = value as? String, let data = string.data(using: .utf8) else { return [:] }
        return (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
    }

    private func encodeToolOutput(_ value: [String: Any]) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: value),
              let string = String(data: data, encoding: .utf8) else { return #"{"error":"encoding failed"}"# }
        return string.prefixString(maxToolOutputCharacters)
    }

    private func visibleText(_ data: Data) -> String {
        let html = String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .isoLatin1)
            ?? ""
        return html
            .replacingOccurrences(of: #"(?is)<script.*?</script>|<style.*?</style>"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"(?s)<[^>]+>"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func extractPublicLinks(_ data: Data, baseURL: URL) -> [String] {
        let html = String(data: data, encoding: .utf8) ?? ""
        let pattern = #"(?i)href\s*=\s*["']([^"'#]+)["']"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(html.startIndex..., in: html)
        var links: [String] = []
        for match in regex.matches(in: html, range: range) {
            guard let capture = Range(match.range(at: 1), in: html) else { continue }
            let value = String(html[capture]).replacingOccurrences(of: "&amp;", with: "&")
            guard let absolute = URL(string: value, relativeTo: baseURL)?.absoluteURL,
                  let safe = safePublicURL(absolute.absoluteString),
                  !links.contains(safe.absoluteString) else { continue }
            links.append(safe.absoluteString)
            if links.count == 20 { break }
        }
        return links
    }

    private func safePublicURL(_ value: String) -> URL? {
        guard let url = URL(string: value),
              ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
              let host = url.host?.lowercased(),
              host != "localhost", !host.hasSuffix(".local"), !isPrivateIPv4(host) else { return nil }
        return url
    }

    private func isPrivateIPv4(_ host: String) -> Bool {
        let parts = host.split(separator: ".").compactMap { Int($0) }
        guard parts.count == 4, parts.allSatisfy({ (0...255).contains($0) }) else { return false }
        return parts[0] == 0 || parts[0] == 10 || parts[0] == 127 || parts[0] >= 224
            || (parts[0] == 169 && parts[1] == 254)
            || (parts[0] == 172 && (16...31).contains(parts[1]))
            || (parts[0] == 192 && parts[1] == 168)
    }

    private func cleanString(_ value: Any?) -> String? {
        guard let value = value as? String else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func cleanStringArray(_ value: Any?) -> [String]? {
        guard let values = value as? [String] else { return nil }
        let cleaned = values.compactMap(cleanString)
        return cleaned.isEmpty ? nil : cleaned
    }

    private func cleanInteger(_ value: Any?) -> Int? {
        if let value = value as? Int { return value }
        return cleanString(value).flatMap { Int($0.filter(\.isNumber)) }
    }

    private static let tools: [[String: Any]] = [
        tool("search_web", "Search Baidu for Chinese-accessible evidence about a book or ISBN.", [
            "type": "object", "properties": ["query": ["type": "string"]], "required": ["query"]
        ]),
        tool("fetch_url", "Read a public web page returned by search to verify metadata.", [
            "type": "object", "properties": ["url": ["type": "string"]], "required": ["url"]
        ]),
        tool("lookup_openlibrary", "Query Open Library directly by ISBN as a free reference source.", [
            "type": "object", "properties": ["isbn": ["type": "string"]], "required": ["isbn"]
        ]),
        tool("report_progress", "Briefly report a useful investigation update to the user. Do not reveal hidden chain-of-thought.", [
            "type": "object", "properties": ["message": ["type": "string"]], "required": ["message"]
        ]),
        tool("submit_search_results", "Submit verified candidate books matching a title, author, or keyword search. Every candidate must include a verified ISBN.", [
            "type": "object",
            "properties": [
                "candidates": [
                    "type": "array",
                    "items": [
                        "type": "object",
                        "properties": [
                            "title": ["type": "string"],
                            "authors": ["type": "array", "items": ["type": "string"]],
                            "isbn10": ["type": ["string", "null"]],
                            "isbn13": ["type": ["string", "null"]],
                            "publisher": ["type": ["string", "null"]],
                            "publishedDate": ["type": ["string", "null"]],
                            "coverURL": ["type": ["string", "null"]],
                            "sourceURL": ["type": "string"]
                        ],
                        "required": ["title", "sourceURL"]
                    ]
                ]
            ],
            "required": ["candidates"]
        ]),
        tool("record_metadata_evidence", "Immediately record any reliable partial metadata found from one source. Call repeatedly for different sources; fields are merged by the app. Do not wait until every field or cover is found.", [
            "type": "object",
            "properties": [
                "title": ["type": ["string", "null"]],
                "subtitle": ["type": ["string", "null"]],
                "authors": ["type": "array", "items": ["type": "string"]],
                "translators": ["type": "array", "items": ["type": "string"]],
                "isbn10": ["type": ["string", "null"]],
                "isbn13": ["type": ["string", "null"]],
                "publisher": ["type": ["string", "null"]],
                "publishedDate": ["type": ["string", "null"]],
                "pageCount": ["type": ["integer", "null"]],
                "price": ["type": ["string", "null"]],
                "edition": ["type": ["string", "null"]],
                "series": ["type": ["string", "null"]],
                "binding": ["type": ["string", "null"]],
                "language": ["type": ["string", "null"]],
                "category": ["type": ["string", "null"]],
                "summary": ["type": ["string", "null"]],
                "sources": [
                    "type": "array",
                    "items": [
                        "type": "object",
                        "properties": ["url": ["type": "string"], "title": ["type": "string"]],
                        "required": ["url"]
                    ]
                ]
            ],
            "required": ["sources"]
        ]),
        tool("inspect_image", "Independent cover subtask: validate and visually inspect one candidate cover. Try multiple distinct candidates when available; metadata must still be submitted if all cover attempts fail.", [
            "type": "object", "properties": ["url": ["type": "string"]], "required": ["url"]
        ]),
        tool("submit_book_result", "Submit evidence-backed core metadata immediately once ISBN and title are verified. coverURL is optional and must be omitted if unavailable or uncertain.", [
            "type": "object",
            "properties": [
                "found": ["type": "boolean"],
                "isbn10": ["type": ["string", "null"]],
                "isbn13": ["type": ["string", "null"]],
                "title": ["type": ["string", "null"]],
                "subtitle": ["type": ["string", "null"]],
                "authors": ["type": "array", "items": ["type": "string"]],
                "translators": ["type": "array", "items": ["type": "string"]],
                "publisher": ["type": ["string", "null"]],
                "publishedDate": ["type": ["string", "null"]],
                "pageCount": ["type": ["integer", "null"]],
                "price": ["type": ["string", "null"]],
                "edition": ["type": ["string", "null"]],
                "series": ["type": ["string", "null"]],
                "binding": ["type": ["string", "null"]],
                "language": ["type": ["string", "null"]],
                "category": ["type": ["string", "null"]],
                "summary": ["type": ["string", "null"]],
                "coverURL": ["type": ["string", "null"]],
                "sources": [
                    "type": "array",
                    "items": [
                        "type": "object",
                        "properties": ["url": ["type": "string"], "title": ["type": "string"]],
                        "required": ["url"]
                    ]
                ]
            ],
            "required": ["found", "sources"]
        ])
    ]

    private static func tool(_ name: String, _ description: String, _ parameters: [String: Any]) -> [String: Any] {
        ["type": "function", "function": ["name": name, "description": description, "parameters": parameters]]
    }
}

private extension String {
    func prefixString(_ limit: Int) -> String {
        if count <= limit { return self }
        return String(prefix(limit)) + "…"
    }
}

struct OpenLibraryProvider: BookLookupProvider {
    let key = BookLookupProviderKey.openLibrary
    let name = "Open Library"
    private let baseURL = "https://openlibrary.org"

    func lookup(isbn: String) async throws -> [BookMetadataDraft] {
        let url = URL(string: "\(baseURL)/api/books?bibkeys=ISBN:\(isbn)&format=json&jscmd=data")!
        let (data, response) = try await URLSession.bookLookup.data(from: url)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw BookLookupError.networkError("Invalid response")
        }

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let key = "ISBN:\(isbn)"
        guard let bookData = json?[key] as? [String: Any] else { return [] }

        let draft = BookMetadataDraft(
            title: (bookData["title"] as? String)?.nilIfEmpty,
            subtitle: nil,
            authors: parseOLContributors(bookData["authors"] as? [[String: Any]]),
            translators: nil,
            isbn10: parseISBNFromKey(key, length: 10),
            isbn13: parseISBNFromKey(key, length: 13),
            publisher: (bookData["publishers"] as? [[String: Any]])?.first?["name"] as? String,
            publishedDate: (bookData["publish_date"] as? String)?.nilIfEmpty,
            pageCount: bookData["number_of_pages"] as? Int,
            price: nil,
            edition: (bookData["edition_name"] as? String)?.nilIfEmpty,
            series: nil,
            binding: nil,
            language: nil,
            category: (bookData["subjects"] as? [[String: Any]])?.first?["name"] as? String,
            summary: (bookData["notes"] as? [String: Any])?["value"] as? String,
            coverURL: parseCoverURL(bookData, isbn: isbn),
            dataSource: "openlibrary",
            rawJSON: String(data: data, encoding: .utf8)
        )

        return draft.hasContent ? [draft] : []
    }

    func search(keyword: String) async throws -> [BookMetadataDraft] {
        let encoded = keyword.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? keyword
        let parameter = keyword.count < 3 ? "title" : "q"
        let url = URL(string: "\(baseURL)/search.json?\(parameter)=\(encoded)&limit=20")!
        let (data, response) = try await URLSession.bookLookup.data(from: url)
        try validateHTTPResponse(response, provider: name, data: data)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let docs = json?["docs"] as? [[String: Any]] else { return [] }

        return docs.compactMap { doc -> BookMetadataDraft? in
            guard let title = doc["title"] as? String, !title.isEmpty else { return nil }
            return BookMetadataDraft(
                title: title,
                subtitle: doc["subtitle"] as? String,
                authors: (doc["author_name"] as? [String])?.filter { !$0.isEmpty },
                translators: nil,
                isbn10: (doc["isbn"] as? [String])?.first(where: { $0.count == 10 }),
                isbn13: (doc["isbn"] as? [String])?.first(where: { $0.count == 13 }),
                publisher: (doc["publisher"] as? [String])?.first,
                publishedDate: (doc["first_publish_date"] as? String),
                pageCount: doc["number_of_pages_median"] as? Int,
                price: nil,
                edition: nil,
                series: nil,
                binding: nil,
                language: nil,
                category: (doc["subject"] as? [String])?.first,
                summary: nil,
                coverURL: parseSearchCoverURL(doc),
                dataSource: "openlibrary",
                rawJSON: nil
            )
        }
    }

    private func parseOLContributors(_ contributors: [[String: Any]]?) -> [String]? {
        contributors?.compactMap { $0["name"] as? String }.filter { !$0.isEmpty }
    }

    private func parseISBNFromKey(_ key: String, length: Int) -> String? {
        let cleaned = key.replacingOccurrences(of: "ISBN:", with: "")
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: " ", with: "")
        return cleaned.count == length ? cleaned : nil
    }

    private func parseCoverURL(_ bookData: [String: Any], isbn: String) -> URL? {
        if let identifies = bookData["identifiers"] as? [String: Any],
           let goodreads = identifies["goodreads"] as? [[String: Any]],
           let id = goodreads.first?["value"] as? String {
            return URL(string: "https://images-na.ssl-images-amazon.com/images/I/\(id).jpg")
        }
        return URL(string: "\(baseURL)/covers/isbn/\(isbn)-M.jpg")
    }

    private func parseSearchCoverURL(_ doc: [String: Any]) -> URL? {
        if let coverID = doc["cover_i"] as? Int {
            return URL(string: "\(baseURL)/covers/id/\(coverID)-M.jpg")
        }
        if let isbn = (doc["isbn"] as? [String])?.first(where: { $0.count == 13 || $0.count == 10 }) {
            return URL(string: "\(baseURL)/covers/isbn/\(isbn)-M.jpg")
        }
        return nil
    }
}

struct JuheISBNProvider: BookLookupProvider {
    let key = BookLookupProviderKey.juhe
    let name = "聚合数据 ISBN"
    private let apiKey: String
    private let baseURL = "https://feedback.api.juhe.cn/ISBN"

    init(apiKey: String) {
        self.apiKey = apiKey
    }

    func lookup(isbn: String) async throws -> [BookMetadataDraft] {
        guard let url = makeURL(isbn: isbn) else {
            throw BookLookupError.invalidResponse
        }

        let (data, response) = try await URLSession.bookLookup.data(from: url)
        try validateHTTPResponse(response, provider: name, data: data)

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let errorCode = (json?["error_code"] as? Int) ?? (json?["code"] as? Int) ?? 0
        guard errorCode == 0 else {
            let reason = (json?["reason"] as? String) ?? (json?["msg"] as? String) ?? "未知错误"
            throw BookLookupError.networkError("\(name): \(reason)")
        }

        guard let result = json?["result"] as? [String: Any] else { return [] }
        let draft = parseResult(result, isbn: isbn, rawData: data)
        return draft.hasContent ? [draft] : []
    }

    func search(keyword: String) async throws -> [BookMetadataDraft] {
        let cleaned = BookRepository.normalizeISBN(keyword)
        guard cleaned.count == 10 || cleaned.count == 13 else { return [] }
        return try await lookup(isbn: cleaned)
    }

    private func makeURL(isbn: String) -> URL? {
        var components = URLComponents(string: baseURL)
        components?.queryItems = [
            URLQueryItem(name: "key", value: apiKey),
            URLQueryItem(name: "sub", value: isbn)
        ]
        return components?.url
    }

    private func parseResult(_ result: [String: Any], isbn: String, rawData: Data) -> BookMetadataDraft {
        let title = stringValue(result, keys: ["title", "name", "bookname"])
        let authorText = stringValue(result, keys: ["author", "authors"])
        let isbn13 = stringValue(result, keys: ["isbn13", "isbn"]) ?? (isbn.count == 13 ? isbn : nil)
        let isbn10 = stringValue(result, keys: ["isbn10"]) ?? (isbn.count == 10 ? isbn : nil)
        let pageText = stringValue(result, keys: ["page", "pages", "page_count"])
        let cover = stringValue(result, keys: ["images_large", "images_medium", "pic", "image", "img", "cover", "cover_url"])

        return BookMetadataDraft(
            title: title,
            subtitle: stringValue(result, keys: ["subtitle"]),
            authors: splitPeople(authorText),
            translators: splitPeople(stringValue(result, keys: ["translator", "translators"])),
            isbn10: isbn10,
            isbn13: isbn13,
            publisher: stringValue(result, keys: ["publisher"]),
            publishedDate: stringValue(result, keys: ["pubdate", "published_date", "pubtime"]),
            pageCount: pageText.flatMap { Int($0.filter(\.isNumber)) },
            price: stringValue(result, keys: ["price"]),
            edition: stringValue(result, keys: ["edition"]),
            series: stringValue(result, keys: ["series"]),
            binding: stringValue(result, keys: ["binding"]),
            language: stringValue(result, keys: ["language"]),
            category: stringValue(result, keys: ["class", "category", "catalog"]),
            summary: stringValue(result, keys: ["summary", "description", "intro"]),
            coverURL: cover.flatMap(URL.init(string:)),
            dataSource: "juhe_isbn",
            rawJSON: String(data: rawData, encoding: .utf8)
        )
    }

    private func stringValue(_ dict: [String: Any], keys: [String]) -> String? {
        for key in keys {
            if dict[key] is NSNull { continue }
            if let value = dict[key] as? String {
                let trimmed = cleanText(value)
                if !trimmed.isEmpty { return trimmed }
            }
            if let value = dict[key] {
                let text = cleanText("\(value)")
                if !text.isEmpty { return text }
            }
        }
        return nil
    }

    private func cleanText(_ value: String) -> String {
        value
            .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func splitPeople(_ value: String?) -> [String]? {
        guard let value else { return nil }
        let separators = CharacterSet(charactersIn: "/,，、;；")
        let people = value.components(separatedBy: separators)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return people.isEmpty ? nil : people
    }
}

struct GuguISBNProvider: BookLookupProvider {
    let key = BookLookupProviderKey.gugu
    let name = "咕咕数据 ISBN"
    private let appKey: String
    private let baseURL = "https://api.gugudata.com/text/isbn"

    init(appKey: String) {
        self.appKey = appKey
    }

    func lookup(isbn: String) async throws -> [BookMetadataDraft] {
        try await request(isbn: isbn, keywords: nil)
    }

    func search(keyword: String) async throws -> [BookMetadataDraft] {
        let cleaned = BookRepository.normalizeISBN(keyword)
        if cleaned.count == 10 || cleaned.count == 13 {
            return try await lookup(isbn: cleaned)
        }
        return try await request(isbn: nil, keywords: keyword)
    }

    private func request(isbn: String?, keywords: String?) async throws -> [BookMetadataDraft] {
        guard let url = makeURL(isbn: isbn, keywords: keywords) else {
            throw BookLookupError.invalidResponse
        }

        let (data, response) = try await URLSession.bookLookup.data(from: url)
        try validateHTTPResponse(response, provider: name, data: data)

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw BookLookupError.invalidResponse
        }

        if let status = json["DataStatus"] as? [String: Any],
           let code = intValue(status, keys: ["StatusCode", "Code"]),
           ![0, 100, 200].contains(code) {
            let message = stringValue(status, keys: ["StatusDescription", "Message"]) ?? "未知错误"
            throw BookLookupError.networkError("\(name): \(message)")
        }

        let items = extractItems(from: json)
        return items.compactMap { parseItem($0, rawData: data) }
    }

    private func makeURL(isbn: String?, keywords: String?) -> URL? {
        var components = URLComponents(string: baseURL)
        var queryItems = [
            URLQueryItem(name: "appkey", value: appKey),
            URLQueryItem(name: "pageindex", value: "1"),
            URLQueryItem(name: "pagesize", value: "10")
        ]
        if let isbn {
            queryItems.append(URLQueryItem(name: "isbn", value: isbn))
        }
        if let keywords, !keywords.isEmpty {
            queryItems.append(URLQueryItem(name: "keywords", value: keywords))
        }
        components?.queryItems = queryItems
        return components?.url
    }

    private func extractItems(from json: [String: Any]) -> [[String: Any]] {
        if let data = json["Data"] as? [[String: Any]] {
            return data
        }
        if let data = json["Data"] as? [String: Any] {
            return [data]
        }
        if let result = json["Result"] as? [[String: Any]] {
            return result
        }
        if let result = json["Result"] as? [String: Any] {
            return [result]
        }
        return []
    }

    private func parseItem(_ item: [String: Any], rawData: Data) -> BookMetadataDraft? {
        let title = stringValue(item, keys: ["Title", "title", "BookName", "Name"])
        let isbn13 = stringValue(item, keys: ["ISBN13", "Isbn13", "isbn13", "ISBN", "Isbn", "isbn"])
        let isbn10 = stringValue(item, keys: ["ISBN10", "Isbn10", "isbn10"])
        let cover = stringValue(item, keys: ["CoverImage", "ImageUrl", "CoverUrl", "Cover", "Picture", "Img", "Pic", "cover"])

        let draft = BookMetadataDraft(
            title: title,
            subtitle: stringValue(item, keys: ["SubTitle", "Subtitle", "subtitle"]),
            authors: splitPeople(stringValue(item, keys: ["Author", "Authors", "author"])),
            translators: splitPeople(stringValue(item, keys: ["Translator", "Translators", "translator"])),
            isbn10: isbn10,
            isbn13: isbn13,
            publisher: stringValue(item, keys: ["Publisher", "publisher"]),
            publishedDate: stringValue(item, keys: ["PublisherDateTime", "PublishDate", "PublishedDate", "PubDate", "pubdate"]),
            pageCount: intValue(item, keys: ["PageNumber", "Pages", "PageCount", "pageCount"]),
            price: stringValue(item, keys: ["Price", "price"]),
            edition: stringValue(item, keys: ["Edition", "edition"]),
            series: stringValue(item, keys: ["Series", "series"]),
            binding: stringValue(item, keys: ["Binding", "binding"]),
            language: stringValue(item, keys: ["Language", "language"]),
            category: stringValue(item, keys: ["Category", "category"]),
            summary: stringValue(item, keys: ["BriefIntroduction", "Summary", "Description", "Content", "summary"]),
            coverURL: cover.flatMap(URL.init(string:)),
            dataSource: "gugu_isbn",
            rawJSON: String(data: rawData, encoding: .utf8)
        )
        return draft.hasContent ? draft : nil
    }

    private func stringValue(_ dict: [String: Any], keys: [String]) -> String? {
        for key in keys {
            if let value = dict[key] as? String {
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { return trimmed }
            }
            if let value = dict[key] {
                let text = "\(value)".trimmingCharacters(in: .whitespacesAndNewlines)
                if !text.isEmpty { return text }
            }
        }
        return nil
    }

    private func intValue(_ dict: [String: Any], keys: [String]) -> Int? {
        for key in keys {
            if let value = dict[key] as? Int { return value }
            if let value = dict[key] as? String, let intValue = Int(value.filter(\.isNumber)) {
                return intValue
            }
        }
        return nil
    }

    private func splitPeople(_ value: String?) -> [String]? {
        guard let value else { return nil }
        let people = value.components(separatedBy: CharacterSet(charactersIn: "/,，、;；"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return people.isEmpty ? nil : people
    }
}

struct JisuISBNProvider: BookLookupProvider {
    let key = BookLookupProviderKey.jisu
    let name = "极速数据 ISBN"
    private let appKey: String
    private let queryURL = "https://api.jisuapi.com/isbn/query"
    private let searchURL = "https://api.jisuapi.com/isbn/search"

    init(appKey: String) {
        self.appKey = appKey
    }

    func lookup(isbn: String) async throws -> [BookMetadataDraft] {
        guard let url = makeQueryURL(isbn: isbn) else {
            throw BookLookupError.invalidResponse
        }

        let (data, response) = try await URLSession.bookLookup.data(from: url)
        try validateHTTPResponse(response, provider: name, data: data)
        let json = try parseRootJSON(data)
        try validateStatus(json)

        guard let result = json["result"] as? [String: Any] else { return [] }
        let draft = parseDetail(result, rawData: data)
        return draft.hasContent ? [draft] : []
    }

    func search(keyword: String) async throws -> [BookMetadataDraft] {
        let cleaned = BookRepository.normalizeISBN(keyword)
        if cleaned.count == 10 || cleaned.count == 13 {
            return try await lookup(isbn: cleaned)
        }

        guard let url = makeSearchURL(keyword: keyword) else {
            throw BookLookupError.invalidResponse
        }

        let (data, response) = try await URLSession.bookLookup.data(from: url)
        try validateHTTPResponse(response, provider: name, data: data)
        let json = try parseRootJSON(data)
        try validateStatus(json)

        guard let result = json["result"] as? [String: Any],
              let list = result["list"] as? [[String: Any]] else {
            return []
        }

        return list.compactMap { parseSearchItem($0, rawData: data) }
    }

    private func makeQueryURL(isbn: String) -> URL? {
        var components = URLComponents(string: queryURL)
        components?.queryItems = [
            URLQueryItem(name: "appkey", value: appKey),
            URLQueryItem(name: "isbn", value: isbn)
        ]
        return components?.url
    }

    private func makeSearchURL(keyword: String) -> URL? {
        var components = URLComponents(string: searchURL)
        components?.queryItems = [
            URLQueryItem(name: "appkey", value: appKey),
            URLQueryItem(name: "keyword", value: keyword),
            URLQueryItem(name: "pagenum", value: "1")
        ]
        return components?.url
    }

    private func parseRootJSON(_ data: Data) throws -> [String: Any] {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw BookLookupError.invalidResponse
        }
        return json
    }

    private func validateStatus(_ json: [String: Any]) throws {
        let status = intValue(json, keys: ["status", "code"]) ?? 0
        guard status == 0 else {
            let message = stringValue(json, keys: ["msg", "message"]) ?? "未知错误"
            throw BookLookupError.networkError("\(name): \(message)")
        }
    }

    private func parseDetail(_ result: [String: Any], rawData: Data) -> BookMetadataDraft {
        let isbn = stringValue(result, keys: ["isbn"])
        let isbn10 = stringValue(result, keys: ["isbn10"])
        let pageText = stringValue(result, keys: ["page"])
        let cover = stringValue(result, keys: ["pic"])

        return BookMetadataDraft(
            title: stringValue(result, keys: ["title"]),
            subtitle: stringValue(result, keys: ["subtitle"]),
            authors: splitPeople(stringValue(result, keys: ["author"])),
            translators: nil,
            isbn10: isbn10,
            isbn13: isbn,
            publisher: stringValue(result, keys: ["publisher"]),
            publishedDate: stringValue(result, keys: ["pubdate"]),
            pageCount: pageText.flatMap { Int($0.filter(\.isNumber)) },
            price: stringValue(result, keys: ["price"]),
            edition: stringValue(result, keys: ["edition"]),
            series: nil,
            binding: stringValue(result, keys: ["binding"]),
            language: stringValue(result, keys: ["language"]),
            category: stringValue(result, keys: ["class", "keyword"]),
            summary: stringValue(result, keys: ["summary"]),
            coverURL: cover.flatMap(URL.init(string:)),
            dataSource: "jisu_isbn",
            rawJSON: String(data: rawData, encoding: .utf8)
        )
    }

    private func parseSearchItem(_ item: [String: Any], rawData: Data) -> BookMetadataDraft? {
        let title = stringValue(item, keys: ["title"])
        let isbn = stringValue(item, keys: ["isbn"])
        let cover = stringValue(item, keys: ["pic"])

        let draft = BookMetadataDraft(
            title: title,
            subtitle: nil,
            authors: splitPeople(stringValue(item, keys: ["author"])),
            translators: nil,
            isbn10: nil,
            isbn13: isbn,
            publisher: stringValue(item, keys: ["publisher"]),
            publishedDate: nil,
            pageCount: nil,
            price: stringValue(item, keys: ["price"]),
            edition: nil,
            series: nil,
            binding: nil,
            language: nil,
            category: nil,
            summary: nil,
            coverURL: cover.flatMap(URL.init(string:)),
            dataSource: "jisu_isbn",
            rawJSON: String(data: rawData, encoding: .utf8)
        )
        return draft.hasContent ? draft : nil
    }

    private func stringValue(_ dict: [String: Any], keys: [String]) -> String? {
        for key in keys {
            if let value = dict[key] as? String {
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { return trimmed }
            }
            if let value = dict[key] {
                let text = "\(value)".trimmingCharacters(in: .whitespacesAndNewlines)
                if !text.isEmpty { return text }
            }
        }
        return nil
    }

    private func intValue(_ dict: [String: Any], keys: [String]) -> Int? {
        for key in keys {
            if let value = dict[key] as? Int { return value }
            if let value = dict[key] as? String, let intValue = Int(value.filter(\.isNumber)) {
                return intValue
            }
        }
        return nil
    }

    private func splitPeople(_ value: String?) -> [String]? {
        guard let value else { return nil }
        let people = value.components(separatedBy: CharacterSet(charactersIn: "/,，、;；"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return people.isEmpty ? nil : people
    }
}

struct GoogleBooksProvider: BookLookupProvider {
    let key = BookLookupProviderKey.googleBooks
    let name = "Google Books"
    private let baseURL = "https://www.googleapis.com/books/v1"

    func lookup(isbn: String) async throws -> [BookMetadataDraft] {
        let encoded = isbn.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? isbn
        let url = URL(string: "\(baseURL)/volumes?q=isbn:\(encoded)")!
        let (data, response) = try await URLSession.bookLookup.data(from: url)
        try validateHTTPResponse(response, provider: name, data: data)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let items = json?["items"] as? [[String: Any]], !items.isEmpty else { return [] }
        return items.compactMap { parseGoogleBook($0) }
    }

    func search(keyword: String) async throws -> [BookMetadataDraft] {
        let encoded = keyword.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? keyword
        let url = URL(string: "\(baseURL)/volumes?q=\(encoded)&maxResults=20&langRestrict=zh")!
        let (data, response) = try await URLSession.bookLookup.data(from: url)
        try validateHTTPResponse(response, provider: name, data: data)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let items = json?["items"] as? [[String: Any]] else { return [] }
        return items.compactMap { parseGoogleBook($0) }
    }

    private func parseGoogleBook(_ item: [String: Any]) -> BookMetadataDraft? {
        guard let volumeInfo = item["volumeInfo"] as? [String: Any] else { return nil }
        let industryIdentifiers = volumeInfo["industryIdentifiers"] as? [[String: Any]] ?? []
        let isbn10 = industryIdentifiers.first(where: { $0["type"] as? String == "ISBN_10" })?["identifier"] as? String
        let isbn13 = industryIdentifiers.first(where: { $0["type"] as? String == "ISBN_13" })?["identifier"] as? String

        let imageLinks = volumeInfo["imageLinks"] as? [String: Any]
        let coverURL: URL? = (imageLinks?["thumbnail"] as? String).flatMap { URL(string: $0) }
            ?? (imageLinks?["smallThumbnail"] as? String).flatMap { URL(string: $0) }

        return BookMetadataDraft(
            title: (volumeInfo["title"] as? String)?.nilIfEmpty,
            subtitle: (volumeInfo["subtitle"] as? String)?.nilIfEmpty,
            authors: volumeInfo["authors"] as? [String],
            translators: nil,
            isbn10: isbn10,
            isbn13: isbn13,
            publisher: (volumeInfo["publisher"] as? String)?.nilIfEmpty,
            publishedDate: (volumeInfo["publishedDate"] as? String)?.nilIfEmpty,
            pageCount: volumeInfo["pageCount"] as? Int,
            price: nil,
            edition: nil,
            series: nil,
            binding: nil,
            language: volumeInfo["language"] as? String,
            category: (volumeInfo["categories"] as? [String])?.first,
            summary: (volumeInfo["description"] as? String)?.nilIfEmpty,
            coverURL: coverURL,
            dataSource: "googlebooks",
            rawJSON: nil
        )
    }
}

private func validateHTTPResponse(_ response: URLResponse, provider: String, data: Data) throws {
    guard let httpResponse = response as? HTTPURLResponse else {
        throw BookLookupError.invalidResponse
    }

    switch httpResponse.statusCode {
    case 200..<300:
        return
    case 429:
        throw BookLookupError.rateLimited(provider)
    default:
        let body = String(data: data, encoding: .utf8) ?? ""
        throw BookLookupError.networkError("HTTP \(httpResponse.statusCode) \(body.prefix(120))")
    }
}
