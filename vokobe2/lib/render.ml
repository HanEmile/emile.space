open Sexp

(* cumulative profiling, printed by bin/main.ml when VOKOBE_PROFILE=1 *)
let prof_time = Util.prof_time

let prof_query_t = ref 0.
let prof_query_n = ref 0
let prof_sxparse_t = ref 0.
let prof_backlinks_t = ref 0.
let prof_navbar_t = ref 0.

(* Mutable per-render heading bookkeeping: numbering counters, TOC index
   and the headings emitted dynamically by (query ... (group tag) ...).
   This is the single source of truth for heading numbering; a fresh
   instance is created for each render pass and threaded through the
   context so the query renderer (which never sees render_state) can
   register its headings too. *)
type heading_state = {
  mutable counters : int list;
  mutable toc_index : int;
  mutable dynamic_headings : Heading.heading list;
}

let new_heading_state () : heading_state =
  { counters = []; toc_index = 0; dynamic_headings = [] }

type page_index = (string, Page.page) Hashtbl.t

(* name -> page, built once per site and shared by all render passes
   (replaces O(n) List.find_opt scans in the render hot path)
   Complexity: O(n); n = pages. *)
let page_index_of (pages : Page.page list) : page_index =
  let t = Hashtbl.create (List.length pages * 2) in
  List.iter (fun (p : Page.page) -> Hashtbl.replace t p.Page.name p) pages;
  t

type context = {
  pages : Page.page list;
  page_index : page_index;
  current : Page.page;
  headings : Heading.heading list;
  hstate : heading_state;
  map_cache_dir : string;
  (* first pass only: skip output-only work (maps, nav, backlinks, toc);
     (query ...) still runs so its dynamic headings are collected *)
  collect_only : bool;
}

let page_link (p : Page.page) : string = "/" ^ p.name

(* first value of an attribute, if present and non-empty
   Complexity: O(a); a = attrs of the page (assoc-list scan). *)
let first_attr (p : Page.page) (key : string) : string option =
  match List.assoc_opt key p.Page.attrs with
  | Some (v :: _) -> Some v
  | _ -> None

(* a page's tags, [] when untagged
   Complexity: O(a); a = attrs of the page. *)
let tags_of (p : Page.page) : string list =
  Option.value ~default:[] (List.assoc_opt "tag" p.Page.attrs)

(* string compare honoring a desc direction flag
   Complexity: O(len of shorter string). *)
let cmp_str ~desc a b =
  let c = String.compare a b in
  if desc then -c else c

(* Group items by key, merging non-adjacent occurrences of the same key.
   Keys keep first-appearance order, items keep their incoming order.
   Complexity: O(i * g) with i = items, g = distinct groups (per item an
   assoc scan plus an acc rebuild); worst case O(i^2) when all keys differ. *)
