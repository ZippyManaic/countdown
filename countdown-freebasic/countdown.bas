' Generate a Countdown numbers round and work out whether it can be solved

#include once "solver.bas"

' Shuffle numbers in place with Fisher-Yates
Sub Shuffle(items() As ULong)
    For i As Long = UBound(items) To LBound(items) + 1 Step -1
        Dim As Long j = LBound(items) + Int(Rnd * (i - LBound(items) + 1))
        Swap items(i), items(j)
    Next
End Sub

Randomize
Dim As ULong target = 100 + Int(Rnd * 900)
Dim As Long large_count = 1 + Int(Rnd * 2)

' Hold two cards of each small number to match the game's deck
Dim As ULong small(0 To 19)
For i As Long = 0 To 19
    small(i) = i Mod 10 + 1
Next
Shuffle(small())
' Shuffle a copy since each large number appears only once in the game
Dim As ULong large(0 To 3) = {25, 50, 75, 100}
Shuffle(large())

Dim As ULong pool(0 To 5)
For i As Long = 0 To 5 - large_count
    pool(i) = small(i)
Next
For i As Long = 0 To large_count - 1
    pool(6 - large_count + i) = large(i)
Next

Print "Target: " & target
Dim As String line_ = "Pool:  "
For i As Long = 0 To 5
    line_ &= " " & pool(i)
Next
Print line_

Dim As String expr
Dim As ULong value = Solve(target, pool(), expr)
If value = target Then
    Print "Solved: " & expr & " = " & value
    End 0
End If
Print "No exact solution, closest is " & expr & " = " & value & " (" & IIf(value > target, value - target, target - value) & " away)"
End 1
