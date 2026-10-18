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
      let acc = ref [] and cur = ref s and fuel = ref 1000 in
      while !cur <= e && !fuel > 0 do
        let (y, m, d) = !cur in
        acc := Printf.sprintf "%04d-%02d-%02d" y m d :: !acc;
        cur := next_day !cur;
        decr fuel
      done;
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

let generate_value_pages (attr : string) (pages : Page.page list) : Page.page list =
  let values =
    pages
    |> List.concat_map (fun (p : Page.page) ->
           match List.assoc_opt attr p.Page.attrs with
           | Some vals -> vals
           | None -> [])
    |> List.sort_uniq String.compare
  in
  let individual = List.filter_map
    (fun value ->
      let slug = Util.sanitize value in
      if slug = "" then None
      else if List.exists (fun (p : Page.page) -> p.name = slug) pages then None
      else
        let escaped = String.concat "\\\"" (String.split_on_char '"' value) in
        let raw =
          Printf.sprintf
            {|# %s

            (query
              (where (has "%s" "%s"))
              (sort "published" desc)
              (group year "published" desc)
              (cols ("Title" "title") ("Published" "published"))
              (format table))|}
            value attr escaped
        in
        Some ({
          Page.name = slug;
          title = value;
          attrs = [("tag", [attr])];
          raw;
        } : Page.page))
    values
  in
  let umbrella = make_umbrella_page attr (pages @ individual) in
  individual @ Option.to_list umbrella

let generate_location_pages (pages : Page.page list) : Page.page list =
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
  let city_pages = List.filter_map
    (fun (city, country_opt) ->
      let slug = Util.sanitize city in
      if slug = "" then None
      else if List.exists (fun (p : Page.page) -> p.name = slug) pages then None
      else
        let escaped = String.concat "\\\"" (String.split_on_char '"' city) in
        (* Show the country in the info bar; excluded from country listings *)
        let attrs =
          match country_opt with
          | Some country ->
              [("tag", ["city"]); ("country", [country]); ("info", ["country"])]
          | None -> [("tag", ["city"])]
        in
        Some ({
          Page.name = slug;
          title = city;
          attrs;
          raw =
            Printf.sprintf
            {|# %s

              (query
                (where (has "location" "%s"))
                (sort "date" desc)
                (cols ("Title" "title") ("Date" "date"))
                (format table))|}
            city escaped;
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
        let escaped = String.concat "\\\"" (String.split_on_char '"' country) in
        Some ({
          Page.name = slug;
          title = country;
          attrs = [("tag", ["location"])];
          raw =
            Printf.sprintf
            {|# %s

              (query
                (where
                  (and (has "country" "%s")
                       (not (tag "city"))))
                (sort "location" asc)
                (group field "location" "country")
                (cols ("Title" "title") ("Date" "date"))
                (format table))|}
            country escaped;
        } : Page.page))
    countries
  in
  let all_generated = city_pages @ country_pages in
  let umbrella =
    if List.exists (fun (p : Page.page) -> p.name = "location") (pages @ all_generated) then None
    else begin
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
                   if copt = Some country then Some city else None)
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
      let raw = "# location\n\n" ^ String.concat "\n" all_lines in
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
  let individual = List.map
    (fun key ->
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
      ({
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
