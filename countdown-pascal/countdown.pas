{ Generate a Countdown numbers round and work out whether it can be solved }
program Countdown;

{$mode objfpc}{$H+}

uses
  { Use the C library's allocator since Free Pascal's returns large blocks to the kernel after every solve }
  cmem, Solver, Dealer;

var
  Target, Value: Cardinal;
  LargeCount, I: Integer;
  Mode: TGameMode;
  Args: array of string;
  Pool: TPool;
  Expr: string;
begin
  Args := nil;
  SetLength(Args, ParamCount);
  for I := 1 to ParamCount do
    Args[I - 1] := ParamStr(I);
  if not ParseArgs(Args, Mode, LargeCount) then
  begin
    WriteLn(StdErr, Usage);
    Halt(2);
  end;
  Deal(Mode, LargeCount, Target, Pool);

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
