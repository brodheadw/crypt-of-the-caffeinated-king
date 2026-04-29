#!/usr/bin/env python3
"""
Crypt of the Caffeinated King
A tiny text-based dungeon crawler. Pure stdlib. Just run it.

    python3 crypt.py
"""

import os
import random
import sys
import time

# ---------- ansi ----------

USE_COLOR = sys.stdout.isatty() and os.environ.get("TERM", "") != "dumb"

class C:
    R    = "\033[0m"        if USE_COLOR else ""
    B    = "\033[1m"        if USE_COLOR else ""
    DIM  = "\033[2m"        if USE_COLOR else ""
    RED  = "\033[38;5;203m" if USE_COLOR else ""
    GRN  = "\033[38;5;114m" if USE_COLOR else ""
    YEL  = "\033[38;5;221m" if USE_COLOR else ""
    GLD  = "\033[38;5;215m" if USE_COLOR else ""
    BLU  = "\033[38;5;110m" if USE_COLOR else ""
    MAG  = "\033[38;5;176m" if USE_COLOR else ""
    CYN  = "\033[38;5;152m" if USE_COLOR else ""
    GRY  = "\033[38;5;245m" if USE_COLOR else ""
    DRK  = "\033[38;5;238m" if USE_COLOR else ""
    WHT  = "\033[38;5;253m" if USE_COLOR else ""
    BRN  = "\033[38;5;180m" if USE_COLOR else ""

def colorize(s, col):
    return f"{col}{s}{C.R}"

def hp_bar(cur, mx, width=14):
    pct = max(0.0, cur / mx) if mx else 0
    filled = int(round(pct * width))
    if pct > 0.66:   col = C.GRN
    elif pct > 0.33: col = C.YEL
    else:            col = C.RED
    return f"{col}{'█' * filled}{C.DRK}{'░' * (width - filled)}{C.R}"

def hr(ch="─", n=52, color=None):
    s = ch * n
    return colorize(s, color) if color else s

def divider():
    print(hr(color=C.DRK))

def clear():
    if USE_COLOR:
        sys.stdout.write("\033[H\033[2J\033[3J")
        sys.stdout.flush()
    else:
        os.system("cls" if os.name == "nt" else "clear")

def slow_print(s, delay=0.010, color=None):
    if color: sys.stdout.write(color)
    for ch in s:
        sys.stdout.write(ch); sys.stdout.flush()
        time.sleep(delay)
    if color: sys.stdout.write(C.R)
    sys.stdout.write("\n")

# ---------- ascii art ----------

ART = {
"banner": r"""
   ____                  _      ___   __    _   _            _
  / ___|_ __ _   _ _ __ | |_   / _ \ / _|  | |_| |__   ___  | | _____ _ __
 | |   | '__| | | | '_ \| __| | | | | |_   | __| '_ \ / _ \ | |/ / _ \ '__|
 | |___| |  | |_| | |_) | |_  | |_| |  _|  | |_| | | |  __/ |   <  __/ |
  \____|_|   \__, | .__/ \__|  \___/|_|     \__|_| |_|\___|_|_|\_\___|_|
             |___/|_|
              C a f f e i n a t e d   K i n g
""",

"start": r"""
            _____
           /     \
          |  . .  |     a stone arch yawns ahead.
           \_____/      mountain air at your back.
            |   |       the dark hums.
""",

"empty": r"""
            .   .   .
              .
            .       .
              dust
              ...
""",

"treasure": r"""
            _______
           /  $ $  \
          |  $   $  |
           \_______/
            ¯¯¯¯¯¯¯
""",

"trap": r"""
           \  |  |  /
            \ | | /
            --v v--
             SNAP!
""",

"shrine": r"""
              *
             / \
            /   \         humming.
           /  ☕  \
           \-----/
""",

"fountain": r"""
            ~   ~   ~
           (    o    )
            \_______/
              | |
""",

"merchant": r"""
            _______
           |  o_o  |     "buying or browsing?"
           |_______|
              | |
              | $ |
""",

"exit": r"""
           ___________
          |   _____   |
          |  |     |  |     light leaks
          |  |  >  |  |     from below.
          |  |_____|  |
          |___________|
""",

"sleepy_goblin": r"""
             ___
            / o o\          zzz...
           |   _   |
            \_____/
""",

"skeleton": r"""
            .-----.
           ( o   o )       *rattle*
            \  -  /
            /| | |\
""",

"giant_rat": r"""
              __
             ( • •)__
              \      \
               ¯¯¯¯¯¯
""",

"cursed_barista": r"""
            _________
           |#########|       "oat milk?"
           |   x x   |
           |    -    |
            \_______/
""",

"slime": r"""
            _________
           /         \         *gloop*
          | o       o |
           \    _    /
            ¯¯¯¯¯¯¯¯¯
""",

"shadow_imp": r"""
            #######
           # o   o #         *flicker*
           #   v   #
            #######
""",

"espresso_golem": r"""
           ===========
           ||  # #  ||        PSSSSST
           ||   v   ||
           ===========
           || ::::: ||
           ===========
""",
}

