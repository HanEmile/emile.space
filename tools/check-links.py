#!/usr/bin/env python3
"""
check-links.py

Scans all HTML files in the output/ directory, extracts every local link
(href and src attributes), and reports any with no file in output/.
The URL space is flat: "/x" is output/x.html when it exists, else the
literal file output/x (e.g. "/style.css" -> output/style.css).

External links (http(s)://...) are not checked -- they never were; the
old server-based version of this script skipped them as well.

Usage: python3 tools/check-links.py [--verbose] [base_url]
The base_url argument is deprecated and ignored (no server needed).
"""

import sys
import re
import urllib.parse
from pathlib import Path

args = sys.argv[1:]
VERBOSE = "--verbose" in args
args = [a for a in args if not a.startswith("--")]
BASE_URL = args[0] if args else None
OUTPUT = Path(__file__).parent.parent / "output"

def extract_links(html: str) -> set[str]:
    links = set()
    for m in re.finditer(r'(?:href|src)="([^"]+)"', html):
        url = m.group(1)
        if url.startswith("//") or url.startswith("http") or url.startswith("#"):
            continue
        if url.startswith("/"):
            links.add(url)
        elif url.startswith("./"):
            links.add("/" + url[2:])  # treat ./file as /file in flat structure
        elif url.startswith("../"):
            links.add("/" + url[3:])  # treat ../file as /file in flat structure
    return links

def exists(path: str) -> bool:
    """does the URL path resolve inside the flat output/ dir?"""
    path = path.split("#", 1)[0].split("?", 1)[0]
    if not path or not path.startswith("/"):
        return False
    # "/x" -> "x.html" (page routes) or the literal file "x" (assets);
    # percent-decoding mirrors what the serving stack resolves
    rel = urllib.parse.unquote(path.lstrip("/"))
    if rel == "":
        rel = "index.html"
    if not (OUTPUT / rel).resolve().is_relative_to(OUTPUT.resolve()):
        return False  # never escape output/
    if (OUTPUT / (rel + ".html")).is_file():
        return True
    return (OUTPUT / rel).is_file()

def main() -> int:
    _ = BASE_URL  # deprecated argument, accepted for compatibility
    all_links: set[str] = set()
    for html_file in OUTPUT.glob("*.html"):
        if html_file.name.startswith("."):
            continue
        text = html_file.read_text(encoding="utf-8", errors="ignore")
        all_links |= extract_links(text)

    if VERBOSE:
        print(f"Found {len(all_links)} unique local links across all pages")
        print(f"Checking against {OUTPUT}/ ...\n")

    broken = sorted(link for link in all_links if not exists(link))
    ok = len(all_links) - len(broken)
    if broken:
        print(f"links: {ok} ok, {len(broken)} broken")
    else:
        print(f"[+] links: {ok} ok")

    if broken and VERBOSE:
        print(f"\n--- broken ({len(broken)}) ---")
        for link in broken:
            print(f"  {link}")

    return len(broken)

if __name__ == "__main__":
    sys.exit(0 if main() == 0 else 1)
