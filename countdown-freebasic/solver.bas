' Solve a Countdown numbers round by building every subset's reachable values smallest subsets first

#include once "crt/stdlib.bi"
#include once "crt/string.bi"

' Sort subsets with fewer values than this by insertion rather than by rank in the bitset
#define RANK_MIN 16

#define OP_ADD 43
#define OP_SUB 45
#define OP_MUL 42
#define OP_DIV 47

' Record a reachable value with how it was made from the larger and smaller of two values in disjoint subsets
Type Entry
    value As ULong
    ' Leave the operator as zero for a pool number
    op As UByte
    larger_mask As UByte
    smaller_mask As UByte
    pad As UByte
    larger As ULong
    smaller As ULong
End Type

' Hold the working memory of one solve
Type SolveState
    target As ULong
    full As ULong
    ' Keep every subset's sorted values back to back in one arena
    arena As Entry Ptr
    top As UInteger
    cap As UInteger
    off(0 To 255) As ULong
    length(0 To 255) As ULong
    ' Hold the largest value each subset can make which bounds the bitset words it touches
    max_value(0 To 255) As ULong
    ' Hold one bit per value seen in the subset being built
    seen As ULongInt Ptr
    seen_words As UInteger
    ' Collect a subset's new values here before they are sorted into the arena
    tmp As Entry Ptr
    tmp_cap As UInteger
    ' Hold the count of values below each bitset word for ranking
    rank As ULong Ptr
    ' Hold the right half's values with their reciprocals for the split being built
    right_values As ULong Ptr
    right_inv As Double Ptr
    right_cap As UInteger
End Type

Private Function Grow(ByVal p As Any Ptr, ByRef cap As UInteger, ByVal need As UInteger, ByVal size As UInteger) As Any Ptr
    If need <= cap Then Return p
    While cap < need
        cap = IIf(cap, cap * 2, 1024)
    Wend
    p = realloc(p, cap * size)
    If p = 0 Then
        Print "out of memory"
        End 2
    End If
    Return p
End Function

' Count the set bits in a word with a pattern GCC turns into one instruction
Private Function PopCount64(ByVal x As ULongInt) As ULong
    x = x - ((x Shr 1) And &h5555555555555555ull)
    x = (x And &h3333333333333333ull) + ((x Shr 2) And &h3333333333333333ull)
    x = (x + (x Shr 4)) And &h0F0F0F0F0F0F0F0Full
    Return CULng((x * &h0101010101010101ull) Shr 56)
End Function

Private Function LowestBit(ByVal x As ULong) As ULong
    Dim As ULong i = 0
    While (x And 1) = 0
        x Shr= 1
        i += 1
    Wend
    Return i
End Function

' Return the operator and masks of an entry shifted above its value
Private Function Template(ByVal op As ULong, ByVal larger_mask As ULong, ByVal smaller_mask As ULong) As ULongInt
    Return CULngInt(op Or (larger_mask Shl 8) Or (smaller_mask Shl 16)) Shl 32
End Function

' Append a value advancing past it only if the bitset shows it is new so duplicates cost no mispredicted branch
#macro EMIT(v, tmpl)
    Scope
        Dim As ULong v_ = (v)
        Dim As ULongInt word_ = seen[v_ Shr 6]
        seen[v_ Shr 6] = word_ Or (1ull Shl (v_ And 63))
        Cast(ULongInt Ptr, out_)[0] = (tmpl) Or v_
        Cast(ULongInt Ptr, out_)[1] = operands
        out_ += ((Not word_) Shr (v_ And 63)) And 1
    End Scope
#endmacro

' Keep a value as the whole pool's best if it is closer to the target or equally close and lower
#macro CHECK(v, tmpl)
    Scope
        Dim As ULong v_ = (v)
        Dim As ULong d_ = IIf(v_ > target, v_ - target, target - v_)
        If v_ <> 0 AndAlso (d_ < whole_distance OrElse (d_ = whole_distance AndAlso v_ < CULng(whole_head))) Then
            whole_distance = d_
            whole_head = (tmpl) Or v_
            whole_operands = operands
        End If
    End Scope
#endmacro

