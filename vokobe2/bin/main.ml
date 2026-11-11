open Vokobe2

let prof_time name f =
  let t0 = Unix.gettimeofday () in
  let v = f () in
  let dt = Unix.gettimeofday () -. t0 in
  if Sys.getenv_opt "VOKOBE_PROFILE" = Some "1" then
    Printf.eprintf "[prof] %-18s %8.2fs\n%!" name dt;
  v

let () =
  if Array.length Sys.argv < 4 then (
    Printf.eprintf
      "usage: %s <input_dir> <output_dir> <site_name> [--offline] \
       [--dump-missing-queries]\n"
      Sys.argv.(0);
    exit 1);
  let input_dir = Sys.argv.(1) in
  let output_dir = Sys.argv.(2) in
  let site_name = Sys.argv.(3) in

  let flags = Array.sub Sys.argv 4 (Array.length Sys.argv - 4) in
  (* --offline: never fetch external data (map regions without a local
     cache render a placeholder instead) *)
  if Array.exists (( = ) "--offline") flags then begin
    Roughmap.set_offline true;
    Printf.printf "[map] offline mode: skipping external data fetches\n%!"
  end;
  (* --dump-missing-queries: don't fetch; write map-cache/*.query files
     for fetch-map-cache.sh (parallel download, e.g. on a fast host) *)
  if Array.exists (( = ) "--dump-missing-queries") flags then begin
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
     published date; warn about them so dates can be added everywhere. *)
  let undated =
    List.filter
      (fun (p : Page.page) -> List.assoc_opt "date-start" p.Page.attrs = None)
      visible_pages
  in
  if undated <> [] then begin
    Printf.printf "[!] %d pages without a date (listed by published):\n%!"
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

  let render_page pages page =
    let headings = Heading.collect_headings page.Page.raw in
    (* First pass: discover any headings emitted dynamically by queries *)
    Render.dynamic_headings := [];
    Render.current_heading_counters := [];
    Render.current_toc_index := 0;
    let ctx0 = Render.{ pages; current = page; headings; map_cache_dir } in
    let _ = Render.render_body ctx0 page.raw in
    let extra = !Render.dynamic_headings in
    (* Second pass: render with the full heading list so (toc) sees everything *)
    Render.dynamic_headings := [];
    Render.current_heading_counters := [];
    Render.current_toc_index := 0;
    let ctx = Render.{ pages; current = page; headings = headings @ extra; map_cache_dir } in
    let body = Render.render_body ctx page.raw in
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
