#!/usr/bin/env bash
# pdf_ocr.sh — 图片型PDF文字提取脚本
#
# 用法:
#   ./pdf_ocr.sh <pdf文件或目录> [输出目录]
#
# 功能:
#   - 自动检测PDF是否有文字层（text PDF vs image PDF）
#   - 有文字层：直接 pdftotext 提取
#   - 图片型PDF：pdftoppm → sips(TIFF) → tesseract OCR
#   - 支持单文件和批量目录处理
#   - 输出 .txt 文件（默认与PDF同目录，可指定输出目录）
#
# 依赖:
#   brew install poppler tesseract tesseract-lang
#   macOS自带: sips
#
# 示例:
#   ./pdf_ocr.sh ./raw/大类资产框架手册/          # 批量处理目录
#   ./pdf_ocr.sh ./raw/某文件.pdf /tmp/output/   # 单文件指定输出目录

set -euo pipefail

# ── 颜色输出 ──────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
info()  { echo -e "${GREEN}[OCR]${NC} $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
error() { echo -e "${RED}[ERR]${NC} $*" >&2; }

# ── 依赖检查 ──────────────────────────────────────────────
check_deps() {
    local missing=()
    for cmd in pdftotext pdftoppm pdfinfo sips tesseract; do
        command -v "$cmd" &>/dev/null || missing+=("$cmd")
    done
    if [[ ${#missing[@]} -gt 0 ]]; then
        error "缺少依赖: ${missing[*]}"
        echo "安装命令: brew install poppler tesseract tesseract-lang"
        exit 1
    fi
}

# ── 检测PDF是否有可提取文字 ────────────────────────────────
is_text_pdf() {
    local pdf="$1"
    local text
    text=$(pdftotext "$pdf" - 2>/dev/null | tr -d '[:space:]')
    [[ ${#text} -gt 50 ]]  # 超过50个非空白字符视为有文字层
}

# ── OCR单个PDF ─────────────────────────────────────────────
ocr_pdf() {
    local pdf="$1"
    local out_dir="$2"
    local basename
    basename=$(basename "$pdf" .pdf)
    local out_txt="$out_dir/${basename}.txt"
    local tmp_dir
    tmp_dir=$(mktemp -d)

    # 跳过已处理的文件
    if [[ -f "$out_txt" ]]; then
        warn "已存在，跳过: $(basename "$out_txt")"
        rm -rf "$tmp_dir"
        return 0
    fi

    info "处理: $(basename "$pdf")"

    # 方案A：文字型PDF，直接提取
    if is_text_pdf "$pdf"; then
        info "  → 文字型PDF，直接提取"
        pdftotext -layout "$pdf" "$out_txt" 2>/dev/null
        info "  ✓ 输出: $(basename "$out_txt")"
        rm -rf "$tmp_dir"
        return 0
    fi

    # 方案B：图片型PDF，走OCR管线
    local page_count
    page_count=$(pdfinfo "$pdf" 2>/dev/null | grep "Pages:" | awk '{print $2}')
    info "  → 图片型PDF（${page_count}页），启动OCR..."

    # Step1: PDF → PPM（150dpi，中文识别够用，速度快）
    pdftoppm -r 150 "$pdf" "$tmp_dir/page" 2>/dev/null

    # Step2: PPM → TIFF（tesseract在macOS上偏好TIFF）
    local page_texts=()
    for ppm in "$tmp_dir"/page-*.ppm; do
        [[ -f "$ppm" ]] || continue
        local page_num
        page_num=$(basename "$ppm" .ppm | sed 's/page-//')
        local tiff="$tmp_dir/page-${page_num}.tiff"
        local page_txt="$tmp_dir/page-${page_num}"

        sips -s format tiff "$ppm" --out "$tiff" &>/dev/null

        # Step3: Tesseract OCR（中英双语）
        tesseract "$tiff" "$page_txt" -l chi_sim+eng \
            --psm 3 \
            -c preserve_interword_spaces=1 \
            2>/dev/null

        page_texts+=("${page_txt}.txt")
    done

    # Step4: 合并多页结果
    if [[ ${#page_texts[@]} -gt 0 ]]; then
        cat "${page_texts[@]}" > "$out_txt" 2>/dev/null
        local line_count
        line_count=$(wc -l < "$out_txt")
        info "  ✓ OCR完成，${line_count}行 → $(basename "$out_txt")"
    else
        warn "  ✗ OCR失败，无输出页面"
    fi

    rm -rf "$tmp_dir"
}

# ── 保存图表（PDF页面 → JPG，用于wiki图片引用）──────────────
save_images() {
    local pdf="$1"
    local assets_dir="$2"
    local basename
    basename=$(basename "$pdf" .pdf)

    mkdir -p "$assets_dir"
    pdftoppm -r 120 -jpeg "$pdf" "$assets_dir/${basename}" 2>/dev/null
    local count
    count=$(ls "${assets_dir}/${basename}"*.jpg 2>/dev/null | wc -l | tr -d ' ')
    [[ $count -gt 0 ]] && info "  📷 保存${count}张页面图 → $assets_dir"
}

# ── 主流程 ─────────────────────────────────────────────────
main() {
    check_deps

    local input="${1:-}"
    local out_dir="${2:-}"

    if [[ -z "$input" ]]; then
        echo "用法: $0 <pdf文件或目录> [输出目录]"
        exit 1
    fi

    # 单文件
    if [[ -f "$input" ]]; then
        [[ -z "$out_dir" ]] && out_dir="$(dirname "$input")"
        mkdir -p "$out_dir"
        ocr_pdf "$input" "$out_dir"
        return
    fi

    # 目录：递归查找所有PDF
    if [[ -d "$input" ]]; then
        [[ -z "$out_dir" ]] && out_dir="$input"
        local pdfs=()
        while IFS= read -r -d '' f; do
            pdfs+=("$f")
        done < <(find "$input" -name "*.pdf" -print0 | sort -z)

        local total=${#pdfs[@]}
        info "发现 $total 个PDF文件"

        local done=0 skipped=0 failed=0
        for pdf in "${pdfs[@]}"; do
            local pdf_out_dir
            # 保持原目录结构
            if [[ "$out_dir" == "$input" ]]; then
                pdf_out_dir="$(dirname "$pdf")"
            else
                local rel
                rel=$(dirname "${pdf#$input/}")
                pdf_out_dir="$out_dir/$rel"
                mkdir -p "$pdf_out_dir"
            fi

            if ocr_pdf "$pdf" "$pdf_out_dir"; then
                ((done++)) || true
            else
                ((failed++)) || true
            fi
        done

        echo ""
        info "完成: $done 个 | 跳过(已存在): $skipped 个 | 失败: $failed 个"
        return
    fi

    error "输入路径不存在: $input"
    exit 1
}

main "$@"
