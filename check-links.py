#!/usr/bin/env python3
"""
check-links.py

Scans all HTML files in the output/ directory, extracts every local link
(href and src attributes), and reports any that don't return HTTP 200.

Usage: python3 check-links.py [--verbose] [base_url]
Default base_url: http://localhost:8081
"""

import sys
import re
import urllib.request
import urllib.error
from pathlib import Path
from collections import defaultdict

args = sys.argv[1:]
VERBOSE = "--verbose" in args
args = [a for a in args if not a.startswith("--")]
BASE_URL = args[0] if args else "http://localhost:8081"
OUTPUT = Path(__file__).parent / "output"

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

def check(path: str) -> int:
    try:
        with urllib.request.urlopen(BASE_URL + path, timeout=5) as r:
            return r.status
    except urllib.error.HTTPError as e:
        return e.code
    except Exception:
        return -1

def main() -> int:
    all_links: set[str] = set()
    for html_file in OUTPUT.glob("*.html"):
        if html_file.name.startswith("."):
            continue
        text = html_file.read_text(encoding="utf-8", errors="ignore")
        all_links |= extract_links(text)

    print(f"Found {len(all_links)} unique local links across all pages")
    print(f"Checking against {BASE_URL} ...\n")

    failures: dict[int, list[str]] = defaultdict(list)
    ok = 0
    for i, link in enumerate(sorted(all_links), 1):
        status = check(link)
        if status == 200:
            ok += 1
        else:
            failures[status].append(link)

    n_failed = sum(len(v) for v in failures.values())
    print(f"links: {ok} ok, {n_failed} broken")

    if n_failed and VERBOSE:
        for code in sorted(failures):
            label = "connection error" if code == -1 else f"HTTP {code}"
            print(f"\n--- {label} ({len(failures[code])}) ---")
            for link in sorted(failures[code]):
                print(f"  {link}")

    return n_failed

if __name__ == "__main__":
    sys.exit(0 if main() == 0 else 1)
