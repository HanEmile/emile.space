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

  (* helpers *)
  let mk_page name raw =
    Vokobe2.Page.
      {
        name;
        title = Vokobe2.Page.page_title_of name raw;
        raw;
        attrs = Vokobe2.Page.parse_attrs raw;
      }
  in
  let ctx pages current =
    Vokobe2.Render.
      {
        pages;
        page_index = Vokobe2.Render.page_index_of pages;
        current;
        headings = [];
        hstate = Vokobe2.Render.new_heading_state ();
        map_cache_dir = ".";
        collect_only = false;
      }
  in
  let contains = Vokobe2.Util.contains_substring in

  (* backlinks: a /name link counts, /name-foo does not *)
  assert (Vokobe2.Render.references_name "see [notes](/gpn21) here" "gpn21");
  assert (Vokobe2.Render.references_name "bare /gpn21 link" "gpn21");
  assert (not (Vokobe2.Render.references_name "[x](/gpn21-foo)" "gpn21"));
  assert (not (Vokobe2.Render.references_name "no link here" "gpn21"));
  let target_page = mk_page "target" "# target\n\n(backlinks)\n" in
  let linker = mk_page "linker" "# linker\n\nsee [notes](/target)\n" in
  let prefixer = mk_page "prefixer" "# prefixer\n\nsee [x](/target-ext)\n" in
  let pages = [target_page; linker; prefixer] in
  let backlinks = Vokobe2.Render.render_backlinks (ctx pages target_page) in
  assert (contains backlinks "/linker");
  assert (not (contains backlinks "/prefixer"));

  (* heading numbering stays continuous across static headings and
     (group tag) query headings; no duplicate numbers/ids *)
  let post_a = mk_page "post-a" "(meta (tag \"aaa\"))\n\n# post a\n" in
  let post_b = mk_page "post-b" "(meta (tag \"bbb\"))\n\n# post b\n" in
  let main =
    mk_page "main"
      "# Main\n\n## First\n\n(query\n  (group tag))\n\n## Last\n"
  in
  let pages = [post_a; post_b; main] in
  let html = Vokobe2.Render.render_body (ctx pages main) main.raw in
  assert (contains html {|<h2 id="first"|} && contains html "1.1. First");
  assert (contains html {|<h2 id="aaa"|} && contains html "1.2. aaa");
  assert (contains html {|<h2 id="bbb"|} && contains html "1.3. bbb");
  assert (contains html {|<h2 id="last"|} && contains html "1.4. Last");

  (* generate_date_pages: a real page named like a date key wins *)
  let year_page = mk_page "2026" "# my 2026 page\n" in
  let post = mk_page "post" "(meta (published \"2026-05-01\"))\n\n# post\n" in
  let date_pages = Vokobe2.Generator.generate_date_pages [year_page; post] in
  assert (List.exists (fun p -> p.Vokobe2.Page.name = "2026-05") date_pages);
  assert (List.exists (fun p -> p.Vokobe2.Page.name = "2026-05-01") date_pages);
  assert (not (List.exists (fun p -> p.Vokobe2.Page.name = "2026") date_pages));

  (* rss excerpt: meta/(toc)/(query) blocks and headings are skipped,
     the first prose paragraph is returned with markdown stripped *)
  let raw =
    {|(meta
  (published "2026-01-01"))

# Big Heading

(toc)

(query
  (where (tag "blog")))

First **prose** paragraph with a [link](/target) inside.

Second paragraph.
|}
  in
  assert (
    Vokobe2.Generator.excerpt_of_raw raw
    = "First prose paragraph with a link inside.");

  (* an unbalanced '(' must not swallow the rest of the page into one
     escaped blob *)
  let broken = mk_page "broken" "# broken\n\n(unbalanced paren\nrest of <page>\n" in
  let html = Vokobe2.Render.render_body (ctx [broken] broken) broken.raw in
  assert (contains html "&lt;page&gt;");
  assert (not (contains html "\\n"));

  print_endline "ok"
