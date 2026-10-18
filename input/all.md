(meta
  (tag "meta")
  (published "2026-09-14")
  (modified "2026-09-14")
  (author "Emile"))

# all pages

(toc)

(query
  (sort "title" asc)
  (group tag)
  (cols ("Title" "title") ("Tags" "tag"))
  (format table))
