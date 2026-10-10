       >>SOURCE FORMAT FREE
*> Check the dealer in every mode and the solver on rounds with known answers
IDENTIFICATION DIVISION.
PROGRAM-ID. tests.

DATA DIVISION.
WORKING-STORAGE SECTION.
01 target                   PIC 9(9) COMP-5.
01 pool.
   05 pool-number           PIC 9(9) COMP-5 OCCURS 6 TIMES.
01 pool-size                PIC 9(9) COMP-5 VALUE 6.
01 expr                     PIC X(128).
01 expr-len                 PIC 9(9) COMP-5.
01 answer                   PIC 9(9) COMP-5.
01 failures                 PIC 9(4) COMP-5 VALUE 0.
01 game-mode                PIC 9 COMP-5.
01 fixed-large              PIC S9 COMP-5.
01 args-valid               PIC 9 COMP-5.
01 arg-count                PIC 9(4) COMP-5.
01 arg-first                PIC X(64).
01 arg-second               PIC X(64).
01 lo-count                 PIC 9 COMP-5.
01 hi-count                 PIC 9 COMP-5.
01 large-found              PIC 9 COMP-5.
01 occurrences              PIC 9 COMP-5.
01 in-set                   PIC 9 COMP-5.
01 i                        PIC 9(4) COMP-5.
01 j                        PIC 9(4) COMP-5.
01 k                        PIC 9(4) COMP-5.
01 r                        PIC V9(9).
01 seen-table.
   05 seen                  PIC 9(4) COMP-5 OCCURS 7 TIMES.
*> Hold four large cards for each mode in turn to check deals against
01 mode-numbers.
   05 FILLER                PIC 9(3) VALUE 25.
   05 FILLER                PIC 9(3) VALUE 50.
   05 FILLER                PIC 9(3) VALUE 75.
   05 FILLER                PIC 9(3) VALUE 100.
   05 FILLER                PIC 9(3) VALUE 25.
   05 FILLER                PIC 9(3) VALUE 50.
   05 FILLER                PIC 9(3) VALUE 75.
   05 FILLER                PIC 9(3) VALUE 100.
   05 FILLER                PIC 9(3) VALUE 12.
   05 FILLER                PIC 9(3) VALUE 37.
   05 FILLER                PIC 9(3) VALUE 62.
   05 FILLER                PIC 9(3) VALUE 87.
01 mode-table REDEFINES mode-numbers.
   05 mode-large            PIC 9(3) OCCURS 12 TIMES.

