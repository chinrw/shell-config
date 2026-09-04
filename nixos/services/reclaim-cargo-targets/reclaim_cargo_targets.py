#!/usr/bin/env python3
"""Reclaim idle Rust build directories from scratch locations.

Two rules, in this order: age (idle past the disk tier's threshold), then
budget (still over BUDGET_GB: oldest first until under). Age runs first so a
quiet week never evicts a dir someone still wants; budget exists because age
alone cannot bound a day of heavy churn.

Guards are re-read right before each delete: no dir with a live build or a
process inside it, none touched within MIN_IDLE_H. A wrong call costs one
cold rebuild.

Dry-run by default; --apply deletes. Env: BUDGET_GB, MIN_IDLE_H, MAXDEPTH,
LIVE_TTL, NO_SYSLOG.
"""
from __future__ import annotations

import argparse
import bisect
import fcntl
import os
import stat
import subprocess
import sys
import syslog
import time
from collections.abc import Callable, Iterable, Iterator
from dataclasses import dataclass

# Heavy interiors that never contain a marker we look for.
PRUNE = frozenset({"deps", "incremental", ".fingerprint", ".git", "node_modules", ".venv"})
TIER_IDLE_DAYS = {0: 14, 1: 7, 2: 2}
UNITS = ("B", "KB", "MB", "GB", "TB", "PB")


def default_roots() -> list[str]:
    # Top-level checkouts are deliberately absent: those rebuilds a human waits on.
    home = os.environ.get("HOME") or os.path.expanduser("~")
    return ["/tmp", f"{home}/.cache", f"{home}/Documents/play/stocks/.claude/worktrees"]


def parse_args(argv: list[str] | None) -> argparse.Namespace:
    p = argparse.ArgumentParser(description="Reclaim idle scratch cargo target dirs.")
    p.add_argument("--apply", action="store_true", help="actually delete (default: dry run)")
    p.add_argument("--budget", type=int, metavar="GB", default=int(os.environ.get("BUDGET_GB", "60")),
                   help="cap total scratch build bytes")
    p.add_argument("--root", action="append", metavar="DIR", help="replace the default roots; repeatable")
    p.add_argument("--tier", type=int, choices=(0, 1, 2), help="override disk pressure: 0 idle>14d, 1 >7d, 2 >2d")
    a = p.parse_args(argv)
    a.roots = a.root or default_roots()
    a.min_idle_h = int(os.environ.get("MIN_IDLE_H", "6"))  # floor under budget pressure, not a policy knob
    a.maxdepth = int(os.environ.get("MAXDEPTH", "8"))  # /tmp/claude-*/<slug>/<uuid>/scratchpad/<x>/target
    a.live_ttl = float(os.environ.get("LIVE_TTL", "30"))
    return a


def make_logger() -> Callable[[str], None]:
    # Under a timer stderr already reaches the journal; syslog is for runs whose
    # stderr goes to a file or nowhere. journalctl -t cargo-target-reclaim.
    to_syslog = not sys.stderr.isatty() and os.environ.get("NO_SYSLOG") != "1"
    if to_syslog:
        syslog.openlog("cargo-target-reclaim")

    def log(msg: str) -> None:
        print(msg, file=sys.stderr, flush=True)
        if to_syslog:
            syslog.syslog(msg)

    return log


