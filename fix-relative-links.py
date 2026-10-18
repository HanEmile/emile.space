#!/usr/bin/env python3
"""
fix-relative-links.py

Copies missing assets from the old site to input/ with page-prefixed names,
and updates ./relative references in .md files to /absolute paths.
"""

import re, shutil
from pathlib import Path

ROOT  = Path(__file__).parent
INPUT = ROOT / "input"
OLD   = Path("/Users/emile/emile.space/in")

# (source_in_old_site, dest_in_input, page_file, old_ref, new_ref)
# old_ref: the ./xxx string used in the page
# new_ref: what it should become (absolute /xxx)
FIXES = [
    # windsurf
    (OLD/"sport/windsurf/angermund.png",       INPUT/"windsurf-angermund.png",
     "windsurf.md",  "./angermund.png",   "/windsurf-angermund.png"),
    (OLD/"sport/windsurf/angermund2.png",      INPUT/"windsurf-angermund2.png",
     "windsurf.md",  "./angermund2.png",  "/windsurf-angermund2.png"),

    # astrophotography full-res
    (OLD/"projects/astrophotography/IMG_20220101_223758.jpg",
     INPUT/"astrophotography-IMG_20220101_223758.jpg",
     "astrophotography.md", "./IMG_20220101_223758.jpg", "/astrophotography-IMG_20220101_223758.jpg"),
    (OLD/"projects/astrophotography/IMG_20201020_012707.jpg",
     INPUT/"astrophotography-IMG_20201020_012707.jpg",
     "astrophotography.md", "./IMG_20201020_012707.jpg", "/astrophotography-IMG_20201020_012707.jpg"),
    (OLD/"projects/astrophotography/IMG_20200723_123728_edited.jpg",
     INPUT/"astrophotography-IMG_20200723_123728_edited.jpg",
     "astrophotography.md", "./IMG_20200723_123728_edited.jpg", "/astrophotography-IMG_20200723_123728_edited.jpg"),
    (OLD/"projects/astrophotography/cccamp.jpeg",
     INPUT/"astrophotography-cccamp.jpeg",  # already exists but ref needs fixing
     "astrophotography.md", "./cccamp.jpeg", "/astrophotography-cccamp.jpeg"),

    # ski-fiss-ladis full-res images
    (OLD/"events/2022/01-ski-fiss-ladis/IMG_20220102_084023.jpg",
     INPUT/"ski-fiss-ladis-IMG_20220102_084023.jpg",
     "ski-fiss-ladis.md", "./IMG_20220102_084023.jpg", "/ski-fiss-ladis-IMG_20220102_084023.jpg"),
    (OLD/"events/2022/01-ski-fiss-ladis/IMG_20220103_120424.jpg",
     INPUT/"ski-fiss-ladis-IMG_20220103_120424.jpg",
     "ski-fiss-ladis.md", "./IMG_20220103_120424.jpg", "/ski-fiss-ladis-IMG_20220103_120424.jpg"),
    (OLD/"events/2022/01-ski-fiss-ladis/IMG_20220104_123448.jpg",
     INPUT/"ski-fiss-ladis-IMG_20220104_123448.jpg",
     "ski-fiss-ladis.md", "./IMG_20220104_123448.jpg", "/ski-fiss-ladis-IMG_20220104_123448.jpg"),
    (OLD/"events/2022/01-ski-fiss-ladis/IMG_20220105_080027.jpg",
     INPUT/"ski-fiss-ladis-IMG_20220105_080027.jpg",
     "ski-fiss-ladis.md", "./IMG_20220105_080027.jpg", "/ski-fiss-ladis-IMG_20220105_080027.jpg"),
    (OLD/"events/2022/01-ski-fiss-ladis/IMG_20220106_124442.jpg",
     INPUT/"ski-fiss-ladis-IMG_20220106_124442.jpg",
     "ski-fiss-ladis.md", "./IMG_20220106_124442.jpg", "/ski-fiss-ladis-IMG_20220106_124442.jpg"),
    (OLD/"events/2022/01-ski-fiss-ladis/IMG_20220106_135737.jpg",
     INPUT/"ski-fiss-ladis-IMG_20220106_135737.jpg",
     "ski-fiss-ladis.md", "./IMG_20220106_135737.jpg", "/ski-fiss-ladis-IMG_20220106_135737.jpg"),
    (OLD/"events/2022/01-ski-fiss-ladis/IMG_20220107_125406.jpg",
     INPUT/"ski-fiss-ladis-IMG_20220107_125406.jpg",
     "ski-fiss-ladis.md", "./IMG_20220107_125406.jpg", "/ski-fiss-ladis-IMG_20220107_125406.jpg"),

    # ski-fiss-ladis GPX tracks
    (OLD/"events/2022/01-ski-fiss-ladis/sportler_track_1-2-22_09-588262521426935870635.gpx",
     INPUT/"ski-fiss-ladis-sportler_track_1-2-22.gpx",
     "ski-fiss-ladis.md",
     "./sportler_track_1-2-22_09-588262521426935870635.gpx",
     "/ski-fiss-ladis-sportler_track_1-2-22.gpx"),
    (OLD/"events/2022/01-ski-fiss-ladis/sportler_track_1-3-22_09-202728502098809034503.gpx",
     INPUT/"ski-fiss-ladis-sportler_track_1-3-22.gpx",
     "ski-fiss-ladis.md",
     "./sportler_track_1-3-22_09-202728502098809034503.gpx",
     "/ski-fiss-ladis-sportler_track_1-3-22.gpx"),
    (OLD/"events/2022/01-ski-fiss-ladis/sportler_track_1-4-22_09-217234164266262352192.gpx",
     INPUT/"ski-fiss-ladis-sportler_track_1-4-22.gpx",
     "ski-fiss-ladis.md",
     "./sportler_track_1-4-22_09-217234164266262352192.gpx",
     "/ski-fiss-ladis-sportler_track_1-4-22.gpx"),
    (OLD/"events/2022/01-ski-fiss-ladis/sportler_track_1-5-22_09-279105235435107604284.gpx",
     INPUT/"ski-fiss-ladis-sportler_track_1-5-22.gpx",
     "ski-fiss-ladis.md",
     "./sportler_track_1-5-22_09-279105235435107604284.gpx",
     "/ski-fiss-ladis-sportler_track_1-5-22.gpx"),
    (OLD/"events/2022/01-ski-fiss-ladis/sportler_track_1-6-22_09-066127438439762856324.gpx",
     INPUT/"ski-fiss-ladis-sportler_track_1-6-22.gpx",
     "ski-fiss-ladis.md",
     "./sportler_track_1-6-22_09-066127438439762856324.gpx",
     "/ski-fiss-ladis-sportler_track_1-6-22.gpx"),
    (OLD/"events/2022/01-ski-fiss-ladis/sportler_track_1-7-22_09-142230253560393793682.gpx",
     INPUT/"ski-fiss-ladis-sportler_track_1-7-22.gpx",
     "ski-fiss-ladis.md",
     "./sportler_track_1-7-22_09-142230253560393793682.gpx",
     "/ski-fiss-ladis-sportler_track_1-7-22.gpx"),

    # PDFs and text files
    (OLD/"publications/2019/Galaxy-Simluation/JUFO19.pdf",
     INPUT/"galaxy-simulation-JUFO19.pdf",
     "galaxy-simulation.md", "./JUFO19.pdf", "/galaxy-simulation-JUFO19.pdf"),
    (OLD/"publications/2020/Accelerating-simulations-by-clustering-bodies-using-the-Barnes-Hut-algorithm/barnes_hut.pdf",
     INPUT/"accelerating-simulations-barnes_hut.pdf",
     "accelerating-simulations.md", "./barnes_hut.pdf", "/accelerating-simulations-barnes_hut.pdf"),
    (OLD/"events/2023/09-balccon-novi-sad/r2wars.pdf",
     INPUT/"balccon-r2wars.pdf",
     "balccon.md", "./r2wars.pdf", "/balccon-r2wars.pdf"),
    (OLD/"events/2023/06-GPN/vom_bufferoverflow_zur_shell.pdf",
     INPUT/"gpn23-vom_bufferoverflow_zur_shell.pdf",
     "gpn23.md", "./vom_bufferoverflow_zur_shell.pdf", "/gpn23-vom_bufferoverflow_zur_shell.pdf"),
    (OLD/"projects/jufo/2019-galaxy-simulation/tree.pdf",
     INPUT/"jufo-galaxy-simulation-tree.pdf",
     "jufo-galaxy-simulation.md", "./tree.pdf", "/jufo-galaxy-simulation-tree.pdf"),
    (OLD/"projects/jufo/2019-galaxy-simulation/langfassung.pdf",
     INPUT/"jufo-galaxy-simulation-langfassung.pdf",
     "jufo-galaxy-simulation.md", "./langfassung.pdf", "/jufo-galaxy-simulation-langfassung.pdf"),
    (OLD/"projects/jufo/2019-galaxy-simulation/posters.pdf",
     INPUT/"jufo-galaxy-simulation-posters.pdf",
     "jufo-galaxy-simulation.md", "./posters.pdf", "/jufo-galaxy-simulation-posters.pdf"),
    (OLD/"projects/jufo/2019-galaxy-simulation/series.pdf",
     INPUT/"jufo-galaxy-simulation-series.pdf",
     "jufo-galaxy-simulation.md", "./series.pdf", "/jufo-galaxy-simulation-series.pdf"),
    (OLD/"projects/toki-pona/tp_words_ranked.txt",
     INPUT/"toki-pona-tp_words_ranked.txt",
     "toki-pona.md", "./tp_words_ranked.txt", "/toki-pona-tp_words_ranked.txt"),
    (OLD/"files/postgres-docker/docker-compose.yml",
     INPUT/"postgres-docker-docker-compose.yml",
     "postgres-docker.md", "./docker-compose.yml", "/postgres-docker-docker-compose.yml"),

    # jufo galaxy simulation images (already in input with prefix, just need ref fix)
    (OLD/"projects/jufo/2019-galaxy-simulation/barnes-hut-tree-50.png",
     INPUT/"jufo-galaxy-simulation-barnes-hut-tree-50.png",
     "jufo-galaxy-simulation.md", "./barnes-hut-tree-50.png", "/jufo-galaxy-simulation-barnes-hut-tree-50.png"),
    (OLD/"projects/jufo/2019-galaxy-simulation/barnes-hut-tree-1000.png",
     INPUT/"jufo-galaxy-simulation-barnes-hut-tree-1000.png",
     "jufo-galaxy-simulation.md", "./barnes-hut-tree-1000.png", "/jufo-galaxy-simulation-barnes-hut-tree-1000.png"),
]

