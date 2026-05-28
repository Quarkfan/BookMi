# 面向 2000+ 实体藏书的 iOS 书房管理 App 技术架构文档

版本：v1.0  
架构原则：无自有服务端、本地优先、iCloud 备份/同步、可配置大模型 API、SQLite 长期可控

---

## 1. 技术目标

本项目是一个自用 iOS App，用于管理 2000+ 实体藏书。技术设计必须优先保证：

- 无自有服务端。
- 核心数据本地保存。
- 备份、同步、跨设备恢复使用 iCloud。
- 大模型 OCR 使用用户配置的 Endpoint 和 API Key。
- 数据可导入、可导出、可备份、可恢复。
- 搜索、筛选、排序、批量操作在本地高效完成。
- 数据模型长期可维护。

---

## 2. 总体架构

```text
iOS App
├── Presentation Layer
│   ├── SwiftUI Views
│   ├── ViewModels
│   └── Navigation / State
│
├── Domain Layer
│   ├── Book Management
│   ├── Shelf Management
│   ├── Tag Management
│   ├── Reading Management
│   ├── Borrow Management
│   ├── Import / Export
│   ├── Backup / Restore
│   ├── Search / Index
│   └── AI / OCR
│
├── Data Layer
│   ├── SQLite Database
│   ├── Repository
│   ├── Search Index
│   ├── File Storage
│   └── Keychain Storage
│
├── Integrations
│   ├── iCloud Drive / CloudKit
│   ├── External Book APIs
│   └── User Configured LLM API
│
└── System Services
    ├── AVFoundation Barcode Scanner
    ├── FileImporter / FileExporter
    ├── LocalAuthentication
    └── URLSession
```

---

## 3. 关键技术决策

### 3.1 不建设服务端

App 不包含自有后端服务。所有核心能力在 iOS 本地完成。

| 能力 | 实现方式 |
|---|---|
| 图书数据 | 本地 SQLite |
| 封面文件 | 本地 Documents 目录 |
| 备份 | 本地 ZIP + iCloud Drive |
| 跨设备同步 | iCloud Drive 或 CloudKit |
| OCR | 用户配置的大模型 API |
| API Key | iOS Keychain |
| 搜索 | SQLite FTS5 + 拼音索引 |

### 3.2 数据库选择

推荐：SQLite + GRDB.swift。

原因：

- 对长期本地数据更可控。
- 便于 schema migration。
- 支持事务。
- 支持批量导入。
- 可结合 FTS5 做全文搜索。
- 便于备份 database.sqlite。
- 不依赖 SwiftData 的黑盒行为。

### 3.3 文件存储

封面、导出文件、备份包等使用 App 沙盒文件系统。

建议目录：

```text
Documents/
├── LibraryData/
│   ├── database.sqlite
│   ├── database.sqlite-wal
│   ├── database.sqlite-shm
│   └── covers/
│       ├── book-id-001.jpg
│       └── book-id-002.jpg
├── Backups/
│   ├── library-backup-2026-05-28-223000.zip
│   └── ...
├── Exports/
│   ├── books.csv
│   ├── books.json
│   └── covers.zip
└── Temp/
    ├── import/
    ├── ocr/
    └── export/
```

---

## 4. iCloud 架构

### 4.1 使用范围

所有备份、同步、跨设备恢复能力使用 iCloud，不使用自有服务端。

支持两类实现方式：

| 方式 | 用途 | 说明 |
|---|---|---|
| iCloud Drive | 备份包存储 | 推荐优先实现，简单、可控 |
| CloudKit | 多设备记录级同步 | 复杂度较高，可在需要时实现 |

### 4.2 推荐主方案

```text
本地 SQLite 数据库
+
本地封面目录
+
完整 ZIP 备份包
+
iCloud Drive 保存备份包
```

该方案优点：

- 实现简单。
- 恢复明确。
- 数据可见、可迁移。
- 不依赖复杂冲突合并。
- 适合自用场景。

### 4.3 备份包结构

