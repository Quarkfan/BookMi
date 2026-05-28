# BookRoom - 书房管理 App 产品需求文档

> 版本：v1.1
> 日期：2026-05-28
> 状态：需求定稿（已确认技术选型）

---

## 一、项目概述

### 1.1 项目信息

| 字段 | 内容 |
|------|------|
| 产品名称 | BookRoom |
| 产品定位 | 个人书房管理工具，管理 2000+ 实体藏书 |
| 目标平台 | iOS（原生） |
| 最低版本 | iOS 17.0 |
| 开发语言 | Swift 5.9+ |
| UI 框架 | SwiftUI |
| 数据持久化 | SQLite + GRDB.swift |
| 全文搜索 | SQLite FTS5 + 拼音索引 |
| 云服务 | iCloud Drive（备份包存储） |
| 服务端 | 无自有服务端 |

### 1.2 产品原则

- **无自有服务端**：不做账号体系、不维护后端、所有能力本地完成
- **本地优先**：核心数据本地 SQLite，离线可浏览/搜索/编辑/批量操作
- **数据可控**：用户可完整拿回自己的数据（CSV/JSON/ZIP/备份包）
- **面向 2000+**：默认用户已有大量藏书，重视搜索、批量、导入导出、数据质量
- **在线/离线边界清晰**：扫码查询、OCR、网络搜索、封面匹配需在线；浏览、搜索、编辑、批量操作可离线

### 1.3 核心用户画像

- 已有 2000+ 实体藏书，有从旧 App 或旧数据源迁移需求
- 更关注长期可维护性，而非上架商店
- 能接受偏工程化的高级配置
- 需要配置自己的大模型 API

---

## 二、数据模型

### 2.1 books

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

**关键设计**：
- 主键用 UUID，不以 ISBN 为主键
- ISBN 可重复，同 ISBN 多副本用 `copy_index` 区分
- 软删除（`deleted_at`），不硬删
- 作者、译者用 JSON 数组存储，支持多人
- `data_source` 记录数据来源（扫码/API/手动/OCR/CSV）

### 2.2 shelves

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

删除书柜时如有图书，必须选择：移动到其他书柜 / 设为未分类 / 同时删除图书。默认移动到未分类。

### 2.3 tags

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

删除标签只删除关联，不删除图书。

### 2.4 book_tags

```sql
CREATE TABLE book_tags (
    book_id TEXT NOT NULL,
    tag_id TEXT NOT NULL,
    created_at TEXT NOT NULL,
    PRIMARY KEY (book_id, tag_id)
);
```

### 2.5 purchase_channels

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

