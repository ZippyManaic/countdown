' Check the dealer in every mode and the solver against rounds with known answers

#include once "solver.bas"
#include once "deal.bas"

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

Dim As ULong four_large(0 To 5) = {10, 10, 25, 50, 75, 100}
value = Solve(999, four_large(), expr)
Expect(value = 999 AndAlso expr = "(((75 + 25) * 100) - 10) / 10", "solves a four-large cats round")

Dim As ULong no_large(0 To 5) = {1, 1, 2, 2, 3, 3}
value = Solve(100, no_large(), expr)
Expect(value = 81 AndAlso expr = "(((2 + 1) * (2 + 1)) * 3) * 3", "reports closest on a no-large cats round")

Dim As ULong nasty(0 To 5) = {2, 3, 87, 62, 37, 12}
value = Solve(999, nasty(), expr)
Expect(value = 999 AndAlso expr = "37 * ((87 / 3) - 2)", "solves a nasty-cats round")

' Return the large count of a dealt round after checking it keeps the rules of its mode
Function CheckRound(ByVal mode As Long, ByVal lowest As Long, ByVal highest As Long) As Long
    Dim As ULong target, pool(0 To 5), large(0 To 3)
    GenerateRound(mode, IIf(lowest = highest, lowest, RANDOM_COUNT), target, pool())
    LargeNumbers(mode, large())
    Expect(target >= 100 AndAlso target <= 999, "deals a target from 100 to 999")
    Dim As Long large_count = 0, seen(0 To 100)
    For i As Long = 0 To 5
        seen(pool(i)) += 1
        If pool(i) > 10 Then
            large_count += 1
            Expect(seen(pool(i)) = 1, "deals distinct large cards")
            Dim As Boolean known = False
            For j As Long = 0 To 3
                If large(j) = pool(i) Then known = True
            Next
            Expect(known, "deals the mode's own large cards")
        Else
            ' Allow each small number at most twice since the deck holds two of each
            Expect(seen(pool(i)) <= 2, "deals each small number at most twice")
        End If
    Next
    Expect(large_count >= lowest AndAlso large_count <= highest, "deals an allowed large count")
    Return large_count
End Function

Randomize 1
For mode As Long = MODE_STANDARD To MODE_NASTY
    Dim As Long lowest = IIf(mode = MODE_STANDARD, 1, 0), highest = IIf(mode = MODE_STANDARD, 2, 4)
    Dim As Long counts(0 To 4)
    For n As Long = 1 To 2000
        Dim As Long k = CheckRound(mode, lowest, highest)
        If k >= 0 AndAlso k <= 4 Then counts(k) += 1
    Next
    For k As Long = lowest To highest
        Expect(counts(k) > 0, "deals every allowed large count")
    Next
Next
For mode As Long = MODE_CATS To MODE_NASTY
    For k As Long = 0 To 4
        Expect(CheckRound(mode, k, k) = k, "deals a fixed large count")
    Next
Next

Dim As String args(0 To 2)
Dim As Long mode, large_count
Expect(ParseArgs(args(), 0, mode, large_count) AndAlso mode = MODE_STANDARD AndAlso large_count = RANDOM_COUNT, "parses no arguments")
args(0) = "nasty" : args(1) = "4"
Expect(ParseArgs(args(), 2, mode, large_count) AndAlso mode = MODE_NASTY AndAlso large_count = 4, "parses nasty 4")
args(0) = "cats" : args(1) = "0"
Expect(ParseArgs(args(), 2, mode, large_count) AndAlso mode = MODE_CATS AndAlso large_count = 0, "parses cats 0")
args(0) = "standard" : args(1) = "3"
Expect(Not ParseArgs(args(), 2, mode, large_count), "rejects standard 3")
args(0) = "cats" : args(1) = "5"
Expect(Not ParseArgs(args(), 2, mode, large_count), "rejects cats 5")
args(0) = "dogs"
Expect(Not ParseArgs(args(), 1, mode, large_count), "rejects an unknown mode")
args(0) = "cats" : args(1) = "1" : args(2) = "2"
Expect(Not ParseArgs(args(), 3, mode, large_count), "rejects three arguments")
args(0) = "cats" : args(1) = "x"
Expect(Not ParseArgs(args(), 2, mode, large_count), "rejects a non-numeric count")

If failures > 0 Then End 1
Print "all tests passed"
