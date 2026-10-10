10 REM Generate a Countdown numbers round and work out whether it can be solved
20 REM Seed from the clock and a number from the environment since the clock only counts whole seconds
30 RANDOMIZE TIMER + VAL(ENVIRON$("COUNTDOWN_SEED"))
40 T = 100 + INT(RND * 900)
50 LC = 1 + INT(RND * 2)
60 DIM SC(19), LG(3), P(5)
70 REM Hold two cards of each small number to match the game's deck
80 FOR I = 0 TO 19
90   SC(I) = I MOD 10 + 1
100 NEXT I
110 REM Shuffle with Fisher-Yates
120 FOR I = 19 TO 1 STEP -1
130   J = INT(RND * (I + 1)): X = SC(I): SC(I) = SC(J): SC(J) = X
140 NEXT I
150 REM Shuffle a copy since each large number appears only once in the game
160 LG(0) = 25: LG(1) = 50: LG(2) = 75: LG(3) = 100
170 FOR I = 3 TO 1 STEP -1
180   J = INT(RND * (I + 1)): X = LG(I): LG(I) = LG(J): LG(J) = X
190 NEXT I
200 FOR I = 0 TO 5 - LC
210   P(I) = SC(I)
220 NEXT I
230 FOR I = 0 TO LC - 1
240   P(6 - LC + I) = LG(I)
250 NEXT I
260 PRINT "Target: "; MID$(STR$(T), 2)
270 PL$ = "Pool:  "
280 FOR I = 0 TO 5
290   PL$ = PL$ + STR$(P(I))
300 NEXT I
310 PRINT PL$
320 N = 6: GOSUB 1000
330 IF RV = T THEN PRINT "Solved: "; RE$; " = "; MID$(STR$(RV), 2): SYSTEM
340 PRINT "No exact solution, closest is "; RE$; " = "; MID$(STR$(RV), 2); " ("; MID$(STR$(ABS(RV - T)), 2); " away)"
350 SYSTEM
