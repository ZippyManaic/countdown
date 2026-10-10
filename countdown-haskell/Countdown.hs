-- | Generate a Countdown numbers round and work out whether it can be solved
module Main (main) where

import Round (generateRound, parseArgs, usage)
import Solver (solve)
import System.Environment (getArgs)
import System.Exit (ExitCode (ExitFailure), exitFailure, exitSuccess, exitWith)
import System.IO (hPutStrLn, stderr)

main :: IO ()
main = do
  args <- getArgs
  (mode, fixed) <- maybe (hPutStrLn stderr usage >> exitWith (ExitFailure 2)) return (parseArgs args)
  (target, pool) <- generateRound mode fixed
  putStrLn ("Target: " ++ show target)
  putStrLn ("Pool:   " ++ unwords (map show pool))
  let (value, expr) = solve target pool
  if value == target
    then putStrLn ("Solved: " ++ expr ++ " = " ++ show value) >> exitSuccess
    else do
      putStrLn ("No exact solution, closest is " ++ expr ++ " = " ++ show value ++ " (" ++ show (abs (value - target)) ++ " away)")
      exitFailure
