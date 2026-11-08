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
  (* JSON smoke test *)
  List.iter
    (fun s ->
      try
        let _ = Vokobe2.Json.parse s in
        ()
      with Vokobe2.Json.Error e ->
        Printf.printf "JSON PARSE FAILED on %S: %s\n" s e;
        exit 1)
    [
      {|{"version": 0.6, "tags": {"a": "b"}}|};
      "{   \"version\": 0.6,\n  \"generator\": \"x\"\n}";
      {|{"a":[{"lat":1.2,"lon":3.4}]}|};
      {|{"elements":[{"type":"way","geometry":[{"lat":51.1,"lon":6.1}]}]}|};
    ];
  let attrs = Vokobe2.Page.parse_attrs raw in
  let get key = match List.assoc_opt key attrs with Some v -> v | None -> [] in
  assert (get "tag" = [ "project"; "vokobe" ]);
  assert (get "published" = [ "2026-09-16" ]);
  (* a (meta ...) that only ever occurs inside a code block yields nothing *)
  let raw2 = "# t\n\n```lisp\n(meta (tag \"x\"))\n```\n" in
  assert (Vokobe2.Page.parse_attrs raw2 = []);
  print_endline "ok"
