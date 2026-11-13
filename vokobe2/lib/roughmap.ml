(* Rough outline maps from OpenStreetMap data.

   (map (center LAT LON WIDTH_KM)
        (aspect 16:9)                ; optional: width:height (default 3:1)
        (scale 0.5)                  ; optional: width factor, 1 = full width
        (marker LAT LON "optional label")
        ...)

   (map (world)                     ; all Natural Earth country outlines
        (marker LAT LON "optional label")
        ...)

   Geometry is fetched from the Overpass API on first use and cached as raw
   JSON in a cache directory (one file per bounding box), so all later builds
   are fully local and reproducible. Rendered as inline SVG.

   Complexity notation below: f = map features, p = points of one geometry,
   P = total geometry points, m = markers, B = binary-layer features,
   L = JSON/text length, k = keys of a JSON object. *)

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

(* cumulative profiling (VOKOBE_PROFILE=1) *)
let prof_time = Util.prof_time

let prof_map_t = ref 0.
let prof_map_n = ref 0
let prof_disk_t = ref 0.
let prof_json_t = ref 0.

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
  ; world : bool
  }

(* region for (center LAT LON WIDTH_KM) specs
   Complexity: O(1). *)
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

(* w/h of the region as rendered (after the cos(lat) correction)
   Complexity: O(1). *)
let natural_aspect (r : region) : float =
  let clat = (r.south +. r.north) /. 2. in
  let kx = Float.cos (clat *. Float.pi /. 180.) in
  ((r.east -. r.west) *. kx) /. Float.max 1e-9 (r.north -. r.south)

(* Display height (in ex) of a tall map of the given w/h aspect.  Tall
   maps are capped by area (60ex * 40ex, i.e. the footprint of a narrow
   60ex-tall map) rather than height alone, so squarish maps (Spain)
   don't dominate the page while narrow ones (UK) still get 60ex.
   Complexity: O(1). *)
let tall_area_cap = 60. *. 40.

let tall_height_ex aspect =
  Float.min 60. (Float.sqrt (tall_area_cap /. Float.max 1e-6 aspect))

(* pad a region (symmetrically) so the rendered map has aspect w/h = a
   Complexity: O(1). *)
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

(* O(size of args): one pass over the directives. *)
let parse_spec (args : sexp list) : (spec, string) result =
  let center = ref None in
  let country = ref None in
  let world = ref false in
  let aspect = ref None in (* width / height of the rendered map *)
  let scale = ref 1. in
  let markers = ref [] in
  let error = ref None in
  List.iter
    (function
      | List [ Atom "world" ] -> world := true
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
      let ok ~region ~country ~world =
        Ok
          {
            region;
            markers = List.rev !markers;
            scale = !scale;
            aspect = !aspect;
            country;
            world;
          }
      in
      match (!center, !country, !world) with
      | Some _, _, true | _, Some _, true ->
          Error "world is mutually exclusive with center and country"
      | Some _, Some _, false ->
          Error "country and center are mutually exclusive"
      | None, None, false ->
          Error "map is missing a (center LAT LON WIDTH_KM), (country NAME) \
                 or (world) directive"
      | None, None, true -> ok ~region:None ~country:None ~world:true
      | Some (lat, lon, w_km), None, false -> (
          match region_of_center ~aspect:!aspect lat lon w_km with
          | Error e -> Error e
          | Ok region -> ok ~region:(Some region) ~country:None ~world:false)
      | None, Some name, false ->
          ok ~region:None ~country:(Some name) ~world:false)

(* -- precomputed geodata (no network) ------------------------------------
   map-cache/country-outlines.json: simplified outlines of all countries
   (Natural Earth 50m), map-cache/places.json: city coordinates, islands
   and other non-country fallbacks, name aliases. Both are regenerated by
   update-map-geodata.py. *)

(* memoized lookups: every repeated pipeline stage below (geodata files,
   world bin decode, parsed region features) is one of these
   Complexity: first call per key costs f, later calls O(1) (Hashtbl). *)
let memoize cache key f =
  match Hashtbl.find_opt cache key with
  | Some v -> v
  | None ->
      let v = f () in
      Hashtbl.replace cache key v;
      v

let json_file_cache : (string, Json.t option) Hashtbl.t = Hashtbl.create 4

(* First call per path: O(L) disk read + JSON parse, L = file size;
   memoized afterwards. *)
let load_json_file path : Json.t option =
  memoize json_file_cache path
    (fun () -> try Some (Json.parse (Util.read_file path)) with _ -> None)

(* (places, outlines) *)
let geodata cache_dir =
  ( load_json_file (Filename.concat cache_dir "places.json"),
    load_json_file (Filename.concat cache_dir "country-outlines.json") )

