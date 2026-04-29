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
- Seven base monsters (cursed barista, espresso golem, etc.) modulated by
  procedural prefixes and suffixes — you'll fight things like
  *the artisanal moss-covered skeleton of the second pour*
- Procedurally generated weapons and armor (`[material] [type] of [theme]`),
  with stats driven by the name itself

## Procedural generation

Two systems generate variety on every run:

**Monsters.** Each base monster (`crypt.py: MONSTERS`) is occasionally wrapped
with a prefix from `MONSTER_PREFIXES` (e.g. *blazing*, *tiny*, *ancient*,
*decaf*) and/or a suffix from `MONSTER_SUFFIXES` (*of the depths*,
*the over-extracted*). Each modifier carries `(hp, atk, gold)` deltas so the
name and the stats move together. Articles are corrected for vowel sounds —
*an ancient slime*, not *a ancient slime*.

**Loot.** `procgen_treasure()` rolls a category, then composes a name:
- weapons: `[material] [type] [optional theme]` — e.g. *an obsidian cleaver of
  the brewmaster* — with the material driving the ATK bonus and the theme
  adding +1
- armor: same, but `ARMOR_TYPES` and ARM bonus
- potions: `[adjective] potion` — flavor only; healing is fixed
- a 15% chance to pull a hand-crafted special item from `SPECIAL_TREASURES`
  (the King's chipped mug, the brewmaster's apron, etc.) instead

To tune: edit the lists at the top of the procgen section. Add a new prefix
like `("unionized", 2, 1, 4)` and it shows up in the rotation immediately.

## Controls

```
w / a / s / d   move
i               info
q               quit
```

In combat: `a` attack, `p` drink potion, `r` run.

## Requirements

Python 3.7+. A terminal that supports ANSI colors and Unicode box-drawing characters (basically anything modern: iTerm2, Terminal.app, modern Linux terminals, Windows Terminal).
