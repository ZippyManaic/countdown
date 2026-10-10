! Work out the simplest Countdown expression that hits a target or gets closest to it
module countdown_solver
    use iso_c_binding, only: c_char, c_int, c_null_char
    use iso_fortran_env, only: int8, int32, int64, real64
    implicit none
    private
    public :: solve, solve_round

    ! Sort subsets with fewer values than this by insertion rather than by rank in the bitset
    integer, parameter :: rank_min = 16
    integer(int64), parameter :: low32 = int(z'FFFFFFFF', int64)

    ! Record a reachable value with how it was made leaving fields uninitialised so allocating arrays costs no zeroing
    type :: entry
        ! Pack value, operator (zero for a pool number), larger mask and smaller mask from the low bits up
        integer(int64) :: head
        ! Pack the larger operand in the low half and the smaller in the high half
        integer(int64) :: operands
    end type entry

    ! Hold the working memory of one solve
    type :: state
        integer(int64) :: target
        integer :: full
        ! Keep every subset's sorted values back to back in one arena
        type(entry), allocatable :: arena(:)
        integer :: top = 0
        integer :: off(0:255) = 0
        integer :: len(0:255) = 0
        ! Hold the largest value each subset can make which bounds the bitset words it touches
        integer(int64) :: max(0:255) = 0
        ! Hold one bit per value seen in the subset being built
        integer(int64), allocatable :: seen(:)
        ! Collect a subset's new values here before they are sorted into the arena
        type(entry), allocatable :: tmp(:)
        ! Hold the count of values below each bitset word for ranking
        integer(int32), allocatable :: rank(:)
        ! Hold the right half's values with their reciprocals for the split being built
        integer(int64), allocatable :: right_values(:)
        real(real64), allocatable :: right_inv(:)
    end type state

