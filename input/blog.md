(meta
  (tag "navbar")
  (published "2026-09-14")
  (modified "2026-09-14")
  (author "Emile"))

# blog

(query
  (where (tag "blog"))
  (sort "published" desc)
  (group year "published" desc)
  (cols ("Title" "title")
        ("Published" "published")
        ("Modified" "modified"))
  (format table))
