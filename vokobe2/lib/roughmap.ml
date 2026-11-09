(* Rough outline maps from OpenStreetMap data.

   (map (center LAT LON WIDTH_KM)
        (aspect 16:9)                ; optional: width:height (default 3:1)
        (scale 0.5)                  ; optional: width factor, 1 = full width
        (marker LAT LON "optional label")
        ...)

   Geometry is fetched from the Overpass API on first use and cached as raw
   JSON in a cache directory (one file per bounding box), so all later builds
   are fully local and reproducible. Rendered as inline SVG. *)

open Sexp

(* set by bin/main.ml via --offline: never touch the network *)
let offline = ref false

let set_offline v = offline := v

(* set by bin/main.ml via --dump-missing-queries: instead of fetching a
   missing region, write its Overpass query to <cachefile>.query so a
   parallel fetcher (fetch-map-cache.sh, possibly on another host) can
   download all of them at once *)
let dump_queries = ref false

let set_dump_queries v = dump_queries := v

(* regions fetched during this build (for the build summary) *)
let fetched = ref 0

(* Public Overpass instances are flaky: try them in order until one works. *)
let overpass_endpoints =
  [
    "https://overpass-api.de/api/interpreter";
    "https://overpass.private.coffee/api/interpreter";
    "https://overpass.nchc.org.tw/api/interpreter";
    "https://overpass.openstreetmap.ru/api/interpreter";
  ]

(* -- S-expression interface ------------------------------------------ *)

type region = { south : float; west : float; north : float; east : float }

type geom = (float * float) list (* (lon, lat) points *)

type marker = { mlat : float; mlon : float; mlabel : string option }

type spec =
  { region : region option
  ; markers : marker list
  ; scale : float
  ; aspect : float option
  ; country : string option
  }

(* region for (center LAT LON WIDTH_KM) specs *)
let region_of_center ~aspect lat lon w_km : (region, string) result =
  if w_km <= 0. || Float.abs lat > 90. || Float.abs lon > 180. then
    Error "center: bad LAT LON or non-positive WIDTH_KM"
  else
    let cos_lat = Float.cos (lat *. Float.pi /. 180.) in
    if cos_lat < 1e-6 then Error "center: latitude too close to a pole"
    else
      (* spans are symmetric; (aspect W:H) sets the vertical span so the
         rendered map is exactly W:H; the default is a 3:1 banner *)
      let a = Option.value ~default:3. aspect in
      let half_lat = w_km /. (2. *. 111.320 *. a) in
      let half_lon = w_km /. 2. /. (111.320 *. cos_lat) in
      Ok
        {
          south = lat -. half_lat;
          north = lat +. half_lat;
          west = lon -. half_lon;
          east = lon +. half_lon;
        }

(* w/h of the region as rendered (after the cos(lat) correction) *)
let natural_aspect (r : region) : float =
  let clat = (r.south +. r.north) /. 2. in
  let kx = Float.cos (clat *. Float.pi /. 180.) in
  ((r.east -. r.west) *. kx) /. Float.max 1e-9 (r.north -. r.south)

