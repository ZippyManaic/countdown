10 REM Check the solver against rounds with known answers
20 DIM P(5)
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
160 IF XF > 0 THEN SYSTEM
170 PRINT "all tests passed"
180 SYSTEM
