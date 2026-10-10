-- | Deal Countdown rounds in each mode and read the mode from the command line
module Round (Mode (..), largeNumbers, allowedCounts, generateRound, parseArgs, usage) where

import System.Random (randomRIO)

-- | Name the standard game, the cats game and the nasty-cats game
data Mode = Standard | Cats | Nasty
  deriving (Eq, Show)

usage :: String
usage = "usage: countdown [standard|cats|nasty] [LARGE]"

-- | Return the large cards of a mode, with nasty-cats using the cards of the 2010 specials
largeNumbers :: Mode -> [Int]
largeNumbers Nasty = [12, 37, 62, 87]
largeNumbers _ = [25, 50, 75, 100]

-- | Return the large counts a mode allows
allowedCounts :: Mode -> [Int]
allowedCounts Standard = [1, 2]
allowedCounts _ = [0 .. 4]

-- | Return the numbers in a random order by drawing each from those left
shuffle :: [Int] -> IO [Int]
shuffle [] = return []
shuffle items = do
  i <- randomRIO (0, length items - 1)
  case splitAt i items of
    (before, chosen : after) -> (chosen :) <$> shuffle (before ++ after)
    _ -> return items

-- | Return a random target and six numbers with one or two large in standard mode and none to four otherwise
generateRound :: Mode -> Maybe Int -> IO (Int, [Int])
generateRound mode fixed = do
  target <- randomRIO (100, 999)
  largeCount <- maybe (randomRIO (if mode == Standard then (1, 2) else (0, 4))) return fixed
  -- Hold two cards of each small number to match the game's deck
  small <- shuffle ([1 .. 10] ++ [1 .. 10])
  -- Shuffle a copy since each large number appears only once in the game
  large <- shuffle (largeNumbers mode)
  return (target, take (6 - largeCount) small ++ take largeCount large)

parseMode :: String -> Maybe Mode
parseMode "standard" = Just Standard
parseMode "cats" = Just Cats
parseMode "nasty" = Just Nasty
parseMode _ = Nothing

-- | Return the mode and fixed large count from the command line, or Nothing when the arguments are invalid
parseArgs :: [String] -> Maybe (Mode, Maybe Int)
parseArgs [] = Just (Standard, Nothing)
parseArgs [m] = (\mode -> (mode, Nothing)) <$> parseMode m
parseArgs [m, n] = do
  mode <- parseMode m
  count <- lookup n [(show k, k) | k <- allowedCounts mode]
  return (mode, Just count)
parseArgs _ = Nothing