```text
library-backup-2026-05-28-223000.zip
├── manifest.json
├── database.sqlite
├── export/
│   ├── books.json
│   ├── shelves.json
│   ├── tags.json
│   ├── book_tags.json
│   ├── borrow_records.json
│   ├── purchase_channels.json
│   ├── reading_records.json
│   ├── settings.json
│   └── ai_ocr_logs.json
└── covers/
    ├── book-id-001.jpg
    ├── book-id-002.jpg
    └── ...
```

### 4.4 manifest.json

```json
{
  "appName": "Personal Library",
  "backupVersion": 1,
  "schemaVersion": 1,
  "createdAt": "2026-05-28T22:30:00+09:00",
  "bookCount": 2138,
  "shelfCount": 12,
  "tagCount": 48,
  "coverCount": 1796,
  "databaseFile": "database.sqlite",
  "jsonExportPath": "export/",
  "coversPath": "covers/",
  "containsApiKey": false
}
```

### 4.5 恢复模式

| 模式 | 说明 |
|---|---|
| 覆盖恢复 | 清空当前数据库和封面，用备份替换 |
| 合并恢复 | 将备份数据合并到当前数据库 |
| 仅导入图书 | 只导入图书、封面、标签、书柜，不恢复设置 |

### 4.6 恢复前保护

执行恢复前必须：

1. 提示用户当前数据会受影响。
2. 自动创建恢复前备份，除非用户明确跳过。
3. 校验备份包 manifest。
4. 校验 database.sqlite 是否存在。
5. 校验 JSON 文件和封面目录完整性。

---

## 5. 大模型 API 架构

### 5.1 设计原则

App 不建设 OCR 服务端。App 直接调用用户配置的大模型 API。

```text
iOS App → User Configured LLM Endpoint
```

### 5.2 配置项

| 配置项 | 存储位置 | 说明 |
|---|---|---|
| enableAI | SQLite settings | 是否启用 AI/OCR |
| apiBaseURL | SQLite settings | 用户配置的调用地址 |
| apiKey | Keychain | 用户配置的密钥 |
| modelName | SQLite settings | 模型名称 |
| requestFormat | SQLite settings | OpenAI-Compatible / Custom |
| timeoutSeconds | SQLite settings | 请求超时 |
| temperature | SQLite settings | 默认 0 |
| maxTokens | SQLite settings | 最大输出长度 |
| languagePreference | SQLite settings | 自动 / 中文 / 英文 |
| saveRawResponse | SQLite settings | 是否保存原始响应 |

### 5.3 API Key 安全

要求：

1. API Key 使用 iOS Keychain 保存。
2. 不写入 SQLite settings 表。
3. 默认不进入备份包。
4. 用户显式选择导出敏感配置时，必须提示风险。
5. 恢复备份后，如不含 API Key，需要用户重新配置。

### 5.4 接口格式

优先支持 OpenAI-Compatible Chat Completions 多模态格式。

抽象接口：

```swift
protocol LLMClient {
    func testConnection() async throws -> LLMTestResult
    func recognizeBookInfo(from image: Data, task: OCRTaskType) async throws -> OCRBookResult
    func cleanBookMetadata(_ input: BookMetadataDraft) async throws -> BookMetadataDraft
    func recommendTags(for book: BookMetadataDraft) async throws -> [String]
}
```

### 5.5 OCR 任务类型

```swift
enum OCRTaskType: String, Codable {
    case copyrightPage
    case cover
    case backCover
    case spine
    case custom
}
```

### 5.6 结构化返回格式

模型必须被要求只返回 JSON。

```json
{
  "title": "string | null",
  "subtitle": "string | null",
  "authors": ["string"],
  "translators": ["string"],
  "isbn10": "string | null",
  "isbn13": "string | null",
  "publisher": "string | null",
  "publishedDate": "string | null",
  "edition": "string | null",
  "printing": "string | null",
  "pageCount": 0,
  "price": "string | null",
  "series": "string | null",
  "binding": "string | null",
  "language": "string | null",
  "category": "string | null",
  "confidence": 0.0,
  "rawText": "string | null"
}
```

### 5.7 OCR 流程

```text
拍照或选择图片
↓
图片压缩与尺寸限制
↓
读取 AI 配置
↓
读取 Keychain API Key
↓
调用大模型 API
↓
解析 JSON
↓
保存 OCR 日志，可选
↓
进入确认编辑页
↓
用户确认
↓
保存图书
```