let group_by_key (key_of : 'a -> string) (items : 'a list) : (string * 'a list) list =
  List.fold_left
    (fun acc x ->
      let k = key_of x in
      if List.mem_assoc k acc then
        List.map (fun (k2, xs) -> if k2 = k then (k2, xs @ [x]) else (k2, xs)) acc
      else acc @ [(k, [x])])
    [] items

(* O(1): Hashtbl lookup. *)
let tag_link (index : page_index) (tag : string) : string =
  match Hashtbl.find_opt index tag with
  | Some target_page -> "/" ^ target_page.name
  | None -> "/" ^ tag

(* Date values are rendered as links into the generated date archive
   (/YYYY, /YYYY-MM, /YYYY-MM-DD).  Only link the parts that actually have
   a page -- e.g. a (modified ...) stamp or a (published ...) date that
   never became a date key must fall back to plain text.
   Complexity: O(len date_str): a constant number of Hashtbl lookups. *)
let format_date_links (index : page_index) (date_str : string) : string =
  let part name label =
    if Hashtbl.mem index name then
      Printf.sprintf {|<a href="/%s" class="local">%s</a>|} name
        (Util.html_escape label)
    else Util.html_escape label
  in
  match String.split_on_char '-' (String.trim date_str) with
  | [year; month; day] ->
      Printf.sprintf "%s-%s-%s" (part year year)
        (part (year ^ "-" ^ month) month)
        (part (year ^ "-" ^ month ^ "-" ^ day) day)
  | [year; month] ->
      Printf.sprintf "%s-%s" (part year year) (part (year ^ "-" ^ month) month)
  | [year] -> part year year
  | _ -> Util.html_escape date_str

(* a value naming a page renders as a local link; anything else as
   plain escaped text
   Complexity: O(len v) for sanitize/escape; the page lookup is O(1). *)
let local_link (ctx : context) (v : string) : string =
  let slug = Util.sanitize v in
  match Hashtbl.find_opt ctx.page_index slug with
  | Some _ ->
      Printf.sprintf {|<a href="/%s" class="local">%s</a>|} slug
        (Util.html_escape v)
  | None -> Util.html_escape v

(* Rendered/HTML value of an attribute, for display (info bar, table
   columns): dates become links, values naming a page become links.
   Complexity: O(a) assoc scans, a = page attrs; the location branch is
   O(l^2) in l = number of cities (List.nth_opt once per index). *)
let get_page_attr (ctx : context) (p : Page.page) (key : string) : string =
  (* single ISO date rendered as archive links *)
  let links d = format_date_links ctx.page_index d in
  (* "start" or "start – end", the end only when it differs *)
  let range start =
    match start with
    | Some d ->
        let start_html = links d in
        (match first_attr p "date-end" with
         | Some e when e <> d -> start_html ^ " – " ^ links e
         | _ -> start_html)
    | None -> ""
  in
  let single key = match first_attr p key with Some d -> links d | None -> "" in
  match key with
  | "title" -> p.title
  | "name" -> p.name
  | "link" -> page_link p
  | "date-range" -> range (first_attr p "date-start")
  | "published" | "modified" -> single key
  | "date" ->
      range
        (match first_attr p "date-start" with
         | Some _ as found -> found
         | None -> (
             match first_attr p "published" with
             | Some _ as found -> found
             | None -> first_attr p "date"))
  | "date-end" -> single "date-end"
  | "tag" | "tags" ->
      tags_of p
      |> List.map (fun t ->
             Printf.sprintf
             {|<a href="%s" class="local">%s</a>|}
             (tag_link ctx.page_index t) (Util.html_escape t))
      |> String.concat ", "
  | "location" ->
      (* Zip cities and countries into "City, Country" pairs, " / " separated *)
      let cities   = Option.value ~default:[] (List.assoc_opt "location" p.attrs) in
      let countries = Option.value ~default:[] (List.assoc_opt "country"  p.attrs) in
      List.mapi (fun i city ->
        let city_html = local_link ctx city in
        match List.nth_opt countries i with
        | Some c -> city_html ^ ", " ^ local_link ctx c
        | None   -> city_html)
        cities
      |> String.concat " / "
  | _ -> (
      match List.assoc_opt key p.attrs with
      | Some vals -> vals |> List.map (local_link ctx) |> String.concat ", "
      | None -> "")

(* Raw (unformatted) value of an attribute, for query filters/sorts:
   attrs lookup, first value; the virtual keys (title/name/link) and the
   "date" fallback chain mirror get_page_attr, but no HTML is produced.
   ISO dates compare correctly as plain strings.
   Complexity: O(a); a = attrs of the page. *)
let get_page_attr_raw (p : Page.page) (key : string) : string =
  let lookup k = Option.value ~default:"" (first_attr p k) in
  match key with
  | "title" -> p.title
  | "name" -> p.name
  | "link" -> p.name
  | "date" ->
      let v = lookup "date-start" in
      if v <> "" then v
      else
        let v = lookup "published" in
        if v <> "" then v
        else lookup "date"
  | "tag" | "tags" -> (
      match List.assoc_opt "tag" p.attrs with
      | Some tags -> String.concat " " tags
      | None -> "")
  | "location" -> (
      match List.assoc_opt "location" p.attrs with
      | Some cities -> String.concat " " cities
      | None -> "")
  | _ -> lookup key

(* O(k * a): get_page_attr per info key; k = info keys, a = page attrs. *)
let render_info_bar (ctx : context) : string =
  let p = ctx.current in
  match List.assoc_opt "info" p.attrs with
  | None | Some [] -> ""
  | Some keys ->
      let items =
        List.filter_map
          (fun key ->
            let val_str = get_page_attr ctx p key in
            if val_str = "" then None
            else
              let index_key = match key with
                | "published" | "modified" | "date-range" -> "date"
                | k -> k
              in
              let key_label =
                match Hashtbl.find_opt ctx.page_index index_key with
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

(* O(t * a) per page: t = nodes in the filter sexp, each leaf an O(a)
   attr lookup; a = attrs of the page. *)
let rec eval_filter (p : Page.page) (sx : sexp) : bool =
  match sx with
  | Atom "true" -> true
  | List [Atom "tag"; Atom t] -> List.mem t (tags_of p)
  | List [Atom "eq"; Atom key; Atom target] ->
      get_page_attr_raw p key = target
  | List [Atom "contains"; Atom key; Atom needle] ->
      Util.contains_substring (get_page_attr_raw p key) needle
  | List [Atom "has"; Atom key; Atom needle] ->
      (match List.assoc_opt key p.attrs with
       | Some vals -> List.mem needle vals
       | None -> false)
  | List (Atom "and" :: rest) ->
      List.for_all (eval_filter p) rest
  | List (Atom "or" :: rest) ->
      List.exists (eval_filter p) rest
  | List [Atom "not"; sub] ->
      not (eval_filter p sub)
  | _ -> false

(* The query engine.  Complexity over n = pages with a = attrs/page:
   filtering O(n * a), sorting O(n log n) comparisons with an O(a) raw
   attr lookup each, each emitted row O(cols * a).  Grouping adds:
   group_by_key/field O(n * g) worst case (g = groups, see group_by_key),
   group-by-tag O(t * n) for t = tag sections (one filter pass per tag)
   plus O(t) dynamic-heading appends.  Output string built in one concat. *)
let render_query_ (ctx : context) (args : sexp list) : string =
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
          group_tag_skip := atoms skips
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

  let matched = List.filter (fun p -> eval_filter p !where_cond) ctx.pages in
  let sorted =
    if !sort_key <> "" then
      List.sort
        (fun a b ->
          cmp_str ~desc:!sort_desc (get_page_attr_raw a !sort_key)
            (get_page_attr_raw b !sort_key))
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
      (* full-width label row separating groups (years, field values) *)
      let group_header ncols label =
        Printf.sprintf {|<tr><td colspan="%d" class="year-group">%s</td></tr>|}
          ncols label
      in
      let header_html =
        "<tr>"
        ^ String.concat ""
            (List.map (fun (label, _) -> Printf.sprintf "<th>%s</th>" (Util.html_escape label)) !cols)
        ^ "</tr>\n"
      in
      let year_of p =
        (* "date" is virtual: same fallback chain as get_page_attr *)
        let lookup key = Option.map String.trim (first_attr p key) in
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
                 let val_str = get_page_attr ctx p field in
                 let cell_content =
                   if field = "title" then
                     Printf.sprintf "<a href=\"%s\">%s</a>" (page_link p) (Util.html_escape p.title)
                   else val_str
                 in
                 Printf.sprintf "<td class=\"col-%s\">%s</td>" field cell_content)
               !cols)
        ^ "</tr>\n"
      in
      let rows_html =
        if !group_by_field <> "" then begin
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
          let joined f p =
            match List.assoc_opt !group_by_field p.Page.attrs with
            | Some vs -> String.concat " / " (List.map f (filter_vals p vs))
            | None -> ""
          in
          let grouped = group_by_key (joined String.trim) sorted in
          List.concat_map
            (fun (_, group_pages) ->
              let label = match group_pages with p :: _ -> joined (local_link ctx) p | [] -> "" in
              group_header ncols label :: List.map make_row group_pages)
            grouped
        end
        else if !group_by_year = "" then List.map make_row sorted
        else begin
          (* Collect rows into (year, pages) groups, then sort groups by year *)
          let grouped = group_by_key year_of sorted in
          let grouped_sorted =
            List.sort (fun (a, _) (b, _) -> cmp_str ~desc:!group_year_desc a b) grouped
          in
          List.concat_map
            (fun (yr, pages) ->
              group_header ncols (format_date_links ctx.page_index yr)
              :: List.map make_row pages)
            grouped_sorted
        end
      in
      if !group_by_tag then begin
        let system_tags = ["date"; "city"; "location"; "country"; "tag"; "meta"] in
        let all_tags =
          sorted |> List.concat_map tags_of |> List.sort_uniq String.compare
        in
        let ordered_tags =
          let all_tags = List.filter (fun t -> not (List.mem t !group_tag_skip)) all_tags in
          let sys = List.filter (fun t -> List.mem t all_tags) system_tags in
          let rest = List.filter (fun t -> not (List.mem t system_tags)) all_tags in
          sys @ rest
        in
        let sections = List.filter_map
          (fun tag ->
            let pages_with_tag =
              List.filter (fun p -> List.mem tag (tags_of p)) sorted
            in
            if pages_with_tag = [] then None
            else Some (tag, pages_with_tag))
          ordered_tags
        in
        String.concat "" (List.map
          (fun (tag, pages_with_tag) ->
            (* heading id uses the single heading-slug function; page links
               (local_link) keep the page-name slug *)
            let slug = Heading.slugify tag in
            ctx.hstate.counters <- Heading.update_counters ctx.hstate.counters 2;
            let num_str = Heading.format_counter ctx.hstate.counters in
            let idx = ctx.hstate.toc_index in
            ctx.hstate.toc_index <- idx + 1;
            ctx.hstate.dynamic_headings <- ctx.hstate.dynamic_headings @ [{
              Heading.level = 2; title = tag; slug;
              number_str = num_str ^ " " ^ tag;
            }];
            Printf.sprintf {|<h2 id="%s" style="--is: --h-%d"><a href="#%s">%s %s</a></h2>%!|}
              slug idx slug num_str (local_link ctx tag)
            ^ "<table>\n"
            ^ String.concat "" (List.map make_row pages_with_tag)
            ^ "</table>\n")
          sections)
      end
      else "<table>\n" ^ header_html ^ String.concat "" rows_html ^ "</table>"