' Pass every legal value from x and y under Countdown rules to act where x is at least y and inv is 1/y
#macro OPS(act, x, y, inv, t)
    Scope
        Dim As ULong x_ = (x), y_ = (y)
        Dim As ULongInt operands = x_ Or (CULngInt(y_) Shl 32)
        act(x_ + y_, t(0))
        ' Skip a zero result since every intermediate value must be a positive integer
        If x_ <> y_ Then
            act(x_ - y_, t(1))
        End If
        ' Skip multiplying and dividing by one as they never produce a new value
        If y_ <> 1 Then
            act(x_ * y_, t(2))
            ' Emit zero for an inexact division by masking with the comparison since bit 0 stays set so it is dropped
            Dim As ULong q_ = CULng(x_ * (inv))
            act(q_ And (q_ * y_ = x_), t(3))
        End If
    End Scope
#endmacro

' Pass every legal combination of each left value with each right value to act
#macro PAIRS(s, left_, right_, act)
    Scope
        Dim As ULongInt tl_(0 To 3) = {Template(OP_ADD, left_, right_), Template(OP_SUB, left_, right_), _
            Template(OP_MUL, left_, right_), Template(OP_DIV, left_, right_)}
        Dim As ULongInt tr_(0 To 3) = {Template(OP_ADD, right_, left_), Template(OP_SUB, right_, left_), _
            Template(OP_MUL, right_, left_), Template(OP_DIV, right_, left_)}
        Dim As Entry Ptr lefts_ = s.arena + s.off(left_), rights_ = s.arena + s.off(right_)
        Dim As ULong nl_ = s.length(left_), nr_ = s.length(right_)
        ' Invert each right value once per split rather than once per pair
        Dim As ULong Ptr rv_ = s.right_values
        Dim As Double Ptr ri_ = s.right_inv
        For j As ULong = 0 To nr_ - 1
            rv_[j] = rights_[j].value
            ri_[j] = 1.0 / rv_[j]
        Next
        For i As ULong = 0 To nl_ - 1
            Dim As ULong a_ = lefts_[i].value, j = 0
            While j < nr_ AndAlso rv_[j] <= a_
                OPS(act, a_, rv_[j], ri_[j], tl_)
                j += 1
            Wend
            Dim As Double ia_ = 1.0 / a_
            While j < nr_
                OPS(act, rv_[j], a_, ia_, tr_)
                j += 1
            Wend
        Next
    End Scope
#endmacro

' Return the entry holding value among n sorted entries or null when it is absent
Private Function Lookup(ByVal p As Entry Ptr, ByVal n As ULong, ByVal value As ULong) As Entry Ptr
    ' Skip the search when the value lies outside the subset's range
    If n = 0 OrElse value < p[0].value OrElse value > p[n - 1].value Then Return 0
    ' Halve the range with a mask so unpredictable comparisons cost no mispredicted branch
    While n > 1
        Dim As ULong half = n Shr 1
        p += (p[half].value <= value) And half
        n -= half
    Wend
    Return IIf(p->value = value, p, 0)
End Function

' Fill m and op with every number that combines with n under Countdown rules to make the target in operator order
Private Function Partners(ByVal n As ULong, ByVal target As ULong, ByVal m As ULong Ptr, ByVal op As UByte Ptr) As Long
    Dim As Long count = 0
    If target > n Then m[count] = target - n : op[count] = OP_ADD : count += 1
    If n > target Then m[count] = n - target : op[count] = OP_SUB : count += 1
    m[count] = n + target : op[count] = OP_SUB : count += 1
    ' Divide only when the quotient could be at least two since neither operand may be one
    If n <> 1 AndAlso 2 * n <= target AndAlso target Mod n = 0 Then m[count] = target \ n : op[count] = OP_MUL : count += 1
    If n >= 2 * target AndAlso n Mod target = 0 Then m[count] = n \ target : op[count] = OP_DIV : count += 1
    ' Skip a product too large for any subset to make
    If n <> 1 AndAlso CULngInt(n) * target <= &hFFFFFFFFull Then m[count] = n * target : op[count] = OP_DIV : count += 1
    Return count
End Function

