#!/bin/bash
# patch-qmd-metal.sh — 修复 llama.cpp tensor API 在 macOS 26+ 上的编译失败
# 根因：macOS 26 的 MetalPerformancePrimitives 要求 matmul2d M 或 N >= 16
# 详见 scripts/qmd-setup.md

set -euo pipefail

QMD_ROOT="$(npm root -g)/@tobilu/qmd"
DEVICE_M="$QMD_ROOT/node_modules/node-llama-cpp/llama/llama.cpp/ggml/src/ggml-metal/ggml-metal-device.m"
PREBUILT="$QMD_ROOT/node_modules/@node-llama-cpp/mac-arm64-metal/bins/mac-arm64-metal"
LOCAL_BUILD="$QMD_ROOT/node_modules/node-llama-cpp/llama/localBuilds/mac-arm64-metal/Release"

# 检查是否需要 patch
if ! grep -q 'matmul2d_descriptor(8, 8, dynamic_extent)' "$DEVICE_M" 2>/dev/null; then
    echo "✓ 已经 patch 过，无需操作"
    # 确认 binary 也是 patched 版本
    if [ -d "$LOCAL_BUILD" ] && [ -f "$LOCAL_BUILD/llama-addon.node" ]; then
        LOCAL_HASH=$(md5 -q "$LOCAL_BUILD/llama-addon.node")
        PREBUILT_HASH=$(md5 -q "$PREBUILT/llama-addon.node")
        if [ "$LOCAL_HASH" = "$PREBUILT_HASH" ]; then
            echo "✓ Binary 已替换"
            exit 0
        fi
    fi
fi

echo "→ Patching ggml-metal-device.m ..."
sed -i '' 's/matmul2d_descriptor(8, 8, dynamic_extent)/matmul2d_descriptor(16, 16, dynamic_extent)/g' "$DEVICE_M"
echo "✓ Source patched"

echo "→ Rebuilding node-llama-cpp (需要 cmake) ..."
cd "$QMD_ROOT"
npx node-llama-cpp source build --gpu metal

echo "→ Replacing prebuilt binaries ..."
for f in "$LOCAL_BUILD"/*; do
    cp "$f" "$PREBUILT/$(basename "$f")"
done

echo "✓ Done! Tensor API 已启用，验证："
node --input-type=module -e "
import {getLlama} from 'node-llama-cpp';
const l = await getLlama({gpu:'metal'});
console.log('  GPU:', l.gpu, '| Offloading:', l.supportsGpuOffloading);
" 2>&1 | grep -v '^\[node-llama-cpp\]' || true
