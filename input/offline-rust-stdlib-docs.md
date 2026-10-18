(meta
  (tag "blog" "rust" "stdlib")
  (published "2022-01-03")
  (modified "2026-09-14")
  (author "Emile"))

# offline rust stdlib docs

Rust has got an amazing documentation, but in order to access it, you need some kind of internet connection. This can be anoying.

Including the following lines into your project allows viewing the rust stdlib documentation when running `cargo doc --open` or so:

```
#[doc(inline)]
pub use std;
```

I found this useful.

Found here:
[https://github.com/rust-lang/rfcs/issues/2324#issuecomment-502437904](https://github.com/rust-lang/rfcs/issues/2324#issuecomment-502437904)