let render_query (ctx : context) (args : sexp list) : string =
  incr prof_query_n;
  prof_time prof_query_t (fun () -> render_query_ ctx args)

(* O(n * a): delegates to one tag-filtered query over all n pages. *)
let render_navbar (ctx : context) : string =
  prof_time prof_navbar_t @@ fun () ->
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

(* O(h); h = headings. *)
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

(* does [text] contain a link reference to /name?  Pages link as
   [label](/name) or bare /name; the character after the match must not
   be a slug char so /name does not count /name-foo as a backlink.
   Complexity: O(L * m) worst case; L = text length, m = name length
   (naive scan with a String.sub compare per position). *)
let references_name (text : string) (name : string) : bool =
  let needle = "/" ^ name in
  let nn = String.length needle and n = String.length text in
  let slug_char c =
    (c >= 'a' && c <= 'z') || (c >= '0' && c <= '9') || c = '-'
  in
  let rec loop i =
    if i + nn > n then false
    else if String.sub text i nn = needle
            && (i + nn = n || not (slug_char text.[i + nn]))
    then true
    else loop (i + 1)
  in
  loop 0

(* O(n * L) per rendered page: references_name-scan over the raw text of
   every page (n = pages, L = raw length).  Rendered once per page, so
   the site-wide backlink cost is O(n^2 * L). *)