(* step deeper into nested JSON objects (None stays None)
   Complexity: O(k); JSON objects are assoc lists, so each member step is
   a linear scan over the object's k keys. *)
let member_of (j : Json.t option) (key : string) : Json.t option =
  match j with Some t -> Json.member key t | None -> None

(* O(k); k = keys of the outer object plus of the aliases object. *)
let places_alias (places : Json.t option) name : string =
  match member_of (member_of places "aliases") name with
  | Some (Json.Str s) -> s
  | _ -> name

(* O(P): one pass over all rings and their P points. *)
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
   local Overpass map of the same (padded) bbox
   Complexity of outline_detailed below: O(P); P = total ring points. *)
let min_outline_points = 50

let outline_detailed (rings : geom list) : bool =
  let npts = List.fold_left (fun acc g -> acc + List.length g) 0 rings in
  npts >= min_outline_points

(* margin around country maps so borders/islands don't sit right on the
   frame edge (fraction of the span, per side)
   Complexity: O(1). *)
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

(* bbox + ring set under the named fields of one country entry
   Complexity: O(k + P): assoc scan over k top-level keys, then O(P)
   ring decode. *)
let outline_fields_of_name (outlines : Json.t option) name bbox_field
    rings_field : (region * geom list) option =
  match member_of outlines name with
  | Some e -> (
      match
        ( Json.member bbox_field e,
          Option.map geom_of_rings (Json.member rings_field e) )
      with
      | Some (Json.Arr [ Json.Num s; Json.Num w; Json.Num n; Json.Num e' ]),
        Some rings when rings <> [] ->
          Some ({ south = s; west = w; north = n; east = e' }, rings)
      | _ -> None)
  | None -> None

(* raw outline rings + region for a country name, regardless of detail
   Complexity: O(k + P), see outline_fields_of_name. *)
let outline_of_name (outlines : Json.t option) name : (region * geom list) option
    =
  outline_fields_of_name outlines name "bbox" "rings"

(* the unfiltered ring set + bbox of a country (far-away parts like
   Rhodes east of mainland Greece or Alaska), when stored
   Complexity: O(k + P), see outline_fields_of_name. *)
let world_outline_of_name (outlines : Json.t option) name :
    (region * geom list) option =
  outline_fields_of_name outlines name "world_bbox" "world_rings"

(* fallback centre for country-attr values that are not countries
   (islands, city-states too small for Natural Earth 50m)
   Complexity: O(k); k = keys of the country entries object. *)
let place_country_center (places : Json.t option) name :
    (float * float * float) option =
  match member_of (member_of places "countries") name with
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
  | None -> None

(* resolved (places, outlines, aliased name) for the country lookups
   below, all keyed off the same cached geodata
   Complexity: O(1) once the geodata files are memoized (the first call
   pays the O(L) file parse, L = file size). *)
let country_geodata cache_dir country =
  let places, outlines = geodata cache_dir in
  (places, outlines, places_alias places country)

(* used by Generator: does (map (country NAME)) resolve to something?
   Complexity: O(k + P) after memoized geodata. *)
let country_available cache_dir country : bool =
  let places, outlines, cname = country_geodata cache_dir country in
  outline_of_name outlines cname <> None
  || place_country_center places cname <> None

(* used by Generator: the region a (country NAME) map would show
   (padded, like the render)
   Complexity: O(k + P) after memoized geodata. *)
let country_region cache_dir country : region option =
  let places, outlines, cname = country_geodata cache_dir country in
  match outline_of_name outlines cname with
  | Some (r, _) -> Some (pad_region country_pad r)
  | None -> (
      match place_country_center places cname with
      | Some (lat, lon, w_km) -> (
          match region_of_center ~aspect:None lat lon w_km with
          | Ok r -> Some r
          | Error _ -> None)
      | None -> None)

(* used by Generator: the region covering ALL of a country's rings
   (including far-away parts) when stored; else the same as
   country_region
   Complexity: O(k + P) after memoized geodata. *)
let country_region_full cache_dir country : region option =
  let _, outlines, cname = country_geodata cache_dir country in
  match world_outline_of_name outlines cname with
  | Some (r, _) -> Some (pad_region country_pad r)
  | None -> country_region cache_dir country

(* used by Generator: is the country's outline detailed enough that its
   map is a pure outline (vs. already a local Overpass map)?  city pages
   of outlined countries get an additional local map of the city
   Complexity: O(k + P) after memoized geodata. *)
let country_outline_detailed cache_dir country : bool =
  let _, outlines, cname = country_geodata cache_dir country in
  match outline_of_name outlines cname with
  | Some (_, rings) -> outline_detailed rings
  | None -> false

(* used by Generator: map marker coordinates for a city
   Complexity: O(k); k = city entries, after memoized geodata. *)
let city_coord cache_dir city : (float * float) option =
  let places, _ = geodata cache_dir in
  match member_of (member_of places "cities") city with
  | Some c -> (
      match (Json.get_float "lat" c, Json.get_float "lon" c) with
      | Some lat, Some lon -> Some (lat, lon)
      | _ -> None)
  | None -> None

(* -- global base layer (Natural Earth 10m, compact binary) -----------
   map-cache/world-base.bin: all coastlines, rivers, lakes and major
   roads of the planet, varint-delta-encoded at 1e-4 deg quantization
   (see build-world-base.py).  Offline, network-free fallback for
   regions without a richer map-cache/<region>.json. *)

(* two compact global layers: world-rich.bin packs every known region's
   rich OSM extract (build-world-rich.py, 1e-4 deg quantization, ~16 MB,
   committed), world-base.bin the whole planet's coastlines/rivers/lakes
   /major roads from Natural Earth 10m (build-world-base.py, 1e-4 deg,
   ~5 MB, committed). *)
let world_rich_file = ("world-rich.bin", "VOKWR001", 1e-4)
let world_base_file = ("world-base.bin", "VOKWB001", 1e-4)

let world_bin_available cache_dir (file, _, _) =
  Sys.file_exists (Filename.concat cache_dir file)

(* O(b); b = bytes of the varint. *)
let read_varint (s : string) (pos : int ref) : int =
  let rec loop shift acc =
    let b = Char.code s.[!pos] in
    incr pos;
    let acc = acc lor ((b land 0x7f) lsl shift) in
    if b land 0x80 <> 0 then loop (shift + 7) acc else acc
  in
  loop 0 0

let zigzag n = (n lsr 1) lxor (- (n land 1))

(* (class, south, west, north, east, geom) *)
type wb_feature = int * float * float * float * float * geom

let world_bin_cache : (string, wb_feature array) Hashtbl.t =
  Hashtbl.create 2

(* First call per file: O(file bytes) disk read + O(P) decode, P = total
   points of all features in the layer; memoized afterwards. *)
let world_bin_all cache_dir (file, magic, quant) : wb_feature array =
  memoize world_bin_cache file
    (fun () ->
        let path = Filename.concat cache_dir file in
        if not (Sys.file_exists path) then [||]
        else
          let s = Util.read_file path in
          if String.length s < 9 || String.sub s 0 8 <> magic then [||]
          else begin
            let pos = ref 8 in
            let n = read_varint s pos in
            Array.init n (fun _ ->
                let cls = Char.code s.[!pos] in
                incr pos;
                let npts = read_varint s pos in
                let x = ref (zigzag (read_varint s pos)) in
                let y = ref (zigzag (read_varint s pos)) in
                let south = ref !y and west = ref !x in
                let north = ref !y and east = ref !x in
                let pts_rev = ref [ (!x, !y) ] in
                for _ = 2 to npts do
                  x := !x + zigzag (read_varint s pos);
                  y := !y + zigzag (read_varint s pos);
                  pts_rev := (!x, !y) :: !pts_rev;
                  south := min !south !y;
                  west := min !west !x;
                  north := max !north !y;
                  east := max !east !x
                done;
                let q v = Float.of_int v *. quant in
                ( cls,
                  q !south,
                  q !west,
                  q !north,
                  q !east,
                  List.rev_map (fun (x, y) -> (q x, q y)) !pts_rev ))
          end)

let world_base_available cache_dir =
  world_bin_available cache_dir world_base_file

let world_rich_available cache_dir =
  world_bin_available cache_dir world_rich_file

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
  way["natural"="coastline"](%s);
  way["landuse"="reservoir"](%s);
  relation["natural"="water"](%s);
  relation["landuse"="reservoir"](%s);
);
out geom;
|}
    bbox
    (if small then "river|canal|stream" else "river|canal")
    bbox bbox bbox bbox bbox bbox

(* Run curl; returns true on success (file exists and looks like JSON).
   A custom UA is required: some instances reject default client agents.
   Complexity: O(network): shell-out to curl plus an O(L) read-back of
   the response, L = response size. *)
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

(* O(e) curl attempts, e = number of endpoints; each attempt O(network). *)
let fetch_overpass (query : string) (out_path : string) : bool =
  List.exists
    (fun ep ->
      Printf.printf "[map]   trying %s\n%!" ep;
      curl_post ep query out_path)
    overpass_endpoints

(* Get cached JSON for a region, fetching from Overpass if missing.
   Cache hit: O(file size) disk read.  Miss: O(network) fetch followed by
   an O(L) minify + rewrite that turns it into a cache hit. *)
let load_region_json (cache_dir : string) (r : region) : (string, string) result
    =
  let path = Filename.concat cache_dir (cache_filename r) in
  if Sys.file_exists path then
    try Ok (prof_time prof_disk_t (fun () -> Util.read_file path))
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
  else if world_base_available cache_dir || world_rich_available cache_dir then
    (* the committed binary layers cover the whole planet offline; live
       Overpass fetches are never needed (rich data comes from local
       extracts via extract-map-cache.py) *)
    Error "no locally cached region data (rendering packed world layers)"
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
  | Coast_line of geom (* open shoreline segments *)

(* bin-layer features intersecting a region
   Complexity: O(B) full scan of the layer's B features per call (bbox
   filter; the decode itself is memoized, the filter is not). *)
let world_bin_features cache_dir which (r : region) : feature list option =
  if not (world_bin_available cache_dir which) then None
  else
    Some
      (Array.fold_left
         (fun acc (cls, s, w, n, e, g) ->
           if e < r.west || w > r.east || n < r.south || s > r.north then acc
           else
             (match cls with
              | 1 -> Coast_line g
              | 2 -> Water_line g
              | 3 -> Water_fill [ g ]
              | 4 -> Road ("trunk", g)
              | 5 -> Road ("primary", g)
              | _ -> Road ("secondary", g))
             :: acc)
         [] (world_bin_all cache_dir which))

let tag_value tags k = Option.value ~default:"" (List.assoc_opt k tags)

(* O(k); k = tag entries of the element. *)
let tags_of (el : Json.t) : (string * string) list =
  match Json.member "tags" el with
  | Some (Json.Obj kvs) ->
      List.filter_map (fun (k, v) ->
          match Json.as_string v with Some s -> Some (k, s) | None -> None)
        kvs
  | _ -> []

(* O(p); p = points of the element's geometry. *)
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

(* Join relation "outer" member ways into rings by matching endpoints.
   Complexity: O(w * (w + P)) worst case, w = member ways, P = total
   points - each merge step does a linear endpoint search, a filteri
   removal and a list append. *)
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

(* O(size of element): O(k + p) for ways; relations add assemble_rings,
   O(w * (w + P)) worst case. *)
let feature_of_element (el : Json.t) : feature list =
  match Json.get_string "type" el with
  | Some "way" -> (
      let tags = tags_of el in
      let tag k = tag_value tags k in
      match geom_of el with
      | None -> []
      | Some geom ->
          let highway = tag "highway" in
          let waterway = tag "waterway" in
          let natural = tag "natural" in
          let landuse = tag "landuse" in
          if highway <> "" then [ Road (highway, geom) ]
          else if waterway <> "" then [ Water_line geom ]
          else if natural = "coastline" then [ Coast_line geom ]
          else if natural = "water" || landuse = "reservoir" then
            [ Water_fill [ geom ] ]
          else [])
  | Some "relation" -> (
      let tags = tags_of el in
      let tag k = tag_value tags k in
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

(* Ramer-Douglas-Peucker polyline simplification on projected px coords.
   Complexity: expected O(p log p), worst case O(p^2); p = input points. *)
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

(* lat/lon inside a region, boundaries included *)
let lat_lon_in_region (r : region) lat lon =
  lat >= r.south && lat <= r.north && lon >= r.west && lon <= r.east

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

(* nice_step-aligned values in [lo, hi]
   Complexity: O(t); t = number of ticks produced (span / step + 1). *)
let tick_values step lo hi =
  let rec go v acc = if v > hi +. (step *. 1e-6) then List.rev acc else go (v +. step) (v :: acc) in
  go (Float.of_int (int_of_float (Float.ceil (lo /. step -. 1e-9))) *. step) []

let fmt_coord ?(dec = 5) v pos neg =
  Printf.sprintf "%.*f°%c" dec (Float.abs v) (if v >= 0. then pos else neg)

(* every country outline within a fixed world frame (no Antarctica;
   countries missing from Natural Earth are just absent) *)
let world_region = { south = -60.; west = -180.; north = 85.; east = 180. }

(* O(total points of every country outline in country-outlines.json),
   after the memoized O(L) file parse. *)
let world_geometries cache_dir : feature list option =
  let _, outlines = geodata cache_dir in
  match outlines with
  | Some (Json.Obj kvs) ->
      Some
        (List.concat_map
           (fun (_, el) ->
             (* the unfiltered world ring set (Alaska, Svalbard, French
                Guiana, ...) when present, else the mainland-focused one *)
             let ring_set =
               match Json.member "world_rings" el with
               | Some rings -> Some rings
               | None -> Json.member "rings" el
             in
             match ring_set with
             | Some rings -> List.map (fun g -> Outline g) (geom_of_rings rings)
             | None -> [])
           kvs)
  | _ -> None

(* O(L): full JSON parse plus one extraction pass over all elements and
   their points; L = JSON text length. *)
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

(* parsed features per region: Overpass JSON is large (MBs) and every
   page renders twice, so without this cache the biggest cost of the
   whole build is re-parsing the same files over and over *)
let feature_cache : (string, (feature list, string) result) Hashtbl.t =
  Hashtbl.create 64

(* on-disk parsed-feature cache: unmarshal is ~10x faster than parsing
   the multi-MB Overpass JSON.  Bump the magic whenever the feature
   type layout changes; stale/corrupt bins are silently rebuilt. *)
let bin_magic = "VOKOBE-FEATURES-2"

(* O(bin file size) disk read + unmarshal. *)
let read_bin path : feature list option =
  try
    let ic = open_in_bin path in
    match really_input_string ic (String.length bin_magic) with
    | magic when magic = bin_magic ->
        let v = (Marshal.from_channel ic : feature list) in
        close_in ic;
        Some v
    | _ ->
        close_in ic;
        None
  with _ -> None

(* O(size of the marshalled feature list) disk write. *)
let write_bin path (fs : feature list) =
  try
    let oc = open_out_bin path in
    output_string oc bin_magic;
    Marshal.to_channel oc fs [];
    close_out oc
  with _ -> ()

(* O(1) per call after the first for a region (memoized).  First call:
   O(bin size) unmarshal when the binary sidecar is fresh, else O(L)
   parse of the cached Overpass JSON, else an O(network) Overpass fetch;
   a successful parse writes the .bin sidecar for later builds. *)
let region_features (cache_dir : string) (r : region) :
    (feature list, string) result =
  let key = cache_filename r in
  memoize feature_cache key
    (fun () ->
      let path = Filename.concat cache_dir key in
      let bin = path ^ ".bin" in
      match
        if Sys.file_exists bin && Sys.file_exists path then (
          let fresh =
            (Unix.stat bin).st_mtime >= (Unix.stat path).st_mtime
          in
          if fresh then read_bin bin else None)
        else None
      with
      | Some fs -> Ok fs
      | None -> (
          match load_region_json cache_dir r with
          | Error e -> Error e
          | Ok json_text -> (
              match features_of_json json_text with
              | Ok fs ->
                  write_bin bin fs;
                  Ok fs
              | Error e -> Error e)))

(* one placed map label, ready to emit *)
type placement = {
  p_label_sz : float;
  p_anchor : string;
  p_tx : float;
  p_box : float * float * float * float;
  p_leader : (float * float) option;
  p_leader_len : float option;
  p_big_ok : bool;
}

(* The full SVG pipeline.  Geometry: O(P) projection plus per-feature RDP
   decimation, expected O(P log p_max), worst case O(P * p_max)
   (P = total points, p_max = points of the largest geometry).  Label
   placement: O(m^2) for m markers - each label tests a constant ~100
   candidate spots against O(m) already-placed obstacle boxes, with at
   most two passes. *)
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
  let b_coast = layer () in (* shorelines *)
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
      | Coast_line g -> path_into b_coast g
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
  emit_layer b_coast
    {|fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" opacity="0.8"|};
  emit_layer b_river
    {|fill="none" stroke="currentColor" stroke-width="3" stroke-linecap="round" opacity="0.6"|};
  (* all three road classes share one style with only width (+ trailing
     extras like opacity) differing *)
  let emit_road buf w extras =
    emit_layer buf
      (Printf.sprintf
         {|fill="none" stroke="currentColor" stroke-width="%.1f" stroke-linecap="round"%s|}
         (w *. wscale) extras)
  in
  emit_road b_road_hw 7. "";
  emit_road b_road_p 5. "";
  emit_road b_road_s 3. {| opacity="0.8"|};
  (* marker dots + labels.  Labels sit on an inverted box (foreground
     fill, page-background text via --map-bg) so they stay readable on
     top of dense features, and are placed around their dot where they
     neither leave the frame nor overlap other labels/dots (a label may
     of course sit next to its own dot).  Labels default to body-text
     size and only shrink in crowded spots where the big size finds no
     free spot.  If no spot is free at all, the candidate overlapping
     the least is used.  A label pushed away from its dot gets a thin
     leader line connecting the two *)
  let big_label_sz = 0.85 *. text_sz in
  let small_label_sz = 0.5 *. text_sz in
  let marker_r = 0.15 *. text_sz in
  let sep = 0.5 *. big_label_sz in
  let in_frame (x0, y0, x1, y1) =
    x0 >= ml && y0 >= mt && x1 <= ml +. width && y1 <= mt +. height
  in
  (* dots are drawn first; remember their boxes so a label can avoid
     every dot except its own *)
  let dot_boxes =
    List.map
      (fun m ->
        let x, y = project (m.mlon, m.mlat) in
        add
          (Printf.sprintf
             "<circle cx=\"%s\" cy=\"%s\" r=\"%s\" fill=\"currentColor\"/>\n"
             (fmt x) (fmt y) (fmt marker_r));
        (x -. marker_r, y -. marker_r, x +. marker_r, y +. marker_r))
      markers
  in
  let placed_labels : (float * float * float * float) list ref = ref [] in
  (* how much of a candidate box collides with the obstacles, counting
     the sep halo on both sides *)
  let overlap_area obstacles (x0, y0, x1, y1) =
    List.fold_left
      (fun acc (a0, b0, a1, b1) ->
        let ox =
          Float.min (x1 +. sep) (a1 +. sep)
          -. Float.max (x0 -. sep) (a0 -. sep)
        in
        let oy =
          Float.min (y1 +. sep) (b1 +. sep)
          -. Float.max (y0 -. sep) (b0 -. sep)
        in
        if ox > 0. && oy > 0. then acc +. (ox *. oy) else acc)
      0. obstacles
  in
  (* width estimation needs glyph count; String.length counts bytes *)
  let utf8_length s =
    String.fold_left
      (fun n c -> if Char.code c land 0xC0 <> 0x80 then n + 1 else n)
      0 s
  in
  (* pick a spot for marker i's label, registering the box as an
     obstacle for later labels.  `prefer_small` tries the small size
     first; it's used in the second pass for labels that couldn't be
     accommodated at full size. *)
  let place_label ~prefer_small i m : placement option =
    match m.mlabel with
    | None -> None
    | Some label ->
        let x, y = project (m.mlon, m.mlat) in
        let other_dots = List.filteri (fun j _ -> j <> i) dot_boxes in
        let obstacles = other_dots @ !placed_labels in
        let n_glyphs = utf8_length label in
        (* candidates for one label size: (label_sz, anchor, text_x,
           box, leader); the text baseline is put at the box's vertical
           centre so the label sits neatly in its background rect.
           `box` is the padded rect that gets drawn, so collision/frame
           checks cover the actual pixels; `leader` carries the x of the
           box edge facing the dot when the label is vertically
           displaced *)
        let candidates_of label_sz =
          let tw = 0.62 *. label_sz *. Float.of_int n_glyphs in
          let th = 1.3 *. label_sz in
          let half = tw /. 2. in
          let pad = 0.25 *. label_sz in
          let gap = 0.7 *. label_sz in
          (* label beside the dot: sign +1. = right, -1. = left (the end
             anchor flips the text away from the dot) *)
          let side ~leader dy sign =
            let gx = x +. (sign *. gap) in
            let x0, x1, edge =
              if sign > 0. then
                (gx -. pad, gx +. pad +. tw, gx -. pad)
              else
                (gx -. pad -. tw, gx +. pad, gx +. pad)
            in
            ( label_sz,
              (if sign > 0. then "" else "text-anchor=\"end\" "),
              gx,
              ( x0,
                y +. dy -. (th /. 2.),
                x1,
                y +. dy +. (th /. 2.) ),
              (if leader then Some edge else None) )
          in
          (* label above (sign -1.) or below (sign +1.) the dot *)
          let over_under sign =
            ( label_sz,
              "text-anchor=\"middle\" ",
              x,
              ( x -. half -. pad,
                y +. (sign *. gap) -. (if sign < 0. then th else 0.),
                x +. half +. pad,
                y +. (sign *. gap) +. (if sign < 0. then 0. else th) ),
              None )
          in
          [
            side ~leader:false 0. 1.;
            side ~leader:false 0. (-1.);
            over_under (-1.);
            over_under 1.;
          ]
          @ List.concat_map
              (fun k ->
                let dy = 0.45 *. th *. k in
                [
                  side ~leader:true (-.dy) 1.;
                  side ~leader:true dy 1.;
                  side ~leader:true (-.dy) (-1.);
                  side ~leader:true dy (-1.);
                ])
              [ 1.; 2.; 3.; 4.; 5.; 6.; 7.; 8.; 9.; 10.; 11.; 12. ]
        in
        let fits (_, _, _, b, _) =
          in_frame b && overlap_area obstacles b = 0.
        in
        let sizes =
          if prefer_small then [ small_label_sz; big_label_sz ]
          else [ big_label_sz; small_label_sz ]
        in
        let prefered = candidates_of (List.hd sizes) in
        let all = List.concat_map candidates_of sizes in
        let c, big_ok =
          (* preferred size first; nothing free at all -> least overlap
             of both sizes *)
          match List.find_opt fits prefered with
          | Some c -> (c, true)
          | None -> (
              match List.find_opt fits all with
              | Some c -> (c, false)
              | None -> (
                  let cost (_, _, _, b, _) =
                    (if in_frame b then 0. else 1e12)
                    +. overlap_area other_dots b
                    +. (8. *. overlap_area !placed_labels b)
                  in
                  match
                    List.fold_left
                      (fun best c ->
                        match best with
                        | None -> Some (c, cost c)
                        | Some (_, best_cost) ->
                            let cc = cost c in
                            if cc < best_cost then Some (c, cc) else best)
                      None all
                  with
                  | Some (c, _) -> (c, false)
                  | None ->
                      ( ( big_label_sz,
                          "text-anchor=\"end\" ",
                          x,
                          (x, y, x, y),
                          None ),
                        false )))
        in
        let label_sz, anchor, tx, box, leader = c in
        placed_labels := box :: !placed_labels;
        let x0, y0, x1, y1 = box in
        let p_leader, p_leader_len =
          match leader with
          | None -> (None, None)
          | Some edge_x ->
              let edge_y =
                Float.min (y1 -. 1.) (Float.max (y0 +. 1.) y)
              in
              let vx = edge_x -. x and vy = edge_y -. y in
              (Some (edge_x, edge_y), Some (Float.hypot vx vy))
        in
        Some
          { p_label_sz = label_sz;
            p_anchor = anchor;
            p_tx = tx;
            p_box = box;
            p_leader;
            p_leader_len;
            p_big_ok = big_ok }
  in
  (* pass 1: everything tries full size first.  Labels that found no
     free spot at full size, or were pushed far from their dot, get a
     second chance at the small size in pass 2 so dense clusters end up
     uniformly small while quiet areas stay large *)
  let placements = Array.make (List.length markers) None in
  List.iteri
    (fun i m -> placements.(i) <- place_label ~prefer_small:false i m)
    markers;
  let shrink =
    List.filter_map
      (fun i ->
        match placements.(i) with
        | Some p when
            (not p.p_big_ok)
            || (match p.p_leader_len with
                | Some l -> l > 1.5 *. big_label_sz
                | None -> false) ->
            Some i
        | _ -> None)
      (List.init (Array.length placements) Fun.id)
  in
  (if shrink <> [] then (
     let marker_arr = Array.of_list markers in
     placed_labels :=
       List.filter_map
         (fun i ->
           if List.mem i shrink then None
           else Option.map (fun (p : placement) -> p.p_box) placements.(i))
         (List.init (Array.length placements) Fun.id);
     List.iter
       (fun i ->
         placements.(i) <-
           place_label ~prefer_small:true i marker_arr.(i))
       shrink));
  List.iteri
    (fun i m ->
      match m.mlabel, placements.(i) with
      | Some label, Some p ->
          let x, y = project (m.mlon, m.mlat) in
          let x0, y0, x1, y1 = p.p_box in
          let label_sz = p.p_label_sz in
          (* leader line from the dot to the label box for displaced
             labels, drawn before the box so the box covers its end *)
          (match p.p_leader, p.p_leader_len with
           | Some (edge_x, edge_y), Some len
             when len > 1.6 *. 0.7 *. label_sz ->
               let vx = edge_x -. x and vy = edge_y -. y in
               add
                   (Printf.sprintf
                      "<path d=\"M%s %sL%s %s\" stroke=\"currentColor\" \
                       stroke-width=\"1.5\" opacity=\"0.5\"/>\n"
                      (fmt (x +. (vx /. len *. marker_r)))
                      (fmt (y +. (vy /. len *. marker_r)))
                      (fmt edge_x) (fmt edge_y))
           | _ -> ());
          add
            (Printf.sprintf
               "<rect x=\"%s\" y=\"%s\" width=\"%s\" height=\"%s\" rx=\"%s\" \
                fill=\"currentColor\"/>\n"
               (fmt x0) (fmt y0)
               (fmt (x1 -. x0))
               (fmt (y1 -. y0))
               (fmt (0.2 *. label_sz)));
          add
            (Printf.sprintf
               "<text x=\"%s\" y=\"%s\" font-size=\"%s\" %s\
                style=\"fill:var(--map-bg)\">%s</text>\n"
               (fmt p.p_tx)
               (fmt (((y0 +. y1) /. 2.) +. (0.35 *. label_sz)))
               (fmt label_sz) p.p_anchor (svg_escape label))
      | _ -> ())
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
  (* one axis of tick marks + coordinate labels: [tick_of v] gives the
     tick-mark segment, [text_xy v] the label position *)
  let draw_ticks values ~anchor ~tick_of ~text_xy ~label_of =
    List.iter
      (fun v ->
        let tx0, ty0, tx1, ty1 = tick_of v in
        addf
          (Printf.sprintf
             "<path d=\"M%.0f %.0fL%.0f %.0f\" stroke=\"currentColor\" \
              stroke-width=\"2\"/>\n"
             tx0 ty0 tx1 ty1);
        let x, y = text_xy v in
        addf
          (Printf.sprintf
             "<text x=\"%.0f\" y=\"%.0f\" text-anchor=\"%s\" \
              font-size=\"%s\" fill=\"currentColor\">%s</text>\n"
             x y anchor (fmt text_sz) (label_of v)))
      values
  in
  let lat_step = nice_step (r.north -. r.south) in
  let lat_dec = decimals_of_step lat_step in
  draw_ticks
    (tick_values lat_step r.south r.north)
    ~anchor:"end"
    ~tick_of:(fun lat ->
      let _, y = project (r.west, lat) in
      (ml -. (0.5 *. text_sz), y, ml, y))
    ~text_xy:(fun lat ->
      let _, y = project (r.west, lat) in
      (ml -. (0.8 *. text_sz), y +. (0.35 *. text_sz)))
    ~label_of:(fun lat -> fmt_coord ~dec:lat_dec lat 'N' 'S');
  let lon_step = nice_step (r.east -. r.west) in
  let lon_dec = decimals_of_step lon_step in
  draw_ticks
    (tick_values lon_step r.west r.east)
    ~anchor:"middle"
    ~tick_of:(fun lon ->
      let x, _ = project (lon, r.north) in
      (x, mt +. height, x, mt +. height +. (0.5 *. text_sz)))
    ~text_xy:(fun lon ->
      let x, _ = project (lon, r.north) in
      (x, mt +. height +. (1.7 *. text_sz)))
    ~label_of:(fun lon -> fmt_coord ~dec:lon_dec lon 'E' 'W');
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

(* Entry point per (map ...) block: dominated by region_features (disk
   O(bin/L) or O(network) on first use) plus render_svg; the offline
   fallback adds an O(B) scan per binary layer.  Country/world maps pay
   only geodata lookup + render_svg. *)
let render_ (cache_dir : string) (args : sexp list) : string =
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
  (* road/water map of a region via locally cached data *)
  let via_overpass spec r =
    match prof_time prof_json_t (fun () -> region_features cache_dir r) with
    | Error e -> (
        (* fallback chain: packed rich regions, then the coarse global
           base; together they cover every place on earth offline *)
        match
          ( world_bin_features cache_dir world_rich_file r,
            world_bin_features cache_dir world_base_file r )
        with
        | Some rich, _ when rich <> [] -> finish spec r rich
        | Some _, Some base | None, Some base -> finish spec r base
        | None, None | Some _, None -> render_error e)
    | Ok features -> finish spec r features
  in
  match parse_spec args with
  | Error e -> render_error e
  | Ok spec when spec.world -> (
      match world_geometries cache_dir with
      | Some features -> finish spec world_region features
      | None -> render_error "no geodata for world map")
  | Ok spec -> (
      match (spec.country, spec.region) with
      | None, Some r -> via_overpass spec r
      | None, None -> render_error "map has neither a center nor a country"
      | Some name, _ -> (
          let places, outlines, cname = country_geodata cache_dir name in
          match outline_of_name outlines cname with
          | Some (r, rings) when outline_detailed rings ->
              (* a marker on a far-away part of the country (Rhodes east
                 of mainland Greece) switches the map to the full ring
                 set + region so the marker isn't silently dropped *)
              let in_region (r : region) (m : marker) =
                lat_lon_in_region r m.mlat m.mlon
              in
              let rings, r =
                match world_outline_of_name outlines cname with
                | Some (wr, wrings)
                  when List.exists
                         (fun m ->
                           (not (in_region (pad_region country_pad r) m))
                           && in_region (pad_region country_pad wr) m)
                         spec.markers ->
                    (wrings, wr)
                | _ -> (rings, r)
              in
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
              let r = pad_region country_pad r in
              let r =
                Option.fold ~none:r ~some:(fun a -> pad_to_aspect a r)
                  spec.aspect
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

let render (cache_dir : string) (args : sexp list) : string =
  incr prof_map_n;
  prof_time prof_map_t (fun () -> render_ cache_dir args)