PROCEDURE DIVISION.
    MOVE 125 TO target
    MOVE 1 TO pool-number(1) MOVE 5 TO pool-number(2) MOVE 7 TO pool-number(3)
    MOVE 3 TO pool-number(4) MOVE 75 TO pool-number(5) MOVE 50 TO pool-number(6)
    CALL "solve" USING target pool pool-size expr answer expr-len
    IF answer NOT = 125 OR expr(1:expr-len) NOT = "75 + 50"
        DISPLAY "FAIL: finds simplest solution"
        ADD 1 TO failures
    END-IF
    MOVE 552 TO target
    MOVE 8 TO pool-number(1) MOVE 4 TO pool-number(2) MOVE 2 TO pool-number(3)
    MOVE 5 TO pool-number(4) MOVE 100 TO pool-number(5) MOVE 25 TO pool-number(6)
    CALL "solve" USING target pool pool-size expr answer expr-len
    IF answer NOT = 552
        DISPLAY "FAIL: solves 552"
        ADD 1 TO failures
    END-IF
    MOVE 974 TO target
    MOVE 8 TO pool-number(1) MOVE 8 TO pool-number(2) MOVE 6 TO pool-number(3)
    MOVE 8 TO pool-number(4) MOVE 25 TO pool-number(5) MOVE 100 TO pool-number(6)
    CALL "solve" USING target pool pool-size expr answer expr-len
    IF answer NOT = 973 AND answer NOT = 975
        DISPLAY "FAIL: reports closest when unsolvable"
        ADD 1 TO failures
    END-IF
    MOVE 1 TO pool-size
    MOVE 100 TO target
    MOVE 7 TO pool-number(1)
    CALL "solve" USING target pool pool-size expr answer expr-len
    IF answer NOT = 7 OR expr(1:expr-len) NOT = "7"
        DISPLAY "FAIL: reports a lone number as closest"
        ADD 1 TO failures
    END-IF
    MOVE 7 TO target
    CALL "solve" USING target pool pool-size expr answer expr-len
    IF answer NOT = 7 OR expr(1:expr-len) NOT = "7"
        DISPLAY "FAIL: solves with a lone number"
        ADD 1 TO failures
    END-IF
    MOVE 2 TO pool-size
    MOVE 100 TO target
    MOVE 3 TO pool-number(1) MOVE 4 TO pool-number(2)
    CALL "solve" USING target pool pool-size expr answer expr-len
    IF answer NOT = 12 OR expr(1:expr-len) NOT = "4 * 3"
        DISPLAY "FAIL: reports closest with two numbers"
        ADD 1 TO failures
    END-IF
    MOVE 6 TO pool-size
    COMPUTE r = FUNCTION RANDOM(1)
    MOVE 0 TO game-mode MOVE 1 TO lo-count MOVE 2 TO hi-count
    PERFORM check-mode
    MOVE 1 TO game-mode MOVE 0 TO lo-count MOVE 4 TO hi-count
    PERFORM check-mode
    MOVE 2 TO game-mode
    PERFORM check-mode
    *> Deal cats and nasty rounds with each fixed large count from 0 to 4
    PERFORM VARYING game-mode FROM 1 BY 1 UNTIL game-mode > 2
        PERFORM VARYING k FROM 0 BY 1 UNTIL k > 4
            MOVE k TO fixed-large lo-count hi-count
            CALL "generate-round" USING game-mode fixed-large target pool
            PERFORM check-round
        END-PERFORM
    END-PERFORM

    MOVE 0 TO arg-count
    PERFORM parse-good
    IF args-valid NOT = 1 OR game-mode NOT = 0 OR fixed-large NOT = -1
        DISPLAY "FAIL: parses no arguments"
        ADD 1 TO failures
    END-IF
    MOVE 2 TO arg-count MOVE "nasty" TO arg-first MOVE "4" TO arg-second
    PERFORM parse-good
    IF args-valid NOT = 1 OR game-mode NOT = 2 OR fixed-large NOT = 4
        DISPLAY "FAIL: parses nasty 4"
        ADD 1 TO failures
    END-IF
    MOVE 2 TO arg-count MOVE "cats" TO arg-first MOVE "0" TO arg-second
    PERFORM parse-good
    IF args-valid NOT = 1 OR game-mode NOT = 1 OR fixed-large NOT = 0
        DISPLAY "FAIL: parses cats 0"
        ADD 1 TO failures
    END-IF
    MOVE 2 TO arg-count MOVE "standard" TO arg-first MOVE "3" TO arg-second
    PERFORM parse-bad
    MOVE 2 TO arg-count MOVE "cats" TO arg-first MOVE "5" TO arg-second
    PERFORM parse-bad
    MOVE 1 TO arg-count MOVE "dogs" TO arg-first MOVE SPACES TO arg-second
    PERFORM parse-bad
    MOVE 3 TO arg-count MOVE "cats" TO arg-first MOVE "1" TO arg-second
    PERFORM parse-bad
    MOVE 2 TO arg-count MOVE "cats" TO arg-first MOVE "x" TO arg-second
    PERFORM parse-bad

    MOVE 999 TO target
    MOVE 10 TO pool-number(1) MOVE 10 TO pool-number(2) MOVE 25 TO pool-number(3)
    MOVE 50 TO pool-number(4) MOVE 75 TO pool-number(5) MOVE 100 TO pool-number(6)
    CALL "solve" USING target pool pool-size expr answer expr-len
    IF answer NOT = 999 OR expr(1:expr-len) NOT = "(((75 + 25) * 100) - 10) / 10"
        DISPLAY "FAIL: solves cats round 999"
        ADD 1 TO failures
    END-IF
    MOVE 100 TO target
    MOVE 1 TO pool-number(1) MOVE 1 TO pool-number(2) MOVE 2 TO pool-number(3)
    MOVE 2 TO pool-number(4) MOVE 3 TO pool-number(5) MOVE 3 TO pool-number(6)
    CALL "solve" USING target pool pool-size expr answer expr-len
    IF answer NOT = 81 OR expr(1:expr-len) NOT = "(((2 + 1) * (2 + 1)) * 3) * 3"
        DISPLAY "FAIL: reports closest on cats round with no large"
        ADD 1 TO failures
    END-IF
    MOVE 999 TO target
    MOVE 2 TO pool-number(1) MOVE 3 TO pool-number(2) MOVE 87 TO pool-number(3)
    MOVE 62 TO pool-number(4) MOVE 37 TO pool-number(5) MOVE 12 TO pool-number(6)
    CALL "solve" USING target pool pool-size expr answer expr-len
    IF answer NOT = 999 OR expr(1:expr-len) NOT = "37 * ((87 / 3) - 2)"
        DISPLAY "FAIL: solves nasty round 999"
        ADD 1 TO failures
    END-IF
    IF failures > 0
        STOP RUN RETURNING 1
    END-IF
    DISPLAY "all tests passed"
    *> Return zero explicitly since a bare STOP RUN returns whatever code the last CALL left
    STOP RUN RETURNING 0.

