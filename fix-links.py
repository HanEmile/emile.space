#!/usr/bin/env python3
"""fix-links.py — fixes old-path links, renames space-in-filename assets, copies static files."""

import re, shutil
from pathlib import Path

ROOT  = Path(__file__).parent
INPUT = ROOT / "input"

# ── 1. old path → new flat path ────────────────────────────────────────────
PATH_MAP = {
    "/blog/2020/10-10-r2wars/":                           "/r2wars",
    "/blog/2021/07-12-monorepo":                          "/monorepo",
    "/blog/2021/12-26-relaunch":                          "/relaunch",
    "/ctf/resources/assembly-basics/":                    "/assembly-basics",
    "/ctf/resources/automated-program-analysis/":         "/automated-program-analysis",
    "/ctf/resources/fuzzing/":                            "/fuzzing",
    "/ctf/resources/heap/":                               "/heap",
    "/ctf/resources/infoleak/":                           "/infoleak",
    "/ctf/resources/kernel/":                             "/kernel",
    "/ctf/resources/linux/":                              "/linux",
    "/ctf/resources/mitigations/":                        "/mitigations",
    "/ctf/resources/overflow/":                           "/overflow",
    "/ctf/resources/race-conditions/":                    "/race-conditions",
    "/ctf/resources/reversing/":                          "/reversing",
    "/ctf/resources/rop/":                                "/rop",
    "/ctf/resources/shellcode/":                          "/shellcode",
    "/ctf/resources/symbolic-execution/":                 "/symbolic-execution",
    "/ctf/teams/ALLES/":                                  "/alles",
    "/ctf/teams/flexerilla/":                             "/flexerilla",
    "/ctf/writeups/2020/nahamconCTF/complete-flag-leak/": "/writeup-complete-flag-leak",
    "/ctf/writeups/2020/redpwnCTF/pseudo-key/":           "/writeup-pseudo-key",
    "/ctf/writeups/2020/redpwnCTF/pseudo-key":            "/writeup-pseudo-key",
    "/events/2017/05-GPN17/":                             "/gpn17",
    "/events/2017/12-34c3/":                              "/34c3",
    "/events/2018/03_ski_obertauern/":                    "/ski-obertauern",
    "/events/2018/05_egypt/":                             "/egypt",
    "/events/2018/10_rhodos/":                            "/rhodos",
    "/events/2019/12-36c3/":                              "/36c3",
    "/events/2019/12_ski_st_anton/":                      "/ski-st-anton",
    "/events/2021/07_wakeboarding_wedau/":                "/wakeboarding-wedau",
    "/events/2022/01-ski-fiss-ladis/":                    "/ski-fiss-ladis",
    "/events/2022/01_ski_fiss_ladis/":                    "/ski-fiss-ladis",
    "/events/2022/03-04_bouldern_superblock":             "/bouldern-superblock",
    "/events/2023/04-easterhegg":                         "/easterhegg-2023",
    "/events/2023/04-easterhegg/":                        "/easterhegg-2023",
    "/events/2023/05-defi-wind/":                         "/defi-wind",
    "/events/2023/06-GPN/":                               "/gpn23",
    "/events/2023/12-37c3":                               "/37c3",
    "/events/2024/10-mrmcd-darmstadt/r2wars-mrmcd-2024.pdf": "/r2wars-mrmcd-2024.pdf",
    "/projects/astrophotography/":                        "/astrophotography",
    "/projects/chaosdorf/":                               "/chaosdorf",
    "/projects/cocktails/#shaking":                       "/cocktails#shaking",
    "/projects/jufo/2019-galaxy-simulation/":             "/jufo-galaxy-simulation",
    "/projects/matrix/matrix-sdk/":                       "/matrix-sdk",
    "/projects/photography/":                             "/photography",
    "/projects/plan9":                                    "/plan9-cluster-init",
    "/projects/vokobe":                                   "/vokobe",
    # full emile.space absolute URLs for old paths
    "https://emile.space/events/2023/03-geekend-berlin/": "/geekend-berlin-2023",
    "https://emile.space/events/2022/03-04_bouldern_superblock/": "/bouldern-superblock",
    "https://emile.space/projects/glitchart/":            "/glitchart",
    "https://emile.space/projects/photography/":          "/photography",
}

# sort longest first so we don't do a partial replacement
SORTED_MAP = sorted(PATH_MAP.items(), key=lambda kv: -len(kv[0]))

def fix_paths(text):
    for old, new in SORTED_MAP:
        text = text.replace(old, new)
    return text

# ── 2. space-in-filename asset renaming ────────────────────────────────────
def slugify_filename(name):
    return name.replace(" ", "_")

def fix_space_files():
    renamed = {}
    for f in list(INPUT.iterdir()):
        if " " in f.name:
            new_name = slugify_filename(f.name)
            new_path = f.parent / new_name
            f.rename(new_path)
            renamed[f.name] = new_name
            print(f"  renamed: '{f.name}' → '{new_name}'")
    return renamed

def fix_space_refs(text, renamed):
    for old, new in renamed.items():
        text = text.replace(old, new)
    return text

# ── 3. static files ────────────────────────────────────────────────────────
OLD_IN = Path("/Users/emile/emile.space/in")
OLD_OUT = Path("/Users/emile/emile.space/out")

STATIC_FILES = [
    (OLD_IN  / "keybase.txt",              INPUT / "keybase.txt"),
    (OLD_IN  / "twtxt.txt",                INPUT / "twtxt.txt"),
    (OLD_OUT / "ssh.keys",                 INPUT / "ssh.keys"),
    (OLD_IN  / ".well-known/webring.txt",  INPUT / ".well-known/webring.txt"),
    (OLD_IN  / "events/2024/10-mrmcd-darmstadt/r2wars-mrmcd-2024.pdf",
                                           INPUT / "r2wars-mrmcd-2024.pdf"),
]

def copy_statics():
    for src, dst in STATIC_FILES:
        if not src.exists():
            print(f"  missing src: {src}")
            continue
        dst.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(src, dst)
        print(f"  copied: {dst.relative_to(ROOT)}")

# ── main ───────────────────────────────────────────────────────────────────
def main():
    print("=== renaming space-in-filename assets ===")
    renamed = fix_space_files()

    print("\n=== copying static files ===")
    copy_statics()

    print("\n=== fixing links in .md files ===")
    for path in sorted(INPUT.glob("*.md")):
        original = path.read_text(encoding="utf-8")
        updated  = fix_paths(original)
        updated  = fix_space_refs(updated, renamed)
        if updated != original:
            path.write_text(updated, encoding="utf-8")
            print(f"  updated: {path.name}")

if __name__ == "__main__":
    main()
