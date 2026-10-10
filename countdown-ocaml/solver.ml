(* Work out the simplest Countdown expression that hits a target or gets closest to it *)

(* Sort subsets with fewer values than this by insertion rather than by radix *)
let radix_min = 64

(* Hold values outside the OCaml heap so the garbage collector neither scans nor zeroes them *)
type ints = (int, Bigarray.int_elt, Bigarray.c_layout) Bigarray.Array1.t

let make_ints n : ints = Bigarray.Array1.create Bigarray.int Bigarray.c_layout n

let[@inline] dim (a : ints) = Bigarray.Array1.dim a

let[@inline] get (a : ints) i = Bigarray.Array1.unsafe_get a i

let[@inline] set (a : ints) i v = Bigarray.Array1.unsafe_set a i v

(* Hold the working memory of one solve *)
type state = {
  (* Keep every subset's sorted values back to back in one arena *)
  mutable vals : ints;
  mutable top : int;
  off : int array;
  len : int array;
  (* Hold the largest value each subset can make which bounds the bitset it touches *)
  max : int array;
  (* Hold one bit per value seen in the subset being built *)
  mutable seen : Bytes.t;
  (* Collect a subset's new values here before they are sorted into the arena *)
  mutable tmp : ints;
  mutable buf : ints;
  (* Hold the reciprocals of the right half's values for the split being built *)
  mutable inv : float array;
  (* Hold the digit counts of every radix pass *)
  counts : ints;
}

(* Track the best partner found so far while searching a split *)
type best = { mutable m : int; mutable p : int; mutable op : int }

(* Compare integers directly since the polymorphic versions call the runtime *)
let[@inline] imax (a : int) b = if a > b then a else b

let[@inline] imin (a : int) b = if a < b then a else b

let popcount m =
  let rec go m c = if m = 0 then c else go (m land (m - 1)) (c + 1) in
  go m 0

(* Return values holding the first used of the old ones with room for at least need *)
let grow (a : ints) used need =
  if need <= dim a then a
  else begin
    let cap = ref (imax 1024 (dim a)) in
    while !cap < need do
      cap := !cap * 2
    done;
    let b = make_ints !cap in
    if used > 0 then Bigarray.Array1.blit (Bigarray.Array1.sub a 0 used) (Bigarray.Array1.sub b 0 used);
    b
  end

(* Append a value to tmp and return the new end advancing only if the bitset shows it is new *)
let[@inline] emit seen tmp out v =
  let i = v lsr 3 and shift = v land 7 in
  let byte = Char.code (Bytes.unsafe_get seen i) in
  Bytes.unsafe_set seen i (Char.unsafe_chr (byte lor (1 lsl shift)));
  set tmp out v;
  out + 1 - ((byte lsr shift) land 1)

(* Emit every legal value from x and y under Countdown rules where x is at least y and inv is 1/y *)
let[@inline] ops seen tmp out x y inv =
  let out = emit seen tmp out (x + y) in
  (* Emit zero for equal operands since the bitset already marks it and drops it *)
  let out = emit seen tmp out (x - y) in
  (* Skip multiplying and dividing by one as they never produce a new value *)
  if y <> 1 then begin
    let out = emit seen tmp out (x * y) in
    (* Round the product with the reciprocal which is exact for every value a subset can make *)
    let q = int_of_float ((float_of_int x *. inv) +. 0.5) in
    emit seen tmp out (if q * y = x then q else 0)
  end
  else out

(* Sort the first count values of src below 2^(9 * passes) into dst at start using buf as scratch *)
let radix_sort counts passes src buf dst start count =
  for d = 0 to (512 * passes) - 1 do
    set counts d 0
  done;
  (* Count every digit of every value in one pass *)
  for i = 0 to count - 1 do
    let v = get src i in
    for p = 0 to passes - 1 do
      let d = (p lsl 9) + ((v lsr (9 * p)) land 511) in
      set counts d (get counts d + 1)
    done
  done;
  (* Turn the counts into starting positions with the last pass placing values straight into dst *)
  for p = 0 to passes - 1 do
    let total = ref (if p = passes - 1 then start else 0) in
    for d = p lsl 9 to (p lsl 9) + 511 do
      let k = get counts d in
      set counts d !total;
      total := !total + k
    done
  done;
  (* Alternate between src and buf so the last pass lands in dst *)
  let from = ref src and spare = ref buf in
  for p = 0 to passes - 1 do
    let f = !from and t = if p = passes - 1 then dst else !spare in
    let shift = 9 * p and base = p lsl 9 in
    for i = 0 to count - 1 do
      let v = get f i in
      let d = base + ((v lsr shift) land 511) in
      let at = get counts d in
      set counts d (at + 1);
      set t at v
    done;
    from := t;
    spare := f
  done

(* Store the sorted values a subset can make in the arena *)
let build s mask =
  let seen = s.seen in
  (* Mark zero as seen so inexact divisions and equal differences never become values *)
  Bytes.unsafe_set seen 0 '\001';
  let out = ref 0 in
  let left = ref ((mask - 1) land mask) in
  while !left <> 0 do
    let l = !left in
    let r = mask lxor l in
    (* Visit each split once rather than once per ordering *)
    if l < r then begin
      let ol = s.off.(l) and nl = s.len.(l) and orr = s.off.(r) and nr = s.len.(r) in
      (* Reserve room for every pair's results plus the one slot each store may write past the end *)
      s.tmp <- grow s.tmp !out (!out + imin (4 * nl * nr) s.max.(mask) + 1);
      let tmp = s.tmp and vals = s.vals and inv = s.inv in
      (* Invert each right value once per split rather than once per pair *)
      for j = 0 to nr - 1 do
        Array.unsafe_set inv j (1.0 /. float_of_int (get vals (orr + j)))
      done;
      let o = ref !out in
      for i = 0 to nl - 1 do
        let a = get vals (ol + i) in
        let j = ref 0 in
        (* Pair a with right values up to it first so the larger operand is known without testing *)
        while !j < nr && get vals (orr + !j) <= a do
          o := ops seen tmp !o a (get vals (orr + !j)) (Array.unsafe_get inv !j);
          incr j
        done;
        let ia = 1.0 /. float_of_int a in
        while !j < nr do
          o := ops seen tmp !o (get vals (orr + !j)) a ia;
          incr j
        done
      done;
      out := !o
    end;
    left := (l - 1) land mask
  done;
  let count = !out in
  s.vals <- grow s.vals s.top (s.top + count);
  let tmp = s.tmp and vals = s.vals and top = s.top in
  (* Clear only the bytes this subset set so the bitset is ready for the next one *)
  Bytes.unsafe_set seen 0 '\000';
  for i = 0 to count - 1 do
    Bytes.unsafe_set seen (get tmp i lsr 3) '\000'
  done;
  if count < radix_min then
    for i = 0 to count - 1 do
      let v = get tmp i in
      let k = ref i in
      while !k > 0 && get vals (top + !k - 1) > v do
        set vals (top + !k) (get vals (top + !k - 1));
        decr k
      done;
      set vals (top + !k) v
    done
  else begin
    s.buf <- grow s.buf 0 count;
    (* Skip the digits no value of this subset can reach *)
    let passes = if s.max.(mask) < 1 lsl 9 then 1 else if s.max.(mask) < 1 lsl 18 then 2 else 3 in
    radix_sort s.counts passes tmp s.buf vals top count
  end;
  s.off.(mask) <- top;
  s.len.(mask) <- count;
  s.top <- top + count

(* Return whether count sorted values from off include v *)
let[@inline] lookup vals off count v =
  if count = 0 || v < get vals off || v > get vals (off + count - 1) then false
  else begin
    let base = ref off and n = ref count in
    (* Halve the range with arithmetic so unpredictable comparisons cost no mispredicted branch *)
    while !n > 1 do
      let half = !n lsr 1 in
      base := !base + ((get vals (!base + half) - v - 1) asr 62 land half);
      n := !n - half
    done;
    get vals !base = v
  end

(* Keep partner m of p with its operator if it is lower than the best so far and the other half holds it *)
let[@inline] try_partner best vals oo on p m op =
  if m > 0 && m < best.m && lookup vals oo on m then begin
    best.m <- m;
    best.p <- p;
    best.op <- op
  end

(* Pack a way of making a value as split, operator and the values of both halves into one integer *)
let[@inline] pack l op a b = (l lsl 56) lor (op lsl 54) lor (a lsl 27) lor b

(* Return the first way building makes v from a subset packed by pack or -1 when it cannot *)
let find_way s mask v =
  let vals = s.vals in
  let best = { m = max_int; p = 0; op = -1 } in
  let result = ref (-1) in
  let left = ref ((mask - 1) land mask) in
  while !result < 0 && !left <> 0 do
    let l = !left in
    let r = mask lxor l in
    (* Visit splits in the same order as building so the same origin wins *)
    if l < r then begin
      let ol = s.off.(l) and nl = s.len.(l) and orr = s.off.(r) and nr = s.len.(r) in
      (* Loop over the smaller half and search the larger for the earliest pair building would make *)
      let scan_left = nl <= nr in
      let so = if scan_left then ol else orr and sn = if scan_left then nl else nr in
      let oo = if scan_left then orr else ol and on = if scan_left then nr else nl in
      best.m <- max_int;
      best.op <- -1;
      let i = ref 0 in
      (* Stop at the first left value with a partner since left values ascend *)
      while !i < sn && not (scan_left && best.op >= 0) do
        let p = get vals (so + !i) in
        (* Try every partner in operator order so an equal later one never wins *)
        if v > p then try_partner best vals oo on p (v - p) 0;
        if p > v then try_partner best vals oo on p (p - v) 1;
        try_partner best vals oo on p (p + v) 1;
        if p <> 1 && 2 * p <= v && v mod p = 0 then try_partner best vals oo on p (v / p) 2;
        if p >= 2 * v && p mod v = 0 then try_partner best vals oo on p (p / v) 3;
        if p <> 1 then try_partner best vals oo on p (p * v) 3;
        incr i
      done;
      if best.op >= 0 then
        result := if scan_left then pack l best.op best.p best.m else pack l best.op best.m best.p
    end;
    left := (l - 1) land mask
  done;
  !result

let op_char = "+-*/"

(* Write the expression for a value of a subset following its first way back to the pool *)
let rec render s b mask v bracket =
  if mask land (mask - 1) = 0 then Buffer.add_string b (string_of_int v)
  else begin
    let way = find_way s mask v in
    let l = way lsr 56 and op = (way lsr 54) land 3 in
    let a = (way lsr 27) land 0x7FFFFFF and bv = way land 0x7FFFFFF in
    let r = mask lxor l in
    let lm, x, sm, y = if a >= bv then (l, a, r, bv) else (r, bv, l, a) in
    if bracket then Buffer.add_char b '(';
    render s b lm x true;
    Buffer.add_char b ' ';
    Buffer.add_char b op_char.[op];
    Buffer.add_char b ' ';
    render s b sm y true;
    if bracket then Buffer.add_char b ')'
  end

(* Return the closest value the whole pool makes preferring the lower on equal distance with its distance *)
let whole_closest s full target =
  let vals = s.vals in
  let whole_d = ref max_int and whole_v = ref 0 in
  let left = ref ((full - 1) land full) in
  while !left <> 0 do
    let l = !left in
    let r = full lxor l in
    if l < r then
      for i = s.off.(l) to s.off.(l) + s.len.(l) - 1 do
        for j = s.off.(r) to s.off.(r) + s.len.(r) - 1 do
          let a = get vals i and b = get vals j in
          let x = imax a b and y = imin a b in
          (* Keep a value if it is closer or equally close and lower to break ties the same way every run *)
          let check v =
            let d = abs (v - target) in
            if d < !whole_d || (d = !whole_d && v < !whole_v) then begin
              whole_d := d;
              whole_v := v
            end
          in
          check (x + y);
          if x > y then check (x - y);
          if y <> 1 then begin
            check (x * y);
            if x mod y = 0 then check (x / y)
          end
        done
      done;
    left := (l - 1) land full
  done;
  (!whole_v, !whole_d)

(* Return the simplest expression that hits the target or gets closest to it with its value *)
let solve target pool =
  let n = Array.length pool in
  let full = (1 lsl n) - 1 in
  let s =
    {
      vals = make_ints 4096;
      top = 0;
      off = Array.make (full + 1) 0;
      len = Array.make (full + 1) 0;
      max = Array.make (full + 1) 0;
      seen = Bytes.empty;
      tmp = make_ints 4096;
      buf = make_ints 0;
      inv = [||];
      counts = make_ints 1536;
    }
  in
  (* Work out each subset's largest value since subtracting and dividing never exceed the larger operand *)
  let largest = Array.make (n + 1) 0 in
  for mask = 1 to full do
    if mask land (mask - 1) = 0 then s.max.(mask) <- pool.(popcount (mask - 1))
    else begin
      let left = ref ((mask - 1) land mask) in
      while !left <> 0 do
        let a = s.max.(!left) and b = s.max.(mask lxor !left) in
        s.max.(mask) <- imax s.max.(mask) (imax (a * b) (a + b));
        left := (!left - 1) land mask
      done
    end;
    let size = popcount mask in
    largest.(size) <- imax largest.(size) s.max.(mask)
  done;
  (* Refuse values too large to pack into the 27 bits radix sorting and way packing allow *)
  if n > 1 && largest.(n - 1) >= 1 lsl 27 then invalid_arg "Solver.solve: pool numbers too large";
  (* Store each pool number as a one-number subset keeping the lowest that hits the target *)
  let best_mask = ref 0 in
  for i = n - 1 downto 0 do
    set s.vals i pool.(i);
    s.off.(1 lsl i) <- i;
    s.len.(1 lsl i) <- 1;
    if pool.(i) = target then best_mask := 1 lsl i
  done;
  s.top <- n;
  (* List subsets by size then mask so each size is a contiguous run *)
  let order = Array.make full 0 and first = Array.make (n + 2) 0 in
  for mask = 1 to full do
    let k = popcount mask + 1 in
    first.(k) <- first.(k) + 1
  done;
  for size = 1 to n + 1 do
    first.(size) <- first.(size) + first.(size - 1)
  done;
  let fill = Array.copy first in
  for mask = 1 to full do
    let k = popcount mask in
    order.(fill.(k)) <- mask;
    fill.(k) <- fill.(k) + 1
  done;
  (* Work through subsets smallest first stopping at the first size that hits the target *)
  let size = ref 2 in
  while !best_mask = 0 && !size <= n do
    (* Keep the lowest matching subset of this size to break ties the same way every run *)
    let k = ref first.(!size) in
    while !best_mask = 0 && !k < first.(!size + 1) do
      if find_way s order.(!k) target >= 0 then best_mask := order.(!k);
      incr k
    done;
    (* Skip building the whole pool's values since no larger subset is made from them *)
    if !best_mask = 0 && !size < n then begin
      let bytes = (largest.(!size) lsr 3) + 1 in
      if bytes > Bytes.length s.seen then s.seen <- Bytes.make bytes '\000';
      let biggest = ref 0 in
      for mask = 1 to full do
        biggest := imax !biggest s.len.(mask)
      done;
      if !biggest > Array.length s.inv then s.inv <- Array.make (2 * !biggest) 0.0;
      for k = first.(!size) to first.(!size + 1) - 1 do
        build s order.(k)
      done
    end;
    incr size
  done;
  let value =
    if !best_mask <> 0 then target
    else begin
      (* Rank by distance from the target then by how many numbers are used so the simplest answer wins *)
      let best_d = ref max_int and best_used = ref max_int and best_v = ref 0 in
      (* Include the lone number of a one-number pool since there is no larger subset to fall back to *)
      for mask = 1 to if n = 1 then full else full - 1 do
        let used = popcount mask in
        for i = s.off.(mask) to s.off.(mask) + s.len.(mask) - 1 do
          let v = get s.vals i in
          let d = abs (v - target) in
          if d < !best_d || (d = !best_d && used < !best_used) then begin
            best_d := d;
            best_used := used;
            best_v := v;
            best_mask := mask
          end
        done
      done;
      (* Fall back to the whole pool only when it gets strictly closer as it uses the most numbers *)
      if n > 1 then begin
        let whole_v, whole_d = whole_closest s full target in
        if whole_d < !best_d then begin
          best_v := whole_v;
          best_mask := full
        end
      end;
      !best_v
    end
  in
  let b = Buffer.create 64 in
  (* Render without outer brackets which matches stripping them from the bracketed form *)
  render s b !best_mask value false;
  (value, Buffer.contents b)
