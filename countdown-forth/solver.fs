\ Work out the simplest Countdown expression that hits a target or gets closest to it

\ Pack each origin as operator code, the larger half's mask shifted by 8 and the larger operand shifted by 16
1 constant op-add
2 constant op-sub
3 constant op-mul
4 constant op-div

256 constant max-subsets
create sub-addr max-subsets cells allot
create sub-len max-subsets cells allot
create sub-max max-subsets cells allot
create sub-size max-subsets cells allot
create pool 8 cells allot
variable pool-n
variable target
variable full

\ Hold the subsets of each size in mask order so loops need no size test
create by-size 9 max-subsets * cells allot
create by-size-count 9 cells allot

\ Mark each value with the mask of the subset that last made it so no clearing is needed between subsets
0 value stamps
0 value stamp-size
0 value stamp-mask
\ Point at the next free candidate slot while a subset is being built
variable out
variable cand-addr
variable cand-cap
variable aux-addr

: entry ( base i -- addr ) 2* cells + ;

\ Store a value with its origin advancing past it only if this subset has not made the value yet
\ Compile the body in place at each use since a call per result costs more than the check itself
: keep ( value origin -- )
    ]] over stamps + dup c@ stamp-mask = if drop 2drop else
        stamp-mask swap c! swap out @ 2! 2 cells out +! then [[ ; immediate

\ Append every legal result of x and y under Countdown rules where x is at least y and base carries the larger half
\ Keep base on the return stack and compile the body in place since a call and locals frame per pair cost more than the work
: emit-pair ( x y base -- )
    ]] >r
    2dup + r@ op-add or keep
    2dup <> if 2dup - r@ op-sub or keep then
    dup 1 <> if
        2dup * r@ op-mul or keep
        2dup /mod swap 0= if r@ op-div or keep else drop then
    then
    2drop r> drop [[ ; immediate

\ Append every new value from pairing each left value with each right value of one split
: build-split { left right -- }
    sub-addr right cells + @ { rights }
    rights sub-len right cells + @ 2* cells + { rights-end }
    left 8 lshift { left-code }
    right 8 lshift { right-code }
    sub-addr left cells + @ dup sub-len left cells + @ 2* cells + swap ?do
        i @ { a }
        a 16 lshift left-code or { left-base }
        rights
        \ Pair with right values up to a first where a is the larger and ties go left
        begin dup rights-end < if dup @ a <= else false then while
            a over @ left-base emit-pair
            2 cells +
        repeat
        \ Pair with the remaining larger right values where a is the smaller
        begin dup rights-end < while
            dup @ { b } b a b 16 lshift right-code or emit-pair
            2 cells +
        repeat drop
    2 cells +loop ;

create counts 256 cells allot

\ Sort n value and origin pairs at addr by value a byte at a time using the auxiliary buffer
: radix-sort { addr n -- }
    addr aux-addr @ { src dst }
    4 0 do
        i { digit }
        counts 256 cells erase
        src n 2* cells bounds ?do 1 counts i digit + c@ cells + +! 2 cells +loop
        \ Skip a byte every value shares
        counts src digit + c@ cells + @ n <> if
            \ Turn the counts into the first slot for each byte value
            0 counts 256 cells bounds do i @ over i ! + cell +loop drop
            src n 2* cells bounds ?do
                counts i digit + c@ cells + dup @ dup 1+ rot !
                dst swap entry i 2@ rot 2!
            2 cells +loop
            src dst to src to dst
        then
    loop
    \ Copy back when an odd number of passes left the result in the auxiliary buffer
    src addr <> if src addr n 2* cells move then ;

\ Sort n value and origin pairs at addr by insertion which suits short runs
: insertion-sort { addr n -- }
    n 1 ?do
        addr i entry 2@ { origin value }
        i begin dup 0> if addr over 1- entry @ value > else false then while
            addr over 1- entry 2@ addr 3 pick entry 2! 1-
        repeat
        >r origin value addr r> entry 2!
    loop ;

\ Build the sorted reachable values of a subset keeping only the first way found to make each
: build { mask -- }
    mask to stamp-mask
    cand-addr @ out !
    mask 1- mask and
    begin dup while { left }
        mask left xor { right }
        \ Visit each split once rather than once per ordering
        left right < if
            \ Reserve room for every pair's results plus one before building the split
            out @ cand-addr @ - 2 cells / { count }
            sub-len left cells + @ sub-len right cells + @ * 4 * sub-max mask cells + @ min count + 1+ { need }
            need cand-cap @ > if
                cand-cap @ begin dup need < while 2* repeat { cap }
                cand-addr @ cap 2* cells resize throw cand-addr !
                aux-addr @ cap 2* cells resize throw aux-addr !
                cap cand-cap !
                cand-addr @ count entry out !
            then
            left right build-split
        then
        left 1- mask and
    repeat drop
    out @ cand-addr @ - 2 cells / { total }
    total 32 < if cand-addr @ total insertion-sort else cand-addr @ total radix-sort then
    total 2* cells allocate throw dup sub-addr mask cells + !
    cand-addr @ swap total 2* cells move
    total sub-len mask cells + ! ;

\ Return the index of value among a subset's sorted values or -1 when it is absent
: find-value { mask value -- index }
    sub-addr mask cells + @ { base }
    sub-len mask cells + @ { n }
    \ Skip the search when the value lies outside the subset's range
    value base @ < value base n 1- entry @ > or if -1 exit then
    0 n 1- { lo hi }
    begin lo hi < while
        lo hi + 1+ 2/ { mid }
        base mid entry @ value > if mid 1- to hi else mid to lo then
    repeat
    base lo entry @ value = if lo else -1 then ;

variable best-a
variable best-b
variable best-op

\ Record a partner when it is lower than the best so far and the searched subset can make it
: try-partner { other op search-mask n left-loop -- }
    left-loop if other best-b @ else other best-a @ then >= if exit then
    search-mask other find-value 0< if exit then
    left-loop if n best-a ! other best-b ! else other best-a ! n best-b ! then
    op best-op ! ;

\ Try every number that combines with n under Countdown rules to make the target in operator order
: try-partners { n search-mask left-loop -- }
    target @ { t }
    t n > if t n - op-add search-mask n left-loop try-partner then
    n t > if n t - op-sub search-mask n left-loop try-partner then
    n t + op-sub search-mask n left-loop try-partner
    \ Divide only when the quotient could be at least two since neither operand may be one
    n 1 <> n 2* t <= and if t n /mod swap 0= if op-mul search-mask n left-loop try-partner else drop then then
    n t 2* >= if n t /mod swap 0= if op-div search-mask n left-loop try-partner else drop then then
    n 1 <> if n t * op-div search-mask n left-loop try-partner then ;

\ Return the origin of the target made from a subset without building all of its values or zero when it cannot be made
: find-exact { mask -- origin }
    mask 1- mask and
    begin dup while { left }
        mask left xor { right }
        \ Visit splits in the same order as building so the same origin wins
        left right < if
            -1 1 rshift dup best-a ! best-b ! 0 best-op !
            sub-len left cells + @ sub-len right cells + @ <= if
                \ Take the first left value with any partner on the right since left values ascend
                sub-addr left cells + @ dup sub-len left cells + @ 2* cells + swap ?do
                    i @ right true try-partners
                    best-op @ if leave then
                2 cells +loop
            else
                sub-addr right cells + @ dup sub-len right cells + @ 2* cells + swap ?do
                    i @ left false try-partners
                2 cells +loop
            then
            best-op @ if
                best-a @ best-b @ >= if
                    best-op @ left 8 lshift or best-a @ 16 lshift or
                else
                    best-op @ right 8 lshift or best-b @ 16 lshift or
                then
                exit
            then
        then
        left 1- mask and
    repeat ;

\ Return the smaller operand of a value made from a larger operand with an operator
: smaller-of { value larger op -- smaller }
    op op-add = if value larger - exit then
    op op-sub = if larger value - exit then
    op op-mul = if value larger / exit then
    larger value / ;

create expr 256 chars allot
variable expr-len

: put ( c-addr u -- ) tuck expr expr-len @ + swap move expr-len +! ;

\ Write the expression for a value made from subset mask by following its origins back to the pool
: render { mask value origin bracket -- }
    origin 0= if value 0 <# #s #> put exit then
    origin 255 and { op }
    origin 8 rshift 255 and { lm }
    origin 16 rshift { larger }
    mask lm xor { sm }
    value larger op smaller-of { smaller }
    bracket if s" (" put then
    lm larger sub-addr lm cells + @ lm larger find-value entry cell+ @ true recurse
    s"  " put op 1- s" +-*/" drop + 1 put s"  " put
    sm smaller sub-addr sm cells + @ sm smaller find-value entry cell+ @ true recurse
    bracket if s" )" put then ;

variable best-value
variable best-origin
variable best-mask
variable best-distance
variable best-used

: distance ( value -- d ) target @ - abs ;

variable whole-value
variable whole-origin
variable whole-distance

\ Keep a whole-pool value if it is closer to the target or equally close and lower
: consider-whole { value origin -- }
    value 0= if exit then
    value distance { d }
    d whole-distance @ < d whole-distance @ = value whole-value @ < and or if
        value whole-value ! origin whole-origin ! d whole-distance !
    then ;

\ Check every legal result of x and y against the whole pool's best
: check-pair { x y base -- }
    x y + base op-add or consider-whole
    x y <> if x y - base op-sub or consider-whole then
    y 1 <> if
        x y * base op-mul or consider-whole
        x y /mod swap 0= if base op-div or consider-whole else drop then
    then ;

\ Check every pair of values from one split of the whole pool
: check-split { left right -- }
    sub-addr right cells + @ { rights }
    rights sub-len right cells + @ 2* cells + { rights-end }
    sub-addr left cells + @ dup sub-len left cells + @ 2* cells + swap ?do
        i @ { a }
        rights
        begin dup rights-end < if dup @ a <= else false then while
            a over @ a 16 lshift left 8 lshift or check-pair
            2 cells +
        repeat
        begin dup rights-end < while
            dup @ { b } b a b 16 lshift right 8 lshift or check-pair
            2 cells +
        repeat drop
    2 cells +loop ;

\ Make the stamp table cover every value up to largest replacing it since old stamps never match a new mask
: reserve-stamps { largest -- }
    largest 1+ stamp-size > if
        stamps ?dup if free throw then
        largest 1+ dup allocate throw dup to stamps swap erase
        largest 1+ to stamp-size
    then ;

\ Return the simplest expression that hits the target or gets closest to it with its value
: solve ( target pool-addr n -- value c-addr u )
    dup pool-n ! pool swap cells move target !
    1 pool-n @ lshift 1- full !
    sub-len max-subsets cells erase
    sub-addr max-subsets cells erase
    by-size-count 9 cells erase
    \ Work out each subset's size and largest value since subtracting and dividing never exceed the larger operand
    full @ 1+ 1 do
        0 i begin dup while dup 1- and swap 1+ swap repeat drop { size }
        size sub-size i cells + !
        i by-size size max-subsets * by-size-count size cells + @ + cells + !
        1 by-size-count size cells + +!
        size 1 = if
            0 i begin dup 1 and 0= while 1 rshift swap 1+ swap repeat drop
            cells pool + @ sub-max i cells + !
        else
            0 i 1- i and begin dup while { left }
                sub-max left cells + @ sub-max i left xor cells + @ 2dup * -rot + max max
                left 1- i and
            repeat drop sub-max i cells + !
        then
    loop
    0 to stamps 0 to stamp-size
    1024 cand-cap ! 1024 2* cells allocate throw cand-addr ! 1024 2* cells allocate throw aux-addr !
    0 best-mask ! 0 best-origin !

    \ Store each pool number as a one-number subset
    pool-n @ 0 do
        2 cells allocate throw dup sub-addr 1 i lshift cells + ! 0 pool i cells + @ rot 2!
        1 sub-len 1 i lshift cells + !
        pool i cells + @ target @ = best-mask @ 0= and if
            1 i lshift best-mask ! target @ best-value ! 0 best-origin !
        then
    loop

    \ Work through subsets smallest first stopping at the first size that hits the target
    pool-n @ 1+ 2 ?do
        best-mask @ if leave then
        \ Keep the lowest matching subset of this size to break ties the same way every run
        by-size-count i cells + @ 0 ?do
            by-size j max-subsets * i + cells + @ { mask }
            mask find-exact ?dup if best-origin ! mask best-mask ! target @ best-value ! leave then
        loop
        \ Skip building the whole pool's values since no larger subset is made from them
        best-mask @ i pool-n @ = or if leave then
        0 by-size-count i cells + @ 0 ?do by-size j max-subsets * i + cells + @ sub-max swap cells + @ max loop
        reserve-stamps
        by-size-count i cells + @ 0 ?do by-size j max-subsets * i + cells + @ build loop
    loop

    best-mask @ 0= if
        \ Rank by distance from the target then by how many numbers are used so the simplest answer wins
        -1 1 rshift best-distance ! 99 best-used !
        \ Include a one-number pool here since the whole-pool pass below needs at least two numbers
        full @ pool-n @ 1 = - 1 ?do
            sub-addr i cells + @ dup sub-len i cells + @ 2* cells + swap ?do
                i @ distance { d }
                d best-distance @ < d best-distance @ = j sub-size swap cells + @ best-used @ < and or if
                    j best-mask ! i 2@ best-value ! best-origin ! d best-distance !
                    j sub-size swap cells + @ best-used !
                then
            2 cells +loop
        loop
        \ Check the whole pool's values as they are made since no larger subset is built from them
        pool-n @ 1 > if
            -1 1 rshift whole-distance ! -1 1 rshift whole-value ! 0 whole-origin !
            full @ 1- full @ and
            begin dup while { left }
                left full @ left xor < if left full @ left xor check-split then
                left 1- full @ and
            repeat drop
            \ Fall back to the whole pool only when it gets strictly closer as it uses the most numbers
            whole-distance @ best-distance @ < if
                full @ best-mask ! whole-value @ best-value ! whole-origin @ best-origin !
            then
        then
    then

    0 expr-len !
    best-mask @ best-value @ best-origin @ false render
    full @ 1+ 1 ?do sub-addr i cells + @ ?dup if free throw then loop
    stamps ?dup if free throw then
    cand-addr @ free throw
    aux-addr @ free throw
    best-value @ expr expr-len @ ;
