' Deal Countdown rounds in each mode and read the mode from the command line

Const MODE_STANDARD = 0
Const MODE_CATS = 1
Const MODE_NASTY = 2
' Mark a large count as unset so the dealer picks it at random
Const RANDOM_COUNT = -1
Const USAGE = "usage: countdown [standard|cats|nasty] [LARGE]"

' Shuffle numbers in place with Fisher-Yates
Sub Shuffle(items() As ULong)
    For i As Long = UBound(items) To LBound(items) + 1 Step -1
        Dim As Long j = LBound(items) + Int(Rnd * (i - LBound(items) + 1))
        Swap items(i), items(j)
    Next
End Sub

' Fill the four large cards of a mode, with nasty-cats using the cards of the 2010 specials
Sub LargeNumbers(ByVal mode As Long, large() As ULong)
    If mode = MODE_NASTY Then
        large(0) = 12 : large(1) = 37 : large(2) = 62 : large(3) = 87
    Else
        large(0) = 25 : large(1) = 50 : large(2) = 75 : large(3) = 100
    End If
End Sub

' Deal a random target and six numbers with one or two large in standard mode and none to four otherwise
Sub GenerateRound(ByVal mode As Long, ByVal large_count As Long, ByRef target As ULong, pool() As ULong)
    target = 100 + Int(Rnd * 900)
    If large_count = RANDOM_COUNT Then
        large_count = IIf(mode = MODE_STANDARD, 1 + Int(Rnd * 2), Int(Rnd * 5))
    End If

    ' Hold two cards of each small number to match the game's deck
    Dim As ULong small(0 To 19)
    For i As Long = 0 To 19
        small(i) = i Mod 10 + 1
    Next
    Shuffle(small())
    ' Shuffle a copy since each large number appears only once in the game
    Dim As ULong large(0 To 3)
    LargeNumbers(mode, large())
    Shuffle(large())

    For i As Long = 0 To 5 - large_count
        pool(i) = small(i)
    Next
    For i As Long = 0 To large_count - 1
        pool(6 - large_count + i) = large(i)
    Next
End Sub

' Set the mode and fixed large count from the arguments and return false when they are invalid
Function ParseArgs(args() As String, ByVal count As Long, ByRef mode As Long, ByRef large_count As Long) As Boolean
    If count > 2 Then Return False
    mode = MODE_STANDARD
    large_count = RANDOM_COUNT
    If count = 0 Then Return True
    Select Case args(0)
    Case "standard" : mode = MODE_STANDARD
    Case "cats" : mode = MODE_CATS
    Case "nasty" : mode = MODE_NASTY
    Case Else : Return False
    End Select
    If count = 1 Then Return True
    Dim As String lowest = IIf(mode = MODE_STANDARD, "1", "0")
    Dim As String highest = IIf(mode = MODE_STANDARD, "2", "4")
    If Len(args(1)) <> 1 OrElse args(1) < lowest OrElse args(1) > highest Then Return False
    large_count = Val(args(1))
    Return True
End Function
