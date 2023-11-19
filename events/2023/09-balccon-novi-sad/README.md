# balcon novi sad

## r2wars - battle bots in shared memory

2023-09-10 15:40 - 16:40
Room: Tesla

Running programmes simultaneously in the same memory: what could go wrong? This is about how and then playing with it hands-on. We look at the substructure, build our own small programmes that then try to overwrite each other.

> ; r2 malloc://1024
> [0x00000000]> aei
> [0x00000000]> aeim
> [0x00000000]> wx e80000000058 @ 0x100
> [0x00000000]> aer PC = 0x100
> [0x00000000]> aer SP = SP + 0x100
> [0x00000000]> aes
> [0x00000000]> aerR

### Links

- [balcon slides](./r2wars.pdf)
- [github.com/hanemile/r2wars](https://github.com/hanemile/r2wars)
- [r2wars blogpost (en) with a lot of info](/blog/2020/10-10-r2wars/)
- [pretalx page](https://cfp.balccon.org/balccon2k23/talk/SNH8QR/)
- [GPN slides (nice html export)](../06-GPN/.r2wars_GPN21/presentation.htm)
- [GPN slides (weird pdf pdf)](../06-GPN/r2wars_GPN21.pdf)
