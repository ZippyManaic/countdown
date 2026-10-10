--  Generate a Countdown numbers round and work out whether it can be solved
with Ada.Command_Line;
with Ada.Numerics.Discrete_Random;
with Ada.Strings.Fixed;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Ada.Text_IO; use Ada.Text_IO;
with Solver; use Solver;

procedure Countdown is
   subtype Index is Positive range 1 .. 20;
   package Random_Index is new Ada.Numerics.Discrete_Random (Natural);
   Generator : Random_Index.Generator;

   --  Return a random number from zero up to but not including N
   function Below (N : Positive) return Natural is (Random_Index.Random (Generator) mod N);

   --  Shuffle numbers in place with Fisher-Yates
   procedure Shuffle (Items : in out Number_List) is
   begin
      for I in reverse Items'First + 1 .. Items'Last loop
         declare
            J : constant Positive := Items'First + Below (I - Items'First + 1);
            T : constant Natural := Items (I);
         begin
            Items (I) := Items (J);
            Items (J) := T;
         end;
      end loop;
   end Shuffle;

   function Image (N : Natural) return String is (Ada.Strings.Fixed.Trim (Natural'Image (N), Ada.Strings.Left));

   Small       : Number_List (Index);
   Large       : Number_List := (25, 50, 75, 100);
   Target      : Natural;
   Large_Count : Positive;
   Value       : Natural;
   Expr        : Unbounded_String;
begin
   Random_Index.Reset (Generator);
   Target := 100 + Below (900);
   Large_Count := 1 + Below (2);
   --  Hold two cards of each small number to match the game's deck
   for I in Index loop
      Small (I) := (I - 1) mod 10 + 1;
   end loop;
   Shuffle (Small);
   --  Shuffle a copy since each large number appears only once in the game
   Shuffle (Large);
   declare
      Pool : constant Number_List := Small (1 .. 6 - Large_Count) & Large (1 .. Large_Count);
   begin
      Put_Line ("Target: " & Image (Target));
      Put ("Pool:  ");
      for P of Pool loop
         Put (" " & Image (P));
      end loop;
      New_Line;
      Solve (Target, Pool, Value, Expr);
   end;
   if Value = Target then
      Put_Line ("Solved: " & To_String (Expr) & " = " & Image (Value));
   else
      Put_Line ("No exact solution, closest is " & To_String (Expr) & " = " & Image (Value)
        & " (" & Image (abs (Value - Target)) & " away)");
      Ada.Command_Line.Set_Exit_Status (1);
   end if;
end Countdown;
