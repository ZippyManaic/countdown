--  Time the solver over a file of rounds and write each answer as value tab expression
with Ada.Command_Line; use Ada.Command_Line;
with Ada.Real_Time; use Ada.Real_Time;
with Ada.Strings.Fixed;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Ada.Text_IO; use Ada.Text_IO;
with Solver; use Solver;

procedure Ada_Harness is
   type Round is array (1 .. 7) of Natural;
   type Round_Array is array (Positive range <>) of Round;
   type Round_Access is access Round_Array;
   type Value_Array is array (Positive range <>) of Natural;
   type Expr_Array is array (Positive range <>) of Unbounded_String;
   --  Print the time per round in fixed notation since Float'Image uses an exponent
   type Milliseconds is delta 0.0001 digits 12;

   Rounds : Round_Access := new Round_Array (1 .. 20_000);
   Count  : Natural := 0;
   Reps   : constant Positive := (if Argument_Count > 2 then Positive'Value (Argument (3)) else 1);
   Input  : File_Type;
   Output : File_Type;
begin
   Open (Input, In_File, Argument (1));
   while not End_Of_File (Input) loop
      declare
         Line : constant String := Get_Line (Input);
         At_Char : Positive := Line'First;
         Last : Natural;
      begin
         Count := Count + 1;
         for K in 1 .. 7 loop
            declare
               Start : Positive := At_Char;
            begin
               while Line (Start) = ' ' loop
                  Start := Start + 1;
               end loop;
               Last := Ada.Strings.Fixed.Index (Line (Start .. Line'Last), " ");
               if Last = 0 then
                  Last := Line'Last + 1;
               end if;
               Rounds (Count) (K) := Natural'Value (Line (Start .. Last - 1));
               At_Char := Natural'Min (Last, Line'Last);
            end;
         end loop;
      end;
   end loop;
   Close (Input);

   declare
      Values : Value_Array (1 .. Count);
      Exprs  : Expr_Array (1 .. Count);
      Start  : constant Time := Clock;
      Took   : Duration;
   begin
      for Rep in 1 .. Reps loop
         for I in 1 .. Count loop
            Solve (Rounds (I) (1), Number_List (Rounds (I) (2 .. 7)), Values (I), Exprs (I));
         end loop;
      end loop;
      Took := To_Duration (Clock - Start);
      Put_Line (Standard_Error, Milliseconds'Image (Milliseconds (Took * 1000 / (Count * Reps))) & " ms/round");
      Create (Output, Out_File, Argument (2));
      for I in 1 .. Count loop
         declare
            V : constant String := Ada.Strings.Fixed.Trim (Natural'Image (Values (I)), Ada.Strings.Left);
         begin
            if I > 1 then
               New_Line (Output);
            end if;
            Put (Output, V & ASCII.HT & To_String (Exprs (I)));
         end;
      end loop;
      Close (Output);
   end;
end Ada_Harness;
