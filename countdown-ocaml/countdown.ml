(* Generate a Countdown numbers round and work out whether it can be solved *)

let () =
  Random.self_init ();
  let mode, large_count =
    match Round.parse_args (List.tl (Array.to_list Sys.argv)) with
    | Some parsed -> parsed
    | None ->
        prerr_endline Round.usage;
        exit 2
  in
  let target, pool = Round.generate_round ?large_count mode in
  Printf.printf "Target: %d\n" target;
  Printf.printf "Pool:   %s\n" (String.concat " " (Array.to_list (Array.map string_of_int pool)));
  let value, expr = Solver.solve target pool in
  if value = target then begin
    Printf.printf "Solved: %s = %d\n" expr value;
    exit 0
  end;
  Printf.printf "No exact solution, closest is %s = %d (%d away)\n" expr value (abs (value - target));
  exit 1
