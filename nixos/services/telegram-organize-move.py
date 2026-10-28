"""Move files from the Telegram inbox into the organized tree, never replacing anything.

Usage: telegram-organize-move <plan.tsv> <log.tsv>
       telegram-organize-move --undo <log.tsv> <undo-log.tsv>

Each plan line is "old<TAB>new". Hermes's deny floors refuse interpreters that
name a Telegram path, so this fixed command is how Hermes organizes downloads.
It renames with RENAME_NOREPLACE and appends "new<TAB>old" to the log after
each move, so a round can be undone with --undo, which replays a log in
reverse. It stops at the first error.

Paths are checked once, with symlinks resolved, and then renamed by path, so a
parent directory swapped for a symlink in between is not caught. The command
guards against mistakes in a plan. It is not a security boundary: Hermes can
already move files under /mnt/data with mv.
"""

import ctypes
import errno
import fcntl
import os
import stat
import sys

INBOX = "/mnt/data/Downloads/Telegram/"
ORGANIZED = "/mnt/data/harmony/telegram/"
USAGE = (
    "usage: telegram-organize-move <plan.tsv> <log.tsv>\n"
    "       telegram-organize-move --undo <log.tsv> <undo-log.tsv>"
)
AT_FDCWD = -100
RENAME_NOREPLACE = 1

libc = ctypes.CDLL(None, use_errno=True)


def inside(path, roots):
    real = os.path.realpath(path)
    return any(real.startswith(root) for root in roots)


def rename_noreplace(old, new):
    if libc.renameat2(AT_FDCWD, os.fsencode(old), AT_FDCWD, os.fsencode(new), RENAME_NOREPLACE) != 0:
        err = ctypes.get_errno()
        raise OSError(err, os.strerror(err), new)


def open_log(path):
    """Open and lock the log for appending and return its descriptor. It must be a plain,
    singly linked file in the organized tree, so appending can never write into
    a media file. Lines go straight to the descriptor; a buffered file object
    would retry a failed write when it is closed."""
    if not inside(path, [ORGANIZED]) or not os.path.basename(path).startswith(".organize-"):
        sys.exit(f"log must be {ORGANIZED}.organize-<name>.tsv")
    try:
        fd = os.open(path, os.O_WRONLY | os.O_APPEND | os.O_CREAT | os.O_NOFOLLOW | os.O_CLOEXEC, 0o664)
    except OSError as e:
        sys.exit(f"cannot open log {path}: {e.strerror}")
    info = os.fstat(fd)
    if not stat.S_ISREG(info.st_mode) or info.st_nlink != 1:
        os.close(fd)
        sys.exit(f"log must be a regular file with one link: {path}")
    # Failure recovery truncates the log to its earlier length, which would drop
    # lines another run appended in between, so one run holds a log at a time.
    try:
        fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except BlockingIOError:
        os.close(fd)
        sys.exit(f"log is in use by another run: {path}")
    return fd


def read_pairs(path):
    pairs = []
    with open(path, encoding="utf-8") as lines:
        for number, line in enumerate(lines, 1):
            if not line.strip():
                continue
            fields = line.rstrip("\n").split("\t")
            if len(fields) != 2 or not all(fields):
                sys.exit(f"{path} line {number}: expected two tab-separated paths")
            pairs.append((number, fields[0], fields[1]))
    return pairs


def check(src, dst, src_roots, dst_roots, log_real):
    if not inside(src, src_roots):
        return "source is outside the allowed trees"
    if not inside(dst, dst_roots):
        return "target is outside the allowed trees"
    if os.path.islink(src):
        return "source is a symlink"
    src_real = os.path.realpath(src)
    if log_real == src_real or log_real.startswith(src_real + "/"):
        return "source is the log or contains it"
    if os.path.isfile(src):
        return None
    # Directories may only be renamed inside the organized tree.
    if os.path.isdir(src) and inside(src, [ORGANIZED]) and inside(dst, [ORGANIZED]):
        return None
    return "source is not a regular file"


def move_all(pairs, log, src_roots, dst_roots):
    log_real = os.path.realpath(log)
    moved = 0
    out = open_log(log)
    try:
        for number, src, dst in pairs:
            problem = check(src, dst, src_roots, dst_roots, log_real)
            if problem:
                sys.exit(f"line {number}: {problem}: {src} -> {dst}; {moved} moved before it")
            try:
                os.makedirs(os.path.dirname(dst), exist_ok=True)
                rename_noreplace(src, dst)
            except OSError as e:
                sys.exit(f"line {number}: {e.strerror}: {dst}; {moved} moved before it")
            logged = os.fstat(out).st_size
            try:
                line = f"{dst}\t{src}\n".encode()
                if os.write(out, line) != len(line):
                    raise OSError(errno.EIO, "short write to the log")
                os.fsync(out)
            except OSError as e:
                # An unlogged move could not be undone, so put the file back and
                # drop any partial line, which would stop a later --undo.
                try:
                    rename_noreplace(dst, src)
                except OSError:
                    sys.exit(f"line {number}: log write failed ({e.strerror}) and moving back failed; "
                             f"{src} is now at {dst}; {moved} moved before it")
                try:
                    os.ftruncate(out, logged)
                except OSError:
                    sys.exit(f"line {number}: log write failed ({e.strerror}); moved back, but the log keeps "
                             f"a line for it past byte {logged}; {moved} moved before it")
                sys.exit(f"line {number}: log write failed ({e.strerror}); moved back; {moved} moved before it")
            moved += 1
    finally:
        os.close(out)
    print(f"moved {moved}")


def main():
    args = sys.argv[1:]
    # Directories inherit setgid and the default ACL from their parent.
    os.umask(0o002)
    if len(args) == 3 and args[0] == "--undo":
        undone, log = args[1], args[2]
        if os.path.realpath(undone) == os.path.realpath(log):
            sys.exit("the undo log must differ from the log being undone")
        # A log line is "new<TAB>old"; undoing moves new back to old, last move first.
        pairs = [(number, new, old) for number, new, old in reversed(read_pairs(undone))]
        move_all(pairs, log, [ORGANIZED], [INBOX, ORGANIZED])
    elif len(args) == 2 and not args[0].startswith("--"):
        move_all(read_pairs(args[0]), args[1], [INBOX, ORGANIZED], [ORGANIZED])
    else:
        sys.exit(USAGE)


if __name__ == "__main__":
    main()
