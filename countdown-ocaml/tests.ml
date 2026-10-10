(* Check the dealer in every mode and the solver against rounds with known answers *)

let failures = ref 0

let expect ok what =
  if not ok then begin
    Printf.printf "FAIL: %s\n" what;
    incr failures
  end

(* Return the large count of a dealt round after checking it keeps the rules of its mode *)
let check_round mode counts (target, pool) =
  let name = match mode with Round.Standard -> "standard" | Round.Cats -> "cats" | Round.Nasty -> "nasty" in
  let large = List.filter (fun n -> n > 10) (Array.to_list pool) in
  let k = List.length large in
  expect (target >= 100 && target <= 999 && Array.length pool = 6) (name ^ " deals a target and six numbers");
  expect (List.mem k counts) (name ^ " deals an allowed large count");
  expect (List.for_all (fun n -> Array.mem n (Round.large_numbers mode)) large) (name ^ " deals its own large cards");
  expect (List.length (List.sort_uniq compare large) = k) (name ^ " deals distinct large cards");
  (* Allow each small number at most twice since the deck holds two of each *)
  expect
    (List.for_all (fun s -> Array.fold_left (fun c n -> if n = s then c + 1 else c) 0 pool <= 2) (List.init 10 succ))
    (name ^ " deals each small number at most twice");
  k

let () =
  Random.init 1;
  List.iter
    (fun mode ->
      let counts = Round.allowed_counts mode in
      let seen = List.init 2000 (fun _ -> check_round mode counts (Round.generate_round mode)) in
      expect (List.sort_uniq compare seen = counts) "deals every allowed large count")
    [ Round.Standard; Round.Cats; Round.Nasty ];
  List.iter
    (fun mode ->
      for k = 0 to 4 do
        expect (check_round mode [ k ] (Round.generate_round ~large_count:k mode) = k) "deals a fixed large count"
      done)
    [ Round.Cats; Round.Nasty ];
  expect (Round.parse_args [] = Some (Round.Standard, None)) "parses no arguments";
  expect (Round.parse_args [ "nasty"; "4" ] = Some (Round.Nasty, Some 4)) "parses nasty 4";
  expect (Round.parse_args [ "cats"; "0" ] = Some (Round.Cats, Some 0)) "parses cats 0";
  List.iter
    (fun bad -> expect (Round.parse_args bad = None) ("rejects " ^ String.concat " " bad))
    [ [ "standard"; "3" ]; [ "cats"; "5" ]; [ "dogs" ]; [ "cats"; "1"; "2" ]; [ "cats"; "x" ] ];
  expect (Solver.solve 125 [| 1; 5; 7; 3; 75; 50 |] = (125, "75 + 50")) "finds simplest solution";
  expect (fst (Solver.solve 552 [| 8; 4; 2; 5; 100; 25 |]) = 552) "solves 552";
  let value, _ = Solver.solve 974 [| 8; 8; 6; 8; 25; 100 |] in
  expect (abs (value - 974) = 1) "reports closest when unsolvable";
  expect (Solver.solve 423 [| 6; 2; 2; 1; 1; 25 |] = (423, "(25 * ((6 * (2 + 1)) - 1)) - 2")) "uses every number";
  expect (Solver.solve 431 [| 3; 2; 3; 4; 2; 25 |] = (432, "((25 * 3) - 3) * (4 + 2)")) "prefers fewer numbers when closest";
  expect (Solver.solve 7 [| 7 |] = (7, "7")) "handles a single number";
  expect (Solver.solve 10 [| 3 |] = (3, "3")) "handles a single number that misses";
  expect (Solver.solve 12 [| 3; 4 |] = (12, "4 * 3")) "handles two numbers";
  expect (Solver.solve 999 [| 10; 10; 25; 50; 75; 100 |] = (999, "(((75 + 25) * 100) - 10) / 10")) "solves a four-large cats round";
  expect (Solver.solve 100 [| 1; 1; 2; 2; 3; 3 |] = (81, "(((2 + 1) * (2 + 1)) * 3) * 3")) "reports closest on a no-large cats round";
  expect (Solver.solve 999 [| 2; 3; 87; 62; 37; 12 |] = (999, "37 * ((87 / 3) - 2)")) "solves a nasty-cats round";
  if !failures > 0 then exit 1;
  print_endline "all tests passed"