### 2.6 borrow_records

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
```

规则：同一本实体书同一时间只能有一条 `status = borrowed` 的记录。归还后保留历史。

### 2.7 search_index

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

### 2.8 FTS5 虚表

```sql
CREATE VIRTUAL TABLE books_fts USING fts5(
    book_id UNINDEXED,
    title, authors, translators, publisher, isbn,
    tags, shelf, location, summary, note,
    pinyin_full, pinyin_initials, combined
);
```

### 2.9 settings

```sql
CREATE TABLE settings (
    key TEXT PRIMARY KEY,
    value TEXT,
    updated_at TEXT NOT NULL
);
```

API Key 不进入 settings 表，保存到 Keychain。

### 2.10 ai_ocr_logs

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

### 2.11 operation_logs

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

### 2.12 schema_info

```sql
CREATE TABLE schema_info (
    key TEXT PRIMARY KEY,
    value TEXT NOT NULL
);
```

维护 `schema_version` 和 `app_version`。

---

## 三、信息架构

采用 5 个一级入口（底部 Tab）：

```
藏书    书柜    录入    统计    设置
```

### 3.1 藏书（全部图书）

- 全部图书列表（列表模式 / 平铺模式）
- 全局搜索框
- 筛选面板（书柜、标签、作者、出版社、阅读状态、购买渠道、借出状态、时间范围、缺失封面/ISBN/书柜）
- 排序（拼音、首字母、添加时间、编辑时间、出版时间、作者、阅读状态、书柜）
- 批量选择与操作
- 点击进入图书详情

### 3.2 书柜

- 书柜列表（名称、图标、图书数量）
- 新建/编辑/删除书柜
- 书柜详情页：该柜内图书列表，支持批量移动

### 3.3 录入

- 扫码录入（ISBN 一维码）
- 网络搜索录入
- 手动录入
- 拍照识别出版信息（AI/OCR）
- CSV 导入
- 批量补全（根据 ISBN 补全信息/封面）
- 扫码默认设置（默认书柜、默认标签、默认购买渠道）

### 3.4 统计

- 总藏书数、年度新增、已读率
- 按书柜分布
- 按作者 TOP N
- 按出版社 TOP N
- 按购买渠道分布
- 热门标签
- 阅读状态分布
- 借出统计（当前借出、历史借出、超期）
- **重复图书统计**（同 ISBN 多副本入口，供用户自行处理）

### 3.5 设置

```
设置
├── AI / OCR 设置
├── 数据备份与恢复
├── 导入导出
├── 数据维护
│   ├── 重建搜索索引
│   ├── 重建拼音索引
│   ├── 检查重复图书
│   ├── 检查缺失封面
│   ├── 检查缺失 ISBN
│   ├── 检查缺失书柜
│   ├── 检查无效标签
│   ├── 检查无效封面文件
│   └── 导出诊断报告
├── 安全设置（启动密码 / Face ID / Touch ID）
├── 显示设置（列表/平铺、排序、可见字段）
├── 标签管理
├── 购买渠道管理
└── 关于
```

---

## 四、功能规格

### 4.1 图书录入

#### 4.1.1 ISBN 扫码

- AVFoundation 识别一维码（EAN-13 / EAN-8 / UPC-E）
- ISBN 标准化（去空格/短横线，校验位，ISBN-10 转 ISBN-13）
- 查本地是否已存在
- 查网络图书信息，自动填充字段
- 应用默认书柜/标签/购买渠道
- 支持保存前编辑、连续扫码
- 查询失败转手动录入

#### 4.1.2 网络搜索

- 关键词搜索（书名/作者/ISBN/出版社）
- 多 Provider 按优先级查询并合并结果
- **数据源优先级**（以国内书籍为主）：
  1. 中文数据源（豆瓣等）
  2. 国际数据源（Open Library、Google Books）
  3. 网络检索兜底（网页搜索）
- 不确定的结果弹出确认页，不静默入库
- 记录 `data_source` 和 `source_raw_data`

#### 4.1.3 手动录入

- 必填：书名
- 其余字段可选，支持多人作者/译者
- 支持上传封面（拍照或相册）

#### 4.1.4 拍照识别（AI/OCR）

- 拍摄版权页或封面
- 调用用户配置的大模型 API
- 返回结构化 JSON（书名、作者、ISBN、出版社等 + 置信度）
- 必须进入确认页，不静默入库
- 低置信度标记需人工确认

#### 4.1.5 CSV 导入

- 选择本地 CSV 文件
- 编码识别/选择
- 字段映射（CSV 列 → 图书字段）
- 预览导入结果
- 重复检测（legacy_id / ISBN / 书名+作者）
- 重复处理策略：跳过 / 覆盖 / 仅填空 / 创建新副本
- 自动创建缺失的书柜/标签
- 支持匹配封面目录/ZIP
- 生成导入报告

### 4.2 AI / OCR 设置

| 配置项 | 存储位置 | 说明 |
|--------|---------|------|
| 启用 AI/OCR | settings | 开关 |
| API Base URL | settings | 调用地址 |
| API Key | Keychain | 密钥 |
| Model Name | settings | 模型名称 |
| Request Format | settings | OpenAI-Compatible / Custom |
| Timeout | settings | 默认 60s |
| Temperature | settings | 默认 0 |
| Max Tokens | settings | 最大输出长度 |
| 识别语言 | settings | 自动/中文/英文 |
| 保存原始响应 | settings | 便于排查 |
| 测试连接 | 按钮 | 验证配置可用性 |

**安全**：API Key 保存到 Keychain，不写入 settings，默认不进入备份包。

### 4.3 搜索与筛选

#### 4.3.1 全局搜索

- 搜索范围：书名、副标题、作者、译者、ISBN、出版社、标签、书柜、位置、购买渠道、简介、备注
- 三层索引：search_index 表 + FTS5 虚表 + 拼音索引
- 支持中文关键词、拼音全拼、拼音首字母、ISBN、混合搜索

#### 4.3.2 搜索排序权重

| 匹配类型 | 权重 |
|---------|------|
| ISBN 精确匹配 | 100 |
| 书名完全匹配 | 90 |
| 书名前缀匹配 | 80 |
| 书名包含匹配 | 70 |
| 作者匹配 | 60 |
| 标签匹配 | 50 |
| 出版社匹配 | 40 |
| 书柜匹配 | 30 |
| 简介/备注匹配 | 20 |

#### 4.3.3 字段筛选

书柜、标签、作者、译者、出版社、阅读状态、购买渠道、借出状态、添加时间、编辑时间、出版年份、是否缺失封面、是否缺失 ISBN、是否未设置书柜。支持多条件组合。

#### 4.3.4 排序

拼音、首字母、添加时间、编辑时间、出版时间、作者、阅读状态、书柜。支持升序/降序。

#### 4.3.5 性能目标

| 数据量 | 目标 |
|--------|------|
| 2000 本 | 300ms 内返回 |
| 10000 本 | 1s 内返回 |

### 4.4 批量操作

| 操作 | 说明 |
|------|------|
| 批量删除 | 软删除 |
| 批量移动书柜 | 移动到指定书柜 |
| 批量设置详细位置 | 层/格等信息 |
| 批量添加标签 | 添加一个或多个 |
| 批量移除标签 | 移除一个或多个 |
| 批量设置阅读状态 | 未读/在读/已读/暂停/放弃 |
| 批量标记读完 | 设置为已读，记录完成时间 |
| 批量设置购买渠道 | 设置渠道 |
| 批量匹配封面 | 对缺失封面图书处理 |
| 批量补全信息 | 根据 ISBN/网络/AI 补全 |
| 批量重建索引 | 修复索引异常 |

全部使用事务执行，显示操作确认和进度。

### 4.5 阅读管理

- 状态：未读（默认）、在读、已读、暂停、放弃
- 进度：当前页码、总页数、百分比、开始/完成时间
- 规则：设为已读时进度自动 100%；当前页码不大于总页数
- 批量标记读完时可设置完成时间为当前日期

### 4.6 借出管理

- 借出记录：借阅人、联系方式、借出时间、预计归还时间、备注
- 同一时间只能一条借出中记录
- 归还后保留历史
- 图书列表显示借出状态
- 支持筛选所有借出中图书

### 4.7 购买渠道

- 新增/编辑/删除渠道
- 给图书设置渠道
- 按渠道筛选和统计

### 4.8 统计分析

| 维度 | 内容 |
|------|------|
| 总量 | 全部藏书数量 |
| 年度 | 按年度统计新增藏书 |
| 书柜 | 各书柜藏书数量分布 |
| 作者 | TOP N 作者排行 |
| 出版社 | TOP N 出版社排行 |
| 购买渠道 | 各渠道购书数量占比 |
| 标签 | 使用频率最高的标签 |
| 阅读状态 | 未读/在读/已读/暂停/放弃占比 |
| 借出 | 当前借出数量、历史借出次数、超期未还数量 |
| 重复图书 | 同 ISBN 多副本统计（入口供用户自行处理） |
| 数据质量 | 缺失 ISBN 数量、缺失封面数量、未设置书柜数量 |

### 4.9 导入导出

#### 4.9.1 CSV 导出

- 可自定义选择导出字段
- 展开作者、标签等数组字段

#### 4.9.2 JSON 导出

- 每个实体单独文件：books.json、shelves.json、tags.json、book_tags.json、borrow_records.json、purchase_channels.json、settings.json
- 用于长期保存和跨版本迁移

#### 4.9.3 封面 ZIP 导出

- 以 book_id 命名：`covers/{book_id}.jpg`

### 4.10 备份与恢复

#### 4.10.1 备份包结构

```
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
│   ├── settings.json
│   └── ai_ocr_logs.json
└── covers/
    ├── book-id-001.jpg
    └── ...
