{ Check the solver against rounds with known answers }
program Tests;

{$mode objfpc}{$H+}

uses
  { Use the C library's allocator since Free Pascal's returns large blocks to the kernel after every solve }
  cmem, Solver;

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

begin
  Value := Solve(125, [1, 5, 7, 3, 75, 50], Expr);
  Expect((Value = 125) and (Expr = '75 + 50'), 'finds simplest solution');
  Expect(Solve(552, [8, 4, 2, 5, 100, 25], Expr) = 552, 'solves 552');
  Value := Solve(974, [8, 8, 6, 8, 25, 100], Expr);
  Expect((Value = 973) or (Value = 975), 'reports closest when unsolvable');
  if Failures > 0 then
    Halt(1);
  WriteLn('all tests passed');
end.
