       >>SOURCE FORMAT FREE
*> Check the solver against rounds with known answers
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
    IF failures > 0
        STOP RUN RETURNING 1
    END-IF
    DISPLAY "all tests passed"
    STOP RUN.
