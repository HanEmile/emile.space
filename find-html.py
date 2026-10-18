#!/usr/bin/env python3
"""
find-html.py

Scans v2/input/*.md for raw HTML that survived the migration and may be broken:
  - <img ...>  (old src paths)
  - <a href=...>  (old internal links)
  - other block-level HTML tags (<div>, <p>, <pre>, <br>, <table>, ...)

Prints a per-file report, then a summary sorted by hit count.

Usage:
    python3 find-html.py [--links-only] [--tag TAG]

Options:
    --links-only   only show <a href> hits
    --tag TAG      only show a specific HTML tag (e.g. --tag img)
"""

import re
import sys
from pathlib import Path
from collections import defaultdict

INPUT = Path(__file__).parent / "input"

# Patterns we care about
PATTERNS = [
    ("img",    re.compile(r'<img\b[^>]*>', re.IGNORECASE)),
    ("a",      re.compile(r'<a\s+[^>]*href\s*=\s*["\'][^"\']*["\'][^>]*>', re.IGNORECASE)),
    ("div",    re.compile(r'</?div\b[^>]*>', re.IGNORECASE)),
    ("pre",    re.compile(r'</?pre\b[^>]*>', re.IGNORECASE)),
    ("p",      re.compile(r'</?p\b[^>]*>', re.IGNORECASE)),
    ("br",     re.compile(r'<br\s*/?>', re.IGNORECASE)),
    ("span",   re.compile(r'</?span\b[^>]*>', re.IGNORECASE)),
    ("style",  re.compile(r'<[^>]+style\s*=', re.IGNORECASE)),
    ("other",  re.compile(r'<(?!meta|!DOCTYPE|!--)[a-zA-Z][a-zA-Z0-9]*\b[^>]*>', re.IGNORECASE)),
]

def is_inside_code_fence(lines, line_idx):
    """Return True if the given line is inside a ```...``` block."""
    in_fence = False
    for i, line in enumerate(lines):
        if i == line_idx:
            return in_fence
        if line.strip().startswith("```"):
            in_fence = not in_fence
    return in_fence

def is_inside_blockquote(line):
    """Lines starting with > are blockquotes (used as code in vokobe)."""
    return line.lstrip().startswith(">")

def scan_file(path, tag_filter=None):
    text = path.read_text(encoding="utf-8", errors="replace")
    lines = text.splitlines()
    hits = []  # (line_num, tag, match_text, full_line)

    active = [(name, pat) for name, pat in PATTERNS
              if tag_filter is None or name == tag_filter]

    for lineno, line in enumerate(lines, start=1):
        if is_inside_code_fence(lines, lineno - 1):
            continue
        if is_inside_blockquote(line):
            continue
        for name, pat in active:
            for m in pat.finditer(line):
                hits.append((lineno, name, m.group(), line.strip()))

    # deduplicate identical matches on the same line
    seen = set()
    deduped = []
    for h in hits:
        key = (h[0], h[2])
        if key not in seen:
            seen.add(key)
            deduped.append(h)
    return deduped


def main():
    links_only = "--links-only" in sys.argv
    tag_filter = None
    if "--tag" in sys.argv:
        idx = sys.argv.index("--tag")
        if idx + 1 < len(sys.argv):
            tag_filter = sys.argv[idx + 1]

    if links_only:
        tag_filter = "a"

    files = sorted(INPUT.glob("*.md"))
    summary = []  # (hit_count, filename, hits)

    for f in files:
        hits = scan_file(f, tag_filter)
        if hits:
            summary.append((len(hits), f.name, hits))

    summary.sort(key=lambda x: -x[0])

    total_hits = sum(c for c, _, _ in summary)
    total_files = len(summary)

    print(f"Found {total_hits} raw-HTML hits across {total_files} files\n")
    print("=" * 72)

    for count, fname, hits in summary:
        print(f"\n{'─' * 72}")
        print(f"  {fname}  ({count} hit{'s' if count != 1 else ''})")
        print(f"{'─' * 72}")
        for lineno, tag, match, full_line in hits:
            # truncate long lines
            display = full_line if len(full_line) <= 100 else full_line[:97] + "..."
            print(f"  L{lineno:4d}  [{tag:6s}]  {display}")

    print(f"\n{'=' * 72}")
    print(f"Summary: {total_hits} hits in {total_files}/{len(files)} files")
    if total_files:
        print("\nTop offenders:")
        for count, fname, _ in summary[:10]:
            bar = "█" * min(count, 40)
            print(f"  {fname:<45} {bar} {count}")


if __name__ == "__main__":
    main()
