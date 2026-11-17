# Crypt of the Caffeinated King

A tiny terminal dungeon crawler, written entirely in AArch64 assembly for macOS on Apple Silicon. One file, no dependencies beyond the system C library.

```
clang -o crypt crypt.s
./crypt
```

## What it is

You descend three randomly generated 5×5 floors, each with its stairs in the far corner. Along the way: monsters, treasure, traps, fountains, shrines, campfires, a riddling owl, and a hooded merchant. At the bottom, on a throne of burlap sacks, sits the Caffeinated King. He has hoarded every bean north of the river. Take the last one.

## Features

- Pick a calling: Knight (+1 ARM, +4 HP), Barista (more and stronger
  potions) or Rogue (+1 ATK, crits, better at running away)
- ANSI-colored terminal UI with rounded box borders
- HP bars that shift green → yellow → red
- ASCII art for every room type and every monster
- Each move clears the screen — each room is its own scene
- Three floors; monsters and traps hit harder the deeper you go
- A boss fight: the King throws scalding espresso every third turn, heals
  once when hurt, and won't let you run
- XP and levels: every kill earns XP; each level gives +4 max HP and +1 ATK
- Combat with attack / heavy attack (double damage or a miss) / potion / run,
  plus a rolling action log
- Shrines, fountains, traps, treasure, a merchant with a mystery box
- Campfires: rest to full HP, if nothing finds you in your sleep
- An owl statue that asks riddles: answer right for loot, wrong and it bites
- Eleven base monsters (cursed barista, espresso golem, latte-art lich, the
  regional manager, etc.) modulated by
  procedural prefixes and suffixes — you'll fight things like
  *an artisanal moss-covered skeleton of the second pour*
- Procedurally generated weapons and armor (`[material] [type] of [theme]`),
  with stats driven by the name itself
- Monster traits: venomous (poisons you), evasive (dodges), armored (shrugs
  off damage), light-fingered (steals gold; kill it to get it back),
  regenerating, and managerial (the regional manager writes you up for -1 ATK
  per write-up, and you can't run from him)
- Coffee beans: chew one mid-fight for +3 ATK until the fight ends. Found as
  loot or bought from the merchant
- A dice goblin who'll roll 2d6 against you for 5, 10 or 20 gold
- A score at the end of every run (floors cleared, level, gold, +500 for the
  King); your best is kept in `~/.crypt-best`

## Procedural generation

Two systems generate variety on every run:

**Monsters.** Each base monster (`crypt.s: monsters`) is occasionally wrapped
with a prefix from `prefixes` (e.g. *blazing*, *tiny*, *ancient*, *decaf*)
and/or a suffix from `suffixes` (*of the depths*, *the over-extracted*). Each
modifier carries `hp, atk, gold` deltas so the name and the stats move
together. Articles are corrected for vowel sounds — *an ancient slime*, not
*a ancient slime*.

**Loot.** `_procgen_treasure` rolls a category, then composes a name:
- weapons: `[material] [type] [optional theme]` — e.g. *an obsidian cleaver of
  the brewmaster* — with the material driving the ATK bonus and the theme
  adding +1
- armor: same, but `armor_types` and ARM bonus
- potions: `[adjective] potion` — flavor only; healing is fixed
- a 15% chance to pull a hand-crafted special item from `specials`
  (the King's chipped mug, the brewmaster's apron, etc.) instead

To tune: edit the tables in the data section at the bottom of `crypt.s`. Each
table's length is hard-coded where it is rolled (`mov x0, 11` before
`bl _rnd` for the 11 prefixes, and so on), so update that count when you add a
row.

## Controls

```
w / a / s / d   move
i               info
q               quit
```

In combat: `a` attack, `h` heavy attack, `b` chew a bean, `p` drink potion, `r` run.

## Requirements

macOS on Apple Silicon (arm64) with the Xcode command line tools
(`xcode-select --install`). A terminal that supports ANSI colors and Unicode
box-drawing characters (Terminal.app, iTerm2, and so on).
