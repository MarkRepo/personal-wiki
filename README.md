# Personal Wiki

由 LLM 管理和维护的个人知识库。

## 使用方式

### 添加新知识
1. 将原始文档（文章、笔记、书摘）放入 `inbox/`
2. 将文档内容发给 Claude，说 **"ingest 这篇文章"**
3. Claude 会自动更新 wiki 页面和索引

### 查询知识
直接向 Claude 提问，说 **"query: 你想问的问题"**

### 定期维护
说 **"执行 lint"**，检查知识库健康状况

## 目录说明

| 目录 | 用途 |
|------|------|
| `wiki/entities/` | 人物、公司、产品、书籍等具体事物 |
| `wiki/concepts/` | 理论、方法、思想等抽象概念 |
| `wiki/events/` | 历史事件、重大新闻 |
| `wiki/relations/` | 对比分析（A vs B） |
| `wiki/synthesis/` | 领域概述、综合分析 |
| `wiki/macro/` | 宏观趋势、长周期规律 |
| `raw/` | 原始文档存档（只读） |
| `inbox/` | 待处理文档暂存 |

## 操作规范

见 [CLAUDE.md](CLAUDE.md)
