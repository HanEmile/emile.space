#!/usr/bin/env python3
"""Add (date "<published>") to pages listed in missing.txt."""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).parent
INPUT = ROOT / "input"

def main():
    names = []
    for line in (ROOT / "missing.txt").read_text().splitlines()[1:]:
        name = line.strip()
        if name:
            names.append(name)

    ok, skipped, failed = 0, [], []

    for name in names:
        path = INPUT / f"{name}.md"
        text = path.read_text()

        # operate on the first (meta ...) block only
        meta_match = re.search(r"\(meta\b", text)
        if not meta_match:
            failed.append((name, "no meta block"))
            continue

        # find the balanced end of the meta block
        depth = 0
        end = None
        for i in range(meta_match.start(), len(text)):
            if text[i] == "(":
                depth += 1
            elif text[i] == ")":
                depth -= 1
                if depth == 0:
                    end = i + 1
                    break
        if end is None:
            failed.append((name, "unbalanced meta block"))
            continue

        meta = text[meta_match.start():end]

        if re.search(r"\((?:date|date-range)\b", meta):
            skipped.append((name, "already has date"))
            continue

        pub = re.search(r'\(published\s+"([^"]+)"', meta)
        if not pub:
            failed.append((name, "no published field"))
            continue

        date_line = f'  (date "{pub.group(1)}")\n'

        # insert after (modified ...) line if present, else after (published ...) line
        anchor = re.search(r"^\s*\(modified\b[^\n]*\n", meta, re.M) or \
                 re.search(r"^\s*\(published\b[^\n]*\n", meta, re.M)
        insert_at = anchor.end()
        new_meta = meta[:insert_at] + date_line + meta[insert_at:]

        path.write_text(text[:meta_match.start()] + new_meta + text[end:])
        ok += 1

    print(f"added date: {ok}")
    for name, why in skipped:
        print(f"  skipped {name}: {why}")
    for name, why in failed:
        print(f"  FAILED  {name}: {why}")
    if failed:
        sys.exit(1)

if __name__ == "__main__":
    main()