contains

    pure integer(int64) function value_of(e)
        type(entry), intent(in) :: e
        value_of = iand(e%head, low32)
    end function value_of

    ! Return the operator and masks of an entry shifted above its value
    pure integer(int64) function template(op, larger_mask, smaller_mask)
        character, intent(in) :: op
        integer, intent(in) :: larger_mask, smaller_mask
        template = shiftl(int(ichar(op) + shiftl(larger_mask, 8) + shiftl(smaller_mask, 16), int64), 32)
    end function template

    ! Fill t with the four operator templates for a split with the given larger and smaller halves
    pure subroutine templates(larger_mask, smaller_mask, t)
        integer, intent(in) :: larger_mask, smaller_mask
        integer(int64), intent(out) :: t(4)
        t = [template('+', larger_mask, smaller_mask), template('-', larger_mask, smaller_mask), &
             template('*', larger_mask, smaller_mask), template('/', larger_mask, smaller_mask)]
    end subroutine templates

    ! Grow an entry array to at least need slots by doubling keeping its first keep entries
    subroutine reserve(list, keep, need)
        type(entry), allocatable, intent(inout) :: list(:)
        integer, intent(in) :: keep, need
        type(entry), allocatable :: grown(:)
        integer :: size_

        if (allocated(list)) then
            if (need <= size(list)) return
            size_ = max(size(list), 1024)
        else
            size_ = 1024
        end if
        do while (size_ < need)
            size_ = 2*size_
        end do
        allocate (grown(size_))
        if (allocated(list)) grown(1:keep) = list(1:keep)
        call move_alloc(grown, list)
    end subroutine reserve

    ! Make room for the values and reciprocals of the largest subset built so far
    subroutine reserve_rights(s)
        type(state), intent(inout) :: s
        integer :: biggest

        biggest = maxval(s%len(1:s%full))
        if (allocated(s%right_values)) then
            if (size(s%right_values) >= biggest) return
            deallocate (s%right_values, s%right_inv)
        end if
        allocate (s%right_values(biggest), s%right_inv(biggest))
    end subroutine reserve_rights

    ! Make the bitset and its ranks cover every value up to largest
    subroutine reserve_seen(s, largest)
        type(state), intent(inout) :: s
        integer(int64), intent(in) :: largest
        integer :: words

        words = int(largest/64) + 1
        if (allocated(s%seen)) then
            if (size(s%seen) >= words) return
            ! Replace rather than copy since building leaves the bitset clear
            deallocate (s%seen, s%rank)
        end if
        allocate (s%seen(0:words - 1), s%rank(0:words - 1))
        s%seen = 0
    end subroutine reserve_seen

    ! Store a value at k advancing past it only if the bitset shows it is new so duplicates cost no mispredicted branch
    subroutine emit(seen, out, k, v, head, operands)
        integer(int64), intent(inout) :: seen(0:*)
        type(entry), intent(inout) :: out(*)
        integer(int64), intent(inout) :: k
        integer(int64), intent(in) :: v, head, operands
        integer(int64) :: w, word
        integer :: bit

        word = shiftr(v, 6)
        bit = int(iand(v, 63_int64))
        w = seen(word)
        seen(word) = ibset(w, bit)
        out(k) = entry(ior(head, v), operands)
        k = k + iand(shiftr(not(w), bit), 1_int64)
    end subroutine emit

    ! Return x divided by y rounded to the nearest integer when exact and zero otherwise using the reciprocal of y
    pure integer(int64) function exact(x, y, inv)
        integer(int64), intent(in) :: x, y
        real(real64), intent(in) :: inv
        integer(int64) :: q

        q = int(real(x, real64)*inv + 0.5_real64, int64)
        ! Mask to zero for an inexact division using arithmetic since gfortran branches on merge here
        exact = iand(q, shifta(ieor(q*y, x) - 1, 63))
    end function exact

    ! Append every new value from combining the two halves of a split at k
    subroutine emit_split(s, left, right, k)
        type(state), intent(inout) :: s
        integer, intent(in) :: left, right
        integer(int64), intent(inout) :: k
        integer(int64) :: tl(4), tr(4)

        call templates(left, right, tl)
        call templates(right, left, tr)
        call emit_pairs(s%arena, s%off(left), s%len(left), s%off(right), s%len(right), tl, tr, &
                        s%right_values, s%right_inv, s%seen, s%tmp, k)
    end subroutine emit_split

    ! Append every new value from pairing the values at two arena offsets passing each array separately so none alias
    subroutine emit_pairs(arena, loff, nl, roff, nr, tl, tr, rv, ri, seen, out, k)
        type(entry), intent(in) :: arena(*)
        integer, intent(in) :: loff, nl, roff, nr
        integer(int64), intent(in) :: tl(4), tr(4)
        integer(int64), intent(inout) :: rv(*)
        real(real64), intent(inout) :: ri(*)
        integer(int64), intent(inout) :: seen(0:*)
        type(entry), intent(inout) :: out(*)
        integer(int64), intent(inout) :: k
        integer(int64) :: a, b, operands
        real(real64) :: ia
        integer(int64) :: i, j

        ! Invert each right value once per split rather than once per pair
        do j = 1, nr
            rv(j) = value_of(arena(roff + j))
            ri(j) = 1.0_real64/real(rv(j), real64)
        end do
        do i = 1, nl
            a = value_of(arena(loff + i))
            j = 1
            ! Pair with right values up to a first where a is the larger and ties go left
            do while (j <= nr)
                b = rv(j)
                if (b > a) exit
                operands = ior(a, shiftl(b, 32))
                call emit(seen, out, k, a + b, tl(1), operands)
                ! Skip a zero result since every intermediate value must be a positive integer
                if (a /= b) call emit(seen, out, k, a - b, tl(2), operands)
                ! Skip multiplying and dividing by one as they never produce a new value
                if (b /= 1) then
                    call emit(seen, out, k, a*b, tl(3), operands)
                    call emit(seen, out, k, exact(a, b, ri(j)), tl(4), operands)
                end if
                j = j + 1
            end do
            ! Pair with the remaining larger right values where a is the smaller
            ia = 1.0_real64/real(a, real64)
            do j = j, nr
                b = rv(j)
                operands = ior(b, shiftl(a, 32))
                call emit(seen, out, k, b + a, tr(1), operands)
                call emit(seen, out, k, b - a, tr(2), operands)
                if (a /= 1) then
                    call emit(seen, out, k, b*a, tr(3), operands)
                    call emit(seen, out, k, exact(b, a, ia), tr(4), operands)
                end if
            end do
        end do
    end subroutine emit_pairs

    ! Keep a value as the whole pool's best if it is closer to the target or equally close and lower
    subroutine check(target, best, best_distance, v, head, operands)
        integer(int64), intent(in) :: target, v, head, operands
        type(entry), intent(inout) :: best
        integer(int64), intent(inout) :: best_distance
        integer(int64) :: d

        d = abs(v - target)
        if (v /= 0 .and. (d < best_distance .or. (d == best_distance .and. v < value_of(best)))) then
            best_distance = d
            best = entry(ior(head, v), operands)
        end if
    end subroutine check

    ! Check every value from combining the two halves of a split of the whole pool
    subroutine check_split(s, left, right, best, best_distance)
        type(state), intent(inout) :: s
        integer, intent(in) :: left, right
        type(entry), intent(inout) :: best
        integer(int64), intent(inout) :: best_distance
        integer(int64) :: tl(4), tr(4), a, b, operands
        real(real64) :: ia
        integer :: i, j, nr

        call templates(left, right, tl)
        call templates(right, left, tr)
        nr = s%len(right)
        do j = 1, nr
            s%right_values(j) = value_of(s%arena(s%off(right) + j))
            s%right_inv(j) = 1.0_real64/real(s%right_values(j), real64)
        end do
        do i = 1, s%len(left)
            a = value_of(s%arena(s%off(left) + i))
            j = 1
            do while (j <= nr)
                b = s%right_values(j)
                if (b > a) exit
                operands = ior(a, shiftl(b, 32))
                call check(s%target, best, best_distance, a + b, tl(1), operands)
                if (a /= b) call check(s%target, best, best_distance, a - b, tl(2), operands)
                if (b /= 1) then
                    call check(s%target, best, best_distance, a*b, tl(3), operands)
                    call check(s%target, best, best_distance, exact(a, b, s%right_inv(j)), tl(4), operands)
                end if
                j = j + 1
            end do
            ia = 1.0_real64/real(a, real64)
            do j = j, nr
                b = s%right_values(j)
                operands = ior(b, shiftl(a, 32))
                call check(s%target, best, best_distance, b + a, tr(1), operands)
                call check(s%target, best, best_distance, b - a, tr(2), operands)
                if (a /= 1) then
                    call check(s%target, best, best_distance, b*a, tr(3), operands)
                    call check(s%target, best, best_distance, exact(b, a, ia), tr(4), operands)
                end if
            end do
        end do
    end subroutine check_split

    ! Return the arena index of value in a subset or zero when it is absent
    pure integer function lookup(s, mask, value)
        type(state), intent(in) :: s
        integer, intent(in) :: mask
        integer(int64), intent(in) :: value

        lookup = search(s%arena, s%off(mask), s%len(mask), value)
    end function lookup

    ! Return the index of value among the n sorted entries after offset off or zero when it is absent
    pure integer function search(arena, off, n, value)
        type(entry), intent(in) :: arena(*)
        integer, intent(in) :: off, n
        integer(int64), intent(in) :: value
        integer :: base, left

        base = off + 1
        left = n
        search = 0
        ! Skip the search when the value lies outside the subset's range
        if (left == 0) return
        if (value < value_of(arena(base)) .or. value > value_of(arena(base + left - 1))) return
        ! Halve the range with a sign mask so unpredictable comparisons cost no mispredicted branch
        do while (left > 1)
            base = base + iand(left/2, int(not(shifta(value - value_of(arena(base + left/2)), 63))))
            left = left - left/2
        end do
        if (value_of(arena(base)) == value) search = base
    end function search

    ! Fill m and ops with every number that combines with n under Countdown rules to make the target in operator order
    subroutine partners(n, target, m, ops, count)
        integer(int64), intent(in) :: n, target
        integer(int64), intent(out) :: m(6)
        character, intent(out) :: ops(6)
        integer, intent(out) :: count

        count = 0
        if (target > n) call add(target - n, '+')
        if (n > target) call add(n - target, '-')
        call add(n + target, '-')
        ! Divide only when the quotient could be at least two since neither operand may be one
        if (n /= 1 .and. 2*n <= target) then
            if (mod(target, n) == 0) call add(target/n, '*')
        end if
        if (n >= 2*target) then
            if (mod(n, target) == 0) call add(n/target, '/')
        end if
        ! Skip a product too large for any subset to make
        if (n /= 1 .and. n*target <= low32) call add(n*target, '/')
    contains
        subroutine add(value, op)
            integer(int64), intent(in) :: value
            character, intent(in) :: op
            count = count + 1
            m(count) = value
            ops(count) = op
        end subroutine add
    end subroutine partners

    ! Find how the target is first made from a subset without building all of its values
    logical function find_exact(s, mask, hit)
        type(state), intent(in) :: s
        integer, intent(in) :: mask
        type(entry), intent(out) :: hit
        integer :: left, right, i, k, count, loop_mask, search_mask
        integer(int64) :: m(6), n, best_a, best_b
        character :: ops(6), best_op

        find_exact = .false.
        left = iand(mask - 1, mask)
        do while (left /= 0)
            right = ieor(mask, left)
            ! Visit splits in the same order as building so the same origin wins
            if (left < right) then
                ! Keep the lowest pair as building would since partners come in operator order
                best_a = huge(best_a)
                best_b = huge(best_b)
                best_op = achar(0)
                if (s%len(left) <= s%len(right)) then
                    loop_mask = left
                    search_mask = right
                else
                    loop_mask = right
                    search_mask = left
                end if
                do i = 1, s%len(loop_mask)
                    n = value_of(s%arena(s%off(loop_mask) + i))
                    call partners(n, s%target, m, ops, count)
                    do k = 1, count
                        if (loop_mask == left) then
                            if (m(k) >= best_b) cycle
                            if (lookup(s, search_mask, m(k)) == 0) cycle
                            best_a = n
                            best_b = m(k)
                        else
                            if (m(k) >= best_a) cycle
                            if (lookup(s, search_mask, m(k)) == 0) cycle
                            best_a = m(k)
                            best_b = n
                        end if
                        best_op = ops(k)
                    end do
                    ! Take the first left value with any partner since left values ascend
                    if (loop_mask == left .and. best_op /= achar(0)) exit
                end do
                if (best_op /= achar(0)) then
                    if (best_a >= best_b) then
                        hit = entry(ior(template(best_op, left, right), s%target), ior(best_a, shiftl(best_b, 32)))
                    else
                        hit = entry(ior(template(best_op, right, left), s%target), ior(best_b, shiftl(best_a, 32)))
                    end if
                    find_exact = .true.
                    return
                end if
            end if
            left = iand(left - 1, mask)
        end do
    end function find_exact

    ! Place each value at its rank in the bitset which needs no comparisons and clear the words it covers
    subroutine rank_sort(items, count, seen, rank, words, sorted)
        type(entry), intent(in) :: items(*)
        integer, intent(in) :: count, words
        integer(int64), intent(inout) :: seen(0:*)
        integer(int32), intent(inout) :: rank(0:*)
        type(entry), intent(inout) :: sorted(*)
        integer(int64) :: v
        integer(int32) :: below
        integer :: i, w

        below = 1
        do w = 0, words - 1
            rank(w) = below
            below = below + popcnt(seen(w))
        end do
        do i = 1, count
            v = value_of(items(i))
            w = int(shiftr(v, 6))
            sorted(rank(w) + popcnt(iand(seen(w), maskr(int(iand(v, 63_int64)), int64)))) = items(i)
        end do
        seen(0:words - 1) = 0
    end subroutine rank_sort

    ! Build the sorted reachable values of a subset into the arena keeping only the first way found to make each
    subroutine build(s, mask)
        type(state), intent(inout) :: s
        integer, intent(in) :: mask
        integer :: left, right, count, i, at
        integer(int64) :: v, pairs, k
        type(entry) :: e

        ! Mark zero as seen so inexact divisions never become entries
        s%seen(0) = ibset(s%seen(0), 0)
        k = 1
        left = iand(mask - 1, mask)
        do while (left /= 0)
            right = ieor(mask, left)
            ! Visit each split once rather than once per ordering
            if (left < right) then
                ! Reserve room for every pair's results plus the one slot each store may write past the end
                pairs = 4*int(s%len(left), int64)*s%len(right)
                call reserve(s%tmp, int(k) - 1, int(k + min(pairs, s%max(mask))))
                call emit_split(s, left, right, k)
            end if
            left = iand(left - 1, mask)
        end do
        s%seen(0) = ibclr(s%seen(0), 0)
        count = int(k) - 1

        call reserve(s%arena, s%top, s%top + count)
        if (count < rank_min) then
            ! Clear only the words this subset touched and insertion sort the few values
            do i = 1, count
                e = s%tmp(i)
                v = value_of(e)
                s%seen(shiftr(v, 6)) = 0
                at = s%top + i
                do while (at > s%top + 1)
                    if (value_of(s%arena(at - 1)) <= v) exit
                    s%arena(at) = s%arena(at - 1)
                    at = at - 1
                end do
                s%arena(at) = e
            end do
        else
            call rank_sort(s%tmp, count, s%seen, s%rank, int(s%max(mask)/64) + 1, s%arena(s%top + 1:))
        end if
        s%off(mask) = s%top
        s%len(mask) = count
        s%top = s%top + count
    end subroutine build

    ! Write n in decimal at position at of text advancing at past it
    subroutine put_uint(text, at, n)
        character(*), intent(inout) :: text
        integer, intent(inout) :: at
        integer(int64), intent(in) :: n
        character(20) :: digits

        write (digits, '(i0)') n
        text(at:at + len_trim(digits) - 1) = trim(digits)
        at = at + len_trim(digits)
    end subroutine put_uint

    ! Write the expression for an entry following its origins back to the pool with brackets when asked
    recursive subroutine render(s, e, text, at, bracket)
        type(state), intent(in) :: s
        type(entry), intent(in) :: e
        character(*), intent(inout) :: text
        integer, intent(inout) :: at
        logical, intent(in) :: bracket
        integer :: larger_mask, smaller_mask
        character :: op

        op = achar(iand(shiftr(e%head, 32), 255_int64))
        if (op == achar(0)) then
            call put_uint(text, at, value_of(e))
            return
        end if
        larger_mask = int(iand(shiftr(e%head, 40), 255_int64))
        smaller_mask = int(iand(shiftr(e%head, 48), 255_int64))
        if (bracket) call put('(')
        call render(s, s%arena(lookup(s, larger_mask, iand(e%operands, low32))), text, at, .true.)
        call put(' '//op//' ')
        call render(s, s%arena(lookup(s, smaller_mask, shiftr(e%operands, 32))), text, at, .true.)
        if (bracket) call put(')')
    contains
        subroutine put(piece)
            character(*), intent(in) :: piece
            text(at:at + len(piece) - 1) = piece
            at = at + len(piece)
        end subroutine put
    end subroutine render

    ! Return the simplest expression that hits the target or gets closest to it with its value
    subroutine solve_round(target, pool, value, expr)
        integer(int32), intent(in) :: target
        integer(int32), intent(in) :: pool(:)
        integer(int32), intent(out) :: value
        character(:), allocatable, intent(out) :: expr
        character(128) :: text
        integer :: at

        value = solve_into(target, pool, text, at)
        expr = text(1:at - 1)
    end subroutine solve_round

    ! Write the simplest expression that hits the target or gets closest into text ending before at and return its value
    integer(int32) function solve_into(target, pool, text, at)
        integer(int32), intent(in) :: target
        integer(int32), intent(in) :: pool(:)
        character(*), intent(out) :: text
        integer, intent(out) :: at
        type(state) :: s
        type(entry) :: best, whole
        integer(int64) :: largest(0:9), a, b, best_distance, whole_distance, d
        integer :: n, mask, left, i, size_, k, used, best_used, first(0:10), fill(0:10), order(255)
        logical :: solved

        n = size(pool)
        s%target = target
        s%full = 2**n - 1

        ! Work out each subset's largest value since subtracting and dividing never exceed the larger operand
        largest = 0
        do mask = 1, s%full
            if (popcnt(mask) == 1) then
                s%max(mask) = pool(trailz(mask) + 1)
            else
                left = iand(mask - 1, mask)
                do while (left /= 0)
                    a = s%max(left)
                    b = s%max(ieor(mask, left))
                    s%max(mask) = max(s%max(mask), a*b, a + b)
                    left = iand(left - 1, mask)
                end do
            end if
            ! Track the largest value of each size so the bitset only grows when bigger subsets are built
            largest(popcnt(mask)) = max(largest(popcnt(mask)), s%max(mask))
        end do

        ! Store each pool number as a one-number subset
        call reserve(s%arena, 0, 4096)
        solved = .false.
        do i = 1, n
            s%arena(i) = entry(int(pool(i), int64), 0)
            s%off(shiftl(1, i - 1)) = i - 1
            s%len(shiftl(1, i - 1)) = 1
            if (.not. solved .and. pool(i) == target) then
                best = s%arena(i)
                solved = .true.
            end if
        end do
        s%top = n

        ! List subsets by size then mask so the loops below need no unpredictable size test
        first = 0
        do mask = 1, s%full
            first(popcnt(mask) + 1) = first(popcnt(mask) + 1) + 1
        end do
        do size_ = 1, n + 1
            first(size_) = first(size_) + first(size_ - 1)
        end do
        fill = first
        do mask = 1, s%full
            fill(popcnt(mask)) = fill(popcnt(mask)) + 1
            order(fill(popcnt(mask))) = mask
        end do

        ! Work through subsets smallest first stopping at the first size that hits the target
        do size_ = 2, n
            if (solved) exit
            ! Keep the lowest matching subset of this size to break ties the same way every run
            do k = first(size_) + 1, first(size_ + 1)
                solved = find_exact(s, order(k), best)
                if (solved) exit
            end do
            ! Skip building the whole pool's values since no larger subset is made from them
            if (solved .or. size_ == n) exit
            call reserve_rights(s)
            call reserve_seen(s, largest(size_))
            do k = first(size_) + 1, first(size_ + 1)
                call build(s, order(k))
            end do
        end do

        if (.not. solved) then
            ! Rank by distance from the target then by how many numbers are used so the simplest answer wins
            best_distance = huge(best_distance)
            best_used = 99
            do mask = 1, s%full - 1
                used = popcnt(mask)
                do i = s%off(mask) + 1, s%off(mask) + s%len(mask)
                    d = abs(value_of(s%arena(i)) - target)
                    if (d < best_distance .or. (d == best_distance .and. used < best_used)) then
                        best = s%arena(i)
                        best_distance = d
                        best_used = used
                    end if
                end do
            end do
            ! Check the whole pool's values as they are made since no larger subset is built from them
            if (n > 1) then
                call reserve_rights(s)
                whole = entry(low32, 0)
                whole_distance = huge(whole_distance)
                left = iand(s%full - 1, s%full)
                do while (left /= 0)
                    if (left < ieor(s%full, left)) call check_split(s, left, ieor(s%full, left), whole, whole_distance)
                    left = iand(left - 1, s%full)
                end do
                ! Fall back to the whole pool only when it gets strictly closer as it uses the most numbers
                if (whole_distance < best_distance) best = whole
            end if
        end if

        ! Render without outer brackets which matches stripping them from the bracketed form
        at = 1
        call render(s, best, text, at, .false.)
        solve_into = int(value_of(best), int32)
    end function solve_into

    ! Expose the solver with the same C interface as the assembly and C versions so one benchmark harness fits all
    integer(c_int) function solve(target, pool, n, out) bind(c, name='solve')
        integer(c_int), value, intent(in) :: target, n
        integer(c_int), intent(in) :: pool(n)
        character(kind=c_char), intent(out) :: out(*)
        character(128) :: text
        integer :: at, i

        solve = solve_into(int(target, int32), int(pool, int32), text, at)
        do i = 1, at - 1
            out(i) = text(i:i)
        end do
        out(at) = c_null_char
    end function solve

end module countdown_solver