*> Deal 2000 rounds in game-mode and check every large count from lo-count to hi-count occurs
check-mode.
    INITIALIZE seen-table
    MOVE -1 TO fixed-large
    PERFORM 2000 TIMES
        CALL "generate-round" USING game-mode fixed-large target pool
        PERFORM check-round
        ADD 1 TO seen(large-found + 1)
    END-PERFORM
    PERFORM VARYING k FROM lo-count BY 1 UNTIL k > hi-count
        IF seen(k + 1) = 0
            DISPLAY "FAIL: every large count occurs"
            ADD 1 TO failures
        END-IF
    END-PERFORM.

*> Check the dealt round is legal for game-mode and has from lo-count to hi-count large numbers
check-round.
    IF target < 100 OR target > 999
        DISPLAY "FAIL: target in range"
        ADD 1 TO failures
    END-IF
    MOVE 0 TO large-found
    PERFORM VARYING i FROM 1 BY 1 UNTIL i > 6
        IF pool-number(i) = 0
            DISPLAY "FAIL: six numbers"
            ADD 1 TO failures
        END-IF
        MOVE 0 TO occurrences
        PERFORM VARYING j FROM 1 BY 1 UNTIL j > 6
            IF pool-number(j) = pool-number(i)
                ADD 1 TO occurrences
            END-IF
        END-PERFORM
        IF pool-number(i) > 10
            ADD 1 TO large-found
            IF occurrences > 1
                DISPLAY "FAIL: large numbers distinct"
                ADD 1 TO failures
            END-IF
            MOVE 0 TO in-set
            PERFORM VARYING j FROM 1 BY 1 UNTIL j > 4
                IF mode-large(game-mode * 4 + j) = pool-number(i)
                    MOVE 1 TO in-set
                END-IF
            END-PERFORM
            IF in-set = 0
                DISPLAY "FAIL: large number from the mode's set"
                ADD 1 TO failures
            END-IF
        ELSE
            *> Allow each small number at most twice since the deck holds two of each
            IF occurrences > 2
                DISPLAY "FAIL: small number at most twice"
                ADD 1 TO failures
            END-IF
        END-IF
    END-PERFORM
    IF large-found < lo-count OR large-found > hi-count
        DISPLAY "FAIL: large count allowed"
        ADD 1 TO failures
    END-IF.

*> Parse arg-count arguments from arg-first and arg-second
parse-good.
    CALL "parse-args" USING arg-count arg-first arg-second game-mode fixed-large args-valid.

*> Parse the arguments and check they are rejected
parse-bad.
    PERFORM parse-good
    IF args-valid NOT = 0
        DISPLAY "FAIL: rejects " FUNCTION TRIM(arg-first) " " FUNCTION TRIM(arg-second)
        ADD 1 TO failures
    END-IF.
