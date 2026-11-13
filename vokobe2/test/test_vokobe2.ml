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
        backlinks_op_used = false;
        book_depth = 0;
        heading_offset = 0;
        feed = None;
      }
  in
  let contains = Vokobe2.Util.contains_substring in

  (* backlinks: a /name link counts, /name-foo does not *)
  let target_page = mk_page "target" "# target\n\n(backlinks)\n" in
  let linker = mk_page "linker" "# linker\n\nsee [notes](/target)\n" in
  let prefixer = mk_page "prefixer" "# prefixer\n\nsee [x](/target-ext)\n" in
  let anchored =
    mk_page "anchored" "# lands\n\n## Deep Section\n\ngo [there](/target)\n"
  in
  (* external urls and plain text mentioning /target must NOT count *)
  let faker =
    mk_page "faker"
      "see https://flickr.com/target/?q=1 and rm target/index.html\n"
  in
  let bare = mk_page "bare" "the /target page is neat (not a link)\n" in
  let linkop =
    mk_page "linkop" "# op\n\n(link \"/target\" \"the target\")\n"
  in
  let pages = [target_page; linker; prefixer; anchored; faker; bare; linkop] in
  let backlinks = Vokobe2.Render.render_backlinks (ctx pages target_page) in
  assert (contains backlinks "/linker");
  assert (not (contains backlinks "/prefixer"));
  assert (not (contains backlinks "/faker") && not (contains backlinks "faker"));
  assert (not (contains backlinks "/bare"));
  (* anchored backlinks point at the place on the page they link from *)
  assert (contains backlinks {|<a href="/anchored#deep-section"|});
  (* the sexp (link ...) op counts too *)
  assert (contains backlinks {|<a href="/linkop#op"|});

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

  (* (book "tag"): chapters ordered by published, self excluded,
     chapter headings renumber independently *)
  let ch_old = mk_page "ch-old" "(meta (tag \"story\") (published \"2024-01-01\"))\n\n# Old\n\nold text.\n" in
  let ch_new = mk_page "ch-new" "(meta (tag \"story\") (published \"2025-01-01\"))\n\n# New\n\nnew text.\n" in
  let book = mk_page "my-book" "(meta (tag \"story\") (published \"2026-01-01\"))\n\n# My Book\n\n(toc)\n\n(book \"story\")\n" in
  let pages = [book; ch_new; ch_old] in
  (* production does pass1 (collect_only) then pass2 with the collected
     dynamic headings; chapter titles must reach the (toc) above the
     book op the same way *)
  let c0 = { (ctx pages book) with Vokobe2.Render.collect_only = true } in
  let _ = Vokobe2.Render.render_body c0 book.raw in
  let c2 = { (ctx pages book) with headings = c0.hstate.dynamic_headings } in
  let html = Vokobe2.Render.render_body c2 book.raw in
  let index_of hay needle =
    let n = String.length hay and m = String.length needle in
    let rec go i =
      if i + m > n then -1
      else if String.sub hay i m = needle then i
      else go (i + 1)
    in
    go 0
  in
  (* published 2024 chapter must sort before published 2025 *)
  assert (index_of html "chapter-ch-old" > 0
          && index_of html "chapter-ch-old" < index_of html "chapter-ch-new");
  (* chapter titles are real numbered h2 headings with a permalink *)
  assert (contains html {|<h2 id="chapter-ch-old"|});
  assert (contains html {|1.1. Old|});
  assert (contains html {|<a href="/ch-old">Old</a>|});
  (* ... and the (toc), even placed above the book op, lists them *)
  assert (contains html {|<a href="#chapter-ch-old"|}
          || failwith "toc missing chapter link");
  assert (contains html "old text." && contains html "new text.");
  assert (not (contains html "chapter-my-book"));
  (* chapters' own top-level h1s are stripped (chapter-title replaces
     them); their body text survives *)
  assert (not (contains html {|<h1 id="old"|})
          && not (contains html {|<h1 id="new"|}));

  (* /now: current events beat past, future shows as upcoming *)
  let ongoing =
    mk_page "trip"
      "(meta (date \"2026-11-01\" \"2026-11-20\") (location \"Berlin\" \"Germany\"))\n\n# Trip\n"
  in
  let later =
    mk_page "later"
      "(meta (date \"2026-12-01\" \"2026-12-05\") (location \"Rome\" \"Italy\"))\n\n# Later\n"
  in
  (match Vokobe2.Generator.generate_now_page ~today:"2026-11-13" [ongoing; later] with
   | Some p -> assert (contains p.raw "right now" && contains p.raw "/trip")
   | None -> assert false);
  (match Vokobe2.Generator.generate_now_page ~today:"2026-11-25" [ongoing; later] with
   | Some p ->
       assert (contains p.raw "ended 2026-11-20"
               && contains p.raw "Upcoming: [Later](/later)")
   | None -> assert false);

  (* /on-this-day: events cluster under their month-day section
     (date-range-str is normally added by add_date_range_str at load) *)
  (match Vokobe2.Generator.generate_on_this_day
            (Vokobe2.Generator.add_date_range_str [ongoing]) with
   | Some p ->
       assert (contains p.raw "(toc)");
       assert (contains p.raw "## November\n" && contains p.raw "### November 13"
               && contains p.raw "[Trip](/trip)")
   | None -> assert false);

  (* search pages: table of results, links carry :~:text= fragments *)
  let p1 = mk_page "nixctf" "# Nix CTF\n\nnixos nixos nixos nixos nixos\n" in
  let p2 = mk_page "nixops" "# nixops\n\nnixos nixos nixos nixos\n" in
  let search_pages = Vokobe2.Generator.generate_search_pages [p1; p2] in
  assert (List.length search_pages = 1);
  let sp = List.hd search_pages in
  assert (sp.Vokobe2.Page.name = "search-nixos");
  (* the page raw holds a (table ...) op; render it to check the table *)
  let pages = [sp; p1; p2] in
  let rendered = Vokobe2.Render.render_body (ctx pages sp) sp.raw in
  assert (contains rendered "<table>");
  assert (contains rendered {|<a href="/nixctf#:~:text=nixos"|});
  assert (contains rendered {|<a href="/nixops#:~:text=nixos"|});
  (* prefixed fragments target the snippet's instance; search- pages
     never produce backlinks *)
  let p3 = mk_page "nixguide" "# guide\n\nI really love nixos nixos nixos nixos.\n" in
  (match Vokobe2.Generator.generate_search_pages [p1; p2; p3] with
   | q :: _ ->
       let r = Vokobe2.Render.render_body (ctx [q; p1; p2; p3] q) q.raw in
       assert (contains r "text=I%20really%20love-,nixos&amp;text=nixos")
   | [] -> assert false);
  let search_page =
    mk_page "search-foo" "# search\n\nsee [notes](/nixctf)\n"
  in
  let bl =
    Vokobe2.Render.render_backlinks (ctx [p1; search_page] p1) in
  assert (not (contains bl "/search-foo"));
  (* nixctf (5 hits) ranks before nixops (4 hits) *)
  let io hay needle =
    let n, m = (String.length hay, String.length needle) in
    let rec go i =
      if i + m > n then -1
      else if String.sub hay i m = needle then i
      else go (i + 1)
    in
    go 0
  in
  assert (io rendered "/nixctf#:~:text=nixos" < io rendered "/nixops#:~:text=nixos");

  print_endline "ok"
