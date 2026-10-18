(meta
  (tag "navbar")
  (published "2026-09-15")
  (modified "2026-10-04")
  (author "Emile"))

# sport

(toc)

## the sports

(query
  (where (has "kind" "sport"))
  (sort "title" asc)
  (cols ("Sport" "title") ("Tags" "tag"))
  (format table))

(query
  (where (and (tag "sport") (not (has "kind" "sport"))))
  (sort "date" desc)
  (group tag "sport")
  (cols ("Title" "title") ("Date" "date"))
  (format table))
