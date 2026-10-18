#!/usr/bin/env python3
"""
clean-titles.py

Cleans location text and legacy prefixes from page titles (# heading).
- Strips leading NN- numbered prefixes
- Strips leading YYYY-MM-DD / YYYY-MM / YYYY- date prefixes
- Removes location text from title (case-insensitive)
- Replaces dashes with spaces if the title looks slug-like
- Falls back to a manual override if the result would be empty
"""

import re
from pathlib import Path

INPUT = Path(__file__).parent / "input"

# manual overrides: filename → desired new title (when auto-clean would leave empty/bad result)
OVERRIDES = {
    "01-munich":                        "Munich",
    "02-fosdem-brussels":               "FOSDEM",
    "02-cccactfebuar-aachen":           "cccactfebuar",
    "03-eatin-snacks-and-getting-flags-duisburg": "eatin snacks and getting flags",
    "03-geekend-berlin":                "geekend",
    "03-tag-des-offenen-hackspaces-düsseldorf": "tag des offenen hackspaces",
    "04-newline-gent":                  "newline",
    "04-plaidctf":                      "plaidctf",
    "2026-07 Flensburg":               "Flensburg sailing",
    "2022-01 Ski Fiss Ladis":          "Ski Fiss Ladis",
    "2019-dorfctf":                     "dorfCTF",
    "2020-labortageCTF":                "labortageCTF",
    "2021-labortageCTF":                "labortageCTF",
    "Obertauern":                       "Ski Obertauern",
    "skiing":                           "Ski Arlberg",
    "Ski ischgl":                       "Ski Ischgl",
    "ski st anton":                     "Ski St. Anton",
    "lausanne":                         "Ski Lausanne",
    "heidelberg":                       "Heidelberg",
    "HIP Berlin 2022":                  "HIP 2022",
    "asia":                             "Asia",
    "balcon novi sad":                  "BAlCCon",
    "windsurfing Viana do Castelo Portugal": "Windsurfing Portugal",
    "jetzt6 chaos.jetzt geekend Wien":  "chaos.jetzt geekend",
    "Wakeboarding Duisburg Wedau":      "Wakeboarding",
}

def location_words(loc: str) -> list[str]:
    """Split location into individual words for matching."""
    words = re.split(r'[\s/,→\.]+', loc)
    return [w.lower() for w in words if w]

def strip_prefixes(title: str) -> str:
    # NN- prefix (01-, 02-, etc.)
    title = re.sub(r'^\d{2}-', '', title)
    # YYYY-MM-DD / YYYY-MM / YYYY- prefix
    title = re.sub(r'^\d{4}-\d{2}-\d{2}\s*', '', title)
    title = re.sub(r'^\d{4}-\d{2}\s*', '', title)
    title = re.sub(r'^\d{4}-', '', title)
    return title

def remove_location(title: str, location: str) -> str:
    """Remove location words from title (case-insensitive)."""
    words = location_words(location)
    result = title
    for word in words:
        if len(word) < 3:
            continue  # skip short words like "do", "el"
        result = re.sub(r'(?i)\b' + re.escape(word) + r'\b[-\s]*', '', result)
    return result.strip(' -')

def slugify_if_needed(title: str) -> str:
    """If title looks like a slug (lowercase+dashes, no spaces), convert dashes to spaces."""
    if ' ' not in title and '-' in title and title == title.lower():
        return title.replace('-', ' ')
    return title

def clean_title(raw_title, location):
    """Return new title or None if no change needed."""
    # Check manual override by raw_title first
    if raw_title in OVERRIDES:
        new = OVERRIDES[raw_title]
        return new if new != raw_title else None

    t = raw_title
    t = strip_prefixes(t)
    if location:
        t = remove_location(t, location)
    t = slugify_if_needed(t)
    t = t.strip()

    # Check override on the cleaned result (for residual slugs)
    if t in OVERRIDES and OVERRIDES[t] != raw_title:
        t = OVERRIDES[t]

    if not t or t == raw_title:
        return None
    return t


def process_file(path: Path) -> None:
    text = path.read_text(encoding="utf-8")

    location_m = re.search(r'\(location\s+"([^"]+)"\)', text)
    location = location_m.group(1) if location_m else ""

    # Find the # Title line
    title_m = re.search(r'^(# )(.+)$', text, re.MULTILINE)
    if not title_m:
        return

    raw_title = title_m.group(2)
    new_title = clean_title(raw_title, location)
    if new_title is None:
        return

    updated = text[:title_m.start(2)] + new_title + text[title_m.end(2):]
    path.write_text(updated, encoding="utf-8")
    print(f"  {path.name}: '{raw_title}' → '{new_title}'")


def main():
    for path in sorted(INPUT.glob("*.md")):
        process_file(path)


if __name__ == "__main__":
    main()
