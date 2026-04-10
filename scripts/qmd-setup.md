# qmd 安装与配置记录

> 记录于 2026-04-10，macOS 26.4 (Tahoe) / Apple M5 / Node.js 25.9.0

## 安装

```bash
npm install -g @tobilu/qmd    # v2.1.0
brew install cmake             # 本地编译 llama.cpp 需要
```

## 索引配置

```bash
# 在 personal-wiki 根目录下执行
qmd collection add wiki --name wiki
qmd context add qmd://wiki "个人知识库：包含 entities、concepts、events、synthesis、macro 等页面"
qmd embed   # 需要先解决下面两个问题
```

## 遇到的问题

### 问题 1：`qmd embed` 卡在 "Gathering information"

**现象：** 执行 `qmd embed` / `qmd vsearch` / `qmd query` 时无限转圈 "Gathering information"。

**根因：** qmd 通过 `node-llama-cpp` 的 `resolveModelFile()` 解析 `hf:` 开头的模型 URI。该函数使用 `ipull` 库通过 Node.js `fetch` 直连 HuggingFace CDN 下载模型或获取元数据。**Node.js `fetch` 不走系统代理**，导致网络请求 hang。

**下载链路：**
```
qmd CLI
  → llm.js: resolveModel(modelUri)
    → node-llama-cpp: resolveModelFile("hf:ggml-org/...", cacheDir)
      → ipull 库: fetch("https://huggingface.co/...") ← 卡在这里
        → 下载到 ~/.cache/qmd/models/
```

"Gathering information" 是 `ipull` 下载库的 loading 提示文本，不是 qmd 自己的。

**解决方案：** 手动用 curl 下载三个模型文件，然后通过环境变量指向本地路径绕过 `ipull`。

```bash
# 1. 手动下载模型（curl 走系统代理，可正常下载）
curl -L -o ~/.cache/qmd/models/embeddinggemma-300M-Q8_0.gguf \
  "https://huggingface.co/ggml-org/embeddinggemma-300M-GGUF/resolve/main/embeddinggemma-300M-Q8_0.gguf"

curl -L -o ~/.cache/qmd/models/qmd-query-expansion-1.7B-q4_k_m.gguf \
  "https://huggingface.co/tobil/qmd-query-expansion-1.7B-gguf/resolve/main/qmd-query-expansion-1.7B-q4_k_m.gguf"

curl -L -o ~/.cache/qmd/models/qwen3-reranker-0.6b-q8_0.gguf \
  "https://huggingface.co/ggml-org/Qwen3-Reranker-0.6B-Q8_0-GGUF/resolve/main/qwen3-reranker-0.6b-q8_0.gguf"

# 2. 设置环境变量（写入 ~/.zshenv，而非 ~/.zshrc）
#    重要：必须放在 ~/.zshenv 而不是 ~/.zshrc！
#    - ~/.zshrc 仅在交互式 shell 中加载
#    - ~/.zshenv 对所有 zsh 进程生效，包括 Claude Code 的 Bash 工具
#    - 如果放在 ~/.zshrc，Claude Code 中运行 qmd embed 会因为缺少环境变量
#      而走 ipull 网络请求，导致无限卡在 "Gathering information"
export QMD_EMBED_MODEL="$HOME/.cache/qmd/models/embeddinggemma-300M-Q8_0.gguf"
export QMD_GENERATE_MODEL="$HOME/.cache/qmd/models/qmd-query-expansion-1.7B-q4_k_m.gguf"
export QMD_RERANK_MODEL="$HOME/.cache/qmd/models/qwen3-reranker-0.6b-q8_0.gguf"

# 3. 现在可以正常运行
qmd embed                          # 生成向量索引
qmd vsearch "语义搜索测试"          # 向量搜索
qmd query "混合搜索测试"            # 混合搜索（BM25 + 向量 + reranking）
```

**模型用途：**

| 环境变量 | 模型 | 大小 | 用途 |
|----------|------|------|------|
| `QMD_EMBED_MODEL` | embeddinggemma-300M | ~313MB | 文档/查询向量化 |
| `QMD_GENERATE_MODEL` | qmd-query-expansion-1.7B | ~1.1GB | 查询扩展（将用户查询拆分为多个搜索角度） |
| `QMD_RERANK_MODEL` | Qwen3-Reranker-0.6B | ~690MB | 搜索结果重排序 |

