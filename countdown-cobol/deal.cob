       >>SOURCE FORMAT FREE
*> Deal Countdown rounds in standard, cats and nasty-cats modes and read the mode from the command line

*> Deal a target and six numbers for mode 0 (standard), 1 (cats) or 2 (nasty), drawing the large count at random when fixed is negative
IDENTIFICATION DIVISION.
PROGRAM-ID. generate-round.

DATA DIVISION.
WORKING-STORAGE SECTION.
*> Hold four large cards for each mode in turn, with nasty-cats using the cards of the 2010 specials
01 large-numbers.
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
01 large-table REDEFINES large-numbers.
   05 large-number          PIC 9(3) OCCURS 12 TIMES.
01 small.
   05 small-number          PIC 9(9) COMP-5 OCCURS 20 TIMES.
01 large.
   05 large-copy            PIC 9(9) COMP-5 OCCURS 4 TIMES.
01 large-count              PIC 9 COMP-5.
01 i                        PIC 9(4) COMP-5.
01 j                        PIC 9(4) COMP-5.
01 swap                     PIC 9(9) COMP-5.

LINKAGE SECTION.
01 lk-mode                  PIC 9 COMP-5.
01 lk-fixed                 PIC S9 COMP-5.
01 lk-target                PIC 9(9) COMP-5.
01 lk-pool.
   05 lk-number             PIC 9(9) COMP-5 OCCURS 6 TIMES.

PROCEDURE DIVISION USING lk-mode lk-fixed lk-target lk-pool.
    COMPUTE lk-target = 100 + FUNCTION INTEGER(FUNCTION RANDOM * 900)
    EVALUATE TRUE
        WHEN lk-fixed >= 0
            MOVE lk-fixed TO large-count
        WHEN lk-mode = 0
            COMPUTE large-count = 1 + FUNCTION INTEGER(FUNCTION RANDOM * 2)
        WHEN OTHER
            COMPUTE large-count = FUNCTION INTEGER(FUNCTION RANDOM * 5)
    END-EVALUATE

    *> Hold two cards of each small number to match the game's deck
    PERFORM VARYING i FROM 1 BY 1 UNTIL i > 20
        COMPUTE small-number(i) = FUNCTION MOD(i - 1, 10) + 1
    END-PERFORM
    *> Shuffle with Fisher-Yates
    PERFORM VARYING i FROM 20 BY -1 UNTIL i < 2
        COMPUTE j = 1 + FUNCTION INTEGER(FUNCTION RANDOM * i)
        MOVE small-number(i) TO swap
        MOVE small-number(j) TO small-number(i)
        MOVE swap TO small-number(j)
    END-PERFORM
    *> Shuffle a copy since each large number appears only once in the game
    PERFORM VARYING i FROM 1 BY 1 UNTIL i > 4
        MOVE large-number(lk-mode * 4 + i) TO large-copy(i)
    END-PERFORM
    PERFORM VARYING i FROM 4 BY -1 UNTIL i < 2
        COMPUTE j = 1 + FUNCTION INTEGER(FUNCTION RANDOM * i)
        MOVE large-copy(i) TO swap
        MOVE large-copy(j) TO large-copy(i)
        MOVE swap TO large-copy(j)
    END-PERFORM
    PERFORM VARYING i FROM 1 BY 1 UNTIL i > 6 - large-count
        MOVE small-number(i) TO lk-number(i)
    END-PERFORM
    PERFORM VARYING i FROM 1 BY 1 UNTIL i > large-count
        MOVE large-copy(i) TO lk-number(6 - large-count + i)
    END-PERFORM
    GOBACK.
END PROGRAM generate-round.

*> Parse up to two arguments into a mode and fixed large count, setting valid to 0 when they are invalid
IDENTIFICATION DIVISION.
PROGRAM-ID. parse-args.

DATA DIVISION.
LINKAGE SECTION.
01 lk-count                 PIC 9(4) COMP-5.
01 lk-first                 PIC X(64).
01 lk-second                PIC X(64).
01 lk-mode                  PIC 9 COMP-5.
01 lk-fixed                 PIC S9 COMP-5.
01 lk-valid                 PIC 9 COMP-5.

PROCEDURE DIVISION USING lk-count lk-first lk-second lk-mode lk-fixed lk-valid.
    MOVE 0 TO lk-valid
    MOVE 0 TO lk-mode
    MOVE -1 TO lk-fixed
    IF lk-count > 2
        GOBACK
    END-IF
    IF lk-count > 0
        EVALUATE lk-first
            WHEN "standard" MOVE 0 TO lk-mode
            WHEN "cats" MOVE 1 TO lk-mode
            WHEN "nasty" MOVE 2 TO lk-mode
            WHEN OTHER GOBACK
        END-EVALUATE
    END-IF
    IF lk-count = 2
        *> Accept only a single digit followed by spaces
        IF lk-second(1:1) IS NOT NUMERIC OR lk-second(2:) NOT = SPACES
            GOBACK
        END-IF
        MOVE FUNCTION NUMVAL(lk-second(1:1)) TO lk-fixed
        IF lk-mode = 0 AND (lk-fixed < 1 OR lk-fixed > 2)
            GOBACK
        END-IF
        IF lk-fixed > 4
            GOBACK
        END-IF
    END-IF
    MOVE 1 TO lk-valid
    GOBACK.
END PROGRAM parse-args.
