(* Time the OCaml solver over a file of rounds and write each answer as value tab expression *)

let () =
  let rounds_path = Sys.argv.(1) and out_path = Sys.argv.(2) in
  let reps = if Array.length Sys.argv > 3 then int_of_string Sys.argv.(3) else 1 in
  let ic = open_in rounds_path in
  let rounds = ref [] in
  (try
     while true do
       let line = input_line ic in
       match List.filter (( <> ) "") (String.split_on_char ' ' (String.trim line)) with
       | target :: pool -> rounds := (int_of_string target, Array.of_list (List.map int_of_string pool)) :: !rounds
       | [] -> ()
     done
   with End_of_file -> ());
  close_in ic;
  let rounds = Array.of_list (List.rev !rounds) in
  let count = Array.length rounds in
  let answers = Array.make count (0, "") in
  let start = Unix.gettimeofday () in
  for _ = 1 to reps do
    Array.iteri (fun i (target, pool) -> answers.(i) <- Solver.solve target pool) rounds
  done;
  let stop = Unix.gettimeofday () in
  Printf.eprintf "%.4f ms/round\n" ((stop -. start) *. 1000. /. float_of_int count /. float_of_int reps);
  let oc = open_out out_path in
  Array.iteri (fun i (v, e) -> Printf.fprintf oc (if i = 0 then "%d\t%s" else "\n%d\t%s") v e) answers;
  close_out oc
