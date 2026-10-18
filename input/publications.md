(meta
  (tag "navbar")
  (published "2026-09-14")
  (modified "2026-09-22")
  (author "Emile"))

# publications

(query
  (where (tag "publication"))
  (sort "date" desc)
  (cols ("Title" "title") ("Date" "date"))
  (format table))
