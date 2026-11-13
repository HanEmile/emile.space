open Vokobe2

let prof_time name f =
  let t0 = Unix.gettimeofday () in
  let v = f () in
  let dt = Unix.gettimeofday () -. t0 in
  if Sys.getenv_opt "VOKOBE_PROFILE" = Some "1" then
    Printf.eprintf "[prof] %-18s %8.2fs\n%!" name dt;
  v

let () =
  let offline = ref false in
  let dump_queries = ref false in
  let positional = ref [] in
  let usage =
    Printf.sprintf
      "usage: %s <input_dir> <output_dir> <site_name> [--offline] \
       [--dump-missing-queries]"
      Sys.argv.(0)
  in
  Arg.parse
    [
      (* --offline: never fetch external data (map regions without a
         local cache render a placeholder instead) *)
      ("--offline", Arg.Set offline,
       " never fetch external data");
      (* --dump-missing-queries: don't fetch; write map-cache/*.query
         files for fetch-map-cache.sh (parallel download, e.g. on a fast
         host) *)
      ("--dump-missing-queries", Arg.Set dump_queries,
       " write map-cache/*.query files instead of fetching");
    ]
    (fun arg -> positional := arg :: !positional)
    usage;
  let input_dir, output_dir, site_name =
    match List.rev !positional with
    | [i; o; s] -> (i, o, s)
    | _ ->
        Printf.eprintf "%s\n" usage;
        exit 1
  in
  if !offline then begin
    Roughmap.set_offline true;
    Printf.printf "[map] offline mode: skipping external data fetches\n%!"
  end;
  if !dump_queries then begin
    Roughmap.set_dump_queries true;
    Printf.printf "[map] dumping missing region queries instead of fetching\n%!"
  end;

  Util.ensure_dir output_dir;

  (* (map ...) regions are cached as raw Overpass JSON next to the input
     directory (i.e. in the repo, outside the published output). The dir
     is created on first use (see Roughmap.load_region_json). *)
  let map_cache_dir = Filename.concat input_dir "../map-cache" in

  let loaded_pages =
    prof_time "load_pages" (fun () ->
        Page.load_pages input_dir |> Generator.add_date_range_str)
  in

  (* Pages whose name starts with '.' are hidden drafts: rendered to HTML but
     excluded from all index pages, queries, and backlinks. *)
  let is_hidden (p : Page.page) =
    String.length p.name > 0 && p.name.[0] = '.'
  in
  let visible_pages = List.filter (fun p -> not (is_hidden p)) loaded_pages in
  let hidden_pages  = List.filter is_hidden loaded_pages in

  (* Pages without an explicit (date ...) meta are listed under their
     published date; warn about them so dates can be added everywhere.
     Pages with (date "") are intentionally dateless and not warned. *)
  let undated =
    List.filter
      (fun (p : Page.page) ->
        List.assoc_opt "date-start" p.Page.attrs = None
        && List.assoc_opt "dateless" p.Page.attrs = None)
      visible_pages
  in
  if undated <> [] then begin
    Printf.printf
      "[!] %d pages without a date (listed by published; add (date \"\") \
       to silence):\n%!"
      (List.length undated);
    List.iter
      (fun (p : Page.page) -> Printf.printf "      %s\n%!" p.Page.name)
      undated
  end;

  let tag_pages =
    prof_time "gen_tags" (fun () -> Generator.generate_tag_pages visible_pages)
  in
  let date_pages =
    prof_time "gen_dates" (fun () -> Generator.generate_date_pages visible_pages)
  in
  let base_pages = visible_pages @ tag_pages @ date_pages in
  let attr_pages =
    prof_time "gen_locations" (fun () ->
        Generator.generate_location_pages ~map_cache_dir base_pages)
  in
  let all_visible = base_pages @ attr_pages in
  Printf.printf "pages: %d (%d tag, %d date, %d attr, %d hidden)\n%!"
    (List.length all_visible)
    (List.length tag_pages)
    (List.length date_pages)
    (List.length attr_pages)
    (List.length hidden_pages);

  (* name -> page, built once and shared by every render *)
  let page_index = Render.page_index_of all_visible in
  let render_page pages page =
    let headings = Heading.collect_headings page.Page.raw in
    let make_ctx headings collect_only =
      Render.
        {
          pages;
          page_index;
          current = page;
          headings;
          hstate = Render.new_heading_state ();
          map_cache_dir;
          collect_only;
        }
    in
    (* First pass: discover any headings emitted dynamically by queries.
       collect_only=true skips output-only work (maps, nav, backlinks,
       toc); (query ...) still runs so its headings are collected. *)
    let ctx0 = make_ctx headings true in
    let _ = Render.render_body ctx0 page.Page.raw in
    let extra = ctx0.hstate.dynamic_headings in
    (* Second pass: render with the full heading list so (toc) sees everything *)
    let ctx = make_ctx (headings @ extra) false in
    let body = Render.render_body ctx page.Page.raw in
    let html = Render.render_html site_name ctx body in
    let out_path = Filename.concat output_dir (page.name ^ ".html") in
    Util.ensure_dir (Filename.dirname out_path);
    Util.write_file out_path html
  in

  prof_time "render_all" (fun () ->
      List.iter (render_page all_visible) all_visible;
      (* Hidden pages are rendered with the visible context so their own
         queries work, but they don't appear in any listing themselves. *)
      List.iter (render_page all_visible) hidden_pages)
  |> ignore;
  Printf.printf "wrote %d html files\n%!" (List.length all_visible + List.length hidden_pages);

  (* RSS feed of the blog posts (tag "blog"), same selection as /blog *)
  Util.write_file
    (Filename.concat output_dir "rss.xml")
    (Generator.rss_xml ~site_name visible_pages);
  if Sys.getenv_opt "VOKOBE_PROFILE" = Some "1" then begin
    let prof = Printf.eprintf in
    prof "[prof] ------------------------\n%!";
    prof "[prof] queries:      %6.2fs  (%d calls)\n%!"
      !Render.prof_query_t !Render.prof_query_n;
    prof "[prof] navbar:       %6.2fs\n%!" !Render.prof_navbar_t;
    prof "[prof] backlinks:    %6.2fs\n%!" !Render.prof_backlinks_t;
    prof "[prof] sexp_parse:   %6.2fs\n%!" !Render.prof_sxparse_t;
    prof "[prof] maps:         %6.2fs  (%d calls)\n%!"
      !Roughmap.prof_map_t !Roughmap.prof_map_n;
    prof "[prof]   disk read:  %6.2fs\n%!" !Roughmap.prof_disk_t;
    prof "[prof]   json parse: %6.2fs\n%!" !Roughmap.prof_json_t
  end;
  if !Roughmap.fetched > 0 then
    Printf.printf "[map] fetched %d new region(s) of external map data\n%!"
      !Roughmap.fetched;

  let rec copy_non_md src_dir dst_dir =
    Sys.readdir src_dir
    |> Array.iter (fun f ->
           if not (Filename.check_suffix f ".md") then
             let src = Filename.concat src_dir f in
             let dst = Filename.concat dst_dir f in
             if Sys.is_directory src then (
               Util.ensure_dir dst;
               copy_non_md src dst)
             else (
               Util.ensure_dir (Filename.dirname dst);
               Util.write_file dst (Util.read_file src)))
  in
  prof_time "copy_files" (fun () -> copy_non_md input_dir output_dir)