### 5.8 错误处理

| 错误 | 处理 |
|---|---|
| 未配置 API Key | 提示进入设置 |
| Base URL 无效 | 提示检查配置 |
| 超时 | 可重试 |
| 返回非 JSON | 展示原始内容并提示解析失败 |
| 字段缺失 | 使用 null，不阻断 |
| 置信度低 | 标记为需人工确认 |
| 网络失败 | 提示离线或网络异常 |

---

## 6. 数据库设计

### 6.1 Schema 版本

需要维护 schema_version。

```sql
CREATE TABLE schema_info (
    key TEXT PRIMARY KEY,
    value TEXT NOT NULL
);
```

示例：

```text
schema_version = 1
app_version = 1.0.0
```

### 6.2 books

```sql
CREATE TABLE books (
    id TEXT PRIMARY KEY,
    legacy_id TEXT,
    title TEXT NOT NULL,
    subtitle TEXT,
    original_title TEXT,
    authors_json TEXT,
    translators_json TEXT,
    isbn10 TEXT,
    isbn13 TEXT,
    publisher TEXT,
    published_date TEXT,
    page_count INTEGER,
    price TEXT,
    edition TEXT,
    printing TEXT,
    series TEXT,
    binding TEXT,
    language TEXT,
    category TEXT,
    summary TEXT,
    cover_file_name TEXT,
    cover_url TEXT,
    cover_hash TEXT,
    shelf_id TEXT,
    location_detail TEXT,
    purchase_channel_id TEXT,
    purchase_date TEXT,
    purchase_price TEXT,
    reading_status TEXT NOT NULL DEFAULT 'unread',
    reading_progress_type TEXT,
    current_page INTEGER,
    progress_percent REAL,
    started_at TEXT,
    finished_at TEXT,
    borrow_status TEXT NOT NULL DEFAULT 'available',
    note TEXT,
    data_source TEXT,
    source_raw_data TEXT,
    duplicate_group_id TEXT,
    copy_index INTEGER NOT NULL DEFAULT 1,
    is_favorite INTEGER NOT NULL DEFAULT 0,
    custom_sort_key TEXT,
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL,
    deleted_at TEXT
);
```

Indexes:

```sql
CREATE INDEX idx_books_title ON books(title);
CREATE INDEX idx_books_isbn10 ON books(isbn10);
CREATE INDEX idx_books_isbn13 ON books(isbn13);
CREATE INDEX idx_books_shelf_id ON books(shelf_id);
CREATE INDEX idx_books_purchase_channel_id ON books(purchase_channel_id);
CREATE INDEX idx_books_reading_status ON books(reading_status);
CREATE INDEX idx_books_borrow_status ON books(borrow_status);
CREATE INDEX idx_books_created_at ON books(created_at);
CREATE INDEX idx_books_updated_at ON books(updated_at);
CREATE INDEX idx_books_deleted_at ON books(deleted_at);
```

### 6.3 shelves

```sql
CREATE TABLE shelves (
    id TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    location_note TEXT,
    sort_order INTEGER NOT NULL DEFAULT 0,
    note TEXT,
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL,
    deleted_at TEXT
);
```

### 6.4 tags

```sql
CREATE TABLE tags (
    id TEXT PRIMARY KEY,
    name TEXT NOT NULL UNIQUE,
    color TEXT,
    sort_order INTEGER NOT NULL DEFAULT 0,
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL,
    deleted_at TEXT
);
```

### 6.5 book_tags

```sql
CREATE TABLE book_tags (
    book_id TEXT NOT NULL,
    tag_id TEXT NOT NULL,
    created_at TEXT NOT NULL,
    PRIMARY KEY (book_id, tag_id)
);

CREATE INDEX idx_book_tags_tag_id ON book_tags(tag_id);
```

### 6.6 purchase_channels

```sql
CREATE TABLE purchase_channels (
    id TEXT PRIMARY KEY,
    name TEXT NOT NULL UNIQUE,
    sort_order INTEGER NOT NULL DEFAULT 0,
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL,
    deleted_at TEXT
);
```

### 6.7 borrow_records

