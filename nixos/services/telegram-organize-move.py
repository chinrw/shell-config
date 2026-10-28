"""Move files from the Telegram inbox into the organized tree, never replacing anything.

Usage: telegram-organize-move <plan.tsv> <log.tsv>

Each plan line is "old<TAB>new". Hermes's deny floors refuse interpreters that
name a Telegram path, so this fixed command is how Hermes organizes downloads.
It renames with RENAME_NOREPLACE and appends "new<TAB>old" to the log after
each move, so a round can be undone line by line. It stops at the first error.
"""

import ctypes
import os
import sys

INBOX = "/mnt/data/Downloads/Telegram/"
ORGANIZED = "/mnt/data/harmony/telegram/"
USAGE = "usage: telegram-organize-move <plan.tsv> <log.tsv>"
AT_FDCWD = -100
RENAME_NOREPLACE = 1

libc = ctypes.CDLL(None, use_errno=True)


def inside(path, root):
    return os.path.realpath(path).startswith(root)


def check(old, new):
    if not (inside(old, INBOX) or inside(old, ORGANIZED)):
        return "source is outside the inbox and the organized tree"
    if not inside(new, ORGANIZED):
        return "target is outside the organized tree"
    if os.path.islink(old):
        return "source is a symlink"
    if not os.path.isfile(old) and not (os.path.isdir(old) and inside(old, ORGANIZED)):
        # Directories may only be renamed inside the organized tree.
        return "source is not a regular file"
    return None


def move(old, new):
    os.makedirs(os.path.dirname(new), exist_ok=True)
    if libc.renameat2(AT_FDCWD, os.fsencode(old), AT_FDCWD, os.fsencode(new), RENAME_NOREPLACE) != 0:
        err = ctypes.get_errno()
        raise OSError(err, os.strerror(err), new)


def main():
    if len(sys.argv) != 3:
        sys.exit(USAGE)
    plan, log = sys.argv[1], sys.argv[2]
    if not inside(log, ORGANIZED) or not os.path.basename(log).startswith(".organize-"):
        sys.exit(f"log must be {ORGANIZED}.organize-<name>.tsv")
    # Directories inherit setgid and the default ACL from their parent.
    os.umask(0o002)
    moved = 0
    with open(plan, encoding="utf-8") as lines, open(log, "a", encoding="utf-8") as out:
        for number, line in enumerate(lines, 1):
            if not line.strip():
                continue
            old, new = line.rstrip("\n").split("\t")
            problem = check(old, new)
            if problem:
                sys.exit(f"line {number}: {problem}: {old} -> {new}")
            try:
                move(old, new)
            except OSError as e:
                sys.exit(f"line {number}: {e.strerror}: {new}; {moved} moved before it")
            out.write(f"{new}\t{old}\n")
            out.flush()
            moved += 1
    print(f"moved {moved}")


if __name__ == "__main__":
    main()
