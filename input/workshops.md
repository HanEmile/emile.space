(meta
  (tag "navbar")
  (published "2026-09-14")
  (modified "2026-09-22")
  (author "Emile"))

# workshops

workshops are kind of like talks, with the fundamental difference that there is some kind of interaction between the speaker and the audience.

## Series

(query
  (where (and (tag "workshop") (tag "ctf")))
  (sort "date" asc)
  (group year "date" desc)
  (cols ("Workshop" "title") ("Date" "date"))
  (format table))

## All workshops

(query
  (where (tag "workshop"))
  (sort "date" desc)
  (group year "date" desc)
  (cols ("Title" "title") ("Date" "date") ("Tags" "tag"))
  (format table))
