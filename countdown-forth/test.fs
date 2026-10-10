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
failures @ 0= [if] ." all tests passed" cr bye [else] 1 (bye) [then]
