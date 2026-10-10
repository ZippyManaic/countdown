3000 REM Deal a target into T and six numbers into P for mode GM (0 standard, 1 cats, 2 nasty) with GF large or a random count when GF is negative
3010 T = 100 + INT(RND * 900)
3020 GC = GF
3030 IF GC < 0 AND GM = 0 THEN GC = 1 + INT(RND * 2)
3040 IF GC < 0 THEN GC = INT(RND * 5)
3050 DIM GS(19), GL(3)
3060 REM Hold two cards of each small number to match the game's deck
3070 FOR GI = 0 TO 19
3080   GS(GI) = GI MOD 10 + 1
3090 NEXT GI
3100 REM Shuffle with Fisher-Yates
3110 FOR GI = 19 TO 1 STEP -1
3120   GJ = INT(RND * (GI + 1)): GX = GS(GI): GS(GI) = GS(GJ): GS(GJ) = GX
3130 NEXT GI
3140 REM Use the cards of the 2010 specials for nasty-cats and the usual large cards otherwise
3150 GL(0) = 25: GL(1) = 50: GL(2) = 75: GL(3) = 100
3160 IF GM = 2 THEN GL(0) = 12: GL(1) = 37: GL(2) = 62: GL(3) = 87
3170 REM Shuffle a copy since each large number appears only once in the game
3180 FOR GI = 3 TO 1 STEP -1
3190   GJ = INT(RND * (GI + 1)): GX = GL(GI): GL(GI) = GL(GJ): GL(GJ) = GX
3200 NEXT GI
3210 REM Fill both parts in one loop since bwBASIC runs a FOR body once even when the range is empty
3220 FOR GI = 0 TO 5
3230   IF GI < 6 - GC THEN P(GI) = GS(GI)
3240   IF GI >= 6 - GC THEN P(GI) = GL(GI - 6 + GC)
3250 NEXT GI
3260 ERASE GS, GL
3270 RETURN
3300 REM Parse mode name GA$ and count GB$ into GM and GF, setting GV to 0 when they are invalid
3310 GV = 0: GM = -1: GF = -1
3320 IF GA$ = "" OR GA$ = "standard" THEN GM = 0
3330 IF GA$ = "cats" THEN GM = 1
3340 IF GA$ = "nasty" THEN GM = 2
3350 IF GM < 0 THEN RETURN
3360 IF GB$ = "" THEN GV = 1: RETURN
3370 IF LEN(GB$) <> 1 OR GB$ < "0" OR GB$ > "4" THEN RETURN
3380 GF = VAL(GB$)
3390 IF GM = 0 AND GF <> 1 AND GF <> 2 THEN GF = -1: RETURN
3400 GV = 1
3410 RETURN
