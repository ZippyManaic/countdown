{ Check the solver against rounds with known answers }
program Tests;

{$mode objfpc}{$H+}

uses
  { Use the C library's allocator since Free Pascal's returns large blocks to the kernel after every solve }
  cmem, Solver, Dealer;

var
  Failures: Integer = 0;
  Value: Cardinal;
  Expr: string;

procedure Expect(Ok: Boolean; const What: string);
begin
  if not Ok then
  begin
    WriteLn('FAIL: ', What);
    Inc(Failures);
  end;
end;

{ Deal many rounds in a mode and check each is legal and every allowed large count occurs }
procedure CheckDeals(Mode: TGameMode);
var
  Round, I, J, Large: Integer;
  Target: Cardinal;
  Pool: TPool;
  Counts: array[0..100] of Integer;
  Seen: array[0..4] of Boolean;
  Legal, InSet: Boolean;
begin
  Legal := True;
  FillChar(Seen, SizeOf(Seen), 0);
  for Round := 1 to 2000 do
  begin
    Deal(Mode, RandomCount, Target, Pool);
    Legal := Legal and (Target >= 100) and (Target <= 999) and (Length(Pool) = 6);
    FillChar(Counts, SizeOf(Counts), 0);
    Large := 0;
    for I := 0 to High(Pool) do
    begin
      Inc(Counts[Pool[I]]);
      if Pool[I] > 10 then
      begin
        Inc(Large);
        InSet := False;
        for J := 0 to 3 do
          InSet := InSet or (LargeNumbers[Mode][J] = Pool[I]);
        Legal := Legal and InSet and (Counts[Pool[I]] = 1);
      end
      else
        Legal := Legal and (Counts[Pool[I]] <= 2);
    end;
    Legal := Legal and (Large >= MinLarge[Mode]) and (Large <= MaxLarge[Mode]);
    Seen[Large] := True;
  end;
  Expect(Legal, ModeNames[Mode] + ' deals legal rounds');
  for I := MinLarge[Mode] to MaxLarge[Mode] do
    Expect(Seen[I], ModeNames[Mode] + ' deals every large count');
end;

{ Check that the arguments parse to the given mode and count }
procedure ExpectParse(const Args: array of string; Mode: TGameMode; Count: Integer; const What: string);
var
  Got: TGameMode;
  N: Integer;
begin
  Expect(ParseArgs(Args, Got, N) and (Got = Mode) and (N = Count), 'parses ' + What);
end;

{ Check that the arguments are rejected }
procedure ExpectReject(const Args: array of string; const What: string);
var
  Got: TGameMode;
  N: Integer;
begin
  Expect(not ParseArgs(Args, Got, N), 'rejects ' + What);
end;

var
  Mode: TGameMode;
  Count, I, Large: Integer;
  Target: Cardinal;
  Pool: TPool;

begin
  Value := Solve(125, [1, 5, 7, 3, 75, 50], Expr);
  Expect((Value = 125) and (Expr = '75 + 50'), 'finds simplest solution');
  Expect(Solve(552, [8, 4, 2, 5, 100, 25], Expr) = 552, 'solves 552');
  Value := Solve(974, [8, 8, 6, 8, 25, 100], Expr);
  Expect((Value = 973) or (Value = 975), 'reports closest when unsolvable');

  for Mode := Low(TGameMode) to High(TGameMode) do
    CheckDeals(Mode);
  for Mode := gmCats to gmNasty do
    for Count := 0 to 4 do
    begin
      Deal(Mode, Count, Target, Pool);
      Large := 0;
      for I := 0 to High(Pool) do
        if Pool[I] > 10 then
          Inc(Large);
      Expect(Large = Count, ModeNames[Mode] + ' deals a fixed large count');
    end;

  ExpectParse([], gmStandard, RandomCount, 'no arguments');
  ExpectParse(['nasty', '4'], gmNasty, 4, 'nasty 4');
  ExpectParse(['cats', '0'], gmCats, 0, 'cats 0');
  ExpectReject(['standard', '3'], 'standard 3');
  ExpectReject(['cats', '5'], 'cats 5');
  ExpectReject(['easy'], 'an unknown mode');
  ExpectReject(['cats', '1', '2'], 'three arguments');
  ExpectReject(['cats', 'x'], 'a non-numeric count');

  Value := Solve(999, [10, 10, 25, 50, 75, 100], Expr);
  Expect((Value = 999) and (Expr = '(((75 + 25) * 100) - 10) / 10'), 'solves cats 999');
  Value := Solve(100, [1, 1, 2, 2, 3, 3], Expr);
  Expect((Value = 81) and (Expr = '(((2 + 1) * (2 + 1)) * 3) * 3'), 'solves cats 100');
  Value := Solve(999, [2, 3, 87, 62, 37, 12], Expr);
  Expect((Value = 999) and (Expr = '37 * ((87 / 3) - 2)'), 'solves nasty 999');
  if Failures > 0 then
    Halt(1);
  WriteLn('all tests passed');
end.
