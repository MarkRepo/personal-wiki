# personal-wiki 新机器搭建计划（步骤 4–7）

> 前置条件 1/2/3 已完成：① clone 仓库 ② 拷贝 `raw/` ③ 拷贝 `~/.claude/skills/`
> 本计划覆盖剩余 4 步。**包用 `brew`/`npm` 重新安装即可；配置内容、脚本、记忆是新机器没有的，已全部内联在本文中，直接复制即可。**
> 适用环境：macOS（Apple Silicon，M5/A19 及以上才有 Metal tensor API 加速）。Linux/Intel 可跳过 Metal patch。

---

## 关键陷阱（先读）

1. **绝对路径硬编码**：当前机器路径是 `/Users/yangqi/...`。新机器若用户名/盘符不同，下面所有 `/Users/yangqi` 必须替换成新机器的实际 `$HOME`。
   - MCP `settings.json` 里 3 个模型路径
   - `youtube` skill 里的 `yt-dlp` 路径（`/Users/yangqi/Library/Python/3.9/bin/yt-dlp`）
2. **qmd 环境变量必须放 `~/.zshenv`，不是 `~/.zshrc`**：`.zshrc` 仅交互式 shell 加载，Claude Code 的 Bash 工具读不到，会导致 `qmd embed` 无限卡在 "Gathering information"。
3. **Node.js `fetch` 不走系统代理**：qmd 通过 `ipull` 下载模型会 hang，必须手动 `curl` 下载 + 环境变量指向本地。
4. **node-llama-cpp 优先用 prebuilt binary**：本地编译后要复制覆盖 prebuilt，否则 patch 不生效。

---

## 步骤 4：安装并配置 qmd 本地搜索引擎

qmd 是 CLAUDE.md ingest 流程第 9 步的依赖（BM25 + 向量 + reranking 混合搜索）。

### 4.1 安装包（重新装）

```bash
npm install -g @tobilu/qmd      # qmd CLI
brew install cmake              # 本地编译 llama.cpp 需要
```

### 4.2 手动下载 3 个模型（curl 走系统代理，可下）

下载到 `~/.cache/qmd/models/`（共约 2.1GB）：

```bash
mkdir -p ~/.cache/qmd/models

curl -L -o ~/.cache/qmd/models/embeddinggemma-300M-Q8_0.gguf \
  "https://huggingface.co/ggml-org/embeddinggemma-300M-GGUF/resolve/main/embeddinggemma-300M-Q8_0.gguf"

curl -L -o ~/.cache/qmd/models/qmd-query-expansion-1.7B-q4_k_m.gguf \
  "https://huggingface.co/tobil/qmd-query-expansion-1.7B-gguf/resolve/main/qmd-query-expansion-1.7B-q4_k_m.gguf"

curl -L -o ~/.cache/qmd/models/qwen3-reranker-0.6b-q8_0.gguf \
  "https://huggingface.co/ggml-org/Qwen3-Reranker-0.6B-Q8_0-GGUF/resolve/main/qwen3-reranker-0.6b-q8_0.gguf"
```

| 模型 | 大小 | 用途 |
|------|------|------|
| embeddinggemma-300M | ~313MB | 文档/查询向量化 |
| qmd-query-expansion-1.7B | ~1.1GB | 查询扩展 |
| Qwen3-Reranker-0.6B | ~690MB | 搜索结果重排序 |

### 4.3 写环境变量到 `~/.zshenv`（不是 .zshrc！）

把以下追加到 `~/.zshenv`：

```bash
export QMD_EMBED_MODEL="$HOME/.cache/qmd/models/embeddinggemma-300M-Q8_0.gguf"
export QMD_GENERATE_MODEL="$HOME/.cache/qmd/models/qmd-query-expansion-1.7B-q4_k_m.gguf"
export QMD_RERANK_MODEL="$HOME/.cache/qmd/models/qwen3-reranker-0.6b-q8_0.gguf"
```

然后 `source ~/.zshenv`（或重开终端）。

### 4.4 初始化 collection（在 personal-wiki 根目录下）

```bash
cd <personal-wiki 根目录>
qmd collection add wiki --name wiki
qmd context add qmd://wiki "个人知识库：包含 entities、concepts、events、synthesis、macro 等页面"
```