let render_backlinks_ (ctx : context) : string =
  let refs =
    List.filter
      (fun p ->
        p.Page.name <> ctx.current.name
        && references_name p.Page.raw ctx.current.name)
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

let render_backlinks (ctx : context) : string =
  prof_time prof_backlinks_t (fun () -> render_backlinks_ ctx)

let known_inline_ops = [
  "nav"; "list-pages"; "toc"; "backlinks"; "site-name";
  "img"; "link"; "table"; "green"; "bold"; "em"; "code"; "quote"; "query"; "meta"; "details";
  "location"; "map"
]

(* S-expression interpreter: O(size of the sexp) plus the cost of each
   operator - query and map dominate (see render_query_/Roughmap.render),
   everything else is linear in its arguments. *)
let rec eval (ctx : context) (sx : sexp) : string =
  match sx with
  | Atom a -> Util.html_escape a
  | List [] -> ""
  | List (Atom op :: args) -> eval_call ctx op args
  | List (head :: _) -> eval ctx head

(* <tag> wrapping space-separated evaluated arguments *)
and wrapped_tag (tag : string) (ctx : context) (args : sexp list) : string =
  "<" ^ tag ^ ">" ^ String.concat " " (List.map (eval ctx) args)
  ^ "</" ^ tag ^ ">"

