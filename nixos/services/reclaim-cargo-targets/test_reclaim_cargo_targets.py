"""Unit tests for reclaim_cargo_targets. Run: python3 -m unittest -v (from this dir)."""
import fcntl
import os
import tempfile
import time
import unittest
from pathlib import Path
from unittest import mock

import reclaim_cargo_targets as rct

IS_ROOT = os.geteuid() == 0


def mk_target(d: Path, age_h: float, size=1 << 20, profile="debug"):
    """A minimal cargo target dir: tag, profile with .fingerprint, lock, one blob."""
    (d / profile / ".fingerprint" / "x-1").mkdir(parents=True)
    (d / profile / "deps").mkdir()
    (d / "CACHEDIR.TAG").touch()
    (d / profile / ".cargo-lock").touch()
    (d / profile / ".fingerprint" / "x-1" / "lib-x").write_text("x")
    with open(d / profile / "deps" / "blob", "wb") as f:
        f.write(b"\0" * size)
    set_age(d, age_h)


def set_age(d: Path, age_h: float):
    t = time.time() - age_h * 3600
    for p in [d, *d.rglob("*")]:
        os.utime(p, (t, t))


class Tmp(unittest.TestCase):
    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory(prefix="rct.")
        self.root = Path(self._tmp.name)
        self.log = []

    def tearDown(self):
        for p in self.root.rglob("*"):
            if p.is_dir():
                p.chmod(0o755)
        self._tmp.cleanup()


class FoldNested(unittest.TestCase):
    def test_dash_sibling_between_parent_and_child_does_not_break_fold(self):
        got = rct.fold_nested(["/t/comp530/wasm32", "/t/comp530-mut", "/t/comp530"])
        self.assertEqual(got, ["/t/comp530", "/t/comp530-mut"])

    def test_prefix_sibling_is_not_a_child(self):
        self.assertEqual(rct.fold_nested(["/t/fx528b", "/t/fx528"]), ["/t/fx528", "/t/fx528b"])


class Discover(Tmp):
    def test_finds_target_and_ignores_tag_without_fingerprint(self):
        mk_target(self.root / "real", 400)
        (self.root / "restic").mkdir()
        (self.root / "restic" / "CACHEDIR.TAG").touch()
        self.assertEqual(rct.discover([str(self.root)], 8), [str(self.root / "real")])

    def test_cross_compile_triple_dir_folds_into_parent(self):
        mk_target(self.root / "t", 400)
        mk_target(self.root / "t" / "wasm32-unknown-unknown", 400)
        self.assertEqual(rct.discover([str(self.root)], 8), [str(self.root / "t")])

    @unittest.skipIf(IS_ROOT, "root can read anything")
    def test_unreadable_dir_in_one_root_does_not_end_the_scan(self):
        r1, r2 = self.root / "r1", self.root / "r2"
        (r1 / "private" / "inner").mkdir(parents=True)
        (r1 / "private").chmod(0)
        mk_target(r2 / "second", 400)
        self.assertEqual(rct.discover([str(r1), str(r2)], 8), [str(r2 / "second")])

    def test_maxdepth_counts_from_root_like_find(self):
        mk_target(self.root / "a" / "b" / "target", 400)  # CACHEDIR.TAG at depth 4
        self.assertEqual(rct.discover([str(self.root)], 3), [])
        self.assertEqual(rct.discover([str(self.root)], 4), [str(self.root / "a" / "b" / "target")])

    def test_missing_root_is_skipped(self):
        self.assertEqual(rct.discover([str(self.root / "nope")], 8), [])


class Clock(Tmp):
    def test_age_comes_from_newest_fingerprint_entry(self):
        mk_target(self.root / "t", 400)
        self.assertIn(rct.last_build_age_h(str(self.root / "t")), (399, 400))

    def test_touching_a_fingerprint_file_resets_age(self):
        mk_target(self.root / "t", 400)
        (self.root / "t" / "debug" / ".fingerprint" / "x-1" / "lib-x").touch()
        self.assertEqual(rct.last_build_age_h(str(self.root / "t")), 0)

    def test_fingerprint_directory_mtime_counts_too(self):
        mk_target(self.root / "t", 400)
        os.utime(self.root / "t" / "debug" / ".fingerprint" / "x-1")
        self.assertEqual(rct.last_build_age_h(str(self.root / "t")), 0)

    def test_deps_mtime_is_ignored(self):
        mk_target(self.root / "t", 400)
        (self.root / "t" / "debug" / "deps" / "blob").touch()
        self.assertIn(rct.last_build_age_h(str(self.root / "t")), (399, 400))

    def test_falls_back_to_dir_mtime_without_fingerprint(self):
        (self.root / "bare").mkdir()
        set_age(self.root / "bare", 50)
        self.assertIn(rct.last_build_age_h(str(self.root / "bare")), (49, 50))