' Find how the target is first made from a subset without building all of its values
Private Function FindExact(ByRef s As SolveState, ByVal mask As ULong, ByRef hit As Entry) As Boolean
    Dim As ULong m(0 To 5)
    Dim As UByte op(0 To 5)
    Dim As ULong left_ = (mask - 1) And mask
    While left_
        Dim As ULong right_ = mask Xor left_
        ' Visit splits in the same order as building so the same origin wins
        If left_ < right_ Then
            Dim As Entry Ptr lefts = s.arena + s.off(left_), rights = s.arena + s.off(right_)
            Dim As ULong nl = s.length(left_), nr = s.length(right_)
            ' Keep the lowest pair as building would since partners come in operator order
            Dim As ULong best_a = &hFFFFFFFF, best_b = &hFFFFFFFF
            Dim As UByte best_op = 0
            If nl <= nr Then
                ' Take the first left value with any partner on the right since left values ascend
                Dim As ULong i = 0
                While i < nl AndAlso best_op = 0
                    Dim As Long count = Partners(lefts[i].value, s.target, @m(0), @op(0))
                    For k As Long = 0 To count - 1
                        If m(k) < best_b AndAlso Lookup(rights, nr, m(k)) <> 0 Then
                            best_a = lefts[i].value : best_b = m(k) : best_op = op(k)
                        End If
                    Next
                    i += 1
                Wend
            Else
                For j As ULong = 0 To nr - 1
                    Dim As Long count = Partners(rights[j].value, s.target, @m(0), @op(0))
                    For k As Long = 0 To count - 1
                        If m(k) < best_a AndAlso Lookup(lefts, nl, m(k)) <> 0 Then
                            best_a = m(k) : best_b = rights[j].value : best_op = op(k)
                        End If
                    Next
                Next
            End If
            If best_op Then
                hit.value = s.target
                hit.op = best_op
                If best_a >= best_b Then
                    hit.larger = best_a : hit.smaller = best_b : hit.larger_mask = left_ : hit.smaller_mask = right_
                Else
                    hit.larger = best_b : hit.smaller = best_a : hit.larger_mask = right_ : hit.smaller_mask = left_
                End If
                Return True
            End If
        End If
        left_ = (left_ - 1) And mask
    Wend
    Return False
End Function

' Build the sorted reachable values of a subset into the arena keeping only the first way found to make each
Private Sub Build(ByRef s As SolveState, ByVal mask As ULong)
    Dim As ULongInt Ptr seen = s.seen
    Dim As UInteger count = 0
    ' Mark zero as seen so inexact divisions never become entries
    seen[0] Or= 1
    Dim As ULong left_ = (mask - 1) And mask
    While left_
        Dim As ULong right_ = mask Xor left_
        ' Visit each split once rather than once per ordering
        If left_ < right_ Then
            ' Reserve room for every pair's results plus the one slot each store may write past the end
            Dim As UInteger pair_count = 4 * CULngInt(s.length(left_)) * s.length(right_)
            Dim As UInteger bound = s.max_value(mask)
            s.tmp = Grow(s.tmp, s.tmp_cap, count + IIf(pair_count < bound, pair_count, bound) + 1, SizeOf(Entry))
            Dim As Entry Ptr out_ = s.tmp + count
            PAIRS(s, left_, right_, EMIT)
            count = out_ - s.tmp
        End If
        left_ = (left_ - 1) And mask
    Wend
    seen[0] And= Not 1ull

    s.arena = Grow(s.arena, s.cap, s.top + count, SizeOf(Entry))
    Dim As Entry Ptr sorted = s.arena + s.top
    If count < RANK_MIN Then
        ' Clear only the words this subset touched and insertion sort the few values
        For i As UInteger = 0 To count - 1
            Dim As Entry e = s.tmp[i]
            seen[e.value Shr 6] = 0
            Dim As UInteger k = i
            While k > 0 AndAlso sorted[k - 1].value > e.value
                sorted[k] = sorted[k - 1]
                k -= 1
            Wend
            sorted[k] = e
        Next
    Else
        ' Place each value at its rank in the bitset which needs no comparisons
        Dim As ULong words = s.max_value(mask) \ 64 + 1, below = 0
        For w As ULong = 0 To words - 1
            s.rank[w] = below
            below += PopCount64(seen[w])
        Next
        For i As UInteger = 0 To count - 1
            Dim As ULong v = s.tmp[i].value
            Dim As ULongInt lower = seen[v Shr 6] And ((1ull Shl (v And 63)) - 1)
            sorted[s.rank[v Shr 6] + PopCount64(lower)] = s.tmp[i]
        Next
        memset(seen, 0, words * SizeOf(ULongInt))
    End If
    s.off(mask) = s.top
    s.length(mask) = count
    s.top += count
