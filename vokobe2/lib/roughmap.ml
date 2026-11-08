(* Rough outline maps from OpenStreetMap data.

   (map (center LAT LON WIDTH_KM)
        (marker LAT LON "optional label")
        ...)

   Geometry is fetched from the Overpass API on first use and cached as raw
   JSON in a cache directory (one file per bounding box), so all later builds
   are fully local and reproducible. Rendered as inline SVG. *)

open Sexp

(* set by bin/main.ml via --offline: never touch the network *)
let offline = ref false

let set_offline v = offline := v

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

type marker = { mlat : float; mlon : float; mlabel : string option }

type spec = { region : region; markers : marker list }

let float_of_atom = function
  | Atom a -> (try Some (float_of_string a) with _ -> None)
  | List _ -> None

let parse_spec (args : sexp list) : (spec, string) result =
  let region = ref None in
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
          | Some lat, Some lon, Some w_km ->
              if w_km <= 0. || Float.abs lat > 90. || Float.abs lon > 180. then
                error := Some "center: bad LAT LON or non-positive WIDTH_KM"
              else
                let cos_lat = Float.cos (lat *. Float.pi /. 180.) in
                if cos_lat < 1e-6 then
                  error := Some "center: latitude too close to a pole"
                else begin
                  (* width_km is the horizontal width; spans are symmetric *)
                  let half_lat = w_km /. 2. /. 110.574 in
                  let half_lon = w_km /. 2. /. (111.320 *. cos_lat) in
                  region :=
                    Some
                      {
                        south = lat -. half_lat;
                        north = lat +. half_lat;
                        west = lon -. half_lon;
                        east = lon +. half_lon;
                      }
                end
          | _ -> error := Some "center needs numeric LAT LON WIDTH_KM")
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
      match !region with
      | None -> Error "map is missing a (center LAT LON WIDTH_KM) directive"
      | Some r -> Ok { region = r; markers = List.rev !markers })

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
  way["boundary"="administrative"]["admin_level"~"^[2-6]$"](%s);
  relation["boundary"="administrative"]["admin_level"~"^[2-4]$"](%s);
  way["natural"="coastline"](%s);
  node["natural"="peak"](%s);
);
out geom;
|}
    bbox
    (if small then "river|canal|stream" else "river|canal")
    bbox bbox bbox bbox bbox bbox bbox bbox bbox

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

type geom = (float * float) list (* (lon, lat) points *)

type way = { tags : (string * string) list; geom : geom }

type feature =
  | Water_fill of geom list (* one or more rings *)
  | Water_line of geom
  | Road of string * geom (* highway class, geometry *)
  | Boundary of string * geom (* admin_level, geometry *)
  | Coastline of geom
  | Peak of float * float * string option * float option (* lon, lat, name, ele *)

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
          let boundary = tag "boundary" in
          if highway <> "" then [ Road (highway, geom) ]
          else if waterway <> "" then [ Water_line geom ]
          else if natural = "water" || landuse = "reservoir" then
            [ Water_fill [ geom ] ]
          else if boundary = "administrative" then
            [ Boundary (tag "admin_level", geom) ]
          else if natural = "coastline" then [ Coastline geom ]
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
      let boundary = tag "boundary" in
      if (natural = "water" || landuse = "reservoir") && outer_geoms <> [] then
        [ Water_fill (assemble_rings outer_geoms) ]
      else if boundary = "administrative" then
        List.map (fun g -> Boundary (tag "admin_level", g)) outer_geoms
      else [])
  | Some "node" -> (
      let tags = tags_of el in
      match
        ( List.assoc_opt "natural" tags,
          Json.get_float "lon" el,
          Json.get_float "lat" el )
      with
      | Some "peak", Some lon, Some lat ->
          let ele =
            match List.assoc_opt "ele" tags with
            | Some s -> (
                (* ele values look like "4810", "4 810" or "4810 m" *)
                let digits =
                  String.to_seq s
                  |> Seq.filter (fun c -> (c >= '0' && c <= '9') || c = '.')
                  |> String.of_seq
                in
                try Some (float_of_string digits) with _ -> None)
            | None -> None
          in
          [ Peak (lon, lat, List.assoc_opt "name" tags, ele) ]
      | _ -> [])
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

