(meta
  (tag "project" "vokobe")
  (published "2026-09-16")
  (modified "2026-11-08")
  (author "Emile")
  (info "published" "tag"))

# vokobe2

[vokobe](/vokobe), rewritten in [OCaml](https://ocaml.org).

## s-expressions

### metadata

```lisp
(meta
  (tag "project" "vokobe")
  (published "2026-09-16")
  (modified "2026-09-16")
  (author "Emile")
  (info "published" "tag"))
```

### queries

For example this is what creates the list on the [blog](/blog) page:

```lisp
(query
  (where (tag "blog"))
  (sort "date" desc)
  (cols ("Title" "title")
        ("Published" "published")
        ("Modified" "modified"))
  (format table))
```

### maps

Renders a rough outline map (borders, major roads, rivers, lakes,
coastlines, mountain peaks) as inline SVG. `(region S W N E)` takes the
bounding box as south/west/north/east lat/lon; any number of
`(marker LAT LON "optional label")` adds markers:

```lisp
(map (region 51.22 6.77 51.25 6.80)
     (marker 51.235 6.785 "my favourite spot"))
```

The geometry is fetched from the Overpass API (OpenStreetMap data) the
first time a region is built and cached in `map-cache/` (committed to
the repo), so later builds are offline. Streams are only included for
small regions, and only the 12 highest peaks are labelled to keep the
map readable.



