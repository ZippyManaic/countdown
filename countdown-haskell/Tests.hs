-- | Check the dealer in every mode and the solver against rounds with known answers
module Main (main) where

import Control.Monad (replicateM, unless)
import Data.List (nub, sort)
import Data.Maybe (catMaybes)
import Round (Mode (..), allowedCounts, generateRound, largeNumbers, parseArgs)
import Solver (solve)
import System.Exit (exitFailure)

-- | Return the names of the checks that fail
failures :: [String]
failures =
  [ what
  | (ok, what) <-
      [ (solve 125 [1, 5, 7, 3, 75, 50] == (125, "75 + 50"), "finds simplest solution")
      , (fst (solve 552 [8, 4, 2, 5, 100, 25]) == 552, "solves 552")
      , (abs (fst (solve 974 [8, 8, 6, 8, 25, 100]) - 974) == 1, "reports closest when unsolvable")
      , (solve 423 [6, 2, 2, 1, 1, 25] == (423, "(25 * ((6 * (2 + 1)) - 1)) - 2"), "uses every number")
      , (solve 431 [3, 2, 3, 4, 2, 25] == (432, "((25 * 3) - 3) * (4 + 2)"), "prefers fewer numbers when closest")
      , (solve 7 [7] == (7, "7"), "handles a single number")
      , (solve 10 [3] == (3, "3"), "handles a single number that misses")
      , (solve 12 [3, 4] == (12, "4 * 3"), "handles two numbers")
      , (solve 999 [10, 10, 25, 50, 75, 100] == (999, "(((75 + 25) * 100) - 10) / 10"), "solves a four-large cats round")
      , (solve 100 [1, 1, 2, 2, 3, 3] == (81, "(((2 + 1) * (2 + 1)) * 3) * 3"), "reports closest on a no-large cats round")
      , (solve 999 [2, 3, 87, 62, 37, 12] == (999, "37 * ((87 / 3) - 2)"), "solves a nasty-cats round")
      , (parseArgs [] == Just (Standard, Nothing), "parses no arguments")
      , (parseArgs ["nasty", "4"] == Just (Nasty, Just 4), "parses nasty 4")
      , (parseArgs ["cats", "0"] == Just (Cats, Just 0), "parses cats 0")
      , (all ((== Nothing) . parseArgs) [["standard", "3"], ["cats", "5"], ["dogs"], ["cats", "1", "2"], ["cats", "x"]], "rejects bad arguments")
      ]
  , not ok
  ]

-- | Return the large count of a dealt round, or Nothing when the round breaks the rules of its mode
checkRound :: Mode -> [Int] -> (Int, [Int]) -> Maybe Int
checkRound mode counts (target, pool)
  | target < 100 || target > 999 || length pool /= 6 = Nothing
  | length large `notElem` counts || any (`notElem` largeNumbers mode) large || nub large /= large = Nothing
  -- Allow each small number at most twice since the deck holds two of each
  | any (\n -> length (filter (== n) pool) > 2) [1 .. 10] = Nothing
  | otherwise = Just (length large)
  where
    large = filter (> 10) pool

-- | Return the names of the dealer checks that fail
dealerFailures :: IO [String]
dealerFailures = do
  random <- mapM randomMode [Standard, Cats, Nasty]
  fixed <- sequence [fixedCount mode k | mode <- [Cats, Nasty], k <- [0 .. 4]]
  return (concat (random ++ fixed))
  where
    randomMode mode = do
      seen <- map (checkRound mode (allowedCounts mode)) <$> replicateM 2000 (generateRound mode Nothing)
      return ["deals valid " ++ show mode ++ " rounds" | Nothing `elem` seen || nub (sort (catMaybes seen)) /= allowedCounts mode]
    fixedCount mode k = do
      r <- generateRound mode (Just k)
      return ["deals " ++ show k ++ " large in " ++ show mode | checkRound mode [k] r /= Just k]

main :: IO ()
main = do
  dealer <- dealerFailures
  let failed = failures ++ dealer
  mapM_ (putStrLn . ("FAIL: " ++)) failed
  unless (null failed) exitFailure
  putStrLn "all tests passed"