```

#### 4.10.2 恢复模式

| 模式 | 说明 |
|------|------|
| 覆盖恢复 | 清空当前数据库和封面，用备份替换 |
| 合并恢复 | 将备份数据合并到当前数据库 |
| 仅导入图书 | 只导入图书、封面、标签、书柜，不恢复设置 |

#### 4.10.3 恢复前保护

1. 提示用户当前数据会受影响
2. 自动创建恢复前备份（除非用户明确跳过）
3. 校验备份包 manifest
4. 校验 database.sqlite 是否存在
5. 校验 JSON 文件和封面目录完整性

#### 4.10.4 WAL 处理

- 备份前执行 WAL checkpoint 或使用 SQLite backup API
- 避免只复制 database.sqlite 导致数据不完整

### 4.11 数据维护

| 功能 | 说明 |
|------|------|
| 重建搜索索引 | 搜索异常或算法变化时使用 |
| 重建拼音索引 | 单独重建拼音字段 |
| 检查重复图书 | 按 ISBN、书名作者、legacyId 检查 |
| 检查缺失封面 | 找出无封面的图书 |
| 检查缺失 ISBN | 找出无 ISBN 的图书 |
| 检查缺失书柜 | 找出未设置位置的图书 |
| 检查无效标签 | 找出未使用标签 |
| 检查无效封面文件 | 数据库引用但文件不存在 |
| 清理孤立封面 | 文件存在但无图书引用 |
| 导出诊断报告 | 导出数据质量报告（diagnostics.json） |

### 4.12 安全

- 启动密码（数字密码）
- Face ID / Touch ID
- API Key 保存到 Keychain
- 备份包默认不包含 API Key
- 导出敏感配置时提示风险
- 忘记密码可通过清除本地数据后从备份恢复

---

## 五、文件存储

```
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

