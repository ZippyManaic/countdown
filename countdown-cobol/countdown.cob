       >>SOURCE FORMAT FREE
*> Generate a Countdown numbers round and work out whether it can be solved
IDENTIFICATION DIVISION.
PROGRAM-ID. countdown.

DATA DIVISION.
WORKING-STORAGE SECTION.
01 target                   PIC 9(9) COMP-5.
01 pool.
   05 pool-number           PIC 9(9) COMP-5 OCCURS 6 TIMES.
01 pool-size                PIC 9(9) COMP-5 VALUE 6.
01 game-mode                PIC 9 COMP-5.
01 fixed-large              PIC S9 COMP-5.
01 args-valid               PIC 9 COMP-5.
01 arg-count                PIC 9(4) COMP-5.
01 arg-first                PIC X(64) VALUE SPACES.
01 arg-second               PIC X(64) VALUE SPACES.
01 i                        PIC 9(4) COMP-5.
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
    ACCEPT arg-count FROM ARGUMENT-NUMBER
    IF arg-count > 0
        ACCEPT arg-first FROM ARGUMENT-VALUE
    END-IF
    IF arg-count > 1
        ACCEPT arg-second FROM ARGUMENT-VALUE
    END-IF
    CALL "parse-args" USING arg-count arg-first arg-second game-mode fixed-large args-valid
    IF args-valid = 0
        DISPLAY "usage: countdown [standard|cats|nasty] [LARGE]" UPON SYSERR
        STOP RUN RETURNING 2
    END-IF

    *> Seed from the clock since FUNCTION RANDOM repeats otherwise
    MOVE FUNCTION CURRENT-DATE(9:8) TO seed
    COMPUTE r = FUNCTION RANDOM(seed)
    CALL "generate-round" USING game-mode fixed-large target pool

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