ART_COLORS = {
    "banner":         C.GLD,
    "start":          C.WHT,
    "empty":          C.DRK,
    "treasure":       C.GLD,
    "trap":           C.MAG,
    "shrine":         C.CYN,
    "fountain":       C.BLU,
    "merchant":       C.YEL,
    "exit":           C.GLD,
    "sleepy_goblin":  C.GRN,
    "skeleton":       C.WHT,
    "giant_rat":      C.BRN,
    "cursed_barista": C.RED,
    "slime":          C.GRN,
    "shadow_imp":     C.MAG,
    "espresso_golem": C.RED,
}

def show_art(key):
    art = ART.get(key)
    if not art:
        return
    col = ART_COLORS.get(key, C.WHT)
    print(colorize(art.strip("\n"), col))

# ---------- world ----------

GRID = 5

ROOM_KINDS = [
    ("empty",    10),
    ("monster",  30),
    ("treasure", 18),
    ("trap",     12),
    ("shrine",    8),
    ("merchant",  8),
    ("fountain", 14),
]

# (name, max_hp, atk, gold, flavor, art_key)
MONSTERS = [
    ("a sleepy goblin",            8,  2,  6,  "It's clutching a tiny mug. Steam rises from it.", "sleepy_goblin"),
    ("a moss-covered skeleton",   12,  3,  9,  "It rattles politely before attacking.",            "skeleton"),
    ("a giant rat",                6,  2,  4,  "Its eyes glint with caffeinated rage.",            "giant_rat"),
    ("a cursed barista",          16,  4, 18,  "'Oat milk?' it hisses. You answer wrong.",         "cursed_barista"),
    ("a slime",                   10,  2,  7,  "It absorbs your sarcasm and grows.",               "slime"),
    ("a shadow imp",               9,  4, 11,  "It flickers like a bad terminal.",                 "shadow_imp"),
    ("the King's espresso golem", 22,  5, 25,  "Pressurized. Loud. Furious.",                      "espresso_golem"),
]

TREASURES = [
    ("a small pouch of gold", "gold",     (8, 18)),
    ("a forgotten gem",       "gold",     (15, 30)),
    ("a healing potion",      "potion",   1),
    ("a rusty sword",         "weapon_up",1),
    ("a shiny shield",        "armor_up", 1),
    ("a stale croissant",     "potion",   1),
]

TRAPS = [
    ("Spikes shoot from the floor!",                            (3, 6)),
    ("A dart whistles past — mostly past.",                     (2, 5)),
    ("The floor crumbles. You catch yourself, but it stings.",  (4, 7)),
    ("A swarm of paper cuts. Yes, paper. Yes, cuts.",           (2, 4)),
]

SHRINE_LINES = [
    "A statue of a cat holding a mug. You leave an offering.",
    "Cold stone hums. Something inside you reorganizes.",
    "The shrine smells faintly of cinnamon.",
]

