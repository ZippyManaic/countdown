--  Generate a Countdown numbers round and work out whether it can be solved
with Ada.Command_Line;
with Ada.Strings.Fixed;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Ada.Text_IO; use Ada.Text_IO;
with Dealer; use Dealer;
with Solver; use Solver;

procedure Countdown is
   function Image (N : Natural) return String is (Ada.Strings.Fixed.Trim (Natural'Image (N), Ada.Strings.Left));

   Args        : Argument_List (1 .. Ada.Command_Line.Argument_Count);
   Ok          : Boolean;
   M           : Game_Mode;
   Large_Count : Integer;
   Target      : Natural;
   Pool        : Number_List (1 .. 6);
   Value       : Natural;
   Expr        : Unbounded_String;
begin
   for I in Args'Range loop
      Args (I) := To_Unbounded_String (Ada.Command_Line.Argument (I));
   end loop;
   Parse_Args (Args, Ok, M, Large_Count);
   if not Ok then
      Put_Line (Standard_Error, Usage);
      Ada.Command_Line.Set_Exit_Status (2);
      return;
   end if;
   Deal (M, Large_Count, Target, Pool);
   Put_Line ("Target: " & Image (Target));
   Put ("Pool:  ");
   for P of Pool loop
      Put (" " & Image (P));
   end loop;
   New_Line;
   Solve (Target, Pool, Value, Expr);
   if Value = Target then
      Put_Line ("Solved: " & To_String (Expr) & " = " & Image (Value));
   else
      Put_Line ("No exact solution, closest is " & To_String (Expr) & " = " & Image (Value)
        & " (" & Image (abs (Value - Target)) & " away)");
      Ada.Command_Line.Set_Exit_Status (1);
   end if;
end Countdown;
