let read_file (path : string) : string =
  let ic = open_in_bin path in
  let n = in_channel_length ic in
  let s = really_input_string ic n in
  close_in ic;
  s

let write_file (path : string) (content : string) : unit =
  let oc = open_out_bin path in
  output_string oc content;
  close_out oc

let ensure_dir (path : string) : unit =
  if not (Sys.file_exists path) then Sys.mkdir path 0o755

let contains_substring (hay : string) (needle : string) : bool =
  let hn = String.length hay and nn = String.length needle in
  if nn = 0 then true
  else
    let rec loop i =
      if i + nn > hn then false
      else if String.sub hay i nn = needle then true
      else loop (i + 1)
    in
    loop 0

let starts_with ~(prefix : string) (s : string) : bool =
  let pl = String.length prefix and sl = String.length s in
  pl <= sl && String.sub s 0 pl = prefix

let drop_prefix ~(prefix : string) (s : string) : string =
  let pl = String.length prefix in
  if starts_with ~prefix s then String.sub s pl (String.length s - pl) else s

let html_escape (s : string) : string =
  let buf = Buffer.create (String.length s) in
  String.iter
    (fun c ->
      match c with
      | '<' -> Buffer.add_string buf "&lt;"
      | '>' -> Buffer.add_string buf "&gt;"
      | '&' -> Buffer.add_string buf "&amp;"
      | '"' -> Buffer.add_string buf "&quot;"
      | c -> Buffer.add_char buf c)
    s;
  Buffer.contents buf

let sanitize (s : string) : string =
  let s = String.map (fun c -> if c = ' ' then '-' else c) s in
  let buf = Buffer.create (String.length s) in
  String.iter
    (fun c ->
      let c = Char.lowercase_ascii c in
      if (c >= 'a' && c <= 'z') || (c >= '0' && c <= '9') || c = '-' then
        Buffer.add_char buf c)
    s;
  Buffer.contents buf
