-- | Time the Haskell solver over a file of rounds and write each answer as value tab expression
module Main (main) where

import Control.DeepSeq (force)
import Control.Exception (evaluate)
import Control.Monad (forM)
import Data.List (intercalate)
import GHC.Clock (getMonotonicTime)
import Solver (solve)
import System.Environment (getArgs)
import System.IO (hPutStrLn, stderr)
import Text.Printf (printf)

-- | Split a round into its target and pool
parse :: [Int] -> (Int, [Int])
parse (target : pool) = (target, pool)
parse [] = error "empty round"

main :: IO ()
main = do
  args <- getArgs
  let (roundsPath, outPath) = (args !! 0, args !! 1)
      reps = if length args > 2 then read (args !! 2) else 1 :: Int
  rounds <- evaluate . force . map (parse . map read . words) . lines =<< readFile roundsPath
  let count = length rounds
  start <- getMonotonicTime
  -- Force every answer inside the timed region so laziness cannot defer the solving
  answers <- fmap last . forM [1 .. reps] $ \_ ->
    forM rounds $ \(target, pool) -> evaluate (force (solve target pool))
  end <- getMonotonicTime
  hPutStrLn stderr (printf "%.4f ms/round" ((end - start) * 1000 / fromIntegral count / fromIntegral reps :: Double))
  writeFile outPath (intercalate "\n" [show v ++ "\t" ++ e | (v, e) <- answers])
