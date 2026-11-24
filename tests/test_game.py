"""Run with python3 tests/test_game.py on an Apple Silicon Mac."""

import os
from pathlib import Path
import re
import subprocess
import tempfile
import unittest


SOURCE = Path(__file__).resolve().parents[1] / "crypt.s"


class TerminalRuns(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        build = tempfile.TemporaryDirectory()
        cls.addClassCleanup(build.cleanup)
        cls.binary = Path(build.name) / "crypt"
        subprocess.run(["clang", "-o", cls.binary, SOURCE.name], cwd=SOURCE.parent, check=True)

    def launch(self, args, lines=()):
        with tempfile.TemporaryDirectory() as home:
            return subprocess.run(
                [self.binary, *args],
                input="".join(line + "\n" for line in lines),
                capture_output=True,
                text=True,
                env={**os.environ, "HOME": home, "TERM": "dumb"},
                timeout=5,
            )

    def play(self, seed, *commands):
        # Empty name and calling select Beans the Knight.
        result = self.launch(["--seed", str(seed)], ["", "", *commands])
        self.assertEqual(result.returncode, 0, result.stderr)
        return result.stdout

    def test_replay_and_seed_bounds(self):
        for seed in (0, 4294967295):
            with self.subTest(seed=seed):
                run = self.play(seed, "w", "")
                self.assertIn("Beans the Knight", run)
                self.assertEqual(run, self.play(seed, "w", ""))
        for bad in ("", "-1", "2oops", "4294967296"):
            with self.subTest(bad=bad):
                self.assertNotEqual(self.launch(["--seed", bad]).returncode, 0)

    def test_parry_and_riposte_survive_invalid_commands(self):
        # Seed 1 opens with a charged foe one tile north.
        clean = self.play(1, "w", "g", "h")
        retried = self.play(1, "w", "oops", "g", "oops", "h")
        combat_hp = r"  You\s+[█░]+\s+(\d+)/[^\n]+\n  Foe\s+[█░]+\s+(\d+)/"
        before, parried, countered = re.findall(combat_hp, clean)
        self.assertEqual(before, parried)
        self.assertLess(int(countered[1]), int(parried[1]))
        self.assertIn("Riposte!", clean)
        self.assertEqual(
            re.findall(combat_hp, retried),
            [before, before, parried, parried, countered],
        )
        self.assertIn("Riposte!", retried)

    def test_postponed_rescue_pays_out_once(self):
        # Seed 2 has Nell three steps north, with a cleared room to her south.
        run = self.play(2, "w", "w", "w", "l", "s", "w", "2", "s", "w", "q")
        self.assertEqual(run.count("[1/2/l] >"), 2)
        self.assertEqual(run.count("Nell is free."), 1)
        before, after = run.split("Nell is free.")
        hp = r"│ HP\s+[█░]+\s+(\d+)/"
        arm = r"│ ATK\s+\d+\s+ARM\s+(\d+)"
        for pattern, delta in ((hp, -4), (arm, 1)):
            previous = int(re.findall(pattern, before)[-1])
            self.assertEqual(
                [int(n) for n in re.findall(pattern, after)], [previous + delta] * 3
            )

    def test_next_floor_layout_survives_different_choices(self):
        # Seed 5 has a shrine north of the entrance. An offering consumes RNG.
        onward = ["d", "w", "w", "d", "d", "d", "w"]
        direct = self.play(5, "w", "n", *onward, "", "q")
        backtrack = self.play(5, "w", "y", *onward, "b", "s", "w", "", "q")
        self.assertEqual(backtrack.count("[enter] descend"), 2)
        for run in (direct, backtrack):
            self.assertIn("Floor 2/3", run)

        def last_map(run):
            rows = re.findall(r"^│  (\S  \S  \S  \S  \S) │", run, re.MULTILINE)
            self.assertGreaterEqual(len(rows), 5)
            return rows[-5:]

        self.assertEqual(last_map(direct), last_map(backtrack))

    def test_unused_fountain_and_field_potion(self):
        # On seed 72 the fountain is north and a trap is east.
        at_trap = ("w", "s", "d")
        fountain = self.play(72, *at_trap, "a", "w", "s", "w", "q")
        self.assertEqual(fountain.count("≈  FOUNTAIN"), 2)
        self.assertIn("You can come back for a drink.", fountain)
        self.assertIn("+4 HP.", fountain)
        self.assertEqual(re.findall(r"│ HP\s+[█░]+\s+(\d+)/", fountain)[-1], "24")

        potion = self.play(72, "p", *at_trap, "p", "q")
        self.assertIn("The cork stays in.", potion)
        self.assertIn("Health 24/24, potions left 0.", potion)


if __name__ == "__main__":
    unittest.main()
