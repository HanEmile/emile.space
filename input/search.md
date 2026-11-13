(meta
  (date "")
  (published "2026-09-14")
  (modified "2026-11-13")
  (author "Emile"))

# search

No javascript, no server round-trips: every frequently used word on
this site has a **precomputed result page**, generated at build time:

/search-<word>

for example [search-nixos](/search-nixos) or [search-map](/search-map).
Words are lowercased, 3–8 chars long and appear at least three times
across the site (~2000 index pages with ranked results and context
snippets).

Works just as well on site mirrors and downloaded copies (`file://`),
which is the whole point.

(A previous incarnation of this page documented a bash one-liner that
precomputed one HTML file per token for v1 of this site. Same idea —
now native to the generator, with ranking and snippets.)
