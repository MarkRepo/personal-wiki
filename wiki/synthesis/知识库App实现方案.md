---
title: 知识库 App 全栈实现方案
scope: [产品设计, 全栈开发, LLM应用, Ingest Pipeline]
tags: [产品设计, 架构, 全栈, FastAPI, Next.js, Tauri, LLM, SaaS]
last_updated: 2026-04-11
---

## 核心结论

基于 [[synthesis/知识库App架构设计]] 的产品方案，本文给出具体技术实现计划。核心能力：用户扔入任意文档 → LLM 自动结构化拆解 → 生成/更新知识库页面 → Obsidian 风格阅读体验。目标平台：桌面 App（Tauri）+ Web 端（Next.js）。

## 技术栈选型

| 层 | 选型 | 理由 |
|---|---|---|
| **桌面客户端** | Tauri 2.0 (Rust + WebView) | 比 Electron 轻 10x，原生性能，安全沙箱，iOS/Android 支持在路线图上 |
| **Web 前端** | Next.js 15 + React | SSR、App Router、前后端共享同一套 UI 代码 |
| **后端 API** | FastAPI (Python) | LLM/文档处理生态最成熟，async 原生，streaming 友好 |
| **异步任务** | Celery + Redis | Ingest 是重任务（30s-2min），必须异步 |
| **数据库** | PostgreSQL + pgvector | 结构化数据 + 向量检索一体化 |
| **对象存储** | MinIO (自托管) / S3 | 存原始文档（epub、pdf、音视频） |
| **LLM** | Claude API (Anthropic SDK) | 当前 wiki 已验证效果，长上下文能力强 |
| **搜索** | pgvector + pg_trgm | 向量语义搜索 + 中文全文搜索，MVP 阶段够用 |
| **认证** | Clerk 或 Supabase Auth | 零代码接入 OAuth/邮箱登录 |
| **部署** | Docker Compose → K8s | MVP 用 Compose 单机部署，规模化后迁移 K8s |

## 详细分析

### 系统架构

```
┌─────────────────────────────────────────────────────────┐
│  Tauri Desktop App / Next.js Web                        │
│  ┌──────────┐ ┌──────────┐ ┌────────┐ ┌─────────────┐  │
│  │ Ingest   │ │ Wiki     │ │ Graph  │ │ Search      │  │
│  │ DropZone │ │ Reader   │ │ View   │ │ Cmd+K       │  │
│  └────┬─────┘ └────┬─────┘ └───┬────┘ └──────┬──────┘  │
│       │            │           │              │         │
│  ┌────┴────────────┴───────────┴──────────────┴──────┐  │
│  │  Local Cache (SQLite via Drizzle)                 │  │
│  │  离线可读，增量同步                                  │  │
│  └───────────────────────┬───────────────────────────┘  │
└──────────────────────────┼──────────────────────────────┘
                           │ REST + WebSocket (sync/notify)
┌──────────────────────────┼──────────────────────────────┐
│  API Gateway (FastAPI)   │                              │
│  ┌───────────────────────┴──┐                           │
│  │ /api/ingest   POST       │──→ Celery Task Queue      │
│  │ /api/wiki     CRUD       │                           │
│  │ /api/search   GET        │                           │
│  │ /api/sync     WebSocket  │                           │
│  │ /api/auth     Clerk      │                           │
│  └──────────────────────────┘                           │
│                                                         │
│  ┌─────────────────────────────────────────────────┐    │
│  │ Ingest Pipeline (Celery Workers)                │    │
│  │                                                 │    │
│  │ Stage 1: Convert                                │    │
│  │   epub→md (pandoc), pdf→md (marker/pymupdf4llm) │    │
│  │   url→md (trafilatura), youtube→transcript       │    │
│  │   audio→text (whisper)                          │    │
│  │                                                 │    │
│  │ Stage 2: Analyze (LLM)                          │    │
│  │   识别实体/概念/事件/观点，输出结构化 JSON          │    │
│  │                                                 │    │
│  │ Stage 3: Diff (LLM)                             │    │
│  │   对比现有知识库，生成 create/update/link 操作列表  │    │
│  │                                                 │    │
│  │ Stage 4: Apply (等用户确认后执行)                   │    │
│  │   写入数据库，更新向量索引，更新关联图谱             │    │
│  └─────────────────────────────────────────────────┘    │
│                                                         │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐              │
│  │PostgreSQL│  │  Redis   │  │  MinIO   │              │
│  │+pgvector │  │  Queue   │  │  Files   │              │
│  └──────────┘  └──────────┘  └──────────┘              │
└─────────────────────────────────────────────────────────┘
```

### 数据模型