## 六、非功能需求

### 6.1 性能

| 场景 | 要求 |
|------|------|
| 2000 本搜索 | 300ms 内返回 |
| 10000 本搜索 | 1s 内返回 |
| 列表滚动 | 异步加载封面，避免主线程 IO |
| 扫码识别 | 1s 内识别条码 |
| CSV 导入 | 支持至少 10000 行 |
| 封面加载 | 本地缓存、异步加载、占位图 |
| 索引重建 | 后台执行并显示进度 |
| 备份创建 | 后台执行并显示进度 |

### 6.2 稳定性

- 导入失败不能破坏已有数据
- 备份失败要提示明确原因
- 恢复前必须创建当前数据备份或提示用户
- 批量操作应可确认，避免误操作
- 关键操作应有日志

### 6.3 可维护性

- 数据库 schema 需要版本号
- 备份包需要 backupVersion
- JSON 导出需要 schemaVersion
- 数据模型保持稳定
- 导入导出避免绑定单一外部服务格式

### 6.4 权限

| 权限 | 用途 |
|------|------|
| 摄像头 | 扫码、拍照识别、拍摄封面 |
| 相册 | 选择封面 |
| 文件访问 | CSV 导入、导出、备份恢复 |
| Face ID | 启动安全验证 |
| iCloud | 备份、恢复、同步 |
| 网络 | 图书查询、封面匹配、大模型 API 调用 |

---

## 七、技术栈

| 层级 | 技术 | 说明 |
|------|------|------|
| UI | SwiftUI | iOS 原生框架 |
| 状态管理 | Observable / ViewModel | |
| 数据库 | GRDB.swift | SQLite 封装 |
| 全文搜索 | SQLite FTS5 | 全文检索 |
| 拼音处理 | HanziToPinyin / pinyin.swift | 汉字转拼音 |
| 扫码 | AVFoundation | 一维码识别 |
| 网络 | URLSession async/await | HTTP 请求 |
| 安全 | Keychain + LocalAuthentication | 密码/生物识别 |
| 压缩 | ZIPFoundation | ZIP 打包 |
| CSV | 自研解析或成熟 CSV parser | |
| iCloud | FileManager ubiquity container | 备份存储 |
| 图片缓存 | Nuke | 封面加载 |
| 图表 | Apple Charts | 统计展示 |

