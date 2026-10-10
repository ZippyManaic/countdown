-- | Check the solver against rounds with known answers
module Main (main) where

import Control.Monad (unless)
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
      ]
  , not ok
  ]

main :: IO ()
main = do
  mapM_ (putStrLn . ("FAIL: " ++)) failures
  unless (null failures) exitFailure
  putStrLn "all tests passed"
