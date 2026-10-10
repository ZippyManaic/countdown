\ Deal Countdown rounds in standard, cats and nasty-cats modes and read the mode from the command line
require random.fs

0 constant mode-standard
1 constant mode-cats
2 constant mode-nasty

\ Hold four large cards for each mode in turn, with nasty-cats using the cards of the 2010 specials
create large-numbers 25 , 50 , 75 , 100 , 25 , 50 , 75 , 100 , 12 , 37 , 62 , 87 ,
create small 20 cells allot
create large 4 cells allot
create hand 6 cells allot

\ Shuffle n cells at addr in place with Fisher-Yates
: shuffle { addr n -- }
    1 n 1- ?do
        i 1+ random { k }
        addr i cells + @ addr k cells + @
        addr i cells + ! addr k cells + !
    -1 +loop ;

\ Return the number of large cards to deal, drawing it at random when fixed is negative
: large-count-for ( mode fixed -- n )
    dup 0< 0= if nip exit then
    drop mode-standard = if 2 random 1+ else 5 random then ;

\ Deal six numbers into hand and return a target, with one or two large in standard mode and none to four otherwise
: generate-round ( mode fixed -- goal )
    over swap large-count-for { mode large-count }
    900 random 100 + { goal }
    \ Hold two cards of each small number to match the game's deck
    20 0 do i 10 mod 1+ small i cells + ! loop
    small 20 shuffle
    \ Shuffle a copy since each large number appears only once in the game
    large-numbers mode 4 * cells + large 4 cells move
    large 4 shuffle
    small hand 6 large-count - cells move
    large hand 6 large-count - cells + large-count cells move
    goal ;

\ Return the mode with a name or -1 when the name is unknown
: mode-of ( c-addr u -- mode )
    2dup s" standard" compare 0= if 2drop mode-standard exit then
    2dup s" cats" compare 0= if 2drop mode-cats exit then
    s" nasty" compare 0= if mode-nasty else -1 then ;

\ Return the large count a mode allows for a one-digit argument or -1 when it is invalid
: count-of ( mode c-addr u -- fixed )
    1 <> if 2drop -1 exit then
    c@ [char] 0 - swap
    mode-standard = if 1 2 else 0 4 then
    { k lo hi } k lo < k hi > or if -1 else k then ;

\ Parse n arguments stored with 2! as pairs at addr into a mode and fixed count, with mode -1 when they are invalid
: parse-args ( addr n -- mode fixed )
    dup 2 > if 2drop -1 -1 exit then
    dup 0= if 2drop mode-standard -1 exit then
    over 2@ mode-of { addr n mode }
    mode 0< if -1 -1 exit then
    n 1 = if mode -1 exit then
    mode addr 2 cells + 2@ count-of { fixed }
    fixed 0< if -1 -1 else mode fixed then ;

\ Print the usage line to stderr
: .usage ( -- ) s" usage: countdown [standard|cats|nasty] [LARGE]" stderr write-line throw ;
