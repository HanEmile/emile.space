(meta
  (tag "projects" "docs" "navbar")
  (published "2026-09-14")
  (modified "2026-09-14")
  (author "Emile"))

# projects

(query
  (where (tag "project"))
  (sort "date" desc)
  (cols ("Title" "title")
        ("Published" "published")
        ("Modified" "modified"))
  (format "list"))


