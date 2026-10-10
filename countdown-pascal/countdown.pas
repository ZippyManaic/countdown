{ Generate a Countdown numbers round and work out whether it can be solved }
program Countdown;

{$mode objfpc}{$H+}

uses
  { Use the C library's allocator since Free Pascal's returns large blocks to the kernel after every solve }
  cmem, Solver;

const
  LargeNumbers: array[0..3] of Cardinal = (25, 50, 75, 100);

{ Shuffle numbers in place with Fisher-Yates }
procedure Shuffle(var Items: array of Cardinal);
var
  I, J: Integer;
  T: Cardinal;
begin
  for I := High(Items) downto 1 do
  begin
    J := Random(I + 1);
    T := Items[I];
    Items[I] := Items[J];
    Items[J] := T;
  end;
end;

var
  Target, Value: Cardinal;
  LargeCount, I: Integer;
  Small: array[0..19] of Cardinal;
  Large: array[0..3] of Cardinal;
  Pool: TPool;
  Expr: string;
begin
  Randomize;
  Target := 100 + Random(900);
  LargeCount := 1 + Random(2);

  { Hold two cards of each small number to match the game's deck }
  for I := 0 to 19 do
    Small[I] := I mod 10 + 1;
  Shuffle(Small);
  { Shuffle a copy since each large number appears only once in the game }
  Large := LargeNumbers;
  Shuffle(Large);

  SetLength(Pool, 6);
  for I := 0 to 5 - LargeCount do
    Pool[I] := Small[I];
  for I := 0 to LargeCount - 1 do
    Pool[6 - LargeCount + I] := Large[I];

  WriteLn('Target: ', Target);
  Write('Pool:  ');
  for I := 0 to 5 do
    Write(' ', Pool[I]);
  WriteLn;

  Value := Solve(Target, Pool, Expr);
  if Value = Target then
  begin
    WriteLn('Solved: ', Expr, ' = ', Value);
    Halt(0);
  end;
  if Value > Target then
    WriteLn('No exact solution, closest is ', Expr, ' = ', Value, ' (', Value - Target, ' away)')
  else
    WriteLn('No exact solution, closest is ', Expr, ' = ', Value, ' (', Target - Value, ' away)');
  Halt(1);
end.
