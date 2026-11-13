(meta
  (date "")
  (tag "project")
  (published "2022-01-01")
  (modified "2026-11-13")
  (author "Emile")
  (info "tag")
)

# Jugend Forscht

"Jugend Forscht" ("youth does science") is a german competition enabling students from the age from 14-22 to work on projects to display at an event.

Over the years, I participated three times:

(query
  (where (tag "jufo"))
  (sort "published" asc)
  (group year "published" asc)
  (cols ("Title" "title")
        ("Published" "published"))
  (format table))