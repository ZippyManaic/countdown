with Ada.Strings.Fixed;
with Ada.Unchecked_Deallocation;
with Interfaces; use Interfaces;

package body Solver is

   use Ada.Strings.Unbounded;

   --  Sort subsets with fewer values than this by insertion rather than by rank in the bitset
   Rank_Min : constant := 16;
   --  Radix sort a subset when its bitset has more than this many words per value
   Sparse : constant := 64;

   Op_Add : constant Unsigned_64 := Character'Pos ('+');
   Op_Sub : constant Unsigned_64 := Character'Pos ('-');
   Op_Mul : constant Unsigned_64 := Character'Pos ('*');
   Op_Div : constant Unsigned_64 := Character'Pos ('/');

   --  Use a modular type for subset masks so they support bitwise operators
   type Mask_Type is mod 256;

   --  Record a reachable value with how it was made from the larger and smaller of two values in disjoint subsets
   type Entry_Type is record
      --  Pack value, operator (zero for a pool number), larger mask and smaller mask from the low bits up
      Head     : Unsigned_64;
      --  Pack the larger operand in the low half and the smaller in the high half
      Operands : Unsigned_64;
   end record;

   type Entry_Array is array (Natural range <>) of Entry_Type;
   type Entry_Access is access Entry_Array;
   type Word_Array is array (Natural range <>) of Unsigned_64;
   type Word_Access is access Word_Array;
   type Count_Array is array (Natural range <>) of Unsigned_32;
   type Count_Access is access Count_Array;
   type Float_Array is array (Natural range <>) of Long_Float;
   type Float_Access is access Float_Array;

   procedure Free is new Ada.Unchecked_Deallocation (Entry_Array, Entry_Access);
   procedure Free is new Ada.Unchecked_Deallocation (Word_Array, Word_Access);
   procedure Free is new Ada.Unchecked_Deallocation (Count_Array, Count_Access);
   procedure Free is new Ada.Unchecked_Deallocation (Float_Array, Float_Access);

   function Popcount (X : Unsigned_64) return Integer
     with Import, Convention => Intrinsic, External_Name => "__builtin_popcountll";

   type Mask_Numbers is array (Mask_Type) of Natural;
   type Mask_Values is array (Mask_Type) of Unsigned_64;

   --  Hold the working memory of one solve
   type State is record
      Target : Unsigned_64;
      Full   : Mask_Type;
      --  Keep every subset's sorted values back to back in one arena
      Arena  : Entry_Access;
      Top    : Natural := 0;
      Off    : Mask_Numbers := (others => 0);
      Len    : Mask_Numbers := (others => 0);
      --  Hold the largest value each subset can make which bounds the bitset words it touches
      Max    : Mask_Values := (others => 0);
      --  Hold one bit per value seen in the subset being built
      Seen   : Word_Access;
      --  Collect a subset's new values here before they are sorted into the arena
      Tmp    : Entry_Access;
      --  Hold the count of values below each bitset word for ranking
      Rank   : Count_Access;
      --  Hold the right half's values with their reciprocals for the split being built
      Right_Values : Word_Access;
      Right_Inv    : Float_Access;
   end record;

   function Value_Of (E : Entry_Type) return Unsigned_64 is (E.Head and 16#FFFF_FFFF#) with Inline;

   --  Return the operator and masks of an entry shifted above its value
   function Template (Op : Unsigned_64; Larger_Mask, Smaller_Mask : Mask_Type) return Unsigned_64 is
     (Shift_Left (Op or Shift_Left (Unsigned_64 (Larger_Mask), 8) or Shift_Left (Unsigned_64 (Smaller_Mask), 16), 32))
     with Inline;

   --  Grow an entry buffer to at least Need entries by doubling keeping its first Keep entries
   procedure Reserve (Items : in out Entry_Access; Keep, Need : Natural) is
      Size  : Natural;
      Grown : Entry_Access;
   begin
      if Items /= null and then Need <= Items'Length then
         return;
      end if;
      Size := (if Items = null then 1024 else Natural'Max (Items'Length, 1024));
      while Size < Need loop
         Size := Size * 2;
      end loop;
      Grown := new Entry_Array (0 .. Size - 1);
      if Items /= null then
         Grown (0 .. Keep - 1) := Items (0 .. Keep - 1);
         Free (Items);
      end if;
      Items := Grown;
   end Reserve;

   --  Return x divided by y when the division is exact and zero otherwise using the reciprocal of y
   function Exact (X, Y : Unsigned_64; Inv : Long_Float) return Unsigned_64 is
      Q : constant Unsigned_64 := Unsigned_64 (Long_Float'Machine_Rounding (Long_Float (X) * Inv));
   begin
      --  Mask with arithmetic since the comparison would otherwise become a branch
      return Q and (0 - Unsigned_64 (Boolean'Pos (Q * Y = X)));
   end Exact;

   --  Append every new value from pairing each left value with each right value of one split and return the new end
   function Emit_Split (S : in out State; Left, Right : Mask_Type; Start : Natural) return Natural is
      Arena : Entry_Array renames S.Arena.all;
      Seen  : Word_Array renames S.Seen.all;
      Tmp   : Entry_Array renames S.Tmp.all;
      RV    : Word_Array renames S.Right_Values.all;
      RI    : Float_Array renames S.Right_Inv.all;
      TL_Add : constant Unsigned_64 := Template (Op_Add, Left, Right);
      TL_Sub : constant Unsigned_64 := Template (Op_Sub, Left, Right);
      TL_Mul : constant Unsigned_64 := Template (Op_Mul, Left, Right);
      TL_Div : constant Unsigned_64 := Template (Op_Div, Left, Right);
      TR_Add : constant Unsigned_64 := Template (Op_Add, Right, Left);
      TR_Sub : constant Unsigned_64 := Template (Op_Sub, Right, Left);
      TR_Mul : constant Unsigned_64 := Template (Op_Mul, Right, Left);
      TR_Div : constant Unsigned_64 := Template (Op_Div, Right, Left);
      NR     : constant Natural := S.Len (Right);
      Out_At : Natural := Start;
      Operands : Unsigned_64;

      --  Store a value and move on only if the bitset shows it is new so duplicates cost no mispredicted branch
      procedure Emit (V, Tmpl : Unsigned_64) with Inline is
         Word : constant Natural := Natural (Shift_Right (V, 6));
         Bit  : constant Natural := Natural (V and 63);
         W    : constant Unsigned_64 := Seen (Word);
      begin
         Seen (Word) := W or Shift_Left (1, Bit);
         Tmp (Out_At) := (Tmpl or V, Operands);
         Out_At := Out_At + Natural (Shift_Right (not W, Bit) and 1);
      end Emit;
   begin
      --  Invert each right value once per split rather than once per pair
      for J in 0 .. NR - 1 loop
         RV (J) := Value_Of (Arena (S.Off (Right) + J));
         RI (J) := 1.0 / Long_Float (RV (J));
      end loop;
      for I in S.Off (Left) .. S.Off (Left) + S.Len (Left) - 1 loop
         declare
            A  : constant Unsigned_64 := Value_Of (Arena (I));
            J  : Natural := 0;
            IA : constant Long_Float := 1.0 / Long_Float (A);
         begin
            --  Pair with right values up to a first where a is the larger and ties go left
            while J < NR and then RV (J) <= A loop
               declare
                  B : constant Unsigned_64 := RV (J);
               begin
                  Operands := A or Shift_Left (B, 32);
                  Emit (A + B, TL_Add);
                  --  Skip a zero result since every intermediate value must be a positive integer
                  if A /= B then
                     Emit (A - B, TL_Sub);
                  end if;
                  --  Skip multiplying and dividing by one as they never produce a new value
                  if B /= 1 then
                     Emit (A * B, TL_Mul);
                     Emit (Exact (A, B, RI (J)), TL_Div);
                  end if;
               end;
               J := J + 1;
            end loop;
            --  Pair with the remaining larger right values where a is the smaller
            while J < NR loop
               declare
                  B : constant Unsigned_64 := RV (J);
               begin
                  Operands := B or Shift_Left (A, 32);
                  Emit (B + A, TR_Add);
                  Emit (B - A, TR_Sub);
                  if A /= 1 then
                     Emit (B * A, TR_Mul);
                     Emit (Exact (B, A, IA), TR_Div);
                  end if;
               end;
               J := J + 1;
            end loop;
         end;
      end loop;
      return Out_At;
   end Emit_Split;

   --  Return the arena index of Value in a subset or -1 when it is absent
   function Lookup (S : State; Mask : Mask_Type; Value : Unsigned_64) return Integer with Inline;

   function Lookup (S : State; Mask : Mask_Type; Value : Unsigned_64) return Integer is
      Arena : Entry_Array renames S.Arena.all;
      Base  : Natural := S.Off (Mask);
      N     : Natural := S.Len (Mask);
      Half  : Natural;
   begin
      --  Skip the search when the value lies outside the subset's range
      if N = 0 or else Value < Value_Of (Arena (Base)) or else Value > Value_Of (Arena (Base + N - 1)) then
         return -1;
      end if;
      --  Halve the range with arithmetic so unpredictable comparisons cost no mispredicted branch
      while N > 1 loop
         Half := N / 2;
         Base := Base + Half * Boolean'Pos (Value_Of (Arena (Base + Half)) <= Value);
         N := N - Half;
      end loop;
      return (if Value_Of (Arena (Base)) = Value then Base else -1);
   end Lookup;

   --  Find how the target is first made from a subset without building all of its values
   function Find_Exact (S : State; Mask : Mask_Type; Hit : out Entry_Type) return Boolean is
      Arena : Entry_Array renames S.Arena.all;
      T     : constant Unsigned_64 := S.Target;
      Left  : Mask_Type := (Mask - 1) and Mask;
   begin
      while Left /= 0 loop
         declare
            Right       : constant Mask_Type := Mask xor Left;
            Left_Loop   : constant Boolean := S.Len (Left) <= S.Len (Right);
            Loop_Mask   : constant Mask_Type := (if Left_Loop then Left else Right);
            Search_Mask : constant Mask_Type := (if Left_Loop then Right else Left);
            Best_A, Best_B : Unsigned_64 := Unsigned_64'Last;
            Best_Op     : Unsigned_64 := 0;

            --  Keep a partner when it beats the best so far and the searched subset can make it
            procedure Try (N, M, Op : Unsigned_64) with Inline is
            begin
               if Left_Loop then
                  if M < Best_B and then Lookup (S, Search_Mask, M) >= 0 then
                     Best_A := N;
                     Best_B := M;
                     Best_Op := Op;
                  end if;
               elsif M < Best_A and then Lookup (S, Search_Mask, M) >= 0 then
                  Best_A := M;
                  Best_B := N;
                  Best_Op := Op;
               end if;
            end Try;
         begin
            --  Visit splits in the same order as building so the same origin wins
            if Left < Right then
               for I in S.Off (Loop_Mask) .. S.Off (Loop_Mask) + S.Len (Loop_Mask) - 1 loop
                  declare
                     N : constant Unsigned_64 := Value_Of (Arena (I));
                  begin
                     --  Try each number that combines with n to make the target in operator order
                     if T > N then
                        Try (N, T - N, Op_Add);
                     end if;
                     if N > T then
                        Try (N, N - T, Op_Sub);
                     end if;
                     Try (N, N + T, Op_Sub);
                     --  Divide only when the quotient could be at least two since neither operand may be one
                     if N /= 1 and then 2 * N <= T and then T mod N = 0 then
                        Try (N, T / N, Op_Mul);
                     end if;
                     if N >= 2 * T and then N mod T = 0 then
                        Try (N, N / T, Op_Div);
                     end if;
                     if N /= 1 then
                        Try (N, N * T, Op_Div);
                     end if;
                  end;
                  --  Take the first left value with any partner since left values ascend
                  exit when Best_Op /= 0 and then Left_Loop;
               end loop;
               if Best_Op /= 0 then
                  if Best_A >= Best_B then
                     Hit := (Template (Best_Op, Left, Right) or T, Best_A or Shift_Left (Best_B, 32));
                  else
                     Hit := (Template (Best_Op, Right, Left) or T, Best_B or Shift_Left (Best_A, 32));
                  end if;
                  return True;
               end if;
            end if;
         end;
         Left := (Left - 1) and Mask;
      end loop;
      return False;
   end Find_Exact;

   --  Build the sorted reachable values of a subset into the arena keeping only the first way found to make each
   procedure Build (S : in out State; Mask : Mask_Type) is
      Count : Natural := 0;
      Left  : Mask_Type := (Mask - 1) and Mask;
   begin
      --  Mark zero as seen so inexact divisions never become entries
      S.Seen (0) := S.Seen (0) or 1;
      while Left /= 0 loop
         declare
            Right : constant Mask_Type := Mask xor Left;
            Pairs : constant Unsigned_64 := 4 * Unsigned_64 (S.Len (Left)) * Unsigned_64 (S.Len (Right));
         begin
            --  Visit each split once rather than once per ordering
            if Left < Right then
               --  Reserve room for every pair's results plus the one slot each store may write past the end
               Reserve (S.Tmp, Count, Count + Natural (Unsigned_64'Min (Pairs, S.Max (Mask))) + 1);
               Count := Emit_Split (S, Left, Right, Count);
            end if;
         end;
         Left := (Left - 1) and Mask;
      end loop;
      S.Seen (0) := S.Seen (0) and not 1;

      Reserve (S.Arena, S.Top, S.Top + Count);
      declare
         Arena : Entry_Array renames S.Arena.all;
         Seen  : Word_Array renames S.Seen.all;
         Tmp   : Entry_Array renames S.Tmp.all;
         Base  : constant Natural := S.Top;
      begin
         if Count < Rank_Min then
            --  Clear only the words this subset touched and insertion sort the few values
            for I in 0 .. Count - 1 loop
               declare
                  E : constant Entry_Type := Tmp (I);
                  K : Natural := I;
               begin
                  Seen (Natural (Shift_Right (Value_Of (E), 6))) := 0;
                  while K > 0 and then Value_Of (Arena (Base + K - 1)) > Value_Of (E) loop
                     Arena (Base + K) := Arena (Base + K - 1);
                     K := K - 1;
                  end loop;
                  Arena (Base + K) := E;
               end;
            end loop;
         elsif S.Max (Mask) / 64 + 1 > Sparse * Unsigned_64 (Count) then
            --  Radix sort sparse subsets so the cost follows the values found rather than the range they could span
            declare
               Counts : array (0 .. 2, 0 .. 2047) of Natural := (others => (others => 0));
               Sum, C, D : Natural;
               V : Unsigned_64;
            begin
               for I in 0 .. Count - 1 loop
                  V := Value_Of (Tmp (I));
                  Seen (Natural (Shift_Right (V, 6))) := 0;
                  D := Natural (V and 2047);
                  Counts (0, D) := Counts (0, D) + 1;
                  D := Natural (Shift_Right (V, 11) and 2047);
                  Counts (1, D) := Counts (1, D) + 1;
                  D := Natural (Shift_Right (V, 22));
                  Counts (2, D) := Counts (2, D) + 1;
               end loop;
               for Pass in 0 .. 2 loop
                  Sum := 0;
                  for Digit in 0 .. 2047 loop
                     C := Counts (Pass, Digit);
                     Counts (Pass, Digit) := Sum;
                     Sum := Sum + C;
                  end loop;
                  --  Scatter from the scratch buffer to the arena and back so the third pass lands in the arena
                  if Pass = 1 then
                     for I in 0 .. Count - 1 loop
                        D := Natural (Shift_Right (Value_Of (Arena (Base + I)), 11) and 2047);
                        Tmp (Counts (Pass, D)) := Arena (Base + I);
                        Counts (Pass, D) := Counts (Pass, D) + 1;
                     end loop;
                  else
                     for I in 0 .. Count - 1 loop
                        D := Natural (Shift_Right (Value_Of (Tmp (I)), 11 * Pass) and 2047);
                        Arena (Base + Counts (Pass, D)) := Tmp (I);
                        Counts (Pass, D) := Counts (Pass, D) + 1;
                     end loop;
                  end if;
               end loop;
            end;
         else
            --  Place each value at its rank in the bitset which needs no comparisons
            declare
               Words : constant Natural := Natural (S.Max (Mask) / 64) + 1;
               Rank  : Count_Array renames S.Rank.all;
               Below : Unsigned_32 := 0;
            begin
               for W in 0 .. Words - 1 loop
                  Rank (W) := Below;
                  Below := Below + Unsigned_32 (Popcount (Seen (W)));
               end loop;
               for I in 0 .. Count - 1 loop
                  declare
                     V     : constant Unsigned_64 := Value_Of (Tmp (I));
                     W     : constant Natural := Natural (Shift_Right (V, 6));
                     Lower : constant Unsigned_64 := Seen (W) and (Shift_Left (1, Natural (V and 63)) - 1);
                  begin
                     Arena (Base + Natural (Rank (W)) + Popcount (Lower)) := Tmp (I);
                  end;
               end loop;
               Seen (0 .. Words - 1) := (others => 0);
            end;
         end if;
      end;
      S.Off (Mask) := S.Top;
      S.Len (Mask) := Count;
      S.Top := S.Top + Count;
   end Build;

   --  Make the bitset and its ranks cover every value up to Largest replacing them since building leaves the bitset clear
   procedure Reserve_Seen (S : in out State; Largest : Unsigned_64) is
      Words : constant Natural := Natural (Largest / 64) + 1;
   begin
      if S.Seen = null or else Words > S.Seen'Length then
         if S.Seen /= null then
            Free (S.Seen);
            Free (S.Rank);
         end if;
         S.Seen := new Word_Array'(0 .. Words - 1 => 0);
         S.Rank := new Count_Array (0 .. Words - 1);
      end if;
   end Reserve_Seen;

   --  Make room for the values and reciprocals of the largest subset built so far
   procedure Reserve_Rights (S : in out State) is
      Biggest : Natural := 1;
   begin
      for Mask in 1 .. S.Full loop
         Biggest := Natural'Max (Biggest, S.Len (Mask));
      end loop;
      if S.Right_Values = null or else Biggest > S.Right_Values'Length then
         if S.Right_Values /= null then
            Free (S.Right_Values);
            Free (S.Right_Inv);
         end if;
         S.Right_Values := new Word_Array (0 .. Biggest - 1);
         S.Right_Inv := new Float_Array (0 .. Biggest - 1);
      end if;
   end Reserve_Rights;

   function Image (N : Unsigned_64) return String is
     (Ada.Strings.Fixed.Trim (Unsigned_64'Image (N), Ada.Strings.Left));

   --  Write the expression for an entry following its origins back to the pool with brackets when asked
   function Render (S : State; E : Entry_Type; Bracket : Boolean) return String is
      Op : constant Unsigned_64 := Shift_Right (E.Head, 32) and 255;
   begin
      if Op = 0 then
         return Image (Value_Of (E));
      end if;
      declare
         Larger_Mask  : constant Mask_Type := Mask_Type (Shift_Right (E.Head, 40) and 255);
         Smaller_Mask : constant Mask_Type := Mask_Type (Shift_Right (E.Head, 48) and 255);
         Larger  : constant Entry_Type := S.Arena (Lookup (S, Larger_Mask, E.Operands and 16#FFFF_FFFF#));
         Smaller : constant Entry_Type := S.Arena (Lookup (S, Smaller_Mask, Shift_Right (E.Operands, 32)));
         Text    : constant String := Render (S, Larger, True) & " " & Character'Val (Op) & " " & Render (S, Smaller, True);
      begin
         return (if Bracket then "(" & Text & ")" else Text);
      end;
   end Render;

   function Distance (Value, Target : Unsigned_64) return Unsigned_64 is
     (if Value > Target then Value - Target else Target - Value);

   procedure Solve
     (Target : Natural;
      Pool   : Number_List;
      Value  : out Natural;
      Expr   : out Unbounded_String)
   is
      N       : constant Natural := Pool'Length;
      S       : State;
      Largest : array (0 .. 9) of Unsigned_64 := (others => 0);
      Best    : Entry_Type := (0, 0);
      Solved  : Boolean := False;
   begin
      S.Target := Unsigned_64 (Target);
      S.Full := Mask_Type (2 ** N - 1);

      --  Work out each subset's largest value since subtracting and dividing never exceed the larger operand
      for Mask in 1 .. S.Full loop
         if (Mask and (Mask - 1)) = 0 then
            declare
               Bit : Natural := 0;
               M   : Mask_Type := Mask;
            begin
               while (M and 1) = 0 loop
                  M := M / 2;
                  Bit := Bit + 1;
               end loop;
               S.Max (Mask) := Unsigned_64 (Pool (Pool'First + Bit));
            end;
         else
            declare
               Left : Mask_Type := (Mask - 1) and Mask;
            begin
               while Left /= 0 loop
                  declare
                     A : constant Unsigned_64 := S.Max (Left);
                     B : constant Unsigned_64 := S.Max (Mask xor Left);
                  begin
                     S.Max (Mask) := Unsigned_64'Max (S.Max (Mask), Unsigned_64'Max (A * B, A + B));
                  end;
                  Left := (Left - 1) and Mask;
               end loop;
            end;
         end if;
         --  Track the largest value of each size so the bitset only grows when bigger subsets are built
         declare
            Size : constant Natural := Popcount (Unsigned_64 (Mask));
         begin
            Largest (Size) := Unsigned_64'Max (Largest (Size), S.Max (Mask));
         end;
      end loop;

      --  Store each pool number as a one-number subset
      Reserve (S.Arena, 0, 4096);
      for I in 0 .. N - 1 loop
         S.Arena (I) := (Unsigned_64 (Pool (Pool'First + I)), 0);
         S.Off (Mask_Type (2 ** I)) := I;
         S.Len (Mask_Type (2 ** I)) := 1;
         if not Solved and then Pool (Pool'First + I) = Target then
            Best := S.Arena (I);
            Solved := True;
         end if;
      end loop;
      S.Top := N;

      --  Work through subsets smallest first stopping at the first size that hits the target
      for Size in 2 .. N loop
         exit when Solved;
         --  Keep the lowest matching subset of this size to break ties the same way every run
         for Mask in 1 .. S.Full loop
            if Popcount (Unsigned_64 (Mask)) = Size and then Find_Exact (S, Mask, Best) then
               Solved := True;
               exit;
            end if;
         end loop;
         --  Skip building the whole pool's values since no larger subset is made from them
         exit when Solved or else Size = N;
         Reserve_Rights (S);
         Reserve_Seen (S, Largest (Size));
         for Mask in 1 .. S.Full loop
            if Popcount (Unsigned_64 (Mask)) = Size then
               Build (S, Mask);
            end if;
         end loop;
      end loop;

      if not Solved then
         declare
            Best_Distance : Unsigned_64 := Unsigned_64'Last;
            Best_Used     : Natural := 99;
            Whole         : Entry_Type := (16#FFFF_FFFF#, 0);
            Whole_Distance : Unsigned_64 := Unsigned_64'Last;
            --  Include a one-number pool here since the whole-pool pass below needs at least two numbers
            Last          : constant Mask_Type := (if N > 1 then S.Full - 1 else S.Full);
         begin
            --  Rank by distance from the target then by how many numbers are used so the simplest answer wins
            for Mask in 1 .. Last loop
               for I in S.Off (Mask) .. S.Off (Mask) + S.Len (Mask) - 1 loop
                  declare
                     D    : constant Unsigned_64 := Distance (Value_Of (S.Arena (I)), S.Target);
                     Used : constant Natural := Popcount (Unsigned_64 (Mask));
                  begin
                     if D < Best_Distance or else (D = Best_Distance and then Used < Best_Used) then
                        Best := S.Arena (I);
                        Best_Distance := D;
                        Best_Used := Used;
                     end if;
                  end;
               end loop;
            end loop;
            --  Check the whole pool's values as they are made since no larger subset is built from them
            if N > 1 then
               declare
                  Left : Mask_Type := (S.Full - 1) and S.Full;

                  --  Keep a value if it is closer to the target or equally close and lower
                  procedure Check (V, Head, Operands : Unsigned_64) is
                     D : constant Unsigned_64 := Distance (V, S.Target);
                  begin
                     if V /= 0 and then (D < Whole_Distance or else (D = Whole_Distance and then V < Value_Of (Whole))) then
                        Whole_Distance := D;
                        Whole := (Head or V, Operands);
                     end if;
                  end Check;
               begin
                  while Left /= 0 loop
                     declare
                        Right : constant Mask_Type := S.Full xor Left;
                     begin
                        if Left < Right then
                           for I in S.Off (Left) .. S.Off (Left) + S.Len (Left) - 1 loop
                              for J in S.Off (Right) .. S.Off (Right) + S.Len (Right) - 1 loop
                                 declare
                                    A : constant Unsigned_64 := Value_Of (S.Arena (I));
                                    B : constant Unsigned_64 := Value_Of (S.Arena (J));
                                    X : constant Unsigned_64 := Unsigned_64'Max (A, B);
                                    Y : constant Unsigned_64 := Unsigned_64'Min (A, B);
                                    LM : constant Mask_Type := (if B <= A then Left else Right);
                                    SM : constant Mask_Type := (if B <= A then Right else Left);
                                    Ops : constant Unsigned_64 := X or Shift_Left (Y, 32);
                                 begin
                                    Check (X + Y, Template (Op_Add, LM, SM), Ops);
                                    if X /= Y then
                                       Check (X - Y, Template (Op_Sub, LM, SM), Ops);
                                    end if;
                                    if Y /= 1 then
                                       Check (X * Y, Template (Op_Mul, LM, SM), Ops);
                                       if X mod Y = 0 then
                                          Check (X / Y, Template (Op_Div, LM, SM), Ops);
                                       end if;
                                    end if;
                                 end;
                              end loop;
                           end loop;
                        end if;
                     end;
                     Left := (Left - 1) and S.Full;
                  end loop;
               end;
               --  Fall back to the whole pool only when it gets strictly closer as it uses the most numbers
               if Whole_Distance < Best_Distance then
                  Best := Whole;
               end if;
            end if;
         end;
      end if;

      --  Render without outer brackets which matches stripping them from the bracketed form
      Expr := To_Unbounded_String (Render (S, Best, False));
      Value := Natural (Value_Of (Best));
      Free (S.Arena);
      Free (S.Tmp);
      Free (S.Seen);
      Free (S.Rank);
      Free (S.Right_Values);
      Free (S.Right_Inv);
   end Solve;

end Solver;
