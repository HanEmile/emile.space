(meta
  (tag "project")
  (published "2022-01-01")
  (modified "2026-09-22")
  (author "Emile")
  (info "tag")
)

# xilero

Minimal python script generating random names for projects


```
from random import randint

consonants = "bcdfghjklmnpqrstvwxyz"
vowels = "aeiou"

for i in range(0, randint(2, 3)):
    print(consonants[randint(0, len(consonants)-1)], end="")
    print(vowels[randint(0, len(vowels)-1)], end="")
```