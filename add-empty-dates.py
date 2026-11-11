#!/usr/bin/env python3
"""One-time: add (date "") to all pages the build reports as dateless.

Captures the "[!] pages without a date" list from a build, then inserts
(date "") right after the opening (meta line of each listed input file
(indentation follows the existing first entry).

usage: ./add-empty-dates.py [--check]
"""
import os, re, subprocess, sys

ROOT = os.path.dirname(os.path.abspath(__file__))
INPUT = os.path.join(ROOT, "input")

def undated_pages():
    out = subprocess.run(
        ["nix-shell", os.path.join(ROOT, "shell.nix"), "--run",
         "dune exec bin/main.exe -- ../input/ /tmp/vokobe-out emile.space --offline"],
        cwd=os.path.join(ROOT, "vokobe2"),
        capture_output=True, text=True).stdout
    marked, pages = False, []
    for line in out.splitlines():
        if line.startswith("[!]"):
            marked = True
        elif marked and line.startswith("pages:"):
            break
        elif marked and line.strip():
            pages.append(line.strip())
    try:
        import shutil
        shutil.rmtree("/tmp/vokobe-out")
    except OSError:
        pass
    return pages

def add_date_tag(path):
    with open(path) as f:
        s = f.read()
    # only the real metadata (before any fenced doc example) counts
    head = s.split("```", 1)[0]
    if re.search(r"^[ \t]*\(date", head, re.M):
        return "already has a date"
    m = re.search(r"^\(meta\s*$", s, re.M)
    if not m:
        return "NO (meta block) - skipped"
    rest = s[m.end():]
    # indentation of the first existing entry; default two spaces
    mi = re.search(r"^\n([ \t]+)\(", rest)
    indent = mi.group(1) if mi else "  "
    s = s[:m.end()] + "\n" + indent + '(date "")' + s[m.end():]
    with open(path, "w") as f:
        f.write(s)
    return "ok"

def main():
    check = "--check" in sys.argv
    pages = undated_pages()
    print(f"{len(pages)} undated pages")
    if check:
        print("\n".join(pages))
        return
    n_ok = 0
    for name in pages:
        path = os.path.join(INPUT, name + ".md")
        if not os.path.exists(path):
            print(f"  {name}: FILE NOT FOUND - skipped")
            continue
        r = add_date_tag(path)
        n_ok += r == "ok"
        if r != "ok":
            print(f"  {name}: {r}")
    print(f"(date \"\") added to {n_ok} pages")

if __name__ == "__main__":
    main()