# ./images directory link → just remove it (no flat equivalent)
REMOVE_LINES = {
    "new-york-2023.md": ["[Image gallery](./images)\n", "[Image gallery](./images)"],
}

# glitchart: ./dither_it_Screenshot ... → already renamed to glitchart-dither_it_Screenshot_...
# ./Screenshot ... files - check if they exist in old site
GLITCHART_OLD = Path("/Users/emile/emile.space/in/events/2023/03-geekend-berlin")

def main():
    # collect all md updates
    updates: dict[str, list[tuple[str, str]]] = {}

    for src, dst, page, old_ref, new_ref in FIXES:
        # copy file
        if not dst.exists():
            if src.exists():
                shutil.copy2(src, dst)
                print(f"  copied  {dst.name}")
            else:
                print(f"  MISSING {src}")
        # queue ref update
        updates.setdefault(page, []).append((old_ref, new_ref))

    # handle glitchart ./dither_it_... and ./Screenshot ... refs
    for f in sorted(INPUT.glob("glitchart-dither_it_Screenshot_*.png")):
        orig_name = f.name.replace("glitchart-", "./").replace("_", " ").replace(". ", "_at_") \
                         .replace("Screenshot ", "Screenshot ")
        # the old ref was like ./dither_it_Screenshot 2023-03-19 at 18.59.39.png
        old = "./" + f.name.replace("glitchart-", "").replace("_", " ")
        # spaces were replaced by underscores when we renamed; old had spaces
        new = "/" + f.name
        updates.setdefault("glitchart.md", []).append((old, new))

    # apply all md updates
    changed = set()
    for page, replacements in updates.items():
        path = INPUT / page
        if not path.exists():
            print(f"  page not found: {page}")
            continue
        text = path.read_text()
        for old, new in replacements:
            text = text.replace(old, new)
        (INPUT / page).write_text(text)
        changed.add(page)

    # remove ./images lines
    for page, lines_to_remove in REMOVE_LINES.items():
        path = INPUT / page
        text = path.read_text()
        for line in lines_to_remove:
            text = text.replace(line, "")
        (INPUT / page).write_text(text)
        changed.add(page)

    print(f"\nupdated {len(changed)} pages: {', '.join(sorted(changed))}")


if __name__ == "__main__":
    main()