End Sub

' Make the bitset and its ranks cover every value up to largest
Private Sub ReserveSeen(ByRef s As SolveState, ByVal largest As ULong)
    Dim As UInteger words = largest \ 64 + 1
    If words <= s.seen_words Then Exit Sub
    ' Replace rather than copy since building leaves the bitset clear
    free(s.seen)
    free(s.rank)
    s.seen = calloc(words, SizeOf(ULongInt))
    s.rank = malloc(words * SizeOf(ULong))
    If s.seen = 0 OrElse s.rank = 0 Then
        Print "out of memory"
        End 2
    End If
    s.seen_words = words
End Sub

' Make room for the values and reciprocals of the largest subset built so far
Private Sub ReserveRights(ByRef s As SolveState)
    Dim As UInteger biggest = 0
    For mask As ULong = 1 To s.full
        If s.length(mask) > biggest Then biggest = s.length(mask)
    Next
    Dim As UInteger cap = s.right_cap
    s.right_values = Grow(s.right_values, s.right_cap, biggest, SizeOf(ULong))
    If s.right_cap <> cap OrElse s.right_inv = 0 Then
        s.right_inv = realloc(s.right_inv, s.right_cap * SizeOf(Double))
        If s.right_inv = 0 Then
            Print "out of memory"
            End 2
        End If
    End If
End Sub

Private Function Distance(ByVal value As ULong, ByVal target As ULong) As ULong
    Return IIf(value > target, value - target, target - value)
End Function

' Write n in decimal and return the new end
Private Function PutUint(ByVal out_ As UByte Ptr, ByVal n As ULong) As UByte Ptr
    Dim As UByte digits(0 To 9)
    Dim As Long k = 0
    Do
        digits(k) = 48 + n Mod 10
        k += 1
        n \= 10
    Loop While n
    While k
        k -= 1
        *out_ = digits(k)
        out_ += 1
    Wend
    Return out_
End Function

' Write the expression for an entry following its origins back to the pool and return the new end
Private Function Render(ByRef s As SolveState, ByVal e As Entry Ptr, ByVal out_ As UByte Ptr, ByVal bracket As Boolean) As UByte Ptr
    If e->op = 0 Then Return PutUint(out_, e->value)
    If bracket Then *out_ = 40 : out_ += 1
    out_ = Render(s, Lookup(s.arena + s.off(e->larger_mask), s.length(e->larger_mask), e->larger), out_, True)
    out_[0] = 32 : out_[1] = e->op : out_[2] = 32
    out_ += 3
    out_ = Render(s, Lookup(s.arena + s.off(e->smaller_mask), s.length(e->smaller_mask), e->smaller), out_, True)
    If bracket Then *out_ = 41 : out_ += 1
    Return out_
End Function

