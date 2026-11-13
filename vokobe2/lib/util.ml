(* cumulative profiling: time one action, add the delta onto the ref *)
let prof_time r f =
  let t0 = Unix.gettimeofday () in
  let v = f () in
  r := !r +. (Unix.gettimeofday () -. t0);
  v

(* O(file size) disk read. *)
let read_file (path : string) : string =
  let ic = open_in_bin path in
  let n = in_channel_length ic in
  let s = really_input_string ic n in
  close_in ic;
  s

(* O(len content) disk write. *)
let write_file (path : string) (content : string) : unit =
  let oc = open_out_bin path in
  output_string oc content;
  close_out oc

(* Tolerates concurrent calls for the same path from parallel page
   renders: a losing mkdir (EEXIST, reported as Sys_error) is fine --
   the directory exists, which is all we need. *)
let ensure_dir (path : string) : unit =
  if not (Sys.file_exists path) then
    try Sys.mkdir path 0o755 with Sys_error _ -> ()

(* O(H * N) worst case; H = hay length, N = needle length (naive scan
   with a String.sub + compare per position). *)
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

let drop_prefix ~(prefix : string) (s : string) : string =
  let pl = String.length prefix in
  if String.starts_with ~prefix s then String.sub s pl (String.length s - pl) else s

(* O(len s). *)
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

(* O(len s). *)
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
