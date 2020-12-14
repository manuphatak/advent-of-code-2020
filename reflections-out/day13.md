Day 13
===

<!--
This section is generated and compiled by the build script at ./Build.hs from
the file `./reflections/day13.md`.  If you want to edit this, edit
that file instead!
-->

*[all][reflections]* / *[1][day01]* / *[2][day02]* / *[3][day03]* / *[4][day04]* / *[5][day05]* / *[6][day06]* / *[7][day07]* / *[8][day08]* / *[9][day09]* / *[10][day10]* / *[11][day11]* / *[12][day12]* / *13* / *[14][day14]*

[reflections]: https://github.com/mstksg/advent-of-code-2020/blob/master/reflections.md
[day01]: https://github.com/mstksg/advent-of-code-2020/blob/master/reflections-out/day01.md
[day02]: https://github.com/mstksg/advent-of-code-2020/blob/master/reflections-out/day02.md
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
[day14]: https://github.com/mstksg/advent-of-code-2020/blob/master/reflections-out/day14.md

[Available as an RSS Feed][rss]

[rss]: http://feeds.feedburner.com/jle-advent-of-code-2020

*[Prompt][d13p]* / *[Code][d13g]* / *[Rendered][d13h]*

[d13p]: https://adventofcode.com/2020/day/13
[d13g]: https://github.com/mstksg/advent-of-code-2020/blob/master/src/AOC/Challenge/Day13.hs
[d13h]: https://mstksg.github.io/advent-of-code-2020/src/AOC.Challenge.Day13.html

Aw man, I feel like I would have leaderboarded today had I not been busy :'(
These type of number theory problems are the ones I usually do well on.

Oh well!  Silly internet points, right?

For part 1, you just need to minimize a function on each bus ID:

```haskell
part1 :: Int -> [Int] -> (Int, Int)
part1 t0 xs = minimumBy (comparing snd)
    [ (x, waitTime)
    | x <- xs
    , let waitTime = x - (t0 `mod` x)
    ]
```

Part 2 is where things get interesting!  Let's try to think of things
inductively: start with small lists, and see how we would "add one more".

Let's say we had `(offset, id)` pairs `(0,7)` and `(1,13)`, like in the
example.  This means that we want to find times where ``t `mod` 7 == 0`` and
``(t + 1) `mod` 13 == 0``.

We can sort of do a manual search by hand to get `14` as our lowest candidate.
But also, note that `14 + (7*13)n` for any integer `n` would preserve the offset
property.  `14`, `14 + 91`, `14 + 182`, etc.  So the family of all "valid"
numbers are `14 + (7*13)n`.

Next, what if we wanted to find the situation for pairs `(0,7)`, `(1,13)`, and
`(4,15)`?  Well, we already know that any solution that includes `(0,7)` and
`(1,13)` will be of the form `14 + (7*13)n`.  So now we just need to find the
*first* one of those that also matches `(4,15)`

```haskell
-- 'until' repeatedly applies a function until it finds a value that matches a
-- predicate
ghci> until (\t -> (t + 4) `mod` 15 == 0) (+ (7*13)) 14
1106
```

Ah hah, good ol' `1106`.  Well, `1106` isn't the only number that works.
We can see that `1106 + (7*13*15)n` for any integer n would *also* work, since
it preserves that mod property.

And so, we can repeat this process over and over again for each new number we
see.

1.  Keep track of the current "lowest match" (`14`) and the current "search
    step" (`7*13`).
2.  When you see a number, search that family until you find a new lowest match
    that includes the new number.
3.  Use that new number as the next lowest match, and multiply it to get the
    new search step.
4.  Rinse and repeat.

Overall, this works pretty well as a `foldl`, where we keep this `(lowest
match, search step)` pair as an accumulator, and update it as we see each new
value in our list.

```haskell
part2 :: [(Int, Int)] -> Int
part2 = fst . foldl' go (0, 1)
  where
    go (!base, !step) (offset, i) = (base', step * i)
      where
        base' = iterateFind (\n -> (n + offset) `mod` i == 0)
                            (+ step)
                            base
```


*[Back to all reflections for 2020][reflections]*

## Day 13 Benchmarks

```
>> Day 13a
benchmarking...
time                 249.4 ns   (231.5 ns .. 266.1 ns)
                     0.972 R²   (0.957 R² .. 0.984 R²)
mean                 247.9 ns   (237.1 ns .. 263.1 ns)
std dev              44.37 ns   (34.61 ns .. 64.02 ns)
variance introduced by outliers: 97% (severely inflated)

* parsing and formatting times excluded

>> Day 13b
benchmarking...
time                 4.491 μs   (4.481 μs .. 4.506 μs)
                     1.000 R²   (1.000 R² .. 1.000 R²)
mean                 4.488 μs   (4.483 μs .. 4.500 μs)
std dev              25.71 ns   (12.51 ns .. 44.60 ns)

* parsing and formatting times excluded
```
