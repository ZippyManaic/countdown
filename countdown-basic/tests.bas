10 REM Check the solver against rounds with known answers and the dealer in every mode
20 DIM P(5), XS(6)
30 XF = 0
40 T = 125: N = 6: P(0) = 1: P(1) = 5: P(2) = 7: P(3) = 3: P(4) = 75: P(5) = 50: GOSUB 1000
50 IF RV <> 125 OR RE$ <> "75 + 50" THEN PRINT "FAIL: finds simplest solution": XF = XF + 1
60 T = 552: N = 6: P(0) = 8: P(1) = 4: P(2) = 2: P(3) = 5: P(4) = 100: P(5) = 25: GOSUB 1000
70 IF RV <> 552 THEN PRINT "FAIL: solves 552": XF = XF + 1
80 T = 974: N = 6: P(0) = 8: P(1) = 8: P(2) = 6: P(3) = 8: P(4) = 25: P(5) = 100: GOSUB 1000
90 IF RV <> 973 AND RV <> 975 THEN PRINT "FAIL: reports closest when unsolvable": XF = XF + 1
100 T = 431: N = 6: P(0) = 3: P(1) = 2: P(2) = 3: P(3) = 4: P(4) = 2: P(5) = 25: GOSUB 1000
110 IF RV <> 432 OR RE$ <> "((25 * 3) - 3) * (4 + 2)" THEN PRINT "FAIL: matches the reference closest answer": XF = XF + 1
120 T = 10: N = 2: P(0) = 6: P(1) = 4: GOSUB 1000
130 IF RV <> 10 OR RE$ <> "6 + 4" THEN PRINT "FAIL: handles smaller pools": XF = XF + 1
140 T = 7: N = 1: P(0) = 5: GOSUB 1000
150 IF RV <> 5 OR RE$ <> "5" THEN PRINT "FAIL: handles a single number": XF = XF + 1
151 T = 100: N = 1: P(0) = 7: GOSUB 1000
152 IF RV <> 7 OR RE$ <> "7" THEN PRINT "FAIL: reports a lone number as closest": XF = XF + 1
153 T = 7: N = 1: P(0) = 7: GOSUB 1000
154 IF RV <> 7 OR RE$ <> "7" THEN PRINT "FAIL: solves with a lone number": XF = XF + 1
155 T = 100: N = 2: P(0) = 3: P(1) = 4: GOSUB 1000
156 IF RV <> 12 OR RE$ <> "4 * 3" THEN PRINT "FAIL: reports closest with two numbers": XF = XF + 1
160 T = 999: N = 6: P(0) = 10: P(1) = 10: P(2) = 25: P(3) = 50: P(4) = 75: P(5) = 100: GOSUB 1000
170 IF RV <> 999 OR RE$ <> "(((75 + 25) * 100) - 10) / 10" THEN PRINT "FAIL: solves cats round 999": XF = XF + 1
180 T = 100: N = 6: P(0) = 1: P(1) = 1: P(2) = 2: P(3) = 2: P(4) = 3: P(5) = 3: GOSUB 1000
190 IF RV <> 81 OR RE$ <> "(((2 + 1) * (2 + 1)) * 3) * 3" THEN PRINT "FAIL: reports closest on cats round with no large": XF = XF + 1
200 T = 999: N = 6: P(0) = 2: P(1) = 3: P(2) = 87: P(3) = 62: P(4) = 37: P(5) = 12: GOSUB 1000
210 IF RV <> 999 OR RE$ <> "37 * ((87 / 3) - 2)" THEN PRINT "FAIL: solves nasty round 999": XF = XF + 1
220 RANDOMIZE 1
230 GM = 0: XL = 1: XH = 2: GOSUB 600
240 GM = 1: XL = 0: XH = 4: GOSUB 600
250 GM = 2: XL = 0: XH = 4: GOSUB 600
260 REM Deal cats and nasty rounds with each fixed large count from 0 to 4
270 FOR XM = 1 TO 2
280   FOR XK = 0 TO 4
290     GM = XM: GF = XK: XL = XK: XH = XK: GOSUB 3000: GOSUB 700
300   NEXT XK
310 NEXT XM
320 GA$ = "": GB$ = "": GOSUB 3300
330 IF GV <> 1 OR GM <> 0 OR GF <> -1 THEN PRINT "FAIL: parses no arguments": XF = XF + 1
340 GA$ = "nasty": GB$ = "4": GOSUB 3300
350 IF GV <> 1 OR GM <> 2 OR GF <> 4 THEN PRINT "FAIL: parses nasty 4": XF = XF + 1
360 GA$ = "cats": GB$ = "0": GOSUB 3300
370 IF GV <> 1 OR GM <> 1 OR GF <> 0 THEN PRINT "FAIL: parses cats 0": XF = XF + 1
380 GA$ = "standard": GB$ = "3": GOSUB 900
390 GA$ = "cats": GB$ = "5": GOSUB 900
400 GA$ = "dogs": GB$ = "": GOSUB 900
410 GA$ = "cats": GB$ = "x": GOSUB 900
420 IF XF > 0 THEN SYSTEM
430 PRINT "all tests passed"
440 SYSTEM
600 REM Deal 2000 rounds in mode GM and check every large count from XL to XH occurs
610 GF = -1
620 FOR XK = 0 TO 6
630   XS(XK) = 0
640 NEXT XK
650 FOR XR = 1 TO 2000
660   GOSUB 3000: GOSUB 700: XS(XN) = XS(XN) + 1
670 NEXT XR
680 FOR XK = XL TO XH
690   IF XS(XK) = 0 THEN PRINT "FAIL: every large count occurs in mode"; GM: XF = XF + 1
695 NEXT XK
698 RETURN
700 REM Check the round in T and P is legal for mode GM with from XL to XH large numbers and leave the large count in XN
710 IF T < 100 OR T > 999 THEN PRINT "FAIL: target in range": XF = XF + 1
720 XN = 0
730 FOR XI = 0 TO 5
740   XC = 0: XV = P(XI)
750   FOR XJ = 0 TO 5
760     IF P(XJ) = XV THEN XC = XC + 1
770   NEXT XJ
780   IF XV < 1 THEN PRINT "FAIL: six numbers": XF = XF + 1
790   REM Allow each small number at most twice since the deck holds two of each
800   IF XV <= 10 AND XC > 2 THEN PRINT "FAIL: small number at most twice": XF = XF + 1
810   IF XV > 10 THEN XN = XN + 1
820   IF XV > 10 AND XC > 1 THEN PRINT "FAIL: large numbers distinct": XF = XF + 1
830   XB = 0
840   IF GM < 2 AND (XV = 25 OR XV = 50 OR XV = 75 OR XV = 100) THEN XB = 1
850   IF GM = 2 AND (XV = 12 OR XV = 37 OR XV = 62 OR XV = 87) THEN XB = 1
860   IF XV > 10 AND XB = 0 THEN PRINT "FAIL: large number from the mode's set": XF = XF + 1
870 NEXT XI
880 IF XN < XL OR XN > XH THEN PRINT "FAIL: large count allowed": XF = XF + 1
890 RETURN
900 REM Parse GA$ and GB$ and check they are rejected
910 GOSUB 3300
920 IF GV <> 0 THEN PRINT "FAIL: rejects "; GA$; " "; GB$: XF = XF + 1
930 RETURN
