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

Over the years, I participated three times, from 2017 to 2019:

(query
  (where (and (tag "jufo")
              (tag "project")))
  (sort "published" asc)
  (group year "published" asc)
  (cols ("Title" "title")
        ("Published" "published"))
  (format table))

In 2022 I visited the [Bundeswettbewerb in Lübeck](/jufo-bundeswettbewerb-lubeck) with some friends — not as a participant, just to look around.