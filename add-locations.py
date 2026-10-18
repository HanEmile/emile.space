#!/usr/bin/env python3
"""
add-locations.py

Adds (location "...") to the meta block of event pages and appends
"location" to their (info ...) lists.
"""

import re
from pathlib import Path

INPUT = Path(__file__).parent / "input"

LOCATIONS = {
    # CCC congresses
    "34c3": "Leipzig",
    "35c3": "Leipzig",
    "36c3": "Leipzig",
    "37c3": "Hamburg",
    "38c3": "Hamburg",
    "39c3": "Hamburg",
    # CCCamp
    "cccamp19": "Mildenberg",
    "cccamp23": "Mildenberg",
    # GPN (all at ZKM Karlsruhe)
    "gpn17": "Karlsruhe",
    "gpn18": "Karlsruhe",
    "gpn19": "Karlsruhe",
    "gpn20": "Karlsruhe",
    "gpn23": "Karlsruhe",
    "gpn25": "Karlsruhe",
    "gpn26": "Karlsruhe",
    # Ski
    "ski-fiss-ladis": "Fiss-Ladis",
    "ski-obertauern": "Obertauern",
    "ski-ishgl": "Ischgl",
    "ski-st-anton": "St. Anton",
    "arlberg": "Arlberg",
    "lausanne_ski_2017": "Lausanne",
    # Countries / regions
    "egypt": "Egypt",
    "rhodos": "Rhodes",
    "korsika": "Corsica",
    "dolomiten": "Dolomites",
    "lanzarote-fuerteventura": "Lanzarote / Fuerteventura",
    "tenerife-2024": "El Médano, Tenerife",
    "tenerife-2025-05": "El Médano, Tenerife",
    "tenerife-2025-09": "Tenerife",
    "asia-2024": "Asia",
    "asia-2025": "Asia",
    # Windsurf
    "windsurf-portugal": "Viana do Castelo",
    "defi-wind": "Gruissan",
    # International
    "bountyconedu-madrid": "Madrid",
    "emf-camp-eastnor": "Eastnor",
    "emfcamp-2024": "Eastnor",
    "mch-zeewolde": "Zeewolde",
    "balccon": "Novi Sad",
    "blackhat-2022": "Las Vegas",
    "defcon30": "Las Vegas",
    "defcon-2022": "Las Vegas",
    "defcon-2023": "Las Vegas",
    "new-york-2023": "New York",
    "newline-gent": "Gent",
    "p4ctf-finals": "Katowice",
    "r2con-barcelona": "Barcelona",
    "fosdem-2023": "Brussels",
    "toorcamp": "Oregon",
    "veluvemeer": "Veluwe",
    # German cities
    "troopers-heidelberg": "Heidelberg",
    "heidelberg-2022": "Heidelberg",
    "koblenz-freiburg-by-bike": "Koblenz → Freiburg",
    "wakeboarding-wedau": "Wedau",
    "chaos-jetzt-geekend-bochum": "Bochum",
    "chaos-jetzt-geekend-leipzig": "Leipzig",
    "chaos-jetzt-geekend-wien": "Vienna",
    "chaotikum-lubeck": "Lübeck",
    "bsides-indor-ctf": "Aachen",
    "ccc-regiowochenende-muhldorf": "Mühldorf",
    "cccactfebuar-aachen": "Aachen",
    "ctf-weekend-aachen": "Aachen",
    "docklands-munster": "Münster",
    "halloween-ctf-bonn": "Bonn",
    "hip-berlin": "Berlin",
    "jufo-bundeswettbewerb-chemnitz": "Chemnitz",
    "jufo-bundeswettbewerb-lubeck": "Lübeck",
    "labortage-2019": "Bochum",
    "labortage-2020": "Bochum",
    "labortage-2021": "Bochum",
    "labortage-2022": "Bochum",
    "labortage-2023": "Bochum",
    "labortagectf-2020": "Bochum",
    "labortagectf-2021": "Bochum",
    "munich-2023": "Munich",
    "mrmcd-2023": "Darmstadt",
    "mrmcd-2024": "Darmstadt",
    "sushi-maki-maki-cologne": "Cologne",
    "warpzone-munster": "Münster",
    "geekend-berlin-2023": "Berlin",
    "berlin-tour-2023": "Berlin",
    "easterhegg-2023": "Hamburg",
    "why25": "Hamburg",
    "sailing-flensburg-2026": "Flensburg",
    "boulder-superblock-2023": "Düsseldorf",
    "bouldern-superblock": "Düsseldorf",
    "dorfctf": "Düsseldorf",
    "eatin-snacks-duisburg": "Duisburg",
    "tag-des-offenen-hackspaces": "Düsseldorf",
    "milliways-storage-day": "Düsseldorf",
    # Online
    "rc3-2020": "Online",
    "rc3-2021": "Online",
    "hidden-services-talk": "Online",
    "push-to-talk": "Online",
    "reboot-to-respawn": "Online",
    "google-ctf-2023": "Online",
    "plaidctf-2023": "Online",
}


def add_location(text: str, location: str) -> str:
    # 1. Add (location "...") before the closing ) of the meta block.
    #    Find the first (meta ...) block end.
    meta_match = re.search(r'\(meta\b', text)
    if not meta_match:
        return text

    # Skip if location already present
    if '(location ' in text:
        return text

    # Find the balanced closing ) of the meta block
    start = meta_match.start()
    depth = 0
    meta_end = start
    for i in range(start, len(text)):
        if text[i] == '(':
            depth += 1
        elif text[i] == ')':
            depth -= 1
            if depth == 0:
                meta_end = i
                break

    # Insert (location "...") on its own line before meta_end
    # Find the last newline before meta_end to align indentation
    insert_pos = text.rfind('\n', start, meta_end)
    if insert_pos == -1:
        insert_pos = meta_end

    # Detect indentation from an existing inner line (e.g. (tag ...))
    indent_match = re.search(r'\n([ \t]+)\(', text[start:meta_end])
    indent = indent_match.group(1) if indent_match else "  "

    loc_line = f'\n{indent}(location "{location}")'
    text = text[:insert_pos] + loc_line + text[insert_pos:]

    # 2. Add "location" to the (info ...) list if present.
    def add_to_info(m):
        # m.group(0) is the full (info ...) sexp
        s = m.group(0).rstrip(')')
        if '"location"' in s:
            return m.group(0)
        return s + ' "location")'

    text = re.sub(r'\(info\s+"[^"]*"(?:\s+"[^"]*")*\)', add_to_info, text)

    return text


def main():
    for name, location in sorted(LOCATIONS.items()):
        path = INPUT / f"{name}.md"
        if not path.exists():
            print(f"  missing  {name}.md")
            continue
        original = path.read_text(encoding="utf-8")
        updated = add_location(original, location)
        if updated != original:
            path.write_text(updated, encoding="utf-8")
            print(f"  updated  {name}.md  ({location})")
        else:
            print(f"  no-op    {name}.md")


if __name__ == "__main__":
    main()
