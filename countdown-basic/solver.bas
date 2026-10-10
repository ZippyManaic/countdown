1000 REM Solve a Countdown numbers round by building every subset's reachable values smallest subsets first
1010 REM Call with the target in T and the N pool numbers in P and get the value in RV and the expression in RE$
1020 GOTO 1930
1030 REM Keep the hot subroutines first since bwBASIC finds a line by searching from the start of the program
1040 REM Add value NV to subset M unless the subset has already made it
1050 HK = MK + NV: H = HK MOD HS
1060 IF HV(H) = HK THEN RETURN
1070 IF HV(H) = 0 THEN HV(H) = HK: EV(TP) = NV: TP = TP + 1: RETURN
1080 H = H + 1: IF H > HS THEN H = 0
1090 GOTO 1060
1100 REM Pass every legal value from a larger A and a smaller B to emit
1110 NV = A + B: GOSUB 1050
1120 IF A > B THEN NV = A - B: GOSUB 1050
1130 IF B = 1 THEN RETURN
1140 NV = A * B: GOSUB 1050
1150 IF A MOD B = 0 THEN NV = A / B: GOSUB 1050
1160 RETURN
1170 REM Pass every legal value from a larger B and a smaller A to emit
1180 NV = A + B: GOSUB 1050
1190 NV = B - A: GOSUB 1050
1200 IF A = 1 THEN RETURN
1210 NV = A * B: GOSUB 1050
1220 IF B MOD A = 0 THEN NV = B / A: GOSUB 1050
1230 RETURN
1240 REM Look up partner QV with operator QP in the other half and keep it if it makes the lowest pair so far
1250 HK = SK + QV: H = HK MOD HS
1260 IF HV(H) = HK THEN GOTO 1300
1270 IF HV(H) = 0 THEN RETURN
1280 H = H + 1: IF H > HS THEN H = 0
1290 GOTO 1260
1300 IF LF = 1 THEN A = NV: B = QV ELSE A = QV: B = NV
1310 IF FF = 0 OR A < FA OR (A = FA AND B * 8 + QP < FB * 8 + FO) THEN FF = 1: FA = A: FB = B: FO = QP
1320 RETURN
1330 REM Keep whole-pool value NV if it is closer to the target or equally close and lower
1340 IF ABS(NV - T) < WD OR (ABS(NV - T) = WD AND NV < WV) THEN WD = ABS(NV - T): WV = NV
1350 RETURN
1360 REM Pass every legal whole-pool value from a pair to consider
1370 NV = A + B: GOSUB 1340
1380 IF A > B THEN NV = A - B: GOSUB 1340
1390 IF B = 1 THEN RETURN
1400 NV = A * B: GOSUB 1340
1410 IF A MOD B = 0 THEN NV = A / B: GOSUB 1340
1420 RETURN
1430 NV = A + B: GOSUB 1340
1440 NV = B - A: GOSUB 1340
1450 IF A = 1 THEN RETURN
1460 NV = A * B: GOSUB 1340
1470 IF B MOD A = 0 THEN NV = B / A: GOSUB 1340
1480 RETURN
1490 REM Find the first way building would make value TV from subset FM and leave its split and operands in KA KB KX KY KO
1500 FD = 0
1510 L = (FM - 1) AND FM
1520 IF L = 0 THEN RETURN
1530 R = FM XOR L
1540 REM Visit splits in the same order as building so the same way wins
1550 IF L >= R THEN GOTO 1750
1560 REM Scan the smaller half and look each value's partners up in the other half
1570 LF = 0: QS = R: SR = L
1580 IF LN(L) <= LN(R) THEN LF = 1: QS = L: SR = R
1590 SK = SR * 134217728: FF = 0
1600 FOR I = OF(QS) TO OF(QS) + LN(QS) - 1
1610   NV = EV(I)
1620   IF TV > NV THEN QV = TV - NV: QP = 1: GOSUB 1250
1630   IF NV > TV THEN QV = NV - TV: QP = 2: GOSUB 1250
1640   QV = NV + TV: QP = 2: GOSUB 1250
1650   REM Divide only when the quotient could be at least two since neither operand may be one
1660   IF NV <> 1 AND 2 * NV <= TV AND TV MOD NV = 0 THEN QV = TV / NV: QP = 3: GOSUB 1250
1670   IF NV >= 2 * TV AND NV MOD TV = 0 THEN QV = NV / TV: QP = 4: GOSUB 1250
1680   REM Skip a product too large for any subset to make
1690   IF NV <> 1 AND NV * TV < 134217728 THEN QV = NV * TV: QP = 4: GOSUB 1250
1700 NEXT I
1710 IF FF = 0 THEN GOTO 1750
1720 FD = 1: KO = FO
1730 IF FA >= FB THEN KX = FA: KY = FB: KA = L: KB = R ELSE KX = FB: KY = FA: KA = R: KB = L
1740 RETURN
1750 L = (L - 1) AND FM
1760 GOTO 1520
1770 REM Build every value subset M can make keeping each once in the hash table and the subset's list
1780 OF(M) = TP: MK = M * 134217728
1790 L = (M - 1) AND M
1800 IF L = 0 THEN LN(M) = TP - OF(M): RETURN
1810 R = M XOR L
1820 REM Visit each split once rather than once per ordering
1830 IF L >= R THEN GOTO 1910
1840 FOR I = OF(L) TO OF(L) + LN(L) - 1
1850   A = EV(I)
1860   FOR J = OF(R) TO OF(R) + LN(R) - 1
1870     B = EV(J)
1880     IF A >= B THEN GOSUB 1110 ELSE GOSUB 1180
1890   NEXT J
1900 NEXT I
1910 L = (L - 1) AND M
1920 GOTO 1800
1930 REM Hold every subset's values back to back and every subset and value pair in one hash table
1940 EM = 40000: HS = 65521
1950 DIM EV(EM), HV(HS), OF(63), LN(63), PC(63)
1960 DIM SM(40), SV(40), SH(40), SO(40), SS$(40)
1970 FL = 2 ^ N - 1
1980 FOR M = 1 TO FL
1990   PC(M) = PC(INT(M / 2)) + (M MOD 2)
2000 NEXT M
2010 REM Answer a single number with itself since it is both the only and the closest value
2020 IF N = 1 THEN BM = 1: BV = P(0): GOTO 2520
2030 TP = 0: SD = 0: TV = T
2040 REM Work through subsets smallest first so the search can stop at the first size that hits the target
2050 SZ = 1
2060 FOR M = 1 TO FL
2070   IF SD = 1 OR PC(M) <> SZ THEN GOTO 2170
2080   IF SZ > 1 THEN GOTO 2140
2090   B = 0: X = M
2100   IF X > 1 THEN X = X / 2: B = B + 1: GOTO 2100
2110   OF(M) = TP: LN(M) = 1: MK = M * 134217728: NV = P(B): GOSUB 1050
2120   IF P(B) = T THEN SD = 1: BM = M: BV = T
2130   GOTO 2170
2140   REM Keep the lowest matching subset of this size to break ties the same way every run
2150   FM = M: GOSUB 1500
2160   IF FD = 1 THEN SD = 1: BM = M: BV = T
2170 NEXT M
2180 REM Skip building the values of the whole pool since no larger subset is made from them
2190 IF SD = 1 OR SZ = N THEN GOTO 2250
2200 IF SZ = 1 THEN GOTO 2240
2210 FOR M = 1 TO FL
2220   IF PC(M) = SZ THEN GOSUB 1780
2230 NEXT M
2240 SZ = SZ + 1: GOTO 2060
2250 IF SD = 1 THEN GOTO 2520
2260 REM Rank by distance from the target then by numbers used then by subset then by value so the simplest answer wins
2270 PD = -1
2280 FOR M = 1 TO FL - 1
2290   U = PC(M)
2300   FOR I = OF(M) TO OF(M) + LN(M) - 1
2310     D = ABS(EV(I) - T)
2320     IF PD < 0 OR D < PD OR (D = PD AND U < PU) OR (D = PD AND M = BM AND EV(I) < BV) THEN PD = D: PU = U: BM = M: BV = EV(I)
2330   NEXT I
2340 NEXT M
2350 REM Check the whole pool's values as they are made since no larger subset is built from them
2360 WD = 1E+30: WV = 0
2370 L = (FL - 1) AND FL
2380 IF L = 0 THEN GOTO 2500
2390 R = FL XOR L
2400 IF L >= R THEN GOTO 2480
2410 FOR I = OF(L) TO OF(L) + LN(L) - 1
2420   A = EV(I)
2430   FOR J = OF(R) TO OF(R) + LN(R) - 1
2440     B = EV(J)
2450     IF A >= B THEN GOSUB 1370 ELSE GOSUB 1430
2460   NEXT J
2470 NEXT I
2480 L = (L - 1) AND FL
2490 GOTO 2380
2500 REM Fall back to the whole pool only when it gets strictly closer as it uses the most numbers
2510 IF WD < PD THEN BM = FL: BV = WV
2520 REM Rebuild the expression by finding each node's first way of being made with a stack in place of recursion
2530 SN = 1: SM(1) = BM: SV(1) = BV: SH(1) = 0: TN = 0
2540 IF SN = 0 THEN GOTO 2640
2550 ZM = SM(SN): ZV = SV(SN): ZH = SH(SN): ZO = SO(SN): SN = SN - 1
2560 IF ZH = 1 THEN SS$(TN - 1) = "(" + SS$(TN - 1) + " " + MID$("+-*/", ZO, 1) + " " + SS$(TN) + ")": TN = TN - 1: GOTO 2540
2570 IF PC(ZM) = 1 THEN TN = TN + 1: SS$(TN) = MID$(STR$(ZV), 2): GOTO 2540
2580 FM = ZM: TV = ZV: GOSUB 1500
2590 REM Push the node again to join its operands then the smaller operand then the larger so the larger comes off first
2600 SN = SN + 1: SM(SN) = ZM: SV(SN) = ZV: SH(SN) = 1: SO(SN) = KO
2610 SN = SN + 1: SM(SN) = KB: SV(SN) = KY: SH(SN) = 0
2620 SN = SN + 1: SM(SN) = KA: SV(SN) = KX: SH(SN) = 0
2630 GOTO 2540
2640 RE$ = SS$(1)
2650 REM Strip the redundant outermost brackets for display
2660 IF LEFT$(RE$, 1) = "(" AND RIGHT$(RE$, 1) = ")" THEN RE$ = MID$(RE$, 2, LEN(RE$) - 2)
2670 RV = BV
2680 ERASE EV, HV, OF, LN, PC, SM, SV, SH, SO, SS$
2690 RETURN