FOUNTAIN_LINES = [
    "A stone fountain bubbles in the corner. The water tastes like a perfect cortado.",
    "Steam rises from the fountain's icy water. You drink. You feel seen.",
    "A frog winks at you from inside the fountain basin. You drink anyway.",
    "A copper mug rests on the fountain rim. You fill it, drink, set it back.",
]

ROOM_LABELS = {
    "empty":    ("·",  C.GRY, "Empty Room"),
    "monster":  ("⚔",  C.RED, "Encounter"),
    "treasure": ("◆",  C.GLD, "Treasure"),
    "trap":     ("☠",  C.MAG, "Trap"),
    "shrine":   ("✦",  C.CYN, "Shrine"),
    "fountain": ("≈",  C.BLU, "Fountain"),
    "merchant": ("$",  C.YEL, "Merchant"),
    "exit":     (">",  C.GLD, "Exit"),
    "start":    ("@",  C.WHT, "Crypt Entrance"),
}

# ---------- state ----------

class Player:
    def __init__(self, name):
        self.name = name
        self.hp = 20; self.max_hp = 20
        self.atk = 4; self.armor = 0
        self.gold = 5; self.potions = 1
        self.x = 0; self.y = 0
        self.turns = 0

    def alive(self): return self.hp > 0

    def hurt(self, dmg):
        actual = max(1, dmg - self.armor)
        self.hp -= actual
        return actual

    def heal(self, amt):
        before = self.hp
        self.hp = min(self.max_hp, self.hp + amt)
        return self.hp - before


class Dungeon:
    def __init__(self):
        self.rooms = {}
        self.exit = (GRID - 1, GRID - 1)
        for x in range(GRID):
            for y in range(GRID):
                if (x, y) in [(0, 0), self.exit]:
                    self.rooms[(x, y)] = "empty"
                else:
                    kinds, weights = zip(*ROOM_KINDS)
                    self.rooms[(x, y)] = random.choices(kinds, weights=weights, k=1)[0]
        self.visited = {(0, 0)}

    def map_str(self, player):
        def cell(x, y):
            if (x, y) == (player.x, player.y):
                return colorize("@", C.B + C.GRN)
            if (x, y) == self.exit:
                if (x, y) in self.visited:
                    return colorize(">", C.B + C.GLD)
                return colorize("?", C.DRK)
            if (x, y) in self.visited:
                return colorize("·", C.GRY)
            return colorize("?", C.DRK)

        inner_w = GRID * 3 + 1
        top    = colorize("╭" + "─" * inner_w + "╮", C.DRK)
        bot    = colorize("╰" + "─" * inner_w + "╯", C.DRK)
        side   = colorize("│", C.DRK)

        rows = [top]
        for y in range(GRID - 1, -1, -1):
            row = side + " "
            for x in range(GRID):
                row += " " + cell(x, y) + " "
            row += side
            rows.append(row)
        rows.append(bot)
        legend = (f"   {colorize('@', C.B+C.GRN)} you   "
                  f"{colorize('·', C.GRY)} visited   "
                  f"{colorize('?', C.DRK)} unknown   "
                  f"{colorize('>', C.B+C.GLD)} exit")
        rows.append(legend)
        return "\n".join(rows)

# ---------- panels ----------

def status_panel(player):
    width = 52
    name = f" {player.name} "
    head = "╭─" + name + "─" * (width - len(name) - 3) + "╮"
    foot = "╰" + "─" * (width - 2) + "╯"

    bar = hp_bar(player.hp, player.max_hp, width=18)
    hp_txt = f"{player.hp}/{player.max_hp}"
    line1_raw = f"│ HP  {bar}  {C.WHT}{hp_txt:<7}{C.R}{C.GRY}Turn {player.turns}{C.R}"
    visible_len_1 = 4 + 18 + 2 + len(hp_txt) + 1 + len(f"Turn {player.turns}") + 2
    line1 = line1_raw + " " * max(0, width - visible_len_1 - 1) + "│"

    line2_raw = (f"│ {C.WHT}ATK{C.R} {player.atk:<3} "
                 f"{C.WHT}ARM{C.R} {player.armor:<3} "
                 f"{C.GLD}Gold{C.R} {player.gold:<5} "
                 f"{C.MAG}Potions{C.R} {player.potions:<3}")
    visible_len_2 = 1 + 1 + 3 + 1 + 4 + 3 + 1 + 4 + 5 + 1 + 7 + 1 + 3 + 1
    line2 = line2_raw + " " * max(0, width - visible_len_2 - 1) + "│"

    return "\n".join([
        colorize(head, C.DRK),
        line1,
        line2,
        colorize(foot, C.DRK),
    ])

