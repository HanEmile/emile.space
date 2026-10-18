(meta
  (tag "sport")
  (kind "sport")
  (published "2022-01-01")
  (modified "2026-09-22")
  (author "Emile")
  (info "tag")
)

# sail

Getting from A to B using the Wind.

(query
  (where (tag "sail"))
  (sort "published" desc)
  (group year "published" desc)
  (cols ("Title" "title") ("Published" "published"))
  (format table))|}