### 4.5 修复 Metal tensor API（仅 macOS 26 / Apple Silicon M5+ 需要）

仓库里已有幂等脚本 `scripts/patch-qmd-metal.sh`，直接跑：

```bash
./scripts/patch-qmd-metal.sh
```

> 若 `npm update @tobilu/qmd` 升级覆盖了 patch，需重跑此脚本。

验证（应看到 `GPU: metal | Offloading: true`）：

```bash
node --input-type=module -e "
import {getLlama} from 'node-llama-cpp';
const l = await getLlama({gpu:'metal'});
console.log('  GPU:', l.gpu, '| Offloading:', l.supportsGpuOffloading);
" 2>&1 | grep -v '^\[node-llama-cpp\]' || true
```

---

## 步骤 5：安装数据源转换的 CLI 工具（重新装）

| Skill / 脚本 | 安装命令 |
|------------|---------|
| `/epub` | `brew install pandoc` |
| `/youtube` | `brew install yt-dlp ffmpeg`（或 `pip install yt-dlp`） |
| `scripts/pdf_ocr.sh` | `brew install poppler tesseract tesseract-lang` |
| 通用 | Node.js（qmd 需要）、Python 3（clean_vtt.py / ingest.py 需要） |

**安装后需修一处硬编码**：`~/.claude/skills/youtube/SKILL.md` 里写死了 `YT_DLP=/Users/yangqi/Library/Python/3.9/bin/yt-dlp`。新机器改成实际路径，最简单是 `YT_DLP=$(command -v yt-dlp)` 或直接 `YT_DLP=yt-dlp`（若在 PATH 中）。

`/youtube` skill 还依赖 **Chrome 浏览器 + 已登录 YouTube 的 cookies**（`--cookies-from-browser chrome`）。

---

## 步骤 6：重建 Claude Code 项目配置 + 记忆（新机器没有，直接复制）

### 6.1 MCP server 配置

新机器上的 Claude Code 会按新仓库绝对路径找配置目录。假设新仓库路径为 `/Users/<新用户名>/Documents/personal-wiki`，则项目配置目录是：

```
~/.claude/projects/-Users-<新用户名>-Documents-personal-wiki/settings.json
```

内容如下（**把 `/Users/yangqi` 全部替换成新机器 `$HOME`**）：

```json
{
  "mcpServers": {
    "qmd": {
      "command": "qmd",
      "args": ["mcp"],
      "env": {
        "QMD_EMBED_MODEL": "/Users/yangqi/.cache/qmd/models/embeddinggemma-300M-Q8_0.gguf",
        "QMD_GENERATE_MODEL": "/Users/yangqi/.cache/qmd/models/qmd-query-expansion-1.7B-q4_k_m.gguf",
        "QMD_RERANK_MODEL": "/Users/yangqi/.cache/qmd/models/qwen3-reranker-0.6b-q8_0.gguf"
      }
    }
  }
}
```

> 路径替换后，重启 Claude Code，MCP 工具（`query`/`get`/`multi_get`/`status`）自动可用。

### 6.2 自动记忆文件

目录：`~/.claude/projects/-Users-<新用户名>-Documents-personal-wiki/memory/`（目录名同样按新路径变）。以下 7 个文件原样创建：

#### `MEMORY.md`

```markdown
- [YouTube ingest最优路径](feedback_youtube_ingest.md) — yt-dlp+Chrome cookies，跳过WebFetch，附清洗脚本经验
- [qmd安装配置与踩坑](reference_qmd_setup.md) — 代理绕过、Metal tensor API patch、MCP配置，详见scripts/qmd-setup.md
- [关注机制而非单次结果](feedback_mechanism_over_instance.md) — 用户提问关注流程规范是否健全，先修机制再补实例
- [读书笔记内联引用与整体评测](feedback_booknote_inline_ref_and_eval.md) — 衍生页面引用须内联正文，评测是两层整体过程（子页面评测→读书笔记整体评分）
- [last_updated 精确到秒](feedback_timestamp_precision.md) — 格式 YYYY-MM-DDTHH:MM:SS，用 date 命令获取
- [子Agent文件写入约束](feedback_subagent_file_constraint.md) — 子Agent可直接写内容页，禁止碰 index.md/log.md/ingest_scores.md
```

