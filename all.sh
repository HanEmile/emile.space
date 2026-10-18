time \
  fd \
    -E search \
    -e md . input/ \
      | xargs cat \
      | sed "s/<.*>//g" \
      | tr -C "a-zA-Z0-9" " " \
      | tr "A-Z" "a-z" \
      | tr " " "\n" \
      | rg -o ".{3,8}$" \
      | sort \
      | uniq
