\ Check the solver against rounds with known answers
require solver.fs

variable failures

\ Report a failed check by name
: check ( flag c-addr u -- ) rot if 2drop else ." FAIL: " type cr 1 failures +! then ;

create round 6 cells allot
: deal ( n1 n2 n3 n4 n5 n6 -- ) 6 0 do round 5 i - cells + ! loop ;

1 5 7 3 75 50 deal
125 round 6 solve s" 75 + 50" compare 0= swap 125 = and s" finds simplest solution" check
8 4 2 5 100 25 deal
552 round 6 solve 2drop 552 = s" solves 552" check
8 8 6 8 25 100 deal
974 round 6 solve 2drop 974 - abs 1 = s" reports closest when unsolvable" check
7 round !
100 round 1 solve s" 7" compare 0= swap 7 = and s" reports a lone number as closest" check
7 round 1 solve s" 7" compare 0= swap 7 = and s" solves with a lone number" check
3 round ! 4 round cell+ !
100 round 2 solve s" 4 * 3" compare 0= swap 12 = and s" reports closest with two numbers" check
require deal.fs

\ Return how often v occurs in hand
: occurrences ( v -- n ) 0 6 0 do over hand i cells + @ = - loop nip ;

\ Return whether v is one of the large cards of mode
: large-of? ( v mode -- flag )
    4 * cells large-numbers + false 4 0 do 2 pick 2 pick i cells + @ = or loop nip nip ;

\ Check the round in hand is legal for mode and return its large count
: check-hand { mode goal -- n }
    goal 100 >= goal 999 <= and s" target in range" check
    0 6 0 do
        hand i cells + @ dup 0> s" six numbers" check
        dup 10 > if
            dup occurrences 1 = s" large numbers distinct" check
            mode large-of? s" large number from the mode's set" check
            1+
        else
            \ Allow each small number at most twice since the deck holds two of each
            occurrences 2 <= s" small number at most twice" check
        then
    loop ;

create seen 7 cells allot

\ Deal 2000 rounds in mode and check each large count lies from lo to hi and every one occurs
: check-mode { mode lo hi -- }
    seen 7 cells erase
    2000 0 do
        mode mode -1 generate-round check-hand
        dup lo >= over hi <= and s" large count allowed" check
        cells seen + 1 swap +!
    loop
    hi 1+ lo do seen i cells + @ 0> s" every large count occurs" check loop ;

\ Check cats and nasty deals with each fixed large count from 0 to 4
: check-fixed ( -- )
    mode-nasty 1+ mode-cats do
        5 0 do j j i generate-round check-hand i = s" fixed large count" check loop
    loop ;

create args 6 cells allot
: arg! ( c-addr u k -- ) 2* cells args + 2! ;

\ Check the parser accepts good arguments and rejects bad ones
: check-parse ( -- )
    args 0 parse-args -1 = swap mode-standard = and s" parses no arguments" check
    s" nasty" 0 arg! s" 4" 1 arg! args 2 parse-args 4 = swap mode-nasty = and s" parses nasty 4" check
    s" cats" 0 arg! s" 0" 1 arg! args 2 parse-args 0= swap mode-cats = and s" parses cats 0" check
    s" standard" 0 arg! s" 3" 1 arg! args 2 parse-args drop -1 = s" rejects standard 3" check
    s" cats" 0 arg! s" 5" 1 arg! args 2 parse-args drop -1 = s" rejects cats 5" check
    s" dogs" 0 arg! args 1 parse-args drop -1 = s" rejects an unknown mode" check
    s" cats" 0 arg! s" 1" 1 arg! s" 2" 2 arg! args 3 parse-args drop -1 = s" rejects three arguments" check
    s" cats" 0 arg! s" x" 1 arg! args 2 parse-args drop -1 = s" rejects a non-numeric count" check ;

1 seed !
mode-standard 1 2 check-mode
mode-cats 0 4 check-mode
mode-nasty 0 4 check-mode
check-fixed
check-parse

10 10 25 50 75 100 deal
999 round 6 solve s" (((75 + 25) * 100) - 10) / 10" compare 0= swap 999 = and s" solves cats round 999" check
1 1 2 2 3 3 deal
100 round 6 solve s" (((2 + 1) * (2 + 1)) * 3) * 3" compare 0= swap 81 = and s" reports closest on cats round with no large" check
2 3 87 62 37 12 deal
999 round 6 solve s" 37 * ((87 / 3) - 2)" compare 0= swap 999 = and s" solves nasty round 999" check
failures @ 0= [if] ." all tests passed" cr bye [else] 1 (bye) [then]
