#!/usr/bin/env python3
"""Update the (modified "...") field of all input/*.md pages to match the
file's modification date."""
import os
import re
import sys
from datetime import datetime
from pathlib import Path

# script dir is on sys.path; meta.py's finder is string-aware (parens
# inside quoted strings don't end the block early)
from meta import meta_block

ROOT = Path(__file__).parent.parent  # tools/ is one level below the repo root
INPUT = ROOT / "input"

def main():
    ok, skipped, failed = 0, [], []

    for path in sorted(INPUT.glob("*.md")):
        name = path.name
        text = path.read_text()

        block = meta_block(text)
        if not block:
            failed.append((name, "no/unbalanced meta block"))
            continue

        start, end = block
        meta = text[start:end]

        mod = re.search(r'\(modified\s+"[^"]*"', meta)
        if not mod:
            skipped.append((name, "no modified field"))
            continue

        mtime = datetime.fromtimestamp(path.stat().st_mtime).strftime("%Y-%m-%d")
        current = mod.group(0).split('"')[1]
        if not re.fullmatch(r"\d{4}-\d{2}-\d{2}", current):
            failed.append((name, f"malformed modified value {current!r}"))
            continue
        if current == mtime:
            continue

        meta = meta[:mod.start()] + mod.group(0).replace(current, mtime, 1) + meta[mod.end():]
        stat = path.stat()
        path.write_text(text[:start] + meta + text[end:])
        # keep the mtime so repeated runs stay idempotent
        os.utime(path, (stat.st_atime, stat.st_mtime))
        print(f"  {name}: {current} -> {mtime}")
        ok += 1

    if ok:
        print(f"[+] modified dates updated: {ok}")
    else:
        print("[.] modified dates unchanged")
    if os.environ.get("VERBOSE") == "1":
        for name, why in skipped:
            print(f"  skipped {name}: {why}")
    for name, why in failed:
        print(f"  FAILED  {name}: {why}")
    if failed:
        sys.exit(1)

if __name__ == "__main__":
    main()
