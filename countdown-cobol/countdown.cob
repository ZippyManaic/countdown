       >>SOURCE FORMAT FREE
*> Generate a Countdown numbers round and work out whether it can be solved
IDENTIFICATION DIVISION.
PROGRAM-ID. countdown.

DATA DIVISION.
WORKING-STORAGE SECTION.
01 large-numbers.
   05 FILLER                PIC 9(3) VALUE 25.
   05 FILLER                PIC 9(3) VALUE 50.
   05 FILLER                PIC 9(3) VALUE 75.
   05 FILLER                PIC 9(3) VALUE 100.
01 large-table REDEFINES large-numbers.
   05 large-number          PIC 9(3) OCCURS 4 TIMES.
01 target                   PIC 9(9) COMP-5.
01 pool.
   05 pool-number           PIC 9(9) COMP-5 OCCURS 6 TIMES.
01 pool-size                PIC 9(9) COMP-5 VALUE 6.
01 small.
   05 small-number          PIC 9(9) COMP-5 OCCURS 20 TIMES.
01 large.
   05 large-copy            PIC 9(9) COMP-5 OCCURS 4 TIMES.
01 large-count              PIC 9 COMP-5.
01 i                        PIC 9(4) COMP-5.
01 j                        PIC 9(4) COMP-5.
01 swap                     PIC 9(9) COMP-5.
01 seed                     PIC 9(8).
01 r                        PIC V9(9).
01 expr                     PIC X(128).
01 expr-len                 PIC 9(9) COMP-5.
01 answer                   PIC 9(9) COMP-5.
01 away                     PIC 9(9) COMP-5.
01 shown                    PIC Z(8)9.
01 line-text                PIC X(200).
01 line-pos                 PIC 9(4) COMP-5.

PROCEDURE DIVISION.
    *> Seed from the clock since FUNCTION RANDOM repeats otherwise
    MOVE FUNCTION CURRENT-DATE(9:8) TO seed
    COMPUTE r = FUNCTION RANDOM(seed)
    COMPUTE target = 100 + FUNCTION INTEGER(FUNCTION RANDOM * 900)
    COMPUTE large-count = 1 + FUNCTION INTEGER(FUNCTION RANDOM * 2)

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
        MOVE large-number(i) TO large-copy(i)
    END-PERFORM
    PERFORM VARYING i FROM 4 BY -1 UNTIL i < 2
        COMPUTE j = 1 + FUNCTION INTEGER(FUNCTION RANDOM * i)
        MOVE large-copy(i) TO swap
        MOVE large-copy(j) TO large-copy(i)
        MOVE swap TO large-copy(j)
    END-PERFORM
    PERFORM VARYING i FROM 1 BY 1 UNTIL i > 6 - large-count
        MOVE small-number(i) TO pool-number(i)
    END-PERFORM
    PERFORM VARYING i FROM 1 BY 1 UNTIL i > large-count
        MOVE large-copy(i) TO pool-number(6 - large-count + i)
    END-PERFORM

    MOVE target TO shown
    DISPLAY "Target: " FUNCTION TRIM(shown)
    MOVE SPACES TO line-text
    MOVE 1 TO line-pos
    STRING "Pool:  " DELIMITED BY SIZE INTO line-text WITH POINTER line-pos
    PERFORM VARYING i FROM 1 BY 1 UNTIL i > 6
        MOVE pool-number(i) TO shown
        STRING " " FUNCTION TRIM(shown) DELIMITED BY SIZE INTO line-text WITH POINTER line-pos
    END-PERFORM
    DISPLAY line-text(1:line-pos - 1)

    CALL "solve" USING target pool pool-size expr answer expr-len
    MOVE answer TO shown
    IF answer = target
        DISPLAY "Solved: " expr(1:expr-len) " = " FUNCTION TRIM(shown)
        STOP RUN RETURNING 0
    END-IF
    COMPUTE away = FUNCTION ABS(answer - target)
    MOVE SPACES TO line-text
    MOVE 1 TO line-pos
    STRING "No exact solution, closest is " expr(1:expr-len) " = " FUNCTION TRIM(shown)
        DELIMITED BY SIZE INTO line-text WITH POINTER line-pos
    MOVE away TO shown
    STRING " (" FUNCTION TRIM(shown) " away)" DELIMITED BY SIZE INTO line-text WITH POINTER line-pos
    DISPLAY line-text(1:line-pos - 1)
    STOP RUN RETURNING 1.
