{ Deal Countdown numbers rounds and read the game mode from the command line }
unit Dealer;

{$mode objfpc}{$H+}

interface

uses
  Solver;

type
  { Name the game mode, which sets the large cards and how many may be dealt }
  TGameMode = (gmStandard, gmCats, gmNasty);
  TLargeNumbers = array[0..3] of Cardinal;

const
  Usage = 'usage: countdown [standard|cats|nasty] [LARGE]';
  { Mark a large count to be chosen at random }
  RandomCount = -1;
  ModeNames: array[TGameMode] of string = ('standard', 'cats', 'nasty');
  { Give each mode its large cards, with nasty-cats using the cards of the 2010 specials }
  LargeNumbers: array[TGameMode] of TLargeNumbers = ((25, 50, 75, 100), (25, 50, 75, 100), (12, 37, 62, 87));
  MinLarge: array[TGameMode] of Integer = (1, 0, 0);
  MaxLarge: array[TGameMode] of Integer = (2, 4, 4);

{ Deal a random target and six numbers with one or two large in standard mode and none to four otherwise }
procedure Deal(Mode: TGameMode; LargeCount: Integer; out Target: Cardinal; out Pool: TPool);

{ Return the mode and fixed large count from the arguments, or False when they are invalid }
function ParseArgs(const Args: array of string; out Mode: TGameMode; out LargeCount: Integer): Boolean;

implementation

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

procedure Deal(Mode: TGameMode; LargeCount: Integer; out Target: Cardinal; out Pool: TPool);
var
  I: Integer;
  Small: array[0..19] of Cardinal;
  Large: TLargeNumbers;
begin
  Target := 100 + Random(900);
  if LargeCount = RandomCount then
    LargeCount := MinLarge[Mode] + Random(MaxLarge[Mode] - MinLarge[Mode] + 1);

  { Hold two cards of each small number to match the game's deck }
  for I := 0 to 19 do
    Small[I] := I mod 10 + 1;
  Shuffle(Small);
  { Shuffle a copy since each large number appears only once in the game }
  Large := LargeNumbers[Mode];
  Shuffle(Large);

  Pool := nil;
  SetLength(Pool, 6);
  for I := 0 to 5 - LargeCount do
    Pool[I] := Small[I];
  for I := 0 to LargeCount - 1 do
    Pool[6 - LargeCount + I] := Large[I];
end;

function ParseArgs(const Args: array of string; out Mode: TGameMode; out LargeCount: Integer): Boolean;
var
  Name: string;
  M: TGameMode;
  Found: Boolean;
begin
  Result := False;
  Mode := gmStandard;
  LargeCount := RandomCount;
  if Length(Args) > 2 then
    Exit;
  Name := 'standard';
  if Length(Args) > 0 then
    Name := Args[0];
  Found := False;
  for M := Low(TGameMode) to High(TGameMode) do
    if ModeNames[M] = Name then
    begin
      Mode := M;
      Found := True;
    end;
  if not Found then
    Exit;
  if Length(Args) = 2 then
  begin
    { Accept only a single digit so that forms such as "+1" are rejected as in the Python version }
    if (Length(Args[1]) <> 1) or not (Args[1][1] in ['0'..'9']) then
      Exit;
    LargeCount := Ord(Args[1][1]) - Ord('0');
    if (LargeCount < MinLarge[Mode]) or (LargeCount > MaxLarge[Mode]) then
    begin
      LargeCount := RandomCount;
      Exit;
    end;
  end;
  Result := True;
end;

initialization
  Randomize;
end.
