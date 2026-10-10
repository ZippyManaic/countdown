--  Work out the simplest Countdown expression that hits a target or gets closest to it
with Ada.Strings.Unbounded;

package Solver is

   type Number_List is array (Positive range <>) of Natural;

   --  Return the simplest expression that hits the target or gets closest to it with its value
   procedure Solve
     (Target : Natural;
      Pool   : Number_List;
      Value  : out Natural;
      Expr   : out Ada.Strings.Unbounded.Unbounded_String);

end Solver;
