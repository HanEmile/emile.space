(meta
  (tag "event")
  (published "2023-09-01")
  (modified "2026-09-22")
  (date "2023-09-01")
  (author "Emile")
  (info "tag" "date" "location")
  (location "Novi Sad" "Serbia")
)

# BAlCCon

## r2wars - battle bots in shared memory

2023-09-10 15:40 - 16:40
Room: Tesla

Running programmes simultaneously in the same memory: what could go wrong? This is about how and then playing with it hands-on. We look at the substructure, build our own small programmes that then try to overwrite each other.

```
; r2 malloc://1024
[0x00000000]> aei
[0x00000000]> aeim
[0x00000000]> wx e80000000058 @ 0x100
[0x00000000]> aer PC = 0x100
[0x00000000]> aer SP = SP + 0x100
[0x00000000]> aes
[0x00000000]> aerR
```

### Links

- [balcon slides](/balccon-r2wars.pdf)
- [github.com/hanemile/r2wars](https://github.com/hanemile/r2wars)
- [r2wars blogpost (en) with a lot of info](/r2wars)
- [pretalx page](https://cfp.balccon.org/balccon2k23/talk/SNH8QR/)
- [GPN slides (weird pdf pdf)](/gpn23-r2wars_GPN21.pdf)
