{ lib }:
let
  # The owner's rule for Telegram: Hermes reads and downloads, and never runs
  # what it downloaded. Downloads are created without execute bits and owned
  # by telegram-reader, so running one takes an interpreter. These floors deny
  # the common ways to do that while ls, mv, cp, 7zz and sha256sum still pass.
  # Files hand-downloaded in the Telegram client do carry execute bits, and
  # organized files move out of the inbox, so the floors cover both trees:
  # /mnt/data/Downloads/Telegram is the inbox and /mnt/data/harmony/telegram
  # holds the organized files. Hermes lowercases the command and the glob
  # before matching, so "/telegram/" covers both spellings. Matching on that
  # word rather than the full paths catches ./, // and .. spellings too, and
  # relies on Hermes matching each command word with its basename folded.
  # A file moved or extracted outside both trees, the terminal workdir
  # argument, and globbed or variable paths all escape them. The smart policy
  # covers those in chat sessions. Cron and -q runs have no such second layer.
  telegramRunners = [
    "sh"
    "bash"
    "dash"
    "zsh"
    "ksh"
    "ash"
    "fish"
    "csh"
    "tcsh"
    "busybox"
    "python*"
    "uv"
    "pip*"
    "node*"
    "npm"
    "npx"
    "deno"
    "bun"
    "perl*"
    "ruby*"
    "php*"
    "lua*"
    "java"
    "awk"
    "gawk"
    "mawk"
    "wine*"
    "source"
    "."
    "eval"
    "xargs"
    "ld-linux*"
    "ld.so*"
    "make"
    "dpkg"
    "apt*"
  ];
  # Interpreters that run a script fed on stdin or handed over by find -exec.
  # awk is left out: piping a listing into awk processes text, and awk -f on
  # a download is caught above.
  telegramPipeRunners = [
    "sh"
    "bash"
    "dash"
    "zsh"
    "ksh"
    "ash"
    "fish"
    "busybox"
    "python*"
    "node*"
    "deno"
    "bun"
    "perl*"
    "ruby*"
    "php*"
    "lua*"
  ];
  # A runner such as "python*" already matches its versions. A plain name must
  # end the command or be followed by something that cannot continue a command
  # name, such as a space, ";" or "|", so "sh" does not catch sha256sum.
  ends = runner: if lib.hasSuffix "*" runner then [ runner ] else [ runner "${runner}[!a-z0-9._-]*" ];
in
[
  "/mnt*/telegram/*"
  "cd */telegram*"
  "pushd */telegram*"
]
++ map (runner: "${runner} */telegram/*") telegramRunners
# The pipe and -exec globs see the whole command, where the interpreter may
# follow "|" with no space or come as /bin/bash or env bash. [ /] stands for
# the space or slash before its name. A glob cannot tell an argument from the
# command after "|", so a read such as "ls .../telegram/ | grep bash" is
# refused too; such a command has to avoid naming an interpreter.
++ lib.concatMap (runner: map (tail: "*/telegram/*|${tail}") (ends runner)) telegramPipeRunners
++ lib.concatMap (runner: map (tail: "*/telegram/*|*[ /]${tail}") (ends runner)) telegramPipeRunners
++ lib.concatMap (runner: map (tail: "find */telegram*-exec*[ /]${tail}") (ends runner)) telegramPipeRunners
