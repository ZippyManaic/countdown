' Generate a Countdown numbers round and work out whether it can be solved

#include once "solver.bas"
#include once "deal.bas"

Dim As Long arg_count = __FB_ARGC__ - 1
Dim As String args(0 To 1)
For i As Long = 0 To IIf(arg_count < 2, arg_count, 2) - 1
    args(i) = Command(i + 1)
Next
Dim As Long mode, large_count
If Not ParseArgs(args(), arg_count, mode, large_count) Then
    Open Err For Output As #1
    Print #1, USAGE
    Close #1
    End 2
End If

Randomize
Dim As ULong target
Dim As ULong pool(0 To 5)
GenerateRound(mode, large_count, target, pool())

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
