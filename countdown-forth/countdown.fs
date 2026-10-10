\ Generate a Countdown numbers round and work out whether it can be solved
require solver.fs
require deal.fs

create arguments 6 cells allot

: .number ( u -- ) 0 <# #s #> type ;

\ Collect the command-line arguments as pairs in arguments and return how many there were
: collect-args ( -- n )
    0 begin next-arg dup while
        2 pick 3 < if 2 pick 2* cells arguments + 2! else 2drop then
        1+
    repeat 2drop ;

: main ( -- )
    arguments collect-args parse-args { mode fixed }
    mode 0< if .usage 2 (bye) then
    \ Seed from the clock since the generator starts from a fixed seed
    utime drop seed !
    \ Discard a few outputs since nearby seeds give nearby first outputs
    16 0 do rnd drop loop
    mode fixed generate-round { goal }

    ." Target: " goal .number cr
    ." Pool:  " 6 0 do space hand i cells + @ .number loop cr
    goal hand 6 solve { value c-addr u }
    value goal = if
        ." Solved: " c-addr u type ."  = " value .number cr
        bye
    then
    ." No exact solution, closest is " c-addr u type ."  = " value .number
    ."  (" value goal - abs .number ."  away)" cr
    1 (bye) ;

main
