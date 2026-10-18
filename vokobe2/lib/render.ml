open Sexp

type context = {
  pages : Page.page list;
  current : Page.page;
  headings : Heading.heading list;
}

let dynamic_headings : Heading.heading list ref = ref []
let current_heading_counters : int list ref = ref []
let current_toc_index : int ref = ref 0

let page_link (p : Page.page) : string = "/" ^ p.name

(* Group items by key, merging non-adjacent occurrences of the same key.
   Keys keep first-appearance order, items keep their incoming order. *)
let group_by_key (key_of : 'a -> string) (items : 'a list) : (string * 'a list) list =
  List.fold_left
    (fun acc x ->
      let k = key_of x in
      if List.mem_assoc k acc then
        List.map (fun (k2, xs) -> if k2 = k then (k2, xs @ [x]) else (k2, xs)) acc
      else acc @ [(k, [x])])
    [] items

let page_has_tag (p : Page.page) (target_tag : string) : bool =
  List.exists
    (fun (k, vals) -> k = "tag" && List.mem target_tag vals)
    p.attrs

let tag_link (pages : Page.page list) (tag : string) : string =
  match List.find_opt (fun (p : Page.page) -> p.name = tag) pages with
  | Some target_page -> "/" ^ target_page.name
  | None -> "/" ^ tag

let format_date_links (date_str : string) : string =
  match String.split_on_char '-' (String.trim date_str) with
  | [year; month; day] ->
      Printf.sprintf
        {|<a href="/%s" class="local">%s</a>-<a href="/%s-%s" class="local">%s</a>-<a href="/%s-%s-%s" class="local">%s</a>|}
        year year year month month year month day day
  | [year; month] ->
      Printf.sprintf
        {|<a href="/%s" class="local">%s</a>-<a href="/%s-%s" class="local">%s</a>|}
        year year year month month
  | [year] ->
      Printf.sprintf
        {|<a href="/%s" class="local">%s</a>|}
        year year
  | _ -> Util.html_escape date_str

let get_page_attr (pages : Page.page list) (p : Page.page) (key : string) : string =
  match key with
  | "title" -> p.title
  | "name" -> p.name
  | "link" -> page_link p
  | "date-range" -> (
      match List.assoc_opt "date-start" p.attrs with
      | Some (d :: _) ->
          let start_html = format_date_links d in
          (match List.assoc_opt "date-end" p.attrs with
           | Some (e :: _) when e <> d -> start_html ^ " – " ^ format_date_links e
           | _ -> start_html)
      | _ -> "")
  | "published" | "modified" -> (
      match List.assoc_opt key p.attrs with
      | Some (d :: _) -> format_date_links d
      | _ -> "")
  | "date" -> (
      let start =
        match List.assoc_opt "date-start" p.attrs with
        | Some (d :: _) -> Some d
        | _ -> (match List.assoc_opt "published" p.attrs with
                | Some (d :: _) -> Some d
                | _ -> (match List.assoc_opt "date" p.attrs with
                        | Some (d :: _) -> Some d
                        | _ -> None))
      in
      match start with
      | Some d ->
          let start_html = format_date_links d in
          (match List.assoc_opt "date-end" p.attrs with
           | Some (e :: _) when e <> d -> start_html ^ " – " ^ format_date_links e
           | _ -> start_html)
      | None -> "")
  | "date-end" -> (
      match List.assoc_opt "date-end" p.attrs with
      | Some (d :: _) -> format_date_links d
      | _ -> "")
  | "tag" | "tags" -> (
      match List.assoc_opt "tag" p.attrs with
      | Some tags ->
          tags
          |> List.map (fun t ->
                 Printf.sprintf
                 {|<a href="%s" class="local">%s</a>|}
                 (tag_link pages t) t)
          |> String.concat ", "
      | None -> "")
  | "location" ->
      (* Zip cities and countries into "City, Country" pairs, " / " separated *)
      let render_val v =
        let slug = Util.sanitize v in
        match List.find_opt (fun (tp : Page.page) -> tp.name = slug) pages with
        | Some _ -> Printf.sprintf {|<a href="/%s" class="local">%s</a>|} slug (Util.html_escape v)
        | None -> Util.html_escape v
      in
      let cities   = Option.value ~default:[] (List.assoc_opt "location" p.attrs) in
      let countries = Option.value ~default:[] (List.assoc_opt "country"  p.attrs) in
      List.mapi (fun i city ->
        let city_html = render_val city in
        match List.nth_opt countries i with
        | Some c -> city_html ^ ", " ^ render_val c
        | None   -> city_html)
        cities
      |> String.concat " / "
  | _ -> (
      match List.assoc_opt key p.attrs with
      | Some vals ->
          vals
          |> List.map (fun v ->
                 let slug = Util.sanitize v in
                 match List.find_opt (fun (tp : Page.page) -> tp.name = slug) pages with
                 | Some _ ->
                     Printf.sprintf
                     {|<a href="/%s" class="local">%s</a>|}
                     slug (Util.html_escape v)
                 | None -> Util.html_escape v)
          |> String.concat ", "
      | None -> "")

let render_info_bar (ctx : context) : string =
  let p = ctx.current in
  match List.assoc_opt "info" p.attrs with
  | None | Some [] -> ""
  | Some keys ->
      let items =
        List.filter_map
          (fun key ->
            let val_str = get_page_attr ctx.pages p key in
            if val_str = "" then None
            else
              let index_key = match key with
                | "published" | "modified" | "date-range" -> "date"
                | k -> k
              in
              let key_label =
                match List.find_opt (fun (tp : Page.page) -> tp.name = index_key) ctx.pages with
                | Some _ ->
                    Printf.sprintf
                    {|<a href="/%s" class="local">%s</a>|}
                    index_key (Util.html_escape key)
                | None -> Util.html_escape key
              in
              Some
                (Printf.sprintf
                {|<span class="info-item info-%s"><strong>%s:</strong> %s</span>|}
                key key_label val_str))
          keys
      in
      if items = [] then ""
      else
        "<div class=\"info-bar\">\n  " ^
        String.concat " <br> " items ^
        "\n</div>\n"

let rec eval_filter (pages : Page.page list) (p : Page.page) (sx : sexp) : bool =
  match sx with
  | Atom "true" -> true
  | List [Atom "tag"; Atom t] ->
      let tags = match List.assoc_opt "tag" p.attrs with Some ts -> ts | None -> [] in
      List.mem t tags
  | List [Atom "eq"; Atom key; Atom target] ->
      get_page_attr pages p key = target
  | List [Atom "contains"; Atom key; Atom needle] ->
      Util.contains_substring (get_page_attr pages p key) needle
  | List [Atom "has"; Atom key; Atom needle] ->
      (match List.assoc_opt key p.attrs with
       | Some vals -> List.mem needle vals
       | None -> false)
  | List (Atom "and" :: rest) ->
      List.for_all (eval_filter pages p) rest
  | List (Atom "or" :: rest) ->
      List.exists (eval_filter pages p) rest
  | List [Atom "not"; sub] ->
      not (eval_filter pages p sub)
  | _ -> false

let render_query (ctx : context) (args : sexp list) : string =
  let where_cond = ref (Atom "true") in
  let sort_key = ref "" in
  let sort_desc = ref false in
  let format_mode = ref "table" in
  let cols = ref [("Title", "title"); ("Date", "date")] in
  let group_by_year = ref "" in
  let group_year_desc = ref false in
  let group_by_field = ref "" in
  let group_field_pair = ref "" in
  let group_by_tag = ref false in
  let group_tag_skip = ref [] in

  List.iter
    (function
      | List (Atom "where" :: cond :: _) -> where_cond := cond
      | List [Atom "sort"; Atom key; Atom dir] ->
          sort_key := key;
          sort_desc := (dir = "desc")
      | List [Atom "format"; Atom fmt] -> format_mode := fmt
      | List [Atom "group"; Atom "year"; Atom field] -> group_by_year := field
      | List [Atom "group"; Atom "year"; Atom field; Atom dir] ->
          group_by_year := field;
          group_year_desc := (dir = "desc")
      | List [Atom "group"; Atom "field"; Atom attr] -> group_by_field := attr
      | List [Atom "group"; Atom "field"; Atom attr; Atom pair] ->
          group_by_field := attr; group_field_pair := pair
      (* (group tag) or (group tag "skip-me" ...) to omit sections for given tags *)
      | List (Atom "group" :: Atom "tag" :: skips) ->
          group_by_tag := true;
          group_tag_skip :=
            List.filter_map (function Atom t -> Some t | _ -> None) skips
      | List (Atom "cols" :: raw_cols) ->
          let parsed =
            List.filter_map
              (function
                | Atom name -> Some (String.capitalize_ascii name, name)
                | List [Atom label; Atom field] -> Some (label, field)
                | _ -> None)
              raw_cols
          in
          if parsed <> [] then cols := parsed
      | _ -> ())
    args;

  let matched = List.filter (fun p -> eval_filter ctx.pages p !where_cond) ctx.pages in
  let sorted =
    if !sort_key <> "" then
      List.sort
        (fun a b ->
          let va = get_page_attr ctx.pages a !sort_key in
          let vb = get_page_attr ctx.pages b !sort_key in
          let cmp = String.compare va vb in
          if !sort_desc then -cmp else cmp)
        matched
    else matched
  in

  match !format_mode with
  | "list" ->
      let items =
        List.map
          (fun p ->
            let is_active = (p.Page.name = ctx.current.name) in
            let class_attr = if is_active then " class=\"active\"" else "" in
            Printf.sprintf
              {|<li><a href="%s"%s>%s</a></li>
|}
              (page_link p) class_attr (Util.html_escape p.title))
          sorted
      in
      "<ul>\n" ^ String.concat "" items ^ "</ul>"

  | _ ->
      let ncols = List.length !cols in
      let header_html =
        "<tr>"
        ^ String.concat ""
            (List.map (fun (label, _) -> Printf.sprintf "<th>%s</th>" (Util.html_escape label)) !cols)
        ^ "</tr>\n"
      in
      let year_of p =
        (* "date" is virtual: same fallback chain as get_page_attr *)
        let lookup key = match List.assoc_opt key p.Page.attrs with
          | Some (v :: _) -> Some (String.trim v)
          | _ -> None
        in
        let v =
          if !group_by_year = "date" then
            match lookup "date-start" with
            | Some d -> d
            | None -> (match lookup "published" with
                       | Some d -> d
                       | None -> Option.value ~default:"" (lookup "date"))
          else Option.value ~default:"" (lookup !group_by_year)
        in
        match String.split_on_char '-' v with
        | year :: _ -> year
        | [] -> ""
      in
      let make_row p =
        "<tr>"
        ^ String.concat ""
            (List.map
               (fun (_, field) ->
                 let val_str = get_page_attr ctx.pages p field in
                 let cell_content =
                   if field = "title" then
                     Printf.sprintf "<a href=\"%s\">%s</a>" (page_link p) (Util.html_escape p.title)
                   else val_str
                 in
                 Printf.sprintf "<td>%s</td>" cell_content)
               !cols)
        ^ "</tr>\n"
      in
      let rows_html =
        if !group_by_field <> "" then begin
          let render_val v =
            let slug = Util.sanitize v in
            match List.find_opt (fun (tp : Page.page) -> tp.name = slug) ctx.pages with
            | Some _ -> Printf.sprintf {|<a href="/%s" class="local">%s</a>|} slug (Util.html_escape v)
            | None -> Util.html_escape v
          in
          let filter_vals p vs =
            if !group_field_pair = "" then vs
            else
              let pairs = Option.value ~default:[]
                (List.assoc_opt !group_field_pair p.Page.attrs) in
              List.filteri (fun i _ ->
                match List.nth_opt pairs i with
                | Some c -> c = ctx.current.title
                | None   -> true)
              vs
          in
          let key_of p =
            match List.assoc_opt !group_by_field p.Page.attrs with
            | Some vs -> String.concat " / " (List.map String.trim (filter_vals p vs))
            | None -> ""
          in
          let label_of p =
            match List.assoc_opt !group_by_field p.Page.attrs with
            | Some vs -> String.concat " / " (List.map render_val (filter_vals p vs))
            | None -> ""
          in
          let grouped = group_by_key key_of sorted in
          List.concat_map
            (fun (_, group_pages) ->
              let label = match group_pages with p :: _ -> label_of p | [] -> "" in
              let header = Printf.sprintf {|<tr><td colspan="%d" class="year-group">%s</td></tr>|} ncols label in
              header :: List.map make_row group_pages)
            grouped
        end
        else if !group_by_year = "" then List.map make_row sorted
        else begin
          (* Collect rows into (year, pages) groups, then sort groups by year *)
          let grouped = group_by_key year_of sorted in
          let grouped_sorted =
            List.sort
              (fun (a, _) (b, _) ->
                let cmp = String.compare a b in
                if !group_year_desc then -cmp else cmp)
              grouped
          in
          List.concat_map
            (fun (yr, pages) ->
              let header =
                Printf.sprintf
                {|<tr><td colspan="%d" class="year-group">%s</td></tr>|}
                  ncols (format_date_links yr)
              in
              header :: List.map make_row pages)
            grouped_sorted
        end
      in
      if !group_by_tag then begin
        let system_tags = ["date"; "city"; "location"; "country"; "tag"; "meta"] in
        let all_tags =
          sorted
          |> List.concat_map (fun p ->
                 match List.assoc_opt "tag" p.Page.attrs with
                 | Some ts -> ts | None -> [])
          |> List.sort_uniq String.compare
        in
        let ordered_tags =
          let all_tags = List.filter (fun t -> not (List.mem t !group_tag_skip)) all_tags in
          let sys = List.filter (fun t -> List.mem t all_tags) system_tags in
          let rest = List.filter (fun t -> not (List.mem t system_tags)) all_tags in
          sys @ rest
        in
        let tag_label tag =
          let slug = Util.sanitize tag in
          match List.find_opt (fun (tp : Page.page) -> tp.name = slug) ctx.pages with
          | Some _ -> Printf.sprintf {|<a href="/%s" class="local">%s</a>|} slug (Util.html_escape tag)
          | None -> Util.html_escape tag
        in
        let sections = List.filter_map
          (fun tag ->
            let pages_with_tag = List.filter (fun p ->
              match List.assoc_opt "tag" p.Page.attrs with
              | Some ts -> List.mem tag ts | None -> false)
              sorted
            in
            if pages_with_tag = [] then None
            else Some (tag, pages_with_tag))
          ordered_tags
        in
        String.concat "" (List.map
          (fun (tag, pages_with_tag) ->
            let slug = Util.sanitize tag in
            let counters = Heading.update_counters !current_heading_counters 2 in
            current_heading_counters := counters;
            let num_str = Heading.format_counter counters in
            let idx = !current_toc_index in
            current_toc_index := idx + 1;
            dynamic_headings := !dynamic_headings @ [{
              Heading.level = 2; title = tag; slug;
              number_str = num_str ^ " " ^ tag;
            }];
            Printf.sprintf {|<h2 id="%s" style="--is: --h-%d"><a href="#%s">%s %s</a></h2>%!|}
              slug idx slug num_str (tag_label tag)
            ^ "<table>\n"
            ^ String.concat "" (List.map make_row pages_with_tag)
            ^ "</table>\n")
          sections)
      end
      else "<table>\n" ^ header_html ^ String.concat "" rows_html ^ "</table>"

let render_navbar (ctx : context) : string =
  let nav_args = [
    List [Atom "where"; List [Atom "tag"; Atom "navbar"]];
    List [Atom "format"; Atom "list"];
  ] in
  let links_html = render_query ctx nav_args in
  links_html ^
  {|<ul style="float: right">
    <!-- <li>
      <form method="GET" action="/search">
        <input type="text" id="q" name="q" placeholder="search">
      </form>
    </li>
    <li><a href="README.md">.md</a></li> -->
  </ul>|}

let render_toc (headings : Heading.heading list) : string =
  let items =
    List.mapi
      (fun i (h : Heading.heading) ->
        Printf.sprintf
          {|<li class="toc-h%d"><a href="#%s" style="--for: --h-%d">%s</a></li>|}
          h.level h.slug i h.number_str)
      headings
  in
  "<ul class=\"toc\">\n" ^ String.concat "" items ^ "</ul>"

let render_backlinks (ctx : context) : string =
  let target = ctx.current.name ^ ".md" in
  let refs =
    List.filter
      (fun p -> p.Page.name <> ctx.current.name && Util.contains_substring p.raw target)
      ctx.pages
  in
  match refs with
  | [] -> ""
  | _ ->
      let items =
        List.map
          (fun p ->
            Printf.sprintf "<a href=\"%s\">%s</a><br>" (page_link p)
              (Util.html_escape p.title))
          refs
      in
      "<div class=\"backlinks\">Backlinks<br>\n" ^ String.concat "" items ^ "</div>"

let known_inline_ops = [
  "nav"; "list-pages"; "toc"; "backlinks"; "site-name";
  "img"; "link"; "table"; "green"; "bold"; "em"; "code"; "quote"; "query"; "meta"; "details";
  "location"
]

let rec eval (ctx : context) (sx : sexp) : string =
  match sx with
  | Atom a -> Util.html_escape a
  | List [] -> ""
  | List (Atom op :: args) -> eval_call ctx op args
  | List (head :: _) -> eval ctx head

and eval_call (ctx : context) (op : string) (args : sexp list) : string =
  match (op, args) with
  | "nav", _ -> "<nav>" ^ render_navbar ctx ^ "</nav>"

  | "list-pages", Atom substr :: _ ->
      render_query ctx [
        List [Atom "where"; List [Atom "contains"; Atom "title"; Atom substr]];
        List [Atom "format"; Atom "list"];
      ]

  | "toc", _ -> render_toc (ctx.headings @ !dynamic_headings)

  | "backlinks", _ -> render_backlinks ctx

  | "site-name", _ -> ""

  | "img", Atom url :: rest ->
    let alt = match rest with Atom a :: _ -> a | _ -> "" in
    let width_attr =
      match rest with
      | _ :: Atom w :: _ when w <> "" -> Printf.sprintf " width=\"%s\"" (Util.html_escape w)
      | _ -> ""
    in
    let height_attr =
      match rest with
      | _ :: _ :: Atom h :: _ when h <> "" -> Printf.sprintf " height=\"%s\"" (Util.html_escape h)
      | _ -> ""
    in
    Printf.sprintf "<img src=\"%s\" alt=\"%s\"%s%s>" url (Util.html_escape alt) width_attr height_attr

  | "link", Atom target :: rest ->
      let label = match rest with Atom l :: _ -> l | _ -> target in
      Printf.sprintf "<a href=\"/%s.html\">%s</a>" target (Util.html_escape label)

  | "table", rows ->
      let ncols =
        List.fold_left (fun mx row ->
          match row with
          | List (Atom "header" :: hdrs) -> max mx (List.length hdrs)
          | List (Atom "row" :: cells) -> max mx (List.length cells)
          | List (Atom "section" :: _) -> mx
          | List cells -> max mx (List.length cells)
          | _ -> mx) 0 rows
      in
      let cell_html c = match c with
        | Atom s -> render_line ctx s
        | List _ -> eval ctx c
      in
      let render_table_row = function
        | List (Atom "header" :: cells) ->
            "  <tr>" ^ String.concat ""
              (List.map (fun c -> Printf.sprintf "<th>%s</th>" (cell_html c)) cells)
            ^ "</tr>\n"
        | List (Atom "section" :: Atom label :: _) ->
            Printf.sprintf "  <tr><td colspan=\"%d\" class=\"section\">%s</td></tr>\n"
              ncols (render_line ctx label)
        | List (Atom "row" :: cells) ->
            "  <tr>" ^ String.concat ""
              (List.map (fun c -> Printf.sprintf "<td>%s</td>" (cell_html c)) cells)
            ^ "</tr>\n"
        | List cells ->
            "  <tr>" ^ String.concat ""
              (List.map (fun c -> Printf.sprintf "<td>%s</td>" (cell_html c)) cells)
            ^ "</tr>\n"
        | _ -> ""
      in
      "<table>\n" ^ String.concat "" (List.map render_table_row rows) ^ "</table>"

  | "green", rest ->
      let content = String.concat "" (List.map (fun c -> match c with
        | Atom s -> render_line ctx s
        | List _ -> eval ctx c) rest)
      in
      "<span class=\"green\">" ^ content ^ "</span>"

  | "details", rest ->
      let content = String.concat " " (List.map (fun c -> match c with
        | Atom s -> render_line ctx s
        | List _ -> eval ctx c) rest)
      in
      "<details><p>" ^ content ^ "</p></details>"

  | "bold", rest ->
      "<b>" ^ String.concat " " (List.map (eval ctx) rest) ^ "</b>"

  | "em", rest -> "<em>" ^ String.concat " " (List.map (eval ctx) rest) ^ "</em>"

  | "code", rest ->
      "<code>" ^ String.concat " " (List.map (eval ctx) rest) ^ "</code>"

  | "quote", rest ->
      "<blockquote>" ^ String.concat " " (List.map (eval ctx) rest)
      ^ "</blockquote>"

  | "query", args -> render_query ctx args

  | "meta", _ -> ""

  (* Inline location marker: renders "City, Country" with links to the
     generated index pages; the attrs themselves are picked up by Page.parse_attrs. *)
  | "location", vals ->
      let render_val v =
        let slug = Util.sanitize v in
        match List.find_opt (fun (tp : Page.page) -> tp.name = slug) ctx.pages with
        | Some _ -> Printf.sprintf {|<a href="/%s" class="local">%s</a>|} slug (Util.html_escape v)
        | None -> Util.html_escape v
      in
      vals
      |> List.filter_map (function Atom s -> Some s | _ -> None)
      |> List.map render_val
      |> String.concat ", "

  | _ ->
      let args_str = String.concat " " (List.map (eval ctx) args) in
      "(" ^ Util.html_escape op ^ (if args_str = "" then "" else " " ^ args_str) ^ ")"

and render_line (ctx : context) (line : string) : string =
  let len = String.length line in
  let buf = Buffer.create len in
  let i = ref 0 in
  while !i < len do
    let c = line.[!i] in

    (* images *)
    if c = '!' && !i + 1 < len && line.[!i + 1] = '[' then (
      match String.index_from_opt line (!i + 1) ']' with
      | Some close_bracket
        when close_bracket + 1 < len && line.[close_bracket + 1] = '(' -> (
          match String.index_from_opt line (close_bracket + 1) ')' with
          | Some close_paren ->
              let alt = String.sub line (!i + 2) (close_bracket - !i - 2) in
              let url =
                String.sub line
                  (close_bracket + 2)
                  (close_paren - close_bracket - 2)
              in
              Buffer.add_string buf
                (Printf.sprintf "<img src=\"%s\" alt=\"%s\">" url (Util.html_escape alt));
              i := close_paren + 1
          | None ->
              Buffer.add_char buf c;
              incr i)
      | _ ->
          Buffer.add_char buf c;
          incr i)

    (* links *)
    else if c = '[' then (
      match String.index_from_opt line !i ']' with
      | Some close_bracket
        when close_bracket + 1 < len && line.[close_bracket + 1] = '(' -> (
          match String.index_from_opt line (close_bracket + 1) ')' with
          | Some close_paren ->
              let text = String.sub line (!i + 1) (close_bracket - !i - 1) in
              let url =
                String.sub line
                  (close_bracket + 2)
                  (close_paren - close_bracket - 2)
              in
              Buffer.add_string buf
                (Printf.sprintf "<a href=\"%s\">%s</a>" url (Util.html_escape text));
              i := close_paren + 1
          | None ->
              Buffer.add_char buf c;
              incr i)
      | _ ->
          Buffer.add_char buf c;
          incr i)

    else if c = '(' then (
      match parse_sexp_at line !i with
      | List (Atom op :: _) as sexp, next when List.mem op known_inline_ops ->
          Buffer.add_string buf (eval ctx sexp);
          i := next
      | _, _ ->
          Buffer.add_string buf (Util.html_escape "(");
          incr i
      | exception Parse_error _ ->
          Buffer.add_string buf (Util.html_escape "(");
          incr i)

    (* code *)
    else if c = '`' then (
      match String.index_from_opt line (!i + 1) '`' with
      | Some close when close > !i + 1 ->
          let inner = String.sub line (!i + 1) (close - !i - 1) in
          Buffer.add_string buf
            (Printf.sprintf "<code>%s</code>" (Util.html_escape inner));
          i := close + 1
      | _ ->
          Buffer.add_string buf (Util.html_escape "`");
          incr i)

    (* bold *)
    else if c = '*' && !i + 1 < len && line.[!i + 1] = '*' then (
      match
        let rec find j =
          if j + 1 >= len then None
          else if line.[j] = '*' && line.[j + 1] = '*' then Some j
          else find (j + 1)
        in
        find (!i + 2)
      with
      | Some close when close > !i + 2 ->
          let inner = String.sub line (!i + 2) (close - !i - 2) in
          Buffer.add_string buf
            (Printf.sprintf "<strong>%s</strong>" (Util.html_escape inner));
          i := close + 2
      | _ ->
          Buffer.add_string buf (Util.html_escape "**");
          i := !i + 2)

    else (
      Buffer.add_string buf (Util.html_escape (String.make 1 c));
      incr i)
  done;
  Buffer.contents buf

let parse_multiline_sexp (first_line : string) (rest_lines : string list) : sexp * string list =
  let rec loop current_str lines =
    match parse_sexp_at current_str 0 with
    | sexp, _ -> (sexp, lines)
    | exception Parse_error _ ->
        match lines with
        | [] -> (Atom current_str, [])
        | next_line :: remaining ->
            loop (current_str ^ "\n" ^ next_line) remaining
  in
  loop first_line rest_lines

type block = Text of string | Code of string

let split_code_blocks (raw : string) : block list =
  let lines = String.split_on_char '\n' raw in
  let rec aux in_code current_chunk acc = function
    | [] ->
        let content = String.concat "\n" (List.rev current_chunk) in
        let last_block = if in_code then Code content else Text content in
        List.rev (if content = "" then acc else last_block :: acc)
    | line :: rest ->
        let trimmed = String.trim line in
        if String.starts_with ~prefix:"```" trimmed then
          if in_code then
            let code_content = String.concat "\n" (List.rev (line :: current_chunk)) in
            aux false [] (Code code_content :: acc) rest
          else
            let text_content = String.concat "\n" (List.rev current_chunk) in
            let acc = if text_content = "" then acc else Text text_content :: acc in
            aux true [line] acc rest
        else
          aux in_code (line :: current_chunk) acc rest
  in
  aux false [] [] lines

type render_state = {
  buf : Buffer.t;
  mutable in_para : bool;
  mutable list_stack : (int * bool) list;  (* indent, is_ordered *)
  mutable heading_counters : int list;
  mutable toc_index : int;
}

let create_state (capacity : int) : render_state = {
  buf = Buffer.create capacity;
  in_para = false;
  list_stack = [];
  heading_counters = [];
  toc_index = 0;
}

let close_para st =
  if st.in_para then (
    Buffer.add_string st.buf "</p>\n";
    st.in_para <- false)

let open_para st =
  if not st.in_para then (
    Buffer.add_string st.buf "<p>\n";
    st.in_para <- true)

let close_lists_to st target_indent =
  let rec loop = function
    | (top, ordered) :: rest when top > target_indent ->
        let tag = if ordered then "ol" else "ul" in
        Buffer.add_string st.buf (Printf.sprintf "</li>\n</%s>\n" tag);
        st.list_stack <- rest;
        loop rest
    | _ -> ()
  in
  loop st.list_stack

let close_all_lists st = close_lists_to st (-1)

let render_heading st line =
  close_para st;
  close_all_lists st;
  let level =
    let rec count i =
      if i < String.length line && line.[i] = '#'
      then count (i + 1)
      else i
    in
    count 0
  in
  let title = String.trim (String.sub line level (String.length line - level)) in
  st.heading_counters <- Heading.update_counters st.heading_counters level;
  current_heading_counters := st.heading_counters;
  let num_str = Heading.format_counter st.heading_counters in
  let id = Heading.slugify title in
  let idx = st.toc_index in
  st.toc_index <- idx + 1;
  current_toc_index := st.toc_index;
  Printf.bprintf st.buf
    {|<h%d id="%s" style="--is: --h-%d"><a href="#%s">%s %s</a></h%d>|}
    level id idx id num_str (Util.html_escape title) level

let render_list_entry st ctx indent ordered item_text =
  close_para st;
  close_lists_to st indent;
  let tag = if ordered then "ol" else "ul" in
  (match st.list_stack with
  | [] ->
      Buffer.add_string st.buf (Printf.sprintf "<%s>\n<li>" tag);
      st.list_stack <- [(indent, ordered)]
  | (top, _) :: _ when indent > top ->
      Buffer.add_string st.buf (Printf.sprintf "\n<%s>\n<li>" tag);
      st.list_stack <- (indent, ordered) :: st.list_stack
  | (top, _) :: _ when indent = top ->
      Buffer.add_string st.buf "</li>\n<li>"
  | _ ->
      Buffer.add_string st.buf (Printf.sprintf "\n<%s>\n<li>" tag);
      st.list_stack <- (indent, ordered) :: st.list_stack);
  Buffer.add_string st.buf (render_line ctx item_text)

let render_code_block st (code_text : string) =
  close_para st;
  close_all_lists st;
  let lines = String.split_on_char '\n' code_text in
  let inner_lines =
    match lines with
    | first :: rest when String.starts_with ~prefix:"```" (String.trim first) ->
        let rec drop_last = function
          | [] | [_] -> []
          | x :: xs -> x :: drop_last xs
        in
        drop_last rest
    | _ -> lines
  in
  let escaped_code = Util.html_escape (String.concat "\n" inner_lines) in
  Printf.bprintf st.buf "<pre><code>%s</code></pre>\n" escaped_code

let render_text_block st (ctx : context) (text : string) =
  let rec process_lines lines =
    match lines with
    | [] -> ()
    | raw_line :: rest ->
        let line = String.trim raw_line in
        if String.length line > 0 && line.[0] = '(' then (
          close_para st;
          close_all_lists st;
          let sexp, remaining_lines = parse_multiline_sexp raw_line rest in
          Buffer.add_string st.buf (eval ctx sexp);
          Buffer.add_char st.buf '\n';
          process_lines remaining_lines)
        else if Util.starts_with ~prefix:"<svg" line then (
          close_para st;
          close_all_lists st;
          let rec collect_svg acc = function
            | [] ->
                Buffer.add_string st.buf (String.concat "\n" (List.rev acc));
                Buffer.add_char st.buf '\n'
            | l :: more ->
                let acc' = l :: acc in
                if Util.contains_substring (String.trim l) "</svg>" then (
                  Buffer.add_string st.buf (String.concat "\n" (List.rev acc'));
                  Buffer.add_char st.buf '\n';
                  process_lines more)
                else
                  collect_svg acc' more
          in
          collect_svg [raw_line] rest)
        else if Util.starts_with ~prefix:">" line then (
          close_para st;
          close_all_lists st;
          (* group consecutive '>' lines into a single quoted paragraph *)
          let strip_quote_marker l =
            let l = String.trim l in
            let l = Util.drop_prefix ~prefix:">" l in
            Util.drop_prefix ~prefix:" " l
          in
          let is_quote_line l =
            Util.starts_with ~prefix:">" (String.trim l)
          in
          let rec collect acc = function
            | l :: more when is_quote_line l ->
                collect (strip_quote_marker l :: acc) more
            | remaining -> (List.rev acc, remaining)
          in
          let quoted_lines, remaining = collect [strip_quote_marker line] rest in
          let html =
            String.concat "<br>\n" (List.map (render_line ctx) quoted_lines)
          in
          Printf.bprintf st.buf "<blockquote>%s</blockquote>\n" html;
          process_lines remaining)
        else
          match Page.parse_list_item raw_line with
          | Some (indent, kind, item_text) ->
              render_list_entry st ctx indent (kind = Page.Ordered) item_text;
              process_lines rest
          | None ->
              close_all_lists st;
              if line = "" then
                close_para st
              else if Util.starts_with ~prefix:"------" line || line = "---" then (
                close_para st;
                Buffer.add_string st.buf "<hr>\n")
              else if Util.starts_with ~prefix:"#" line then
                render_heading st line
              else (
                open_para st;
                Buffer.add_string st.buf (render_line ctx line);
                Buffer.add_char st.buf '\n');
              process_lines rest
  in
  process_lines (String.split_on_char '\n' text)

let render_body (ctx : context) (raw : string) : string =
  let st = create_state (String.length raw * 2) in
  let blocks = split_code_blocks raw in
  List.iter
    (function
      | Text t -> render_text_block st ctx t
      | Code c -> render_code_block st c)
    blocks;
  close_para st;
  close_all_lists st;
  Buffer.contents st.buf

let heading_to_html (buf : Buffer.t) (ctx : context) (level : int) (line : string) : unit =
  let text = String.trim (Util.drop_prefix ~prefix:(String.make level '#') line) in
  let slug = Util.sanitize text in
  Buffer.add_string buf
    (Printf.sprintf
      {|<h%d id="%s"><a href="#%s">%s</a></h%d>n|}
      level slug slug
      (render_line ctx text)
      level)

let render_html (site_name : string) (ctx : context) (body : string) : string =
  let scope_style =
    match ctx.headings with
    | [] -> ""
    | hs ->
      let names = List.mapi (fun i _ -> Printf.sprintf "--h-%d" i) hs
                  |> String.concat ", " in
      Printf.sprintf " style=\"timeline-scope: %s\"" names
  in
  Printf.sprintf
    {|<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>%s</title>
  <link rel="stylesheet" href="/style.css">
</head>
<body>
  <header>
    <a href="/">%s</a>
    <a href="https://r2wa.rs">r2wa.rs</a>
  </header>
  <nav>%s</nav>
  %s
  <main%s>
%s  </main>
  <footer>
    <br><br><br>
    <a href="https://social.emile.space/@hanemile/feed.rss" target="_blank" rel="noopener" class="icon"><img class="webring" src="/rss.svg" alt="rss" height="32px"/></a>
    <a href="https://lieu.cblgh.org/" target="_blank" rel="noopener" class="icon"><img class="webring" src="/lieu.svg" alt="lieu" height="32px"/></a>
    <a href="https://webring.xxiivv.com/#emile" target="_blank" rel="noopener" class="icon"><img class="webring" src="/webring.svg" alt="XXIIVV" height="32px"/></a>
    <a href="https://social.emile.space/@hanemile" rel="me" target="_blank" class="icon"><img class="webring" src="/activitypub.svg" alt="activitypub" height="32px"/></a>
    <a href="https://emile.space/gnirbew" class="icon"><img class="webring" src="/ring.svg" alt="ring" height="32px"></a>
    <p>%s - generated with vokobe-ml</p>
  </footer>
</body>
</html>
|}
    (Util.html_escape ctx.current.title)
    (Util.html_escape site_name)
    (render_navbar ctx)
    (render_info_bar ctx)
    scope_style
    body
    (Util.html_escape site_name)
