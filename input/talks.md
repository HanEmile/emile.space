(meta
  (tag "navbar")
  (published "2026-09-14")
  (modified "2026-09-22")
  (author "Emile"))

# talks

(query
  (where (tag "talk"))
  (sort "date" desc)
  (cols ("Title" "title") ("Date" "date"))
  (format table))
