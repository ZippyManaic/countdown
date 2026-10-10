{ Time the solver over a file of rounds and write each answer as value tab expression }
program Bench;

{$mode objfpc}{$H+}

uses
  cmem, SysUtils, Classes, Solver;

var
  Lines, Fields: TStringList;
  Rounds: array of array[0..6] of Cardinal;
  Values: array of Cardinal;
  Exprs: array of string;
  Pool: TPool;
  I, J, Rep, Reps: Integer;
  Start: QWord;
  Output: TStringList;
begin
  Lines := TStringList.Create;
  Lines.LoadFromFile(ParamStr(1));
  SetLength(Rounds, Lines.Count);
  Fields := TStringList.Create;
  Fields.Delimiter := ' ';
  for I := 0 to Lines.Count - 1 do
  begin
    Fields.DelimitedText := Lines[I];
    for J := 0 to 6 do
      Rounds[I][J] := StrToInt(Fields[J]);
  end;
  Reps := 1;
  if ParamCount > 2 then
    Reps := StrToInt(ParamStr(3));
  SetLength(Values, Length(Rounds));
  SetLength(Exprs, Length(Rounds));
  SetLength(Pool, 6);
  Start := GetTickCount64;
  for Rep := 1 to Reps do
    for I := 0 to High(Rounds) do
    begin
      for J := 0 to 5 do
        Pool[J] := Rounds[I][J + 1];
      Values[I] := Solve(Rounds[I][0], Pool, Exprs[I]);
    end;
  WriteLn(StdErr, Format('%.4f ms/round', [(GetTickCount64 - Start) / (Length(Rounds) * Reps)]));
  Output := TStringList.Create;
  Output.LineBreak := #10;
  Output.TrailingLineBreak := False;
  for I := 0 to High(Rounds) do
    Output.Add(IntToStr(Values[I]) + #9 + Exprs[I]);
  Output.SaveToFile(ParamStr(2));
end.
