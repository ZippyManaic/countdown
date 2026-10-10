10 REM Time the solver over a file of rounds and write each answer as value tab expression
20 REM Take the rounds file, output file and repeat count from the environment since bwBASIC reads no arguments
30 IN$ = ENVIRON$("COUNTDOWN_ROUNDS"): OU$ = ENVIRON$("COUNTDOWN_OUT")
40 RP = VAL(ENVIRON$("COUNTDOWN_REPS")): IF RP < 1 THEN RP = 1
50 DIM RD(20000, 6), RW(20000), RX$(20000), P(5)
60 NR = 0
70 OPEN "I", #1, IN$
80 IF EOF(1) THEN GOTO 110
90 INPUT #1, RD(NR, 0), RD(NR, 1), RD(NR, 2), RD(NR, 3), RD(NR, 4), RD(NR, 5), RD(NR, 6)
100 NR = NR + 1: GOTO 80
110 CLOSE #1
120 N = 6
130 T0 = TIMER
140 FOR RR = 1 TO RP
150   FOR RI = 0 TO NR - 1
160     T = RD(RI, 0)
170     FOR PJ = 0 TO 5
180       P(PJ) = RD(RI, PJ + 1)
190     NEXT PJ
200     GOSUB 1000
210     RW(RI) = RV: RX$(RI) = RE$
220   NEXT RI
230 NEXT RR
240 REM Allow for the clock passing midnight since TIMER counts whole seconds from it
250 T1 = TIMER: IF T1 < T0 THEN T1 = T1 + 86400
260 REM Print four decimal places by hand since bwBASIC chooses its own number format
270 MT = INT((T1 - T0) * 1000 / NR / RP * 10000 + 0.5)
280 MI = INT(MT / 10000)
290 PRINT MID$(STR$(MI), 2); "."; MID$(STR$(10000 + MT - MI * 10000), 3); " ms/round"
300 OPEN "O", #2, OU$
310 FOR RI = 0 TO NR - 1
320   IF RI > 0 THEN PRINT #2, CHR$(10);
330   PRINT #2, MID$(STR$(RW(RI)), 2); CHR$(9); RX$(RI);
340 NEXT RI
350 CLOSE #2
360 SYSTEM
