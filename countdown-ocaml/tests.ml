(* Check the solver against rounds with known answers *)

let failures = ref 0

let expect ok what =
  if not ok then begin
    Printf.printf "FAIL: %s\n" what;
    incr failures
  end

let () =
  expect (Solver.solve 125 [| 1; 5; 7; 3; 75; 50 |] = (125, "75 + 50")) "finds simplest solution";
  expect (fst (Solver.solve 552 [| 8; 4; 2; 5; 100; 25 |]) = 552) "solves 552";
  let value, _ = Solver.solve 974 [| 8; 8; 6; 8; 25; 100 |] in
  expect (abs (value - 974) = 1) "reports closest when unsolvable";
  expect (Solver.solve 423 [| 6; 2; 2; 1; 1; 25 |] = (423, "(25 * ((6 * (2 + 1)) - 1)) - 2")) "uses every number";
  expect (Solver.solve 431 [| 3; 2; 3; 4; 2; 25 |] = (432, "((25 * 3) - 3) * (4 + 2)")) "prefers fewer numbers when closest";
  expect (Solver.solve 7 [| 7 |] = (7, "7")) "handles a single number";
  expect (Solver.solve 10 [| 3 |] = (3, "3")) "handles a single number that misses";
  expect (Solver.solve 12 [| 3; 4 |] = (12, "4 * 3")) "handles two numbers";
  if !failures > 0 then exit 1;
  print_endline "all tests passed"
