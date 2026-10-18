(meta
  (tag "project" "vokobe")
  (published "2026-09-16")
  (modified "2026-09-16")
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