---

## 八、完整需求清单

1. 当前目录用于开发一个 iOS App。
2. App 目标是个人书房管理，主要用于管理 2000+ 实体藏书。
3. App 不建设自有服务端。
4. 所有核心数据本地存储。
5. 所有备份、同步和跨设备恢复能力使用 iCloud。
6. 支持配置大模型 API Endpoint。
7. 支持配置大模型 API Key。
8. API Key 使用 iOS Keychain 保存。
9. 支持配置模型名称、超时时间、请求格式等参数。
10. 支持通过大模型进行 OCR / 拍照识别出版信息。
11. 支持扫码录入图书，扫码对象为图书一维码 / ISBN。
12. 扫码录入时支持选择默认书柜和默认标签。
13. 扫码入库时自动附加默认书柜和默认标签。
14. 支持网络搜索图书并加入藏书。
15. 支持手动录入藏书。
16. 支持 CSV 导入现有图书。
17. 支持导入时字段映射。
18. 支持导入时重复检测。
19. 支持导入时封面匹配。
20. 支持获取图书封面。
21. 支持手动替换封面。
22. 支持搜索图书。
23. 支持全局字段搜索。
24. 支持指定字段筛选。
25. 支持模糊搜索。
26. 支持拼音索引。
27. 支持重建搜索索引。
28. 支持自定义标签。
29. 支持书柜概念，记录图书存储位置。
30. 支持批量删除图书。
31. 支持批量移动书柜中的图书到另一个书柜。
32. 支持批量添加标签。
33. 支持批量标记读完。
34. 支持记录阅读进度。
35. 支持借出管理。
36. 支持配置购买渠道。
37. 支持显示设置，包括列表模式、平铺模式。
38. 支持按拼音、添加时间、编辑时间、首字母排序。
39. 支持全部藏书数量统计。
40. 支持年度藏书统计。
41. 支持按照书柜统计书籍数量。
42. 支持作者、出版社、购买渠道、热门标签等维度分析。
43. 支持阅读统计，包括在读、已读、未读等维度。
44. 支持导出图书信息为 CSV。
45. 支持选择具体导出字段。
46. 支持导出封面压缩包。
47. 支持完整备份包导出。
48. 支持完整备份包恢复。
49. 支持将备份包保存到 iCloud。
50. 支持从 iCloud 备份包恢复。
51. 支持启动密码。
52. 支持 Face ID / Touch ID。
53. 支持数据维护工具，包括重复检查、缺失封面检查、缺失 ISBN 检查、无效文件清理。
54. 所有功能作为完整目标一次性设计，开发实现可按阶段推进。

---

## 九、开发阶段规划（内部排期，产品范围不拆）

| 阶段 | 内容 |
|------|------|
| **Phase 1: 基础架构** | 项目初始化、GRDB 数据库搭建、全部数据模型建表、文件存储结构、Settings/Keychain 管理 |
| **Phase 2: 图书录入** | 扫码（AVFoundation）、网络搜索（多 Provider fallback）、手动录入、OCR 拍照识别、CSV 导入、默认书柜/标签设置 |
| **Phase 3: 浏览与搜索** | 图书列表（列表/平铺）、全局搜索、FTS5 + 拼音索引、字段筛选、排序、图书详情页编辑 |
| **Phase 4: 管理功能** | 书柜管理、标签管理、批量操作（删除/移动/标签/状态）、阅读管理、借出管理、购买渠道管理 |
| **Phase 5: 统计分析** | 统计页面（总量/年度/书柜/作者/出版社/渠道/标签/阅读/借出）、重复图书统计入口、数据质量看板 |
| **Phase 6: 导入导出与备份** | CSV 导出（可选字段）、JSON 导出、封面 ZIP、完整备份包创建/恢复、iCloud 备份存储 |
| **Phase 7: 数据维护与安全** | 重建索引、重复检查、缺失封面/ISBN 检查、孤立文件清理、诊断报告、启动密码/FaceID |
| **Phase 8: 打磨** | 性能优化、UI 打磨、测试覆盖、验收 |

---

_最后更新：2026-05-28_
