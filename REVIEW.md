# Code Review — emile.space v2 (2026-11-13)

> Status: `[ ]` todo · `[.]` agent working · `[x]` done
> Legend: (A) = OCaml agent · (B) = python agent · (C) = cleanup agent

Findings from a full codebase review (vokobe2 OCaml generator, python
content/map scripts, shell pipeline). Items are grouped and rated.

## 1. Correctness / fragility / performance

* [x] **(HIGH) Backlinks are broken** (A) — `render.ml:~462` searches raw text
  for `name ^ ".md"`; no page ever links that way (they use `[](/name)` /
  `/name`), so the `(backlinks)` box is empty everywhere (e.g.
  `input/gpn21.md`). Match `/` ^ name instead.
* [x] **(HIGH) Unescaped `img`/`link` URLs** (A) — `render.ml:~524-529,636,659`:
  a `"` in a path breaks out of the HTML attribute. Escape with
  `html_escape`.
* [x] **(HIGH) O(pages) linear scans in the render hot path** (A) — `tag_link`,
  `get_page_attr`, query grouping etc. do `List.find_opt` over ~460 pages
  per lookup across ~920 renders (≈O(n²)). Build a `Hashtbl` name→page in
  the render context.
* [x] **(MED) Heading numbering desync** (A) — two counter states
  (`st.heading_counters` + global `current_heading_counters`); dynamic
  `(group tag)` headings only update the global → duplicate section
  numbers/ids for "static h2 → group query → static h2" sequences. Make
  `render_state` the single source of truth.
* [x] **(MED) `parse_multiline_sexp` swallows the page** (A) — `render.ml:~719`:
  on an unbalanced `(`, the rest of the page becomes one giant escaped
  blob. Fall back to rendering the lines as regular text.
* [x] **(MED) TOC vs body heading rules differ** (A) — `Heading.parse_heading`
  requires a space after `#` and level ≤ 5; `render_heading` counts raw
  `#`s. Use `Heading.parse_heading` in the renderer too.
* [x] **(MED) `generate_date_pages` skips name-collision check** (A) —
  `generator.ml:~401`: a real page named `2024.md` would silently
  overwrite the generated date page; other generators do check.
* [x] **(MED) Python meta-block scanners ignore quoted strings** (B) —
  `update-modified.py`, `map-attrs-changed.py`: a paren inside
  `(description "x (see y)")` ends the `(meta …)` block early.
* [x] **(MED) `check-links.py` needs a live server + sequential HTTP** (B) —
  output maps 1:1 onto `output/`; a stat-based check is milliseconds (or
  parallelize with `concurrent.futures`).
* [x] **(MED) Every page renders twice** (A) (`main.ml:~96`) just to collect
  dynamic headings for `(toc)`. Cheaper: placeholder + patch, or a
  scan-only first pass.
* [x] **(LOW) Query filters/sorts compare rendered HTML, not raw values** (A) —
  `(eq "date" "2024-01-01")` can never match; sorting mixes markup into
  keys. Add a raw-value accessor for filters/sorting.
* [x] **(LOW) `enumerate_date_range` truncates silently at 1000 days** (A) —
  raise the cap or warn when fuel runs out.
* [x] **(LOW) Overly broad catches / small robustness issues** (A) —
  `page.ml:~145` catches `exception _`; `Page.parse_attrs`/`render_line`
  worst-case O(n²) on paren-heavy text.
* [x] **(LOW) Wrong quantization in docstrings** (B) — `build-world-rich.py:9`
  and `roughmap.ml:~429` claim 1e-6°, code uses 1e-4 (~10 m).
