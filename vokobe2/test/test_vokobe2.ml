(* Regression test: s-expressions inside fenced code blocks are examples
   and must not be picked up as page metadata by Page.parse_attrs. *)
let () =
  let raw =
    {|(meta
  (tag "project" "vokobe")
  (published "2026-09-16"))

# vokobe2

```lisp
(meta
  (tag "project" "vokobe")
  (published "2026-09-16"))
```
|}
  in
  let attrs = Vokobe2.Page.parse_attrs raw in
  let get key = match List.assoc_opt key attrs with Some v -> v | None -> [] in
  assert (get "tag" = [ "project"; "vokobe" ]);
  assert (get "published" = [ "2026-09-16" ]);
  (* a (meta ...) that only ever occurs inside a code block yields nothing *)
  let raw2 = "# t\n\n```lisp\n(meta (tag \"x\"))\n```\n" in
  assert (Vokobe2.Page.parse_attrs raw2 = []);
  print_endline "ok"
