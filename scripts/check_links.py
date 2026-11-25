#!/usr/bin/env python3
"""离线检查 Markdown 相对链接是否指向真实文件（纯标准库，无第三方依赖）。

用法:
  python scripts/check_links.py          # 检查仓库内所有 *.md
  python scripts/check_links.py --root . # 指定仓库根目录

CI 里会跑这一步，防止文档里出现指向不存在文件的链接（例如图片路径写错层级）。
"""
from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

LINK = re.compile(r"\[[^\]]*\]\(([^)\s]+)\)")


def check(root: Path) -> list[tuple[Path, str]]:
    bad: list[tuple[Path, str]] = []
    for md in sorted(root.rglob("*.md")):
        if ".git" in md.parts:
            continue
        for match in LINK.finditer(md.read_text(encoding="utf-8")):
            target = match.group(1)
            if target.startswith(("http://", "https://", "mailto:", "#")):
                continue
            rel = target.split("#", 1)[0]
            if rel and not (md.parent / rel).exists():
                bad.append((md, target))
    return bad


def main() -> None:
    ap = argparse.ArgumentParser(description="检查 Markdown 相对链接")
    ap.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[1])
    args = ap.parse_args()
    root = args.root.resolve()
    bad = check(root)
    for md, target in bad:
        print(f"{md.relative_to(root)}: broken link -> {target}")
    print(f"{len(bad)} broken relative link(s)")
    raise SystemExit(1 if bad else 0)


if __name__ == "__main__":
    main()
