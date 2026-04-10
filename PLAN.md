# Personal Wiki 搭建计划

基于 Karpathy LLM-wiki 理念，定位为**个人通识知识库**（书籍、视频、访谈、文章），与 investment-wiki（投研专用）互补。

## 目录结构

```
~/Documents/personal-wiki/
├── CLAUDE.md               ← Wiki Schema（已完成，已迭代）
├── PLAN.md                 ← 本文件
├── inbox/                  ← 新文档暂存区
├── raw/                    ← 原始文档存档（只读）
│   └── assets/             ← 本地化图片
├── wiki/                   ← LLM 维护的知识库
│   ├── entities/           ← 人物、书籍、公司等
│   ├── concepts/           ← 概念、理论、方法论
│   ├── events/             ← 历史事件
│   ├── relations/          ← 对比分析（A_vs_B）
│   ├── synthesis/          ← 读书笔记、综合视图
│   ├── macro/              ← 宏观趋势
│   ├── index.md            ← 全局索引
│   └── log.md              ← 操作日志
├── scripts/                ← 工具脚本
│   ├── clean_vtt.py        ← YouTube VTT 字幕清洗
│   └── ingest.py           ← inbox 文件批量移入 raw
└── .claude/skills/         ← Claude Code Skills
    ├── youtube/SKILL.md    ← YouTube 视频 ingest
    └── epub/SKILL.md       ← EPUB 电子书 ingest
```

---

## Phase 1：打磨 Schema + 手动 Ingest（第 1 周）✅ 已完成

**目标：跑通 ingest 流程，调好 CLAUDE.md**

- [x] 建目录结构
- [x] 写 CLAUDE.md（Wiki Schema）
- [x] 参考 Karpathy llm-wiki 改进 CLAUDE.md
- [x] 手动 ingest 9 次，覆盖多种类型：
  - 育儿/心理：P.E.T父母效能训练
  - 商业/数学：底层逻辑2
  - 制度/历史：国家为什么会失败
  - 自我成长：认知觉醒（含 Opus re-ingest 对比）
  - YouTube 访谈：刘嘉教授谈 AI 与脑科学
  - 个人发展：纳瓦尔宝典
  - 宏观经济：大衰退（辜朝明）
  - 政治/哲学：毛泽东选集(1-4卷)
  - 全球化：见证逆潮（付鹏）
- [x] 建立 Skills 系统（YouTube / EPUB），从 CLAUDE.md 中剥离数据源处理流程
- [x] CLAUDE.md 稳定

**关键经验：**
- Claude Code 对话式 ingest 比脚本方式更灵活，能实时读取已有页面做关联
- Opus 模型 ingest 质量明显高于 Sonnet（内容深度、概念覆盖率、跨书关联）
- EPUB → pandoc → md 是最稳定的书籍预处理路径
- YouTube 用 yt-dlp + Chrome cookies 提取中文字幕，跳过 WebFetch
- re-ingest 有价值：用更好的模型重写可显著提升页面质量
- 一次 ingest 通常新建 5-10 个页面，更新 2-3 个已有页面

**当前规模：**
- 88 个 wiki 页面（21 entities + 60 concepts + 2 events + 9 synthesis）
- 9 个原始文档源
- relations/ 和 macro/ 尚未使用

---

## Phase 2：补充高价值内容 + 质量提升（第 2-3 周）⬅️ 当前阶段

**目标：wiki 达到 150+ 页面，开始产生跨领域关联价值**

### 2a. 继续 Ingest（目标：再 ingest 5-8 本书/视频）

- [ ] inbox 中待处理：余永定《见证失衡》1&2（宏观经济/国际收支）
- [ ] 从个人书单中选择高价值书籍 ingest
- [ ] 寻找高质量 YouTube 访谈/播客 ingest
- [ ] 考虑 ingest 长文章/Newsletter（需要新的 Skill 或手动）

### 2b. 启用 relations/ 和 macro/

- [ ] 写 2-3 个对比页（如：广纳式制度 vs 榨取式制度、辜朝明 vs 凯恩斯的衰退理论）
- [ ] 写 1-2 个宏观页（如：全球化与逆全球化的百年周期）
- [ ] 这些页面需要跨多本书/多个源的综合，是 wiki 的高价值产出

### 2c. 质量回顾

- [ ] 对早期 Sonnet ingest 的页面（P.E.T、底层逻辑2、国家为什么会失败）考虑用 Opus re-ingest
- [ ] 首次运行 Lint（检查孤立页面、缺失关联、过时内容）
- [ ] 检查概念页之间的交叉引用是否完整

---

## Phase 3：自动化与效率提升（第 4 周）

**目标：减少手动操作，提升 ingest 效率**

### 3a. 预处理自动化

