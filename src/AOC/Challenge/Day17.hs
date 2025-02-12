-- |
-- Module      : AOC.Challenge.Day17
-- License     : BSD3
--
-- Stability   : experimental
-- Portability : non-portable

module AOC.Challenge.Day17 (
    day17a
  , day17b
  , pascals
  , runDay17
  , ixPascal
  , pascalIx
  , encRun
  , pascalVecRunIx
  , vecRunIxPascal
  , pascalTable
  , oldNeighborWeights
  , vecRunNeighbs
  , vecRunNeighbs_
  , neighborWeights
  , finalWeight
  ) where

import           AOC.Common                    (factorial, integerFactorial, freqs, lookupFreq, foldMapParChunk, strictIterate)
import           AOC.Common.Point              (Point, parseAsciiSet)
import           AOC.Solver                    ((:~>)(..))
import           Control.Applicative.Backwards (Backwards(..))
import           Control.DeepSeq               (force, NFData)
import           Control.Lens                  (itraverseOf)
import           Control.Monad                 (when, guard)
import           Control.Monad.ST              (runST)
import           Control.Monad.State           (StateT(..))
import           Data.Bifunctor                (second)
import           Data.Coerce                   (coerce)
import           Data.Foldable                 (toList, for_)
import           Data.IntMap.Strict            (IntMap)
import           Data.IntSet                   (IntSet)
import           Data.List                     (scanl', sort, transpose)
import           Data.Map                      (Map)
import           Data.Maybe                    (fromMaybe, mapMaybe)
import           Data.Set                      (Set)
import           Data.Tuple.Strict             (T3(..), T2(..))
import           GHC.Generics                  (Generic)
import           Linear                        (V2(..))
import           Safe                          (lastMay)
import qualified Data.IntMap.Monoidal.Strict   as MIM
import qualified Data.IntMap.Strict            as IM
import qualified Data.IntSet                   as IS
import qualified Data.Map                      as M
import qualified Data.MemoCombinators          as Memo
import qualified Data.Set                      as S
import qualified Data.Vector                   as V
import qualified Data.Vector.Generic.Lens      as V
import qualified Data.Vector.Mutable           as MV
import qualified Data.Vector.Unboxed           as VU

pascals :: [[Int]]
pascals = repeat 1 : map (tail . scanl' (+) 0) pascals

pascalIx :: [Int] -> Int
pascalIx = sum . zipWith (\p x -> ((0:p) !! x)) (tail pascals)

pascalTable :: Int -> Int -> [[Int]]
pascalTable d mx = reverse
                 . transpose
                 . map (take mx)
                 . reverse
                 . take d
                 $ tail pascals

pascalVecRunIx :: VU.Vector Int -> Int
pascalVecRunIx = go 0 ((0:) <$> tail pascals). VU.toList
  where
    go !tot !cs = \case
      []   -> tot
      x:xs ->
        let (c,cs') = splitAt x cs
        in  go (tot + sum (map head c)) (tail <$> cs') xs

ixPascal
    :: Int      -- ^ dimension
    -> Int
    -> [Int]
ixPascal n x = go x (reverse p0) []
  where
    p0 = take n (tail pascals)
    go :: Int -> [[Int]] -> [Int] -> [Int]
    go _ []     r = r
    go y (p:ps) r = go (y - last qs) ps ((length qs - 1) : r)
      where
        qs = takeWhile (<= y) (0:p)

vecRunIxPascal
    :: Int      -- ^ dimension
    -> Int      -- ^ maximum
    -> Int      -- ^ number
    -> [Int]    -- ^ run
vecRunIxPascal n mx x = go x p0 []
  where
    p0 = reverse . transpose $ take mx <$> reverse (take n (tail pascals))
    go :: Int -> [[Int]] -> [Int] -> [Int]
    go q ps z = case chompPascal q ps of
      (j, _, [] ) -> (length (head ps) - j):j:z
      (j, r, ps') -> go r ps' (j:z)

chompPascal :: Int -> [[Int]] -> (Int, Int, [[Int]])
chompPascal = go 0
  where
    go !i q ~(xs:xss) = case xs of
      []            -> (i, q, xss)
      (x:ys)
        | q >= x    -> go (i+1) (q-x) (ys:map tail xss)
        | otherwise -> (i, q, xss)

encRun :: Int -> [Int] -> [Int]
encRun mx = take (mx + 1) . (++ repeat 0) . go 0 0
  where
    go :: Int -> Int -> [Int] -> [Int]
    go x !n = \case
      [] -> [n]
      y:ys
        | x == y    -> go x (n+1) ys
        | otherwise -> n : replicate (y-x-1) 0 ++ go y 1 ys

neighbs2d :: Int -> Int -> [Int]
neighbs2d n i =
    [ i + dx + n*dy
    | dx <- [0,-1,1]
    , dy <- [0,-1,1]
    ]

data NCount =
      NOne
    | NTwo
    | NThree
    | NMany
  deriving (Show, Eq, Ord, Generic)
instance NFData NCount

instance Semigroup NCount where
    NOne <> NOne = NTwo
    NOne <> NTwo = NThree
    NTwo <> NOne = NThree
    _    <> _    = NMany

data LiveCount = Dead !Ordering
               | LiveAlone
               | Live !Ordering
               | Overloaded
  deriving (Show, Eq, Ord, Generic)
instance NFData LiveCount

addOrdering :: a -> (Ordering -> a) -> Ordering -> Ordering -> a
addOrdering x f = go
  where
    go LT LT = f EQ
    go LT EQ = f GT
    go EQ LT = f GT
    go _  _  = x

toDead :: NCount -> LiveCount
toDead = \case
    NOne   -> Dead LT
    NTwo   -> Dead EQ
    NThree -> Dead GT
    NMany  -> Overloaded

instance Semigroup LiveCount where
    Dead n      <> Dead m      = addOrdering Overloaded Dead n m
    Dead n      <> LiveAlone   = Live n
    Dead n      <> Live  m     = addOrdering Overloaded Live n m
    LiveAlone   <> Dead m      = Live m
    LiveAlone   <> LiveAlone   = LiveAlone
    LiveAlone   <> Live m      = Live m
    Live n      <> Dead m      = addOrdering Overloaded Live n m
    Live n      <> LiveAlone   = Live n
    Live n      <> Live m      = addOrdering Overloaded Live n m
    _           <> _           = Overloaded

validLiveCount :: LiveCount -> Bool
validLiveCount = \case
    Dead GT -> True
    Live EQ -> True
    Live GT -> True
    _       -> False

stepper
    :: Int                          -- ^ how big the xy plane is
    -> (Int -> IntMap LiveCount)    -- ^ neighbor getter function (please cache)
    -> IntMap IntSet                -- ^ alive set: map of <x.y> to all zw+ points (pascal coords)
    -> IntMap IntSet
stepper nxy syms cs = fmap (IM.keysSet . IM.filter validLiveCount) . coerce $
    flip (foldMapParChunk chnk) (IM.toList cs) $ \(gIx, ds) ->
      let T2 updateHere updateThere = prebaked M.! ds
      in  MIM.MonoidalIntMap . IM.fromList $
            zip (neighbs2d nxy gIx) (updateHere : repeat updateThere)
  where
    -- the number of unique groups stays constant as you increase d
    uniqueGroups = S.fromList $ IM.elems cs
    prebaked :: Map IntSet (T2 (MIM.MonoidalIntMap LiveCount) (MIM.MonoidalIntMap LiveCount))
    prebaked = flip M.fromSet uniqueGroups $ \ds ->
      flip foldMap (IS.toList ds) $ \pIx ->
        let pNeighbs = syms pIx
        in  T2 (MIM.MonoidalIntMap $ IM.insertWith (<>) pIx LiveAlone pNeighbs)
               (MIM.MonoidalIntMap $ IM.insertWith (<>) pIx (Dead LT) pNeighbs)
    chnk = 100 `min` 5 `max` (IM.size cs `div` 10)

neighbs :: (Num a, Eq a) => a -> [a] -> [[a]]
neighbs mx = tail . traverse (\x -> if | x == mx   -> [x,x-1]
                                       | x == 0    -> [x,x+1,x+1]
                                       | otherwise -> [x,x-1,x+1]
                             )
{-# INLINE neighbs #-}

oldNeighborWeights
    :: Int            -- ^ dimension
    -> Int            -- ^ maximum
    -> V.Vector (IntMap NCount)
oldNeighborWeights d mx = runST $ do
    v <- MV.replicate n' IM.empty
    for_ [0 .. n-1] $ \x ->
      for_ (neighbs (mx-1) (ixPascal d x)) $ \i -> do
        let pIx = pascalIx (sort i)
        when (pIx < n') $
          MV.modify v (IM.insertWith (flip (<>)) x NOne) pIx
    V.freeze v
  where
    n  = pascals !! d !! mx
    n' = pascals !! d !! (mx-1)

-- -- used to test finalWeights
-- _duplicands
--     :: (Ord a, Num a, Enum a)
--     => a      -- ^ maximum
--     -> Int    -- ^ length (dimension)
--     -> Map [a] Int
-- _duplicands mx n = freqs . map symmer $ replicateM n [-mx .. mx]
--   where
--     symmer    = sort . map abs

finalWeight
    :: (Num a, Ord a)
    => Int              -- ^ dim
    -> [a]
    -> Integer
finalWeight n x = process . freqs $ x
  where
    process mp = (2 ^ numNonZeroes) * perms
      where
        numNonZeroes = n - lookupFreq 0 mp
        perms = integerFactorial (fromIntegral n)
          `div` product (integerFactorial . fromIntegral <$> mp)


-- | Reference implementation for 'vecRunNeighbs', which takes and returns
-- actual vec run neighbors
vecRunNeighbs_
    :: VU.Vector Int
    -> [(VU.Vector Int, NCount)]
vecRunNeighbs_ xs0 = mapMaybe pullSame $
    runStateT (forwards $ itraverseOf V.vectorTraverse go xs0) (T3 xs0 True 1)
  where
    pullSame (_, T3 _ True _) = Nothing
    pullSame (x, T3 _ _    p) = Just (x, toNCount p)
    -- we go backwards because it makes the final choice (1->0 transitions)
    -- simpler
    go :: Int -> Int -> Backwards (StateT (T3 (VU.Vector Int) Bool Int) []) Int
    go i x0 = Backwards $ StateT $ \(T3 xs allSame p) -> do
      let l0 = xs VU.!? (i-1)
          x  = xs VU.!   i
          r  = fromMaybe 0 $ xs VU.!? (i+1)
      case l0 of
        Nothing -> pure
          let res  = r + x
              p'   = p * factorial res * (2^r) `div` factorial x
          in  (res, T3 xs (allSame && x == x0) p')
        Just l  -> do
          xlContrib <- [0..(x+l)]
          xContrib  <- [max 0 (xlContrib-l) .. min x xlContrib]
          let lContrib   = xlContrib - xContrib
              res        = r + xlContrib
              xs'        = xs VU.// [(i, x-xContrib), (i-1, l-lContrib)]
              p'         = p * factorial res
                         `div` factorial r
                         `div` factorial xContrib
                         `div` factorial lContrib
          pure (res, T3 xs' (allSame && xContrib == x0) p')

genVecRunIxPascal
    :: [[Int]]  -- ^ pascal table
    -> Int      -- ^ number
    -> [Int]    -- ^ runs, but reverse order
genVecRunIxPascal p0 x = go x p0
  where
    go :: Int -> [[Int]] -> [Int]
    go q ps = case chompPascal q ps of
      (j, _, [] ) -> j : [length (head ps) - j]
      (j, r, ps') -> j : go r ps'

-- | Streaming/constant space enumerate all neighbor and multiplicities
vecRunNeighbs
    :: [[Int]]            -- ^ pascal table
    -> Int
    -> [(Int, NCount)]
vecRunNeighbs pasc0 = (\(x:xs) -> go pasc0 0 x True NOne 0 x xs)
                    . genVecRunIxPascal pasc0
  where
    -- we build these in reverse because we can both generate and encode
    -- pascal indices in reverse order in constant space/a streaming way
    -- and also because it makes the final choice for 1->0 transitions much
    -- simpler
    go  :: [[Int]]      -- ^ running pascal table
        -> Int          -- ^ running total
        -> Int          -- ^ original item in that position
        -> Bool         -- ^ currently all the same?
        -> NCount       -- ^ multiplicity
        -> Int          -- ^ item to the right
        -> Int          -- ^ current item
        -> [Int]        -- ^ leftover items (right to left)
        -> [(Int, NCount)]
    go pascs_ !tot x0 allSame !p r x = \case
      [] ->
        let res  = r + x
            p'   = p `mulNCount` toNCount @Integer
                    ( integerFactorial (fromIntegral res)
                    * (2^r)
                `div` integerFactorial (fromIntegral x)
                    )
            tot' = tot
        in  (tot', p') <$ guard (not (allSame && x == x0))
      l:ls -> do
        xlContrib <- [0..(x+l)]
        xContrib  <- [max 0 (xlContrib-l) .. min x xlContrib]
        let lContrib   = xlContrib - xContrib
            res        = r + xlContrib
            l'         = l - lContrib
            x'         = x - xContrib
            p'         = p `mulNCount` toNCount @Integer
                           ( integerFactorial (fromIntegral res)
                       `div` integerFactorial (fromIntegral r)
                       `div` integerFactorial (fromIntegral xContrib)
                       `div` integerFactorial (fromIntegral lContrib)
                           )
            pasc:pascs = pascs_
            tot'       = tot + sum (take res pasc)
            pascs'     = drop res <$> pascs
        go pascs' tot' l (allSame && xContrib == x0) p' x' l' ls

-- | Build up all the weights for quick reference comparison
neighborWeights
    :: Int            -- ^ dimension
    -> Int            -- ^ maximum
    -> V.Vector (IntMap NCount)
neighborWeights d mx =
      V.fromList
    . map (IM.fromListWith (<>) . vecRunNeighbs (pascalTable d mx))
    $ [0 .. n' - 1]
  where
    n' = pascals !! d !! (mx - 1)

toNCount :: (Num a, Eq a) => a -> NCount
toNCount = \case
    -- 0 -> error "0 ncount"
    1 -> NOne
    2 -> NTwo
    3 -> NThree
    _ -> NMany

mulNCount :: NCount -> NCount -> NCount
mulNCount = \case
    NOne   -> id
    NTwo   -> \case
      NOne -> NTwo
      _    -> NMany
    NThree -> \case
      NOne -> NThree
      _    -> NMany
    _      -> const NMany

runDay17
    :: Bool               -- ^ cache neighbors between runs
    -> Bool               -- ^ use an up-front vector cache (instead of dynamic memotable)
    -> Int                -- ^ number of steps
    -> Int                -- ^ dimensions
    -> Set Point          -- ^ points
    -> [IntMap IntSet]    -- ^ steps
runDay17 cache vcache mx d (S.toList -> x) =
          take (mx + 1)
        . strictIterate (force . stepper nxy wts)
        $ shifted
  where
    bounds  = maximum (concatMap toList x) + 1
    nxy     = bounds + mx*2
    shifted = IM.fromList $
        (\(V2 i j) -> (i + j * nxy, IS.singleton 0)) . (+ V2 mx mx) <$> x
    mx'
      | cache     = mx
      | otherwise = mx + length x - length x
    {-# INLINE mx' #-}
    wts
      | vcache    = ((fmap toDead <$> neighborWeights d mx') V.!)
      | otherwise = Memo.integral $ IM.fromListWith (<>)
                        . map (second toDead)
                        . vecRunNeighbs (pascalTable d mx')
{-# INLINE runDay17 #-}

day17
    :: Int
    -> Set Point :~> Integer
day17 d = MkSol
    { sParse = Just . parseAsciiSet (== '#')
    , sShow  = show
    , sSolve = fmap (sum . map (sum . map (finalWeight d . ixPascal d) . IS.toList) . toList)
             . lastMay
             . runDay17 False True 6 d
    }
{-# INLINE day17 #-}

day17a :: Set Point :~> Integer
day17a = day17 1

day17b :: Set Point :~> Integer
day17b = day17 2

-- d=5: 5760 / 16736; 274ms     -- with unboxed, 96ms, with pre-neighb: 35ms
-- d=6: 35936 / 95584; 1.5s     -- with unboxed, 309ms, with pre-neighb: 105ms
-- d=7: 178720 / 502240; 7.7s   -- with pre-neighbs: 356ms (no cache: 290ms)
-- d=8: 900288 / 2567360; 30s        -- with pre-neighbs: 1.2s (no cache: 690ms) (smallcache: 920ms)
-- d=9: 4333056 / 12764416; 2m20s   -- with pre-neighbs: 4.8s (no cache: 1.5s)
--                                                  no knownnat: 4.3s
-- d=10: 20251648 / 62771200; 8m58s    -- with unboxed, 1m6s, with pre-neighb: 21s (no cache: 2.56?)
--                                      no knownnat: 19s
--                                      smallcache: 12s
--                                      smart cache: 4.0s total
--                                      no-t=6 cache: 3.3s total
--                                      smarter t=6 cache: 3.0s total
--                                      unflatted step grid: 2.1s total
--                                      pure grid: 1.2s total
--                                      unique z-stacks: 120ms step
-- d=11: 93113856 / 309176832; 43m54s  -- with unboxed, 5m3s, with pre-neighb: 1m43s (no cache: 4.5s)
--                                      smallcache: 52s
--                                      8.8s v 7.7s
--                                      smarter t=6 cache: 5.8s
--                                      unique z-stacks: 172ms step
-- d=12: 424842240 / 1537981440 -- with unboxed, 22m10s, with pre-neighb: 8m30s (no cache: 7.4s)
--                                      smart cache: 21.5s total
--                                      21s vs 17s
--                                      no t=6 cache: 14s
--                                      unique z-stacks: 281ms step
-- d=13: 1932496896 / 7766482944 -- sqlite3 cache: 13.4s
--                                      smart cache: 1m10s total
--                                      new: 43s
--                                      unique z-stacks: 421ms step
-- d=14: 8778178560 / 39942504448 -- sqlite3 cache: 21.6s
--                                      new: 2m21s total
--                                      unique z-stacks: 647ms step
--                                      forward cache: (old) 4.8s all in memory
--                                          -> 1.2s with streaming neighbor gen
-- d=15: 39814275072 / 209681145856 -- sqlite3 cache: 32.5s, (including loading: 1m20s); smart cache: 4h35m
--    new method: total cache + run = 20m53s
--                                      unique z-stacks: 1.00s step
-- d=16: ? / 1125317394432 -- build sqlite cache + run = 62m44; run = 2m25s
--                                      unique z-stacks: 1.37s step
-- d=17: ? / 6178939535360 -- build sqlite cache + run = 24m
--                                      unique z-stacks: 2.08s step
-- d=18: ? / 34702568194048 -- build sqlite cache + run = 75m
--                                      unique z-stacks: 3.19s step
-- d=19: ? / 199077056872448 -- build sqlite cache + run = 220m
--                                      unique z-stacks: 18s step step
--                                      forward neighb: 11.4s
-- d=20: ? / 1163817241018368 -- forward neighb: 16.6s
--                                      forward cache: 6.4s
-- d=21: ? / 6913315519332352 -- forward neighb: 23.3s
--                                      forward cache: 9.2s
-- d=22: ? / 41598514437816320 -- forward neighb: 34.0s
--                                      forward cache: 12.8s
-- d=30: ? / 86683143717026864824320 -- forward neighb: 5m1s