(* cell-like inline content: atoms render markup, lists evaluate *)
and eval_item (ctx : context) (c : sexp) : string =
  match c with
  | Atom s -> render_line ctx s
  | List _ -> eval ctx c

and eval_call (ctx : context) (op : string) (args : sexp list) : string =
  match (op, args) with
  | "nav", _ ->
      if ctx.collect_only then ""
      else "<nav>" ^ render_navbar ctx ^ "</nav>"

  | "list-pages", Atom substr :: _ ->
      if ctx.collect_only then ""
      else
        render_query ctx [
          List [Atom "where"; List [Atom "contains"; Atom "title"; Atom substr]];
          List [Atom "format"; Atom "list"];
        ]

  | "toc", _ ->
      if ctx.collect_only then ""
      else render_toc (ctx.headings @ ctx.hstate.dynamic_headings)

  | "backlinks", _ ->
      if ctx.collect_only then ""
      else render_backlinks ctx

  | "site-name", _ -> ""

  | "img", Atom url :: rest ->
    let alt = match rest with Atom a :: _ -> a | _ -> "" in
    (* optional width/height at positions 1/2 *)
    let dim_attr name i =
      match List.nth_opt rest i with
      | Some (Atom s) when s <> "" ->
          Printf.sprintf " %s=\"%s\"" name (Util.html_escape s)
      | _ -> ""
    in
    Printf.sprintf "<img src=\"%s\" alt=\"%s\"%s%s>"
      (Util.html_escape url) (Util.html_escape alt)
      (dim_attr "width" 1) (dim_attr "height" 2)

  | "link", Atom target :: rest ->
      let label = match rest with Atom l :: _ -> l | _ -> target in
      Printf.sprintf "<a href=\"/%s.html\">%s</a>"
        (Util.html_escape target) (Util.html_escape label)

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
      let cell_html c = eval_item ctx c in
      (* one <tr> of same-tagged cells *)
      let row_of tag cells =
        "  <tr>" ^ String.concat ""
          (List.map
             (fun c -> Printf.sprintf "<%s>%s</%s>" tag (cell_html c) tag)
             cells)
        ^ "</tr>\n"
      in
      let render_table_row = function
        | List (Atom "header" :: cells) -> row_of "th" cells
        | List (Atom "section" :: Atom label :: _) ->
            Printf.sprintf "  <tr><td colspan=\"%d\" class=\"section\">%s</td></tr>\n"
              ncols (render_line ctx label)
        | List (Atom "row" :: cells) -> row_of "td" cells
        | List cells -> row_of "td" cells
        | _ -> ""
      in
      "<table>\n" ^ String.concat "" (List.map render_table_row rows) ^ "</table>"

  | "green", rest ->
      let content = String.concat "" (List.map (eval_item ctx) rest) in
      "<span class=\"green\">" ^ content ^ "</span>"

  | "details", rest ->
      let content = String.concat " " (List.map (eval_item ctx) rest) in
      "<details><p>" ^ content ^ "</p></details>"

  (* <inline-tag> wrapping space-separated evaluated arguments *)
  | "bold", rest -> wrapped_tag "b" ctx rest
  | "em", rest -> wrapped_tag "em" ctx rest
  | "code", rest -> wrapped_tag "code" ctx rest
  | "quote", rest -> wrapped_tag "blockquote" ctx rest

  | "query", args -> render_query ctx args

  | "map", args ->
      if ctx.collect_only then ""
      else Roughmap.render ctx.map_cache_dir args

  | "meta", _ -> ""

  (* Inline location marker: renders "City, Country" with links to the
     generated index pages; the attrs themselves are picked up by Page.parse_attrs. *)
  | "location", vals ->
      vals |> atoms |> List.map (local_link ctx) |> String.concat ", "

  | _ ->
      let args_str = String.concat " " (List.map (eval ctx) args) in
      "(" ^ Util.html_escape op ^ (if args_str = "" then "" else " " ^ args_str) ^ ")"

