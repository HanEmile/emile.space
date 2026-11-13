let is_leap_year y = (y mod 4 = 0 && y mod 100 <> 0) || y mod 400 = 0

let days_in_month y m = match m with
  | 1|3|5|7|8|10|12 -> 31 | 4|6|9|11 -> 30
  | 2 -> if is_leap_year y then 29 else 28 | _ -> 0

let next_day (y, m, d) =
  let d' = d + 1 in
  if d' <= days_in_month y m then (y, m, d')
  else let m' = m + 1 in
    if m' <= 12 then (y, m', 1) else (y + 1, 1, 1)

(* O(d); d = days in the range (hard-capped at 1000). *)
let enumerate_date_range (start_str : string) (end_str : string) : string list =
  let parse s = match String.split_on_char '-' (String.trim s) with
    | [y; m; d] -> (try Some (int_of_string y, int_of_string m, int_of_string d) with _ -> None)
    | _ -> None
  in
  match parse start_str, parse end_str with
  | Some s, Some e ->
      if s > e then
        Printf.eprintf
          "[!] date range %s..%s is reversed, no dates generated\n%!" start_str
          end_str;
      let acc = ref [] and cur = ref s and fuel = ref 1000 in
      while !cur <= e && !fuel > 0 do
        let (y, m, d) = !cur in
        acc := Printf.sprintf "%04d-%02d-%02d" y m d :: !acc;
        cur := next_day !cur;
        decr fuel
      done;
      if !fuel = 0 && !cur <= e then
        Printf.eprintf
          "[!] date range %s..%s exceeds 1000 days, truncated\n%!"
          start_str end_str;
      List.rev !acc
  | _ -> []

(* O(n * d): enumerate up to d = 1000 days per ranged page; n = pages.
   The attrs append is another O(a) per page, a = attrs/page. *)
let add_date_range_str (pages : Page.page list) : Page.page list =
  List.map (fun (p : Page.page) ->
    match List.assoc_opt "date-start" p.attrs, List.assoc_opt "date-end" p.attrs with
    | Some (s :: _), Some (e :: _) ->
        let days = enumerate_date_range s e in
        let range_str = String.concat " " days in
        { p with Page.attrs = p.Page.attrs @ [("date-range-str", [range_str])] }
    | _ -> p)
  pages