(* Display height (in ex) of a tall map of the given w/h aspect.  Tall
   maps are capped by area (60ex * 40ex, i.e. the footprint of a narrow
   60ex-tall map) rather than height alone, so squarish maps (Spain)
   don't dominate the page while narrow ones (UK) still get 60ex. *)
let tall_area_cap = 60. *. 40.

let tall_height_ex aspect =
  Float.min 60. (Float.sqrt (tall_area_cap /. Float.max 1e-6 aspect))

(* pad a region (symmetrically) so the rendered map has aspect w/h = a *)
let pad_to_aspect a (r : region) : region =
  let clat = (r.south +. r.north) /. 2. in
  let kx = Float.cos (clat *. Float.pi /. 180.) in
  let w_units = (r.east -. r.west) *. kx in
  let h_units = Float.max 1e-9 (r.north -. r.south) in
  let cur = w_units /. h_units in
  if cur < a then
    let add = ((a *. h_units) -. w_units) /. kx in
    { r with west = r.west -. (add /. 2.); east = r.east +. (add /. 2.) }
  else
    let add = (w_units /. a) -. h_units in
    { r with south = r.south -. (add /. 2.); north = r.north +. (add /. 2.) }

let float_of_atom = function
  | Atom a -> (try Some (float_of_string a) with _ -> None)
  | List _ -> None

let parse_spec (args : sexp list) : (spec, string) result =
  let center = ref None in
  let country = ref None in
  let aspect = ref None in (* width / height of the rendered map *)
  let scale = ref 1. in
  let markers = ref [] in
  let error = ref None in
  List.iter
    (function
      | List [ Atom "center"; clat; clon; cwidth ] -> (
          match
            ( float_of_atom clat,
              float_of_atom clon,
              float_of_atom cwidth )
          with
          | Some lat, Some lon, Some w_km -> center := Some (lat, lon, w_km)
          | _ -> error := Some "center needs numeric LAT LON WIDTH_KM")
      | List [ Atom "country"; Atom name ] -> country := Some name
      | List (Atom "country" :: _) ->
          error := Some "country needs a single name"
      | List [ Atom "aspect"; Atom a ] -> (
          let parts = String.split_on_char ':' a in
          let parsed =
            List.map
              (fun p -> try Some (float_of_string p) with _ -> None)
              parts
          in
          match parsed with
          | [ Some aw; Some ah ] when aw > 0. && ah > 0. ->
              aspect := Some (aw /. ah)
          | _ -> error := Some "aspect needs W:H (e.g. 16:9)")
      | List [ Atom "scale"; s ] -> (
          match float_of_atom s with
          | Some s when s > 0. && s <= 10. -> scale := s
          | _ -> error := Some "scale needs a positive factor (at most 10)")
      | List [ Atom "region"; _; _; _; _ ] ->
          error := Some "use (center LAT LON WIDTH_KM) instead of region"
      | List (Atom "marker" :: lat :: lon :: label_sx) -> (
          match (float_of_atom lat, float_of_atom lon) with
          | Some mlat, Some mlon ->
              let mlabel =
                match label_sx with
                | [ Atom l ] -> Some l
                | _ -> None
              in
              markers := { mlat; mlon; mlabel } :: !markers
          | _ -> error := Some "marker needs numeric lat/lon")
      | List (Atom "marker" :: _) ->
          error := Some "marker needs at least lat and lon"
      | List (Atom other :: _) ->
          error := Some ("unknown map directive: " ^ other)
      | _ -> ())
    args;
  match !error with
  | Some e -> Error e
  | None -> (
      match (!center, !country) with
      | Some _, Some _ -> Error "country and center are mutually exclusive"
      | None, None ->
          Error "map is missing a (center LAT LON WIDTH_KM) or (country NAME) \
                 directive"
      | Some (lat, lon, w_km), None -> (
          match region_of_center ~aspect:!aspect lat lon w_km with
          | Error e -> Error e
          | Ok region ->
              Ok
                {
                  region = Some region;
                  markers = List.rev !markers;
                  scale = !scale;
                  aspect = !aspect;
                  country = None;
                })
      | None, Some name ->
          Ok
            {
              region = None;
              markers = List.rev !markers;
              scale = !scale;
              aspect = !aspect;
              country = Some name;
            })

(* -- precomputed geodata (no network) ------------------------------------
   map-cache/country-outlines.json: simplified outlines of all countries
   (Natural Earth 50m), map-cache/places.json: city coordinates, islands
   and other non-country fallbacks, name aliases. Both are regenerated by
   update-map-geodata.py. *)

let json_file_cache : (string, Json.t option) Hashtbl.t = Hashtbl.create 4

let load_json_file path : Json.t option =
  match Hashtbl.find_opt json_file_cache path with
  | Some v -> v
  | None ->
      let v = try Some (Json.parse (Util.read_file path)) with _ -> None in
      Hashtbl.replace json_file_cache path v;
      v

(* (places, outlines) *)
let geodata cache_dir =
  ( load_json_file (Filename.concat cache_dir "places.json"),
    load_json_file (Filename.concat cache_dir "country-outlines.json") )

let places_alias (places : Json.t option) name : string =
  match places with
  | Some p -> (
      match Json.member "aliases" p with
      | Some aliases -> (
          match Json.member name aliases with
          | Some (Json.Str s) -> s
          | _ -> name)
      | None -> name)
  | None -> name

let geom_of_rings (el : Json.t) : geom list =
  match Json.as_list el with
  | None -> []
  | Some rings ->
      List.filter_map
        (fun ring ->
          match Json.as_list ring with
          | Some pts ->
              let g =
                List.filter_map
                  (fun pt ->
                    match Json.as_list pt with
                    | Some [ Json.Num x; Json.Num y ] -> Some (x, y)
                    | _ -> None)
                  pts
              in
              if List.length g >= 3 then Some g else None
          | None -> None)
        rings

(* outlines with fewer points render as crude polygons (microstates at
   natural-earth 50m: Singapore has 8); those are better served by a
   local Overpass map of the same (padded) bbox *)
let min_outline_points = 50

let outline_detailed (rings : geom list) : bool =
  let npts = List.fold_left (fun acc g -> acc + List.length g) 0 rings in
  npts >= min_outline_points

(* margin around country maps so borders/islands don't sit right on the
   frame edge (fraction of the span, per side) *)
let pad_region frac (r : region) : region =
  let dlat = frac *. (r.north -. r.south)
  and dlon = frac *. (r.east -. r.west) in
  {
    south = Float.max (-90.) (r.south -. dlat);
    west = Float.max (-180.) (r.west -. dlon);
    north = Float.min 90. (r.north +. dlat);
    east = Float.min 180. (r.east +. dlon);
  }

let country_pad = 0.06

(* raw outline rings + region for a country name, regardless of detail *)
let outline_of_name (outlines : Json.t option) name : (region * geom list) option
    =
  match outlines with
  | Some o -> (
      match Json.member name o with
      | Some e -> (
          match
            ( Json.member "bbox" e,
              Option.map geom_of_rings (Json.member "rings" e) )
          with
          | Some (Json.Arr [ Json.Num s; Json.Num w; Json.Num n; Json.Num e' ]),
            Some rings when rings <> [] ->
              Some ({ south = s; west = w; north = n; east = e' }, rings)
          | _ -> None)
      | None -> None)
  | None -> None

(* fallback centre for country-attr values that are not countries
   (islands, city-states too small for Natural Earth 50m) *)
let place_country_center (places : Json.t option) name :
    (float * float * float) option =
  match places with
  | Some p -> (
      match Json.member "countries" p with
      | Some countries -> (
          match Json.member name countries with
          | Some c -> (
              match
                ( Json.get_float "lat" c,
                  Json.get_float "lon" c,
                  Json.get_float "width_km" c )
              with
              | Some lat, Some lon, Some w ->
                  (* clamp: Nominatim bboxes of island city-states (Hong
                     Kong, Singapore) span far more sea than land *)
                  Some (lat, lon, Float.min w 40.)
              | _ -> None)
          | None -> None)
      | None -> None)
  | None -> None

(* used by Generator: does (map (country NAME)) resolve to something? *)
let country_available cache_dir country : bool =
  let places, outlines = geodata cache_dir in
  let cname = places_alias places country in
  outline_of_name outlines cname <> None
  || place_country_center places cname <> None

(* used by Generator: the region a (country NAME) map would show
   (padded, like the render) *)
let country_region cache_dir country : region option =
  let places, outlines = geodata cache_dir in
  let cname = places_alias places country in
  match outline_of_name outlines cname with
  | Some (r, _) -> Some (pad_region country_pad r)
  | None -> (
      match place_country_center places cname with
      | Some (lat, lon, w_km) -> (
          match region_of_center ~aspect:None lat lon w_km with
          | Ok r -> Some r
          | Error _ -> None)
      | None -> None)

(* used by Generator: is the country's outline detailed enough that its
   map is a pure outline (vs. already a local Overpass map)?  city pages
   of outlined countries get an additional local map of the city *)
let country_outline_detailed cache_dir country : bool =
  let places, outlines = geodata cache_dir in
  let cname = places_alias places country in
  match outline_of_name outlines cname with
  | Some (_, rings) -> outline_detailed rings
  | None -> false

(* used by Generator: map marker coordinates for a city *)
let city_coord cache_dir city : (float * float) option =
  let places, _ = geodata cache_dir in
  match places with
  | Some p -> (
      match Json.member "cities" p with
      | Some cities -> (
          match Json.member city cities with
          | Some c -> (
              match (Json.get_float "lat" c, Json.get_float "lon" c) with
              | Some lat, Some lon -> Some (lat, lon)
              | _ -> None)
          | None -> None)
      | None -> None)
  | None -> None

(* -- Overpass fetching + caching -------------------------------------- *)

let cache_filename (r : region) : string =
  Printf.sprintf "%.4f_%.4f_%.4f_%.4f.json" r.south r.west r.north r.east

let overpass_query (r : region) : string =
  let bbox = Printf.sprintf "%.6f,%.6f,%.6f,%.6f" r.south r.west r.north r.east in
  (* small regions get streams too; at regional scale they drown the map *)
  let small = (r.north -. r.south) *. (r.east -. r.west) <= 0.01 in
  Printf.sprintf
    {| [out:json][timeout:120];
(
  way["highway"~"^(motorway|motorway_link|trunk|trunk_link|primary|primary_link|secondary)$"](%s);
  way["waterway"~"^(%s)$"](%s);
  way["natural"="water"](%s);
  way["landuse"="reservoir"](%s);
  relation["natural"="water"](%s);
  relation["landuse"="reservoir"](%s);
);
out geom;
|}
    bbox
    (if small then "river|canal|stream" else "river|canal")
    bbox bbox bbox bbox bbox

(* Run curl; returns true on success (file exists and looks like JSON).
   A custom UA is required: some instances reject default client agents. *)
let curl_post (url : string) (query : string) (out_path : string) : bool =
  let query_file, oc = Filename.open_temp_file "overpass-query" ".txt" in
  output_string oc query;
  close_out oc;
  let cmd =
    Printf.sprintf
      "curl -sS --fail --connect-timeout 10 --max-time 90 -A %s -o %s \
       --data-urlencode data@%s %s"
      (Filename.quote "vokobe2 map renderer (https://emile.space)")
      (Filename.quote out_path) (Filename.quote query_file)
      (Filename.quote url)
  in
  let status = Sys.command cmd in
  (try Sys.remove query_file with _ -> ());
  status = 0
  && Sys.file_exists out_path
  &&
  let content =
    try Some (String.trim (Util.read_file out_path))
    with _ -> None
  in
  match content with
  | Some c -> String.length c > 0 && c.[0] = '{'
  | None -> false

let fetch_overpass (query : string) (out_path : string) : bool =
  List.exists
    (fun ep ->
      Printf.printf "[map]   trying %s\n%!" ep;
      curl_post ep query out_path)
    overpass_endpoints

(* Get cached JSON for a region, fetching from Overpass if missing. *)
let load_region_json (cache_dir : string) (r : region) : (string, string) result
    =
  let path = Filename.concat cache_dir (cache_filename r) in
  if Sys.file_exists path then
    try Ok (Util.read_file path)
    with Sys_error e -> Error e
  else if !dump_queries then begin
    Util.ensure_dir cache_dir;
    Util.write_file (path ^ ".query") (overpass_query r);
    Error "not cached (query dumped for parallel fetch)"
  end
  else if !offline then
    Error
      "offline build: not fetching map data (map appears the next time the \
       site is built with internet access)"
  else begin
    Util.ensure_dir cache_dir;
    Printf.printf
      "[map] fetching external data for region %.4f,%.4f - %.4f,%.4f (cached \
       for future builds)\n\
       %!"
      r.south r.west r.north r.east;
    let tmp_path = path ^ ".tmp" in
    if fetch_overpass (overpass_query r) tmp_path then begin
      incr fetched;
      (try
         let minified = Json.minify (Util.read_file tmp_path) in
         Util.write_file path minified;
         Sys.remove tmp_path
       with _ -> (
         try Sys.rename tmp_path path
         with _ -> Util.write_file path (Util.read_file tmp_path)));
      try Ok (Util.read_file path)
      with Sys_error e -> Error e
    end else begin
      (try Sys.remove tmp_path with _ -> ());
      Error
        (Printf.sprintf
           "no cached data for region and Overpass fetch failed (offline?): \
            %s"
           path)
    end
  end

(* -- Geometry extraction ---------------------------------------------- *)

type way = { tags : (string * string) list; geom : geom }

type feature =
  | Water_fill of geom list (* one or more rings *)
  | Water_line of geom
  | Road of string * geom (* highway class, geometry *)
  | Outline of geom (* country border ring *)

let tags_of (el : Json.t) : (string * string) list =
  match Json.member "tags" el with
  | Some (Json.Obj kvs) ->
      List.filter_map (fun (k, v) ->
          match Json.as_string v with Some s -> Some (k, s) | None -> None)
        kvs
  | _ -> []

let geom_of (el : Json.t) : geom option =
  match Json.member "geometry" el with
  | Some (Json.Arr pts) ->
      let g =
        List.filter_map
          (fun p ->
            match (Json.get_float "lon" p, Json.get_float "lat" p) with
            | Some lon, Some lat -> Some (lon, lat)
            | _ -> None)
          pts
      in
      if List.length g >= 2 then Some g else None
  | _ -> None

(* Join relation "outer" member ways into rings by matching endpoints. *)
let assemble_rings (lines : geom list) : geom list =
  let eps = 1e-6 in
  let near (x1, y1) (x2, y2) = Float.abs (x1 -. x2) < eps && Float.abs (y1 -. y2) < eps in
  let rec close_ring acc remaining =
    match acc with
    | [] -> []
    | (first :: _) as ring ->
        let last = List.nth ring (List.length ring - 1) in
        if near first last then [ ring ] @ assemble_all remaining
        else
          let candidate =
            List.find_index
              (fun g ->
                match g with
                | s :: _ ->
                    let e = List.nth g (List.length g - 1) in
                    near last s || near last e || near first s || near first e
                | [] -> false)
              remaining
          in
          (match candidate with
           | None -> [ ring ] @ assemble_all remaining (* unclosed, keep anyway *)
           | Some i ->
               let g = List.nth remaining i in
               let remaining' = List.filteri (fun j _ -> j <> i) remaining in
               let s = List.hd g in
               let e = List.nth g (List.length g - 1) in
               let ring' =
                 if near last s then ring @ g
                 else if near last e then ring @ List.rev g
                 else if near first s then List.rev g @ ring
                 else g @ ring
               in
               close_ring ring' remaining')
  and assemble_all remaining =
    match remaining with
    | [] -> []
    | g :: rest -> close_ring g rest
  in
  assemble_all lines

let feature_of_element (el : Json.t) : feature list =
  match Json.get_string "type" el with
  | Some "way" -> (
      let tags = tags_of el in
      let tag k = match List.assoc_opt k tags with Some v -> v | None -> "" in
      match geom_of el with
      | None -> []
      | Some geom ->
          let highway = tag "highway" in
          let waterway = tag "waterway" in
          let natural = tag "natural" in
          let landuse = tag "landuse" in
          if highway <> "" then [ Road (highway, geom) ]
          else if waterway <> "" then [ Water_line geom ]
          else if natural = "water" || landuse = "reservoir" then
            [ Water_fill [ geom ] ]
          else [])
  | Some "relation" -> (
      let tags = tags_of el in
      let tag k = match List.assoc_opt k tags with Some v -> v | None -> "" in
      let outer_geoms =
        match Json.member "members" el with
        | Some (Json.Arr ms) ->
            List.filter_map
              (fun m ->
                match
                  (Json.get_string "type" m, Json.get_string "role" m)
                with
                | Some "way", Some "outer" -> geom_of m
                | _ -> None)
              ms
        | _ -> []
      in
      let natural = tag "natural" in
      let landuse = tag "landuse" in
      if (natural = "water" || landuse = "reservoir") && outer_geoms <> [] then
        [ Water_fill (assemble_rings outer_geoms) ]
      else [])
  | _ -> []

(* -- SVG rendering ------------------------------------------------------ *)

let svg_escape = Util.html_escape

(* Projected point, rounded for compact SVG *)
let fmt n = Printf.sprintf "%.0f" n

(* Ramer-Douglas-Peucker polyline simplification on projected px coords. *)
let rdp (eps : float) (pts : (float * float) list) : (float * float) list =
  let arr = Array.of_list pts in
  let n = Array.length arr in
  if n < 3 then pts
  else begin
    let keep = Array.make n false in
    keep.(0) <- true;
    keep.(n - 1) <- true;
    let rec aux i0 i1 =
      let x1, y1 = arr.(i0) in
      let x2, y2 = arr.(i1) in
      let dx = x2 -. x1 and dy = y2 -. y1 in
      let len = Float.sqrt ((dx *. dx) +. (dy *. dy)) in
      let maxd = ref eps and maxi = ref (-1) in
      for i = i0 + 1 to i1 - 1 do
        let x, y = arr.(i) in
        let d =
          if len < 1e-12 then Float.sqrt (((x -. x1) ** 2.) +. ((y -. y1) ** 2.))
          else Float.abs ((dx *. (y1 -. y)) -. ((x1 -. x) *. dy)) /. len
        in
        if d > !maxd then begin
          maxd := d;
          maxi := i
        end
      done;
      if !maxi >= 0 then begin
        keep.(!maxi) <- true;
        aux i0 !maxi;
        aux !maxi i1
      end
    in
    aux 0 (n - 1);
    List.filteri (fun i _ -> keep.(i)) pts
  end

(* -- map frame: tick marks + coordinates ------------------------------- *)

let center_of_region (r : region) : float * float =
  ((r.south +. r.north) /. 2., (r.west +. r.east) /. 2.)

let width_km_of_region (r : region) : float =
  let clat, _ = center_of_region r in
  (r.east -. r.west) *. 111.320 *. Float.cos (clat *. Float.pi /. 180.)

(* OSM zoom level that roughly fits a region of the given width on a
   ~600px wide display *)
let osm_zoom ~lat ~width_km =
  let cos_lat = Float.max 0.01 (Float.cos (lat *. Float.pi /. 180.)) in
  let z = Float.log (40075. *. cos_lat *. 600. /. (256. *. width_km)) /. Float.log 2. in
  max 1 (min 19 (int_of_float (Float.round z)))

(* the largest "nice" tick interval giving at least two ticks *)
let nice_step span =
  let steps =
    [ 30.; 10.; 5.; 2.; 1.; 0.5; 0.2; 0.1; 0.05; 0.02; 0.01; 0.005; 0.002;
      0.001; 0.0005; 0.0002; 0.0001 ]
  in
  match List.find_opt (fun s -> span /. s >= 2.) steps with
  | Some s -> s
  | None -> 0.0001

let decimals_of_step s = int_of_float (Float.ceil (Float.max 0. (-. Float.log10 s)))

(* nice_step-aligned values in [lo, hi] *)
let tick_values step lo hi =
  let rec go v acc = if v > hi +. (step *. 1e-6) then List.rev acc else go (v +. step) (v :: acc) in
  go (Float.of_int (int_of_float (Float.ceil (lo /. step -. 1e-9))) *. step) []

let fmt_coord ?(dec = 5) v pos neg =
  Printf.sprintf "%.*f°%c" dec (Float.abs v) (if v >= 0. then pos else neg)

let features_of_json (json_text : string) : (feature list, string) result =
  match (try Ok (Json.parse json_text) with Json.Error e -> Error e) with
  | Error e -> Error ("failed to parse map data: " ^ e)
  | Ok json ->
      let elements =
        match Json.member "elements" json with
        | Some (Json.Arr els) -> els
        | _ -> []
      in
      Ok (List.concat_map feature_of_element elements)

let render_svg (spec : spec) (r : region) (features : feature list) :
    (string, string) result =
  let markers = spec.markers in
  let clat, _ = center_of_region r in
  let kx = Float.cos (clat *. Float.pi /. 180.) in
  let width = 900. in
  let deg_w = Float.max 1e-9 (r.east -. r.west) in
  let scale = width /. (deg_w *. kx) in
  let height = Float.max 1. ((r.north -. r.south) *. scale) in
  (* Text on the map should match the surrounding body text (1em ≈ 2ex).
     The CSS sizes banners to 100ex wide and caps tall maps to
     tall_height_ex ex high, so we know the SVG-units per displayed ex
     and can size text from it.  The margin estimates below are close
     enough for the displayed scale. *)
  let banner = ((r.east -. r.west) *. kx) /. height >= 2.95 in
  let units_per_ex =
    if banner then (width +. 220.) /. 100.
    else (height +. 60.) /. tall_height_ex (((r.east -. r.west) *. kx) /. height)
  in
  let text_sz = 2. *. units_per_ex in
  (* margins around the map area: room for lat/lon tick labels *)
  let ml = 5.2 *. text_sz and mt = 0.5 *. text_sz in
  let mr = 0.5 *. text_sz and mb = 2.4 *. text_sz in
  let project (lon, lat) =
    ( ml +. ((lon -. r.west) *. kx *. scale),
      mt +. ((r.north -. lat) *. scale) )
  in
  (* simplify after projection: it's a rough map with thick lines *)
  let decimate pts = rdp 1.5 pts in
  (* skip rings too small to see (fountains, tiny ponds) *)
  let big_enough_ring g =
    let xs = List.map (fun p -> fst (project p)) g in
    let ys = List.map (fun p -> snd (project p)) g in
    match xs, ys with
    | [], _ | _, [] -> false
    | x0 :: _, y0 :: _ ->
        let minmax init f l = List.fold_left f init l in
        let min_x = minmax x0 Float.min xs in
        let max_x = minmax x0 Float.max xs in
        let min_y = minmax y0 Float.min ys in
        let max_y = minmax y0 Float.max ys in
        (max_x -. min_x) *. (max_y -. min_y) >= 4.0
  in
  (* road density: dense city maps (Hong Kong, Singapore) need much
     thinner strokes or the roads blob into each other.  ~10k road
     points per map is the point where strokes start overlapping, so
     scale down with 1/sqrt(density) beyond that, floored at 0.3 *)
  let road_points =
    List.fold_left
      (fun acc f ->
        match f with
        | Road (_, g) -> acc + List.length g
        | _ -> acc)
      0 features
  in
  let wscale =
    if road_points <= 10000 then 1.
    else Float.max 0.3 (Float.sqrt (10_000. /. Float.of_int road_points))
  in
  let parts = Buffer.create 4096 in
  (* layer buffers: all geometries of a class share one big <path> *)
  let layer () = Buffer.create 1024 in
  let b_water_fill = layer () in
  let b_river = layer () in
  let b_outline = layer () in (* country borders *)
  let b_road_hw = layer () in (* motorway/trunk *)
  let b_road_p = layer () in (* primary *)
  let b_road_s = layer () in (* secondary *)
  let path_into ?(close = false) buf g =
    match decimate (List.map project g) with
    | [] -> ()
    | (x0, y0) :: rest ->
        Printf.bprintf buf "M%s %s" (fmt x0) (fmt y0);
        List.iter
          (fun (x, y) -> Printf.bprintf buf "L%s %s" (fmt x) (fmt y))
          rest;
        if close then Buffer.add_char buf 'Z'
  in
  let add s = Buffer.add_string parts s in
  List.iter
    (function
      | Water_fill rings ->
          List.iter
            (fun ring ->
              if big_enough_ring ring then
                path_into ~close:true b_water_fill ring)
            rings
      | Water_line g -> path_into b_river g
      | Outline g ->
          if big_enough_ring g then path_into ~close:true b_outline g
      | Road (cls, g) ->
          let buf =
            match cls with
            | "motorway" | "motorway_link" | "trunk" | "trunk_link" ->
                b_road_hw
            | "primary" | "primary_link" -> b_road_p
            | _ -> b_road_s
          in
          path_into buf g)
    features;
  (* minimal + monochrome: everything is currentColor, i.e. it inherits
     the page's text colour and thereby works in light and dark themes *)
  let emit_layer buf style =
    if Buffer.length buf > 0 then
      Printf.bprintf parts "<path d=\"%s\" %s/>\n" (Buffer.contents buf)
        style
  in
  emit_layer b_water_fill
    {|fill="none" stroke="currentColor" stroke-width="2" opacity="0.45"|};
  emit_layer b_outline
    {|fill="none" stroke="currentColor" stroke-width="2.2"|};
  emit_layer b_river
    {|fill="none" stroke="currentColor" stroke-width="3" stroke-linecap="round" opacity="0.6"|};
  emit_layer b_road_hw
    (Printf.sprintf
       {|fill="none" stroke="currentColor" stroke-width="%.1f" stroke-linecap="round"|}
       (7. *. wscale));
  emit_layer b_road_p
    (Printf.sprintf
       {|fill="none" stroke="currentColor" stroke-width="%.1f" stroke-linecap="round"|}
       (5. *. wscale));
  emit_layer b_road_s
    (Printf.sprintf
       {|fill="none" stroke="currentColor" stroke-width="%.1f" stroke-linecap="round" opacity="0.8"|}
       (3. *. wscale));
  (* marker dot + label, same text size as the body; labels that would
     leave the frame are moved to the left of the dot *)
  let marker_r = 0.45 *. text_sz in
  List.iter
    (fun m ->
      let x, y = project (m.mlon, m.mlat) in
      add
        (Printf.sprintf
           "<circle cx=\"%s\" cy=\"%s\" r=\"%s\" fill=\"currentColor\"/>\n"
           (fmt x) (fmt y) (fmt marker_r));
      match m.mlabel with
      | Some label ->
          let label_w =
            0.62 *. text_sz *. Float.of_int (String.length label)
          in
          (* label right of the dot; if that overflows the frame, left of
             it (end-anchored); if that would cross the left frame edge,
             clamp it so the label always stays fully inside *)
          let gap = 0.9 *. text_sz in
          let anchor, tx =
            if x +. gap +. (0.6 *. text_sz) +. label_w <= ml +. width then
              ("", x +. gap)
            else
              let lx = x -. gap in
              if lx -. label_w >= ml then ("text-anchor=\"end\" ", lx)
              else
                ( "text-anchor=\"end\" ",
                  Float.min (ml +. width) (ml +. label_w +. (0.2 *. text_sz)) )
          in
          add
            (Printf.sprintf
               "<text x=\"%s\" y=\"%s\" font-size=\"%s\" %s\
                fill=\"currentColor\">%s</text>\n"
               (fmt tx)
               (fmt (y +. (0.35 *. text_sz)))
               (fmt text_sz) anchor (svg_escape label))
      | None -> ())
    markers;
  (* frame + lat/lon tick marks outside the map area *)
  let frame = Buffer.create 1024 in
  let addf s = Buffer.add_string frame s in
  addf
    (Printf.sprintf
       "<rect x=\"%.0f\" y=\"%.0f\" width=\"%.0f\" height=\"%.0f\" \
        fill=\"none\" stroke=\"currentColor\" stroke-width=\"2\"/>\n"
       ml mt width height);
  (* latitudes on the left, longitudes below *)
  let lat_step = nice_step (r.north -. r.south) in
  let lat_dec = decimals_of_step lat_step in
  List.iter
    (fun lat ->
      let _, y = project (r.west, lat) in
      addf
        (Printf.sprintf
           "<path d=\"M%.0f %.0fL%.0f %.0f\" stroke=\"currentColor\" \
            stroke-width=\"2\"/>\n"
           (ml -. (0.5 *. text_sz)) y ml y);
      addf
        (Printf.sprintf
           "<text x=\"%.0f\" y=\"%.0f\" text-anchor=\"end\" \
            font-size=\"%s\" fill=\"currentColor\">%s</text>\n"
           (ml -. (0.8 *. text_sz))
           (y +. (0.35 *. text_sz))
           (fmt text_sz)
           (fmt_coord ~dec:lat_dec lat 'N' 'S')))
    (tick_values lat_step r.south r.north);
  let lon_step = nice_step (r.east -. r.west) in
  let lon_dec = decimals_of_step lon_step in
  List.iter
    (fun lon ->
      let x, _ = project (lon, r.north) in
      addf
        (Printf.sprintf
           "<path d=\"M%.0f %.0fL%.0f %.0f\" stroke=\"currentColor\" \
            stroke-width=\"2\"/>\n"
           x (mt +. height) x
           (mt +. height +. (0.5 *. text_sz)));
      addf
        (Printf.sprintf
           "<text x=\"%.0f\" y=\"%.0f\" text-anchor=\"middle\" \
            font-size=\"%s\" fill=\"currentColor\">%s</text>\n"
           x
           (mt +. height +. (1.7 *. text_sz))
           (fmt text_sz)
           (fmt_coord ~dec:lon_dec lon 'E' 'W')))
    (tick_values lon_step r.west r.east);
  (* clip id must be unique: a page can contain several maps *)
  let clip_id =
    Printf.sprintf "rm-clip-%08x"
      (Hashtbl.hash (r.south, r.west, r.north, r.east) land 0x7fffffff)
  in
  Ok
    (Printf.sprintf
       "<svg class=\"roughmap\" viewBox=\"0 0 %.0f %.0f\" \
        xmlns=\"http://www.w3.org/2000/svg\" role=\"img\">\n\
        <defs><clipPath id=\"%s\"><rect x=\"%.0f\" y=\"%.0f\" \
        width=\"%.0f\" height=\"%.0f\"/></clipPath></defs>\n\
        <g clip-path=\"url(#%s)\">\n%s</g>\n%s</svg>\n"
       (ml +. width +. mr) (mt +. height +. mb) clip_id ml mt width
       height clip_id (Buffer.contents parts) (Buffer.contents frame))

let render_error (msg : string) : string =
  Printf.eprintf "[map] %s\n%!" msg;
  Printf.sprintf
    "<div class=\"map-error\"><!-- map error: %s -->map unavailable \
    (%s)</div>"
    (svg_escape msg) (svg_escape msg)

let render (cache_dir : string) (args : sexp list) : string =
  let finish spec r features =
    match render_svg spec r features with
    | Error e -> render_error e
    | Ok svg ->
        let clat, clon = center_of_region r in
        let width_km = width_km_of_region r in
        (* deep link to the shown segment; a single marker gets a pin *)
        let pin =
          match spec.markers with
          | [ m ] -> Printf.sprintf "?mlat=%.5f&mlon=%.5f" m.mlat m.mlon
          | _ -> ""
        in
        let osm_url =
          Printf.sprintf "https://www.openstreetmap.org/%s#map=%d/%.5f/%.5f"
            pin (osm_zoom ~lat:clat ~width_km) clat clon
        in
        (* tall maps (clearly taller than the 3:1 banner) are capped by
           area via a per-map CSS variable (see tall_height_ex); 2.95
           instead of 3. avoids float boundary noise *)
        let aspect = natural_aspect r in
        let tall = aspect < 2.95 in
        (* (scale S) sizes the map relative to the full page width (100ex) *)
        let styles =
          (if spec.scale = 1. then []
           else [ Printf.sprintf "max-width:%.0fex" (100. *. spec.scale) ])
          @
          if tall then
            [ Printf.sprintf "--map-h:%.0fex" (tall_height_ex aspect) ]
          else []
        in
        let style =
          match styles with
          | [] -> ""
          | _ -> Printf.sprintf " style=\"%s\"" (String.concat ";" styles)
        in
        let cls = if tall then "roughmap tall" else "roughmap" in
        Printf.sprintf
          "<figure class=\"%s\"%s>\n%s<figcaption>%s, %s — %.1f km — \
           <a href=\"%s\">openstreetmap</a></figcaption>\n</figure>\n"
          cls style svg (fmt_coord clat 'N' 'S') (fmt_coord clon 'E' 'W')
          width_km osm_url
  in
  (* road/water map of a region via cached Overpass data *)
  let via_overpass spec r =
    match load_region_json cache_dir r with
    | Error e -> render_error e
    | Ok json_text -> (
        match features_of_json json_text with
        | Error e -> render_error e
        | Ok features -> finish spec r features)
  in
  match parse_spec args with
  | Error e -> render_error e
  | Ok spec -> (
      match (spec.country, spec.region) with
      | None, Some r -> via_overpass spec r
      | None, None -> render_error "map has neither a center nor a country"
      | Some name, _ -> (
          let places, outlines = geodata cache_dir in
          let cname = places_alias places name in
          match outline_of_name outlines cname with
          | Some (r, rings) when outline_detailed rings ->
              (* explicit aspect wins; otherwise pad wide countries to the
                 3:1 banner but keep portrait countries natural *)
              let r = pad_region country_pad r in
              let r =
                match spec.aspect with
                | Some a -> pad_to_aspect a r
                | None ->
                    if natural_aspect r >= 3. then pad_to_aspect 3. r else r
              in
              finish spec r (List.map (fun g -> Outline g) rings)
          | Some (r, _) ->
              (* outline too coarse to draw (city-states): an Overpass
                 map of its bbox instead; keeps the territory's own
                 extent (Hong Kong incl. Lantau + airport) *)
              let r =
                match spec.aspect with
                | Some a -> pad_to_aspect a (pad_region country_pad r)
                | None -> pad_region country_pad r
              in
              via_overpass spec r
          | None -> (
              (* not in Natural Earth (islands, small city-states):
                 fall back to an Overpass map around its center *)
              match place_country_center places cname with
              | Some (lat, lon, w_km) -> (
                  match region_of_center ~aspect:spec.aspect lat lon w_km with
                  | Error e -> render_error e
                  | Ok r -> via_overpass spec r)
              | None -> render_error ("no geodata for country " ^ name))))