```sql
-- 用户
users (id, email, name, plan, created_at)

-- 知识库（一个用户可有多个）
wikis (id, user_id, name, schema_template, settings_json, created_at)

-- Wiki 页面
pages (
  id, wiki_id,
  slug,                    -- "concepts/杠杆效应"
  category,                -- enum: entity, concept, event, synthesis, macro, relation
  title,
  frontmatter_json,        -- tags, domain, related 等
  content_md,              -- Markdown 正文
  embedding vector(1536),  -- 语义向量
  version int,             -- 乐观锁版本号
  created_at, updated_at
)

-- 页面间链接（图谱数据）
page_links (source_page_id, target_page_id, link_type, context_snippet)

-- 原始文档
sources (id, wiki_id, filename, mime_type, storage_key, status, created_at)

-- Ingest 任务
ingest_jobs (
  id, wiki_id, source_id,
  status,          -- pending → processing → review → applied / rejected
  stage,           -- convert / analyze / diff / apply
  diff_json,       -- Stage 3 输出的变更计划
  error_msg,
  created_at, completed_at
)

-- Ingest 产生的变更（diff 的每一条）
ingest_changes (
  id, job_id, page_id,
  action,          -- create / update / link
  old_content_md,  -- update 时有值
  new_content_md,
  status,          -- pending / accepted / rejected
  user_reviewed_at
)
```

### 后端项目结构

```
server/
├── api/
│   ├── routes/
│   │   ├── ingest.py      # POST /api/ingest, GET /api/ingest/{id}
│   │   ├── wiki.py        # CRUD pages
│   │   ├── search.py      # 全文 + 语义搜索
│   │   └── sync.py        # WebSocket 同步
│   └── deps.py            # 依赖注入
├── pipeline/
│   ├── converter.py       # Stage 1: 格式转换
│   ├── analyzer.py        # Stage 2: LLM 分析
│   ├── differ.py          # Stage 3: Diff 生成
│   ├── applier.py         # Stage 4: 应用变更
│   ├── prompts/           # LLM prompt 模板
│   │   ├── analyze.py     # 实体/概念识别 prompt
│   │   ├── diff.py        # 对比生成 prompt
│   │   └── schema.py      # 各类页面模板
│   └── tasks.py           # Celery task 定义
├── models/                # SQLAlchemy models
├── services/
│   ├── llm.py             # Anthropic SDK 封装
│   ├── embedding.py       # 向量化服务
│   └── storage.py         # MinIO 封装
└── config.py
```

### Ingest Pipeline 关键设计

**Analyzer prompt 策略——两轮 LLM 调用：**

- **Round 1 (Analyze)**：输入原始文档 → 输出结构化 JSON（识别出哪些实体、概念、事件、关键观点）
- **Round 2 (Diff)**：输入 Round 1 的 JSON + 现有相关页面内容 → 输出具体的 create/update 操作

拆两轮而非一轮的原因：降低单次 prompt 复杂度，提升输出稳定性，且 Round 1 结果可缓存复用。

当前 personal-wiki 的 CLAUDE.md ingest 规范即为 prompt 模板的原型。

### 前端项目结构

```
client/
├── src/
│   ├── app/                    # Next.js App Router
│   │   ├── wiki/[...slug]/     # 页面阅读
│   │   ├── ingest/             # Ingest 面板
│   │   ├── graph/              # 图谱全屏视图
│   │   └── search/             # 搜索结果页
│   ├── components/
│   │   ├── editor/
│   │   │   └── MarkdownRenderer.tsx  # unified/remark 渲染 wiki markdown
│   │   ├── ingest/
│   │   │   ├── DropZone.tsx          # 拖拽上传区
│   │   │   ├── DiffReview.tsx        # diff 审阅界面（核心交互）
│   │   │   └── IngestStatus.tsx      # 任务进度
│   │   ├── graph/
│   │   │   └── ForceGraph.tsx        # D3 force-directed 图谱
│   │   ├── search/
│   │   │   └── CommandPalette.tsx    # Cmd+K 搜索面板
│   │   └── layout/
│   │       ├── Sidebar.tsx           # 目录树导航
│   │       └── Backlinks.tsx         # 反向链接面板
│   ├── lib/
│   │   ├── local-db.ts        # SQLite (Drizzle ORM) 本地缓存
│   │   └── sync.ts            # 增量同步逻辑
│   └── hooks/
│       └── useWikiPage.ts     # 本地优先读取，后台同步
├── src-tauri/                  # Tauri Rust 后端
│   └── src/main.rs            # 文件系统访问、本地 SQLite
└── package.json
```

