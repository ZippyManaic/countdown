{ Work out the simplest Countdown expression that hits a target or gets closest to it }
unit Solver;

{$mode objfpc}{$H+}
{$inline on}
{$pointermath on}
{ Keep floating constants in double precision since a single precision reciprocal would miss exact divisions }
{$minfpconstprec 64}

interface

type
  TPool = array of Cardinal;

{ Return the simplest expression that hits the target or gets closest to it with its value }
function Solve(Target: Cardinal; const Pool: TPool; out Expr: string): Cardinal;

implementation

uses
  SysUtils;

const
  { Sort subsets with fewer values than this by insertion rather than by rank in the bitset }
  RankMin = 16;
  OpAdd = Ord('+');
  OpSub = Ord('-');
  OpMul = Ord('*');
  OpDiv = Ord('/');

type
  { Record a reachable value with how it was made from the larger and smaller of two values in disjoint subsets }
  TEntry = record
    { Pack value, operator (zero for a pool number), larger mask and smaller mask from the low bits up }
    Head: QWord;
    { Pack the larger operand in the low half and the smaller in the high half }
    Operands: QWord;
  end;
  PEntry = ^TEntry;

  TTemplates = array[0..3] of QWord;

  { Hold the working memory of one solve }
  TState = record
    Target: Cardinal;
    Full: Integer;
    { Keep every subset's sorted values back to back in one arena }
    Arena: PEntry;
    Top, Cap: SizeInt;
    Off, Len: array[0..255] of Cardinal;
    { Hold the largest value each subset can make which bounds the bitset words it touches }
    Max: array[0..255] of QWord;
    { Hold one bit per value seen in the subset being built }
    Seen: PQWord;
    SeenWords: SizeInt;
    { Collect a subset's new values here before they are sorted into the arena }
    Tmp: PEntry;
    TmpCap: SizeInt;
    { Hold the count of values below each bitset word for ranking }
    Rank: PCardinal;
    { Hold the right half's values with their reciprocals for the split being built }
    RightValues: PCardinal;
    RightInv: PDouble;
    RightCap: SizeInt;
  end;

function ValueOf(const E: TEntry): Cardinal; inline;
begin
  Result := Cardinal(E.Head);
end;

{ Return the operator and masks of an entry shifted above its value }
function MakeTemplate(Op: Byte; LargerMask, SmallerMask: Cardinal): QWord; inline;
begin
  Result := QWord(Op or (LargerMask shl 8) or (SmallerMask shl 16)) shl 32;
end;

procedure MakeTemplates(LargerMask, SmallerMask: Cardinal; out T: TTemplates); inline;
begin
  T[0] := MakeTemplate(OpAdd, LargerMask, SmallerMask);
  T[1] := MakeTemplate(OpSub, LargerMask, SmallerMask);
  T[2] := MakeTemplate(OpMul, LargerMask, SmallerMask);
  T[3] := MakeTemplate(OpDiv, LargerMask, SmallerMask);
end;

{ Grow a buffer of entries to at least Need by doubling keeping its first Keep entries }
procedure Reserve(var Items: PEntry; var Cap: SizeInt; Keep, Need: SizeInt);
var
  Size: SizeInt;
  Grown: PEntry;
begin
  if Need <= Cap then
    Exit;
  Size := Cap;
  if Size < 1024 then
    Size := 1024;
  while Size < Need do
    Size := 2 * Size;
  { Skip zeroing since every slot is written before it is read }
  Grown := GetMem(Size * SizeOf(TEntry));
  if Keep > 0 then
    Move(Items^, Grown^, Keep * SizeOf(TEntry));
  FreeMem(Items);
  Items := Grown;
  Cap := Size;
end;

{ Return x divided by y when the division is exact and zero otherwise using the reciprocal of y }
function Exact(X, Y: Cardinal; Inv: Double): Cardinal; inline;
var
  Q: Cardinal;
begin
  Q := Cardinal(Trunc(X * Inv + 0.5));
  { Mask with arithmetic since the comparison would otherwise become a branch }
  Result := Q and Cardinal(-Ord(Q * Y = X));
end;

{ Store a value and return the next slot which moves on only if the bitset shows the value is new }
function Emit(Seen: PQWord; Output: PEntry; V: PtrUInt; Tmpl, Operands: QWord): PEntry; inline;
var
  W: QWord;
  Word_, Bit: PtrUInt;
begin
  { Return the pointer rather than taking it by reference so it can stay in a register }
  Word_ := V shr 6;
  Bit := V and 63;
  W := Seen[Word_];
  Seen[Word_] := W or (QWord(1) shl Bit);
  Output^.Head := Tmpl or V;
  Output^.Operands := Operands;
  Result := Output + ((not W shr Bit) and 1);
end;

{ Append every new value from combining the two halves of a split to Output and return the new end }
function EmitSplit(var S: TState; Left, Right: Cardinal; Output: PEntry): PEntry;
var
  TL, TR: TTemplates;
  Lefts, Rights: PEntry;
  RV: PCardinal;
  RI: PDouble;
  Seen: PQWord;
  NL, NR, I, J, A, B: PtrUInt;
  IA: Double;
  Operands: QWord;
begin
  MakeTemplates(Left, Right, TL);
  MakeTemplates(Right, Left, TR);
  Lefts := S.Arena + S.Off[Left];
  Rights := S.Arena + S.Off[Right];
  NL := S.Len[Left];
  NR := S.Len[Right];
  RV := S.RightValues;
  RI := S.RightInv;
  Seen := S.Seen;
  { Invert each right value once per split rather than once per pair }
  for J := 0 to NR - 1 do
  begin
    RV[J] := ValueOf(Rights[J]);
    RI[J] := 1.0 / RV[J];
  end;
  for I := 0 to NL - 1 do
  begin
    A := ValueOf(Lefts[I]);
    J := 0;
    { Pair with right values up to a first where a is the larger and ties go left }
    while (J < NR) and (RV[J] <= A) do
    begin
      B := RV[J];
      Operands := A or (QWord(B) shl 32);
      Output := Emit(Seen, Output, A + B, TL[0], Operands);
      { Skip a zero result since every intermediate value must be a positive integer }
      if A <> B then
        Output := Emit(Seen, Output, A - B, TL[1], Operands);
      { Skip multiplying and dividing by one as they never produce a new value }
      if B <> 1 then
      begin
        Output := Emit(Seen, Output, A * B, TL[2], Operands);
        Output := Emit(Seen, Output, Exact(A, B, RI[J]), TL[3], Operands);
      end;
      Inc(J);
    end;
    { Pair with the remaining larger right values where a is the smaller }
    IA := 1.0 / A;
    while J < NR do
    begin
      B := RV[J];
      Operands := B or (QWord(A) shl 32);
      Output := Emit(Seen, Output, B + A, TR[0], Operands);
      Output := Emit(Seen, Output, B - A, TR[1], Operands);
      if A <> 1 then
      begin
        Output := Emit(Seen, Output, B * A, TR[2], Operands);
        Output := Emit(Seen, Output, Exact(B, A, IA), TR[3], Operands);
      end;
      Inc(J);
    end;
  end;
  Result := Output;
end;

{ Keep the whole pool's value closest to the target preferring the lower value on equal distance }
procedure CheckSplit(var S: TState; Left, Right: Cardinal; var Best: TEntry; var BestDistance: Cardinal);
var
  TL, TR: TTemplates;
  Lefts, Rights: PEntry;
  RV: PCardinal;
  RI: PDouble;
  NL, NR, I, J, A, B: Cardinal;
  IA: Double;
  Operands: QWord;

  procedure Check(V: Cardinal; Tmpl: QWord);
  var
    D: Cardinal;
  begin
    if V > S.Target then
      D := V - S.Target
    else
      D := S.Target - V;
    if (V <> 0) and ((D < BestDistance) or ((D = BestDistance) and (V < ValueOf(Best)))) then
    begin
      BestDistance := D;
      Best.Head := Tmpl or V;
      Best.Operands := Operands;
    end;
  end;

begin
  MakeTemplates(Left, Right, TL);
  MakeTemplates(Right, Left, TR);
  Lefts := S.Arena + S.Off[Left];
  Rights := S.Arena + S.Off[Right];
  NL := S.Len[Left];
  NR := S.Len[Right];
  RV := S.RightValues;
  RI := S.RightInv;
  for J := 0 to NR - 1 do
  begin
    RV[J] := ValueOf(Rights[J]);
    RI[J] := 1.0 / RV[J];
  end;
  for I := 0 to NL - 1 do
  begin
    A := ValueOf(Lefts[I]);
    J := 0;
    while (J < NR) and (RV[J] <= A) do
    begin
      B := RV[J];
      Operands := A or (QWord(B) shl 32);
      Check(A + B, TL[0]);
      if A <> B then
        Check(A - B, TL[1]);
      if B <> 1 then
      begin
        Check(A * B, TL[2]);
        Check(Exact(A, B, RI[J]), TL[3]);
      end;
      Inc(J);
    end;
    IA := 1.0 / A;
    while J < NR do
    begin
      B := RV[J];
      Operands := B or (QWord(A) shl 32);
      Check(B + A, TR[0]);
      Check(B - A, TR[1]);
      if A <> 1 then
      begin
        Check(B * A, TR[2]);
        Check(Exact(B, A, IA), TR[3]);
      end;
      Inc(J);
    end;
  end;
end;

{ Return the entry holding Value among N sorted entries or nil when it is absent }
function Lookup(Base: PEntry; N: Cardinal; Value: Cardinal): PEntry; inline;
var
  Half: Cardinal;
begin
  Result := nil;
  { Skip the search when the value lies outside the subset's range }
  if (N = 0) or (Value < ValueOf(Base[0])) or (Value > ValueOf(Base[N - 1])) then
    Exit;
  { Halve the range with arithmetic so unpredictable comparisons cost no mispredicted branch }
  while N > 1 do
  begin
    Half := N shr 1;
    Inc(Base, Half and Cardinal(-Ord(ValueOf(Base[Half]) <= Value)));
    Dec(N, Half);
  end;
  if ValueOf(Base^) = Value then
    Result := Base;
end;

{ Find how the target is first made from a subset without building all of its values }
function FindExact(const S: TState; Mask: Cardinal; out Hit: TEntry): Boolean;
var
  Left, Right, NL, NR, I, K, Count, N, BestA, BestB: Cardinal;
  Lefts, Rights: PEntry;
  M: array[0..5] of Cardinal;
  Ops: array[0..5] of Byte;
  BestOp: Byte;

  { Fill M and Ops with every number that combines with N to make the target in operator order }
  procedure Partners;
  var
    T: Cardinal;
  begin
    T := S.Target;
    Count := 0;
    if T > N then
    begin
      M[Count] := T - N;
      Ops[Count] := OpAdd;
      Inc(Count);
    end;
    if N > T then
    begin
      M[Count] := N - T;
      Ops[Count] := OpSub;
      Inc(Count);
    end;
    M[Count] := N + T;
    Ops[Count] := OpSub;
    Inc(Count);
    { Divide only when the quotient could be at least two since neither operand may be one }
    if (N <> 1) and (2 * N <= T) and (T mod N = 0) then
    begin
      M[Count] := T div N;
      Ops[Count] := OpMul;
      Inc(Count);
    end;
    if (N >= 2 * T) and (N mod T = 0) then
    begin
      M[Count] := N div T;
      Ops[Count] := OpDiv;
      Inc(Count);
    end;
    { Skip a product too large for any subset to make }
    if (N <> 1) and (QWord(N) * T <= High(Cardinal)) then
    begin
      M[Count] := N * T;
      Ops[Count] := OpDiv;
      Inc(Count);
    end;
  end;

begin
  Count := 0;
  FillChar(M, SizeOf(M), 0);
  FillChar(Ops, SizeOf(Ops), 0);
  Left := (Mask - 1) and Mask;
  while Left <> 0 do
  begin
    Right := Mask xor Left;
    { Visit splits in the same order as building so the same origin wins }
    if Left < Right then
    begin
      Lefts := S.Arena + S.Off[Left];
      Rights := S.Arena + S.Off[Right];
      NL := S.Len[Left];
      NR := S.Len[Right];
      { Keep the lowest pair as building would since partners come in operator order }
      BestA := High(Cardinal);
      BestB := High(Cardinal);
      BestOp := 0;
      if NL <= NR then
      begin
        { Take the first left value with any partner on the right since left values ascend }
        I := 0;
        while (I < NL) and (BestOp = 0) do
        begin
          N := ValueOf(Lefts[I]);
          Partners;
          for K := 0 to Count - 1 do
            if (M[K] < BestB) and (Lookup(Rights, NR, M[K]) <> nil) then
            begin
              BestA := N;
              BestB := M[K];
              BestOp := Ops[K];
            end;
          Inc(I);
        end;
      end
      else
        for I := 0 to NR - 1 do
        begin
          N := ValueOf(Rights[I]);
          Partners;
          for K := 0 to Count - 1 do
            if (M[K] < BestA) and (Lookup(Lefts, NL, M[K]) <> nil) then
            begin
              BestA := M[K];
              BestB := N;
              BestOp := Ops[K];
            end;
        end;
      if BestOp <> 0 then
      begin
        if BestA >= BestB then
        begin
          Hit.Head := MakeTemplate(BestOp, Left, Right) or S.Target;
          Hit.Operands := BestA or (QWord(BestB) shl 32);
        end
        else
        begin
          Hit.Head := MakeTemplate(BestOp, Right, Left) or S.Target;
          Hit.Operands := BestB or (QWord(BestA) shl 32);
        end;
        Exit(True);
      end;
    end;
    Left := (Left - 1) and Mask;
  end;
  Result := False;
end;

{ Build the sorted reachable values of a subset into the arena keeping only the first way found to make each }
procedure Build(var S: TState; Mask: Cardinal);
var
  Left, Right, V, W, Words, Below: Cardinal;
  Count, I, K, Pairs, Bound: SizeInt;
  Output, Sorted: PEntry;
  E: TEntry;
begin
  Count := 0;
  { Mark zero as seen so inexact divisions never become entries }
  S.Seen[0] := S.Seen[0] or 1;
  Left := (Mask - 1) and Mask;
  while Left <> 0 do
  begin
    Right := Mask xor Left;
    { Visit each split once rather than once per ordering }
    if Left < Right then
    begin
      { Reserve room for every pair's results plus the one slot each store may write past the end }
      Pairs := 4 * SizeInt(S.Len[Left]) * S.Len[Right];
      Bound := S.Max[Mask];
      if Pairs < Bound then
        Bound := Pairs;
      Reserve(S.Tmp, S.TmpCap, Count, Count + Bound + 1);
      Output := EmitSplit(S, Left, Right, S.Tmp + Count);
      Count := Output - S.Tmp;
    end;
    Left := (Left - 1) and Mask;
  end;
  S.Seen[0] := S.Seen[0] and not QWord(1);

  Reserve(S.Arena, S.Cap, S.Top, S.Top + Count);
  Sorted := S.Arena + S.Top;
  if Count < RankMin then
    { Clear only the words this subset touched and insertion sort the few values }
    for I := 0 to Count - 1 do
    begin
      E := S.Tmp[I];
      S.Seen[ValueOf(E) shr 6] := 0;
      K := I;
      while (K > 0) and (ValueOf(Sorted[K - 1]) > ValueOf(E)) do
      begin
        Sorted[K] := Sorted[K - 1];
        Dec(K);
      end;
      Sorted[K] := E;
    end
  else
  begin
    { Place each value at its rank in the bitset which needs no comparisons }
    Words := S.Max[Mask] div 64 + 1;
    Below := 0;
    for W := 0 to Words - 1 do
    begin
      S.Rank[W] := Below;
      Inc(Below, PopCnt(S.Seen[W]));
    end;
    for I := 0 to Count - 1 do
    begin
      V := ValueOf(S.Tmp[I]);
      W := V shr 6;
      Sorted[S.Rank[W] + PopCnt(S.Seen[W] and ((QWord(1) shl (V and 63)) - 1))] := S.Tmp[I];
    end;
    FillQWord(S.Seen^, Words, 0);
  end;
  S.Off[Mask] := S.Top;
  S.Len[Mask] := Count;
  Inc(S.Top, Count);
end;

{ Make the bitset and its ranks cover every value up to Largest }
procedure ReserveSeen(var S: TState; Largest: QWord);
var
  Words: SizeInt;
begin
  Words := Largest div 64 + 1;
  if Words <= S.SeenWords then
    Exit;
  { Replace rather than copy since building leaves the bitset clear }
  FreeMem(S.Seen);
  FreeMem(S.Rank);
  S.Seen := AllocMem(Words * SizeOf(QWord));
  S.Rank := GetMem(Words * SizeOf(Cardinal));
  S.SeenWords := Words;
end;

{ Make room for the values and reciprocals of the largest subset built so far }
procedure ReserveRights(var S: TState);
var
  Biggest: SizeInt;
  Mask: Integer;
begin
  Biggest := 0;
  for Mask := 1 to S.Full do
    if S.Len[Mask] > Biggest then
      Biggest := S.Len[Mask];
  if Biggest <= S.RightCap then
    Exit;
  FreeMem(S.RightValues);
  FreeMem(S.RightInv);
  S.RightValues := GetMem(Biggest * SizeOf(Cardinal));
  S.RightInv := GetMem(Biggest * SizeOf(Double));
  S.RightCap := Biggest;
end;

function Distance(Value, Target: Cardinal): Cardinal; inline;
begin
  if Value > Target then
    Result := Value - Target
  else
    Result := Target - Value;
end;

{ Write the expression for an entry following its origins back to the pool with brackets when asked }
function Render(const S: TState; const E: TEntry; Bracket: Boolean): string;
var
  Op: Char;
  LargerMask, SmallerMask: Cardinal;
begin
  Op := Chr(Byte(E.Head shr 32));
  if Op = #0 then
    Exit(IntToStr(ValueOf(E)));
  LargerMask := Byte(E.Head shr 40);
  SmallerMask := Byte(E.Head shr 48);
  Result := Render(S, Lookup(S.Arena + S.Off[LargerMask], S.Len[LargerMask], Cardinal(E.Operands))^, True) + ' ' +
    Op + ' ' + Render(S, Lookup(S.Arena + S.Off[SmallerMask], S.Len[SmallerMask], E.Operands shr 32)^, True);
  if Bracket then
    Result := '(' + Result + ')';
end;

function Solve(Target: Cardinal; const Pool: TPool; out Expr: string): Cardinal;
var
  S: TState;
  N, Mask, Left, Size, K, I, Used, BestUsed, Last: Integer;
  A, B: QWord;
  Largest: array[0..9] of QWord;
  First, Fill: array[0..9] of Integer;
  Order: array[0..255] of Byte;
  Best, Whole: TEntry;
  Solved: Boolean;
  D, BestDistance, WholeDistance: Cardinal;
  Values: PEntry;
begin
  S := Default(TState);
  N := Length(Pool);
  S.Target := Target;
  S.Full := (1 shl N) - 1;

  { Work out each subset's largest value since subtracting and dividing never exceed the larger operand }
  FillChar(Largest, SizeOf(Largest), 0);
  for Mask := 1 to S.Full do
  begin
    if Mask and (Mask - 1) = 0 then
      S.Max[Mask] := Pool[BsfDWord(Mask)]
    else
    begin
      Left := (Mask - 1) and Mask;
      while Left <> 0 do
      begin
        A := S.Max[Left];
        B := S.Max[Mask xor Left];
        if A * B > S.Max[Mask] then
          S.Max[Mask] := A * B;
        if A + B > S.Max[Mask] then
          S.Max[Mask] := A + B;
        Left := (Left - 1) and Mask;
      end;
    end;
    { Track the largest value of each size so the bitset only grows when bigger subsets are built }
    Size := PopCnt(DWord(Mask));
    if S.Max[Mask] > Largest[Size] then
      Largest[Size] := S.Max[Mask];
  end;

  { Store each pool number as a one-number subset }
  Reserve(S.Arena, S.Cap, 0, 4096);
  Best := Default(TEntry);
  Solved := False;
  for I := 0 to N - 1 do
  begin
    S.Arena[I].Head := Pool[I];
    S.Arena[I].Operands := 0;
    S.Off[1 shl I] := I;
    S.Len[1 shl I] := 1;
    if (not Solved) and (Pool[I] = Target) then
    begin
      Best := S.Arena[I];
      Solved := True;
    end;
  end;
  S.Top := N;

  { List subsets by size then mask so the loops below need no unpredictable size test }
  FillChar(First, SizeOf(First), 0);
  FillChar(Order, SizeOf(Order), 0);
  for Mask := 1 to S.Full do
    Inc(First[PopCnt(DWord(Mask)) + 1]);
  for Size := 1 to N + 1 do
    Inc(First[Size], First[Size - 1]);
  Fill := First;
  for Mask := 1 to S.Full do
  begin
    Order[Fill[PopCnt(DWord(Mask))]] := Mask;
    Inc(Fill[PopCnt(DWord(Mask))]);
  end;

  { Work through subsets smallest first stopping at the first size that hits the target }
  for Size := 2 to N do
  begin
    if Solved then
      Break;
    { Keep the lowest matching subset of this size to break ties the same way every run }
    for K := First[Size] to First[Size + 1] - 1 do
    begin
      Solved := FindExact(S, Order[K], Best);
      if Solved then
        Break;
    end;
    { Skip building the whole pool's values since no larger subset is made from them }
    if Solved or (Size = N) then
      Break;
    ReserveRights(S);
    ReserveSeen(S, Largest[Size]);
    for K := First[Size] to First[Size + 1] - 1 do
      Build(S, Order[K]);
  end;

  if not Solved then
  begin
    { Rank by distance from the target then by how many numbers are used so the simplest answer wins }
    BestDistance := High(Cardinal);
    BestUsed := 99;
    { Include a one-number pool here since the whole-pool pass below needs at least two numbers }
    if N > 1 then
      Last := S.Full - 1
    else
      Last := S.Full;
    for Mask := 1 to Last do
    begin
      Used := PopCnt(DWord(Mask));
      Values := S.Arena + S.Off[Mask];
      for I := 0 to Integer(S.Len[Mask]) - 1 do
      begin
        D := Distance(ValueOf(Values[I]), Target);
        if (D < BestDistance) or ((D = BestDistance) and (Used < BestUsed)) then
        begin
          Best := Values[I];
          BestDistance := D;
          BestUsed := Used;
        end;
      end;
    end;
    { Check the whole pool's values as they are made since no larger subset is built from them }
    if N > 1 then
    begin
      ReserveRights(S);
      Whole.Head := High(Cardinal);
      Whole.Operands := 0;
      WholeDistance := High(Cardinal);
      Left := (S.Full - 1) and S.Full;
      while Left <> 0 do
      begin
        if Left < S.Full xor Left then
          CheckSplit(S, Left, S.Full xor Left, Whole, WholeDistance);
        Left := (Left - 1) and S.Full;
      end;
      { Fall back to the whole pool only when it gets strictly closer as it uses the most numbers }
      if WholeDistance < BestDistance then
        Best := Whole;
    end;
  end;

  { Render without outer brackets which matches stripping them from the bracketed form }
  Expr := Render(S, Best, False);
  Result := ValueOf(Best);
  FreeMem(S.Arena);
  FreeMem(S.Tmp);
  FreeMem(S.Seen);
  FreeMem(S.Rank);
  FreeMem(S.RightValues);
  FreeMem(S.RightInv);
end;

end.
