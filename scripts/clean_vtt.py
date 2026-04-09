#!/usr/bin/env python3
"""
clean_vtt.py — 将 YouTube VTT 字幕文件清洗为纯文本

用法：
    python3 scripts/clean_vtt.py <input.vtt> [output.txt]

如果不指定 output，则输出到 stdout。

处理逻辑：
    1. 去掉 VTT 头部（WEBVTT 及 metadata）
    2. 去掉时间戳行（00:00:00.000 --> ...）
    3. 去掉 position/align 等样式标注
    4. 去掉 HTML 标签（<c>, <b> 等）
    5. 相邻重复行去重（VTT 滚动字幕常见）
    6. 合并空行
"""

import re
import sys


def clean_vtt(content: str) -> str:
    # 去掉 VTT 头部
    content = re.sub(r"^WEBVTT\n.*?\n\n", "", content, count=1, flags=re.DOTALL)

    lines = content.split("\n")
    text_lines = []
    seen = set()

    for line in lines:
        line = line.strip()
        if not line:
            continue
        # 跳过时间戳行
        if re.match(r"^\d{2}:\d{2}", line):
            continue
        # 跳过样式标注行
        if "align:" in line or "position:" in line:
            continue
        # 去掉 HTML 标签
        line = re.sub(r"<[^>]+>", "", line)
        line = line.strip()
        if not line:
            continue
        # 去重（VTT 滚动字幕会重复上一行）
        if line not in seen:
            seen.add(line)
            text_lines.append(line)

    return "\n".join(text_lines)


def main():
    if len(sys.argv) < 2:
        print(f"用法: {sys.argv[0]} <input.vtt> [output.txt]", file=sys.stderr)
        sys.exit(1)

    input_path = sys.argv[1]
    with open(input_path, "r", encoding="utf-8") as f:
        content = f.read()

    result = clean_vtt(content)

    if len(sys.argv) >= 3:
        output_path = sys.argv[2]
        with open(output_path, "w", encoding="utf-8") as f:
            f.write(result)
        count = result.count("\n") + 1
        print(f"已清洗: {input_path} -> {output_path} ({count} 行)", file=sys.stderr)
    else:
        print(result)


if __name__ == "__main__":
    main()