class Size(Tmp):
    def test_counts_allocated_blocks_and_hardlinks_once(self):
        mk_target(self.root / "t", 1)
        blob = self.root / "t" / "debug" / "deps" / "blob"
        os.link(blob, blob.with_name("blob2"))
        n = rct.dir_bytes(str(self.root / "t"))
        self.assertGreaterEqual(n, 1 << 20)
        self.assertLess(n, (1 << 20) + 64 * 1024)

    def test_missing_dir_is_zero(self):
        self.assertEqual(rct.dir_bytes(str(self.root / "nope")), 0)


class Live(unittest.TestCase):
    def test_snapshot_is_reused_within_ttl_and_refreshed_after(self):
        calls, now = [], [0.0]
        lt = rct.LiveTable(ttl=30, clock=lambda: now[0], scan=lambda: calls.append(1) or ["/x/a"])
        for t in (0, 10, 29):
            now[0] = t
            lt.holder("/x")
        self.assertEqual(len(calls), 1)
        now[0] = 31
        lt.holder("/x")
        self.assertEqual(len(calls), 2)

    def test_holder_matches_root_and_descendants_not_prefix_siblings(self):
        lt = rct.LiveTable(ttl=30, clock=lambda: 0, scan=lambda: ["/x/fx542/debug/foo", "/x/fx542b", "socket:[1]"])
        self.assertEqual(lt.holder("/x/fx542"), "/x/fx542/debug/foo")
        self.assertEqual(lt.holder("/x/fx542b"), "/x/fx542b")
        self.assertIsNone(lt.holder("/x/fx54"))
        self.assertIsNone(lt.holder("/x/fx5420"))

    def test_real_proc_scan_sees_own_cwd(self):
        with tempfile.TemporaryDirectory(prefix="rct.") as d:
            here = os.getcwd()
            os.chdir(d)
            try:
                hit = rct.LiveTable(ttl=0).holder(os.path.realpath(d))
            finally:
                os.chdir(here)
            self.assertIsNotNone(hit)


class Lock(Tmp):
    def test_flocked_cargo_lock_is_held(self):
        mk_target(self.root / "t", 400)
        lock = self.root / "t" / "debug" / ".cargo-lock"
        with open(lock) as f:
            fcntl.flock(f, fcntl.LOCK_EX | fcntl.LOCK_NB)
            self.assertTrue(rct.lock_held(str(lock)))
        self.assertFalse(rct.lock_held(str(lock)))

    @unittest.skipIf(IS_ROOT, "root can open anything")
    def test_unopenable_lock_counts_as_held(self):
        mk_target(self.root / "t", 400)
        lock = self.root / "t" / "debug" / ".cargo-lock"
        lock.chmod(0)
        self.assertTrue(rct.lock_held(str(lock)))

    def test_locks_found_at_profile_and_triple_depth(self):
        mk_target(self.root / "t", 400)
        mk_target(self.root / "t" / "x86_64-unknown-none", 400)
        got = sorted(rct.cargo_locks(str(self.root / "t")))
        self.assertEqual(got, sorted([
            str(self.root / "t" / "debug" / ".cargo-lock"),
            str(self.root / "t" / "x86_64-unknown-none" / "debug" / ".cargo-lock"),
        ]))


