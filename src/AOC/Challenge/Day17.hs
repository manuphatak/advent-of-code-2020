{-# LANGUAGE OverloadedStrings #-}

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
  , pascalIx
  , pascalVecRunIx
  , ixPascal
  , neighborWeights
  , oldNeighborWeights
  , neighborPairs
  , loadNeighborWeights
  , vecRunNeighbs
  , vecRunNeighbs_
  , allVecRuns
  , NCount(..)
  ) where

-- import           Debug.Trace
import           AOC.Common                  ((!!!), factorial, freqs, lookupFreq, foldMapParChunk)
import           AOC.Common.Point            (Point, parseAsciiSet)
import           AOC.Solver                  ((:~>)(..))
import           Control.Concurrent          (forkIO, threadDelay)
import           Control.Concurrent.MVar     (takeMVar, putMVar, newEmptyMVar)
import           Control.Concurrent.QSem     (waitQSem, signalQSem, newQSem)
import           Control.DeepSeq             (force, NFData)
import           Control.Exception           (bracket_, evaluate)
import           Control.Monad               (unless, void, when)
import           Control.Monad.ST            (runST)
import           Control.Monad.State         (StateT(..))
import           Data.Bifunctor              (second)
import           Data.Coerce                 (coerce)
import           Data.Foldable               (toList, for_)
import           Data.IntMap.Strict          (IntMap)
import           Data.IntSet                 (IntSet)
import           Data.List                   (scanl', sort)
import           Data.List.NonEmpty          (NonEmpty(..))
import           Data.List.Split             (chunksOf)
import           Data.Maybe                  (fromMaybe, mapMaybe)
import           Data.Set                    (Set)
import           Data.Tuple.Strict           (T3(..))
import           GHC.Generics                (Generic)
import           Linear                      (V2(..))
import           System.IO.Unsafe            (unsafePerformIO)
import           Text.Printf                 (printf)
import qualified Data.IntMap.Monoidal.Strict as MIM
import qualified Data.IntMap.Strict          as IM
import qualified Data.IntSet                 as IS
import qualified Data.Set                    as S
import qualified Data.Vector                 as V
import qualified Data.Vector.Mutable         as MV
import qualified Data.Vector.Unboxed         as VU
import qualified Database.SQLite.Simple      as D

pascals :: [[Int]]
pascals = repeat 1 : map (tail . scanl' (+) 0) pascals

pascalIx :: [Int] -> Int
pascalIx = sum . zipWith (\p x -> ((0:p) !! x)) (tail pascals)

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
    (<>) = \case
      NOne -> \case
        NOne   -> NTwo
        NTwo   -> NThree
        _      -> NMany
      NTwo -> \case
        NOne   -> NThree
        _      -> NMany
      _        -> const NMany

data LiveCount = Dead !Ordering
               | LiveAlone
               | Live !Ordering
               | Overloaded
  deriving (Show, Eq, Ord, Generic)
instance NFData LiveCount

addOrdering :: a -> (Ordering -> a) -> Ordering -> Ordering -> a
addOrdering x f = \case
    LT -> \case
      LT -> f EQ
      EQ -> f GT
      GT -> x
    EQ -> \case
      LT -> f GT
      _  -> x
    GT -> const x

toDead :: NCount -> LiveCount
toDead = \case
    NOne   -> Dead LT
    NTwo   -> Dead EQ
    NThree -> Dead GT
    NMany  -> Overloaded

-- toLiveCount :: Int -> LiveCount
-- toLiveCount = \case
--     0 -> error "0 livecount"
--     1 -> Dead LT
--     2 -> Dead EQ
--     3 -> Dead GT
--     _ -> Overloaded

instance Semigroup LiveCount where
    Dead n     <> Dead m     = addOrdering Overloaded Dead n m
    Dead n     <> LiveAlone  = Live n
    Dead n     <> Live  m    = addOrdering Overloaded Live n m
    Dead _     <> Overloaded = Overloaded
    LiveAlone  <> Dead m     = Live m
    LiveAlone  <> LiveAlone  = LiveAlone
    LiveAlone  <> Live m     = Live m
    LiveAlone  <> Overloaded = Overloaded
    Live n     <> Dead m     = addOrdering Overloaded Live n m
    Live n     <> LiveAlone  = Live n
    Live n     <> Live m     = addOrdering Overloaded Live n m
    Live _     <> Overloaded = Overloaded
    Overloaded <> _          = Overloaded

validLiveCount :: LiveCount -> Bool
validLiveCount = \case
    Dead GT -> True
    Live EQ -> True
    Live GT -> True
    _       -> False

stepper
    :: Int      -- ^ how big the xy plane is
    -> V.Vector (IntMap LiveCount)        -- ^ symmetry map
    -> IntMap IntSet
    -> IntMap IntSet
stepper nxy syms cs = fmap (IM.keysSet . IM.filter validLiveCount) $
      coerce (foldMapParChunk @(MIM.MonoidalIntMap (MIM.MonoidalIntMap LiveCount)) chnk id)
      [ IM.fromList . ((gIx, updateHere):) $
          [ (gnIx, updateThere)
          | gnIx <- tail gNeighbs
          ]
      | (gIx, ds) <- IM.toList cs
      , pIx <- IS.toList ds
      , let pNeighbs = syms V.! pIx
            gNeighbs = neighbs2d nxy gIx
            updateHere  = IM.insertWith (<>) pIx LiveAlone pNeighbs
            updateThere = IM.insertWith (<>) pIx (Dead LT) pNeighbs
      ]
  where
    chnk :: Int
    chnk = min 1000 (max 10 (sum (IS.size <$> toList cs) `div` 100))

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
    v <- MV.replicate n IM.empty
    for_ [0 .. n-1] $ \x ->
      for_ (neighbs mx (ixPascal d x)) $ \i -> do
        MV.unsafeModify v (IM.insertWith (flip (<>)) x NOne) $
          pascalIx (sort i)
    V.freeze v
  where
    n = pascals !! d !! mx

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
    -> Int
finalWeight n x = process . freqs $ x
  where
    process mp = (2 ^ numNonZeroes) * perms
      where
        numNonZeroes = n - lookupFreq 0 mp
        perms = factorial n
          `div` product (factorial <$> mp)


data Chomper a = C { _cLeft2 :: !Bool        -- false if no exist, true if exist
                   , _cLeft  :: !(Maybe a)
                   , _cHere  :: !a
                   , _cOrig  :: !a
                   , _cRight :: !(NonEmpty a)
                   }

toChomper :: [a] -> Maybe (Chomper a)
toChomper (x:y:zs) = Just (C False Nothing x x (y:|zs))
toChomper _        = Nothing

-- reference implementaiton returning the actual runs. but
vecRunNeighbs_
    :: VU.Vector Int
    -> [(VU.Vector Int, NCount)]
vecRunNeighbs_ xs0 =
    mapMaybe pullSame $ runStateT (VU.imapM go xs0) (T3 xs0 True p0)
  where
    pullSame (_, (T3 _ True _)) = Nothing
    pullSame (x, (T3 _ _    c)) = Just (x, toNCount c)
    p0 = product . map factorial $ VU.toList xs0
    go :: Int -> Int -> StateT (T3 (VU.Vector Int) Bool Int) [] Int
    go i _
      | i == n - 1 = pure 0
      | otherwise  = StateT $ \(T3 xs b p) -> do
        let l  = fromMaybe 0 $ xs VU.!? (i-1)
            r  = xs VU.! (i+1)
            x  = xs VU.! i
            x0 = xs0 VU.! i
        (rContrib, xs', b', xContrib, p') <-
          if i == (n-2)
            then pure
                  ( r, xs, b && x == x0 && r == 0, x
                  , p `div` factorial x `div` factorial r
                  )
            else
              [ ( rContrib
                , xs VU.// [(i, x-xContrib),(i+1, r-rContrib)]
                , b && xContrib == x0
                , xContrib
                , p `div` factorial xContrib `div` factorial rContrib
                )
              | totContrib <- [0..(x+r)]
              , xContrib <- [max 0 (totContrib-r)..min x totContrib]
              , let rContrib = totContrib - xContrib
              ]
        let p''
              | i == 1    = p' * (2^l)
              | otherwise = p' `div` factorial l
            res = l + rContrib + xContrib
        pure (res, T3 xs' b' p'')
    n = VU.length xs0

-- | directly return pascal coords
vecRunNeighbs
    :: VU.Vector Int
    -> [(Int, NCount)]
vecRunNeighbs xs0 = mapMaybe pullSame $ go 0 True chomp0 p0 ((0:) <$> tail pascals)
  where
    xs0' = VU.toList xs0
    Just chomp0 = toChomper xs0'
    pullSame (True, _) = Nothing
    pullSame (_   , x) = Just x
    p0 = product . map factorial $ xs0'
    go !tot !allSame (C ll l x x0 rs) !p !cs = case rs of
        -- we can ignore all of these since we don't ever check neighbors
        -- of t>=mx.  so rContrib must be completely r for the last item,
        -- since the last item must be 0
        r:|[] -> do
          let p' = p `div` factorial x `div` factorial r
              p''
                | ll' && not ll = p' * (2^l')
                | otherwise     = p' `div` factorial l'
              res  = l' + x + r
              c    = take res cs
              tot' = tot + sum (map head c)
          pure (allSame && x == x0 && r == 0, (tot', toNCount p''))
        r:|(r':rs') -> do
          (xContrib, rContrib, p') <-
              [ ( xContrib
                , rContrib
                , p `div` factorial xContrib `div` factorial rContrib
                )
              | totContrib <- [0..(x+r)]
              , xContrib <- [max 0 (totContrib-r)..min x totContrib]
              , let rContrib = totContrib - xContrib
              ]
          let p''
                | ll' && not ll = p' * (2^l')
                | otherwise     = p' `div` factorial l'
              res = l' + xContrib + rContrib
              (c,cs') = splitAt res cs
              tot'    = tot + sum (map head c)
              chomp   = C ll' (Just (x - xContrib)) (r - rContrib) r (r':|rs')
          go tot' (allSame && xContrib == x0) chomp p'' (tail <$> cs')
      where
        (l', ll') = case l of
          Nothing -> (0, False)
          Just q  -> (q, True )

-- | All point runs for a given dim and max
allVecRuns
    :: Int    -- ^ dim
    -> Int    -- ^ max
    -> [VU.Vector Int]
allVecRuns d mx = go 0 d []
  where
    go i j rs
      | i < mx = do
          k <- [0..j]
          go (i + 1) (j - k) (k:rs)
      | otherwise = pure $ VU.fromListN (mx+1) (j:rs)

neighborPairs
    :: Int    -- ^ dimension
    -> Int    -- ^ maximum
    -> [(Int, (Int, NCount))]
neighborPairs d mx =
    [ (pG, (pX, w))
    | x <- allVecRuns d mx
    , let pX = pascalVecRunIx x
    , (pG, w) <- vecRunNeighbs x
    ]

neighborWeights
    :: Int            -- ^ dimension
    -> Int            -- ^ maximum
    -> V.Vector (IntMap NCount)
neighborWeights d mx = runST $ do
    v <- MV.replicate n' IM.empty
    for_ (neighborPairs d mx) $ \(pG, (pX, w')) ->
      MV.unsafeModify v (IM.insertWith (flip (<>)) pX w') pG
    V.freeze v
  where
    n' = pascals !! d !! (mx-1)

toNCount :: Int -> NCount
toNCount = \case
    0 -> error "0 ncount"
    1 -> NOne
    2 -> NTwo
    3 -> NThree
    _ -> NMany

day17
    :: Int
    -> Set Point :~> Int
day17 d = MkSol
    { sParse = Just . parseAsciiSet (== '#')
    , sShow  = show
    , sSolve = \(S.toList->x) ->
        let bounds  = maximum (concatMap toList x) + 1
            nxy     = bounds + 12
            shifted = IM.fromList $
                (\(V2 i j) -> (i + j * nxy, IS.singleton 0)) . (+ 6) <$> x
            -- wts = neighborWeights d 6
            wts = neighborWeights d (6 + length x - length x)   -- force no cache
            -- wts = loadNeighborWeights d (6 + length x - length x)
        -- in         Just . IS.size
        in  Just . sum
                 . map (sum . map (finalWeight d . ixPascal d) . IS.toList) . toList
                 . (!!! 6)
                 -- . map (\q -> traceShow (IS.size q) q)
                 -- . zipWith (\i q -> if i == 4 then traceShow (ixDouble d nxy <$> IS.toList q) q
                 --                              else q
                 --           ) [0..]
                 . iterate (force . stepper nxy (fmap toDead <$> wts))
                 $ shifted
    }
{-# INLINE day17 #-}

day17a :: Set Point :~> Int
day17a = day17 1

day17b :: Set Point :~> Int
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
--                                      unflatted grid: 2.1s total
-- d=11: 93113856 / 309176832; 43m54s  -- with unboxed, 5m3s, with pre-neighb: 1m43s (no cache: 4.5s)
--                                      smallcache: 52s
--                                      8.8s v 7.7s
--                                      smarter t=6 cache: 5.8s
-- d=12: 424842240 / 1537981440 -- with unboxed, 22m10s, with pre-neighb: 8m30s (no cache: 7.4s)
--                                      smart cache: 21.5s total
--                                      21s vs 17s
--                                      no t=6 cache: 14s
-- d=13: 1932496896 / 7766482944 -- sqlite3 cache: 13.4s
--                                      smart cache: 1m10s total
--                                      new: 43s
-- d=14: 8778178560 / 39942504448 -- sqlite3 cache: 21.6s
--                                      new: 2m21s total
-- d=15: 39814275072 / 209681145856 -- sqlite3 cache: 32.5s, (including loading: 1m20s); smart cache: 4h35m
--    new method: total cache + run = 20m53s
-- d=16: ? / 1125317394432 -- build sqlite cache + run = 62m44; run = 2m25s
-- d=17: ? / 6178939535360 -- build sqlite cache + run = 24m

cacheNeighborWeights
    :: D.Connection
    -> Int    -- ^ dimension
    -> Int    -- ^ maximum
    -> IO ()
cacheNeighborWeights conn d mx = do
    dbsem <- newQSem 1
    threadsem <- newQSem 5
    done <- newEmptyMVar
    forEnd_ (chunkUp <$> chunksOf 5_000_000 (neighborPairs d mx)) $ \isLast pmap -> do
      waitQSem threadsem
      forkIO $ do
        let chunky   = IM.size pmap
            bunky    = sum $ IM.size <$> pmap
            lastSeen = fromIntegral (maximum (fst . IM.findMax <$> pmap) + 1)
        _ <- evaluate $ force pmap
        bracket_ (waitQSem dbsem) (signalQSem dbsem) $ do
          printf "[%05.2f%%] Cacheing chunk of size %d/%d ...\n" (lastSeen / n * 100) chunky bunky
          D.withTransaction conn $ D.executeMany conn
            "INSERT INTO cache(dim,source,target,weight) VALUES (?,?,?,?) ON CONFLICT(dim,source,target) DO UPDATE SET weight = weight + ? WHERE weight < 4"
            [ (d, x, y, c, c)
            | (x, ys) <- IM.toList pmap
            , (y, z ) <- IM.toList ys
            , let c = fromCount z
            ]
        signalQSem threadsem
        when isLast $ putMVar done ()
    takeMVar done
    threadDelay 1000000
  where
    fromCount :: NCount -> Int
    fromCount = \case
      NOne   -> 1
      NTwo   -> 2
      NThree -> 3
      NMany  -> 4
    n :: Double
    n = fromIntegral (pascals !! d !! mx)
    chunkUp :: [(Int, (Int, NCount))] -> IntMap (IntMap NCount)
    chunkUp = IM.fromListWith (IM.unionWith (<>))
            . (map . second) (uncurry IM.singleton)

forEnd_
    :: Applicative m
    => [a]
    -> (Bool -> a -> m c)
    -> m ()
forEnd_ xs0 f = go xs0
  where
    go []     = pure ()
    go [x]    = void $ f True x
    go (x:xs) = f False x *> go xs

loadCache
    :: D.Connection
    -> Int      -- ^ dimensions
    -> Int      -- ^ max
    -> IO (V.Vector (IntMap NCount))
loadCache conn d mx =
    V.generateM n' $ \src -> do
      fmap toNCount . IM.fromList <$> D.queryNamed conn
        "SELECT target,weight FROM cache WHERE dim = :d AND source = :src"
        [ ":d" D.:= d, ":src" D.:= src ]
  where
    n' = pascals !! d !! (mx-1)

loadNeighborWeights
    :: Int    -- ^ dimensions
    -> Int    -- ^ maximum
    -> V.Vector (IntMap NCount)
loadNeighborWeights d mx = unsafePerformIO $ loadNeighborWeights_ d mx

loadNeighborWeights_
    :: Int    -- ^ dimensions
    -> Int    -- ^ maximum
    -> IO (V.Vector (IntMap NCount))
loadNeighborWeights_ d mx = D.withConnection "cache/day17.db" $ \conn -> do
    D.execute_ conn
      "CREATE TABLE IF NOT EXISTS cache (dim INT, source INT, target INT, weight INT, CONSTRAINT dst UNIQUE(dim, source, target))"
    exists <- not . null @[] @(D.Only Int) <$> D.queryNamed conn
      "SELECT dim FROM cache WHERE dim = :d LIMIT 1" [":d" D.:= d]
    unless exists $ do
      putStrLn "Building cache..."
      cacheNeighborWeights conn d mx
      putStrLn "Cache completed."
    loadCache conn d mx
      -- <* putStrLn "cache loaded"