```sql
CREATE TABLE borrow_records (
    id TEXT PRIMARY KEY,
    book_id TEXT NOT NULL,
    borrower_name TEXT NOT NULL,
    contact TEXT,
    borrowed_at TEXT NOT NULL,
    expected_return_at TEXT,
    returned_at TEXT,
    status TEXT NOT NULL,
    note TEXT,
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL
);

CREATE INDEX idx_borrow_records_book_id ON borrow_records(book_id);
CREATE INDEX idx_borrow_records_status ON borrow_records(status);
```

### 6.8 ai_ocr_logs

```sql
CREATE TABLE ai_ocr_logs (
    id TEXT PRIMARY KEY,
    task_type TEXT NOT NULL,
    related_book_id TEXT,
    image_file_name TEXT,
    request_summary TEXT,
    response_json TEXT,
    raw_response TEXT,
    success INTEGER NOT NULL,
    error_message TEXT,
    duration_ms INTEGER,
    model_name TEXT,
    created_at TEXT NOT NULL
);
```

### 6.9 settings

```sql
CREATE TABLE settings (
    key TEXT PRIMARY KEY,
    value TEXT,
    updated_at TEXT NOT NULL
);
```

注意：API Key 不进入 settings 表。

---

## 7. 搜索与索引设计

### 7.1 搜索要求

搜索必须本地完成，不依赖网络。

支持：

- 中文关键词。
- 拼音全拼。
- 拼音首字母。
- ISBN。
- 作者。
- 译者。
- 出版社。
- 标签。
- 书柜。
- 详细位置。
- 购买渠道。
- 混合关键词。

### 7.2 search_index 表

```sql
CREATE TABLE search_index (
    book_id TEXT PRIMARY KEY,
    normalized_title TEXT,
    normalized_authors TEXT,
    normalized_translators TEXT,
    normalized_publisher TEXT,
    normalized_isbn TEXT,
    normalized_tags TEXT,
    normalized_shelf TEXT,
    normalized_location TEXT,
    normalized_purchase_channel TEXT,
    pinyin_title_full TEXT,
    pinyin_title_initials TEXT,
    pinyin_authors_full TEXT,
    pinyin_authors_initials TEXT,
    combined_search_text TEXT,
    updated_at TEXT NOT NULL
);
```

### 7.3 FTS5 虚表

```sql
CREATE VIRTUAL TABLE books_fts USING fts5(
    book_id UNINDEXED,
    title,
    authors,
    translators,
    publisher,
    isbn,
    tags,
    shelf,
    location,
    summary,
    note,
    pinyin_full,
    pinyin_initials,
    combined
);
```

### 7.4 索引生成

当图书、标签、书柜、购买渠道变化时，需要更新对应图书的索引。

触发场景：

- 新增图书。
- 编辑图书。
- 删除图书。
- 修改标签。
- 修改书柜。
- 修改购买渠道。
- 批量操作。
- 用户手动重建索引。

### 7.5 文本标准化

标准化规则：

- 转小写。
- 全角转半角。
- 去除多余空格。
- 去除常见标点。
- ISBN 去除 `-` 和空格。
- 中文保留。
- 英文保留。

### 7.6 拼音索引

对中文字段生成：

- 全拼：`shujujiegou`
- 首字母：`sjjg`

字段：

- 书名。
- 作者。
- 译者。
- 出版社，可选。
- 标签，可选。

### 7.7 搜索排序权重

| 匹配类型 | 权重 |
|---|---:|
| ISBN 精确匹配 | 100 |
| 书名完全匹配 | 90 |
| 书名前缀匹配 | 80 |
| 书名包含匹配 | 70 |
| 作者匹配 | 60 |
| 标签匹配 | 50 |
| 出版社匹配 | 40 |
| 书柜匹配 | 30 |
| 简介/备注匹配 | 20 |

### 7.8 搜索性能目标

| 数据量 | 目标 |
|---|---|
| 2000 本 | 300ms 内返回 |
| 10000 本 | 1s 内返回 |

---

## 8. CSV 导入架构

### 8.1 导入流程

