(meta
  (tag "navbar")
  (published "2026-09-14")
  (modified "2026-09-22")
  (author "Emile"))

# ctf

(toc)

Capture-The-Flag, one of the most amazing (and sometimes frustrating) ways to learn stuff while looking at computers all day.

In short: other people define challenges that can be solved by gaining access to some information called a "flag" (hence the name: "Capture the flag").

By providing the flag to the people organizing the challenges, one can prove that the challenge has been solved. How you gain access to the flag is up to you, [almost](https://x.com/gf_256/status/1206393845497376768) anything is allowed.

The challenges themselves can fall into many categories, but are mostly part of the reversing, web-exploitation, forensics, cryptography and binary-exploitation categories.

## Resources

- starting out
  - [tryhackme](https://tryhackme.com)
  - [hackthebox](https://www.hackthebox.com)
  - [overthewire](https://overthewire.org/wargames/)
  - [hextree](https://hextree.io)
  - [open security trainings](https://ost2.fyi)
- find CTFs / meta CTF tracking
  - [ctftime](https://ctftime.org)
  - [247ctf](https://247ctf.com)

### Challenges

- pwn
  - [pwn.college](https://pwn.college)
  - [pwnable.kr](https://pwnable.kr)
  - [pwnable.tw](https://pwnable.tw)
  - [pwnable.xyz](https://pwnable.xyz)
- crypto
  - [cryptohack](https://cryptohack.org)
  - [cryptopals](https://cryptopals.com)
- web
  - [Portswigger Academy](https://portswigger.net/web-security)
- archives
  - [archive.ooo](https://archive.ooo)

### Zines

- [paged out!](https://pagedout.institute)
- POC||GTFO: [all issues](https://www.alchemistowl.org/pocorgtfo/)
- [phrack](http://phrack.org)
- [tmpout.sh](https://tmpout.sh)

### Video content

- [LiveOverflow](https://www.youtube.com/@LiveOverflow)
- [PwnFunction](https://www.youtube.com/@PwnFunction)
- [John Hammond](https://www.youtube.com/@_JohnHammond)
- [gamozolabs](https://www.youtube.com/@gamozolabs)
- [Laurie Wired](https://www.youtube.com/@lauriewired)

## Resource pages

(query
  (where (and (tag "ctf") (tag "resource")))
  (sort "title" asc)
  (cols ("Topic" "title"))
  (format list))

## Writeups

(query
  (where (and (tag "ctf") (tag "writeup")))
  (sort "published" desc)
  (cols ("Title" "title") ("Date" "published"))
  (format table))

## Teams

(query
  (where (and (tag "ctf") (tag "team")))
  (sort "title" asc)
  (cols ("Team" "title"))
  (format list))

## Pages with tag ctf and event

(query
  (where (and (tag "ctf") (tag "event")))
  (sort "date" desc)
  (group year "date" desc)
  (cols ("Event" "title") ("Date" "date"))
  (format table))
