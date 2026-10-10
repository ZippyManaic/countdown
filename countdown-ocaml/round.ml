(* Deal Countdown rounds in each mode and read the mode from the command line *)

type mode = Standard | Cats | Nasty

let usage = "usage: countdown [standard|cats|nasty] [LARGE]"

(* Return the large cards of a mode, with nasty-cats using the cards of the 2010 specials *)
let large_numbers = function Nasty -> [| 12; 37; 62; 87 |] | Standard | Cats -> [| 25; 50; 75; 100 |]

(* Return the large counts a mode allows *)
let allowed_counts = function Standard -> [ 1; 2 ] | Cats | Nasty -> [ 0; 1; 2; 3; 4 ]

(* Shuffle numbers in place with Fisher-Yates *)
let shuffle items =
  for i = Array.length items - 1 downto 1 do
    let j = Random.int (i + 1) in
    let t = items.(i) in
    items.(i) <- items.(j);
    items.(j) <- t
  done

(* Return a random target and six numbers with one or two large in standard mode and none to four otherwise *)
let generate_round ?large_count mode =
  let target = 100 + Random.int 900 in
  let large_count =
    match large_count with
    | Some k -> k
    | None -> if mode = Standard then 1 + Random.int 2 else Random.int 5
  in
  (* Hold two cards of each small number to match the game's deck *)
  let small = Array.init 20 (fun i -> (i mod 10) + 1) in
  shuffle small;
  (* Shuffle a copy since each large number appears only once in the game *)
  let large = Array.copy (large_numbers mode) in
  shuffle large;
  (target, Array.append (Array.sub small 0 (6 - large_count)) (Array.sub large 0 large_count))

let parse_mode = function
  | "standard" -> Some Standard
  | "cats" -> Some Cats
  | "nasty" -> Some Nasty
  | _ -> None

(* Return the mode and fixed large count from the command line, or None when the arguments are invalid *)
let parse_args args =
  match args with
  | [] -> Some (Standard, None)
  | [ m ] -> Option.map (fun mode -> (mode, None)) (parse_mode m)
  | [ m; n ] -> (
      match parse_mode m with
      | Some mode -> (
          match List.find_opt (fun k -> string_of_int k = n) (allowed_counts mode) with
          | Some k -> Some (mode, Some k)
          | None -> None)
      | None -> None)
  | _ -> None