let render_svg (r : region) (markers : marker list) (json_text : string) :
    (string, string) result =
  match (try Ok (Json.parse json_text) with Json.Error e -> Error e) with
  | Error e -> Error ("failed to parse map data: " ^ e)
  | Ok json ->
      let clat = (r.south +. r.north) /. 2. in
      let kx = Float.cos (clat *. Float.pi /. 180.) in
      let width = 900. in
      let deg_w = Float.max 1e-9 (r.east -. r.west) in
      let scale = width /. (deg_w *. kx) in
      let height = Float.max 1. ((r.north -. r.south) *. scale) in
      let project (lon, lat) =
        ((lon -. r.west) *. kx *. scale, (r.north -. lat) *. scale)
      in
      (* simplify to ~1px tolerance after projection: it's a rough map *)
      let decimate pts = rdp 1.0 pts in
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
      let parts = Buffer.create 4096 in
      (* layer buffers: all geometries of a class share one big <path> *)
      let layer () = Buffer.create 1024 in
      let b_country = layer () in (* admin_level 2 *)
      let b_state = layer () in (* 3-4 *)
      let b_local = layer () in (* 5-6 *)
      let b_water_fill = layer () in
      let b_coast = layer () in
      let b_river = layer () in
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
      let elements =
        match Json.member "elements" json with
        | Some (Json.Arr els) -> els
        | _ -> []
      in
      let features = List.concat_map feature_of_element elements in
      List.iter
        (function
          | Boundary (level, g) ->
              let buf =
                match level with
                | "2" -> b_country
                | "3" | "4" -> b_state
                | _ -> b_local
              in
              path_into buf g
          | Water_fill rings ->
              List.iter
                (fun ring ->
                  if big_enough_ring ring then
                    path_into ~close:true b_water_fill ring)
                rings
          | Coastline g -> path_into b_coast g
          | Water_line g -> path_into b_river g
          | Road (cls, g) ->
              let buf =
                match cls with
                | "motorway" | "motorway_link" | "trunk" | "trunk_link" ->
                    b_road_hw
                | "primary" | "primary_link" -> b_road_p
                | _ -> b_road_s
              in
              path_into buf g
          | Peak _ -> ())
        features;
      let ink = "#1c1a17" in
      let emit_layer buf style =
        if Buffer.length buf > 0 then
          Printf.bprintf parts "<path d=\"%s\" %s/>\n" (Buffer.contents buf)
            style
      in
      emit_layer b_country
        (Printf.sprintf
           {|fill="none" stroke="%s" stroke-width="2.6" stroke-dasharray="7 4" opacity="0.9"|}
           ink);
      emit_layer b_state
        (Printf.sprintf
           {|fill="none" stroke="%s" stroke-width="1.8" stroke-dasharray="6 4" opacity="0.7"|}
           ink);
      emit_layer b_local
        (Printf.sprintf
           {|fill="none" stroke="%s" stroke-width="1.2" stroke-dasharray="4 4" opacity="0.5"|}
           ink);
      (* water as open hatching, like carved waves in a linocut *)
      emit_layer b_water_fill
        (Printf.sprintf
           {|fill="url(#rm-hatch)" fill-rule="evenodd" stroke="%s" stroke-width="1"|}
           ink);
      emit_layer b_coast
        (Printf.sprintf {|fill="none" stroke="%s" stroke-width="2.2"|} ink);
      emit_layer b_river
        (Printf.sprintf
           {|fill="none" stroke="%s" stroke-width="2" stroke-linecap="round"|}
           ink);
      emit_layer b_road_hw
        (Printf.sprintf
           {|fill="none" stroke="%s" stroke-width="3" stroke-linecap="round"|}
           ink);
      emit_layer b_road_p
        (Printf.sprintf
           {|fill="none" stroke="%s" stroke-width="2.2" stroke-linecap="round"|}
           ink);
      emit_layer b_road_s
        (Printf.sprintf
           {|fill="none" stroke="%s" stroke-width="1.4" stroke-linecap="round"|}
           ink);
      (* label only the 12 highest named peaks: more is unreadable *)
      let labeled_peaks =
        features
        |> List.filter_map (function Peak (lon, lat, Some n, ele) -> Some (lon, lat, n, ele) | _ -> None)
        |> List.sort (fun (_, _, _, e1) (_, _, _, e2) ->
               compare (Option.value ~default:0. e2) (Option.value ~default:0. e1))
        |> List.filteri (fun i _ -> i < 12)
        |> List.map (fun (lon, lat, n, _) -> (lon, lat, n))
      in
      let paper = "#ece5d3" in
      List.iter
        (function
          | Peak (lon, lat, name, _) -> (
              let x, y = project (lon, lat) in
              if x >= 0. && x <= width && y >= 0. && y <= height then begin
                add
                  (Printf.sprintf
                     "<path d=\"M%s %sL%s %sL%s %sZ\" fill=\"%s\"/>\n"
                     (fmt x) (fmt (y -. 5.)) (fmt (x -. 3.5)) (fmt (y +. 2.5))
                     (fmt (x +. 3.5)) (fmt (y +. 2.5)) ink);
                match name with
                | Some n when List.mem (lon, lat, n) labeled_peaks ->
                    add
                      (Printf.sprintf
                         "<text x=\"%s\" y=\"%s\" font-size=\"10\" \
                          fill=\"%s\" style=\"paint-order:stroke\" \
                          stroke=\"%s\" stroke-width=\"2.5\">%s</text>\n"
                         (fmt (x +. 6.)) (fmt (y +. 3.5)) ink paper
                         (svg_escape n))
                | _ -> ()
              end
            )
          | _ -> ())
        features;
      (* markers on top: the single accent colour of the print *)
      List.iter
        (fun m ->
          let x, y = project (m.mlon, m.mlat) in
          add
            (Printf.sprintf
               "<circle cx=\"%s\" cy=\"%s\" r=\"4.5\" fill=\"#7d2a1a\" \
                stroke=\"%s\" stroke-width=\"1.5\"/>\n"
               (fmt x) (fmt y) paper);
          match m.mlabel with
          | Some label ->
              add
                (Printf.sprintf
                   "<text x=\"%s\" y=\"%s\" font-size=\"11.5\" \
                    fill=\"#7d2a1a\" style=\"paint-order:stroke\" \
                    stroke=\"%s\" stroke-width=\"3\">%s</text>\n"
                   (fmt (x +. 8.)) (fmt (y +. 4.)) paper (svg_escape label))
          | None -> ())
        markers;
      Ok
        (Printf.sprintf
           {| <svg class="roughmap" viewBox="0 0 %.0f %.0f" xmlns="http://www.w3.org/2000/svg" role="img">
<defs>
  <pattern id="rm-hatch" width="9" height="9" patternUnits="userSpaceOnUse" patternTransform="rotate(45)">
    <line x1="0" y1="0" x2="0" y2="9" stroke="%s" stroke-width="1.2" opacity="0.55"/>
  </pattern>
  <filter id="rm-wobble" x="-5%%" y="-5%%" width="110%%" height="110%%">
    <feTurbulence type="fractalNoise" baseFrequency="0.02" numOctaves="3" seed="7" result="n"/>
    <feDisplacementMap in="SourceGraphic" in2="n" scale="4"/>
  </filter>
  <filter id="rm-grain" x="0" y="0" width="100%%" height="100%%">
    <feTurbulence type="fractalNoise" baseFrequency="0.8" numOctaves="2" seed="3"/>
    <feColorMatrix values="0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0.10 0"/>
  </filter>
</defs>
<rect x="0" y="0" width="%.0f" height="%.0f" fill="%s"/>
<g filter="url(#rm-wobble)">
%s</g>
<rect x="0" y="0" width="%.0f" height="%.0f" filter="url(#rm-grain)"/>
<rect x="2" y="2" width="%.0f" height="%.0f" fill="none" stroke="%s" stroke-width="2.5"/>
<rect x="6" y="6" width="%.0f" height="%.0f" fill="none" stroke="%s" stroke-width="0.8" opacity="0.7"/>
</svg>
|}
           width height ink width height paper
           (Buffer.contents parts)
           width height
           (width -. 4.) (height -. 4.) ink
           (width -. 12.) (height -. 12.) ink)

let render_error (msg : string) : string =
  Printf.eprintf "[map] %s\n%!" msg;
  Printf.sprintf
    "<div class=\"map-error\"><!-- map error: %s -->map unavailable \
    (%s)</div>"
    (svg_escape msg) (svg_escape msg)

let render (cache_dir : string) (args : sexp list) : string =
  match parse_spec args with
  | Error e -> render_error e
  | Ok spec -> (
      match load_region_json cache_dir spec.region with
      | Error e -> render_error e
      | Ok json_text -> (
          match render_svg spec.region spec.markers json_text with
          | Ok svg -> svg
          | Error e -> render_error e))