(* Inline-markup renderer: O(L) expected, L = line length; worst case
   O(L^2) on lines dense in failed markup candidates (each '[' or '**'
   rescans the rest of the line via String.index_from_opt).  Each '('
   candidate additionally runs parse_sexp_at, O(sexp size). *)
and render_line (ctx : context) (line : string) : string =
  let len = String.length line in
  let buf = Buffer.create len in
  let i = ref 0 in
  (* [inner](url) with the '[' at position b: (inner, url, next offset) *)
  let bracket_markup b =
    match String.index_from_opt line b ']' with
    | Some close_bracket
      when close_bracket + 1 < len && line.[close_bracket + 1] = '(' -> (
        match String.index_from_opt line (close_bracket + 1) ')' with
        | Some close_paren ->
            Some
              ( String.sub line (b + 1) (close_bracket - b - 1),
                String.sub line
                  (close_bracket + 2)
                  (close_paren - close_bracket - 2),
                close_paren + 1 )
        | None -> None)
    | _ -> None
  in
  (* apply a [inner](url) formatter; on any malformation keep the
     current char as literal text *)
  let bracket_markup_or_literal b format =
    match bracket_markup b with
    | Some (inner, url, next) ->
        Buffer.add_string buf
          (Printf.sprintf format (Util.html_escape url)
             (Util.html_escape inner));
        i := next
    | None ->
        Buffer.add_char buf line.[!i];
        incr i
  in
  while !i < len do
    let c = line.[!i] in

    (* images *)
    if c = '!' && !i + 1 < len && line.[!i + 1] = '[' then
      bracket_markup_or_literal (!i + 1) "<img src=\"%s\" alt=\"%s\">"

    (* links *)
    else if c = '[' then
      bracket_markup_or_literal !i "<a href=\"%s\">%s</a>"

    else if c = '(' then (
      match
        prof_time prof_sxparse_t (fun () -> parse_sexp_at line !i)
      with
      | List (Atom op :: _) as sexp, next when List.mem op known_inline_ops ->
          Buffer.add_string buf (eval ctx sexp);
          i := next
      | _, _ | exception Parse_error _ ->
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

(* Returns [None] when no balanced s-expression can be read even by
   absorbing lines to EOF (unbalanced '('); the caller must then render
   the lines as regular text instead of one giant escaped blob.
   Complexity: O(s) when the sexp parses immediately; O(s^2) worst case
   when it never balances - each retry re-parses the accumulated string
   (s = total chars absorbed). *)
let parse_multiline_sexp (first_line : string) (rest_lines : string list)
    : sexp option * string list =
  let rec loop current_str lines =
    match parse_sexp_at current_str 0 with
    | sexp, _ -> (Some sexp, lines)
    | exception Parse_error _ ->
        (match lines with
         | [] -> (None, [])
         | next_line :: remaining ->
             loop (current_str ^ "\n" ^ next_line) remaining)
  in
  match loop first_line rest_lines with
  | (None, _) -> (None, rest_lines)
  | parsed -> parsed

type block = Text of string | Code of string

(* O(L); L = raw length (each line contributes to exactly one reopened
   chunk concat). *)
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
}

let create_state (capacity : int) : render_state = {
  buf = Buffer.create capacity;
  in_para = false;
  list_stack = [];
}

let close_para st =
  if st.in_para then (
    Buffer.add_string st.buf "</p>\n";
    st.in_para <- false)

let open_para st =
  if not st.in_para then (
    Buffer.add_string st.buf "<p>\n";
    st.in_para <- true)

(* O(d); d = nesting depth of open lists above target_indent. *)
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

(* entering any block-level element ends the current paragraph and lists *)
let close_block st =
  close_para st;
  close_all_lists st

