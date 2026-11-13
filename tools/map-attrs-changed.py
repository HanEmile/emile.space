#!/usr/bin/env python3
"""Do the (location ...) / (map ...) attrs in input/*.md differ from the
last publish (map-cache/.map-attrs.stamp)?  Exit 1 when changed (stamp
updated), 0 when unchanged.  publish.sh uses this to skip the
dump-missing-regions + extract pass (a second full site render) on
publishes that cannot possibly need new map data."""
import glob, hashlib, os, sys

import meta as meta_mod
from mapconsts import ROOT, MAP_ATTRS_STAMP

STAMP = MAP_ATTRS_STAMP

h = hashlib.sha256()
for path in sorted(glob.glob(os.path.join(ROOT, "input", "*.md"))):
    text = open(path, encoding="utf8", errors="replace").read()
    block = meta_mod.meta_block(text)
    if not block:
        continue
    # hash the meta block only: prose edits can't add regions
    h.update(text[block[0]:block[1]].encode())

new = h.hexdigest()
old = open(STAMP).read().strip() if os.path.exists(STAMP) else ""
if old == new:
    sys.exit(0)
open(STAMP, "w").write(new + "\n")
sys.exit(1)