(* a page's tags, [] when untagged (same accessor as in the renderer) *)
let tags_of_page = Render.tags_of

(* O(T log T); T = total tag occurrences across all pages. *)
let collect_all_tags (pages : Page.page list) : string list =
  pages |> List.concat_map tags_of_page |> List.sort_uniq String.compare

(* the set of page names of a list, for O(1) "name already taken" checks *)
let page_name_set (pages : Page.page list) : (string, unit) Hashtbl.t =
  let t = Hashtbl.create (List.length pages * 2) in
  List.iter (fun (p : Page.page) -> Hashtbl.replace t p.Page.name ()) pages;
  t

(* one generated pseudo-page per key (index pages for tags, dates, ...);
   a real page with the key's name always wins, only attrs/raw differ per
   generator
   Complexity: O(k + n); k = keys, n = base pages - the "real page wins"
   check is a Hashtbl.mem against a name set built once up front. *)
let gen_index_pages base_pages keys attrs_of raw_of : Page.page list =
  let taken = page_name_set base_pages in
  List.filter_map
    (fun key ->
      if Hashtbl.mem taken key then
        None
      else
        Some
          ({
            Page.name = key;
            title = key;
            attrs = attrs_of key;
            raw = raw_of key;
          } : Page.page))
    keys

(* O(n); n = pages (List.exists scan). *)
let make_umbrella_page (attr : string) (pages : Page.page list) : Page.page option =
  if List.exists (fun (p : Page.page) -> p.name = attr) pages then None
  else
    Some ({
      Page.name = attr;
      title = attr;
      attrs = [("tag", ["meta"])];
      raw =
        Printf.sprintf
          {|# %s

          (query
            (where (tag "%s"))
            (sort "title" asc)
            (format list))|}
          attr attr;
    } : Page.page)

(* O(t + n): gen_index_pages over t = distinct tags against n pages. *)
let generate_tag_pages (pages : Page.page list) : Page.page list =
  let individual =
    gen_index_pages pages (collect_all_tags pages)
      (fun _ -> [("tag", ["tag"])])
      (fun tag ->
        Printf.sprintf
        {|# %s

          (query
            (where (tag "%s"))
            (sort "date" desc)
            (group year "date" desc)
            (cols ("Title" "title") ("Date" "date"))
            (format table))|}
          tag tag)
  in
  let umbrella = make_umbrella_page "tag" (pages @ individual) in
  individual @ Option.to_list umbrella

(* small (map ...) snippets for generated location pages *)
let map_marker lat lon label =
  Printf.sprintf "(marker %.5f %.5f \"%s\")" lat lon
    (Sexp.escaped_str label)

let center_map_block lat lon label =
  Printf.sprintf "(map (center %.5f %.5f 40) %s)\n\n" lat lon
    (map_marker lat lon label)

let country_map_block country inner =
  Printf.sprintf "(map (country \"%s\")%s)\n\n" (Sexp.escaped_str country) inner

(* O(n * l_p + n + l + c * l): locations are collected in one pass over
   n pages with l_p locations/page; each of the l distinct locations
   runs safe_page with a Hashtbl.mem name check against sets built once
   (base pages, later plus the city pages), and each of the c countries
   scans all l locations for map markers.  Roughmap geodata lookups are
   memoized O(1)-ish after the first call. *)
let generate_location_pages ~(map_cache_dir : string) (pages : Page.page list)
    : Page.page list =
  let locations =
    pages
    |> List.concat_map (fun (p : Page.page) ->
           let cities    = Option.value ~default:[] (List.assoc_opt "location" p.Page.attrs) in
           let countries = Option.value ~default:[] (List.assoc_opt "country"  p.Page.attrs) in
           List.mapi (fun i city ->
             (city, List.nth_opt countries i))
           cities)
    |> List.sort_uniq compare
  in
  (* a single-value (location "X") naming a known country means "in
     country X", not a city without a country page *)
  let locations =
    List.map
      (fun ((city, country_opt) as loc) ->
        match country_opt with
        | None when Roughmap.country_available map_cache_dir city ->
            (city, Some city)
        | _ -> loc)
      locations
  in
  (* slug-named page for one location string; skipped when the slug is
     empty or the name is already taken (real pages first, then earlier
     generated ones).  Name sets are built once per list; the checks
     themselves are Hashtbl.mem. *)
  let taken = page_name_set pages in
  let no_also = Hashtbl.create 0 in
  let safe_page ~also ~title ~attrs raw : Page.page option =
    let slug = Util.sanitize title in
    if slug = "" then None
    else if Hashtbl.mem taken slug || Hashtbl.mem also slug then None
    else Some ({Page.name = slug; title; attrs; raw} : Page.page)
  in
  let city_pages = List.filter_map
    (fun (city, country_opt) ->
      (* country-only locations are handled by the country page *)
      if country_opt = Some city then None
      else
        let escaped = Sexp.escaped_str city in
        (* Show the country in the info bar; excluded from country listings *)
        let attrs =
          match country_opt with
          | Some country ->
              [("tag", ["city"]); ("country", [country]); ("info", ["country"])]
          | None -> [("tag", ["city"])]
        in
        (* city maps: the country outline with a marker on the city, plus
           a local Overpass map of the city itself when the country map
           is a pure outline (for city-states it already IS the local
           map).  If the city lies outside the country's outline (e.g.
           islands on a mainland-only map), only the local map is used *)
        let map_block =
          match country_opt with
          | Some country when Roughmap.country_available map_cache_dir country ->
            (
              match Roughmap.city_coord map_cache_dir city with
              | Some (lat, lon) ->
                  let in_country =
                    match Roughmap.country_region_full map_cache_dir country with
                    | Some r -> Roughmap.lat_lon_in_region r lat lon
                    | None -> false
                  in
                  if in_country then
                    country_map_block country (" " ^ map_marker lat lon city)
                    ^
                    if Roughmap.country_outline_detailed map_cache_dir country
                    then center_map_block lat lon city
                    else ""
                  else
                    center_map_block lat lon city
              | None -> "")
          | _ -> ""
        in
        safe_page ~also:no_also ~title:city ~attrs
          (Printf.sprintf
          {|# %s

%s              (query
                (where (has "location" "%s"))
                (sort "date" desc)
                (cols ("Title" "title") ("Date" "date"))
                (format table))|}
          city map_block escaped))
    locations
  in
  let countries =
    locations
    |> List.filter_map snd
    |> List.sort_uniq String.compare
  in
  let city_names = page_name_set city_pages in
  let country_pages = List.filter_map
    (fun country ->
        let escaped = Sexp.escaped_str country in
        (* country map with a marker for every city of the country that
           has known coordinates and lies inside the shown region (e.g.
           Phnom Penh and Siem Reap on the Cambodia map); cities outside
           (islands on a mainland-only map) keep their own local maps *)
        let map_block =
          if Roughmap.country_available map_cache_dir country then
            let markers =
              match Roughmap.country_region_full map_cache_dir country with
              | Some r ->
                  List.filter_map
                    (fun (city, copt) ->
                      if copt <> Some country then None
                      else
                        match Roughmap.city_coord map_cache_dir city with
                        | Some (lat, lon)
                          when Roughmap.lat_lon_in_region r lat lon ->
                            Some (map_marker lat lon city)
                        | _ -> None)
                    locations
              | None -> []
            in
            country_map_block country
              (match markers with
               | [] -> ""
               | ms -> " " ^ String.concat " " ms)
          else ""
        in
        safe_page ~also:city_names ~title:country
          ~attrs:[("tag", ["location"])]
          (Printf.sprintf
          {|# %s

%s              (query
                (where
                  (and (or (has "country" "%s")
                           (has "location" "%s"))
                       (not (tag "city"))))
                (sort "location" asc)
                (group field "location" "country")
                (cols ("Title" "title") ("Date" "date"))
                (format table))|}
          country map_block escaped escaped))
    countries
  in
  let all_generated = city_pages @ country_pages in
  let umbrella =
    if List.exists (fun (p : Page.page) -> p.name = "location") (pages @ all_generated) then None
    else begin
      (* world map with a dot for every city that has known coordinates *)
      let world_map_block =
        let markers =
          List.filter_map
            (fun (city, _) ->
              match Roughmap.city_coord map_cache_dir city with
              | Some (lat, lon) ->
                  Some (Printf.sprintf "(marker %.5f %.5f)" lat lon)
              | None -> None)
            locations
        in
        match markers with
        | [] -> ""
        | ms -> Printf.sprintf "(map (world) %s)\n\n" (String.concat " " ms)
      in
      let standalone_cities =
        locations
        |> List.filter_map (fun (city, country_opt) ->
               if country_opt = None then Some city else None)
        |> List.sort_uniq String.compare
      in
      let country_lines =
        List.concat_map (fun country ->
          let country_slug = Util.sanitize country in
          let cities_in_country =
            locations
            |> List.filter_map (fun (city, copt) ->
                   if copt = Some country && city <> country then Some city
                   else None)
            |> List.sort String.compare
          in
          let city_lines = List.map (fun city ->
            let slug = Util.sanitize city in
            Printf.sprintf "  - [%s](/%s)" city slug)
            cities_in_country
          in
          Printf.sprintf "- [%s](/%s)" country country_slug :: city_lines)
          countries
      in
      let standalone_lines = List.map (fun city ->
        let slug = Util.sanitize city in
        Printf.sprintf "- [%s](/%s)" city slug)
        standalone_cities
      in
      let all_lines = country_lines @ standalone_lines in
      let raw = "# location\n\n" ^ world_map_block ^ String.concat "\n" all_lines in
      Some ({
        Page.name = "location";
        title = "location";
        attrs = [("tag", ["meta"])];
        raw;
      } : Page.page)
    end
  in
  let city_umbrella = make_umbrella_page "city" (pages @ all_generated) in
  all_generated @ Option.to_list umbrella @ Option.to_list city_umbrella

(* O(a + d); a = attrs of the page, d = days in its date range (cap
   1000, see enumerate_date_range). *)
let extract_dates_from_page (p : Page.page) : string list =
  let clean_first key =
    match List.assoc_opt key p.attrs with
    | Some (v :: _) -> Some (String.trim v)
    | _ -> None
  in
  (* Effective dates of a page: its (date ...) meta, or (published ...)
     when it has no date yet. "modified" never creates date entries. *)
  match clean_first "date-start", clean_first "date-end" with
  | Some s, Some e -> enumerate_date_range s e
  | Some s, None   -> [s]
  | None,   Some e -> [e]
  | None,   None ->
      (match clean_first "published" with
       | Some d -> [d]
       | None -> [])

(* O(D log D); D = total dates across all pages, each date expanding to
   up to 3 keys (year, year-month, year-month-day). *)
let collect_date_keys (pages : Page.page list) : string list =
  let raw_dates = List.concat_map extract_dates_from_page pages in
  let keys =
    List.concat_map
      (fun d ->
        match String.split_on_char '-' d with
        | [y; m; d_num] -> [y; y ^ "-" ^ m; y ^ "-" ^ m ^ "-" ^ d_num]
        | [y; m] -> [y; y ^ "-" ^ m]
        | [y] -> [y]
        | _ -> [])
      raw_dates
  in
  List.sort_uniq String.compare keys

(* O(D log D + k + n): collect D dates, then gen_index_pages over
   k = distinct date keys against n pages. *)
let generate_date_pages (pages : Page.page list) : Page.page list =
  let individual =
    gen_index_pages pages (collect_date_keys pages)
      (fun key ->
        [("tag", ["date"]); ("published", [key]); ("modified", [key])])
      (fun key ->
        Printf.sprintf
        {|# %s

          (query
            (where
              (and
                (or (contains "date" "%s")
                    (contains "date-range-str" "%s"))
                (not (tag "date"))))
            (sort "date" desc)
            (cols ("Title" "title")
                  ("Date" "date")
                  ("Tags" "tag"))
            (format table))|}
          key key key)
  in
  let umbrella = make_umbrella_page "date" (pages @ individual) in
  individual @ Option.to_list umbrella

(* -- RSS feed ---------------------------------------------------------------

   rss.xml at the site root, mirroring the /blog page: every visible page
   tagged "blog", newest published date first. *)

let rss_day_names = [| "Thu"; "Fri"; "Sat"; "Sun"; "Mon"; "Tue"; "Wed" |]
let rss_month_names =
  [| "Jan"; "Feb"; "Mar"; "Apr"; "May"; "Jun";
     "Jul"; "Aug"; "Sep"; "Oct"; "Nov"; "Dec" |]

(* O(y - 1970 + m) constant-work iterations; effectively constant for
   any realistic date. *)
let days_since_epoch y m d =
  let days = ref 0 in
  for yy = 1970 to y - 1 do
    days := !days + if is_leap_year yy then 366 else 365
  done;
  for mm = 1 to m - 1 do
    days := !days + days_in_month y mm
  done;
  !days + d - 1

(* "2026-11-13" -> "Fri, 13 Nov 2026 00:00:00 +0000"
   Complexity: O(len iso) + days_since_epoch. *)
let rfc822_of_iso (iso : string) : string option =
  match String.split_on_char '-' (String.trim iso) with
  | [y; m; d] -> (
      try
        let y = int_of_string y and m = int_of_string m and d = int_of_string d in
        if m < 1 || m > 12 || d < 1 || y < 1970 then None
        else
          let wd = rss_day_names.(days_since_epoch y m d mod 7) in
          Some
            (Printf.sprintf "%s, %02d %s %04d 00:00:00 +0000" wd d
               rss_month_names.(m - 1) y)
      with _ -> None)
  | _ -> None

(* [text](url) / ![alt](url) -> text, other markdown chars dropped
   Complexity: O(L) expected, L = input length; '['-dense input rescans
   via String.index_from_opt, O(L^2) worst case. *)
let strip_markdown (s : string) : string =
  let n = String.length s in
  let b = Buffer.create n in
  let rec aux i =
    if i >= n then ()
    else
      let i = if s.[i] = '!' && i + 1 < n && s.[i + 1] = '[' then i + 1 else i in
      if s.[i] = '[' then (
        match String.index_from_opt s (i + 1) ']' with
        | Some j when j + 1 < n && s.[j + 1] = '(' ->
            Buffer.add_substring b s (i + 1) (j - i - 1);
            aux (match String.index_from_opt s (j + 2) ')' with
                 | Some k -> k + 1
                 | None -> j + 1)
        | Some j ->
            Buffer.add_substring b s (i + 1) (j - i - 1);
            aux (j + 1)
        | None -> aux (i + 1))
      else (
        (match s.[i] with
         | '`' | '*' | '_' | '#' | '~' -> ()
         | '<' | '>' -> Buffer.add_char b ' '
         | c -> Buffer.add_char b c);
        aux (i + 1))
  in
  aux 0;
  Buffer.contents b

(* first prose paragraph of a page (meta/queries skipped, markup stripped),
   capped at 280 chars, for <description>
   Complexity: O(L); L = raw page length (one sexp-dropping pass plus a
   paragraph split). *)
let excerpt_of_raw (raw : string) : string =
  let n = String.length raw in
  (* drop every (sexp ...) block -- (meta ...), (toc), (query ...),
     (map ...) etc. -- tracking strings so quoted parens don't break the
     depth count; everything at depth 0 is kept as prose *)
  let prose = Buffer.create n in
  let depth = ref 0 and in_str = ref false and esc = ref false in
  for i = 0 to n - 1 do
    let c = raw.[i] in
    if !esc then esc := false
    else if !in_str then (
      if c = '\\' then esc := true else if c = '"' then in_str := false)
    else if c = '"' && !depth > 0 then in_str := true
    else if c = '(' then incr depth
    else if c = ')' then (if !depth > 0 then decr depth)
    else if !depth = 0 then Buffer.add_char prose c
  done;
  let text = Buffer.contents prose in
  let tn = String.length text in
  (* split into paragraphs (blank-line separated), then take the first
     paragraph that has prose text -- headings and tables don't count *)
  let rec paragraphs acc cur p =
    if p > tn then List.rev (cur :: acc)
    else
      let line, next =
        match String.index_from_opt text p '\n' with
        | Some nl -> (String.sub text p (nl - p), nl + 1)
        | None -> (String.sub text p (tn - p), tn + 1)
      in
      if String.trim line = "" then paragraphs (cur :: acc) [] next
      else paragraphs acc (line :: cur) next
  in
  let is_prose line =
    let t = String.trim line in
    t <> "" && t.[0] <> '#' && t.[0] <> '|'
  in
  let rec first_prose = function
    | [] -> []
    | para :: rest ->
        let lines = para |> List.rev |> List.filter is_prose in
        if lines = [] then first_prose rest else lines
  in
  let lines = first_prose (paragraphs [] [] 0) in
  let s = String.concat " " (List.map strip_markdown lines) |> String.trim in
  if String.length s <= 280 then s
  else String.sub s 0 280 ^ "…"

(* O(n * t + b log b + E): filter n pages by tag (t = tags/page), sort
   b = blog posts, then excerpts cost E = total raw length of the
   (at most 25) emitted items. *)
let rss_xml ~(site_name : string) ~(feed_tag : string)
    (pages : Page.page list) : string =
  let base = "https://" ^ site_name in
  let published (p : Page.page) =
    match List.assoc_opt "published" p.Page.attrs with
    | Some (d :: _) -> Some d
    | _ -> None
  in
  let items =
    pages
    |> List.filter (fun (p : Page.page) ->
           List.mem feed_tag (tags_of_page p) && published p <> None)
    |> List.sort (fun a b -> compare (published b) (published a))
  in
  let items =
    let rec take n l =
      if n <= 0 then []
      else match l with [] -> [] | x :: t -> x :: take (n - 1) t
    in
    take 25 items
  in
  let last_build =
    match items with
    | p :: _ -> (
        match published p with Some d -> rfc822_of_iso d | None -> None)
    | [] -> None
  in
  let buf = Buffer.create 4096 in
  Buffer.add_string buf
    {|<?xml version="1.0" encoding="UTF-8"?>
<rss version="2.0">
<channel>
|};
  Buffer.add_string buf
    (Printf.sprintf {|<title>%s</title>
<link>%s/</link>
<description>Recent posts on %s</description>
<language>en</language>
|}
       (Util.html_escape
          (if feed_tag = "blog" then site_name
           else site_name ^ " — " ^ feed_tag))
       base
       (Util.html_escape
          (if feed_tag = "blog" then site_name
           else site_name ^ " — pages tagged " ^ feed_tag)));
  (match last_build with
   | Some d -> Buffer.add_string buf ("<lastBuildDate>" ^ d ^ "</lastBuildDate>\n")
   | None -> ());
  List.iter
    (fun (p : Page.page) ->
      let link = Printf.sprintf "%s/%s" base p.Page.name in
      Buffer.add_string buf "<item>\n";
      Buffer.add_string buf
        ("<title>" ^ Util.html_escape p.Page.title ^ "</title>\n");
      Buffer.add_string buf ("<link>" ^ link ^ "</link>\n");
      Buffer.add_string buf
        ("<guid isPermaLink=\"true\">" ^ link ^ "</guid>\n");
      (match published p with
       | Some d -> (
           match rfc822_of_iso d with
           | Some rfc -> Buffer.add_string buf ("<pubDate>" ^ rfc ^ "</pubDate>\n")
           | None -> ())
       | None -> ());
      let excerpt = excerpt_of_raw p.Page.raw in
      if excerpt <> "" then
        Buffer.add_string buf
          ("<description>" ^ Util.html_escape excerpt ^ "</description>\n");
      Buffer.add_string buf "</item>\n")
    items;
  Buffer.add_string buf "</channel>\n</rss>\n";
  Buffer.contents buf

(* ---------------------------------------------------------------------------
   on this day / now: cross-date views over the event date ranges *)

(* "YYYY-MM-DD" -> (year, month, day) when well-formed *)
let split_iso (s : string) =
  match String.split_on_char '-' s with
  | [y; m; d] -> (
      try Some (int_of_string y, int_of_string m, int_of_string d)
      with _ -> None)
  | _ -> None

(* every (month-day, page) pair covered by pages' date ranges
   (date-range-str is precomputed by add_date_range_str) *)
let month_day_events (pages : Page.page list) : (string * Page.page) list =
  pages
  |> List.concat_map (fun (p : Page.page) ->
         match List.assoc_opt "date-range-str" p.Page.attrs with
         | Some (s :: _) ->
             s |> String.split_on_char ' '
             |> List.filter_map (fun d ->
                    match split_iso d with
                    | Some (_, m, day) ->
                        Some (Printf.sprintf "%02d-%02d" m day, p)
                    | None -> None)
         | _ -> [])

let month_names_full =
  [| "January"; "February"; "March"; "April"; "May"; "June"; "July";
     "August"; "September"; "October"; "November"; "December" |]

(* /on-this-day: one section per month-day that has any dated event *)
let generate_on_this_day (pages : Page.page list) : Page.page option =
  if List.exists (fun (p : Page.page) -> p.Page.name = "on-this-day") pages
  then None
  else
    let events = month_day_events pages in
    if events = [] then None
    else
      let tbl = Hashtbl.create 64 in
      List.iter
        (fun (md, p) ->
          let prev =
            match Hashtbl.find_opt tbl md with Some l -> l | None -> []
          in
          Hashtbl.replace tbl md (p :: prev))
        events;
      let days = Hashtbl.fold (fun k _ acc -> k :: acc) tbl [] in
      let days = List.sort compare days in
      let buf = Buffer.create 4096 in
      Buffer.add_string buf
        "# on this day\n\neverything that happened on a given day of the \
         year, across all years.\n\n(toc)\n";
      (* months as headings, days as subheadings *)
      let current_month = ref 0 in
      List.iter
        (fun md ->
          let m, d =
            (int_of_string (String.sub md 0 2), int_of_string (String.sub md 3 2))
          in
          if m <> !current_month then begin
            current_month := m;
            Buffer.add_string buf
              (Printf.sprintf "\n## %s\n" month_names_full.(m - 1))
          end;
          Buffer.add_string buf
            (Printf.sprintf "\n### %s %d\n\n" month_names_full.(m - 1) d);
          let ps = Hashtbl.find tbl md in
          (* dedupe multi-day events appearing in several days of the
             range; order newest first *)
          let seen = Hashtbl.create 8 in
          List.iter
            (fun (p : Page.page) ->
              if not (Hashtbl.mem seen p.Page.name) then begin
                Hashtbl.replace seen p.Page.name ();
                Buffer.add_string buf
                  (Printf.sprintf "- [%s](/%s)\n"
                     (Sexp.escaped_str p.Page.title) p.Page.name)
              end)
            ps)
        days;
      Some
        ({
           Page.name = "on-this-day";
           title = "on this day";
           attrs = [ ("tag", [ "meta" ]) ];
           raw = Buffer.contents buf;
         } : Page.page)

(* /now: what am I doing TODAY, derived from event date ranges *)
let generate_now_page ~(today : string) (pages : Page.page list)
    : Page.page option =
  let range_of (p : Page.page) =
    match
      ( List.assoc_opt "date-start" p.Page.attrs,
        List.assoc_opt "date-end" p.Page.attrs )
    with
    | Some (s :: _), Some (e :: _) -> Some (s, e)
    | _ -> None
  in
  let dated =
    List.filter_map
      (fun (p : Page.page) ->
        match range_of p with
        | Some (s, e) when s <= e -> Some (p, s, e)
        | _ -> None)
      pages
  in
  let loc (p : Page.page) =
    match List.assoc_opt "location" p.Page.attrs with
    | Some (l :: _) -> l
    | _ -> "somewhere"
  in
  let fmt (p : Page.page) s e =
    if s = e then
      Printf.sprintf "today is [%s](/%s), in %s.\n" p.Page.title
        p.Page.name (loc p)
    else
      Printf.sprintf "until %s: [%s](/%s), in %s.\n" e p.Page.title
        p.Page.name (loc p)
  in
  let body =
    (* current first (latest start), else the most recently ended past
       event, else the nearest upcoming one *)
    match
      List.filter (fun (_, s, e) -> s <= today && today <= e) dated
      |> List.sort (fun (_, s1, _) (_, s2, _) -> compare s2 s1)
    with
    | (p, s, e) :: _ -> "right now:\n\n" ^ fmt p s e
    | [] -> (
        let past =
          List.filter (fun (_, _, e) -> e <= today) dated
          |> List.sort (fun (_, _, e1) (_, _, e2) -> compare e2 e1)
        and future =
          List.filter (fun (_, s, _) -> s > today) dated
          |> List.sort (fun (_, s1, _) (_, s2, _) -> compare s1 s2)
        in
        match past with
        | (p, _, e) :: _ ->
            Printf.sprintf
              "as of my last update, I was at [%s](/%s) (ended %s).%s\n"
              p.Page.title p.Page.name e
              (match future with
               | (f, s, _) :: _ ->
                   Printf.sprintf " Upcoming: [%s](/%s) starting %s."
                     f.Page.title f.Page.name s
               | [] -> "")
        | [] -> (
            match future with
            | (f, s, _) :: _ ->
                Printf.sprintf "upcoming: [%s](/%s) starting %s, in %s.\n"
                  f.Page.title f.Page.name s (loc f)
            | [] -> ""))
  in
  if body = "" || List.exists (fun (p : Page.page) -> p.Page.name = "now") pages
  then None
  else
    Some
      ({
         Page.name = "now";
         title = "now";
         attrs = [ ("tag", [ "meta" ]) ];
         raw = "# now\n\n" ^ body;
       } : Page.page)

(* ---------------------------------------------------------------------------
   static search: one precomputed result page per frequent token
   (no javascript anywhere; works on file:// and site mirrors) *)

let search_word_max_pages = 25
let search_min_occurrences = 3

(* index tokens of length 3..8 ([a-z0-9]+, lowercased) per page *)
let tokenize (raw : string) : (string, int) Hashtbl.t =
  let counts = Hashtbl.create 256 in
  let n = String.length raw in
  let i = ref 0 in
  while !i < n do
    let is_w c =
      (c >= 'a' && c <= 'z') || (c >= '0' && c <= '9')
      || (c >= 'A' && c <= 'Z')
    in
    if is_w raw.[!i] then begin
      let start = !i in
      while !i < n && is_w raw.[!i] do
        incr i
      done;
      let wlen = !i - start in
      if wlen >= 3 && wlen <= 8 then
        let w = String.lowercase_ascii (String.sub raw start wlen) in
        Hashtbl.replace counts w (1 + Option.value (Hashtbl.find_opt counts w) ~default:0)
    end
    else incr i
  done;
  counts

(* first raw line containing [tok] (case-insensitive), parens replaced so
   snippets can never be parsed as s-expressions, capped at 120 chars.
   Also returns the disambiguation prefix for the text-fragment link:
   the stripped words immediately before the token's first occurrence --
   the browser highlights the snippet's instance, not the page's first. *)
let snippet_of (tok : string) (raw : string) : string * string option =
  let n = String.length raw in
  let tl = String.length tok in
  let contains_at i =
    let rec go j =
      j >= tl
      || (Char.lowercase_ascii raw.[i + j] = tok.[j] && go (j + 1))
    in
    i + tl <= n && go 0
  in
  let clean s =
    s
    |> String.map (fun c -> if c = '(' then '[' else if c = ')' then ']' else c)
    |> strip_markdown |> String.trim
  in
  let rec find_line pos =
    if pos >= n then None
    else
      let stop =
        match String.index_from_opt raw pos '\n' with
        | Some nl -> nl
        | None -> n
      in
      let rec found i =
        if i < stop && contains_at i then Some i
        else if i + 1 < stop then found (i + 1)
        else None
      in
      match found pos with
      | Some i0 -> Some (pos, stop, i0)
      | None -> find_line (stop + 1)
  in
  match find_line 0 with
  | None -> ("", None)
  | Some (pos, stop, i0) ->
      let s =
        clean (String.sub raw pos (min 120 (stop - pos)))
      in
      let s =
        (* drop leftover list markers *)
        if String.starts_with ~prefix:"- " s then
          String.sub s 2 (String.length s - 2)
        else s
      in
      let prefix =
        match clean (String.sub raw pos (i0 - pos)) with
        | "" -> None
        | p ->
            let p =
              (* text fragments allow ~-40 char prefixes; keep the tail,
                 starting on a word boundary *)
              let len = String.length p in
              if len <= 24 then p
              else
                let tail = String.sub p (len - 24) 24 in
                match String.index_opt tail ' ' with
                | Some sp ->
                    String.sub tail (sp + 1) (String.length tail - sp - 1)
                | None -> tail
            in
            if String.trim p = "" then None else Some p
      in
      (s, prefix)

(* percent-encode a text-fragment component (spec: anything but
   alphanumeric is %XX, including '-' and spaces) *)
let frag_encode (s : string) : string =
  let b = Buffer.create (String.length s) in
  String.iter
    (fun c ->
      match c with
      | 'a' .. 'z' | 'A' .. 'Z' | '0' .. '9' -> Buffer.add_char b c
      | c -> Buffer.add_string b (Printf.sprintf "%%%02X" (Char.code c)))
    s;
  Buffer.contents b

(* per token: one "search-TOKEN" page listing the pages it appears on,
   name-match first, then by occurrence count *)
(* index only the input-derived pages (not generated tag/date pages --
   their template raws would pollute the index with query keywords) *)
let generate_search_pages (pages : Page.page list) : Page.page list =
  let per_token : (string, (Page.page * int) list ref) Hashtbl.t =
    Hashtbl.create 4096
  in
  let total_occ : (string, int) Hashtbl.t = Hashtbl.create 4096 in
  List.iter
    (fun (p : Page.page) ->
      let counts = tokenize p.Page.raw in
      Hashtbl.iter
        (fun tok cnt ->
          let entry =
            match Hashtbl.find_opt per_token tok with
            | Some r -> r
            | None ->
                let r = ref [] in
                Hashtbl.replace per_token tok r;
                r
          in
          entry := (p, cnt) :: !entry;
          Hashtbl.replace total_occ tok
            (Option.value (Hashtbl.find_opt total_occ tok) ~default:0 + cnt))
        counts)
    pages;
  Hashtbl.fold
    (fun tok entry acc ->
      let total = Hashtbl.find total_occ tok in
      if total < search_min_occurrences
         || List.exists (fun (p : Page.page) -> p.Page.name = "search-" ^ tok) pages
      then acc
      else
        let rank (p : Page.page) =
          (* exact page-name match, then name prefix, then the rest *)
          if p.Page.name = tok then 0
          else if String.starts_with ~prefix:tok p.Page.name then 1
          else 2
        in
        let ranked =
          List.sort
            (fun (a, ca) (b, cb) ->
              let ra, rb = (rank a, rank b) in
              if ra <> rb then compare ra rb
              else if ca <> cb then compare cb ca
              else compare a.Page.name b.Page.name)
            !entry
        in
        let shown = List.filteri (fun i _ -> i < search_word_max_pages) ranked in
        let buf = Buffer.create 1024 in
        Buffer.add_string buf
          (Printf.sprintf "# search: %s\n\nfound on %d page(s):\n\n"
             tok (List.length ranked));
        (* results via the (table ...) op (raw html in the markdown body
           is escaped); the :~:text= fragment makes browsers highlight
           every occurrence of the term on the target page *)
        Buffer.add_string buf "(table\n  (header \"page\" \"hits\" \"context\")\n";
        List.iter
          (fun (p, cnt) ->
            let snip, prefix = snippet_of tok p.Page.raw in
            (* prefixed directive highlights the snippet's instance; the
               bare-token second directive is the fallback (page's first
               instance) when rendered/raw text disagrees *)
            let frag =
              match prefix with
              | Some pre ->
                  Printf.sprintf "#:~:text=%s-,%s&text=%s" (frag_encode pre)
                    tok tok
              | None -> Printf.sprintf "#:~:text=%s" tok
            in
            Buffer.add_string buf
              (Printf.sprintf "  (row (link \"/%s%s\" \"%s\") \"%d\" \"%s\")\n"
                 p.Page.name frag (Sexp.escaped_str p.Page.title) cnt
                 (Sexp.escaped_str snip)))
          shown;
        Buffer.add_string buf ")\n";
        ({
           Page.name = "search-" ^ tok;
           title = "search: " ^ tok;
           attrs = [ ("tag", [ "search" ]) ];
           raw = Buffer.contents buf;
         } : Page.page)
        :: acc)
    per_token []

(* ---------------------------------------------------------------------------
   /travel: world map with every visited country shaded and every known
   city dotted, plus a year list per country. *)

let generate_travel_page ~(map_cache_dir : string) (pages : Page.page list)
    : Page.page option =
  if List.exists (fun (p : Page.page) -> p.Page.name = "travel") pages
  then None
  else
    let countries =
      pages
      |> List.concat_map (fun (p : Page.page) ->
             match List.assoc_opt "country" p.Page.attrs with
             | Some cs -> cs
             | None ->
                 (* single-value locations naming a country count too *)
                 (match List.assoc_opt "location" p.Page.attrs with
                  | Some [ l ] when Roughmap.country_available map_cache_dir l ->
                      [ l ]
                  | _ -> []))
      |> List.sort_uniq compare
    in
    if countries = [] then None
    else
      (* year(s) of each country's pages *)
      let years_of country =
        pages
        |> List.filter_map (fun (p : Page.page) ->
               let in_country =
                 match List.assoc_opt "country" p.Page.attrs with
                 | Some cs -> List.mem country cs
                 | None ->
                     (match List.assoc_opt "location" p.Page.attrs with
                      | Some [ l ] -> l = country
                      | _ -> false)
               in
               match List.assoc_opt "date-start" p.Page.attrs, in_country with
               | Some (d :: _), true -> Some (String.sub d 0 4)
               | _ -> None)
        |> List.sort_uniq compare
      in
      let fills =
        String.concat " "
          (List.map
             (fun c -> Printf.sprintf "(fill \"%s\")" (Sexp.escaped_str c))
             countries)
      in
      let markers =
        pages
        |> List.concat_map (fun (p : Page.page) ->
               match List.assoc_opt "location" p.Page.attrs with
               | Some (city :: _) -> [ city ]
               | _ -> [])
        |> List.sort_uniq compare
        |> List.filter_map (fun city ->
               match Roughmap.city_coord map_cache_dir city with
               | Some (lat, lon) ->
                   Some (Printf.sprintf "(marker %.5f %.5f)" lat lon)
               | None -> None)
      in
      let sections =
        List.map
          (fun c ->
            let years = String.concat ", " (years_of c) in
            Printf.sprintf "- [%s](/%s)%s\n" (Sexp.escaped_str c)
              (Util.sanitize c)
              (if years = "" then "" else " — " ^ years))
          countries
      in
      Some
        ({
           Page.name = "travel";
           title = "travel";
           attrs = [ ("tag", [ "meta" ]) ];
           raw =
             Printf.sprintf
               "# travel\n\neverywhere I've been: countries shaded, cities \
                dotted.\n\n(map (world) %s %s)\n\n## countries\n\n%s"
               fills (String.concat " " markers) (String.concat "" sections);
         } : Page.page)


(* all feeds: the blog feed plus one per tag that has at least two
   published pages.  Returns (filename, tag, xml) triples. *)
let rss_feeds ~(site_name : string) (pages : Page.page list) :
    (string * string * string) list =
  let tags =
    collect_all_tags pages
    |> List.filter (fun t -> t <> "meta" && t <> "date" && t <> "search")
    |> List.filter (fun t ->
           let n =
             List.length
               (List.filter
                  (fun (p : Page.page) ->
                    List.mem t (tags_of_page p)
                    && List.assoc_opt "published" p.Page.attrs <> None)
                  pages)
           in
           n >= 2 || t = "blog")
  in
  List.map
    (fun t ->
      let file = if t = "blog" then "rss.xml" else "feed-" ^ t ^ ".xml" in
      (file, t, rss_xml ~site_name ~feed_tag:t pages))
    tags
