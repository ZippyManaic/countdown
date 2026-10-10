\ Time the solver over a file of rounds and write each answer as value tab expression
\ Take the solver directory, rounds file, output file and repeat count from the command line
next-arg 2constant solver-dir
next-arg 2constant rounds-file
next-arg 2constant out-file
next-arg s>number? 0= [if] 2drop 1. [then] drop constant reps

: load-solver ( -- ) solver-dir s" /solver.fs" s+ included ;
load-solver

20000 constant max-rounds
create rounds max-rounds 7 * cells allot
variable round-count
create values max-rounds cells allot
create exprs max-rounds 128 * chars allot
create expr-lens max-rounds cells allot
create line 256 chars allot

\ Parse up to seven numbers from a line into the next round
: parse-round ( c-addr u -- )
    round-count @ 7 * cells rounds + { dest }
    7 0 do
        begin dup if over c@ bl = else false then while 1 /string repeat
        0. 2swap >number 2swap drop dest i cells + !
    loop 2drop 1 round-count +! ;

: load-rounds ( -- )
    rounds-file r/o open-file throw { fid }
    begin line 256 fid read-line throw while line swap parse-round repeat drop
    fid close-file throw ;

\ Solve every round reps times then report the time per round and write the answers
: run ( -- )
    load-rounds
    utime
    reps 0 ?do
        round-count @ 0 ?do
            rounds i 7 * cells + dup @ swap cell+ 6 solve
            expr-lens i cells + ! exprs i 128 * + 128 move values i cells + !
        loop
    loop
    utime 2swap d- d>f 1e3 f/ round-count @ reps * s>d d>f f/
    f. ." ms/round" cr
    out-file w/o create-file throw { out }
    round-count @ 0 ?do
        i if s\" \n" out write-file throw then
        values i cells + @ 0 <# #s #> out write-file throw
        s\" \t" out write-file throw
        exprs i 128 * + expr-lens i cells + @ out write-file throw
    loop
    out close-file throw ;

run
bye
