Day 2
===

<!--
This section is generated and compiled by the build script at ./Build.hs from
the file `./reflections/day02.md`.  If you want to edit this, edit
that file instead!
-->

*[all][reflections]* / *[1][day01]* / *2* / *[3][day03]* / *[4][day04]* / *[5][day05]* / *[6][day06]* / *[7][day07]* / *[8][day08]* / *[9][day09]* / *[10][day10]* / *[11][day11]* / *[12][day12]* / *[13][day13]*

[reflections]: https://github.com/mstksg/advent-of-code-2020/blob/master/reflections.md
[day01]: https://github.com/mstksg/advent-of-code-2020/blob/master/reflections-out/day01.md
[day03]: https://github.com/mstksg/advent-of-code-2020/blob/master/reflections-out/day03.md
[day04]: https://github.com/mstksg/advent-of-code-2020/blob/master/reflections-out/day04.md
[day05]: https://github.com/mstksg/advent-of-code-2020/blob/master/reflections-out/day05.md
[day06]: https://github.com/mstksg/advent-of-code-2020/blob/master/reflections-out/day06.md
[day07]: https://github.com/mstksg/advent-of-code-2020/blob/master/reflections-out/day07.md
[day08]: https://github.com/mstksg/advent-of-code-2020/blob/master/reflections-out/day08.md
[day09]: https://github.com/mstksg/advent-of-code-2020/blob/master/reflections-out/day09.md
[day10]: https://github.com/mstksg/advent-of-code-2020/blob/master/reflections-out/day10.md
[day11]: https://github.com/mstksg/advent-of-code-2020/blob/master/reflections-out/day11.md
[day12]: https://github.com/mstksg/advent-of-code-2020/blob/master/reflections-out/day12.md
[day13]: https://github.com/mstksg/advent-of-code-2020/blob/master/reflections-out/day13.md

[Available as an RSS Feed][rss]

[rss]: http://feeds.feedburner.com/jle-advent-of-code-2020

*[Prompt][d02p]* / *[Code][d02g]* / *[Rendered][d02h]*

[d02p]: https://adventofcode.com/2020/day/2
[d02g]: https://github.com/mstksg/advent-of-code-2020/blob/master/src/AOC/Challenge/Day02.hs
[d02h]: https://mstksg.github.io/advent-of-code-2020/src/AOC.Challenge.Day02.html

Day 2, not too bad for Haskell either :)

There is some fun in parsing here:

```haskell
data Policy = P
    { pIx1  :: Int
    , pIx2  :: Int
    , pChar :: Char
    , pPass :: String
    }

parsePolicy :: String -> Maybe Policy
parsePolicy str = do
    [ixes,c:_,pwd] <- pure $ words str
    [ix1,ix2]      <- pure $ splitOn "-" ixes
    P <$> readMaybe ix1
      <*> readMaybe ix2
      <*> pure c
      <*> pure pwd
```

I used one of my more regular do-block tricks: if you pattern match in a
`Maybe` do-block, then failed pattern matches will turn the whole thing into a
`Nothing`.  So if any of those list literal pattern matches failed, the whole
block will return `Nothing`.

In any case, we just need to write a function to check if a given policy is
valid for either criteria:

```haskell
countTrue :: (a -> Bool) -> [a] -> Int
countTrue p = length . filter p

validate1 :: Policy -> Bool
validate1 P{..} = n >= pIx1 && n <= pIx2
  where
    n = countTrue (== pChar) pPass

validate2 :: Policy -> Bool
validate2 P{..} = n == 1
  where
    n = countTrue (== pChar) [pPass !! (pIx1 - 1), pPass !! (pIx2 - 1)]
```

And so parts 1 and 2 are just a count of how many policies are true :)

```haskell
part1 :: [Policy] -> Int
part1 = countTrue validate1

part2 :: [Policy] -> Int
part2 = countTrue validate2
```


*[Back to all reflections for 2020][reflections]*

## Day 2 Benchmarks

```
>> Day 02a
benchmarking...
time                 68.36 μs   (68.31 μs .. 68.39 μs)
                     1.000 R²   (1.000 R² .. 1.000 R²)
mean                 68.43 μs   (68.40 μs .. 68.45 μs)
std dev              93.46 ns   (76.39 ns .. 120.0 ns)

* parsing and formatting times excluded

>> Day 02b
benchmarking...
time                 79.58 μs   (77.84 μs .. 81.25 μs)
                     0.998 R²   (0.996 R² .. 0.999 R²)
mean                 80.76 μs   (79.83 μs .. 82.03 μs)
std dev              3.570 μs   (2.862 μs .. 5.070 μs)
variance introduced by outliers: 46% (moderately inflated)

* parsing and formatting times excluded
```

