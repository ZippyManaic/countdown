' Time the solver over a file of rounds and write each answer as value tab expression

#include once "solver.bas"

Dim As Integer f = FreeFile
Open Command(1) For Input As #f
Dim As ULong rounds(0 To 19999, 0 To 6)
Dim As Long count = 0
While Not EOF(f)
    For j As Long = 0 To 6
        Input #f, rounds(count, j)
    Next
    count += 1
Wend
Close #f
Dim As Long reps = 1
If Len(Command(3)) Then reps = ValInt(Command(3))

Dim As ULong values(0 To count - 1)
Dim As String exprs(0 To count - 1)
Dim As ULong pool(0 To 5)
Dim As Double start = Timer
For rep As Long = 1 To reps
    For i As Long = 0 To count - 1
        For j As Long = 0 To 5
            pool(j) = rounds(i, j + 1)
        Next
        values(i) = Solve(rounds(i, 0), pool(), exprs(i))
    Next
Next
Dim As Double elapsed = Timer - start
Open Err As #2
' Print four decimal places by hand since Str switches to exponent form for small numbers
Dim As LongInt tenths = CLngInt(elapsed * 1e7 / count / reps)
Print #2, Str(tenths \ 10000) & "." & Right("000" & Str(tenths Mod 10000), 4) & " ms/round"
Close #2

f = FreeFile
Open Command(2) For Output As #f
For i As Long = 0 To count - 1
    If i Then Print #f, Chr(10);
    Print #f, Str(values(i)) & Chr(9) & exprs(i);
Next
Close #f
