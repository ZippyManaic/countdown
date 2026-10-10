{-# LANGUAGE BangPatterns #-}

-- | Work out the simplest Countdown expression that hits a target or gets closest to it
module Solver (solve) where

import Control.Monad (when)
import Control.Monad.ST (ST, runST)
import Data.Bits (complement, popCount, unsafeShiftL, unsafeShiftR, xor, (.&.), (.|.))
import Data.Primitive.PrimArray
import Data.Word (Word64)

-- | Sort subsets with fewer values than this by insertion rather than by rank in the bitset
rankMin :: Int
rankMin = 16

-- | Radix sort a subset when its bitset has more than this many words per value
sparse :: Int
sparse = 64

-- | Run an action for every index from a up to but not including b
loop :: Int -> Int -> (Int -> ST s ()) -> ST s ()
loop a b act = go a
  where
    go !i = when (i < b) (act i >> go (i + 1))
{-# INLINE loop #-}

-- | Compare integers directly so no dictionary is involved
imax, imin :: Int -> Int -> Int
imax a b = if a > b then a else b
imin a b = if a < b then a else b
{-# INLINE imax #-}
{-# INLINE imin #-}

-- | Append a value to tmp and return the new end advancing only if the bitset shows it is new
emit :: MutablePrimArray s Word64 -> MutablePrimArray s Int -> Int -> Int -> ST s Int
emit seen tmp !out !v = do
  let !w = v `unsafeShiftR` 6
      !b = v .&. 63
  word <- readPrimArray seen w
  writePrimArray seen w (word .|. (1 `unsafeShiftL` b))
  writePrimArray tmp out v
  return $! out + 1 - fromIntegral ((word `unsafeShiftR` b) .&. 1)
{-# INLINE emit #-}

-- | Emit every legal value from x and y under Countdown rules where x is at least y and inv is 1/y
ops :: MutablePrimArray s Word64 -> MutablePrimArray s Int -> Int -> Int -> Int -> Double -> ST s Int
ops seen tmp !out !x !y !inv = do
  o1 <- emit seen tmp out (x + y)
  -- Emit zero for equal operands since the bitset already marks it and drops it
  o2 <- emit seen tmp o1 (x - y)
  -- Skip multiplying and dividing by one as they never produce a new value
  if y /= 1
    then do
      o3 <- emit seen tmp o2 (x * y)
      -- Round the product with the reciprocal which is exact for every value a subset can make
      let !q = truncate (fromIntegral x * inv + 0.5 :: Double) :: Int
      emit seen tmp o3 (if q * y == x then q else 0)
    else return o2
{-# INLINE ops #-}

-- | Hold the working memory of one solve
data Work s = Work
  { offs :: !(MutablePrimArray s Int)
  , lens :: !(MutablePrimArray s Int)
  , maxes :: !(MutablePrimArray s Int)
  -- | Keep every subset's sorted values back to back
  , arena :: !(MutablePrimArray s Int)
  -- | Hold one bit per value seen in the subset being built
  , seen :: !(MutablePrimArray s Word64)
  -- | Collect a subset's new values here before they are sorted into the arena
  , tmp :: !(MutablePrimArray s Int)
  -- | Hold the count of values below each bitset word for ranking
  , ranks :: !(MutablePrimArray s Int)
  -- | Hold the reciprocals of the right half's values for the split being built
  , invs :: !(MutablePrimArray s Double)
  }

-- | Store the sorted values a subset can make in the arena at top and return the new top
build :: Work s -> Int -> Int -> ST s Int
build work !top !mask = do
  let vals = arena work
      bits = seen work
      out0 = tmp work
      inv = invs work
  -- Mark zero as seen so inexact divisions and equal differences never become values
  w0 <- readPrimArray bits 0
  writePrimArray bits 0 (w0 .|. 1)
  let splits !left !out
        | left == 0 = return out
        | left >= right = splits next out
        | otherwise = do
            ol <- readPrimArray (offs work) left
            nl <- readPrimArray (lens work) left
            orr <- readPrimArray (offs work) right
            nr <- readPrimArray (lens work) right
            -- Invert each right value once per split rather than once per pair
            loop 0 nr $ \j -> readPrimArray vals (orr + j) >>= writePrimArray inv j . (1 /) . fromIntegral
            let lefts !i !o
                  | i == nl = return o
                  | otherwise = do
                      a <- readPrimArray vals (ol + i)
                      -- Pair a with right values up to it first so the larger operand is known without testing
                      let below !j !o'
                            | j == nr = above j o'
                            | otherwise = do
                                y <- readPrimArray vals (orr + j)
                                if y > a
                                  then above j o'
                                  else readPrimArray inv j >>= ops bits out0 o' a y >>= below (j + 1)
                          !ia = 1 / fromIntegral a
                          above !j !o'
                            | j == nr = lefts (i + 1) o'
                            | otherwise = do
                                y <- readPrimArray vals (orr + j)
                                ops bits out0 o' y a ia >>= above (j + 1)
                      below 0 o
            lefts 0 out >>= splits next
        where
          right = mask `xor` left
          next = (left - 1) .&. mask
  count <- splits ((mask - 1) .&. mask) 0
  w0' <- readPrimArray bits 0
  writePrimArray bits 0 (w0' .&. complement 1)
  if count < rankMin
    then
      -- Clear only the words this subset touched and insertion sort the few values
      loop 0 count $ \i -> do
        v <- readPrimArray out0 i
        writePrimArray bits (v `unsafeShiftR` 6) 0
        let shift !k
              | k == 0 = writePrimArray vals top v
              | otherwise = do
                  u <- readPrimArray vals (top + k - 1)
                  if u > v
                    then writePrimArray vals (top + k) u >> shift (k - 1)
                    else writePrimArray vals (top + k) v
        shift i
    else do
      biggest <- readPrimArray (maxes work) mask
      let !nwords = biggest `unsafeShiftR` 6 + 1
      if nwords > sparse * count
        then do
          -- Radix sort sparse subsets so the cost follows the values found rather than the range they could span
          counts <- newPrimArray (3 * 2048)
          setPrimArray counts 0 (3 * 2048) (0 :: Int)
          let bump d = readPrimArray counts d >>= writePrimArray counts d . (+ 1)
          loop 0 count $ \i -> do
            v <- readPrimArray out0 i
            writePrimArray bits (v `unsafeShiftR` 6) 0
            bump (v .&. 2047)
            bump (2048 + (v `unsafeShiftR` 11) .&. 2047)
            bump (4096 + v `unsafeShiftR` 22)
          -- Pass from tmp to the arena and back so the third pass lands in the arena
          let pass !p from fromAt to toAt = do
                let !c = 2048 * p
                    !shift = 11 * p
                    sums !d !total = when (d < c + 2048) $ do
                      n <- readPrimArray counts d
                      writePrimArray counts d total
                      sums (d + 1) (total + n)
                sums c 0
                loop 0 count $ \i -> do
                  v <- readPrimArray from (fromAt + i)
                  let !d = c + (v `unsafeShiftR` shift) .&. 2047
                  at <- readPrimArray counts d
                  writePrimArray counts d (at + 1)
                  writePrimArray to (toAt + at) v
          pass 0 out0 0 vals top
          pass 1 vals top out0 0
          pass 2 out0 0 vals top
        else do
          -- Place each value at its rank in the bitset which needs no comparisons
          let rank = ranks work
              counts !w !below = when (w < nwords) $ do
                writePrimArray rank w below
                word <- readPrimArray bits w
                counts (w + 1) (below + popCount word)
          counts 0 0
          loop 0 count $ \i -> do
            v <- readPrimArray out0 i
            let !w = v `unsafeShiftR` 6
            word <- readPrimArray bits w
            r <- readPrimArray rank w
            writePrimArray vals (top + r + popCount (word .&. ((1 `unsafeShiftL` (v .&. 63)) - 1))) v
          setPrimArray bits 0 nwords 0
  writePrimArray (offs work) mask top
  writePrimArray (lens work) mask count
  return $! top + count

-- | Return whether count sorted values from off include v
contains :: MutablePrimArray s Int -> Int -> Int -> Int -> ST s Bool
contains vals !off !count !v
  | count == 0 = return False
  | otherwise = do
      lo <- readPrimArray vals off
      hi <- readPrimArray vals (off + count - 1)
      if v < lo || v > hi then return False else go off count
  where
    -- Halve the range with arithmetic so unpredictable comparisons cost no mispredicted branch
    go !base !n
      | n > 1 = do
          let !half = n `unsafeShiftR` 1
          x <- readPrimArray vals (base + half)
          go (base + (((x - v - 1) `unsafeShiftR` 63) .&. half)) (n - half)
      | otherwise = (== v) <$> readPrimArray vals base
{-# INLINE contains #-}

-- | Pack a way of making a value as split, operator and the values of both halves into one integer
pack :: Int -> Int -> Int -> Int -> Int
pack l op a b = (l `unsafeShiftL` 56) .|. (op `unsafeShiftL` 54) .|. (a `unsafeShiftL` 27) .|. b

-- | Track the lowest partner found so far with the scanned value and operator
data Best = Best !Int !Int !Int

-- | Return the first way building makes v from a subset packed by pack or -1 when it cannot
findWay :: Work s -> Int -> Int -> ST s Int
findWay work !mask !v = splits ((mask - 1) .&. mask)
  where
    vals = arena work
    splits !left
      | left == 0 = return (-1)
      | left >= right = splits next
      | otherwise = do
          ol <- readPrimArray (offs work) left
          nl <- readPrimArray (lens work) left
          orr <- readPrimArray (offs work) right
          nr <- readPrimArray (lens work) right
          -- Loop over the smaller half and search the larger for the earliest pair building would make
          let scanLeft = nl <= nr
              (so, sn, oo, on) = if scanLeft then (ol, nl, orr, nr) else (orr, nr, ol, nl)
              -- Keep partner m of p if it is lower than the best so far and the other half holds it
              try p m op best@(Best bm _ _)
                | m > 0 && m < bm = do
                    found <- contains vals oo on m
                    return (if found then Best m p op else best)
                | otherwise = return best
              -- Try every partner in operator order so an equal later one never wins
              partners p best0 = do
                b1 <- if v > p then try p (v - p) 0 best0 else return best0
                b2 <- if p > v then try p (p - v) 1 b1 else return b1
                b3 <- try p (p + v) 1 b2
                b4 <- if p /= 1 && 2 * p <= v && v `rem` p == 0 then try p (v `quot` p) 2 b3 else return b3
                b5 <- if p >= 2 * v && p `rem` v == 0 then try p (p `quot` v) 3 b4 else return b4
                if p /= 1 then try p (p * v) 3 b5 else return b5
              -- Stop at the first left value with a partner since left values ascend
              scan !i best@(Best _ _ op)
                | i == sn || (scanLeft && op >= 0) = return best
                | otherwise = do
                    p <- readPrimArray vals (so + i)
                    partners p best >>= scan (i + 1)
          Best m p op <- scan 0 (Best maxBound 0 (-1))
          if op < 0
            then splits next
            else return (if scanLeft then pack left op p m else pack left op m p)
      where
        right = mask `xor` left
        next = (left - 1) .&. mask

-- | Return the expression for a value of a subset following its first way back to the pool
render :: Work s -> Int -> Int -> Bool -> ST s ShowS
render work mask v bracket
  | mask .&. (mask - 1) == 0 = return (shows v)
  | otherwise = do
      way <- findWay work mask v
      let l = way `unsafeShiftR` 56
          op = (way `unsafeShiftR` 54) .&. 3
          a = (way `unsafeShiftR` 27) .&. 0x7FFFFFF
          b = way .&. 0x7FFFFFF
          r = mask `xor` l
          (lm, x, sm, y) = if a >= b then (l, a, r, b) else (r, b, l, a)
      larger <- render work lm x True
      smaller <- render work sm y True
      let body = larger . showChar ' ' . showChar ("+-*/" !! op) . showChar ' ' . smaller
      return (if bracket then showChar '(' . body . showChar ')' else body)

-- | Return the closest value the whole pool makes preferring the lower on equal distance with its distance
wholeClosest :: Work s -> Int -> Int -> ST s (Int, Int)
wholeClosest work !full !target = splits ((full - 1) .&. full) maxBound 0
  where
    vals = arena work
    splits !left !bd !bv
      | left == 0 = return (bv, bd)
      | left >= right = splits next bd bv
      | otherwise = do
          ol <- readPrimArray (offs work) left
          nl <- readPrimArray (lens work) left
          orr <- readPrimArray (offs work) right
          nr <- readPrimArray (lens work) right
          let pairs !i !j !d !w
                | i == nl = splits next d w
                | j == nr = pairs (i + 1) 0 d w
                | otherwise = do
                    a <- readPrimArray vals (ol + i)
                    b <- readPrimArray vals (orr + j)
                    let x = imax a b
                        y = imin a b
                        (d1, w1) = check (x + y) d w
                        (d2, w2) = if x > y then check (x - y) d1 w1 else (d1, w1)
                        (d3, w3) = if y /= 1 then check (x * y) d2 w2 else (d2, w2)
                        (d4, w4) = if y /= 1 && x `rem` y == 0 then check (x `quot` y) d3 w3 else (d3, w3)
                    pairs i (j + 1) d4 w4
          pairs 0 0 bd bv
      where
        right = full `xor` left
        next = (left - 1) .&. full
    -- Keep a value if it is closer or equally close and lower to break ties the same way every run
    check v d w =
      let dv = abs (v - target)
       in if dv < d || (dv == d && v < w) then (dv, v) else (d, w)

-- | Return an array holding the first used values of the old one with room for at least need
grow :: MutablePrimArray s Int -> Int -> Int -> ST s (MutablePrimArray s Int)
grow a used need = do
  have <- getSizeofMutablePrimArray a
  if need <= have
    then return a
    else do
      b <- newPrimArray (imax need (2 * have))
      when (used > 0) $ copyMutablePrimArray b 0 a 0 used
      return b

-- | Return the simplest expression that hits the target or gets closest to it with its value
solve :: Int -> [Int] -> (Int, String)
solve target poolList = runST $ do
  let pool = primArrayFromList poolList
      n = sizeofPrimArray pool
      full = (1 `unsafeShiftL` n) - 1
      masksOf size = [m | m <- [1 .. full], popCount m == size]
  offs0 <- newPrimArray (full + 1)
  lens0 <- newPrimArray (full + 1)
  maxes0 <- newPrimArray (full + 1)
  -- Zero the lengths since unbuilt subsets are read when sizing buffers
  setPrimArray lens0 0 (full + 1) 0
  setPrimArray offs0 0 (full + 1) 0
  -- Work out each subset's largest value since subtracting and dividing never exceed the larger operand
  largest <- newPrimArray (n + 1)
  setPrimArray largest 0 (n + 1) 0
  loop 1 (full + 1) $ \mask -> do
    m <-
      if mask .&. (mask - 1) == 0
        then return (indexPrimArray pool (popCount (mask - 1)))
        else do
          let go !left !best
                | left == 0 = return best
                | otherwise = do
                    a <- readPrimArray maxes0 left
                    b <- readPrimArray maxes0 (mask `xor` left)
                    go ((left - 1) .&. mask) (imax best (imax (a * b) (a + b)))
          go ((mask - 1) .&. mask) 0
    writePrimArray maxes0 mask m
    l <- readPrimArray largest (popCount mask)
    writePrimArray largest (popCount mask) (imax l m)
  topLargest <- if n > 1 then readPrimArray largest (n - 1) else return 0
  when (topLargest >= 1 `unsafeShiftL` 27) $ error "Solver.solve: pool numbers too large"
  -- Store each pool number as a one-number subset
  arena0 <- newPrimArray 4096
  loop 0 n $ \i -> do
    writePrimArray arena0 i (indexPrimArray pool i)
    writePrimArray offs0 (1 `unsafeShiftL` i) i
    writePrimArray lens0 (1 `unsafeShiftL` i) 1
  work0 <- Work offs0 lens0 maxes0 arena0 <$> newPrimArray 0 <*> newPrimArray 0 <*> newPrimArray 0 <*> newPrimArray 0
  let -- Keep the lowest matching subset of this size to break ties the same way every run
      search _ [] = return 0
      search work (m : ms) = do
        way <- findWay work m target
        if way >= 0 then return m else search work ms
      -- Reserve room for every value a subset could add since none makes more than its pairs or its range
      bound work m = do
        let go !left !s
              | left == 0 = return s
              | left >= (m `xor` left) = go ((left - 1) .&. m) s
              | otherwise = do
                  nl <- readPrimArray (lens work) left
                  nr <- readPrimArray (lens work) (m `xor` left)
                  go ((left - 1) .&. m) (s + 4 * nl * nr)
        pairs <- go ((m - 1) .&. m) 0
        mx <- readPrimArray (maxes work) m
        return (imin pairs mx + 1)
      -- Make every buffer big enough to build the subsets of this size
      reserve work size top = do
        bounds <- mapM (bound work) (masksOf size)
        vals <- grow (arena work) top (top + sum bounds)
        out <- grow (tmp work) 0 (maximum bounds + 1)
        big <- readPrimArray largest size
        let nwords = big `unsafeShiftR` 6 + 1
        haveBits <- getSizeofMutablePrimArray (seen work)
        bits <-
          if haveBits >= nwords
            then return (seen work)
            else do
              b <- newPrimArray nwords
              setPrimArray b 0 nwords 0
              return b
        haveRanks <- getSizeofMutablePrimArray (ranks work)
        rank <- if haveRanks >= nwords then return (ranks work) else newPrimArray nwords
        most <- maximum <$> mapM (readPrimArray (lens work)) [1 .. full]
        haveInvs <- getSizeofMutablePrimArray (invs work)
        inv <- if haveInvs >= most then return (invs work) else newPrimArray (2 * most)
        return work {arena = vals, tmp = out, seen = bits, ranks = rank, invs = inv}
      -- Work through subsets smallest first stopping at the first size that hits the target
      level work !size !top = do
        hit <- search work (masksOf size)
        if hit /= 0 || size == n
          then return (work, hit)
          else do
            work' <- reserve work size top
            let builds !t [] = return t
                builds !t (m : ms) = build work' t m >>= \t' -> builds t' ms
            top' <- builds top (masksOf size)
            level work' (size + 1) top'
  (work, hitMask) <-
    case [1 `unsafeShiftL` i | i <- [0 .. n - 1], indexPrimArray pool i == target] of
      (m : _) -> return (work0, m)
      []
        | n == 1 -> return (work0, 0)
        | otherwise -> level work0 2 n
  (value, mask) <-
    if hitMask /= 0
      then return (target, hitMask)
      else do
        -- Rank by distance from the target then by how many numbers are used so the simplest answer wins
        let lastMask = if n == 1 then full else full - 1
            masks !m !bd !bu !bv !bm
              | m > lastMask = return (bd, bv, bm)
              | otherwise = do
                  o <- readPrimArray (offs work) m
                  c <- readPrimArray (lens work) m
                  let used = popCount m
                      vals !i !d !u !v !mm
                        | i == c = masks (m + 1) d u v mm
                        | otherwise = do
                            x <- readPrimArray (arena work) (o + i)
                            let dx = abs (x - target)
                            if dx < d || (dx == d && used < u)
                              then vals (i + 1) dx used x m
                              else vals (i + 1) d u v mm
                  vals 0 bd bu bv bm
        (bd, bv, bm) <- masks 1 maxBound maxBound 0 0
        -- Fall back to the whole pool only when it gets strictly closer as it uses the most numbers
        if n > 1
          then do
            (wv, wd) <- wholeClosest work full target
            return (if wd < bd then (wv, full) else (bv, bm))
          else return (bv, bm)
  -- Render without outer brackets which matches stripping them from the bracketed form
  text <- render work mask value False
  return (value, text "")