**Markdown 渲染关键能力：**
- `[[wikilink]]` 解析为内部路由跳转
- frontmatter 渲染为页面头部标签
- Mermaid / KaTeX 支持
- 图片引用走本地缓存或 CDN

**Diff Review 界面（核心交互）：**

```
┌─────────────────────────────────────┐
│ Ingest: 纳瓦尔宝典_第3章.epub       │
│ ━━━━━━━━━━━━━━━━━━━━ 100% 分析完成   │
│                                     │
│ ┌─ 新建 ──────────────────────────┐ │
│ │ [v] concepts/杠杆效应.md        │ │
│ │     [预览] 三种杠杆：劳动力…     │ │
│ │ [v] concepts/四种运气.md        │ │
│ │     [预览] 从盲目运气到独特…     │ │
│ └─────────────────────────────────┘ │
│ ┌─ 更新 ──────────────────────────┐ │
│ │ [v] entities/纳瓦尔.md (+3段)   │ │
│ │     [展开 diff]                 │ │
│ └─────────────────────────────────┘ │
│                                     │
│ [全部接受]  [接受选中]  [丢弃]       │
└─────────────────────────────────────┘
```

### 同步机制

采用 **CRDT-lite** 方案（简化版）：

- 每个 page 有 `version` 字段（单调递增）
- 客户端维护 `last_synced_version`
- 打开 App 时 pull：`GET /api/sync?since={last_version}` 拉增量
- 后台 WebSocket 推送实时变更通知
- **冲突策略**：服务端 wins（用户只在客户端阅读，写入全部走服务端 ingest pipeline）

客户端是**只读缓存**，不存在写冲突，大幅简化同步复杂度。

### Schema 模板系统

预设模板存为 JSON，用户选择后影响 LLM prompt：

```json
{
  "读书笔记": {
    "categories": ["entity/book", "entity/person", "concept", "synthesis"],
    "ingest_prompt_override": "重点提取作者核心观点、方法论、案例..."
  },
  "行业研究": {
    "categories": ["entity/company", "entity/product", "concept", "event", "macro"],
    "ingest_prompt_override": "重点提取市场数据、竞争格局、趋势..."
  }
}
```

## 分阶段实现计划

### Phase 1: 核心后端 + 最小前端（6-8 周）

**后端：**
- FastAPI 项目脚手架 + PostgreSQL + pgvector
- 用户认证（Clerk）
- Wiki CRUD API（pages 表）
- Ingest Pipeline Stage 1-4 完整链路
- Celery worker + Redis
- MinIO 文件上传

**前端：**
- Next.js 项目 + 基础布局（侧边栏 + 内容区）
- Markdown 渲染（wikilink 支持）
- 文件上传 DropZone
- Ingest 状态轮询 + Diff Review 页面
- 基础搜索（pg_trgm 全文搜索）

**验证目标：** 用户上传一本 epub → 后端处理 → 看到 diff → 确认 → wiki 页面可读。

### Phase 2: 体验完善（4-6 周）

- Tauri 桌面 App 打包
- 本地 SQLite 缓存 + 增量同步
- 图谱视图（D3 force graph）
- 反向链接面板
- Cmd+K 语义搜索（pgvector）
- 向量 embedding 自动生成
- URL / YouTube ingest 支持
- WebSocket 实时通知

### Phase 3: 产品化（4-6 周）

- 订阅付费（Stripe）
- 用量计量 + 免费版限额
- Schema 模板选择器
- 浏览器剪藏插件（Chrome Extension）
- 移动端 PWA 或 Tauri Mobile
- Docker Compose 一键部署
- 监控 + 日志（Sentry + 结构化日志）

## 关键技术风险

| 风险 | 影响 | 缓解措施 |
|------|------|----------|
| LLM 输出不稳定 | Ingest 质量波动 | 结构化 JSON output + 校验 schema + 重试机制 |
| 长文档超 token 限制 | 无法处理大文件 | 分块处理，滑动窗口 + 跨块合并 |
| 中文语义搜索质量 | 搜索不准 | pgvector + 中文 embedding 模型（如 bge-m3） |
| Tauri WebView 兼容性 | 跨平台渲染差异 | 用标准 CSS，避免 bleeding-edge API |

## 知识地图

- [[synthesis/知识库App架构设计]] — 产品架构设计与市场分析（前置文档）
- [[concepts/杠杆效应]] — 软件作为无边际成本的杠杆
- [[concepts/把自己产品化]] — 将个人能力/工具产品化的思维框架

## 关联页面

- 本 wiki 的 CLAUDE.md 即为 Ingest Pipeline 的 prompt 原型
- Quartz 项目作为阅读端的早期验证方案