' Return the value of the simplest expression that hits the target or gets closest to it and set expr to its text
Function Solve(ByVal target As ULong, pool() As ULong, ByRef expr As String) As ULong
    Dim As ULong n = UBound(pool) - LBound(pool) + 1
    Dim As SolveState Ptr sp = calloc(1, SizeOf(SolveState))
    If sp = 0 Then
        Print "out of memory"
        End 2
    End If
    Dim ByRef As SolveState s = *sp
    s.target = target
    s.full = (1 Shl n) - 1

    ' Work out each subset's largest value since subtracting and dividing never exceed the larger operand
    Dim As ULong largest(0 To 9)
    For mask As ULong = 1 To s.full
        If (mask And (mask - 1)) = 0 Then
            s.max_value(mask) = pool(LBound(pool) + LowestBit(mask))
        Else
            Dim As ULong left_ = (mask - 1) And mask
            While left_
                Dim As ULongInt a = s.max_value(left_), b = s.max_value(mask Xor left_)
                Dim As ULongInt m = IIf(a * b > a + b, a * b, a + b)
                If m > s.max_value(mask) Then s.max_value(mask) = m
                left_ = (left_ - 1) And mask
            Wend
        End If
        ' Track the largest value of each size so the bitset only grows when bigger subsets are built
        Dim As ULong size = PopCount64(mask)
        If s.max_value(mask) > largest(size) Then largest(size) = s.max_value(mask)
    Next

    ' Store each pool number as a one-number subset
    s.arena = Grow(0, s.cap, 4096, SizeOf(Entry))
    Dim As Entry Ptr best = 0
    For i As ULong = 0 To n - 1
        Cast(ULongInt Ptr, @s.arena[i])[0] = pool(LBound(pool) + i)
        Cast(ULongInt Ptr, @s.arena[i])[1] = 0
        s.off(1 Shl i) = i
        s.length(1 Shl i) = 1
        If best = 0 AndAlso s.arena[i].value = target Then best = @s.arena[i]
    Next
    s.top = n

    ' List subsets by size then mask so the loops below need no unpredictable size test
    Dim As UByte order(0 To 255)
    Dim As ULong first(0 To 9), fill(0 To 9)
    For mask As ULong = 1 To s.full
        first(PopCount64(mask) + 1) += 1
    Next
    For size As ULong = 1 To n + 1
        first(size) += first(size - 1)
    Next
    For size As ULong = 0 To 9
        fill(size) = first(size)
    Next
    For mask As ULong = 1 To s.full
        Dim As ULong size = PopCount64(mask)
        order(fill(size)) = mask
        fill(size) += 1
    Next

    ' Work through subsets smallest first stopping at the first size that hits the target
    Dim As Entry hit
    Dim As ULong size = 2
    While size <= n AndAlso best = 0
        ' Keep the lowest matching subset of this size to break ties the same way every run
        Dim As ULong k = first(size)
        While k < first(size + 1) AndAlso best = 0
            If FindExact(s, order(k), hit) Then best = @hit
            k += 1
        Wend
        ' Skip building the whole pool's values since no larger subset is made from them
        If best <> 0 OrElse size = n Then Exit While
        ReserveRights(s)
        ReserveSeen(s, largest(size))
        For k = first(size) To first(size + 1) - 1
            Build(s, order(k))
        Next
        size += 1
    Wend

    Dim As Entry whole
    If best = 0 Then
        ' Rank by distance from the target then by how many numbers are used so the simplest answer wins
        Dim As ULong best_distance = &hFFFFFFFF
        Dim As Long best_used = 99
        ' Include a one-number pool here since the whole-pool pass below needs at least two numbers
        Dim As ULong last = IIf(n > 1, s.full - 1, s.full)
        For mask As ULong = 1 To last
            Dim As Long used = PopCount64(mask)
            Dim As Entry Ptr values = s.arena + s.off(mask)
            For i As ULong = 0 To s.length(mask) - 1
                Dim As ULong d = Distance(values[i].value, target)
                If d < best_distance OrElse (d = best_distance AndAlso used < best_used) Then
                    best = @values[i] : best_distance = d : best_used = used
                End If
            Next
        Next
        ' Check the whole pool's values as they are made since no larger subset is built from them
        If n > 1 Then
            ReserveRights(s)
            Dim As ULong whole_distance = &hFFFFFFFF
            Dim As ULongInt whole_head = &hFFFFFFFF, whole_operands = 0
            Dim As ULong full = s.full
            Dim As ULong left_ = (full - 1) And full
            While left_
                If left_ < (full Xor left_) Then
                    Dim As ULong right_ = full Xor left_
                    PAIRS(s, left_, right_, CHECK)
                End If
                left_ = (left_ - 1) And full
            Wend
            ' Fall back to the whole pool only when it gets strictly closer as it uses the most numbers
            If whole_distance < best_distance Then
                Cast(ULongInt Ptr, @whole)[0] = whole_head
                Cast(ULongInt Ptr, @whole)[1] = whole_operands
                best = @whole
            End If
        End If
    End If

    ' Render without outer brackets which matches stripping them from the bracketed form
    Dim As UByte text(0 To 127)
    Dim As UByte Ptr end_ = Render(s, best, @text(0), False)
    *end_ = 0
    expr = *Cast(ZString Ptr, @text(0))
    Dim As ULong value = best->value
    free(s.arena)
    free(s.tmp)
    free(s.seen)
    free(s.rank)
    free(s.right_values)
    free(s.right_inv)
    free(sp)
    Return value
End Function
