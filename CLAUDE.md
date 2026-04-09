# Personal Wiki Schema (CLAUDE.md)

> 本文件定义 LLM 维护此知识库的行为规范。每次操作前必须读取。

## 目录结构

```
personal-wiki/
├── raw/          原始文档，只读，LLM 不可修改
│   └── assets/       本地化图片存放目录
├── wiki/         LLM 维护的知识库
│   ├── entities/     具体事物：人物、公司、产品、地点、书籍
│   ├── concepts/     抽象概念：理论、方法、思想、术语
│   ├── events/       事件：历史事件、新闻、里程碑
│   ├── relations/    对比与关联分析（如 A_vs_B.md）
│   ├── synthesis/    综合视图、领域概述、读书笔记汇总
│   ├── macro/        宏观主题：趋势、时代背景、长周期规律
│   ├── index.md      全局索引，每次 ingest 后更新
│   └── log.md        操作日志，只追加
├── inbox/        新文档暂存区，处理后移至 raw/
└── scripts/      自动化脚本
```

## 页面格式规范

### 实体页 (entities/NAME.md)
适用于：人物、公司、产品、地点、书籍、电影等具体事物

```markdown
---
name: 
type: person | company | product | place | book | other
tags: []
related: []
last_updated: YYYY-MM-DD
source_count: 0
---

## 概述
<!-- 是什么，一句话定义 -->

## 核心内容
<!-- 最重要的事实、观点、数据 -->

## 背景与历史
<!-- 来龙去脉 -->

## 影响与评价
<!-- 对世界/领域的影响，争议观点并列记录 -->

## 关联页面
<!-- [[concepts/XXX]] [[events/XXX]] -->
```

### 概念页 (concepts/NAME.md)
适用于：理论、方法论、思想框架、学科术语

```markdown
---
name: 
domain: []   # 所属领域，如 [物理, 信息论]
tags: []
related: []
last_updated: YYYY-MM-DD
---

## 定义
<!-- 精确定义，一段话 -->

## 核心原理
<!-- 关键机制和逻辑 -->

## 应用场景
<!-- 在哪里用，怎么用 -->

## 局限性
<!-- 适用边界，常见误解 -->

## 关联页面
```

### 事件页 (events/NAME.md)
适用于：历史事件、重大新闻、里程碑

```markdown
---
name: 
date: YYYY-MM-DD   # 或 YYYY 年代
tags: []
related: []
last_updated: YYYY-MM-DD
---

## 事件经过
<!-- 时间线，核心事实 -->

## 背景原因
## 结果与影响
## 争议与反思
## 关联页面
```

### 宏观页 (macro/NAME.md)
适用于：长周期趋势、时代背景、跨领域规律

```markdown
---
topic: 
tags: []
last_updated: YYYY-MM-DD
---

## 当前状态
## 历史演变
## 驱动因素
## 未来展望
## 关联页面
```

### 综合页 (synthesis/NAME.md)
适用于：领域概述、读书笔记汇总、主题研究报告

```markdown
---
title: 
scope: []   # 覆盖的实体/概念
tags: []
last_updated: YYYY-MM-DD
---

## 核心结论
## 详细分析
## 知识地图
<!-- 本主题下的关键页面列表 -->
## 关联页面
```

## 数据源处理

特定数据源的获取和转换流程通过 **Skills** 按需加载，不在本文件中展开：

| 数据源 | Skill | 触发方式 |
|--------|-------|----------|
| YouTube 视频 | `/youtube <url>` | 手动或遇到 YouTube URL 自动触发 |
| EPUB 电子书 | `/epub <path>` | 手动或遇到 .epub 文件自动触发 |

Skill 文件位于 `~/.claude/skills/`（全局，跨知识库共用），包含完整的工具链、命令和踩坑经验。

## Ingest 操作规范

当收到新文档（文章、笔记、书摘、网页等）时，执行：

1. **读取 wiki/index.md**，了解当前已有哪些页面
2. **分析文档**，识别涉及的实体、概念、事件
3. **读取相关已有页面**（最多 3-5 个）
4. **更新或新建页面**：
   - 已有页面：更新相关章节，保留原有内容，标注新信息来源和日期
   - 新内容：按模板新建页面，归入对应子目录
5. **更新 wiki/index.md**：新页面加入索引，更新摘要和时间
6. **追加 wiki/log.md**：`## [YYYY-MM-DD] ingest | 文档标题`
7. **移动原始文档**：将 inbox 中的原始文档（epub/网页/html 等）以及 pandoc 转换后的 `.md` 文件全部移至 `raw/`，确保 inbox 清空
8. **输出**：列出所有新建/修改的文件

**注意：**
- 观点矛盾时，并列记录并注明来源，不擅自判断
- 数据信息标注来源和日期，避免过时数据覆盖新数据
- 一次 ingest 通常涉及 2-8 个页面
- 图片优先引用本地路径（`raw/assets/filename.png`），避免依赖外部 URL
- **ingest 完成后 inbox 中对应文档必须移走，不得残留**

## Query 操作规范

1. 读取 wiki/index.md 找相关页面
2. 读取相关页面内容
3. 基于 wiki 内容回答，标注引用（[[页面名]]）
4. **有价值的分析结论默认建议写回 wiki**（对比、洞察、发现的关联等），不应让知识停留在聊天记录里；由用户决定是否执行
5. 追加 log.md：`## [YYYY-MM-DD] query | 问题摘要`

## Lint 操作规范（每月或按需执行）

检查并报告：
- 孤立页面（无 inbound links）
- 数据超过 90 天未更新
- 页面间存在明显矛盾的观点
- 重要概念被提及但无独立页面
- 建议新增的对比页或综合页

追加 log.md：`## [YYYY-MM-DD] lint | 发现 N 个问题`

> log.md 格式说明：每条记录以 `## [YYYY-MM-DD]` 开头，便于用 `grep "^## \[" log.md` 解析历史。

## 搜索策略

- **小规模（< 100 页）**：直接读 index.md 导航，无需额外工具
- **中大规模（>= 100 页）**：考虑引入 [qmd](https://github.com/tobi/qmd)，提供本地 BM25/向量混合搜索，支持 CLI 和 MCP 两种接入方式

## 命名规范

- 人物：中文姓名或英文全名，如 `爱因斯坦.md`、`Alan_Turing.md`
- 公司/产品：常用名，如 `OpenAI.md`、`iPhone.md`
- 概念：准确术语，如 `熵.md`、`贝叶斯推断.md`
- 事件：简明描述，如 `2008年金融危机.md`、`阿波罗11号登月.md`
- 对比：`A_vs_B.md`
- 综合/宏观：中文名，如 `人工智能概览.md`

## 语言规范

- 默认用中文写 wiki 页面
- 专有名词、术语首次出现时附英文原文，如 `熵（Entropy）`
- 数字和数据标注单位和来源

## Frontmatter tags 参考

常用 domain tags：
`物理` `数学` `计算机` `AI` `生物` `化学` `经济` `历史` `哲学` `心理` `社会` `艺术` `文学` `工程` `医学`

常用 type tags：
`基础概念` `方法论` `人物` `公司` `事件` `趋势` `争议`
