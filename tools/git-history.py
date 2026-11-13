#!/usr/bin/env python3
"""Per-page git history for the vokobe2 info bar.

One `git log` pass over input/ emitting history.json:
  {"page-name": {"created": epoch, "modified": epoch, "edits": n}}

History is attributed to the *current* filename only -- it truncates at
renames (`--follow` per file across hundreds of files is far slower than
one log pass). Run from anywhere; history.json lands at the repo root and
is gitignored (it is derived from git itself)."""

import json
import os
import subprocess

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

out = subprocess.run(
    ["git", "log", "--format=@%ct", "--name-only", "--", "input/"],
    capture_output=True, text=True, cwd=ROOT, check=True).stdout

stats = {}
epoch = None
for line in out.splitlines():
    if line.startswith("@"):
        epoch = int(line[1:])
    elif epoch and line.startswith("input/") and line.endswith(".md"):
        name = line[len("input/"):-len(".md")]
        s = stats.setdefault(
            name, {"created": epoch, "modified": epoch, "edits": 0})
        s["edits"] += 1
        s["created"] = min(s["created"], epoch)
        s["modified"] = max(s["modified"], epoch)

with open(os.path.join(ROOT, "history.json"), "w") as f:
    json.dump(stats, f)
print(f"history: {len(stats)} pages")