def human(n: int) -> str:
    """numfmt --to=iec --suffix=B: one decimal under 10, integers above, rounded up."""
    i = 0
    while i < len(UNITS) - 1 and n >= 1024 ** (i + 1):
        i += 1
    if i == 0:
        return f"{n}B"
    unit = 1024 ** i
    tenths = -(-n * 10 // unit)
    if tenths < 100:
        return f"{tenths // 10}.{tenths % 10}{UNITS[i]}"
    whole = -(-n // unit)
    if whole >= 1024:
        return f"1.0{UNITS[i + 1]}"
    return f"{whole}{UNITS[i]}"


def disk_tier(path: str, force: int | None) -> tuple[int, int]:
    st = os.statvfs(path)
    free_pct = st.f_bavail * 100 // st.f_blocks if st.f_blocks else 0
    if force is not None:
        return free_pct, force
    return free_pct, 2 if free_pct < 10 else 1 if free_pct < 25 else 0


def _subdirs(d: str) -> Iterator[os.DirEntry]:
    try:
        with os.scandir(d) as it:
            for e in it:
                if e.is_dir(follow_symlinks=False):
                    yield e
    except OSError:
        return


def _tag_dirs(root: str, maxdepth: int) -> Iterator[str]:
    """Dirs under root holding a CACHEDIR.TAG. Depth counts and the device
    rule follow find -xdev -maxdepth, which MAXDEPTH and the tests assume."""
    try:
        dev = os.lstat(root).st_dev
    except OSError:
        return
    stack = [(root, 0)]
    while stack:
        d, depth = stack.pop()
        try:
            with os.scandir(d) as it:
                entries = list(it)
        except OSError:
            continue  # unreadable dir: skip it, not the whole scan
        for e in entries:
            if e.name == "CACHEDIR.TAG":
                yield d
            elif e.is_dir(follow_symlinks=False) and e.name not in PRUNE and depth + 1 < maxdepth:
                try:
                    if e.stat(follow_symlinks=False).st_dev == dev:
                        stack.append((e.path, depth + 1))
                except OSError:
                    pass


def is_cargo_target(d: str) -> bool:
    """CACHEDIR.TAG alone is not proof (restic, borg): a .fingerprint must sit at
    <profile>/ or <triple>/<profile>/."""
    for lvl1 in _subdirs(d):
        for lvl2 in _subdirs(lvl1.path):
            if lvl2.name == ".fingerprint":
                return True
            if lvl2.name in PRUNE:
                continue
            if any(lvl3.name == ".fingerprint" for lvl3 in _subdirs(lvl2.path)):
                return True
    return False


def fold_nested(paths: Iterable[str]) -> list[str]:
    """Keep only outermost dirs: a cross-compile triple dir carries its own
    CACHEDIR.TAG and would otherwise be counted twice."""
    kept: list[str] = []
    for p in sorted(set(paths)):
        if not any(p == k or p.startswith(k + "/") for k in kept):
            kept.append(p)
    return kept


def discover(roots: Iterable[str], maxdepth: int) -> list[str]:
    found = [d for root in roots if os.path.isdir(root)
             for d in _tag_dirs(root, maxdepth) if is_cargo_target(d)]
    return fold_nested(found)


def _newest_fingerprint_mtime(d: str) -> float | None:
    """Newest mtime inside any .fingerprint dir, to depth 5. Cargo rewrites a
    fingerprint for every unit it compiles or freshness-checks, so this moves
    whenever the dir is used and nothing else in the tree does."""
    newest = None
    stack = [(d, 0, False)]
    while stack:
        path, depth, inside = stack.pop()
        try:
            with os.scandir(path) as it:
                entries = list(it)
        except OSError:
            continue
        for e in entries:
            is_dir = e.is_dir(follow_symlinks=False)
            if inside:
                try:
                    m = e.stat(follow_symlinks=False).st_mtime
                except OSError:
                    continue
                newest = m if newest is None or m > newest else newest
                if is_dir and depth + 1 < 5:
                    stack.append((e.path, depth + 1, True))
            elif is_dir and e.name == ".fingerprint":
                stack.append((e.path, depth + 1, True))
            elif is_dir and e.name not in PRUNE and depth + 1 < 3:
                stack.append((e.path, depth + 1, False))
    return newest


def last_build_age_h(d: str, now: float | None = None) -> int:
    now = time.time() if now is None else now
    newest = _newest_fingerprint_mtime(d)
    if newest is None:
        try:
            newest = os.lstat(d).st_mtime
        except OSError:
            return 0  # vanished since inventory; the rename will fail harmlessly
    return int((now - newest) / 3600)


def dir_bytes(d: str) -> int:
    """du -sB1: allocated blocks, hardlinks counted once, unreadable parts skipped."""
    try:
        total = os.lstat(d).st_blocks * 512
    except OSError:
        return 0
    seen: set[tuple[int, int]] = set()
    stack = [d]
    while stack:
        try:
            with os.scandir(stack.pop()) as it:
                entries = list(it)
        except OSError:
            continue
        for e in entries:
            try:
                st = e.stat(follow_symlinks=False)
            except OSError:
                continue
            if st.st_nlink > 1 and not stat.S_ISDIR(st.st_mode):
                key = (st.st_dev, st.st_ino)
                if key in seen:
                    continue
                seen.add(key)
            total += st.st_blocks * 512
            if stat.S_ISDIR(st.st_mode):
                stack.append(e.path)
    return total


def scan_proc() -> Iterator[str]:
    """exe catches a binary running out of target/debug after cargo dropped the
    lock (cargo run releases it, cargo test keeps it); cwd catches a shell in
    the tree; fd catches rustc mid-write. Unreadable links are the norm."""
    for pid in os.listdir("/proc"):
        if not pid.isdigit():
            continue
        base = f"/proc/{pid}"
        for link in ("exe", "cwd"):
            try:
                yield os.readlink(f"{base}/{link}")
            except OSError:
                pass
        try:
            fds = os.listdir(f"{base}/fd")
        except OSError:
            continue
        for fd in fds:
            try:
                yield os.readlink(f"{base}/fd/{fd}")
            except OSError:
                pass


class LiveTable:
    """Paths held open by any process, cached for ttl seconds: a scan per
    candidate would re-read every process dozens of times, one scan for the
    whole run would be minutes stale by the first delete."""

    def __init__(self, ttl: float, clock: Callable[[], float] = time.monotonic,
                 scan: Callable[[], Iterable[str]] = scan_proc):
        self.ttl, self.clock, self.scan = ttl, clock, scan
        self.at: float | None = None
        self.paths: list[str] = []

    def refresh(self) -> None:
        now = self.clock()
        if self.at is not None and now - self.at < self.ttl:
            return
        self.paths = sorted({p for p in self.scan() if p.startswith("/")})
        self.at = now

    def holder(self, d: str) -> str | None:
        self.refresh()
        i = bisect.bisect_left(self.paths, d)
        if i < len(self.paths) and self.paths[i] == d:
            return d
        prefix = d + "/"
        i = bisect.bisect_left(self.paths, prefix)
        if i < len(self.paths) and self.paths[i].startswith(prefix):
            return self.paths[i]
        return None


def cargo_locks(d: str) -> Iterator[str]:
    """<profile>/.cargo-lock and <triple>/<profile>/.cargo-lock."""
    stack = [(d, 0)]
    while stack:
        path, depth = stack.pop()
        try:
            with os.scandir(path) as it:
                entries = list(it)
        except OSError:
            continue
        for e in entries:
            if e.name == ".cargo-lock":
                yield e.path
            elif e.is_dir(follow_symlinks=False) and e.name not in PRUNE and depth + 1 < 3:
                stack.append((e.path, depth + 1))


def lock_held(path: str) -> bool:
    """Only reachable for a build whose fds we cannot see, such as another
    user's. A lock we cannot even open counts as held."""
    try:
        fd = os.open(path, os.O_RDONLY)
    except OSError:
        return True
    try:
        fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except BlockingIOError:
        return True
    finally:
        os.close(fd)
    return False


def in_use(d: str, live: LiveTable, log: Callable[[str], None]) -> bool:
    hit = live.holder(d)
    if hit:
        log(f"  in use: a process holds {hit}")
        return True
    for lock in cargo_locks(d):
        if lock_held(lock):
            log(f"  in use: {lock} is held")
            return True
    return False


@dataclass(frozen=True)
class Run:
    apply: bool
    live: LiveTable
    log: Callable[[str], None]


def reclaim(d: str, nbytes: int, apply: bool, log: Callable[[str], None]) -> bool:
    """Rename first: rm -rf takes minutes, and a cargo starting mid-delete would
    build into a tree being torn down. After the rename it creates a fresh one."""
    if not apply:
        log(f"  WOULD reclaim {human(nbytes)}")
        return True
    tmp = f"{d}.reclaim.{os.getpid()}"
    try:
        os.rename(d, tmp)
    except OSError:
        log("  rename failed, skipping")
        return False
    if subprocess.run(["rm", "-rf", "--", tmp], check=False).returncode:
        log(f"  partial: {tmp} left behind")  # still carries CACHEDIR.TAG; next run retries
        return False
    log(f"  reclaimed {human(nbytes)}")
    return True


def consider(d: str, nbytes: int, need_h: int, why: str, run: Run) -> bool:
    """Inventory readings are minutes old by the time they are acted on, long
    enough for an agent to come back and build. Read both again here."""
    idle = last_build_age_h(d)
    if idle < need_h:
        run.log(f"keep touched {idle}h ago  {d}")
        return False
    run.log(f"{why} {idle}h idle  {d}")
    if in_use(d, run.live, run.log):
        return False
    return reclaim(d, nbytes, run.apply, run.log)


def main(argv: list[str] | None = None, log: Callable[[str], None] | None = None) -> int:
    a = parse_args(argv)
    log = log or make_logger()
    free_pct, tier = disk_tier("/tmp", a.tier)
    idle_days = TIER_IDLE_DAYS[tier]
    need_h = idle_days * 24
    budget = a.budget * 1024 ** 3
    log(f"disk {free_pct}% free -> tier {tier} (age: idle >{idle_days}d, budget: {a.budget}G)")

    inv = sorted(((last_build_age_h(d), dir_bytes(d), d) for d in discover(a.roots, a.maxdepth)), reverse=True)
    total = sum(b for _, b, _ in inv)
    log(f"found {len(inv)} scratch build dirs, {human(total)}")

    run = Run(apply=a.apply, live=LiveTable(a.live_ttl), log=log)
    taken: set[str] = set()
    freed = 0
    for idle, nbytes, d in inv:  # oldest first, so the first young one ends the pass
        if idle < need_h:
            break
        if consider(d, nbytes, need_h, "age ", run):
            taken.add(d)
            freed += nbytes

    if total - freed > budget:
        log(f"still {human(total - freed)} over a {human(budget)} budget")
        for idle, nbytes, d in inv:
            if total - freed <= budget:
                break
            if d in taken or idle < a.min_idle_h:
                continue
            if consider(d, nbytes, a.min_idle_h, "over", run):
                taken.add(d)
                freed += nbytes

    log(f"total: {human(freed)}" + ("" if a.apply else " (dry run - re-run with --apply)"))
    return 0


if __name__ == "__main__":
    sys.exit(main())