(* Renders a heading already validated by Heading.parse_heading, so the
   body and the TOC (Heading.collect_headings) agree on what counts as a
   heading.  Numbering/toc-index are threaded through ctx.hstate, shared
   with the dynamic (group tag) headings emitted by queries.
   Complexity: O(level + len title + d), d = open list depth. *)
let render_heading st (ctx : context) level title =
  close_block st;
  ctx.hstate.counters <- Heading.update_counters ctx.hstate.counters level;
  let num_str = Heading.format_counter ctx.hstate.counters in
  let id = Heading.slugify title in
  let idx = ctx.hstate.toc_index in
  ctx.hstate.toc_index <- idx + 1;
  Printf.bprintf st.buf
    {|<h%d id="%s" style="--is: --h-%d"><a href="#%s">%s %s</a></h%d>|}
    level id idx id num_str (Util.html_escape title) level

(* O(d + L); d = closed list depth, L = item text length (render_line). *)
let render_list_entry st ctx indent ordered item_text =
  close_para st;
  close_lists_to st indent;
  let tag = if ordered then "ol" else "ul" in
  (* after close_lists_to no open list is deeper than indent, so a
     non-empty stack with indent <> top means a deeper list opens *)
  (match st.list_stack with
  | [] ->
      Buffer.add_string st.buf (Printf.sprintf "<%s>\n<li>" tag);
      st.list_stack <- [(indent, ordered)]
  | (top, _) :: _ when indent = top ->
      Buffer.add_string st.buf "</li>\n<li>"
  | _ ->
      Buffer.add_string st.buf (Printf.sprintf "\n<%s>\n<li>" tag);
      st.list_stack <- (indent, ordered) :: st.list_stack);
  Buffer.add_string st.buf (render_line ctx item_text)

(* O(L); L = code text length. *)
let render_code_block st (code_text : string) =
  close_block st;
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

(* Block renderer: O(L) over L = block length, plus the cost of every
   evaluated sexp (queries, maps, tables).  A page with an unbalanced
   sexp opener triggers the parse_multiline_sexp fallback per line,
   O(L^2) worst case overall. *)
let render_text_block st (ctx : context) (text : string) =
  let rec process_lines lines =
    (* continued paragraph text (also used by the unbalanced-'(' fallback,
       so we take the current line rather than returning a string) *)
    let para_line line =
      open_para st;
      Buffer.add_string st.buf (render_line ctx line);
      Buffer.add_char st.buf '\n'
    in
    match lines with
    | [] -> ()
    | raw_line :: rest ->
        let line = String.trim raw_line in
        if String.length line > 0 && line.[0] = '(' then (
          match parse_multiline_sexp raw_line rest with
          | Some sexp, remaining_lines ->
              close_block st;
              Buffer.add_string st.buf (eval ctx sexp);
              Buffer.add_char st.buf '\n';
              process_lines remaining_lines
          | None, remaining_lines ->
              (* unbalanced '(': render the line as plain text rather than
                 swallowing the rest of the page into one escaped blob *)
              para_line line;
              process_lines remaining_lines)
        else if Util.starts_with ~prefix:"<svg" line then (
          close_block st;
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
          close_block st;
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
              else (
                match Heading.parse_heading line with
                | Some (level, title) -> render_heading st ctx level title
                | None ->
                    (* includes '#'-lines that are no valid headings (no
                       space after '#', level > 5): plain paragraph text *)
                    para_line line);
              process_lines rest
  in
  process_lines (String.split_on_char '\n' text)

(* O(L) plus per-sexp evaluation costs; L = raw source length. *)
let render_body (ctx : context) (raw : string) : string =
  let st = create_state (String.length raw * 2) in
  let blocks = split_code_blocks raw in
  List.iter
    (function
      | Text t -> render_text_block st ctx t
      | Code c -> render_code_block st c)
    blocks;
  close_block st;
  Buffer.contents st.buf

(* O(h + len body) plus one navbar query O(n * a); h = headings,
   n = pages, a = attrs/page.  Called once per page in the hot path. *)
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
  <link rel="alternate" type="application/rss+xml" title="%s" href="/rss.xml">
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
    (Util.html_escape site_name)
    (render_navbar ctx)
    (render_info_bar ctx)
    scope_style
    body
    (Util.html_escape site_name)
