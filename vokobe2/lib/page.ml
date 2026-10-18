open Sexp

type page = {
  name : string;
  title : string;
  raw : string;
  attrs : (string * string list) list;
}

type list_kind = Ordered | Unordered

let parse_list_item (line : string) : (int * list_kind * string) option =
  let len = String.length line in
  let rec count_indent i =
    if i < len && (line.[i] = ' ' || line.[i] = '\t') then count_indent (i + 1)
    else i
  in
  let indent = count_indent 0 in
  let rest = String.sub line indent (len - indent) in
  if Util.starts_with ~prefix:"* " rest
  || Util.starts_with ~prefix:"- " rest
  || Util.starts_with ~prefix:"+ " rest
  then
    Some (indent, Unordered, String.trim (String.sub rest 2 (String.length rest - 2)))
  else
    let rlen = String.length rest in
    let rec find_dot i =
      if i >= rlen then None
      else if rest.[i] = '.' && i + 1 < rlen && rest.[i + 1] = ' ' then Some i
      else if rest.[i] >= '0' && rest.[i] <= '9' then find_dot (i + 1)
      else None
    in
    match find_dot 0 with
    | Some dot_pos when dot_pos > 0 ->
        let text = String.trim (String.sub rest (dot_pos + 2) (rlen - dot_pos - 2)) in
        Some (indent, Ordered, text)
    | _ -> None

let page_title_of (name : string) (raw : string) : string =
  let lines = String.split_on_char '\n' raw in
  let rec find = function
    | [] -> name
    | line :: rest ->
      let line = String.trim line in
      if Util.starts_with ~prefix:"# " line then
        String.trim (Util.drop_prefix ~prefix:"# " line)
      else find rest
  in
  find lines

let merge_attrs (attrs_rev : (string * string list) list) : (string * string list) list =
  List.fold_left
    (fun acc (k, vs) ->
      if List.mem_assoc k acc then
        List.map (fun (k2, v2) -> if k2 = k then (k2, v2 @ vs) else (k2, v2)) acc
      else
        acc @ [(k, vs)])
    []
    (List.rev attrs_rev)

(* (location "City") or (location "City" "Country") -> location/country attrs *)
let location_attrs (vals : sexp list) : (string * string list) list =
  let str_vals = List.filter_map (function Atom s -> Some s | _ -> None) vals in
  match str_vals with
  | [city; country] -> [("country", [country]); ("location", [city])]
  | _ -> [("location", str_vals)]

(* Character ranges [start, stop) covered by fenced code blocks, so that
   example s-expressions inside ``` blocks are not treated as metadata. *)
let code_block_ranges (raw : string) : (int * int) list =
  let len = String.length raw in
  let rec aux pos in_code start acc =
    if pos >= len then
      if in_code then List.rev ((start, len) :: acc) else List.rev acc
    else
      let line_end =
        match String.index_from_opt raw pos '\n' with
        | Some nl -> nl + 1
        | None -> len
      in
      let line = String.sub raw pos (line_end - pos) in
      let trimmed = String.trim line in
      if Util.starts_with ~prefix:"```" trimmed then
        if in_code then aux line_end false 0 ((start, line_end) :: acc)
        else aux line_end true pos acc
      else aux line_end in_code start acc
  in
  aux 0 false 0 []

let parse_attrs (raw : string) : (string * string list) list =
  let len = String.length raw in
  let pos = ref 0 in
  let attrs = ref [] in
  let code_ranges = ref (code_block_ranges raw) in
  while !pos < len do
    (* skip over fenced code blocks: their contents are examples, not metadata *)
    (match !code_ranges with
     | (range_start, range_end) :: rest ->
         if !pos >= range_end then code_ranges := rest
         else if !pos >= range_start then (
           pos := range_end;
           code_ranges := rest)
     | [] -> ());
    if !pos < len then
    if raw.[!pos] = '(' then (
      match parse_sexp_at raw !pos with
      | List (Atom "meta" :: entries), next_pos ->
          List.iter
            (function
              | List (Atom "location" :: vals) ->
                  attrs := location_attrs vals @ !attrs
              | List (Atom ("date-range" | "date") :: vals) ->
                  let str_vals =
                    List.filter_map
                      (function Atom s -> Some s | _ -> None)
                      vals
                  in
                  (match str_vals with
                   | [start; end_] ->
                       attrs := ("date-end", [end_]) :: !attrs;
                       attrs := ("date-start", [start]) :: !attrs
                   | [single] ->
                       attrs := ("date-end", [single]) :: !attrs;
                       attrs := ("date-start", [single]) :: !attrs
                   | _ -> ())
              | List (Atom key :: vals) ->
                  let str_vals =
                    List.filter_map
                      (function Atom s -> Some s | _ -> None)
                      vals
                  in
                  attrs := (key, str_vals) :: !attrs
              | _ -> ())
            entries;
          pos := next_pos
      (* inline (location ...) in body text, outside any (meta ...) block *)
      | List (Atom "location" :: vals), next_pos ->
          attrs := location_attrs vals @ !attrs;
          pos := next_pos
      | _, next_pos -> pos := next_pos
      | exception _ -> incr pos)
    else
      incr pos
  done;
  merge_attrs !attrs

let load_pages (input_dir : string) : page list =
  Sys.readdir input_dir
  |> Array.to_list
  |> List.filter (fun f -> Filename.check_suffix f ".md")
  |> List.sort compare
  |> List.map (fun f ->
         let name = Filename.remove_extension f in
         let raw = Util.read_file (Filename.concat input_dir f) in
         { name; title = page_title_of name raw; raw; attrs = parse_attrs raw })