class Consider(Tmp):
    def run_(self, apply=False, holder=None):
        live = rct.LiveTable(ttl=30, clock=lambda: 0, scan=lambda: [holder] if holder else [])
        return rct.Run(apply=apply, live=live, log=self.log.append)

    def test_re_reads_clock_and_keeps_a_dir_touched_since_inventory(self):
        mk_target(self.root / "t", 400)
        (self.root / "t" / "debug" / ".fingerprint" / "x-1" / "lib-x").touch()
        ok = rct.consider(str(self.root / "t"), 5, need_h=6, why="over", run=self.run_())
        self.assertFalse(ok)
        self.assertRegex(self.log[0], r"^keep touched 0h ago  .*/t$")

    def test_dry_run_reports_would_reclaim(self):
        mk_target(self.root / "t", 400)
        ok = rct.consider(str(self.root / "t"), 5, need_h=6, why="age ", run=self.run_())
        self.assertTrue(ok)
        self.assertRegex(self.log[0], r"^age  (399|400)h idle  .*/t$")
        self.assertEqual(self.log[1], "  WOULD reclaim 5B")
        self.assertTrue((self.root / "t").exists())

    def test_process_inside_blocks(self):
        mk_target(self.root / "t", 400)
        ok = rct.consider(str(self.root / "t"), 5, need_h=6, why="over", run=self.run_(holder=str(self.root / "t")))
        self.assertFalse(ok)
        self.assertRegex(self.log[1], r"^  in use: a process holds .*/t$")

    def test_held_lock_blocks(self):
        mk_target(self.root / "t", 400)
        lock = self.root / "t" / "debug" / ".cargo-lock"
        with open(lock) as f:
            fcntl.flock(f, fcntl.LOCK_EX | fcntl.LOCK_NB)
            ok = rct.consider(str(self.root / "t"), 5, need_h=6, why="over", run=self.run_())
        self.assertFalse(ok)
        self.assertRegex(self.log[1], r"^  in use: .*/\.cargo-lock is held$")


class Reclaim(Tmp):
    def test_apply_removes_dir_and_leaves_no_residue(self):
        mk_target(self.root / "gone", 400)
        self.assertTrue(rct.reclaim(str(self.root / "gone"), 1 << 20, apply=True, log=self.log.append))
        self.assertEqual(sorted(p.name for p in self.root.iterdir()), [])
        self.assertEqual(self.log, ["  reclaimed 1.0MB"])

    def test_rename_failure_is_skipped_not_fatal(self):
        self.assertFalse(rct.reclaim(str(self.root / "nope"), 1, apply=True, log=self.log.append))
        self.assertEqual(self.log, ["  rename failed, skipping"])


class Human(unittest.TestCase):
    def test_matches_numfmt_iec_rounding(self):
        cases = [(0, "0B"), (5, "5B"), (1153433, "1.1MB"), (1 << 30, "1.0GB"),
                 (630194176, "601MB"), (14 * (1 << 30), "14GB"), (60 * (1 << 30), "60GB")]
        for n, want in cases:
            with self.subTest(n=n):
                self.assertEqual(rct.human(n), want)


class Main(Tmp):
    def main(self, *args, **env):
        with mock.patch.dict(os.environ, {"NO_SYSLOG": "1", **env}):
            rct.main(["--tier", "0", "--root", str(self.root), *args], log=self.log.append)
        return "\n".join(self.log)

    def test_age_pass_takes_only_dirs_past_the_tier_threshold(self):
        mk_target(self.root / "old", 400)
        mk_target(self.root / "mid", 100)
        mk_target(self.root / "new", 1)
        out = self.main("--budget", "1000")
        self.assertRegex(out, r"age  (399|400)h idle  .*/old\n  WOULD reclaim")
        self.assertNotIn("/mid", out)
        self.assertNotIn("/new", out)
        self.assertRegex(out, r"total: 1\.[01]MB \(dry run - re-run with --apply\)")

    def test_budget_pass_is_oldest_first_and_respects_the_idle_floor(self):
        mk_target(self.root / "a", 100)
        mk_target(self.root / "b", 50)
        mk_target(self.root / "c", 1)
        out = self.main("--budget", "0", MIN_IDLE_H="6")
        self.assertRegex(out, r"still .* over a 0B budget\nover (99|100)h idle  .*/a\n  WOULD.*\nover (49|50)h idle  .*/b\n")
        self.assertNotIn("/c", out)

    def test_apply_deletes_and_logs_total_without_dry_run_hint(self):
        mk_target(self.root / "gone", 400)
        mk_target(self.root / "kept", 1)
        out = self.main("--budget", "1000", "--apply")
        self.assertFalse((self.root / "gone").exists())
        self.assertTrue((self.root / "kept").is_dir())
        self.assertRegex(out, r"total: 1\.[01]MB$")


if __name__ == "__main__":
    unittest.main()
