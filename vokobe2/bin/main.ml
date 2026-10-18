open Vokobe2

let () =
  if Array.length Sys.argv < 4 then (
    Printf.eprintf "usage: %s <input_dir> <output_dir> <site_name>\n" Sys.argv.(0);
    exit 1);
  let input_dir = Sys.argv.(1) in
  let output_dir = Sys.argv.(2) in
  let site_name = Sys.argv.(3) in

  Util.ensure_dir output_dir;

  let loaded_pages = Page.load_pages input_dir
                     |> Generator.add_date_range_str in

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

  let tag_pages = Generator.generate_tag_pages visible_pages in
  let date_pages = Generator.generate_date_pages visible_pages in
  let base_pages = visible_pages @ tag_pages @ date_pages in
  let attr_pages = Generator.generate_location_pages base_pages in
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
    let ctx0 = Render.{ pages; current = page; headings } in
    let _ = Render.render_body ctx0 page.raw in
    let extra = !Render.dynamic_headings in
    (* Second pass: render with the full heading list so (toc) sees everything *)
    Render.dynamic_headings := [];
    Render.current_heading_counters := [];
    Render.current_toc_index := 0;
    let ctx = Render.{ pages; current = page; headings = headings @ extra } in
    let body = Render.render_body ctx page.raw in
    let html = Render.render_html site_name ctx body in
    let out_path = Filename.concat output_dir (page.name ^ ".html") in
    Util.ensure_dir (Filename.dirname out_path);
    Util.write_file out_path html
  in

  List.iter (render_page all_visible) all_visible;
  (* Hidden pages are rendered with the visible context so their own queries
     work, but they don't appear in any listing themselves. *)
  List.iter (render_page all_visible) hidden_pages;
  Printf.printf "wrote %d html files\n%!" (List.length all_visible + List.length hidden_pages);

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
  copy_non_md input_dir output_dir