def render(player, dungeon, art_key, room_label_key, flavor_lines):
    """Standard frame: clear, art, label, flavor, map, status."""
    clear()
    show_art(art_key)
    if room_label_key in ROOM_LABELS:
        icon, col, label = ROOM_LABELS[room_label_key]
        print()
        print(colorize(f"  {icon}  {label.upper()}", C.B + col))
        divider()
    for line in flavor_lines:
        print(line)
    print()
    print(dungeon.map_str(player))
    print()
    print(status_panel(player))

def render_combat(player, foe_hp, foe_max, monster_name, art_key, log):
    """Combat frame: clear, monster art, name, HP bars, log."""
    clear()
    show_art(art_key)
    print()
    print(colorize(f"  ⚔  {monster_name.upper()}", C.B + C.RED))
    divider()
    print(f"  {C.WHT}You{C.R}    {hp_bar(player.hp, player.max_hp, 14)}  "
          f"{C.WHT}{player.hp}/{player.max_hp}{C.R}")
    print(f"  {C.RED}Foe{C.R}    {hp_bar(foe_hp, foe_max, 14)}  "
          f"{C.WHT}{foe_hp}/{foe_max}{C.R}")
    print()
    for line in log[-4:]:
        print(line)
    if log:
        print()

# ---------- combat ----------

def combat(player, monster):
    name, max_hp, atk, gold, flavor, art_key = monster
    foe_hp = max_hp
    log = [colorize(f"  {flavor}", C.DIM + C.WHT)]

    while foe_hp > 0 and player.alive():
        render_combat(player, foe_hp, max_hp, name, art_key, log)
        action = input(f"  {C.DIM}[a]ttack  [p]otion  [r]un >{C.R} ").strip().lower()

        if action in ("a", ""):
            dmg = random.randint(player.atk - 1, player.atk + 2)
            foe_hp -= dmg
            log.append(colorize(f"  → You hit {name} for {dmg}.", C.GRN))
            if foe_hp <= 0:
                break
            taken = player.hurt(random.randint(atk - 1, atk + 1))
            log.append(colorize(f"  ← {name} hits you for {taken}.", C.RED))
        elif action == "p":
            if player.potions <= 0:
                log.append(colorize("  No potions. Pockets full of lint.", C.DIM))
                continue
            player.potions -= 1
            healed = player.heal(10)
            log.append(colorize(f"  ✚ You drink. +{healed} HP.", C.GRN))
            taken = player.hurt(random.randint(atk - 1, atk + 1))
            log.append(colorize(f"  ← {name} clips you for {taken} mid-sip.", C.RED))
        elif action == "r":
            if random.random() < 0.5:
                return "fled", 0
            taken = player.hurt(random.randint(atk - 1, atk + 1))
            log.append(colorize(f"  ← You stumble. {name} clips you for {taken}.", C.RED))
        else:
            log.append(colorize("  That's not a thing you can do.", C.DIM))

    if not player.alive():
        return "dead", 0
    return "won", gold

# ---------- room handlers ----------