#### `feedback_booknote_inline_ref_and_eval.md`

```markdown
---
name: 读书笔记内联引用与整体评测规范
description: 读书笔记引用衍生页面须内联在正文中，但不强制覆盖所有衍生页面；评测是整体过程，子页面评测是读书笔记评测的子过程
type: feedback
originSessionId: 2cf300ff-ba72-465b-ae22-1f6699f1a45e
---
## 规则

**引用方式**：读书笔记在正文叙述讲到某概念/实体时，以 `[[concepts/XXX]]` 在该处内联引用，不在末尾单独列表。**但不强制覆盖所有衍生页面**——若某页面与核心叙事无自然交汇点，保留在末尾关联页面中即可。叙事结构服从书的内在逻辑，引用跟着叙事走，不能为了覆盖引用而新建章节。

**评测结构**：评测是两层整体过程，不是各页面独立打分：
1. 子过程：先逐一按各类型自查标准检查衍生页面（概念页：清/透/用/联；实体页：特/全/实），不达标须先修正
2. 主评分：读书笔记六维评分对象是"读书笔记正文 + 所有衍生子页面内容"的整体，子页面质量影响"全"维度

**Why:** "强制覆盖所有衍生页面"会让引用义务凌驾于叙事逻辑之上，导致为了内联某个概念而新建原本不需要的章节，破坏叙事骨架。教训来自置身事内re-ingest：为覆盖激励相容、国内大循环两个概念页新建了章节，导致叙事生硬、结构变形。

**How to apply:** 写读书笔记时先确定核心叙事结构（服从书的逻辑），再自然嵌入概念链接；能内联的内联，无法自然内联的留在末尾关联页面，不因"覆盖率"破坏叙事。
```

#### `feedback_mechanism_over_instance.md`

```markdown
---
name: 关注机制而非单次结果
description: 用户提出问题时关注的是系统性机制保障，而非某次操作的补救
type: feedback
originSessionId: 391f9069-8d4e-4e33-8dcd-196ea14bba8e
---
用户问"ingest 会不会更新已有页面"时，不是在要求补做这一次的更新，而是在审视 ingest 流程本身是否有机制保障。

**Why:** 用户以系统思维看待知识库维护，单次修补不如修好规则。

**How to apply:** 当用户对某次操作结果提出疑问时，优先检查 CLAUDE.md 中的流程规范是否有漏洞或模糊之处，先修机制再补实例。不要急于"我现在补上"，而是先回答"机制层面怎么保证以后不再出这个问题"。
```

#### `feedback_subagent_file_constraint.md`

```markdown
---
name: 子Agent文件写入约束
description: 大文件ingest时子Agent可直接写内容页面，但禁止触碰维护文件
type: feedback
originSessionId: 7870eaa5-e3e1-4657-82c3-e49a98ce3bae
---
子 Agent 只返回结构化摘要，不写任何 wiki 文件。主 Agent 统一写入所有页面。

**Why:** 并行 Agent 写同一文件会冲突覆盖（读书笔记只有一个文件；多个 Agent 可能发现同一概念并各自写 concepts/XXX.md）。给 wiki schema 和文件路径会触发 Agent 越权写文件，光靠"不要写"的 prompt 指令不可靠。

**How to apply:** 子 Agent prompt 给四要素：背景（书名/范围）、主 Agent 目标描述（让读者不读原书也能理解，用于校准提炼深度）、提炼维度（论点/数据/概念/连接点）、明确禁止写文件。**不给 wiki schema，不给目标文件路径。**
```

#### `feedback_timestamp_precision.md`

```markdown
---
name: last_updated 精确到秒
description: 所有 wiki 页面的 last_updated 字段必须精确到秒，格式 YYYY-MM-DDTHH:MM:SS
type: feedback
originSessionId: 2cf300ff-ba72-465b-ae22-1f6699f1a45e
---
## 规则

`last_updated` 字段格式为 `YYYY-MM-DDTHH:MM:SS`，不是 `YYYY-MM-DD`。

**Why:** 用户明确要求精确到秒。

**How to apply:** 新建或更新任何 wiki 页面时，用 `date '+%Y-%m-%dT%H:%M:%S'` 获取当前时间戳填入 `last_updated`。
```

