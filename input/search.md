(meta
  (published "2026-09-14")
  (modified "2026-09-22")
  (author "Emile")
)

# search

Just go to:

```
https://emile.space/search/<search-query>.html
```

All 3-8 char values are precomputed using this bash script:

```
search () {
  rg \
    -g \!search \
    -g "*.md" \
    -C 3 \
    -n \
    --color=never \
    --heading "$0" \
    | awk '/^[^[:space:]]/ && /\.md$/ {
      dir=$0; sub(/README.md/, "", dir);
      print "</pre><a href=\"https://emile.space/" dir "\">/" dir "</a><pre>";
      next
    } {print}' \
    > "search/$0.html"
}
export -f search

time \
  fd \
    -E search \
    -e md . \
      | xargs cat \
      | sed "s/<.*>//g" \
      | tr -C "a-zA-Z0-9" " " \
      | tr "A-Z" "a-z" \
      | tr " " "\n" \
      | rg -o ".{3,8}$" \
      | sort \
      | uniq \
      | xargs -n 1 bash -c "search '$@'"
 
# this is used by vokobe and should not be indexed
rm search/index.html
```