### 问题 2：`ggml_metal_library_init_from_source: error compiling source`

**现象：** 每次运行 qmd 都会输出此警告，tensor API 被禁用。

**根因：** llama.cpp (b8390) 在 Metal 初始化时编译一个 dummy kernel 来验证 tensor API 是否可用（`ggml-metal-device.m:673-720`）。该 kernel 使用 `[MTLDevice newLibraryWithSource:]` 运行时编译，**不依赖 Xcode 或 `xcrun metal`**（Metal 运行时编译器是系统内置的）。

真正的失败原因是 **macOS 26 的 MetalPerformancePrimitives 框架新增了约束**：

```
static_assert: "At least one of M or N must be a multiple of 16"
```

而 llama.cpp 的 dummy kernel 使用了 `matmul2d_descriptor(8, 8, dynamic_extent)`（M=8, N=8），不满足新约束。

**关键代码位置：** `ggml/src/ggml-metal/ggml-metal-device.m` 第 693 行和第 743 行（f16 和 bf16 两处）

**实际影响：** tensor API 被禁用。tensor API 是 Metal 4 引入的硬件加速矩阵运算接口（仅 M5/A19 及以上支持），禁用后回退到 simdgroup 实现。Metal GPU 推理本身正常：
- GPU type: metal（Metal 后端激活）
- GPU offloading: true（模型推理在 GPU 上）
- GPU layers: 25（全部层 offload 到 GPU）

**修复方法：** 将两处 `matmul2d_descriptor(8, 8, dynamic_extent)` 改为 `matmul2d_descriptor(16, 16, dynamic_extent)`，然后从源码重新编译并替换预编译 binary。

```bash
# 1. 修改源码（两处，f16 和 bf16 的 dummy kernel）
FILE=/opt/homebrew/lib/node_modules/@tobilu/qmd/node_modules/node-llama-cpp/llama/llama.cpp/ggml/src/ggml-metal/ggml-metal-device.m
sed -i '' 's/matmul2d_descriptor(8, 8, dynamic_extent)/matmul2d_descriptor(16, 16, dynamic_extent)/g' "$FILE"

# 2. 从源码重新编译（需要 cmake）
cd /opt/homebrew/lib/node_modules/@tobilu/qmd
npx node-llama-cpp source build --gpu metal

# 3. 将本地编译的 binary 替换预编译版本
PREBUILT=node_modules/@node-llama-cpp/mac-arm64-metal/bins/mac-arm64-metal
LOCAL=node_modules/node-llama-cpp/llama/localBuilds/mac-arm64-metal/Release
for f in "$LOCAL"/*; do cp "$f" "$PREBUILT/$(basename $f)"; done
```

修复后 Metal 输出干净，无任何警告，tensor API 正常启用。

**自动化脚本：** `scripts/patch-qmd-metal.sh` 封装了以上步骤（幂等，可重复执行）：

```bash
./scripts/patch-qmd-metal.sh   # patch + 编译 + 替换，已 patch 则跳过
```

**注意：** `npm update @tobilu/qmd` 会覆盖此 patch，更新后需重新运行脚本。上游 llama.cpp 修复后此问题会自动消失。

**性能对比（132 文档 / 215 chunks）：**

| | 有 Tensor API | 无 Tensor API |
|--|--|--|
| embed 耗时 | 9s | 14s |
| 提升 | **+36%** | baseline |

## Claude Code MCP 配置

项目级配置文件 `.claude/projects/-Users-yangqi-Documents-personal-wiki/settings.json`：

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

重启 Claude Code 后 MCP 工具自动可用：`query` / `get` / `multi_get` / `status`。

## 日常维护

```bash
# 新增文档后更新索引
qmd collection update wiki    # 重新扫描文件
qmd embed                     # 为新文档生成向量

# 搜索
qmd search "关键词"            # BM25 全文搜索（无需模型）
qmd vsearch "语义查询"         # 向量搜索
qmd query "自然语言问题"       # 混合搜索（最高质量）

# 状态检查
qmd status
```
