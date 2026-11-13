let is_leap_year y = (y mod 4 = 0 && y mod 100 <> 0) || y mod 400 = 0

let days_in_month y m = match m with
  | 1|3|5|7|8|10|12 -> 31 | 4|6|9|11 -> 30
  | 2 -> if is_leap_year y then 29 else 28 | _ -> 0

let next_day (y, m, d) =
  let d' = d + 1 in
  if d' <= days_in_month y m then (y, m, d')
  else let m' = m + 1 in
    if m' <= 12 then (y, m', 1) else (y + 1, 1, 1)

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

let add_date_range_str (pages : Page.page list) : Page.page list =
  List.map (fun (p : Page.page) ->
    match List.assoc_opt "date-start" p.attrs, List.assoc_opt "date-end" p.attrs with
    | Some (s :: _), Some (e :: _) ->
        let days = enumerate_date_range s e in
        let range_str = String.concat " " days in
        { p with Page.attrs = p.Page.attrs @ [("date-range-str", [range_str])] }
    | _ -> p)
  pages

let collect_all_tags (pages : Page.page list) : string list =
  pages
  |> List.concat_map (fun p ->
         match List.assoc_opt "tag" p.Page.attrs with
         | Some tags -> tags
         | None -> [])
  |> List.sort_uniq String.compare

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

let generate_tag_pages (pages : Page.page list) : Page.page list =
  let tags = collect_all_tags pages in
  let individual = List.filter_map
    (fun tag ->
      if List.exists (fun (p : Page.page) -> p.name = tag) pages then
        None
      else
        Some
          ({
            name = tag;
            title = tag;
            attrs = [
              ("tag", ["tag"]);
            ];
            raw =
              Printf.sprintf
              {|# %s

                (query
                  (where (tag "%s"))
                  (sort "date" desc)
                  (group year "date" desc)
                  (cols ("Title" "title") ("Date" "date"))
                  (format table))|}
                tag tag;
          } : Page.page))
    tags
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
  let city_pages = List.filter_map
    (fun (city, country_opt) ->
      (* country-only locations are handled by the country page *)
      if country_opt = Some city then None
      else
      let slug = Util.sanitize city in
      if slug = "" then None
      else if List.exists (fun (p : Page.page) -> p.name = slug) pages then None
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
                    | Some (r : Roughmap.region) ->
                        lat >= r.south && lat <= r.north && lon >= r.west
                        && lon <= r.east
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
        Some ({
          Page.name = slug;
          title = city;
          attrs;
          raw =
            Printf.sprintf
            {|# %s

%s              (query
                (where (has "location" "%s"))
                (sort "date" desc)
                (cols ("Title" "title") ("Date" "date"))
                (format table))|}
            city map_block escaped;
        } : Page.page))
    locations
  in
  let countries =
    locations
    |> List.filter_map snd
    |> List.sort_uniq String.compare
  in
  let country_pages = List.filter_map
    (fun country ->
      let slug = Util.sanitize country in
      if slug = "" then None
      else if List.exists (fun (p : Page.page) -> p.name = slug) pages then None
      else if List.exists (fun (p : Page.page) -> p.name = slug) city_pages then None
      else
        let escaped = Sexp.escaped_str country in
        (* country map with a marker for every city of the country that
           has known coordinates and lies inside the shown region (e.g.
           Phnom Penh and Siem Reap on the Cambodia map); cities outside
           (islands on a mainland-only map) keep their own local maps *)
        let map_block =
          if Roughmap.country_available map_cache_dir country then
            let markers =
              match Roughmap.country_region_full map_cache_dir country with
              | Some (r : Roughmap.region) ->
                  List.filter_map
                    (fun (city, copt) ->
                      if copt <> Some country then None
                      else
                        match Roughmap.city_coord map_cache_dir city with
                        | Some (lat, lon)
                          when lat >= r.south && lat <= r.north
                               && lon >= r.west && lon <= r.east ->
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
        Some ({
          Page.name = slug;
          title = country;
          attrs = [("tag", ["location"])];
          raw =
            Printf.sprintf
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
            country map_block escaped escaped;
        } : Page.page))
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

let clean_str (s : string) : string =
  let s = String.trim s in
  let len = String.length s in
  if len >= 2 && s.[0] = '"' && s.[len - 1] = '"' then
    String.sub s 1 (len - 2)
  else
    s

let extract_dates_from_page (p : Page.page) : string list =
  let clean_first key =
    match List.assoc_opt key p.attrs with
    | Some (v :: _) -> Some (clean_str v)
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

let generate_date_pages (pages : Page.page list) : Page.page list =
  let date_keys = collect_date_keys pages in
  let individual = List.filter_map
    (fun key ->
      if List.exists (fun (p : Page.page) -> p.name = key) pages then
        (* a real page with this name wins, like in the other generators *)
        None
      else
      let name = key in
      let title = key in
      let raw =
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
          key key key
      in
      Some ({
        name;
        title;
        attrs = [
          ("tag", ["date"]);
          ("published", [key]);
          ("modified", [key]);
        ];
        raw;
      } : Page.page))
    date_keys
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

let days_since_epoch y m d =
  let days = ref 0 in
  for yy = 1970 to y - 1 do
    days := !days + if is_leap_year yy then 366 else 365
  done;
  for mm = 1 to m - 1 do
    days := !days + days_in_month y mm
  done;
  !days + d - 1

(* "2026-11-13" -> "Fri, 13 Nov 2026 00:00:00 +0000" *)
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

(* [text](url) / ![alt](url) -> text, other markdown chars dropped *)
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
   capped at 280 chars, for <description> *)
let excerpt_of_raw (raw : string) : string =
  let n = String.length raw in
  (* skip leading whitespace and balanced (sexp ...) blocks *)
  let pos = ref 0 in
  let rec skip_ws () =
    while !pos < n && (raw.[!pos] = ' ' || raw.[!pos] = '\t' || raw.[!pos] = '\n' || raw.[!pos] = '\r') do
      incr pos
    done
  in
  let rec skip_sexp () =
    skip_ws ();
    if !pos < n && raw.[!pos] = '(' then begin
      let depth = ref 0 in
      while !pos < n && (!depth > 0 || raw.[!pos] = '(') do
        if raw.[!pos] = '(' then incr depth
        else if raw.[!pos] = ')' then decr depth;
        incr pos
      done;
      skip_sexp ()
    end
  in
  skip_sexp ();
  (* drop every remaining (sexp ...) block -- (toc), (query ...), (map ...)
     etc. -- tracking strings so quoted parens don't break the depth count *)
  let prose = Buffer.create (n - !pos) in
  let depth = ref 0 and in_str = ref false and esc = ref false in
  for i = !pos to n - 1 do
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

let rss_xml ~(site_name : string) (pages : Page.page list) : string =
  let base = "https://" ^ site_name in
  let published (p : Page.page) =
    match List.assoc_opt "published" p.Page.attrs with
    | Some (d :: _) -> Some d
    | _ -> None
  in
  let items =
    pages
    |> List.filter (fun (p : Page.page) ->
           (match List.assoc_opt "tag" p.Page.attrs with
            | Some tags -> List.mem "blog" tags
            | None -> false)
           && published p <> None)
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
       (Util.html_escape site_name) base (Util.html_escape site_name));
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