```text
选择 CSV
↓
读取文件
↓
编码识别或用户选择
↓
解析 Header
↓
自动字段映射
↓
用户确认字段映射
↓
预览前 N 行
↓
重复检测
↓
封面目录/ZIP 匹配
↓
事务批量写入
↓
生成搜索索引
↓
输出导入报告
```

### 8.2 字段映射

内部使用 ImportFieldMapping：

```swift
struct ImportFieldMapping: Codable {
    let csvColumn: String
    let targetField: BookImportField
}
```

### 8.3 重复检测

规则：

1. legacy_id 相同。
2. isbn13 相同。
3. isbn10 相同。
4. title + authors 标准化后相同。

处理策略：

```swift
enum DuplicateStrategy {
    case skip
    case overwrite
    case fillEmptyOnly
    case createNewCopy
}
```

### 8.4 导入事务

批量导入必须在事务中执行。

原则：

- 单行失败不应导致整个导入失败，除非是数据库级错误。
- 每行记录成功、跳过或失败状态。
- 导入结束后生成报告。
- 大批量导入要显示进度。

---

## 9. 导出与备份架构

### 9.1 CSV 导出

支持字段选择。

导出流程：

```text
选择字段
↓
查询数据
↓
展开作者、标签等数组字段
↓
生成 CSV
↓
保存到本地或分享
```

### 9.2 JSON 导出

JSON 导出用于长期可读和跨版本迁移。

建议每个实体单独文件：

- books.json
- shelves.json
- tags.json
- book_tags.json
- borrow_records.json
- purchase_channels.json
- settings.json

### 9.3 封面 ZIP

封面以 book_id 命名，避免 ISBN 缺失或重复导致冲突。

```text
covers/book-id.jpg
```

### 9.4 完整备份

备份流程：

```text
暂停写入或进入一致性快照
↓
checkpoint SQLite WAL
↓
复制 database.sqlite
↓
导出 JSON
↓
复制 covers
↓
生成 manifest.json
↓
打包 ZIP
↓
保存到本地或 iCloud Drive
```

SQLite WAL 注意：

- 备份前执行 WAL checkpoint。
- 或使用 SQLite backup API。
- 避免只复制 database.sqlite 导致数据不完整。

---

## 10. 批量操作架构

### 10.1 操作类型

```swift
enum BatchOperation {
    case deleteBooks
    case moveShelf(shelfId: String, locationDetail: String?)
    case addTags(tagIds: [String])
    case removeTags(tagIds: [String])
    case setReadingStatus(ReadingStatus)
    case markFinished(finishedAt: Date?)
    case setPurchaseChannel(channelId: String?)
    case rebuildSearchIndex
    case matchCovers
    case enrichMetadata
}
```

### 10.2 执行原则

- 使用事务。
- 显示操作确认。
- 显示进度。
- 记录操作结果。
- 更新搜索索引。
- 支持部分失败报告。

---

## 11. 扫码架构

### 11.1 技术

使用 AVFoundation 识别一维码。

支持类型：

- EAN-13。
- EAN-8。
- UPC-E。
- Code 128，可选。

### 11.2 流程

```text
打开摄像头
↓
识别条码
↓
标准化 ISBN
↓
查询本地是否已存在
↓
查询网络图书信息
↓
展示确认页
↓
应用默认书柜/标签
↓
保存
```

### 11.3 ISBN 标准化

- 去除空格和短横线。
- 校验 ISBN-10 / ISBN-13 校验位。
- 必要时 ISBN-10 转 ISBN-13。

---

## 12. 外部图书信息查询

### 12.1 原则

外部图书信息查询是客户端直接调用第三方公开 API 或网页接口，不经过自有服务端。

### 12.2 抽象接口

```swift
protocol BookLookupProvider {
    func lookup(isbn: String) async throws -> [BookMetadataDraft]
    func search(keyword: String) async throws -> [BookMetadataDraft]
}
```

### 12.3 Provider 组合

```swift
final class BookLookupService {
    private let providers: [BookLookupProvider]
}
```

支持多个 Provider，按顺序查询并合并结果。

### 12.4 数据来源记录

每条由外部查询生成或补全的数据，应记录：

- data_source。
- source_raw_data，可选。
- updated_at。

---

## 13. 封面管理

### 13.1 文件命名

