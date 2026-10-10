--  Check the solver against rounds with known answers
with Ada.Command_Line;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Ada.Text_IO; use Ada.Text_IO;
with Solver; use Solver;

procedure Tests is
   Failures : Natural := 0;
   Value    : Natural;
   Expr     : Unbounded_String;

   procedure Expect (Ok : Boolean; What : String) is
   begin
      if not Ok then
         Put_Line ("FAIL: " & What);
         Failures := Failures + 1;
      end if;
   end Expect;
begin
   Solve (125, (1, 5, 7, 3, 75, 50), Value, Expr);
   Expect (Value = 125 and then To_String (Expr) = "75 + 50", "finds simplest solution");
   Solve (552, (8, 4, 2, 5, 100, 25), Value, Expr);
   Expect (Value = 552, "solves 552");
   Solve (974, (8, 8, 6, 8, 25, 100), Value, Expr);
   Expect (Value = 973 or else Value = 975, "reports closest when unsolvable");
   if Failures > 0 then
      Ada.Command_Line.Set_Exit_Status (1);
   else
      Put_Line ("all tests passed");
   end if;
end Tests;
