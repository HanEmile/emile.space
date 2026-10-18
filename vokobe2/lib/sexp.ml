type sexp = Atom of string | List of sexp list

exception Parse_error of string

let parse_sexp_at (s : string) (start : int) : sexp * int =
  let len = String.length s in
  let pos = ref start in
  let peek () = if !pos < len then Some s.[!pos] else None in
  let advance () = incr pos in
  let is_ws c = c = ' ' || c = '\t' || c = '\n' || c = '\r' in
  let skip_ws () =
    while !pos < len && is_ws s.[!pos] do
      advance ()
    done
  in
  let read_string () =
    advance ();
    let buf = Buffer.create 16 in
    let finished = ref false in
    while not !finished do
      match peek () with
      | None -> raise (Parse_error "unterminated string literal")
      | Some '"' ->
        advance ();
        finished := true
      | Some '\\' -> (
        advance ();
        match peek () with
        | Some c ->
          Buffer.add_char buf c;
          advance ()
        | None -> raise (Parse_error "unterminated escape"))
      | Some c ->
        Buffer.add_char buf c;
        advance ()
    done;
    Buffer.contents buf
  in
  let read_atom () =
    let buf = Buffer.create 16 in
    let continue_ = ref true in
    while !continue_ do
      match peek () with
      | Some c when (not (is_ws c)) && c <> '(' && c <> ')' && c <> '"' ->
          Buffer.add_char buf c;
          advance ()
      | _ -> continue_ := false
    done;
    Buffer.contents buf
  in
  let rec read () =
    skip_ws ();
    match peek () with
    | Some '(' ->
        advance ();
        let items = ref [] in
        skip_ws ();
        let continue_ = ref true in
        while !continue_ do
          match peek () with
          | Some ')' ->
              advance ();
              continue_ := false
          | None -> raise (Parse_error "unterminated list, missing )")
          | _ ->
              items := read () :: !items;
              skip_ws ()
        done;
        List (List.rev !items)
    | Some '"' -> Atom (read_string ())
    | Some _ -> Atom (read_atom ())
    | None -> raise (Parse_error "unexpected end of input")
  in
  let result = read () in
  (result, !pos)

let find_sexps_in_line (line : string) : (int * int * sexp) list =
  let len = String.length line in
  let rec scan i acc =
    if i >= len then List.rev acc
    else if line.[i] = '(' then
      match parse_sexp_at line i with
      | sexp, next -> scan next ((i, next, sexp) :: acc)
      | exception Parse_error _ -> scan (i + 1) acc
    else scan (i + 1) acc
  in
  scan 0 []