推荐以 book_id 命名：

```text
covers/{book_id}.jpg
```

如有多个版本：

```text
covers/{book_id}_cover.jpg
covers/{book_id}_original.jpg
```

### 13.2 封面获取来源

- 外部图书 API。
- 网络图片地址。
- 用户相册。
- 用户拍照。
- CSV 导入匹配。

### 13.3 图片处理

- 保存前压缩。
- 生成缩略图，可选。
- 计算 hash，用于去重。
- 加载时异步读取。
- 列表使用缩略图或缓存。

### 13.4 封面一致性检查

数据维护中检查：

- 数据库引用但文件不存在。
- 文件存在但无图书引用。
- 重复封面文件。

---

## 14. 阅读与借出状态

### 14.1 ReadingStatus

```swift
enum ReadingStatus: String, Codable {
    case unread
    case reading
    case finished
    case paused
    case abandoned
}
```

### 14.2 BorrowStatus

```swift
enum BorrowStatus: String, Codable {
    case available
    case borrowed
}
```

### 14.3 借出一致性

规则：

- 一本实体书同一时间只能有一条 status = borrowed 的 borrow_record。
- 归还时更新 borrow_records.returned_at 和 books.borrow_status。
- 删除图书时借出记录保留但图书软删除。

---

## 15. 安全架构

### 15.1 启动密码

使用本地安全设置控制。

支持：

- 数字密码。
- Face ID / Touch ID。
- App 启动验证。
- 从后台恢复后验证，可配置。

### 15.2 API Key

使用 Keychain。

Keychain Key 示例：

```text
com.personal-library.llm-api-key
```

### 15.3 备份安全

默认备份不包含 API Key。

如用户手动选择包含敏感配置，需要：

- 明确提示。
- manifest 标记 containsApiKey = true。
- 可选提供备份包密码加密。

---

## 16. 设置架构

settings 表存储非敏感配置。

建议 key：

```text
ai.enabled
ai.base_url
ai.model_name
ai.request_format
ai.timeout_seconds
ai.temperature
ai.max_tokens
ai.language_preference
ai.save_raw_response
ui.display_mode
ui.list_visible_fields
scan.default_shelf_id
scan.default_tag_ids
scan.default_purchase_channel_id
backup.auto_enabled
backup.auto_frequency
backup.last_backup_at
security.passcode_enabled
security.biometric_enabled
search.index_version
```

复杂 value 使用 JSON 字符串。

---

## 17. 数据维护架构

### 17.1 维护任务

```swift
enum MaintenanceTask {
    case rebuildSearchIndex
    case rebuildPinyinIndex
    case findDuplicateBooks
    case findMissingCovers
    case findMissingISBN
    case findMissingShelf
    case findUnusedTags
    case findBrokenCoverReferences
    case cleanOrphanCoverFiles
    case exportDiagnostics
}
```

### 17.2 诊断报告

导出 diagnostics.json：

```json
{
  "createdAt": "2026-05-28T22:30:00+09:00",
  "bookCount": 2138,
  "missingISBNCount": 126,
  "missingCoverCount": 342,
  "missingShelfCount": 58,
  "duplicateISBNGroups": 24,
  "unusedTagCount": 12,
  "brokenCoverReferences": 3,
  "orphanCoverFiles": 8
}
```

---

## 18. 错误处理与日志

### 18.1 日志类型

- 导入日志。
- 备份日志。
- 恢复日志。
- AI/OCR 调用日志。
- 批量操作日志。
- 数据维护日志。

### 18.2 operation_logs

```sql
CREATE TABLE operation_logs (
    id TEXT PRIMARY KEY,
    operation_type TEXT NOT NULL,
    summary TEXT,
    detail_json TEXT,
    success INTEGER NOT NULL,
    error_message TEXT,
    created_at TEXT NOT NULL
);
```

### 18.3 错误展示原则

- 用户可理解。
- 保留详细错误用于排查。
- 批量操作支持部分失败报告。
- 导入错误可定位到行号。

---

## 19. UI 技术建议

