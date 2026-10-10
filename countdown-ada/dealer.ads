--  Deal Countdown numbers rounds and read the game mode from the command line
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Solver; use Solver;

package Dealer is

   --  Name the game mode, which sets the large cards and how many may be dealt
   type Game_Mode is (Standard, Cats, Nasty);

   type Argument_List is array (Positive range <>) of Unbounded_String;

   Usage : constant String := "usage: countdown [standard|cats|nasty] [LARGE]";

   --  Mark a large count to be chosen at random
   Random_Count : constant Integer := -1;

   --  Return the four large cards of the mode
   function Large_Numbers (M : Game_Mode) return Number_List;

   --  Return the fewest large cards the mode allows
   function Min_Large (M : Game_Mode) return Natural is (if M = Standard then 1 else 0);

   --  Return the most large cards the mode allows
   function Max_Large (M : Game_Mode) return Natural is (if M = Standard then 2 else 4);

   --  Deal a random target and six numbers with one or two large in standard mode and none to four otherwise
   procedure Deal
     (M           : Game_Mode;
      Large_Count : Integer;
      Target      : out Natural;
      Pool        : out Number_List)
   with Pre => Pool'Length = 6;

   --  Read the mode and fixed large count from the arguments and clear Ok when they are invalid
   procedure Parse_Args
     (Args        : Argument_List;
      Ok          : out Boolean;
      M           : out Game_Mode;
      Large_Count : out Integer);

end Dealer;
