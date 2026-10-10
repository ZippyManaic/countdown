\ Generate a Countdown numbers round and work out whether it can be solved
require random.fs
require solver.fs

create large-numbers 25 , 50 , 75 , 100 ,
create small 20 cells allot
create large 4 cells allot
create round 6 cells allot

\ Shuffle n cells at addr in place with Fisher-Yates
: shuffle { addr n -- }
    1 n 1- ?do
        i 1+ random { k }
        addr i cells + @ addr k cells + @
        addr i cells + ! addr k cells + !
    -1 +loop ;

: .number ( u -- ) 0 <# #s #> type ;

: main ( -- )
    \ Seed from the clock since the generator starts from a fixed seed
    utime drop seed !
    \ Discard a few outputs since nearby seeds give nearby first outputs
    16 0 do rnd drop loop
    900 random 100 + { goal }
    2 random 1+ { large-count }
    \ Hold two cards of each small number to match the game's deck
    20 0 do i 10 mod 1+ small i cells + ! loop
    small 20 shuffle
    \ Shuffle a copy since each large number appears only once in the game
    large-numbers large 4 cells move
    large 4 shuffle
    small round 6 large-count - cells move
    large round 6 large-count - cells + large-count cells move

    ." Target: " goal .number cr
    ." Pool:  " 6 0 do space round i cells + @ .number loop cr
    goal round 6 solve { value c-addr u }
    value goal = if
        ." Solved: " c-addr u type ."  = " value .number cr
        bye
    then
    ." No exact solution, closest is " c-addr u type ."  = " value .number
    ."  (" value goal - abs .number ."  away)" cr
    1 (bye) ;

main
