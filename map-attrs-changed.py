#!/usr/bin/env python3
"""Do the (location ...) / (map ...) attrs in input/*.md differ from the
last publish (map-cache/.map-attrs.stamp)?  Exit 1 when changed (stamp
updated), 0 when unchanged.  publish.sh uses this to skip the
dump-missing-regions + extract pass (a second full site render) on
publishes that cannot possibly need new map data."""
import glob, hashlib, os, re, sys

ROOT = os.path.dirname(os.path.abspath(__file__))
STAMP = os.path.join(ROOT, "map-cache", ".map-attrs.stamp")

h = hashlib.sha256()
for path in sorted(glob.glob(os.path.join(ROOT, "input", "*.md"))):
    text = open(path, encoding="utf8", errors="replace").read()
    m = re.search(r"\(meta\b", text)
    if not m:
        continue
    # hash the meta block only: prose edits can't add regions
    depth = 0
    for i in range(m.start(), len(text)):
        if text[i] == "(":
            depth += 1
        elif text[i] == ")":
            depth -= 1
            if depth == 0:
                h.update(text[m.start():i + 1].encode())
                break

new = h.hexdigest()
old = open(STAMP).read().strip() if os.path.exists(STAMP) else ""
if old == new:
    sys.exit(0)
open(STAMP, "w").write(new + "\n")
sys.exit(1)
