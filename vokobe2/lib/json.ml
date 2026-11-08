(* Minimal JSON parser, just enough to read API responses (e.g. Overpass).
   Objects are association lists; numbers are floats. *)

type t =
  | Null
  | Bool of bool
  | Num of float
  | Str of string
  | Arr of t list
  | Obj of (string * t) list

exception Error of string

let parse (s : string) : t =
  let len = String.length s in
  let pos = ref 0 in
  let peek () = if !pos < len then Some s.[!pos] else None in
  let expect c =
    match peek () with
    | Some c' when c' = c -> incr pos
    | _ -> raise (Error (Printf.sprintf "expected %C at byte %d" c !pos))
  in
  let skip_ws () =
    while
      !pos < len
      && (match s.[!pos] with ' ' | '\t' | '\n' | '\r' -> true | _ -> false)
    do
      incr pos
    done
  in
  let read_string () =
    expect '"';
    let buf = Buffer.create 32 in
    let rec loop () =
      match peek () with
      | None -> raise (Error "unterminated string")
      | Some '"' -> incr pos
      | Some '\\' ->
          incr pos;
          (match peek () with
           | Some '"' -> Buffer.add_char buf '"'; incr pos
           | Some '\\' -> Buffer.add_char buf '\\'; incr pos
           | Some '/' -> Buffer.add_char buf '/'; incr pos
           | Some 'b' -> Buffer.add_char buf '\b'; incr pos
           | Some 'f' -> Buffer.add_char buf '\012'; incr pos
           | Some 'n' -> Buffer.add_char buf '\n'; incr pos
           | Some 'r' -> Buffer.add_char buf '\r'; incr pos
           | Some 't' -> Buffer.add_char buf '\t'; incr pos
           | Some 'u' ->
               incr pos;
               if !pos + 4 > len then raise (Error "bad \\u escape");
               let hex = String.sub s !pos 4 in
               pos := !pos + 4;
               let code =
                 try int_of_string ("0x" ^ hex)
                 with _ -> raise (Error "bad \\u escape")
               in
               (* encode (possibly lossy for surrogates; fine for map labels) *)
               if code < 0x80 then Buffer.add_char buf (Char.chr code)
               else if code < 0x800 then begin
                 Buffer.add_char buf (Char.chr (0xC0 lor (code lsr 6)));
                 Buffer.add_char buf (Char.chr (0x80 lor (code land 0x3F)))
               end else begin
                 Buffer.add_char buf (Char.chr (0xE0 lor (code lsr 12)));
                 Buffer.add_char buf
                   (Char.chr (0x80 lor ((code lsr 6) land 0x3F)));
                 Buffer.add_char buf (Char.chr (0x80 lor (code land 0x3F)))
               end
           | _ -> raise (Error "bad escape"));
          loop ()
      | Some c ->
          Buffer.add_char buf c;
          incr pos;
          loop ()
    in
    loop ();
    Buffer.contents buf
  in
  let read_number () =
    let start = !pos in
    let is_num_char c =
      (c >= '0' && c <= '9') || c = '-' || c = '+' || c = '.' || c = 'e'
      || c = 'E'
    in
    while (match peek () with Some c -> is_num_char c | None -> false) do
      incr pos
    done;
    if !pos = start then raise (Error (Printf.sprintf "bad number at %d" start));
    let str = String.sub s start (!pos - start) in
    try float_of_string str
    with _ -> raise (Error ("bad number: " ^ str))
  in
  let read_lit lit value =
    let n = String.length lit in
    if !pos + n <= len && String.sub s !pos n = lit then (
      pos := !pos + n;
      value)
    else raise (Error (Printf.sprintf "bad literal at %d" !pos))
  in
  let rec read_value () : t =
    skip_ws ();
    match peek () with
    | None -> raise (Error "unexpected end of input")
    | Some '{' -> read_object ()
    | Some '[' -> read_array ()
    | Some '"' -> Str (read_string ())
    | Some 't' -> read_lit "true" (Bool true)
    | Some 'f' -> read_lit "false" (Bool false)
    | Some 'n' -> read_lit "null" Null
    | Some _ -> Num (read_number ())
  and read_object () =
    expect '{';
    skip_ws ();
    let rec loop acc =
      skip_ws ();
      match peek () with
      | Some '}' -> incr pos; List.rev acc
      | Some '"' ->
          let key = read_string () in
          skip_ws ();
          expect ':';
          let v = read_value () in
          skip_ws ();
          (match peek () with
           | Some ',' -> incr pos; loop ((key, v) :: acc)
           | _ -> loop ((key, v) :: acc))
      | _ -> raise (Error (Printf.sprintf "bad object at %d" !pos))
    in
    Obj (loop [])
  and read_array () =
    expect '[';
    skip_ws ();
    let rec loop acc =
      skip_ws ();
      match peek () with
      | Some ']' -> incr pos; List.rev acc
      | _ ->
          let v = read_value () in
          skip_ws ();
          (match peek () with
           | Some ',' -> incr pos; loop (v :: acc)
           | _ -> loop (v :: acc))
    in
    Arr (loop [])
  in
  let v = read_value () in
  skip_ws ();
  v

(* Strip insignificant whitespace (respecting string literals + escapes). *)
let minify (s : string) : string =
  let buf = Buffer.create (String.length s) in
  let in_str = ref false in
  let esc = ref false in
  String.iter
    (fun c ->
      if !in_str then begin
        Buffer.add_char buf c;
        if !esc then esc := false
        else if c = '\\' then esc := true
        else if c = '"' then in_str := false
      end
      else
        match c with
        | '"' ->
            in_str := true;
            Buffer.add_char buf c
        | ' ' | '\t' | '\n' | '\r' -> ()
        | _ -> Buffer.add_char buf c)
    s;
  Buffer.contents buf

(* accessors *)
let member key = function Obj kvs -> List.assoc_opt key kvs | _ -> None
let as_float = function Num n -> Some n | _ -> None
let as_string = function Str s -> Some s | _ -> None
let as_list = function Arr xs -> Some xs | _ -> None

let get_float key j = match member key j with
  | Some v -> as_float v
  | None -> None

let get_string key j = match member key j with
  | Some v -> as_string v
  | None -> None