| 层 | 技术 |
|---|---|
| UI | SwiftUI |
| 状态管理 | Observable / ViewModel |
| 数据库 | GRDB.swift |
| 文件 | FileManager |
| 扫码 | AVFoundation |
| 网络 | URLSession async/await |
| 安全 | Keychain + LocalAuthentication |
| 压缩 | ZIPFoundation 或等价库 |
| CSV | 自研解析或成熟 CSV parser |
| iCloud Drive | FileManager ubiquity container |

---

## 20. 模块划分建议

```text
PersonalLibraryApp/
├── App/
├── Features/
│   ├── Books/
│   ├── Shelves/
│   ├── Tags/
│   ├── Scanner/
│   ├── ImportExport/
│   ├── BackupRestore/
│   ├── Search/
│   ├── AI/
│   ├── Reading/
│   ├── Borrowing/
│   ├── Statistics/
│   ├── Settings/
│   └── Maintenance/
├── Core/
│   ├── Database/
│   ├── FileStorage/
│   ├── Keychain/
│   ├── Networking/
│   ├── iCloud/
│   ├── Logging/
│   └── Utils/
└── Resources/
```

---

## 21. 数据一致性规则

1. 图书主键使用 UUID，不使用 ISBN。
2. ISBN 可重复。
3. 同 ISBN 多副本使用 copy_index 区分。
4. 删除使用软删除。
5. 书柜删除时必须迁移图书或设为未分类。
6. 标签删除时只删除关联，不删除图书。
7. 批量操作必须更新 updated_at。
8. 图书关键字段变化必须更新搜索索引。
9. 备份前必须确保数据库一致性。
10. 恢复前必须校验备份包。

---

## 22. 性能要求

| 场景 | 技术要求 |
|---|---|
| 2000 本搜索 | 300ms 内返回 |
| 10000 本搜索 | 1s 内返回 |
| CSV 10000 行导入 | 支持进度与错误报告 |
| 图书列表滚动 | 异步加载封面，避免主线程 IO |
| 批量操作 | 使用事务，显示进度 |
| 备份创建 | 后台执行，显示进度 |
| OCR 调用 | 支持超时、取消、重试 |

---

## 23. 测试重点

### 23.1 数据测试

- ISBN 校验。
- CSV 字段映射。
- 重复检测。
- 标签拆分。
- 作者拆分。
- 备份恢复一致性。
- JSON 导入导出一致性。

### 23.2 搜索测试

- 中文搜索。
- 拼音全拼。
- 拼音首字母。
- ISBN 搜索。
- 多关键词搜索。
- 字段筛选。
- 排序正确性。

### 23.3 AI/OCR 测试

- 未配置 Key。
- Base URL 错误。
- 超时。
- 非 JSON 返回。
- 字段缺失。
- 低置信度。
- 用户确认后保存。

### 23.4 备份测试

- 本地备份。
- iCloud 备份。
- 覆盖恢复。
- 合并恢复。
- 封面恢复。
- manifest 缺失或损坏。
- database.sqlite 缺失。

---

## 24. 验收标准摘要

| 模块 | 验收标准 |
|---|---|
| 本地数据库 | 图书、书柜、标签、阅读、借出等数据可持久保存 |
| 无服务端 | 核心功能不依赖自有服务端 |
| iCloud | 可创建和恢复 iCloud 备份包 |
| AI/OCR | 可配置 Endpoint 和 Key，并完成拍照识别 |
| 搜索 | 支持中文、拼音、首字母、ISBN、本地模糊搜索 |
| CSV 导入 | 可导入 2000+ 图书并输出报告 |
| 批量操作 | 可批量删除、移动、打标签、标记读完 |
| 备份恢复 | 完整备份包可恢复数据库和封面 |
| 数据维护 | 可检查重复、缺失封面、缺失 ISBN、重建索引 |
| 安全 | API Key 存储在 Keychain，支持启动密码和生物识别 |

---

## 25. 结论

本项目技术路线应固定为：

```text
SwiftUI
+
SQLite / GRDB
+
本地文件系统
+
SQLite FTS5 / 拼音索引
+
iCloud Drive 备份包
+
用户配置的大模型 API
+
Keychain 保存敏感信息
```

该方案避免自建服务端，符合自用场景，同时保证 2000+ 藏书数据长期可控、可迁移、可维护。
