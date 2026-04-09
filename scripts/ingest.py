#!/usr/bin/env python3
"""
ingest.py — 将 inbox/ 中的文件批量移入 raw/
使用方式：python3 scripts/ingest.py
"""
import os
import shutil
from datetime import date

INBOX = os.path.join(os.path.dirname(__file__), "../inbox")
RAW = os.path.join(os.path.dirname(__file__), "../raw")

def main():
    files = [f for f in os.listdir(INBOX) if not f.startswith(".")]
    if not files:
        print("inbox/ 为空，无文件需要处理。")
        return
    print(f"发现 {len(files)} 个文件：")
    for f in files:
        print(f"  - {f}")
    confirm = input("\n确认移入 raw/？(y/n) ")
    if confirm.lower() != "y":
        print("已取消。")
        return
    for f in files:
        src = os.path.join(INBOX, f)
        dst = os.path.join(RAW, f)
        shutil.move(src, dst)
        print(f"  移动：{f} -> raw/")
    print(f"\n完成。共处理 {len(files)} 个文件。")
    print("请将这些文件内容发送给 LLM 执行 ingest 操作。")

if __name__ == "__main__":
    main()
