(meta
  (date "")
  (tag "docs" "navbar")
  (published "2026-09-14")
  (modified "2026-11-13")
  (author "Emile"))

# events

(query
  (where (tag "event"))
  (sort "date" desc)
  (group year "date" desc)
  (cols ("Title" "title")
        ("Date" "date"))
  (format table))
