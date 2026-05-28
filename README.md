# BookRoom - 书房管理 App

> iOS 原生书房管理工具 | 管理 2000+ 实体藏书 | 本地优先 · 无服务端 · iCloud 备份

---

## 项目状态

| 阶段 | 状态 | 进度 |
|------|------|------|
| 需求收集 | ✅ 完成 | 原始需求已记录 |
| PRD 设计 | ✅ 完成 | v1.1 已确认 |
| 技术方案 | ✅ 完成 | 已确认 |
| 项目开发 | 🔄 进行中 | Phase 1-2 已完成 |

**最后更新**：2026-05-28

---

## 文档导航

| 文档 | 说明 | 用途 |
|------|------|------|
| [PRD.md](PRD.md) | 产品需求文档（最终版 v1.1） | 开发实现参考 |
| [REQUIREMENTS.md](REQUIREMENTS.md) | 原始需求记录（最终版） | 追溯用户原始想法 |

### 历史归档

以下文档为开发过程中的参考版本，已归档至 `archive/` 目录：

| 归档文件 | 说明 |
|---------|------|
| `archive/MY_prd.md` | 用户自研 PRD（面向 2000+ 藏书的完整设计，权威参考） |
| `archive/MY_technical_architecture.md` | 用户自研技术架构文档（权威技术方案） |
| `archive/PRD.md` | 早期整合版 PRD（已被最终版替代） |
| `archive/REQUIREMENTS.md` | 早期需求记录（已被最终版替代） |

> 当前以根目录下的 `PRD.md` 和 `REQUIREMENTS.md` 为唯一权威版本。

---

## 已确认的技术决策

| 决策项 | 选择 |
|--------|------|
| 数据库 | **SQLite + GRDB.swift**（非 SwiftData） |
| 全文搜索 | SQLite FTS5 + 拼音索引 |
| UI | SwiftUI |
| 扫码 | AVFoundation（一维码/ISBN） |
| OCR | 用户配置的大模型 API（非离线 Vision 兜底） |
| 数据源优先级 | 中文数据源优先 → 国际数据源 → 网络检索兜底 |
| 云同步 | iCloud Drive 备份包（非 CloudKit 记录级同步） |
| 安全 | Keychain（API Key）+ LocalAuthentication（FaceID/密码） |
| 最低版本 | iOS 17.0 |

---

## 需求概览

### 核心功能模块

| 模块 | 功能数 | 包含 |
|------|--------|------|
| 图书录入 | 6 | 扫码/网络搜索/手动/拍照OCR/CSV导入/默认设置 |
| 信息管理 | 3 | 封面匹配/自定义标签/书柜管理 |
| 批量操作 | 11 | 删除/移动/标签/状态/渠道/封面/索引等 |
| 搜索筛选 | 6 | 全局搜索/字段筛选/拼音模糊/FTS5/重建索引/排序 |
| 阅读管理 | 5 | 5种状态/进度/开始完成时间 |
| 借出管理 | 1 | 借出记录+历史 |
| 统计分析 | 11 | 总量/年度/书柜/作者/出版社/渠道/标签/阅读/借出/重复/数据质量 |
| 导入导出 | 3 | CSV/JSON/封面ZIP |
| 备份恢复 | 3 | 完整备份包/iCloud存储/三种恢复模式 |
| 数据维护 | 10 | 重建索引/重复检查/缺失检查/清理/诊断 |
| 安全设置 | 2 | 启动密码/iCloud备份 |
| AI/OCR | 1 | 可配置大模型API |

完整清单见 [REQUIREMENTS.md](REQUIREMENTS.md)。

---

## 信息架构

```
藏书    书柜    录入    统计    设置
```

5 个底部 Tab，录入独立为一个入口，方便连续扫码。

---

## 开发阶段规划

| 阶段 | 内容 | 状态 |
|------|------|------|
| **Phase 1: 基础架构** | 项目初始化、GRDB、数据模型、文件存储、Settings/Keychain | ✅ |
| **Phase 2: 图书录入** | 扫码、网络搜索、手动、OCR、CSV导入、默认设置 | ✅ |
| **Phase 3: 浏览与搜索** | 列表/平铺、FTS5+拼音搜索、筛选、排序、详情编辑 | 🔄 |
| **Phase 4: 管理功能** | 书柜/标签/批量/阅读/借出/渠道管理 | ⏳ |
| **Phase 5: 统计分析** | 统计页面、重复图书入口、数据质量看板 | ⏳ |
| **Phase 6: 导入导出与备份** | CSV/JSON导出、封面ZIP、备份包、iCloud、恢复 | ⏳ |
| **Phase 7: 数据维护与安全** | 重建索引、重复检查、清理、诊断、启动密码/FaceID | ⏳ |
| **Phase 8: 打磨** | 性能优化、UI、测试、验收 | ⏳ |

> 产品范围不拆，开发按阶段推进，最终统一验收。

---

## 开发日志

| 日期 | 提交 | 内容 |
|------|------|------|
| 2026-05-28 | `5d5102a` | Phase 1 完成：GRDB 数据库层、全部数据模型（11表+FTS5）、Repository层（Book/Shelf/Tag/Search）、SettingsManager、拼音工具（CFStringTransform）、AppContainer依赖注入、密码锁屏+FaceID |
| 2026-05-28 | `e1ac74d` | Phase 2 完成：ISBN扫码（AVFoundation）、网络图书查询（OpenLibrary+Google Books，多Provider fallback）、图书录入表单（含书柜/标签/渠道选择）、默认书柜/标签设置、封面下载 |

---

## 目录结构

```
bookroom/
├── README.md               ← 项目入口，快速了解全貌和进度
├── PRD.md                  ← 产品需求文档（唯一权威版本）
├── REQUIREMENTS.md         ← 原始需求记录（唯一权威版本）
├── docs/                   ← 技术文档目录（后续补充设计稿、API文档等）
├── archive/                ← 历史文档归档
│   ├── MY_prd.md           ← 用户自研PRD（权威参考）
│   ├── MY_technical_architecture.md ← 用户自研技术架构（权威参考）
│   ├── PRD.md              ← 早期整合版PRD
│   └── REQUIREMENTS.md     ← 早期需求记录
└── BookRoom/               ← iOS 项目源码（待创建）
    ├── BookRoom.xcodeproj
    ├── BookRoom/
    └── BookRoomTests/
```

---

## 给 AI / 协作者的指引

### 每次进入项目必做

1. **先看 README** 了解项目全貌和当前进度
2. **看 archive/MY_prd.md** 了解用户权威需求设计（历史参考）
3. **看 archive/MY_technical_architecture.md** 了解技术架构决策（历史参考）
4. **看 PRD.md** 了解整合后的功能规格（当前权威版本）
5. 检查 git 分支和最近提交，了解代码变更
6. 按 Phase 顺序推进开发，不要跳步

### 关键约束

- **无自有服务端**，所有能力本地完成
- **以国内书籍为优先**，数据源多层级 fallback
- **离线/在线边界清晰**：扫码、OCR、网络搜索需在线；浏览、搜索、编辑可离线
- **产品范围不拆**，按阶段开发，最终统一验收
- **同 ISBN 多副本保留**，给统计入口让用户自行处理

---

## 技术栈速查

```
语言: Swift 5.9+
UI: SwiftUI
数据库: SQLite + GRDB.swift
搜索: FTS5 + 拼音索引
最低版本: iOS 17.0
Xcode: 15.0+
```

### 外部数据源（按优先级）

1. 中文数据源（豆瓣等）
2. 国际数据源（Open Library、Google Books）
3. 网络检索兜底

---

_最后更新：2026-05-28_
