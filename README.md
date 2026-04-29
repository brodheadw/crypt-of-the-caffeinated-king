# Crypt of the Caffeinated King

A tiny terminal dungeon crawler. Pure Python stdlib, no dependencies.

```
python3 crypt.py
```

## What it is

You wander a randomly generated 5×5 dungeon trying to reach the exit in the far corner. Along the way: monsters, treasure, traps, fountains, shrines, and a hooded merchant. The King has hoarded every bean north of the river. Get the last one.

## Features

- ANSI-colored terminal UI with rounded box borders
- HP bars that shift green → yellow → red
- ASCII art for every room type and every monster
- Each move clears the screen — each room is its own scene
- Combat with attack / potion / run, plus a rolling action log
- Shrines, fountains, traps, treasure, a merchant with a mystery box
- Seven monsters including a cursed barista and an espresso golem

## Controls

```
w / a / s / d   move
i               info
q               quit
```

In combat: `a` attack, `p` drink potion, `r` run.

## Requirements

Python 3.7+. A terminal that supports ANSI colors and Unicode box-drawing characters (basically anything modern: iTerm2, Terminal.app, modern Linux terminals, Windows Terminal).
