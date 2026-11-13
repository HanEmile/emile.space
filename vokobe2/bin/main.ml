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
  let search_pages =
    prof_time "gen_search" (fun () ->
        Generator.generate_search_pages visible_pages)
  in
  let dated_pages =
    prof_time "gen_now_otd" (fun () ->
        let today =
          let tm = Unix.localtime (Unix.time ()) in
          Printf.sprintf "%04d-%02d-%02d" (tm.tm_year + 1900)
            (tm.tm_mon + 1) tm.tm_mday
        in
        Option.to_list (Generator.generate_now_page ~today visible_pages)
        @ Option.to_list (Generator.generate_on_this_day visible_pages)
        @ Option.to_list
            (Generator.generate_travel_page ~map_cache_dir visible_pages))
  in
  let base_pages = base_pages @ dated_pages in
  let all_visible = base_pages @ attr_pages @ search_pages in
  Printf.printf "pages: %d (%d tag, %d date, %d attr, %d search, %d hidden)\n%!"
    (List.length all_visible)
    (List.length tag_pages)
    (List.length date_pages)
    (List.length attr_pages)
    (List.length search_pages)
    (List.length hidden_pages);

  (* RSS feeds: blog (/rss.xml) plus one per tag with >=2 published
     pages (/feed-<tag>.xml); feed_of_page maps tag-page names to feed
     filenames so their pages can advertise the right feed *)
  let feed_of_page : (string, string) Hashtbl.t = Hashtbl.create 16 in
  List.iter
    (fun (file, tag, xml) ->
      Util.write_file (Filename.concat output_dir file) xml;
      Hashtbl.replace feed_of_page tag file)
    (Generator.rss_feeds ~site_name visible_pages);

  (* name -> page, built once and shared by every render *)
  let page_index = Render.page_index_of all_visible in
  (* Per page: two render_body passes (the first in collect-only mode to
     harvest dynamically generated query headings), so body rendering
     costs 2x, plus O(len html) for the template and disk write.  The
     queries/backlinks/navbar inside each render scan all pages, making
     the whole render phase superlinear in the page count. *)
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
          backlinks_op_used = false;
          book_depth = 0;
          heading_offset = 0;
          feed =
            (match Hashtbl.find_opt feed_of_page page.Page.name with
             | Some file -> Some (file, page.Page.name)
             | None -> None);
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

  (* Number of worker domains for page rendering: VOKOBE_JOBS overrides
     (1 = the old sequential loop, for debugging), default is the
     recommended domain count, capped at 8 -- pages are small and the
     returns diminish quickly. *)
  let njobs =
    let from_env =
      match Sys.getenv_opt "VOKOBE_JOBS" with
      | Some s -> (try int_of_string (String.trim s) with _ -> 1)
      | None -> min 8 (max 1 (Domain.recommended_domain_count ()))
    in
    max 1 from_env
  in
  (* Prewarm the shared backlinks cache single-threaded BEFORE spawning:
     it is keyed on the pages-list identity and read-only afterwards, so
     read-only Hashtbl access from multiple domains is then safe.  The
     roughmap geodata/map caches are similarly warmed by gen_locations
     above, and their own cold paths are mutex-guarded (see roughmap.ml). *)
  ignore (Render.backlinks_of all_visible);
  let render_pool =
    (* output-file write order is irrelevant (each page writes its own
       file), so visible and hidden pages share one work queue.
       Per-page hstate/ctx are fresh per page, so heading ids and
       numbering stay deterministic regardless of scheduling. *)
    let pages = Array.of_list (all_visible @ hidden_pages) in
    let n = Array.length pages in
    fun () ->
      if njobs = 1 then Array.iter (render_page all_visible) pages
      else begin
        let next = Atomic.make 0 in
        let rec work () =
          let i = Atomic.fetch_and_add next 1 in
          if i < n then begin
            render_page all_visible pages.(i);
            work ()
          end
        in
        (* njobs - 1 extra domains; the main domain works too *)
        let domains =
          List.init (njobs - 1) (fun _ -> Domain.spawn work)
        in
        work ();
        List.iter Domain.join domains
      end
  in
  (* Hidden pages are rendered with the visible context (all_visible) so
     their own queries work, but they don't appear in any listing. *)
  prof_time "render_all" render_pool |> ignore;
  Printf.printf "wrote %d html files\n%!" (List.length all_visible + List.length hidden_pages);


  if Sys.getenv_opt "VOKOBE_PROFILE" = Some "1" then begin
    let prof = Printf.eprintf in
    prof "[prof] ------------------------\n%!";
    prof "[prof] jobs:          %6d     (render pool)\n%!" njobs;
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

  (* O(total bytes of non-.md files): recursive directory walk copying
     every asset verbatim. *)
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
