' Check the solver against rounds with known answers

#include once "solver.bas"

Dim Shared As Long failures = 0

Sub Expect(ByVal ok As Boolean, ByRef what As String)
    If Not ok Then
        Print "FAIL: " & what
        failures += 1
    End If
End Sub

Dim As String expr
Dim As ULong value

Dim As ULong simple(0 To 5) = {1, 5, 7, 3, 75, 50}
value = Solve(125, simple(), expr)
Expect(value = 125 AndAlso expr = "75 + 50", "finds simplest solution")

Dim As ULong hard(0 To 5) = {8, 4, 2, 5, 100, 25}
Expect(Solve(552, hard(), expr) = 552, "solves 552")

Dim As ULong unsolvable(0 To 5) = {8, 8, 6, 8, 25, 100}
value = Solve(974, unsolvable(), expr)
Expect(value = 973 OrElse value = 975, "reports closest when unsolvable")

Dim As ULong closest(0 To 5) = {3, 2, 3, 4, 2, 25}
value = Solve(431, closest(), expr)
Expect(value = 432 AndAlso expr = "((25 * 3) - 3) * (4 + 2)", "matches the reference closest answer")

Dim As ULong pair(0 To 1) = {6, 4}
value = Solve(10, pair(), expr)
Expect(value = 10 AndAlso expr = "6 + 4", "handles smaller pools")

If failures > 0 Then End 1
Print "all tests passed"
