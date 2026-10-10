defmodule Countdown.Solver.Tables do
  @moduledoc """
  Work out the subset tables that depend only on the pool size so the solver can embed them as constants
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

defmodule Countdown.Solver do
  @moduledoc """
  Work out the simplest Countdown expression that hits a target or gets closest to it
  """

  import Bitwise

  alias Countdown.Solver.Tables

  # Search this far either side of the target before building everything for a full closest search
  @near_limit 8
  # Search outwards only for full pools since smaller pools miss by more and build their subsets cheaply
  @near_from 6

  @compile {:inline, member?: 2, partner: 3, first_of: 5, keep: 3}

  # Embed the subset tables for every pool of up to six numbers since they depend only on the pool size
  @max_pool 6
  @by_size List.to_tuple(for n <- 0..@max_pool, do: Tables.masks_by_size(n, (1 <<< n) - 1))
  @splits Tables.split_table((1 <<< @max_pool) - 1)

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

    # Hold each subset's values as an ascending list for scanning and a tuple for binary search
    reach =
      Enum.reduce(Enum.with_index(pool), :erlang.make_tuple(full + 1, nil), fn {p, i}, reach ->
        put_elem(reach, 1 <<< i, {[p], {p}, 1})
      end)

    st = {reach, splits}

    {value, mask, st} =
      case Enum.find_index(pool, &(&1 == target)) do
        nil -> grow(st, by_size, 2, n, target, full)
        i -> {target, 1 <<< i, st}
      end

    {value, IO.iodata_to_binary(render(st, mask, value, true))}
  end

  # Search each size for the target and build its subsets only when none of them hits it
  defp grow(st, by_size, size, n, target, full) when size <= n do
    masks = elem(by_size, size)

    case Enum.find(masks, &(way(st, &1, target) != nil)) do
      # Build every deferred size but the largest so searches for nearby values can nest cheaply
      nil when size == n ->
        st = Enum.reduce(deferred(n) -- [n - 1], st, fn k, st -> build(st, elem(by_size, k)) end)

        (n >= @near_from && near(st, by_size, n, target, 1)) ||
          closest(build_all(st, by_size, n), by_size, n, target, full)

      nil ->
        st = if size in deferred(n), do: st, else: build(st, masks)
        grow(st, by_size, size + 1, n, target, full)

      mask ->
        {target, mask, st}
    end
  end

  defp grow(st, by_size, _size, n, target, full), do: closest(st, by_size, n, target, full)

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
        made =
          Enum.reduce(elem(splits, mask), [], fn {l, r}, made ->
            {ls, _, _} = elem(reach, l)
            {rs, _, _} = elem(reach, r)
            pairs(ls, rs, made)
          end)

        values = :lists.usort(made)
        put_elem(acc, mask, {values, List.to_tuple(values), length(values)})
      end)

    {reach, splits}
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
    found =
      case {elem(reach, l), elem(reach, r)} do
        # Search an unbuilt half by nesting while scanning the built half
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

    found || way_from(rest, reach, st, v)
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
      {nil, nil} -> {elem(elem(elem(reach, 1), 1), 0), 1, st}
      {nil, w} -> {w, full, st}
      {{_, _, _, v}, w} when w != nil and abs(w - target) < abs(v - target) -> {w, full, st}
      {{_, _, mask, v}, _} -> {v, mask, st}
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
  defp render(st, mask, v, outer) do
    if (mask &&& mask - 1) == 0 do
      Integer.to_string(v)
    else
      {l, a, b, op} = way(st, mask, v)
      r = bxor(mask, l)
      {lm, x, sm, y} = if a >= b, do: {l, a, r, b}, else: {r, b, l, a}

      inner = [
        render(st, lm, x, false),
        elem({" + ", " - ", " * ", " / "}, op),
        render(st, sm, y, false)
      ]

      if outer, do: inner, else: ["(", inner, ")"]
    end
  end
end
