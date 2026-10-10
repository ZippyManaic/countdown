defmodule CountdownPar.Solver.Tables do
  @moduledoc """
  Work out the subset and search tables that depend only on the pool size so the solver can embed them as constants
  """

  import Bitwise

  # List every subset mask of each size in ascending order
  def masks_by_size(n, full) do
    groups = Enum.group_by(1..full//1, &popcount/1)
    List.to_tuple(for size <- 0..n, do: Map.get(groups, size, []))
  end

  # List each subset's splits as left and right halves in the order the reference visits them
  def split_table(full) do
    List.to_tuple(for mask <- 0..full, do: splits_of(mask))
  end

  # List the shared search tasks in the order the sequential search would try them with whole masks for the cheapest size
  def task_table(n) do
    full = (1 <<< n) - 1
    by_size = masks_by_size(n, full)
    splits = split_table(full)
    first = max(n - 2, 2)

    tasks =
      for size <- first..n//1, mask <- elem(by_size, size), task <- tasks_of(size == first, mask, splits) do
        task
      end

    List.to_tuple(tasks)
  end

  # Search a mask of the cheapest size as one task since its splits take well under a microsecond each
  defp tasks_of(true, mask, _splits), do: [{mask, 0, 0}]
  defp tasks_of(false, mask, splits), do: for({l, r} <- elem(splits, mask), do: {mask, l, r})

  defp splits_of(0), do: []

  defp splits_of(mask), do: splits_from(mask - 1 &&& mask, mask, [])

  defp splits_from(0, _mask, acc), do: Enum.reverse(acc)

  defp splits_from(left, mask, acc) do
    right = bxor(mask, left)
    acc = if left < right, do: [{left, right} | acc], else: acc
    splits_from(left - 1 &&& mask, mask, acc)
  end

  defp popcount(0), do: 0
  defp popcount(m), do: (m &&& 1) + popcount(m >>> 1)
end

defmodule CountdownPar.Solver do
  @moduledoc """
  Work out the simplest Countdown expression that hits a target or gets closest to it sharing the largest searches across worker processes
  """

  import Bitwise

  alias CountdownPar.Solver.Tables

  # Search this far either side of the target before building everything for a full closest search
  @near_limit 8
  # Search outwards only for full pools since smaller pools miss by more and build their subsets cheaply
  @near_from 6
  # Swap the small subsets between processes only with at least this many since one helper builds them as fast alone
  @swap_from 3
  # Share the search only for pools large enough to defer two sizes since smaller pools solve in microseconds
  @share_from 5

  # Lay out each round's shared counters as next task then best task then phase before the per-task slots
  @next 1
  @best 2
  @phase 3
  @slots 3
  # Tell the workers whether the round is over or needs the next size built for a closest search
  @running 0
  @finished 1
  @build_more 2
  # Cancel a round by marking its best task as before every task
  @cancelled -1
  # Give each task a done flag and four result slots for the left mask, both values and the operator
  @per_task 5
  # Poll an idle mailbox this many times between rounds which comes to a few milliseconds
  @spins 50_000
  # Mark the best task as none with a value above any task index
  @no_task 1_000_000

  @compile {:inline, member?: 2, partner: 3, first_of: 5, keep: 3}

  # Embed the subset tables for every pool of up to six numbers since they depend only on the pool size
  @max_pool 6
  # Give each size a shared build might cover its own claim counter after the per-task slots
  @build_slots @max_pool
  @by_size List.to_tuple(for n <- 0..@max_pool, do: Tables.masks_by_size(n, (1 <<< n) - 1))
  @splits Tables.split_table((1 <<< @max_pool) - 1)
  @tasks List.to_tuple(for n <- 0..@max_pool, do: Tables.task_table(n))

  @doc """
  Return the simplest expression that hits the target or gets closest to it with its value
  """
  def solve(target, pool) do
    n = length(pool)
    full = (1 <<< n) - 1

    {by_size, splits} =
      if n <= @max_pool,
        do: {elem(@by_size, n), @splits},
        else: {Tables.masks_by_size(n, full), Tables.split_table(full)}

    st = {base_reach(pool, full), splits}

    {value, mask, way, st} =
      case Enum.find_index(pool, &(&1 == target)) do
        nil -> grow_shared(st, by_size, n, target, full, pool)
        i -> {target, 1 <<< i, nil, st}
      end

    {value, IO.iodata_to_binary(render(st, mask, value, way, true))}
  end

  # Share the search with the workers for pools large enough to repay it and plain search otherwise
  defp grow_shared(st, by_size, n, target, full, pool) do
    # Share only pools whose values fit the 64-bit shared counters since a way holds two values
    if n >= @share_from and n <= @max_pool and Enum.reduce(pool, 1, &((&1 + 1) * &2)) < 1 <<< 62 do
      # Keep this process on the first scheduler while sharing since every other scheduler holds a worker
      bound = :erlang.process_flag(:scheduler, 1)
      found = grow(st, by_size, 2, n, target, full, workers(pool, target))
      :erlang.process_flag(:scheduler, bound)
      found
    else
      grow(st, by_size, 2, n, target, full, nil)
    end
  end

  # Hold each subset's values as an ascending list for scanning and a tuple for binary search
  defp base_reach(pool, full) do
    Enum.reduce(Enum.with_index(pool), :erlang.make_tuple(full + 1, nil), fn {p, i}, reach ->
      put_elem(reach, 1 <<< i, {[p], {p}, 1})
    end)
  end

  # Search each size for the target and build its subsets only when none of them hits it
  defp grow(st, by_size, size, n, target, full, workers) when size <= n do
    masks = elem(by_size, size)

    cond do
      # Hand the deferred sizes to the shared search once every size below them is built
      workers != nil and size == n - 2 ->
        shared(st, by_size, n, target, full, workers)

      true ->
        case Enum.find(masks, &(way(st, &1, target) != nil)) do
          nil when size == n ->
            missed(st, by_size, n, target, full)

          # Share the build of the last size below the shared search with the workers
          nil when workers != nil and size == n - 3 ->
            {pids, a, _pool, peers} = workers

            st =
              if length(pids) + 1 < @swap_from,
                do: build(st, masks),
                else: shared_build(st, a, List.to_tuple(masks), peers, size)

            grow(st, by_size, size + 1, n, target, full, workers)

          nil ->
            st = if size in deferred(n), do: st, else: build(st, masks)
            grow(st, by_size, size + 1, n, target, full, workers)

          mask ->
            if workers != nil, do: cancel(workers)
            {target, mask, nil, st}
        end
    end
  end

  defp grow(st, by_size, _size, n, target, full, _workers), do: closest(st, by_size, n, target, full)

  # Build what the closest search needs once no subset of any size hits the target
  defp missed({reach, _} = st, by_size, n, target, full) do
    st =
      Enum.reduce(deferred(n) -- [n - 1], st, fn k, st ->
        if elem(reach, hd(elem(by_size, k))) == nil, do: build(st, elem(by_size, k)), else: st
      end)

    case n >= @near_from && near(st, by_size, n, target, 1) do
      {v, mask, st} -> {v, mask, nil, st}
      _ -> closest(build_all(st, by_size, n), by_size, n, target, full)
    end
  end

  # Search every deferred size together with the workers and keep the earliest task that hits the target
  defp shared(st, by_size, n, target, full, {_pids, a, _pool, _peers} = workers) do
    tasks = elem(@tasks, n)
    total = tuple_size(tasks)
    run_tasks(a, tasks, total, st, target)
    best = settle(a, total)
    :atomics.put(a, @best, @cancelled)

    if best < total do
      :atomics.put(a, @phase, @finished)
      {mask, _, _} = elem(tasks, best)
      base = @slots + total + best * 4
      way = {:atomics.get(a, base + 1), :atomics.get(a, base + 2), :atomics.get(a, base + 3), :atomics.get(a, base + 4)}
      {target, mask, way, st}
    else
      # Build the next size with the workers since the closest search needs all of its values
      {pids, _, _, peers} = workers

      st =
        if pids == [] do
          build(st, elem(by_size, n - 2))
        else
          :atomics.put(a, @phase, @build_more)
          shared_build(st, a, List.to_tuple(elem(by_size, n - 2)), peers, n - 2)
        end

      missed(st, by_size, n, target, full)
    end
  end

  # Wait until every task before the best has finished since only then can no earlier task still hit
  defp settle(a, total), do: settle(a, total, 0)

  # Reread the best on every poll since a claimer skips any task at or after a best lowered after an earlier read
  defp settle(a, total, i) do
    best = min(:atomics.get(a, @best), total)

    cond do
      i >= best -> best
      :atomics.get(a, @slots + i + 1) == 1 -> settle(a, total, i + 1)
      true -> settle(a, total, i)
    end
  end

  # Claim tasks in order and run each one until none is left or the best already beats it
  defp run_tasks(a, tasks, total, st, target) do
    i = :atomics.add_get(a, @next, 1) - 1

    if i < total and i < :atomics.get(a, @best) do
      {reach, _} = st

      found =
        case elem(tasks, i) do
          {mask, 0, 0} -> way(st, mask, target)
          {_mask, l, r} -> split_way(reach, st, l, r, target)
        end

      case found do
        nil ->
          :ok

        {wl, x, y, op} ->
          base = @slots + total + i * 4
          :atomics.put(a, base + 1, wl)
          :atomics.put(a, base + 2, x)
          :atomics.put(a, base + 3, y)
          :atomics.put(a, base + 4, op)
          lower_best(a, i)
      end

      :atomics.put(a, @slots + i + 1, 1)
      run_tasks(a, tasks, total, st, target)
    end
  end

  # Stop the workers on a round this process has already answered
  defp cancel({_pids, a, _pool, _peers}) do
    :atomics.put(a, @best, @cancelled)
    :atomics.put(a, @phase, @finished)
  end

  # Wait for this process to learn whether the round is over or needs another size built
  defp await_phase(a) do
    case :atomics.get(a, @phase) do
      @running ->
        :erlang.yield()
        await_phase(a)

      phase ->
        phase
    end
  end

  # Build the claimed subsets of one size then swap them with every other process until all of them are held
  defp shared_build({reach, splits}, a, masks, peers, size) do
    counter = @slots + tuple_size(elem(@tasks, @max_pool)) * @per_task + size
    mine = claim_builds(a, counter, masks, reach, splits, [])

    if mine != [] do
      # Send one encoded binary since the virtual machine shares large binaries rather than copying them
      bin = :erlang.term_to_binary(mine)
      me = self()
      Enum.each(peers, fn p -> if p != me, do: send(p, {:built, a, size, bin}) end)
    end

    reach = merge(reach, mine)
    {collect(reach, a, size, tuple_size(masks) - length(mine)), splits}
  end

  # Claim subsets in turn and build each one until none is left
  defp claim_builds(a, counter, masks, reach, splits, built) do
    j = :atomics.add_get(a, counter, 1) - 1

    if j < tuple_size(masks) do
      mask = elem(masks, j)
      claim_builds(a, counter, masks, reach, splits, [{mask, values_of(reach, splits, mask)} | built])
    else
      built
    end
  end

  # Receive the subsets of one size the other processes built until none is missing
  defp collect(reach, _a, _size, 0), do: reach

  defp collect(reach, a, size, missing) do
    receive do
      {:built, ^a, ^size, bin} ->
        parts = :erlang.binary_to_term(bin)
        collect(merge(reach, parts), a, size, missing - length(parts))
    end
  end

  defp merge(reach, parts) do
    Enum.reduce(parts, reach, fn {mask, values}, reach ->
      put_elem(reach, mask, {values, List.to_tuple(values), length(values)})
    end)
  end

  # Drop subsets sent for rounds this process answered before the workers finished building
  defp drain do
    receive do
      {:built, _, _, _} -> drain()
    after
      0 -> :ok
    end
  end

  # Lower the shared best task to this one unless an earlier task already holds it
  defp lower_best(a, i) do
    best = :atomics.get(a, @best)

    if i < best and :atomics.compare_exchange(a, @best, best, i) != :ok,
      do: lower_best(a, i),
      else: :ok
  end

  # Return the pool of workers with a fresh set of shared counters for this round
  defp workers(pool, target) do
    drain()
    a = :atomics.new(@slots + tuple_size(elem(@tasks, @max_pool)) * @per_task + @build_slots, [])
    :atomics.put(a, @best, @no_task)
    pids = pool_pids()
    workers = {pids, a, pool, [self() | pids]}
    # Start the workers rebuilding the sizes they need while this process searches and builds them too
    dispatch(workers, target)
    workers
  end

  # Send each worker the round so it rebuilds the sizes below the shared ones and joins the search
  defp dispatch({pids, a, pool, peers}, target) do
    Enum.each(pids, &send(&1, {:round, a, target, pool, peers}))
  end

  # Return the persistent workers starting them on first use with one per extra scheduler
  defp pool_pids do
    case :persistent_term.get({__MODULE__, :pool}, nil) do
      nil -> :global.trans({{__MODULE__, :pool}, self()}, &start_pool/0)
      pids -> pids
    end
  end

  defp start_pool do
    case :persistent_term.get({__MODULE__, :pool}, nil) do
      nil ->
        threads = String.to_integer(System.get_env("COUNTDOWN_THREADS", "8"))
        # Never run more spinning workers than processors this process may use since spinners would starve one another
        cpus = :erlang.system_info(:logical_processors_available)
        cpus = if is_integer(cpus), do: cpus, else: threads
        count = max(Enum.min([threads, :erlang.system_info(:schedulers_online), cpus]), 1)
        # Bind each worker to its own scheduler so workers never queue behind one another
        pids = for s <- 2..count//1, do: :erlang.spawn_opt(&worker/0, [{:scheduler, s}])
        :persistent_term.put({__MODULE__, :pool}, pids)
        pids

      pids ->
        pids
    end
  end

  # Wait for a round then rebuild the sizes below the shared search and claim tasks until none is left
  defp worker, do: worker(@spins)

  # Poll the mailbox for a while before blocking since a sleeping scheduler takes microseconds to wake
  defp worker(0) do
    receive do
      {:round, _, _, _, _} = round -> work(round)
    end
  end

  # Leave subsets other workers send for the next round in the mailbox until that round starts
  defp worker(spins) do
    receive do
      {:round, _, _, _, _} = round -> work(round)
    after
      0 ->
        # Let any other process queued on this scheduler run between polls
        :erlang.yield()
        worker(spins - 1)
    end
  end

  defp work(round) do
    case round do
      {:round, a, target, pool, peers} ->
        n = length(pool)
        full = (1 <<< n) - 1
        st = {base_reach(pool, full), @splits}
        by_size = elem(@by_size, n)
        # Rebuild the small sizes here since they take less time than receiving them
        st = Enum.reduce(2..(n - 4)//1, st, fn k, st -> build(st, elem(by_size, k)) end)
        masks = elem(by_size, n - 3)

        st =
          if length(peers) < @swap_from,
            do: build(st, masks),
            else: shared_build(st, a, List.to_tuple(masks), peers, n - 3)

        run_tasks(a, elem(@tasks, n), tuple_size(elem(@tasks, n)), st, target)

        # Help build the next size when no subset hits the target since the closest search needs it
        if await_phase(a) == @build_more,
          do: shared_build(st, a, List.to_tuple(elem(by_size, n - 2)), peers, n - 2)

        worker()
    end
  end

  # Build any size still deferred since the full closest search needs every value of every subset
  defp build_all(st, by_size, n) do
    Enum.reduce(deferred(n), st, fn k, {reach, _} = st ->
      if elem(reach, hd(elem(by_size, k))) == nil, do: build(st, elem(by_size, k)), else: st
    end)
  end

  # Search outwards from the target one distance at a time ranking by size then mask then value
  defp near(_st, _by_size, _n, _target, d) when d > @near_limit, do: nil

  defp near(st, by_size, n, target, d) do
    values = if target - d >= 1, do: [target - d, target + d], else: [target + d]

    Enum.find_value(1..n, fn k ->
      Enum.find_value(elem(by_size, k), fn mask ->
        Enum.find_value(values, fn v -> if holds?(st, mask, v), do: {v, mask, st} end)
      end)
    end) || near(st, by_size, n, target, d + 1)
  end

  # Return whether a subset can make a value looking it up when built and searching when not
  defp holds?({reach, _} = st, mask, v) do
    case elem(reach, mask) do
      nil -> way(st, mask, v) != nil
      set -> member?(set, v)
    end
  end

  # Return the subset sizes left unbuilt until a search needs them since larger subsets can search them by nesting
  defp deferred(n) when n >= 5, do: [n - 2, n - 1]
  defp deferred(n) when n >= 3, do: [n - 1]
  defp deferred(_n), do: []

  # Store the sorted distinct values of every subset of one size
  defp build({reach, splits}, masks) do
    reach =
      Enum.reduce(masks, reach, fn mask, acc ->
        values = values_of(reach, splits, mask)
        put_elem(acc, mask, {values, List.to_tuple(values), length(values)})
      end)

    {reach, splits}
  end

  # Return the sorted distinct values one subset makes from the built subsets below it
  defp values_of(reach, splits, mask) do
    made =
      Enum.reduce(elem(splits, mask), [], fn {l, r}, made ->
        {ls, _, _} = elem(reach, l)
        {rs, _, _} = elem(reach, r)
        pairs(ls, rs, made)
      end)

    :lists.usort(made)
  end

  # Prepend every legal result of each left value with each right value
  defp pairs([], _rs, made), do: made
  defp pairs([a | as], rs, made), do: pairs(as, rs, pair_row(a, rs, made))

  # Combine one left value with the ascending right values knowing which operand is larger
  defp pair_row(_a, [], made), do: made
  defp pair_row(a, [b | bs], made) when b <= a, do: pair_row(a, bs, ops(a, b, made))
  defp pair_row(a, bs, made), do: pair_row_above(a, bs, made)

  # Combine one left value with right values that all exceed it
  defp pair_row_above(_a, [], made), do: made
  defp pair_row_above(a, [b | bs], made), do: pair_row_above(a, bs, ops(b, a, made))

  # Prepend every legal result of a larger value x and a smaller value y under Countdown rules
  defp ops(x, 1, made) when x > 1, do: [x + 1, x - 1 | made]
  defp ops(x, 1, made), do: [x + 1 | made]
  defp ops(x, x, made), do: [x + x, x * x, 1 | made]

  defp ops(x, y, made) do
    if rem(x, y) == 0,
      do: [x + y, x - y, x * y, div(x, y) | made],
      else: [x + y, x - y, x * y | made]
  end

  # Return whether a value is in a subset by binary search over its sorted tuple
  defp member?({_, t, size}, v) when v < elem(t, 0) or v > elem(t, size - 1), do: false
  defp member?({_, t, size}, v), do: bsearch(t, v, 0, size - 1)

  defp bsearch(_t, _v, lo, hi) when lo > hi, do: false

  defp bsearch(t, v, lo, hi) do
    mid = (lo + hi) >>> 1
    w = elem(t, mid)

    cond do
      w < v -> bsearch(t, v, mid + 1, hi)
      w > v -> bsearch(t, v, lo, mid - 1)
      true -> true
    end
  end

  # Return the first way a subset makes a value as left mask, left value, right value and operator rank
  defp way({reach, splits} = st, mask, v), do: way_from(elem(splits, mask), reach, st, v)

  # Try each split in turn and return the first way any of them makes the value
  defp way_from([], _reach, _st, _v), do: nil

  defp way_from([{l, r} | rest], reach, st, v) do
    split_way(reach, st, l, r, v) || way_from(rest, reach, st, v)
  end

  # Return the first way one split makes a value searching an unbuilt half by nesting
  defp split_way(reach, st, l, r, v) do
    case {elem(reach, l), elem(reach, r)} do
      {nil, {rs, _, _}} ->
        case nested_right(rs, v, st, l, nil) do
          nil -> nil
          {a, b, op} -> {l, a, b, op}
        end

      {{ls, _, _}, nil} ->
        nested_left(ls, v, st, r, l)

      {lset, rset} ->
        way_split(lset, rset, l, v)
    end
  end

  # Return the first way a split makes a value scanning the shorter half and looking up partners in the other
  defp way_split({ls, _, ln} = lset, {rs, _, rn} = rset, l, v) do
    if ln <= rn do
      scan_left(ls, v, rset, l)
    else
      case scan_right(rs, v, lset, nil) do
        nil -> nil
        {a, b, op} -> {l, a, b, op}
      end
    end
  end

  # Return the first left value whose partner an unbuilt right subset can make with its least such partner
  defp nested_left([], _v, _st, _r, _l), do: nil

  defp nested_left([a | as], v, st, r, l) do
    case Enum.find(Enum.sort(candidates(a, v)), fn {b, _} -> way(st, r, b) end) do
      nil -> nested_left(as, v, st, r, l)
      {b, op} -> {l, a, b, op}
    end
  end

  # Return the least left value right value and operator where an unbuilt left subset makes the left value
  defp nested_right([], _v, _st, _l, best), do: best

  defp nested_right([b | bs], v, st, l, best) do
    found =
      Enum.find(Enum.sort(candidates(b, v)), fn {a, op} ->
        (best == nil or {a, b, op} < best) and way(st, l, a)
      end)

    best = if found, do: {elem(found, 0), b, elem(found, 1)}, else: best
    nested_right(bs, v, st, l, best)
  end

  # Return every number that could combine with n to make v under Countdown rules with its operator rank
  defp candidates(n, v) do
    found = if n < v, do: [{v - n, 0}], else: []
    found = if n > v, do: [{n - v, 1} | found], else: found
    found = [{n + v, 1} | found]
    found = if rem(v, n) == 0 and n != 1 and v != n, do: [{div(v, n), 2} | found], else: found
    found = if rem(n, v) == 0 and n != v, do: [{div(n, v), 3} | found], else: found
    if n != 1, do: [{n * v, 3} | found], else: found
  end

  # Return the first left value with a partner on the right together with its least partner
  defp scan_left([], _v, _rset, _l), do: nil

  defp scan_left([a | as], v, rset, l) do
    case best_partner(a, v, rset) do
      nil -> scan_left(as, v, rset, l)
      {b, op} -> {l, a, b, op}
    end
  end

  # Return the least left value right value and operator over every right value with a partner on the left
  defp scan_right([], _v, _lset, best), do: best

  defp scan_right([b | bs], v, lset, best) do
    best =
      case best_partner(b, v, lset) do
        nil -> best
        {a, op} -> if best == nil or {a, b, op} < best, do: {a, b, op}, else: best
      end

    scan_right(bs, v, lset, best)
  end

  # Return the least partner of n in a set with its operator rank by checking candidates in ascending order
  defp best_partner(n, v, set) when n < v do
    low =
      if rem(v, n) == 0 and n != 1 do
        q = div(v, n)
        d = v - n
        if q < d, do: first_of(q, 2, d, 0, set), else: first_of(d, 0, q, 2, set)
      else
        if member?(set, v - n), do: {v - n, 0}
      end

    low || partner(n + v, 1, set) || (n != 1 && partner(n * v, 3, set)) || nil
  end

  defp best_partner(n, v, set) when n > v do
    low =
      if rem(n, v) == 0 do
        q = div(n, v)
        d = n - v
        if q < d, do: first_of(q, 3, d, 1, set), else: first_of(d, 1, q, 3, set)
      else
        partner(n - v, 1, set)
      end

    # Check the product before the sum when v is one since n times one is below n plus one
    if v == 1,
      do: low || partner(n + 1, 1, set),
      else: low || partner(n + v, 1, set) || partner(n * v, 3, set)
  end

  defp best_partner(n, _v, set) do
    partner(n + n, 1, set) || (n != 1 && partner(n * n, 3, set)) || nil
  end

  # Return the first of two candidate partners the set holds
  defp first_of(m1, op1, m2, op2, set), do: partner(m1, op1, set) || partner(m2, op2, set)

  # Return a candidate partner with its operator rank when the set holds it
  defp partner(m, op, set), do: if(member?(set, m), do: {m, op})

  # Return the closest value as value and mask ranked by distance then numbers used then mask
  defp closest({reach, _} = st, by_size, n, target, full) do
    partial =
      Enum.reduce(1..(n - 1)//1, nil, fn size, best ->
        Enum.reduce(elem(by_size, size), best, fn mask, best ->
          {_, t, count} = elem(reach, mask)
          nearest(t, count, target, size, mask, best)
        end)
      end)

    whole = if n > 1, do: whole_best(st, full, target), else: nil

    # Fall back to the whole pool only when it gets strictly closer as it uses the most numbers
    case {partial, whole} do
      {nil, nil} -> {elem(elem(elem(reach, 1), 1), 0), 1, nil, st}
      {nil, w} -> {w, full, nil, st}
      {{_, _, _, v}, w} when w != nil and abs(w - target) < abs(v - target) -> {w, full, nil, st}
      {{_, _, mask, v}, _} -> {v, mask, nil, st}
    end
  end

  # Fold a subset's values either side of the target into the best key so far
  defp nearest(t, count, target, size, mask, best) do
    i = lower_bound(t, target, 0, count)
    best = if i < count, do: better(elem(t, i), target, size, mask, best), else: best
    if i > 0, do: better(elem(t, i - 1), target, size, mask, best), else: best
  end

  defp better(v, target, size, mask, best) do
    key = {abs(v - target), size, mask, v}
    if best == nil or key < best, do: key, else: best
  end

  # Return the index of the first value not below v in a sorted tuple
  defp lower_bound(_t, _v, lo, hi) when lo >= hi, do: lo

  defp lower_bound(t, v, lo, hi) do
    mid = (lo + hi) >>> 1
    if elem(t, mid) < v, do: lower_bound(t, v, mid + 1, hi), else: lower_bound(t, v, lo, mid)
  end

  # Return the whole pool's value closest to the target preferring the lower value on equal distance
  defp whole_best({reach, splits}, full, target) do
    {_, v} =
      Enum.reduce(elem(splits, full), {nil, nil}, fn {l, r}, acc ->
        {ls, _, _} = elem(reach, l)
        {rs, _, _} = elem(reach, r)
        whole_rows(ls, rs, target, acc)
      end)

    v
  end

  defp whole_rows([], _rs, _t, acc), do: acc
  defp whole_rows([a | as], rs, t, acc), do: whole_rows(as, rs, t, whole_row(a, rs, t, acc))

  defp whole_row(_a, [], _t, acc), do: acc

  defp whole_row(a, [b | bs], t, acc) do
    {x, y} = if a >= b, do: {a, b}, else: {b, a}
    acc = keep(x + y, t, acc)
    acc = if x > y, do: keep(x - y, t, acc), else: acc

    acc =
      cond do
        y == 1 -> acc
        rem(x, y) == 0 -> keep(div(x, y), t, keep(x * y, t, acc))
        true -> keep(x * y, t, acc)
      end

    whole_row(a, bs, t, acc)
  end

  defp keep(v, t, {d, w} = acc) do
    e = abs(v - t)
    if d == nil or e < d or (e == d and v < w), do: {e, v}, else: acc
  end

  # Write the canonical expression for a value made from a subset with brackets unless it is outermost
  defp render(st, mask, v, way, outer) do
    if (mask &&& mask - 1) == 0 do
      Integer.to_string(v)
    else
      # Reuse the way the shared search already found rather than searching for it again
      {l, a, b, op} = way || way(st, mask, v)
      r = bxor(mask, l)
      {lm, x, sm, y} = if a >= b, do: {l, a, r, b}, else: {r, b, l, a}

      inner = [
        render(st, lm, x, nil, false),
        elem({" + ", " - ", " * ", " / "}, op),
        render(st, sm, y, nil, false)
      ]

      if outer, do: inner, else: ["(", inner, ")"]
    end
  end
end
