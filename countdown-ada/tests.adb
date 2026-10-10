--  Check the solver against rounds with known answers
with Ada.Command_Line;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Ada.Text_IO; use Ada.Text_IO;
with Dealer; use Dealer;
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

   --  Deal many rounds in a mode and check each is legal and every allowed large count occurs
   procedure Check_Deals (M : Game_Mode) is
      Target : Natural;
      Pool   : Number_List (1 .. 6);
      Seen   : array (0 .. 4) of Boolean := (others => False);
      Legal  : Boolean := True;
   begin
      for Round in 1 .. 2000 loop
         Deal (M, Random_Count, Target, Pool);
         declare
            Counts : array (0 .. 100) of Natural := (others => 0);
            Large  : Natural := 0;
         begin
            Legal := Legal and Target in 100 .. 999;
            for P of Pool loop
               Counts (P) := Counts (P) + 1;
               if P > 10 then
                  Large := Large + 1;
                  Legal := Legal and Counts (P) = 1 and (for some L of Large_Numbers (M) => L = P);
               else
                  Legal := Legal and Counts (P) <= 2;
               end if;
            end loop;
            Legal := Legal and Large in Min_Large (M) .. Max_Large (M);
            Seen (Large) := True;
         end;
      end loop;
      Expect (Legal, Game_Mode'Image (M) & " deals legal rounds");
      Expect ((for all C in Min_Large (M) .. Max_Large (M) => Seen (C)), Game_Mode'Image (M) & " deals every count");
   end Check_Deals;

   --  Return the arguments as a list for Parse_Args
   function Args (A, B : String := ""; C : String := "") return Argument_List is
      All_Args : constant Argument_List :=
        (To_Unbounded_String (A), To_Unbounded_String (B), To_Unbounded_String (C));
      Count    : Natural := 0;
   begin
      for Arg of All_Args loop
         if Length (Arg) > 0 then
            Count := Count + 1;
         end if;
      end loop;
      return All_Args (1 .. Count);
   end Args;

   --  Check that the arguments parse to the given mode and count
   procedure Expect_Parse (List : Argument_List; M : Game_Mode; Count : Integer; What : String) is
      Ok  : Boolean;
      Got : Game_Mode;
      N   : Integer;
   begin
      Parse_Args (List, Ok, Got, N);
      Expect (Ok and then Got = M and then N = Count, "parses " & What);
   end Expect_Parse;

   --  Check that the arguments are rejected
   procedure Expect_Reject (List : Argument_List; What : String) is
      Ok  : Boolean;
      Got : Game_Mode;
      N   : Integer;
   begin
      Parse_Args (List, Ok, Got, N);
      Expect (not Ok, "rejects " & What);
   end Expect_Reject;

   Target : Natural;
   Pool   : Number_List (1 .. 6);
begin
   Solve (125, (1, 5, 7, 3, 75, 50), Value, Expr);
   Expect (Value = 125 and then To_String (Expr) = "75 + 50", "finds simplest solution");
   Solve (552, (8, 4, 2, 5, 100, 25), Value, Expr);
   Expect (Value = 552, "solves 552");
   Solve (974, (8, 8, 6, 8, 25, 100), Value, Expr);
   Expect (Value = 973 or else Value = 975, "reports closest when unsolvable");

   for M in Game_Mode loop
      Check_Deals (M);
   end loop;
   for M in Cats .. Nasty loop
      for Count in 0 .. 4 loop
         Deal (M, Count, Target, Pool);
         Expect ((for all I in 1 .. 6 - Count => Pool (I) <= 10)
           and then (for all I in 7 - Count .. 6 => Pool (I) > 10),
           Game_Mode'Image (M) & " deals" & Integer'Image (Count) & " large");
      end loop;
   end loop;

   Expect_Parse (Args, Dealer.Standard, Random_Count, "no arguments");
   Expect_Parse (Args ("nasty", "4"), Nasty, 4, "nasty 4");
   Expect_Parse (Args ("cats", "0"), Cats, 0, "cats 0");
   Expect_Reject (Args ("standard", "3"), "standard 3");
   Expect_Reject (Args ("cats", "5"), "cats 5");
   Expect_Reject (Args ("easy"), "an unknown mode");
   Expect_Reject (Args ("cats", "1", "2"), "three arguments");
   Expect_Reject (Args ("cats", "x"), "a non-numeric count");

   Solve (999, (10, 10, 25, 50, 75, 100), Value, Expr);
   Expect (Value = 999 and then To_String (Expr) = "(((75 + 25) * 100) - 10) / 10", "solves cats 999");
   Solve (100, (1, 1, 2, 2, 3, 3), Value, Expr);
   Expect (Value = 81 and then To_String (Expr) = "(((2 + 1) * (2 + 1)) * 3) * 3", "solves cats 100");
   Solve (999, (2, 3, 87, 62, 37, 12), Value, Expr);
   Expect (Value = 999 and then To_String (Expr) = "37 * ((87 / 3) - 2)", "solves nasty 999");
   if Failures > 0 then
      Ada.Command_Line.Set_Exit_Status (1);
   else
      Put_Line ("all tests passed");
   end if;
end Tests;
