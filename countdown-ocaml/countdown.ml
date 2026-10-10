(* Generate a Countdown numbers round and work out whether it can be solved *)

let large_numbers = [| 25; 50; 75; 100 |]

(* Shuffle numbers in place with Fisher-Yates *)
let shuffle items =
  for i = Array.length items - 1 downto 1 do
    let j = Random.int (i + 1) in
    let t = items.(i) in
    items.(i) <- items.(j);
    items.(j) <- t
  done

(* Return a random target and a pool of six numbers with either one or two large numbers *)
let generate_round () =
  let target = 100 + Random.int 900 in
  let large_count = 1 + Random.int 2 in
  (* Hold two cards of each small number to match the game's deck *)
  let small = Array.init 20 (fun i -> (i mod 10) + 1) in
  shuffle small;
  (* Shuffle a copy since each large number appears only once in the game *)
  let large = Array.copy large_numbers in
  shuffle large;
  (target, Array.append (Array.sub small 0 (6 - large_count)) (Array.sub large 0 large_count))

let () =
  Random.self_init ();
  let target, pool = generate_round () in
  Printf.printf "Target: %d\n" target;
  Printf.printf "Pool:   %s\n" (String.concat " " (Array.to_list (Array.map string_of_int pool)));
  let value, expr = Solver.solve target pool in
  if value = target then begin
    Printf.printf "Solved: %s = %d\n" expr value;
    exit 0
  end;
  Printf.printf "No exact solution, closest is %s = %d (%d away)\n" expr value (abs (value - target));
  exit 1