- [ ] 完善 scripts/ingest.py：自动检测文件类型 → 调用对应转换 → 存入 raw/
- [ ] PDF ingest 支持（pymupdf4llm，用于文章/报告）
- [ ] 音频/播客转录（faster-whisper，本地免费）

### 3b. Claude Code 工作流优化

- [ ] 评估是否需要脚本式 ingest（API 调用）vs 继续用 Claude Code 对话式 ingest
  - 对话式优点：灵活、能读已有页面、质量高
  - 脚本式优点：批量处理、token 可控、可定时
  - 判断依据：月 ingest 量是否超过 15 次
- [ ] 如选脚本式：写 scripts/api_ingest.py（参考 investment-wiki 方案）

### 3c. 信息收集

| 来源 | 工具 | 频率 |
|---|---|---|
| YouTube/播客 | yt-dlp + Skills | 按需 |
| EPUB 书籍 | pandoc + Skills | 按需 |
| PDF 文章 | pymupdf4llm | 按需 |
| 音频 | faster-whisper | 按需 |
| 网页文章 | 手动复制到 inbox/ | 按需 |

> 注：personal-wiki 以深度阅读为主，不需要像 investment-wiki 那样接入 RSS/新闻流。
> 信息获取是按需的，不需要定时自动收集。

---

## Phase 4：知识网络成熟（持续）

**目标：wiki 从"笔记集合"进化为"可查询的知识网络"**

- [ ] 定期 Lint（每月 1 次）：孤立页面、矛盾观点、过时数据、缺失页面
- [ ] 定期生成知识图谱概览（synthesis/ 中的领域概述页）
- [ ] 当页面超过 150 时，考虑引入 qmd 本地搜索（BM25 + 向量混合）
- [ ] 跨 wiki 关联：personal-wiki 中的宏观经济概念 ↔ investment-wiki 中的实操应用
- [ ] 探索 query 的高级用法：多页面综合推理、时间线生成、知识缺口分析

---

## 与 Investment-wiki 的分工

| 维度           | Personal Wiki      | Investment Wiki      |
| ------------ | ------------------ | -------------------- |
| 定位           | 通识知识库（认知、方法论、宏观理解） | 投研知识库（个股、行业、交易）      |
| 输入频率         | 低频深度（每周 1-3 本书/视频） | 高频碎片（每天 5-10 篇研报/新闻） |
| 主要 ingest 方式 | Claude Code 对话式    | 脚本式（API）             |
| 核心价值         | 跨领域关联、思维框架积累       | 投资决策支持、信息追踪          |
| 关联点          | 宏观经济理论、制度分析、历史规律   | 宏观数据、政策影响、市场映射       |

---

## 工具清单

| 工具 | 用途 | 状态 |
|---|---|---|
| pandoc | EPUB/HTML → Markdown | ✅ 已安装 |
| yt-dlp | YouTube 视频/字幕下载 | ✅ 已安装 |
| scripts/clean_vtt.py | VTT 字幕清洗 | ✅ 已完成 |
| pymupdf4llm | PDF → Markdown | ⬜ 待安装（Phase 3） |
| faster-whisper | 音频转录 | ⬜ 待安装（Phase 3） |
| qmd | Wiki 本地搜索 | ⬜ 待引入（150+ 页后） |

---

## 模型策略

Personal-wiki 以质量为先，不追求成本最低：

| 任务 | 模型 | 理由 |
|---|---|---|
| Ingest（主力） | Claude Opus（通过 Claude Code） | 深度提取、跨书关联、高质量概念页 |
| Query | Claude Opus/Sonnet（通过 Claude Code） | 多页面综合推理 |
| Lint | Claude Sonnet | 结构化检查，不需要最强推理 |

> 因为使用 Claude Code 对话式 ingest，成本计入 Claude Code 订阅，无需额外 API 费用。
> 如果后续切换到脚本式 ingest，参考 investment-wiki 的模型分层方案。

---

## 关键决策记录

1. **使用 Claude Code 对话式 ingest**：比脚本式更灵活，能实时读取已有页面做关联，质量更高
2. **Skills 架构**：数据源处理流程从 CLAUDE.md 剥离到 Skills，减少每次对话的上下文开销
3. **Opus 为主力模型**：re-ingest 实验证明 Opus 质量显著高于 Sonnet
4. **不接 RSS/定时任务**：本 wiki 以深度阅读为主，按需 ingest，不需要信息流
5. **与 investment-wiki 分开维护**：定位不同、输入节奏不同、查询模式不同，分开更清晰
6. **先不上 qmd 搜索**：88 页时 index.md 导航足够，150+ 页后再考虑

---

## 当前进度

- [x] Phase 1：Schema 打磨 + 手动 Ingest（88 页，9 个源）
- [ ] Phase 2：补充内容 + 启用 relations/macro + 质量提升 ⬅️ 当前
- [ ] Phase 3：自动化与效率提升
- [ ] Phase 4：知识网络成熟
