# nix like structures elsewhere

So I've got kind of hooked by the structure nix provides and have throught
about rewriting this static site generator in order to use a simillar
architecture as described in one of the previos blog posts.

The nix like store structure is actually amazing if you think about it: it
allows to build incremental systems that can be build over multiple machines
with some kind of caching mechanism. It's just great!

So, how do we build a static site generator utilizing this architecture?