def handle_room(player, dungeon):
    pos = (player.x, player.y)
    kind = dungeon.rooms[pos]

    if pos == dungeon.exit:
        return "exit"

    if kind == "empty":
        render(player, dungeon, "empty", "empty",
               [colorize("  The room is empty. Dust. A faint smell of beans.", C.DIM)])
        return "ok"

    if kind == "monster":
        m = random.choice(MONSTERS)
        result, gold = combat(player, m)
        if result == "dead":
            return "dead"
        dungeon.rooms[pos] = "empty"
        if result == "fled":
            render(player, dungeon, "empty", "empty",
                   [colorize("  You catch your breath. The room is quiet now.", C.DIM)])
        else:
            player.gold += gold
            render(player, dungeon, "empty", "empty", [
                colorize(f"  ✓ {m[0]} collapses.", C.GRN),
                colorize(f"  +{gold} gold.", C.GLD),
            ])
        return "ok"

    if kind == "treasure":
        name, kind2, val = random.choice(TREASURES)
        lines = [f"  You find {colorize(name, C.GLD)}."]
        if kind2 == "gold":
            g = random.randint(*val); player.gold += g
            lines.append(colorize(f"  +{g} gold.", C.GLD))
        elif kind2 == "potion":
            player.potions += 1
            lines.append(colorize("  +1 potion.", C.MAG))
        elif kind2 == "weapon_up":
            player.atk += 1
            lines.append(colorize("  ATK +1.", C.GRN))
        elif kind2 == "armor_up":
            player.armor += 1
            lines.append(colorize("  Armor +1.", C.GRN))
        dungeon.rooms[pos] = "empty"
        render(player, dungeon, "treasure", "treasure", lines)
        return "ok"

    if kind == "trap":
        msg, dmg_range = random.choice(TRAPS)
        taken = player.hurt(random.randint(*dmg_range))
        lines = [f"  {msg}", colorize(f"  -{taken} HP.", C.RED)]
        dungeon.rooms[pos] = "empty"
        render(player, dungeon, "trap", "trap", lines)
        if not player.alive():
            return "dead"
        return "ok"

    if kind == "shrine":
        line = random.choice(SHRINE_LINES)
        render(player, dungeon, "shrine", "shrine", [f"  {line}"])
        if player.gold >= 5:
            ans = input(f"\n  {C.DIM}Offer 5 gold? [y/N] >{C.R} ").strip().lower()
            if ans == "y":
                player.gold -= 5
                roll = random.random()
                if roll < 0.4:
                    player.max_hp += 3; player.hp += 3
                    msg = colorize("  Max HP +3.", C.GRN)
                elif roll < 0.7:
                    player.atk += 1
                    msg = colorize("  ATK +1.", C.GRN)
                else:
                    player.armor += 1
                    msg = colorize("  Armor +1.", C.GRN)
                dungeon.rooms[pos] = "empty"
                render(player, dungeon, "shrine", "shrine",
                       [f"  {line}", "", msg])
                return "ok"
        dungeon.rooms[pos] = "empty"
        return "ok"

    if kind == "fountain":
        line = random.choice(FOUNTAIN_LINES)
        healed = player.heal(8)
        dungeon.rooms[pos] = "empty"
        render(player, dungeon, "fountain", "fountain",
               [f"  {line}", colorize(f"  +{healed} HP.", C.GRN)])
        return "ok"

    if kind == "merchant":
        merchant_visit(player, dungeon)
        return "ok"

    return "ok"