#### `feedback_youtube_ingest.md`

```markdown
---
name: YouTube视频ingest经验
description: YouTube视频内容获取的踩坑经验，具体流程已迁移到 .claude/skills/youtube/SKILL.md
type: feedback
originSessionId: 1545ece6-3312-4109-ba9e-e8ce06ba476a
---
YouTube视频ingest时，直接走 yt-dlp + Chrome cookies 路径，具体命令参见 `.claude/skills/youtube/SKILL.md`。

**不要做的事（踩过的坑）：**
- 不要用 WebFetch 抓YouTube页面（只能拿到JS配置）
- 不要用 Safari cookies（macOS权限拒绝）
- 不要先跑无cookie的 yt-dlp（会被bot检测拦截）
- 不要尝试 json3 格式获取中文原始字幕（只有vtt可用；json3只在翻译字幕上可用）

**Why:** 首次ingest时在以上每个环节都踩坑，浪费约40%时间。

**How to apply:** 遇到 YouTube URL时使用 `/youtube` skill，一步到位。
```

#### `reference_qmd_setup.md`

```markdown
---
name: qmd 安装配置与踩坑记录
description: qmd本地搜索引擎的安装、代理绕过、Metal tensor API patch、MCP配置，详见scripts/qmd-setup.md
type: reference
originSessionId: 5e3f5b86-07bf-4098-a74d-ee697d05b247
---
qmd 已配置为 personal-wiki 的本地搜索引擎（BM25 + 向量 + reranking 混合搜索）。

关键文件：
- `scripts/qmd-setup.md` — 完整安装记录，含两个踩坑问题的根因和解决方案
- `scripts/patch-qmd-metal.sh` — 幂等脚本，修复 macOS 26 Metal tensor API 编译失败（`npm update` 后需重跑）
- `~/.claude/projects/.../settings.json` — MCP server 配置，含三个模型环境变量
- `~/.zshrc` — QMD_EMBED_MODEL / QMD_GENERATE_MODEL / QMD_RERANK_MODEL 环境变量

已知陷阱：
1. Node.js `fetch`（ipull 库）不走系统代理 → 手动 curl 下载模型 + 环境变量指向本地路径
2. **环境变量必须放在 `~/.zshenv` 而非 `~/.zshrc`** → `.zshrc` 仅交互式 shell 加载，Claude Code 的 Bash 工具读不到，导致 `qmd embed` 无限卡住
3. macOS 26 MPP 要求 matmul2d M或N >= 16 → patch llama.cpp 源码后重编译
4. node-llama-cpp 优先使用 prebuilt binary → 本地编译后需复制到 prebuilt 目录

CLAUDE.md ingest 流程已更新：步骤 8 为 `qmd embed`。
```

---

## 步骤 7：重建向量索引

环境变量生效、collection 配置好后，在仓库根目录跑：

```bash
qmd embed
```

验证三档搜索都正常：

```bash
qmd search "关键词"      # BM25 全文（无需模型）
qmd vsearch "语义查询"   # 向量搜索
qmd query "自然语言问题"  # 混合搜索（最高质量）
qmd status               # 状态检查
```

参考基线（132 文档 / 215 chunks）：embed 约 9s（tensor API 开启）/ 14s（未开启）。

---

## 完成检查清单

- [ ] `qmd` 在 PATH 中，`qmd status` 不报错
- [ ] `~/.cache/qmd/models/` 下有 3 个 `.gguf`
- [ ] `~/.zshenv` 里有 3 个 `QMD_*` 变量，新终端 `echo $QMD_EMBED_MODEL` 有值
- [ ] `scripts/patch-qmd-metal.sh` 跑过（或确认非 M5+/非 macOS 26 跳过）
- [ ] pandoc / yt-dlp / ffmpeg / poppler / tesseract 装齐
- [ ] `~/.claude/skills/youtube/SKILL.md` 里 `YT_DLP` 路径已改成新机器实际路径
- [ ] `~/.claude/projects/-<新路径>/settings.json` 创建，模型路径指向新 `$HOME`
- [ ] `~/.claude/projects/-<新路径>/memory/` 下 7 个文件齐全
- [ ] 重启 Claude Code，MCP qmd 工具可见
- [ ] `qmd embed` 成功，`qmd query` 返回结果
