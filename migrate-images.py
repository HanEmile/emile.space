#!/usr/bin/env python3
"""
migrate-images.py

Flattens all image references into v2/input/ with pagename-filename naming.

Handles two cases:
  A) raw <img src="...">        → not yet migrated
  B) already-converted ![](/page/file) → from a previous subdir-based run

In both cases: copies the image to input/<page>-<file> and rewrites the
reference to ![]( /<page>-<file>).
"""

import re
import shutil
from pathlib import Path

ROOT  = Path(__file__).parent.parent
OLD   = ROOT / "in"
INPUT = Path(__file__).parent / "input"

PAGES = [
    ("blog/2021/02-04-menger-sponge",                                   "menger-sponge"),
    ("events/2012/08_korsika",                                           "korsika"),
    ("events/2017/05_gpn17",                                             "gpn17"),
    ("events/2017/07_dolomiten",                                         "dolomiten"),
    ("events/2018/03_ski_obertauern",                                    "ski-obertauern"),
    ("events/2018/05_egypt",                                             "egypt"),
    ("events/2018/05_gpn18",                                             "gpn18"),
    ("events/2018/10_rhodos",                                            "rhodos"),
    ("events/2019/05_gpn19_karlsruhe",                                   "gpn19"),
    ("events/2019/08_cccamp19_mildenberg",                               "cccamp19"),
    ("events/2019/12_36c3_leipzig",                                      "36c3"),
    ("events/2021/07_wakeboarding_wedau",                                "wakeboarding-wedau"),
    ("events/2022/01-ski-fiss-ladis",                                    "ski-fiss-ladis"),
    ("events/2022/04-28_bountyconedu_madrid",                            "bountyconedu-madrid"),
    ("events/2022/05-19-gpn20-karlsruhe",                                "gpn20"),
    ("events/2022/06-02-emf-camp-eastnor",                               "emf-camp-eastnor"),
    ("events/2022/06-29-troopers-heidelberg",                            "troopers-heidelberg"),
    ("events/2022/07-22-mch-zeewolde",                                   "mch-zeewolde"),
    ("events/2022/08-01-windsurf-portugal-viana-do-castelo",             "windsurf-portugal"),
    ("events/2022/08-08-blackhat-las-vegas",                             "blackhat-2022"),
    ("events/2022/08-11-defcon-30-las-vegas",                            "defcon30"),
    ("events/2023/05-defi-wind",                                         "defi-wind"),
    ("events/2023/08-cccamp",                                            "cccamp23"),
    ("events/2023/08-defcon",                                            "defcon-2023"),
    ("events/2024/05-koblenz-freiburg-by-bike",                          "koblenz-freiburg-by-bike"),
    ("ctf/writeups/2020/hacklu/confessions",                             "writeup-confessions"),
    ("ctf/writeups/2020/nahamconCTF/complete-flag-leak",                 "writeup-complete-flag-leak"),
    ("projects/astrophotography",                                        "astrophotography"),
    ("projects/glitchart",                                               "glitchart"),
    ("projects/jufo/2019-galaxy-simulation",                             "jufo-galaxy-simulation"),
    ("projects/led-cube",                                                "led-cube"),
    ("publications/2018/glitch-gallery",                                 "glitch-gallery"),
    ("publications/2019/Galaxy-Simluation",                              "galaxy-simulation"),
    ("publications/2020/Accelerating-simulations-by-clustering-bodies-using-the-Barnes-Hut-algorithm",
                                                                         "accelerating-simulations"),
    ("sport/windsurf",                                                   "windsurf"),
    ("sport/windsurf/knowledge/fin",                                     "windsurf-fin"),
]

old_dir_of = {name: OLD / path for path, name in PAGES}

IMG_TAG_RE  = re.compile(r'<img\b[^>]*/?>(?:\s*</img>)?', re.IGNORECASE | re.DOTALL)
SRC_RE      = re.compile(r'\bsrc=["\']([^"\']+)["\']', re.IGNORECASE)
SUBDIR_RE   = re.compile(r'!\[\]\(/([^/\n]+)/([^\)\n]+)\)')  # ![](/page/file) – no cross-line matches


def strip_rel(src: str) -> str:
    s = src.strip()
    for prefix in ("./", "/"):
        if s.startswith(prefix):
            s = s[len(prefix):]
    return s


def copy_and_flatten(page_name: str, bare_filename: str):
    """
    Locates the source image and copies it to input/<page>-<file>.
    Returns the new flat filename, or None if not found.
    """
    new_name = f"{page_name}-{bare_filename}"
    dest = INPUT / new_name
    if dest.exists():
        return new_name  # already done

    old_dir = old_dir_of.get(page_name)
    candidates = [old_dir / bare_filename] if old_dir else []
    candidates.append(INPUT / bare_filename)

    found = next((c for c in candidates if c.exists()), None)
    if found is None:
        return None

    shutil.copy2(found, dest)
    print(f"  copied   {found.relative_to(ROOT)}  →  {new_name}")
    return new_name


def migrate_file(md_path: Path) -> int:
    page = md_path.stem
    text = md_path.read_text(encoding="utf-8")
    changes = 0

    # ── A: convert raw <img src="..."> tags ──────────────────────────────────
    def replace_img_tag(m: re.Match) -> str:
        nonlocal changes
        tag = m.group(0)
        src_m = SRC_RE.search(tag)
        if not src_m:
            return tag
        bare = strip_rel(src_m.group(1))
        new_name = copy_and_flatten(page, bare)
        if new_name is None:
            print(f"  MISSING  {page}: {src_m.group(1)}")
            return tag
        changes += 1
        return f"![](/{new_name})"

    text = IMG_TAG_RE.sub(replace_img_tag, text)

    # ── B: fix already-converted ![](/page/file) paths ───────────────────────
    def replace_subdir_ref(m: re.Match) -> str:
        nonlocal changes
        ref_page, bare = m.group(1), m.group(2)
        new_name = copy_and_flatten(ref_page, bare)
        if new_name is None:
            print(f"  MISSING  {page}: /{ref_page}/{bare}")
            return m.group(0)
        changes += 1
        return f"![](/{new_name})"

    text = SUBDIR_RE.sub(replace_subdir_ref, text)

    if changes:
        md_path.write_text(text, encoding="utf-8")
        print(f"  updated  {md_path.name}  ({changes} image(s))")
    return changes


def main():
    total = 0
    for md in sorted(INPUT.glob("*.md")):
        total += migrate_file(md)
    print(f"\nDone: {total} image reference(s) migrated.")


if __name__ == "__main__":
    main()
