# Work out the simplest Countdown expression that hits a target or gets closest to it

module Solver
  # Encode operators so an origin packs into one integer as larger * 256 + larger mask * 4 + operator
  ADD = 0
  SUB = 1
  MUL = 2
  DIV = 3
  OP_TEXT = ["+", "-", "*", "/"].freeze

  # List each pool size's subsets by size and each subset's splits as left then right in visiting order
  TABLES = (0..6).map do |n|
    full = (1 << n) - 1
    by_size = Array.new(n + 1) { [] }
    splits = Array.new(full + 1) { [] }
    (1..full).each do |mask|
      by_size[mask.digits(2).sum] << mask
      left = (mask - 1) & mask
      while left != 0
        right = mask ^ left
        # Visit each split once rather than once per ordering
        splits[mask].push(left, right) if left < right
        left = (left - 1) & mask
      end
      splits[mask].freeze
    end
    [by_size.each(&:freeze).freeze, splits.freeze]
  end.freeze

  # Count the numbers each subset uses
  SIZES = (0..63).map { |m| m.digits(2).sum }.freeze

  module_function

  # Return the packed origin of the first way the target is made from a subset or nil without building its values
  def find_exact(values, origins, split, target)
    s = 0
    while s < split.length
      left = split[s]
      right = split[s + 1]
      s += 2
      lefts = values[left]
      rights = values[right]
      # Loop over the smaller half and look up the larger for the lowest pair building would yield
      left_loop = lefts.length <= rights.length
      if left_loop
        loop_values = lefts
        search = origins[right]
      else
        loop_values = rights
        search = origins[left]
      end
      best_n = best_m = best_op = nil
      i = 0
      count = loop_values.length
      while i < count
        n = loop_values[i]
        i += 1
        # Try each number that combines with n to make the target in operator order keeping the lowest partner
        if target > n
          m = target - n
          best_n, best_m, best_op = n, m, ADD if search.key?(m) && (best_m.nil? || m < best_m)
        end
        if n > target
          m = n - target
          best_n, best_m, best_op = n, m, SUB if search.key?(m) && (best_m.nil? || m < best_m)
        end
        m = n + target
        best_n, best_m, best_op = n, m, SUB if search.key?(m) && (best_m.nil? || m < best_m)
        # Divide only when the quotient could be at least two since neither operand may be one
        if n != 1 && 2 * n <= target && (target % n).zero?
          m = target / n
          best_n, best_m, best_op = n, m, MUL if search.key?(m) && (best_m.nil? || m < best_m)
        end
        if n >= 2 * target && (n % target).zero?
          m = n / target
          best_n, best_m, best_op = n, m, DIV if search.key?(m) && (best_m.nil? || m < best_m)
        end
        if n != 1
          m = n * target
          best_n, best_m, best_op = n, m, DIV if search.key?(m) && (best_m.nil? || m < best_m)
        end
        # Take the first left value with any partner since left values ascend and the lowest partner wins
        break if best_m && left_loop
      end
      next unless best_m

      a, b = left_loop ? [best_n, best_m] : [best_m, best_n]
      return a >= b ? a * 256 + left * 4 + best_op : b * 256 + right * 4 + best_op
    end
    nil
  end

  # Build a subset's values sorted ascending and a map from each value to the first way found to make it
  def build(values, split)
    seen = {}
    # Declare the result variable first so the parser reads it as a local in the modifier lines below
    v = nil
    s = 0
    while s < split.length
      left = split[s]
      right = split[s + 1]
      s += 2
      lefts = values[left]
      rights = values[right]
      nr = rights.length
      left_code = left * 4
      right_code = right * 4
      i = 0
      nl = lefts.length
      while i < nl
        a = lefts[i]
        i += 1
        j = 0
        base = a * 256 + left_code
        # Pair with right values up to a first where a is the larger and ties go left
        while j < nr
          b = rights[j]
          break if b > a

          j += 1
          seen[v] = base unless seen.key?(v = a + b)
          # Skip a zero result since every intermediate value must be a positive integer
          seen[v] = base + SUB if a != b && !seen.key?(v = a - b)
          # Skip multiplying and dividing by one as they never produce a new value
          next if b == 1

          seen[v] = base + MUL unless seen.key?(v = a * b)
          seen[v] = base + DIV if (a % b).zero? && !seen.key?(v = a / b)
        end
        # Pair with the remaining larger right values where a is the smaller
        while j < nr
          b = rights[j]
          j += 1
          code = b * 256 + right_code
          seen[v] = code unless seen.key?(v = b + a)
          seen[v] = code + SUB unless seen.key?(v = b - a)
          next if a == 1

          seen[v] = code + MUL unless seen.key?(v = b * a)
          seen[v] = code + DIV if (b % a).zero? && !seen.key?(v = b / a)
        end
      end
    end
    [seen.keys.sort!, seen]
  end

  # Return the whole pool's closest value preferring the lower on equal distance with its packed origin and distance
  def whole_pass(values, split, target)
    # Start beyond any reachable distance so the first value always wins
    best = 0
    best_origin = nil
    best_d = 1 << 62
    s = 0
    while s < split.length
      left = split[s]
      right = split[s + 1]
      s += 2
      lefts = values[left]
      rights = values[right]
      nr = rights.length
      left_code = left * 4
      right_code = right * 4
      i = 0
      nl = lefts.length
      while i < nl
        a = lefts[i]
        i += 1
        j = 0
        base = a * 256 + left_code
        # Pair with right values up to a first where a is the larger and ties go left
        while j < nr
          b = rights[j]
          break if b > a

          j += 1
          v = a + b
          d = v > target ? v - target : target - v
          best, best_origin, best_d = v, base, d if d < best_d || (d == best_d && v < best)
          if a != b
            v = a - b
            d = v > target ? v - target : target - v
            best, best_origin, best_d = v, base + SUB, d if d < best_d || (d == best_d && v < best)
          end
          next if b == 1

          v = a * b
          d = v > target ? v - target : target - v
          best, best_origin, best_d = v, base + MUL, d if d < best_d || (d == best_d && v < best)
          next unless (a % b).zero?

          v = a / b
          d = v > target ? v - target : target - v
          best, best_origin, best_d = v, base + DIV, d if d < best_d || (d == best_d && v < best)
        end
        # Pair with the remaining larger right values where a is the smaller
        while j < nr
          b = rights[j]
          j += 1
          code = b * 256 + right_code
          v = b + a
          d = v > target ? v - target : target - v
          best, best_origin, best_d = v, code, d if d < best_d || (d == best_d && v < best)
          v = b - a
          d = v > target ? v - target : target - v
          best, best_origin, best_d = v, code + SUB, d if d < best_d || (d == best_d && v < best)
          next if a == 1

          v = b * a
          d = v > target ? v - target : target - v
          best, best_origin, best_d = v, code + MUL, d if d < best_d || (d == best_d && v < best)
          next unless (b % a).zero?

          v = b / a
          d = v > target ? v - target : target - v
          best, best_origin, best_d = v, code + DIV, d if d < best_d || (d == best_d && v < best)
        end
      end
    end
    [best, best_origin, best_d]
  end

  # Return the smaller operand of a value made from a larger operand with an operator
  def smaller_of(value, larger, op)
    case op
    when ADD then value - larger
    when SUB then larger - value
    when MUL then value / larger
    else larger / value
    end
  end

  # Append the expression for a value of a subset to out by following packed origins back to the pool
  def render(origins, mask, value, origin, out, bracket)
    if origin.zero?
      out << value.to_s
      return out
    end
    op = origin & 3
    larger_mask = (origin >> 2) & 63
    larger = origin >> 8
    smaller_mask = mask ^ larger_mask
    smaller = smaller_of(value, larger, op)
    out << "(" if bracket
    render(origins, larger_mask, larger, origins[larger_mask][larger], out, true)
    out << " " << OP_TEXT[op] << " "
    render(origins, smaller_mask, smaller, origins[smaller_mask][smaller], out, true)
    out << ")" if bracket
    out
  end

  # Return the simplest expression that hits the target or gets closest to it with its value
  def solve(target, pool)
    n = pool.length
    full = (1 << n) - 1
    by_size, splits = TABLES[n]
    # Map each subset of the pool (as a bitmask) to its values sorted ascending and to each value's packed origin
    values = Array.new(full + 1, [].freeze)
    origins = Array.new(full + 1, {}.freeze)
    exact_mask = exact_origin = nil

    # Store each pool number as a one-number subset with origin zero
    n.times do |i|
      v = pool[i]
      values[1 << i] = [v]
      origins[1 << i] = { v => 0 }
      exact_mask, exact_origin = 1 << i, 0 if v == target && exact_mask.nil?
    end

    # Work through subsets smallest first stopping at the first size that hits the target
    (2..n).each do |size|
      break if exact_mask

      masks = by_size[size]
      # Keep the lowest matching subset of this size to break ties the same way every run
      masks.each do |m|
        origin = find_exact(values, origins, splits[m], target)
        next unless origin

        exact_mask = m
        exact_origin = origin
        break
      end
      # Skip building the whole pool's values since no larger subset is made from them
      break if exact_mask || size == n

      masks.each { |m| values[m], origins[m] = build(values, splits[m]) }
    end

    value_mask = exact_mask
    value = target
    origin = exact_origin
    unless value_mask
      # Rank by distance from the target then by how many numbers are used so the simplest answer wins
      best_distance = best_used = nil
      # Include the only subset of a one-number pool since it is also the whole pool
      (1...(n == 1 ? 2 : full)).each do |m|
        used = SIZES[m]
        list = values[m]
        # Find the closest value with a binary search since the values are sorted
        k = list.bsearch_index { |v| v >= target } || list.length
        [k - 1, k].each do |idx|
          next if idx.negative? || idx >= list.length

          v = list[idx]
          d = (v - target).abs
          next unless best_distance.nil? || d < best_distance || (d == best_distance && used < best_used)

          value_mask = m
          value = v
          best_distance = d
          best_used = used
        end
      end
      origin = origins[value_mask][value]

      # Check the whole pool's values as they are made since no larger subset is built from them
      if n > 1
        whole, whole_origin, whole_distance = whole_pass(values, splits[full], target)
        # Fall back to the whole pool only when it gets strictly closer as it uses the most numbers
        if whole_distance && whole_distance < best_distance
          value_mask = full
          value = whole
          origin = whole_origin
        end
      end
    end

    # Render without outer brackets which matches stripping them from the bracketed form
    [value, render(origins, value_mask, value, origin, +"", false)]
  end
end
