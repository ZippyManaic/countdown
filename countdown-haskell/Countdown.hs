-- | Generate a Countdown numbers round and work out whether it can be solved
module Main (main) where

import Solver (solve)
import System.Exit (exitFailure, exitSuccess)
import System.Random (randomRIO)

largeNumbers :: [Int]
largeNumbers = [25, 50, 75, 100]

-- | Return the numbers in a random order by drawing each from those left
shuffle :: [Int] -> IO [Int]
shuffle [] = return []
shuffle items = do
  i <- randomRIO (0, length items - 1)
  case splitAt i items of
    (before, chosen : after) -> (chosen :) <$> shuffle (before ++ after)
    _ -> return items

-- | Return a random target and a pool of six numbers with either one or two large numbers
generateRound :: IO (Int, [Int])
generateRound = do
  target <- randomRIO (100, 999)
  largeCount <- randomRIO (1, 2)
  -- Hold two cards of each small number to match the game's deck
  small <- shuffle ([1 .. 10] ++ [1 .. 10])
  -- Shuffle a copy since each large number appears only once in the game
  large <- shuffle largeNumbers
  return (target, take (6 - largeCount) small ++ take largeCount large)

main :: IO ()
main = do
  (target, pool) <- generateRound
  putStrLn ("Target: " ++ show target)
  putStrLn ("Pool:   " ++ unwords (map show pool))
  let (value, expr) = solve target pool
  if value == target
    then putStrLn ("Solved: " ++ expr ++ " = " ++ show value) >> exitSuccess
    else do
      putStrLn ("No exact solution, closest is " ++ expr ++ " = " ++ show value ++ " (" ++ show (abs (value - target)) ++ " away)")
      exitFailure
