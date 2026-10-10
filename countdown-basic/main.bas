10 REM Generate a Countdown numbers round and work out whether it can be solved
20 REM Read the mode and large count from COUNTDOWN_MODE and COUNTDOWN_LARGE, which the countdown script always sets, since bwBASIC cannot read arguments
30 GA$ = ENVIRON$("COUNTDOWN_MODE"): GB$ = ENVIRON$("COUNTDOWN_LARGE"): GOSUB 3300
40 IF GV = 0 THEN PRINT "usage: countdown [standard|cats|nasty] [LARGE]": SYSTEM
50 REM Seed from the clock and a number from the environment since the clock only counts whole seconds
60 RANDOMIZE TIMER + VAL(ENVIRON$("COUNTDOWN_SEED"))
70 DIM P(5)
80 GOSUB 3000
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