* [x] **(LOW) `update-map-geodata.py` stamp too coarse** (B) — any input/*.md
  mtime triggers the ~13 s recompute; hash the location-relevant slice
  like `map-attrs-changed.py`. Its `loc_re` also scans code fences.
* [ ] **(LOW) `shell.nix` unpinned** *(deferred — needs network/a pinned channel decision; `all.sh` was deleted so the `fd`/`rg` half is moot)*

## 2. Elegance

* [x] **(MED) Global mutable refs in `Render`/`Roughmap`** (A) —
  `dynamic_headings`, `current_heading_counters`, `current_toc_index`,
  `offline`, `dump_queries`, `fetched` are side-effected from `main.ml`.
  Fold into `render_state` / a config record.
* [x] **(MED) Two slug implementations** (A) — `Util.sanitize` vs
  `Heading.slugify` (different rules!). Unify.
* [x] **(MED) Two heading-counter implementations** (A) —
  `Heading.update_counters` (list) vs array approach in
  `collect_headings`. Keep one.
* [x] **(LOW) Escape/printf duplication** (A) — the split-on-'"' escape idiom
  appears 4× in `generator.ml` (→ a `Sexp` helper); `(map … (marker …))`
  printf blocks repeated 3×.
* [x] **(LOW) Hand-rolled flag parsing** (A) — `bin/main.ml` (use stdlib
  `Arg`); `check-links.py` argv parsing; `import math` inside functions
  in `update-map-geodata.py`; empty placeholder `vokobe2/lib/main.ml`.

## 3. Duplication to combine

* [x] **(HIGH) Four RDP implementations** (B) — `update-map-geodata.py`,
  `build-world-base.py`, `build-world-rich.py`, `roughmap.ml`. Extract a
  shared python `maptools.py`.
* [x] **(HIGH) Two byte-identical binary `Writer` classes** (B) —
  `build-world-base.py` vs `build-world-rich.py` (varint/zigzag/feature;
  the way/road classifiers are near-duplicates too).
* [x] **(HIGH) Geofabrik extract catalog in three places** (B) —
  `fetch-osm-dataset.sh`, `extract-map-cache.py` (`EXTRACTS` +
  `COUNTRY_TO_EXTRACT`). Single manifest.
* [x] **(MED) Meta-block scanning duplicated in Python** (B) —
  `update-modified.py`, `map-attrs-changed.py`, `add-dates.py`,
  `add-empty-dates.py` → shared `meta.py` (string-aware; also fixes the
  quoted-string bug).
* [x] **(MED) Geodata paths/regexes re-declared everywhere** (B) —
  `update-map-geodata.py`, `map-attrs-changed.py`,
  `extract-map-cache.py`, `build-world-rich.py` (`REGION_RE` twice) +
  `roughmap.ml`. Shared constants module.
* [x] **(LOW) `rebuild-publish.sh` ≈ `publish.sh` minus data prep** (C) —
  make it `publish.sh --no-prep` or delete.

## 4. Reducible / dead

* [x] **(HIGH) Delete finished migration toolchain** (C) — `migrate.py`,
  `MIGRATION.md`, `clean-html.py`, `clean-titles.py`, `find-html.py`,
  `fix-links.py` (hardcodes a path outside the repo),
  `fix-relative-links.py`, `migrate-images.py`, `add-locations.py`,
  `add-dates.py` + `missing.txt`, `add-empty-dates.py` (git history
  keeps them).
* [x] **(HIGH) Delete `input_backup/` and `main_backup/`** (C) — local
  snapshots superseded by git (already gitignored).
* [x] **(MED) Dead OCaml code** (A) — `generate_value_pages` (never called),
  `find_sexps_in_line`, `heading_to_html` (dead *and* buggy: wrong
  slugify + `"}n"` typo).
* [x] **(LOW) `all.sh` misleadingly named** (C) (a vocab dumper, not "build
  everything") — rename or delete.
* [x] **(LOW) Placeholder package metadata** (C) — `vokobe2/opam`,
  `dune-project` (fake synopsis/maintainer/docs/license); fill in or
  drop.
* [x] **(LOW) Verbose-flag plumbing in shell scripts** (C) —
  `publish.sh`/`sync.sh`/`build.sh` each re-loop `$@`; one `VERBOSE` env
  var instead.

## 5. Testing

* [x] **(MED) Add golden-render tests** (A) — the suite is a single ~40-line
  regression test; add tests for backlinks, TOC/heading numbering
  (static+dynamic), date-page collisions, RSS excerpt extraction.

## 6. Broken date links (found during review follow-up, fixed 2026-11-13)

`check-links.py` flagged 6 broken date-URL links: two content typos
(reversed date ranges in `input/chaos-jetzt-geekend-bochum.md` and
`input/hackimpott.md`) and two generator/renderer mismatches
(`published`/`modified` values were link-rendered even when no date page
exists for them).

* [x] content typos corrected in input/
* [x] `format_date_links` now only links date parts that have a real page
* [x] `enumerate_date_range` warns on reversed ranges (build-time typo detection)
* [x] verified: `python3 check-links.py` → 1126 ok, 0 broken