def merchant_visit(player, dungeon):
    pos = (player.x, player.y)
    intro = [
        colorize("  A hooded figure unfolds a tiny table.", C.WHT),
        colorize("  'Buying or browsing?'", C.DIM),
    ]
    last_msg = []
    while True:
        render(player, dungeon, "merchant", "merchant", intro + [""] + last_msg)
        print()
        print(f"  {C.WHT}[1]{C.R} Potion           {C.GLD}5g{C.R}")
        print(f"  {C.WHT}[2]{C.R} Sharpen weapon  {C.GLD}12g{C.R}  (+1 ATK)")
        print(f"  {C.WHT}[3]{C.R} Reinforce armor {C.GLD}12g{C.R}  (+1 ARM)")
        print(f"  {C.WHT}[4]{C.R} Mystery box     {C.GLD}10g{C.R}")
        print(f"  {C.WHT}[5]{C.R} Leave")
        c = input(f"  {C.DIM}>{C.R} ").strip()
        if c == "1" and player.gold >= 5:
            player.gold -= 5; player.potions += 1
            last_msg = [colorize("  You pocket a potion.", C.MAG)]
        elif c == "2" and player.gold >= 12:
            player.gold -= 12; player.atk += 1
            last_msg = [colorize("  Sharper. Meaner.", C.GRN)]
        elif c == "3" and player.gold >= 12:
            player.gold -= 12; player.armor += 1
            last_msg = [colorize("  Click. Sturdier.", C.GRN)]
        elif c == "4" and player.gold >= 10:
            player.gold -= 10
            r = random.random()
            if r < 0.4:
                player.potions += 2
                last_msg = [colorize("  Two potions clatter out.", C.MAG)]
            elif r < 0.7:
                player.gold += 18
                last_msg = [colorize("  18 gold. Don't ask.", C.GLD)]
            elif r < 0.9:
                taken = player.hurt(4)
                last_msg = [colorize(f"  It bites. {taken} damage.", C.RED)]
            else:
                player.max_hp += 2; player.hp += 2
                last_msg = [colorize("  Max HP +2.", C.GRN)]
        elif c in ("5", ""):
            dungeon.rooms[pos] = "empty"
            render(player, dungeon, "empty", "empty",
                   [colorize("  The figure refolds the table and is gone.", C.DIM)])
            return
        else:
            last_msg = [colorize("  Not enough gold, or not a real choice.", C.DIM)]

# ---------- main loop ----------

def move(player, dx, dy):
    nx, ny = player.x + dx, player.y + dy
    if 0 <= nx < GRID and 0 <= ny < GRID:
        player.x, player.y = nx, ny
        player.turns += 1
        return True
    return False

def play():
    clear()
    print(colorize(ART["banner"].strip("\n"), C.GLD))
    print()
    name = input(colorize("  Adventurer's name: ", C.CYN)).strip() or "Beans"

    player = Player(name)
    dungeon = Dungeon()

    render(player, dungeon, "start", "start", [
        colorize(f"  Welcome, {name}.", C.WHT),
        colorize("  The King hoards every bean north of the river.", C.DIM),
        colorize("  Reach the > tile in the far corner. Don't die.", C.DIM),
    ])

    while player.alive():
        cmd = input(f"\n  {C.DIM}[w/a/s/d] move  [i] info  [q] quit >{C.R} ").strip().lower()
        if cmd == "q":
            print(colorize("\n  You walk back into the daylight. Story untold.", C.DIM))
            return
        if cmd == "i":
            print(colorize("  Find > in the far corner. @ is you. · visited. ? unknown.", C.DIM))
            continue
        moved = False
        if cmd == "w":   moved = move(player, 0, 1)
        elif cmd == "s": moved = move(player, 0, -1)
        elif cmd == "a": moved = move(player, -1, 0)
        elif cmd == "d": moved = move(player, 1, 0)
        else:
            print(colorize("  Try w/a/s/d.", C.DIM))
            continue
        if not moved:
            print(colorize("  A wall. Rude.", C.DIM))
            continue
        dungeon.visited.add((player.x, player.y))
        result = handle_room(player, dungeon)
        if result == "dead":
            print()
            divider()
            slow_print("  You crumple. The King sips, somewhere, smug.", color=C.RED)
            slow_print(f"  Final: turn {player.turns}, gold {player.gold}.", color=C.DIM)
            divider()
            return
        if result == "exit":
            clear()
            show_art("exit")
            print()
            divider()
            slow_print("  You reach the back of the crypt. A door.", color=C.GLD)
            slow_print("  Behind it: a kitchen. On the counter: the King's last bean.", color=C.GLD)
            slow_print("  You take it.", color=C.B + C.GLD)
            divider()
            print()
            print(colorize(f"  ★ VICTORY in {player.turns} turns "
                           f"with {player.gold} gold and {player.hp} HP.",
                           C.B + C.GRN))
            print()
            return

if __name__ == "__main__":
    try:
        play()
    except (KeyboardInterrupt, EOFError):
        print(colorize("\n  You step out of the crypt. The wind smells like rain.", C.DIM))
