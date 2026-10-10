with Ada.Numerics.Discrete_Random;

package body Dealer is

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

   function Large_Numbers (M : Game_Mode) return Number_List is
   begin
      --  Use the large cards of the 2010 specials for nasty-cats
      if M = Nasty then
         return (12, 37, 62, 87);
      end if;
      return (25, 50, 75, 100);
   end Large_Numbers;

   procedure Deal
     (M           : Game_Mode;
      Large_Count : Integer;
      Target      : out Natural;
      Pool        : out Number_List)
   is
      Small : Number_List (1 .. 20);
      Large : Number_List := Large_Numbers (M);
      Count : Natural;
   begin
      Target := 100 + Below (900);
      if Large_Count = Random_Count then
         Count := Min_Large (M) + Below (Max_Large (M) - Min_Large (M) + 1);
      else
         Count := Large_Count;
      end if;
      --  Hold two cards of each small number to match the game's deck
      for I in Small'Range loop
         Small (I) := (I - 1) mod 10 + 1;
      end loop;
      Shuffle (Small);
      --  Shuffle a copy since each large number appears only once in the game
      Shuffle (Large);
      Pool := Small (1 .. 6 - Count) & Large (1 .. Count);
   end Deal;

   procedure Parse_Args
     (Args        : Argument_List;
      Ok          : out Boolean;
      M           : out Game_Mode;
      Large_Count : out Integer)
   is
      Name : constant String := (if Args'Length > 0 then To_String (Args (Args'First)) else "standard");
   begin
      Ok := False;
      M := Standard;
      Large_Count := Random_Count;
      if Args'Length > 2 then
         return;
      elsif Name = "standard" then
         M := Standard;
      elsif Name = "cats" then
         M := Cats;
      elsif Name = "nasty" then
         M := Nasty;
      else
         return;
      end if;
      if Args'Length = 2 then
         --  Accept only a single digit so that forms such as "+1" are rejected as in the Python version
         declare
            Count : constant String := To_String (Args (Args'First + 1));
         begin
            if Count'Length /= 1 or else Count (Count'First) not in '0' .. '9' then
               return;
            end if;
            Large_Count := Character'Pos (Count (Count'First)) - Character'Pos ('0');
            if Large_Count not in Min_Large (M) .. Max_Large (M) then
               Large_Count := Random_Count;
               return;
            end if;
         end;
      end if;
      Ok := True;
   end Parse_Args;

begin
   Random_Index.Reset (Generator);
end Dealer;
